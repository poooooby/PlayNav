-- Super Training's UI drawn by the engine: each id the screens ask Assets for (frames,
-- windows, buttons, labels, plates, moods, effects, the shutters' edges, the bags) is drawn
-- here once into a canvas of the texture's own size (in layout units) at K times the density,
-- read back into an Image, and handed out in its place. The screens keep their layout and
-- animation code: only where the pixels come from changes. Sprites Wooble supplies later go
-- in assets/ and take the same ids.

return function(mod, deps)
  local U = { K = 4, images = {}, made = 0 }
  local Rules, STAT_RGB = deps.Rules, deps.statRgb or {}

  -- ------- palette (sampled from the game's own screens)
  local function c255(r, g, b, a) return { r / 255, g / 255, b / 255, (a or 255) / 255 } end
  local P = {
    ink = c255(20, 22, 26), dark = c255(34, 34, 38), plate = c255(51, 51, 55), steel = c255(119, 119, 124),
    steelHi = c255(168, 168, 174), rim = c255(80, 82, 88), teal = c255(17, 204, 170), tealHi = c255(80, 236, 210),
    tealLo = c255(8, 150, 128), tealDeep = c255(6, 104, 96), wire = c255(170, 221, 255, 210),
    lime = c255(190, 245, 40), limeHi = c255(236, 255, 150), limeLo = c255(70, 168, 20), silver = c255(214, 216, 222),
    blue = c255(30, 96, 200), blueHi = c255(140, 190, 255), white = c255(255, 255, 255), black = c255(0, 0, 0),
    gold = c255(250, 210, 60), orange = c255(250, 140, 30), red = c255(220, 50, 50),
  }
  U.PALETTE = P
  local function col(G, c, a) G.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end

  -- ------- shared shapes

  local function circle(G, mode, x, y, r) G.circle(mode, x, y, r, math.max(24, math.floor(r * 4))) end

  -- a vertical gradient over a rect (two colours), as a mesh
  local function vgrad(G, x, y, w, h, top, bottom)
    local m = G.newMesh({
      { x, y, 0, 0, top[1], top[2], top[3], top[4] or 1 }, { x + w, y, 0, 0, top[1], top[2], top[3], top[4] or 1 },
      { x + w, y + h, 0, 0, bottom[1], bottom[2], bottom[3], bottom[4] or 1 },
      { x, y + h, 0, 0, bottom[1], bottom[2], bottom[3], bottom[4] or 1 },
    }, "fan", "static")
    G.setColor(1, 1, 1, 1)
    G.draw(m)
  end

  -- a disc lit from the top left: outer to inner colour in rings
  local function shadedDisc(G, x, y, r, outer, inner)
    local n = 24
    for i = 0, n - 1 do
      local t = i / (n - 1)
      local rr = r * (1 - t * 0.85)
      G.setColor(outer[1] + (inner[1] - outer[1]) * t, outer[2] + (inner[2] - outer[2]) * t,
        outer[3] + (inner[3] - outer[3]) * t, 1)
      circle(G, "fill", x - r * 0.18 * t, y - r * 0.22 * t, rr)
    end
  end

  -- thick polyline with round joints
  local function stroke(G, w, ...)
    G.setLineWidth(w)
    G.setLineJoin("bevel")
    G.line(...)
    local pts = { ... }
    for i = 1, #pts, 2 do circle(G, "fill", pts[i], pts[i + 1], w / 2) end
  end

  -- text with an outline, centred in a box (font made at the canvas's density)
  local fonts = {}
  local function font(size)
    local f = fonts[size]
    if not f then
      local ok, made = pcall(love.graphics.newFont, size, "normal", U.K)
      f = ok and made or love.graphics.getFont()
      fonts[size] = f
    end
    return f
  end
  local function outlined(G, text, cx, cy, size, fill, outline, ow, sx)
    local f = font(size)
    G.setFont(f)
    local tw, th = f:getWidth(text), f:getHeight()
    local k = math.min(1, (sx or 1e9) / math.max(1, tw))
    local x, y = cx - tw * k / 2, cy - th / 2
    col(G, outline)
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then G.print(text, x + dx * ow, y + dy * ow, 0, k, 1) end
      end
    end
    col(G, fill)
    G.print(text, x, y, 0, k, 1)
  end

  -- ------- the finish: rounded outlines, light along the edges, glow, fine texture

  -- a closed outline with each corner rounded (r units, at most under half of either edge);
  -- the corners listed in keep (by number) stay sharp: those on a mirror seam or a screen edge
  local function roundPts(pts, r, keep)
    local out, n = {}, #pts / 2
    local seg = 5
    for i = 1, n do
      local pi_, ni = ((i - 2) % n) * 2, (i % n) * 2
      local x, y = pts[(i - 1) * 2 + 1], pts[(i - 1) * 2 + 2]
      local px, py, nx, ny = pts[pi_ + 1], pts[pi_ + 2], pts[ni + 1], pts[ni + 2]
      local d1 = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
      local d2 = math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)
      if d1 < 1e-6 or d2 < 1e-6 or (keep and keep[i]) then
        out[#out + 1] = x; out[#out + 1] = y
      else
        local rr = math.min(r, d1 * 0.45, d2 * 0.45)
        local ax, ay = x + (px - x) * rr / d1, y + (py - y) * rr / d1
        local bx, by = x + (nx - x) * rr / d2, y + (ny - y) * rr / d2
        for s = 0, seg do
          local t = s / seg
          local u = 1 - t
          out[#out + 1] = u * u * ax + 2 * u * t * x + t * t * bx
          out[#out + 1] = u * u * ay + 2 * u * t * y + t * t * by
        end
      end
    end
    return out
  end

  -- a concave outline filled (triangulated), or used as a stencil for what fn draws
  local function fillShape(G, pts)
    local ok, tris = pcall(love.math.triangulate, pts)
    if not ok then G.polygon("fill", pts); return end
    for _, t in ipairs(tris) do G.polygon("fill", t) end
  end
  local function within(G, pts, fn)
    G.stencil(function() fillShape(G, pts) end, "replace", 1)
    G.setStencilTest("greater", 0)
    fn()
    G.setStencilTest()
  end
  local function gradShape(G, pts, x, y, w, h, top, bottom)
    within(G, pts, function() vgrad(G, x, y, w, h, top, bottom) end)
  end
  local function closed(pts)
    local out = {}
    for i = 1, #pts do out[i] = pts[i] end
    out[#out + 1] = pts[1]; out[#out + 1] = pts[2]
    return out
  end

  -- a line that glows: wide faint passes under it, a pale core along it
  local GLOW_PASSES = { { 5.5, 0.05 }, { 3.4, 0.1 }, { 2, 0.22 } }
  local function neon(G, w, c, a, pts, core)
    a = a or 1
    G.setLineJoin("bevel")
    for _, p in ipairs(GLOW_PASSES) do
      G.setLineWidth(w * p[1]); col(G, c, a * p[2]); G.line(pts)
    end
    G.setLineWidth(w); col(G, c, a); G.line(pts)
    if core ~= false then
      G.setLineWidth(w * 0.4); G.setColor(1, 1, 1, 0.55 * a); G.line(pts)
    end
  end

  -- light along a shape's edge, inside it: a bright rim, brighter at the top
  local function rimLight(G, pts, a, top)
    within(G, pts, function()
      G.setLineJoin("bevel")
      G.setLineWidth(1.6); G.setColor(1, 1, 1, 0.22 * (a or 1)); G.line(closed(pts))
      if top then
        local minY, maxY = math.huge, -math.huge
        for i = 2, #pts, 2 do minY = math.min(minY, pts[i]); maxY = math.max(maxY, pts[i]) end
        vgrad(G, -400, minY, 1200, (maxY - minY) * 0.45, { 1, 1, 1, 0.16 * (a or 1) }, { 1, 1, 1, 0 })
      end
    end)
  end

  -- fine scanlines, a grain, a hex mesh, circuit traces (drawn inside whatever stencil is set)
  local function scan(G, x, y, w, h, a, step)
    step = step or 1.25
    G.setColor(1, 1, 1, a)
    local yy = y
    while yy < y + h do G.rectangle("fill", x, yy, w, 0.35); yy = yy + step end
  end
  local function grain(G, x, y, w, h, a, seed)
    local rng = love.math.newRandomGenerator(seed or 7)
    for _ = 1, math.floor(w * h * 0.5) do
      local v = rng:random() < 0.5 and 0 or 1
      G.setColor(v, v, v, a * rng:random())
      G.rectangle("fill", x + rng:random() * w, y + rng:random() * h, 0.3, 0.3)
    end
  end
  local function hexes(G, x, y, w, h, size, a, c)
    col(G, c or P.white, a)
    G.setLineWidth(0.35)
    local dx, dy = size * 1.5, size * math.sqrt(3)
    local i = 0
    for cx = x - size, x + w + size, dx do
      local off = (i % 2 == 1) and dy / 2 or 0
      for cy = y - dy + off, y + h + dy, dy do
        local pts = {}
        for k = 0, 6 do
          local ang = k * math.pi / 3
          pts[#pts + 1] = cx + math.cos(ang) * size; pts[#pts + 1] = cy + math.sin(ang) * size
        end
        G.line(pts)
      end
      i = i + 1
    end
  end
  local function circuit(G, x, y, w, h, seed, a, c, count)
    local rng = love.math.newRandomGenerator(seed or 3)
    for _ = 1, count or 6 do
      local px, py = x + rng:random() * w, y + rng:random() * h
      local pts = { px, py }
      for _ = 1, 3 do
        local len = 3 + rng:random() * 9
        local dir = rng:random(1, 3)
        local sx = (rng:random() < 0.5) and -1 or 1
        if dir == 1 then px = px + len * sx
        elseif dir == 2 then py = py + len * sx
        else px = px + len * 0.7 * sx; py = py + len * 0.7 end
        pts[#pts + 1] = px; pts[#pts + 1] = py
      end
      neon(G, 0.7, c or P.tealHi, a, pts, false)
      col(G, c or P.tealHi, a)
      circle(G, "fill", px, py, 1.1)
      G.setColor(1, 1, 1, 0.6 * a); circle(G, "fill", px, py, 0.5)
    end
  end

  -- ------- glyphs (drawn black on the lime buttons)

  local function returnGlyph(G, cx, cy, s, c)
    col(G, c)
    local lw = 3.2 * s
    stroke(G, lw, cx + 7 * s, cy + 6 * s, cx - 5 * s, cy + 6 * s, cx - 8 * s, cy + 3 * s, cx - 8 * s, cy - 1 * s,
      cx - 5 * s, cy - 4 * s, cx + 4 * s, cy - 4 * s)
    G.polygon("fill", cx + 3 * s, cy - 10 * s, cx + 11 * s, cy - 4 * s, cx + 3 * s, cy + 2 * s)
  end

  local function bagGlyph(G, cx, cy, s, c)
    col(G, c)
    G.setLineWidth(1.6 * s)
    G.line(cx, cy - 13 * s, cx - 4 * s, cy - 8 * s)
    G.line(cx, cy - 13 * s, cx + 4 * s, cy - 8 * s)
    G.rectangle("fill", cx - 5 * s, cy - 8 * s, 10 * s, 18 * s, 4 * s, 4 * s)
    -- the circling arrows either side
    G.setLineWidth(2 * s)
    G.arc("line", "open", cx, cy + 1 * s, 13 * s, math.rad(200), math.rad(250), 10)
    G.arc("line", "open", cx, cy + 1 * s, 13 * s, math.rad(20), math.rad(70), 10)
    G.polygon("fill", cx - 9 * s, cy - 13 * s, cx - 3 * s, cy - 12 * s, cx - 8 * s, cy - 6 * s)
    G.polygon("fill", cx + 9 * s, cy + 15 * s, cx + 3 * s, cy + 14 * s, cx + 8 * s, cy + 8 * s)
  end

  local function ballGlyph(G, cx, cy, r, c)
    col(G, c)
    G.setLineWidth(r * 0.22)
    circle(G, "line", cx, cy, r)
    local pts = {}
    for i = 0, 4 do
      local a = -math.pi / 2 + i * 2 * math.pi / 5
      pts[#pts + 1] = cx + math.cos(a) * r * 0.42
      pts[#pts + 1] = cy + math.sin(a) * r * 0.42
    end
    G.polygon("fill", pts)
  end

  -- the lime round button: black rim, silver bezel, a lit lime face
  local function limeButton(G, cx, cy, r)
    -- a soft lime glow round it
    for i = 3, 1, -1 do col(G, P.lime, 0.08 * (4 - i)); circle(G, "fill", cx, cy, r + i * 0.9) end
    col(G, P.ink, 0.92)
    circle(G, "fill", cx, cy, r)
    shadedDisc(G, cx, cy, r * 0.92, P.rim, P.silver)
    shadedDisc(G, cx, cy, r * 0.76, P.limeLo, P.limeHi)
    -- a fine ring of light inside the bezel, the gloss along the top
    G.setLineWidth(0.7); G.setColor(1, 1, 1, 0.55); circle(G, "line", cx, cy, r * 0.76)
    G.setColor(0, 0, 0, 0.35); circle(G, "line", cx, cy, r * 0.92)
    for i = 0, 5 do
      G.setColor(1, 1, 1, 0.07)
      G.ellipse("fill", cx - r * 0.1, cy - r * 0.42, r * 0.5 * (1 - i * 0.09), r * 0.22 * (1 - i * 0.12), 32)
    end
  end

  -- ------- the generators: id -> { w, h, draw(G, w, h) } in the texture's own units

  local GEN = {}
  local function gen(id, w, h, draw) GEN[id] = { w = w, h = h, draw = draw } end

  -- the top frame's left half (mirrored for the right): the bolted steel plate at the left,
  -- the dark rim along the teal name band, the band, and the light-blue wire under it
  -- a recessed screw: its hole, a slot, light on its lower rim
  local function screw(G, x, y, r)
    G.setColor(0.08, 0.08, 0.1, 0.9); circle(G, "fill", x, y, r)
    shadedDisc(G, x, y, r * 0.78, c255(70, 72, 80), c255(150, 152, 160))
    G.setColor(0.1, 0.1, 0.12, 0.8); G.setLineWidth(r * 0.3); G.line(x - r * 0.5, y + r * 0.3, x + r * 0.5, y - r * 0.3)
    G.setColor(1, 1, 1, 0.35); G.setLineWidth(0.4)
    G.arc("line", "open", x, y, r * 0.95, math.rad(20), math.rad(160), 12)
  end

  gen("training/home_bg03", 160, 60, function(G)
    -- corners on the screen's top edge and on the mirror seam stay sharp
    local outer = roundPts({ 10, 0, 100, 0, 96, 15, 98, 30, 160, 31, 160, 36, 98, 36, 92, 40, 38, 49, 33, 49, 25, 28, 28, 25 },
      2.5, { [1] = true, [2] = true, [5] = true, [6] = true })
    local rim = roundPts({ 13, 0, 96, 0, 93, 15, 95, 32, 90, 37, 40, 45, 35, 45, 28, 27, 30, 24 }, 2.2, { [1] = true, [2] = true })
    local steel = roundPts({ 20, 0, 82, 0, 92, 30, 87, 37, 40, 41, 37, 40, 33, 25 }, 2.4, { [1] = true, [2] = true })
    -- a soft shadow under the frame
    G.push(); G.translate(0, 1.4)
    G.setColor(0, 0, 0, 0.22); fillShape(G, outer)
    G.pop()
    col(G, P.ink, 0.96); fillShape(G, outer)
    gradShape(G, rim, 0, 0, 160, 46, c255(58, 60, 66), c255(24, 25, 29))
    -- the brushed steel plate with its circuit traces
    gradShape(G, steel, 0, 0, 100, 42, c255(176, 178, 186), c255(96, 98, 106))
    within(G, steel, function()
      scan(G, 0, 0, 100, 42, 0.07, 0.8)
      grain(G, 18, 0, 76, 42, 0.07, 11)
      circuit(G, 36, 4, 46, 30, 5, 0.55, P.tealHi, 5)
    end)
    rimLight(G, steel, 1, true)
    for _, b in ipairs({ { 73, 13 }, { 65, 26 }, { 81, 29 } }) do screw(G, b[1], b[2], 2.4) end
    -- the teal name band: a deep gradient, fine scanlines, a lit top edge and a glowing foot
    local band = { 96, 0, 160, 0, 160, 30.5, 97, 30.5 }
    gradShape(G, band, 96, 0, 64, 31, P.tealHi, P.tealDeep)
    within(G, band, function()
      scan(G, 96, 0, 64, 31, 0.07, 1.1)
      vgrad(G, 96, 0, 64, 4, { 1, 1, 1, 0.28 }, { 1, 1, 1, 0 })
      vgrad(G, 96, 22, 64, 9, { 0.3, 1, 0.9, 0 }, { 0.3, 1, 0.9, 0.35 })
    end)
    col(G, P.ink); fillShape(G, roundPts({ 96, 0, 100, 0, 95, 15, 97, 30, 94, 30, 92, 15 }, 1, { [1] = true, [2] = true }))
    -- light along the frame's lower edge, the light-blue wire under it
    neon(G, 0.55, P.tealHi, 0.6, { 160, 36.2, 98.5, 36.2, 92.2, 40.2, 38, 49.2 }, false)
    neon(G, 0.9, P.wire, 1, { 100, 47, 145, 47, 152, 42, 160, 42 })
    neon(G, 0.9, P.wire, 1, { 152, 55, 160, 55 })
    col(G, P.wire); circle(G, "fill", 100, 47, 1.1)
  end)

  -- the bottom tray's left half: the dark plate, the teal panel behind its diagonal edge
  gen("training/home_bg02", 160, 60, function(G)
    -- corners on the screen's left and bottom edges and on the mirror seam stay sharp
    local SEAM = { [1] = true, [4] = true, [5] = true, [6] = true }
    local outer = roundPts({ 0, 7, 90, 17, 93, 22, 160, 26, 160, 60, 0, 60 }, 2.5, SEAM)
    local plate = roundPts({ 0, 9, 89, 19, 92, 24, 160, 28, 160, 60, 0, 60 }, 2.2, SEAM)
    local frame = roundPts({ 74, 21, 92, 22, 96, 27, 160, 30, 160, 60, 52, 60 }, 2.2, { [4] = true, [5] = true, [6] = true })
    local panel = roundPts({ 77, 25, 160, 33, 160, 60, 57, 60 }, 2, { [2] = true, [3] = true, [4] = true })
    G.push(); G.translate(0, -1.2)
    G.setColor(0, 0, 0, 0.22); fillShape(G, outer)
    G.pop()
    col(G, P.ink, 0.96); fillShape(G, outer)
    gradShape(G, plate, 0, 9, 160, 51, c255(74, 76, 82), c255(36, 37, 41))
    within(G, plate, function()
      scan(G, 0, 9, 160, 51, 0.05, 0.8)
      grain(G, 0, 9, 80, 51, 0.06, 23)
      circuit(G, 6, 30, 50, 26, 9, 0.4, P.tealHi, 4)
    end)
    rimLight(G, plate, 0.8, true)
    -- the teal panel, framed in steel: a hex mesh in it, its top edge lit
    gradShape(G, frame, 50, 21, 110, 39, c255(140, 142, 150), c255(70, 72, 78))
    gradShape(G, panel, 57, 25, 103, 35, P.tealHi, P.tealLo)
    within(G, panel, function()
      hexes(G, 57, 25, 103, 35, 3.2, 0.09)
      scan(G, 57, 25, 103, 35, 0.05, 1.1)
    end)
    neon(G, 0.6, P.tealHi, 0.85, { 78, 25.3, 160, 33.3 })
    col(G, P.tealDeep, 0.9)
    G.setLineWidth(1.2)
    G.line(84, 30, 78, 30, 76, 34)
    G.line(80, 41, 72, 41, 74, 36)
    neon(G, 0.9, P.wire, 1, { 100, 15, 145, 18, 152, 12, 160, 10 })
    col(G, P.wire); circle(G, "fill", 100, 15, 1.1)
  end)

  -- the perspective grid (drawn white; the layout tints and fades it)
  gen("training/home_bg01", 320, 120, function(G)
    -- each line glows faintly; the lines thin out toward the horizon
    local line = {}
    for i = -12, 12 do
      line[1], line[2], line[3], line[4] = 160 + i * 17, 0, 160 + i * 22, 120
      neon(G, 0.8, P.white, 0.85, line, false)
    end
    local y = 2
    local step = 8
    while y < 120 do
      line[1], line[2], line[3], line[4] = 0, y, 320, y
      neon(G, 0.55 + 0.45 * y / 120, P.white, 0.85, line, false)
      y = y + step
      step = step * 1.06
    end
  end)

  -- the + mark the backdrop tiles: rounded, with a soft halo
  gen("training/home_bg_ptn", 32, 32, function(G)
    for i = 4, 1, -1 do
      G.setColor(1, 1, 1, 0.03 * (5 - i))
      local g = i * 0.8
      G.rectangle("fill", 14.8 - g, 9.5 - g, 2.4 + 2 * g, 13 + 2 * g, 1.2 + g, 1.2 + g)
      G.rectangle("fill", 9.5 - g, 14.8 - g, 13 + 2 * g, 2.4 + 2 * g, 1.2 + g, 1.2 + g)
    end
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 14.8, 9.5, 2.4, 13, 1.2, 1.2)
    G.rectangle("fill", 9.5, 14.8, 13, 2.4, 1.2, 1.2)
  end)

  -- the PlayNav strip: brushed steel, a gloss along its top, a glowing stepped edge
  gen("training/home_strip", 160, 30, function(G)
    vgrad(G, 0, 0, 160, 30, c255(226, 228, 234), c255(140, 144, 154))
    scan(G, 0, 0, 160, 30, 0.08, 0.7)
    grain(G, 0, 0, 160, 24, 0.05, 31)
    vgrad(G, 0, 0, 160, 7, { 1, 1, 1, 0.45 }, { 1, 1, 1, 0 })
    G.setBlendMode("replace")
    G.setColor(0, 0, 0, 0)
    G.polygon("fill", 30, 24, 160, 24, 160, 30, 24, 30)
    G.setBlendMode("alpha")
    neon(G, 0.9, c255(170, 221, 255), 1, { 0, 29, 24, 29, 30, 23.5, 160, 23.5 })
  end)

  -- the round buttons
  gen("training/btn_return", 48, 48, function(G)
    limeButton(G, 24, 24, 21.5)
    returnGlyph(G, 24, 25, 1.05, P.ink)
  end)
  gen("training/home_return", 30, 30, function(G)
    for i = 3, 1, -1 do col(G, P.blueHi, 0.09 * (4 - i)); circle(G, "fill", 15, 15, 13.2 + i * 0.5) end
    col(G, P.ink, 0.9); circle(G, "fill", 15, 15, 13.2)
    shadedDisc(G, 15, 15, 12.2, c255(150, 156, 170), P.white)
    shadedDisc(G, 15, 15, 9.8, c255(200, 220, 245), P.white)
    G.setLineWidth(0.5); col(G, P.blueHi, 0.9); circle(G, "line", 15, 15, 9.8)
    returnGlyph(G, 15, 15.5, 0.58, P.blue)
  end)
  gen("training/btn_bags", 48, 48, function(G)
    limeButton(G, 24, 24, 21.5)
    bagGlyph(G, 24, 24, 0.8, P.ink)
  end)
  -- the Regimens button: the bottom-left corner of a lime panel that runs off the screen's
  -- left and bottom edges, its top edge sloping down with a step, its right end round; a black
  -- edge, a silver bezel with a teal stripe along its upper slope, a drop shadow on the right;
  -- on the lime, a ball whose swoosh trails off to a small figure
  local REG = { -6, 0.5, 33, 15.6, 35.2, 17.6, 42, 21, 48, 24, 52, 27, 55, 31, 57.5, 35.5, 59, 41, 59.6, 47,
    59.2, 53, 57.8, 58, 56, 61.5, 54.2, 66, -6, 66 }
  local GLYPH = c255(8, 48, 4)
  local function swoosh(G, x0, y0, x1, y1, x2, y2, w0, w1)
    local left, right = {}, {}
    local n = 24
    for i = 0, n do
      local t = i / n
      local u = 1 - t
      local x, y = u * u * x0 + 2 * u * t * x1 + t * t * x2, u * u * y0 + 2 * u * t * y1 + t * t * y2
      local dx, dy = 2 * u * (x1 - x0) + 2 * t * (x2 - x1), 2 * u * (y1 - y0) + 2 * t * (y2 - y1)
      local d = math.sqrt(dx * dx + dy * dy)
      local w = (w0 + (w1 - w0) * t) / 2
      left[#left + 1] = x - dy / d * w; left[#left + 1] = y + dx / d * w
      right[#right + 1] = x + dy / d * w; right[#right + 1] = y - dx / d * w
    end
    local pts = left
    for i = #right - 1, 1, -2 do pts[#pts + 1] = right[i]; pts[#pts + 1] = right[i + 1] end
    fillShape(G, pts)
  end
  gen("training/btn_regimens", 64, 64, function(G)
    local O = roundPts(REG, 1.4, { [1] = true, [14] = true, [15] = true })
    -- a soft shadow off the right end
    G.push(); G.translate(1.6, 0.6)
    G.setColor(0, 0, 0, 0.32); fillShape(G, O)
    G.pop()
    local edge = closed(O)
    within(G, O, function()
      -- the lime face, brighter toward the foot, with fine lines and a gloss
      vgrad(G, -6, 18, 70, 48, c255(104, 196, 26), c255(206, 255, 84))
      scan(G, -6, 18, 70, 48, 0.06, 1.1)
      vgrad(G, -6, 18, 70, 10, { 1, 1, 1, 0.3 }, { 1, 1, 1, 0 })
      -- the bezel, inward from the edge: a light inner rim, silver, a darker outer band, black
      G.setLineJoin("bevel")
      G.setLineWidth(10.6); G.setColor(0.84, 0.92, 0.72, 1); G.line(edge)
      G.setLineWidth(9.4); G.setColor(0.86, 0.87, 0.88, 1); G.line(edge)
      G.setLineWidth(4.6); G.setColor(0.6, 0.62, 0.62, 1); G.line(edge)
      G.setLineWidth(3.2); G.setColor(0.33, 0.36, 0.36, 1); G.line(edge)
      G.setLineWidth(1.9); G.setColor(0, 0, 0, 1); G.line(edge)
      -- the teal stripe along the upper slope
      neon(G, 1.5, c255(75, 222, 188), 1, { -6, 4.4, 29.6, 18.1 })
    end)
    -- the ball: a dark ring, lime inside, the middle patch and the seams out to the edge
    local bx, by, br = 17.5, 36.5, 8.5
    col(G, GLYPH); circle(G, "fill", bx, by, br)
    col(G, c255(132, 226, 44)); circle(G, "fill", bx, by, br - 1.6)
    col(G, GLYPH)
    local pent = {}
    for i = 0, 4 do
      local a = -math.pi / 2 + i * 2 * math.pi / 5
      pent[#pent + 1] = bx + math.cos(a) * 3.4; pent[#pent + 1] = by + math.sin(a) * 3.4
      G.setLineWidth(1.8); G.line(bx + math.cos(a) * 3.4, by + math.sin(a) * 3.4, bx + math.cos(a) * (br - 1), by + math.sin(a) * (br - 1))
      circle(G, "fill", bx + math.cos(a + math.pi / 5) * (br - 1.2), by + math.sin(a + math.pi / 5) * (br - 1.2), 2.5)
    end
    G.polygon("fill", pent)
    -- its swoosh, from under the ball round to the figure's feet
    swoosh(G, 10.5, 42, 14, 58, 41, 46.6, 6.2, 1.6)
    -- the figure: two ears, a head, a body on a little base
    G.polygon("fill", 41.6, 34.6, 42.4, 30.2, 43.7, 34)
    G.polygon("fill", 44.4, 34, 45.6, 30.2, 46.4, 34.6)
    circle(G, "fill", 44, 36, 2.9)
    G.polygon("fill", 41.4, 38.5, 46.6, 38.5, 47.6, 45.2, 40.4, 45.2)
    G.ellipse("fill", 44.2, 46.2, 5.8, 1.6, 24)
  end)

  -- the message windows' corner (9-sliced: the last column and row stretch, the corner pixel fills)
  -- the windows' fill is see-through (the game's: 80%), its rim a faint light glow
  local GLASS = c255(17, 221, 187, 204)
  local GLOW_RIM = c255(187, 255, 255, 60)
  gen("training/win_bl", 16, 24, function(G)
    col(G, GLOW_RIM); G.rectangle("fill", 0, 0, 40, 60, 7, 7)
    G.setBlendMode("replace")
    col(G, c255(119, 221, 204, 187)); G.rectangle("fill", 1.5, 1.5, 40, 60, 5.5, 5.5)
    col(G, GLASS); G.rectangle("fill", 3, 3, 40, 60, 4.5, 4.5)
    G.setBlendMode("alpha")
    G.setLineWidth(0.5); G.setColor(1, 1, 1, 0.45); G.rectangle("line", 3.25, 3.25, 40, 60, 4.3, 4.3)
  end)
  -- the drawer's corner (mirrored for the other three; its last row and column stretch): a
  -- steel cap along the top, chamfered down to the side at the corner, then the see-through
  -- glass with a bright line down its side and a faint cyan glow outside it
  gen("training/list_win", 32, 32, function(G)
    -- the glow outside the side, fading away from the window
    local glow = function(x0, x1, y0, y1)
      G.setColor(1, 1, 1, 1)
      G.draw(G.newMesh({ { x0, y0, 0, 0, 0.73, 1, 1, 0 }, { x1, y0, 0, 0, 0.73, 1, 1, 0.3 },
        { x1, y1, 0, 0, 0.73, 1, 1, 0.3 }, { x0, y1, 0, 0, 0.73, 1, 1, 0 } }, "fan", "static"))
    end
    glow(0, 11, 12, 24.5)
    glow(0, 14.5, 24.5, 32)
    -- the glass, with its darker band under the cap
    local glass = { 32, 7.5, 32, 32, 14.5, 32, 14.5, 26.5, 10.5, 23, 10.5, 12.5, 15, 7.5 }
    G.setBlendMode("replace")
    within(G, glass, function()
      col(G, c255(17, 214, 184, 204)); G.rectangle("fill", 0, 7, 32, 26)
      vgrad(G, 0, 7.5, 32, 5.5, c255(0, 102, 102, 238), c255(17, 214, 184, 204))
    end)
    G.setBlendMode("alpha")
    -- the bright line down the side
    neon(G, 1.4, c255(153, 255, 238), 1, { 15.2, 7.6, 10.9, 12.5, 10.9, 23, 14.9, 26.6, 14.9, 32 })
    -- the steel cap: a black edge, a lit bevel at the side, a recessed slot along the top
    local cap = roundPts({ 2, 0, 32, 0, 32, 7.5, 15, 7.5, 10.5, 12.5, 6.5, 12, 2, 7 }, 1.2,
      { [1] = true, [2] = true, [3] = true })
    col(G, P.ink); fillShape(G, cap)
    local inner = roundPts({ 3.2, 0, 32, 0, 32, 6.6, 14.6, 6.6, 10.2, 11.3, 7, 10.9, 3.2, 6.5 }, 1,
      { [1] = true, [2] = true, [3] = true })
    gradShape(G, inner, 0, 0, 32, 12, c255(92, 96, 100), c255(62, 66, 70))
    within(G, inner, function()
      scan(G, 0, 0, 32, 12, 0.06, 0.8)
      G.setColor(0.13, 0.13, 0.14, 1); G.rectangle("fill", 10, -1, 22, 3.2, 1, 1)
      G.setColor(1, 1, 1, 0.12); G.rectangle("fill", 10, 2.2, 22, 0.5)
    end)
    G.setLineJoin("bevel"); G.setLineWidth(1.2); G.setColor(0.6, 0.62, 0.64, 1)
    G.line(4.4, 0, 4.4, 6.6, 7.8, 10.2)
    G.setColor(0, 0.13, 0.13, 1); G.setLineWidth(0.7); G.line(32, 7.3, 15.2, 7.3, 10.6, 12.3)
  end)
  gen("training/meter_bar", 180, 30, function(G)
    for i = 3, 1, -1 do col(G, P.lime, 0.06 * (4 - i)); G.rectangle("fill", 1 - i, 5 - i, 178 + 2 * i, 20 + 2 * i, 10 + i, 10 + i) end
    col(G, P.ink, 0.92); G.rectangle("fill", 1, 5, 178, 20, 10, 10)
    G.stencil(function() G.rectangle("fill", 3, 7, 174, 16, 8, 8) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 3, 7, 174, 16, P.limeHi, P.limeLo)
    scan(G, 3, 7, 174, 16, 0.08, 1)
    vgrad(G, 3, 7, 174, 6, { 1, 1, 1, 0.5 }, { 1, 1, 1, 0.05 })
    G.setStencilTest()
    G.setLineWidth(0.6); G.setColor(1, 1, 1, 0.45); G.rectangle("line", 3.3, 7.3, 173.4, 15.4, 7.7, 7.7)
  end)
  gen("training/black_mask", 8, 8, function(G) G.setColor(0, 0, 0, 1); G.rectangle("fill", 0, 0, 8, 8) end)

  -- the Effort-o-Meter's hexagon and its gauge track (the EVs are drawn over it)
  gen("training/home_meter", 150, 150, function(G)
    local cx, cy, r = 63.5, 85.5, 50.5
    local hex, inner = {}, {}
    for i = 0, 5 do
      local a = -math.pi / 2 + i * math.pi / 3
      hex[#hex + 1] = cx + math.cos(a) * r; hex[#hex + 1] = cy + math.sin(a) * r
      inner[#inner + 1] = cx + math.cos(a) * r * 0.5; inner[#inner + 1] = cy + math.sin(a) * r * 0.5
    end
    -- see-through glass, brighter toward the middle, a fine hex mesh in it
    local fan = { { cx, cy, 0, 0, P.tealHi[1], P.tealHi[2], P.tealHi[3], 0.62 } }
    for i = 0, 6 do
      local k = (i % 6) * 2
      fan[#fan + 1] = { hex[k + 1], hex[k + 2], 0, 0, P.tealLo[1], P.tealLo[2], P.tealLo[3], 0.82 }
    end
    G.setColor(1, 1, 1, 1); G.draw(G.newMesh(fan, "fan", "static"))
    within(G, hex, function() hexes(G, cx - r, cy - r, 2 * r, 2 * r, 2.6, 0.1) end)
    col(G, P.tealHi, 0.3); G.polygon("fill", inner)
    local spoke = {}
    for i = 0, 2 do
      local a = -math.pi / 2 + i * math.pi / 3
      spoke[1], spoke[2] = cx + math.cos(a) * r, cy + math.sin(a) * r
      spoke[3], spoke[4] = cx - math.cos(a) * r, cy - math.sin(a) * r
      neon(G, 0.6, P.tealHi, 0.7, spoke, false)
    end
    neon(G, 0.7, P.tealHi, 0.85, closed(inner), false)
    neon(G, 1.3, P.tealHi, 1, closed(hex))
    -- the total's track at the right, wired to the hexagon's corner
    col(G, P.tealDeep, 0.9); G.rectangle("fill", 140, 1, 6, 132, 3, 3)
    within(G, { 140, 1, 146, 1, 146, 133, 140, 133 }, function() scan(G, 140, 1, 6, 132, 0.1, 1.2) end)
    neon(G, 0.7, P.tealHi, 1, closed({ 140, 2, 146, 2, 146, 132, 140, 132 }))
    neon(G, 0.7, P.tealHi, 0.9, { 143, 133, 143, 138, 112, 138, cx + r * 0.87, cy + r * 0.5 })
  end)

  -- the stat labels: the stat's name in outlined block letters
  local LABELS = { hp = "HP", atk = "ATTACK", def = "DEFENSE", spa = "SP. ATK", spd = "SP. DEF", spe = "SPEED" }
  local LABEL_RGB = { hp = c255(196, 236, 60), atk = c255(252, 196, 40), def = c255(252, 150, 40),
    spa = c255(120, 196, 255), spd = c255(96, 156, 246), spe = c255(236, 120, 240) }
  for stat, word in pairs(LABELS) do
    gen("training/label_" .. stat, 64, 20, function(G)
      -- a soft halo in the stat's colour, then the letters in a thin dark outline
      local rgb = LABEL_RGB[stat]
      local halo = { rgb[1], rgb[2], rgb[3], 0.16 }
      outlined(G, word, 32, 10, 11, { 0, 0, 0, 0 }, halo, 2.2, 60)
      outlined(G, word, 32, 10, 11, { 0, 0, 0, 0 }, halo, 1.5, 60)
      outlined(G, word, 32, 10, 11, rgb, { 0.05, 0.07, 0.1, 0.9 }, 0.8, 60)
    end)
  end

  -- the +N's plate: a black ragged burst
  gen("training/point_up_win", 40, 20, function(G)
    local pts = {}
    local n = 22
    for i = 0, n - 1 do
      local a = i / n * 2 * math.pi
      local rr = (i % 2 == 0) and 1 or 0.86
      pts[#pts + 1] = 20 + math.cos(a) * 19.5 * rr
      pts[#pts + 1] = 10 + math.sin(a) * 9.5 * rr
    end
    G.setColor(0, 0, 0, 1)
    G.polygon("fill", pts)
  end)
  gen("training/arrow", 16, 16, function(G)
    col(G, P.ink); G.polygon("fill", 8, 0.5, 15.5, 8.5, 11, 8.5, 11, 15.5, 5, 15.5, 5, 8.5, 0.5, 8.5)
    col(G, P.white); G.polygon("fill", 8, 2.5, 13, 7.5, 10, 7.5, 10, 14.5, 6, 14.5, 6, 7.5, 3, 7.5)
  end)

  -- the training plates: a slanted plate, grey (untrained) or teal with the flexing figure
  -- (Fully Trained) and its stars (Supremely)
  -- the plate leans like a backslash: its top along the screen's edge, its right corner at the
  -- foot cut off; no outline, a thin darker edge, the game's bright stripe every third row,
  -- a darker foot and a faint halo
  local PLATE = { 1.5, 0, 39.5, 0, 48.5, 29.5, 46.5, 34.5, 17.5, 35 }
  local function plateStripes(G, x, y, w, h, a)
    G.setColor(1, 1, 1, a)
    for yy = y + 4, y + h, 6 do G.rectangle("fill", x, yy, w, 1.2) end
    scan(G, x, y, w, h, a * 0.5, 1)
  end
  local function plate(G, top, bottom, edge, halo)
    local pts = roundPts(PLATE, 1.2, { [1] = true, [2] = true })
    if halo then
      G.setLineJoin("bevel")
      for i = 3, 1, -1 do col(G, halo, 0.07 * (4 - i)); G.setLineWidth(i * 1.5); G.line(closed(pts)) end
    end
    gradShape(G, pts, 0, 0, 50, 35, top, bottom)
    within(G, pts, function()
      plateStripes(G, 0, 0, 50, 35, 0.07)
      vgrad(G, 0, 30, 50, 5, { edge[1], edge[2], edge[3], 0 }, { edge[1], edge[2], edge[3], 0.7 })
    end)
    rimLight(G, pts, 0.7, true)
    G.setLineJoin("bevel"); G.setLineWidth(0.8); col(G, edge, 0.85); G.line(closed(pts))
  end
  local function flexer(G, cx, cy, s)
    col(G, P.white)
    circle(G, "fill", cx, cy - 7 * s, 3.4 * s)
    G.rectangle("fill", cx - 4 * s, cy - 3 * s, 8 * s, 9 * s, 2 * s, 2 * s)
    stroke(G, 3 * s, cx - 4 * s, cy - 1 * s, cx - 10 * s, cy - 1 * s, cx - 11 * s, cy - 7 * s)
    stroke(G, 3 * s, cx + 4 * s, cy - 1 * s, cx + 10 * s, cy - 1 * s, cx + 11 * s, cy - 7 * s)
  end
  local function star(G, cx, cy, r)
    local pts = {}
    for i = 0, 9 do
      local a = -math.pi / 2 + i * math.pi / 5
      local rr = (i % 2 == 0) and r or r * 0.45
      pts[#pts + 1] = cx + math.cos(a) * rr; pts[#pts + 1] = cy + math.sin(a) * rr
    end
    G.polygon("fill", pts)
  end
  gen("training/home_perfect_win00", 50, 40, function(G)
    -- untrained: a grey plate split by a stepped seam, two slots on it
    local DARK = c255(66, 66, 76)
    plate(G, c255(134, 134, 138), c255(112, 112, 116), DARK)
    local seam = { 8.5, 16.5, 25, 16.5, 28.5, 21.5, 47.5, 21.5 }
    col(G, DARK, 0.9); G.setLineWidth(1.1); G.line(seam)
    G.setColor(1, 1, 1, 0.25); G.setLineWidth(0.5)
    G.line(9, 17.6, 24.6, 17.6, 28, 22.6, 47.5, 22.6)
    col(G, DARK); G.rectangle("fill", 17, 20, 5, 1.2, 0.5, 0.5); G.rectangle("fill", 33, 17, 5, 1.2, 0.5, 0.5)
  end)
  local TEAL_TOP, TEAL_FOOT, TEAL_EDGE, HALO = c255(24, 214, 186), c255(14, 186, 160), c255(0, 150, 150), c255(136, 255, 255)
  gen("training/home_perfect_win02", 50, 40, function(G)
    plate(G, TEAL_TOP, TEAL_FOOT, TEAL_EDGE, HALO)
    flexer(G, 27, 21, 1.05)
  end)
  gen("training/home_s_perfect_win", 50, 40, function(G)
    plate(G, TEAL_TOP, TEAL_FOOT, TEAL_EDGE, HALO)
    flexer(G, 27, 17, 0.9)
    col(G, P.white)
    for i = 0, 4 do star(G, 17 + i * 6, 29, 2.5) end
  end)
  -- the shot type's plate leans the other way, like a slash, with a thick lip along its foot
  -- and a darker right edge
  gen("training/home_shot_win", 50, 40, function(G)
    local face = roundPts({ 11, 0, 47.5, 0, 34, 30.5, 1, 30.5 }, 1.2, { [1] = true, [2] = true })
    local lip = roundPts({ 1, 30.5, 34, 30.5, 32.5, 35.2, 9, 35.4 }, 1.2, { [1] = true, [2] = true })
    G.setLineJoin("bevel")
    for i = 3, 1, -1 do col(G, HALO, 0.06 * (4 - i)); G.setLineWidth(i * 1.5); G.line(closed(face)) end
    gradShape(G, lip, 0, 30, 50, 6, c255(0, 170, 153), c255(0, 120, 120))
    gradShape(G, face, 0, 0, 50, 31, c255(20, 210, 180), c255(14, 190, 164))
    within(G, face, function()
      plateStripes(G, 0, 0, 50, 31, 0.08)
      col(G, c255(0, 150, 150), 0.9); G.setLineWidth(3); G.line(48.5, -1, 35, 31.5)
    end)
    rimLight(G, face, 0.7, true)
  end)

  -- the shot types: a white ball with the type's patches, and its speed lines
  -- a soccer ball: a light rim, white panels, the type's colour in the middle patch, the seams
  -- and the patches round the edge; sx / sy squash it, rot turns it
  local function soccerBall(G, cx, cy, r, c, sx, sy, rot)
    G.push()
    G.translate(cx, cy); G.rotate(rot or 0); G.scale(sx or 1, sy or 1)
    G.setColor(0.86, 0.87, 0.9, 1); circle(G, "fill", 0, 0, r)
    shadedDisc(G, 0, 0, r - 0.9, c255(200, 202, 212), c255(250, 250, 255))
    G.stencil(function() circle(G, "fill", 0, 0, r - 0.9) end, "replace", 1)
    G.setStencilTest("greater", 0)
    col(G, c)
    local pent, rp = {}, r * 0.3
    G.setLineWidth(math.max(0.6, r * 0.09))
    for i = 0, 4 do
      local a = -math.pi / 2 + i * 2 * math.pi / 5
      pent[#pent + 1] = math.cos(a) * rp; pent[#pent + 1] = math.sin(a) * rp
      local ox, oy = math.cos(a) * r * 0.62, math.sin(a) * r * 0.62
      G.line(math.cos(a) * rp, math.sin(a) * rp, ox, oy)
      G.line(ox, oy, math.cos(a - 0.6) * r, math.sin(a - 0.6) * r)
      G.line(ox, oy, math.cos(a + 0.6) * r, math.sin(a + 0.6) * r)
      local b = a + math.pi / 5
      local q = {}
      for k = 0, 4 do
        local e = b + math.pi + k * 2 * math.pi / 5
        q[#q + 1] = math.cos(b) * r * 1.02 + math.cos(e) * r * 0.3
        q[#q + 1] = math.sin(b) * r * 1.02 + math.sin(e) * r * 0.3
      end
      G.polygon("fill", q)
    end
    G.polygon("fill", pent)
    -- a gloss at the top left
    G.setColor(1, 1, 1, 0.35); G.ellipse("fill", -r * 0.35, -r * 0.45, r * 0.35, r * 0.18, 20)
    G.setStencilTest()
    G.pop()
  end
  local SHOT = { black = c255(64, 64, 68), blue = c255(40, 130, 205), orange = c255(244, 140, 56),
    yellow = c255(226, 190, 20), green = c255(110, 196, 60) }
  gen("training/shot_black", 32, 32, function(G) soccerBall(G, 16, 17.5, 9.8, SHOT.black) end)
  gen("training/shot_orange", 32, 32, function(G) soccerBall(G, 16, 17, 11.8, SHOT.orange) end)
  gen("training/shot_blue", 32, 32, function(G)
    -- flying: squashed along its path, speed lines trailing off to the lower left
    col(G, c255(150, 210, 245), 0.85); G.setLineWidth(0.7)
    G.line(4, 25, 10, 20); G.line(3, 29, 11, 23); G.line(7, 30, 13, 25)
    soccerBall(G, 17.5, 14.5, 9.6, SHOT.blue, 1.12, 0.84, math.rad(-38))
  end)
  gen("training/shot_yellow", 32, 32, function(G)
    -- a string of balls growing toward the upper right
    for _, b in ipairs({ { 4.6, 28.4, 2.3 }, { 9.6, 23, 3.3 }, { 16.2, 16.2, 4.6 }, { 24.4, 8, 6.2 } }) do
      soccerBall(G, b[1], b[2], b[3], SHOT.yellow)
    end
  end)
  gen("training/shot_green", 32, 32, function(G)
    -- a spiky burst behind it at the upper right
    local pts = {}
    for i = 0, 17 do
      local a = math.rad(-150) + i * math.rad(200) / 17
      local rr = (i % 2 == 0) and 13 or 9
      pts[#pts + 1] = 18 + math.cos(a) * rr; pts[#pts + 1] = 15 + math.sin(a) * rr
    end
    pts[#pts + 1] = 18; pts[#pts + 1] = 15
    col(G, c255(220, 250, 200), 0.9); fillShape(G, pts)
    col(G, SHOT.green, 0.8); G.setLineWidth(0.7); G.line(pts)
    soccerBall(G, 15.5, 18.5, 10, SHOT.green)
  end)

  -- the mood bubbles: a teal screen on a stalk with its face
  local function bubble(G)
    col(G, P.steelHi); G.setLineWidth(1.6); G.line(9, 26, 6, 31)
    for i = 2, 1, -1 do col(G, P.tealHi, 0.1 * (3 - i)); G.rectangle("fill", 2 - i, 3 - i, 28 + 2 * i, 23 + 2 * i, 3.5 + i, 3.5 + i) end
    G.stencil(function() G.rectangle("fill", 2, 3, 28, 23, 3.5, 3.5) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 2, 3, 28, 23, P.silver, P.steel)
    G.setStencilTest()
    G.setBlendMode("replace")
    vgrad(G, 4, 5, 24, 19, c255(0, 171, 171, 210), c255(0, 112, 118, 210))
    G.setBlendMode("alpha")
    G.stencil(function() G.rectangle("fill", 4, 5, 24, 19) end, "replace", 1)
    G.setStencilTest("greater", 0)
    scan(G, 4, 5, 24, 19, 0.1, 1)
    vgrad(G, 4, 5, 24, 6, { 1, 1, 1, 0.22 }, { 1, 1, 1, 0 })
    G.setStencilTest()
  end
  local FACE = {
    smile = function(G)
      col(G, P.tealHi); G.rectangle("fill", 10, 9, 3, 5); G.rectangle("fill", 19, 9, 3, 5)
      G.setLineWidth(2.2); G.arc("line", "open", 16, 13, 6, math.rad(20), math.rad(160), 12)
    end,
    silence = function(G)
      col(G, P.tealHi)
      for i = 0, 2 do G.rectangle("fill", 9 + i * 6, 13, 3, 3) end
    end,
    sad = function(G)
      col(G, P.tealHi); G.setLineWidth(2)
      G.line(9, 10, 13, 12); G.line(23, 10, 19, 12)
      G.arc("line", "open", 16, 22, 6, math.rad(200), math.rad(340), 12)
    end,
    surprise = function(G)
      col(G, P.tealHi); G.rectangle("fill", 14.5, 7, 3, 9); G.rectangle("fill", 14.5, 18, 3, 3)
    end,
    perfect = function(G) flexer(G, 16, 15, 0.7) end,
  }
  for name, face in pairs(FACE) do
    gen("training/mood_" .. name, 32, 32, function(G) bubble(G); face(G) end)
  end

  -- the effects: the hit mark, the finishing move's slash, a quarter of its glow
  gen("training/burst", 64, 64, function(G)
    local function burstPoly(r1, r2, n, rot)
      local pts = {}
      for i = 0, n * 2 - 1 do
        local a = rot + i * math.pi / n
        local rr = (i % 2 == 0) and r1 or r2
        pts[#pts + 1] = 32 + math.cos(a) * rr; pts[#pts + 1] = 32 + math.sin(a) * rr
      end
      return pts
    end
    col(G, P.orange); G.polygon("fill", burstPoly(26, 11, 8, 0.2))
    col(G, P.gold); G.polygon("fill", burstPoly(20, 9, 8, 0.2))
    col(G, c255(255, 250, 210)); circle(G, "fill", 32, 32, 8)
    col(G, P.gold)
    for _, d in ipairs({ { 8, 10 }, { 56, 12 }, { 54, 54 }, { 10, 52 }, { 33, 4 }, { 60, 34 } }) do
      G.rectangle("fill", d[1] - 1.5, d[2] - 1.5, 3, 3)
    end
  end)
  gen("training/finish_slash", 64, 64, function(G)
    local outer, inner = {}, {}
    for i = 0, 24 do
      local a = math.rad(110 + i * 140 / 24)
      outer[#outer + 1] = 40 + math.cos(a) * 26; outer[#outer + 1] = 32 + math.sin(a) * 28
      inner[#inner + 1] = 48 + math.cos(a) * 24; inner[#inner + 1] = 32 + math.sin(a) * 25
    end
    local pts = {}
    for i = 1, #outer, 2 do pts[#pts + 1] = outer[i]; pts[#pts + 1] = outer[i + 1] end
    for i = #inner - 1, 1, -2 do pts[#pts + 1] = inner[i]; pts[#pts + 1] = inner[i + 1] end
    local tris = love.math.triangulate(pts)
    col(G, P.orange)
    for _, t in ipairs(tris) do G.polygon("fill", t) end
    G.setColor(1, 0.85, 0.35, 1); G.setLineWidth(2)
    G.line(outer)
  end)
  gen("training/finish_light", 32, 32, function(G)
    -- the bright corner at the lower left, rays out from it
    for i = 12, 1, -1 do
      local r = i * 2.6
      G.setColor(1, 1, 1, 0.09 + (12 - i) * 0.02)
      G.arc("fill", 0, 32, r, -math.pi / 2, 0, 16)
    end
    G.setColor(1, 1, 1, 0.75)
    for _, a in ipairs({ -0.25, -0.75, -1.25 }) do
      G.polygon("fill", 0, 32, math.cos(a) * 32, 32 + math.sin(a) * 32,
        math.cos(a - 0.08) * 32, 32 + math.sin(a - 0.08) * 32)
    end
  end)

  -- the charge ring: a quarter arc about a point off the texture's lower left (the image spins
  -- about its middle, so the arc sweeps round the trainee), a solid yellow band with a soft
  -- inside edge, a thinner see-through band inside it, soft edges; rounded ends
  gen("training/charge", 64, 64, function(G)
    local CX, CY, A0, A1, STEPS = 4.3, 58.4, math.rad(-87), math.rad(-3), 40
    local YEL = c255(255, 224, 84)
    -- per band: the middle radius and the alpha across it (offset from the middle, alpha)
    local BANDS = {
      { 32.7, { { -2.6, 0 }, { -1.8, 0.2 }, { -1.1, 0.47 }, { 1.1, 0.47 }, { 1.9, 0.13 }, { 2.6, 0 } } },
      { 41, { { -4, 0 }, { -3, 0.3 }, { -2.2, 0.62 }, { -1.6, 1 }, { 1.6, 1 }, { 2.3, 0.35 }, { 3.1, 0.12 }, { 4, 0 } } },
    }
    for _, b in ipairs(BANDS) do
      local rc, prof = b[1], b[2]
      local hw = prof[#prof][1]
      local cap = hw / rc
      local lo, hi = A0 - cap, A1 + cap
      local n = STEPS * 3
      -- one strip per pair of profile points, the band narrowing round each end like a cap
      for j = 1, #prof - 1 do
        local o0, al0, o1, al1 = prof[j][1], prof[j][2], prof[j + 1][1], prof[j + 1][2]
        local verts = {}
        for i = 0, n do
          local a = lo + (hi - lo) * i / n
          local over = math.max(A0 - a, a - A1, 0) / cap
          local s = math.sqrt(math.max(0, 1 - over * over))
          local ca, sa = math.cos(a), math.sin(a)
          local r0, r1 = rc + o0 * s, rc + o1 * s
          verts[#verts + 1] = { CX + ca * r0, CY + sa * r0, 0, 0, YEL[1], YEL[2], YEL[3], al0 }
          verts[#verts + 1] = { CX + ca * r1, CY + sa * r1, 0, 0, YEL[1], YEL[2], YEL[3], al1 }
        end
        G.setColor(1, 1, 1, 1)
        G.draw(love.graphics.newMesh(verts, "strip", "static"))
      end
    end
  end)

  -- the shutters: a stepped edge (repeated down the screen) and the glowing seam
  gen("training/ss_black_out", 32, 64, function(G)
    G.setColor(0, 0, 0, 1)
    G.polygon("fill", 16, 0, 32, 0, 32, 64, 16, 64, 16, 52, 8, 44, 8, 20, 16, 12)
  end)
  gen("training/ss_black_out2", 32, 64, function(G)
    G.setColor(0, 0, 0, 1); G.rectangle("fill", 0, 0, 32, 64)
    G.setColor(1, 1, 1, 0.35)
    stroke(G, 5, 18, 0, 18, 14, 12, 22, 12, 42, 18, 50, 18, 64)
    G.setColor(1, 1, 1, 1)
    stroke(G, 1.6, 18, 0, 18, 14, 12, 22, 12, 42, 18, 50, 18, 64)
  end)

  -- ------- the bags: chains, an outlined body in the bag's colour, its pattern

  local EFFECT = {
    strength = { c255(214, 172, 30), "diamonds" }, toughen_up = { c255(26, 118, 220), "squares" },
    swiftness = { c255(140, 70, 180), "triangles" }, big_shot = { c255(40, 140, 70), "dots" },
    double_up = { c255(44, 44, 50), "x2" }, team_flare = { c255(220, 60, 40), "flare" },
    reset = { c255(196, 210, 230), "plain" }, soothing = { c255(232, 110, 130), "band" },
  }
  local function bagBody(G, fill, pattern, size)
    -- the chains to the hook
    col(G, P.steelHi); G.setLineWidth(0.9)
    G.line(10, 0.5, 3.5, 11); G.line(10, 0.5, 16.5, 11); G.line(10, 0.5, 10, 9)
    col(G, P.ink, 0.85); G.rectangle("fill", 1.4, 9.4, 17.2, 39.8, 5, 5)
    -- the body round like a cylinder: lit at the left, shaded at the right, a soft top and foot
    local L = { math.min(1, fill[1] * 1.35 + 0.08), math.min(1, fill[2] * 1.35 + 0.08), math.min(1, fill[3] * 1.35 + 0.08) }
    local D = { fill[1] * 0.55, fill[2] * 0.55, fill[3] * 0.55 }
    local body = function() G.rectangle("fill", 2.3, 10.3, 15.4, 38, 4.2, 4.2) end
    G.stencil(body, "replace", 1)
    G.setStencilTest("greater", 0)
    G.setColor(1, 1, 1, 1)
    G.draw(G.newMesh({ { 2.3, 0, 0, 0, D[1], D[2], D[3], 1 }, { 2.3, 50, 0, 0, D[1], D[2], D[3], 1 },
      { 6.5, 0, 0, 0, L[1], L[2], L[3], 1 }, { 6.5, 50, 0, 0, L[1], L[2], L[3], 1 },
      { 10, 0, 0, 0, fill[1], fill[2], fill[3], 1 }, { 10, 50, 0, 0, fill[1], fill[2], fill[3], 1 },
      { 17.7, 0, 0, 0, D[1], D[2], D[3], 1 }, { 17.7, 50, 0, 0, D[1], D[2], D[3], 1 } }, "strip", "static"))
    G.setColor(1, 1, 1, 0.3); G.rectangle("fill", 5, 12, 1.6, 34, 0.8, 0.8)
    vgrad(G, 0, 10, 20, 5, { 0, 0, 0, 0.45 }, { 0, 0, 0, 0 })
    vgrad(G, 0, 43, 20, 6, { 0, 0, 0, 0 }, { 0, 0, 0, 0.35 })
    scan(G, 2, 10, 16, 39, 0.05, 0.9)
    G.setStencilTest()
    local hi = { 1, 1, 1, 0.75 }
    if pattern == "bands" then
      for i = 1, size do
        G.setColor(1, 1, 1, 0.7); G.rectangle("fill", 2.3, 44 - i * 6, 15.4, 2.6)
      end
    elseif pattern == "diamonds" then
      G.setColor(hi)
      for _, y in ipairs({ 22, 32, 41 }) do G.polygon("fill", 10, y - 4, 14, y, 10, y + 4, 6, y) end
    elseif pattern == "squares" then
      G.setColor(hi)
      for _, p in ipairs({ { 6, 22 }, { 11, 22 }, { 6, 30 }, { 11, 30 } }) do G.rectangle("fill", p[1], p[2], 3.5, 3.5) end
    elseif pattern == "triangles" then
      G.setColor(hi)
      for _, x in ipairs({ 5, 10, 15 }) do G.polygon("fill", x - 2.5, 36, x, 32, x + 2.5, 36) end
      for _, x in ipairs({ 7.5, 12.5 }) do G.polygon("fill", x - 2.5, 30, x, 26, x + 2.5, 30) end
    elseif pattern == "dots" then
      G.setColor(hi)
      for _, p in ipairs({ { 6, 24 }, { 14, 24 }, { 10, 31 }, { 6, 38 }, { 14, 38 } }) do circle(G, "fill", p[1], p[2], 2.2) end
    elseif pattern == "x2" then
      col(G, P.gold)
      G.setLineWidth(1.6); G.line(4, 22, 8, 27); G.line(8, 22, 4, 27)
      stroke(G, 1.6, 10, 22, 15, 22, 15, 26, 10, 30, 15, 30)
      G.rectangle("fill", 2.3, 17, 15.4, 1.6); G.rectangle("fill", 2.3, 35, 15.4, 1.6)
    elseif pattern == "flare" then
      G.setColor(0.25, 0.25, 0.28, 1); G.rectangle("fill", 3.5, 20, 13, 18, 2, 2)
      col(G, P.red); G.polygon("fill", 10, 22, 14, 28, 12, 35, 10, 31, 8, 35, 6, 28)
    elseif pattern == "band" then
      G.setColor(1, 1, 1, 0.65); G.rectangle("fill", 2.3, 30, 15.4, 3)
    end
  end
  gen("training/home_sand_bag", 20, 50, function(G) bagBody(G, c255(56, 58, 66), "plain", 0) end)
  gen("training/sand_bag_00", 20, 50, function(G) bagBody(G, c255(56, 58, 66), "plain", 0) end)
  local SIZE_BANDS = { s = 1, m = 2, l = 3 }
  for i, id in ipairs(Rules.GAME_ORDER) do
    local def = Rules.bag(id)
    gen(("training/sand_bag_%02d"):format(i), 20, 50, function(G)
      if def and def.kind == "stat" then
        local rgb = STAT_RGB[def.stat] or { 0.6, 0.6, 0.65 }
        bagBody(G, { rgb[1] * 0.85, rgb[2] * 0.85, rgb[3] * 0.85, 1 }, "bands", SIZE_BANDS[def.size] or 1)
      else
        local e = EFFECT[id] or { c255(120, 120, 130), "plain" }
        bagBody(G, e[1], e[2], 0)
      end
    end)
  end

  -- ------- the regimen picker and its card

  -- the medal: a gold disc with a dark rim, its shine and swirl, and two ribbons splaying out
  -- under it with forked ends (orange-yellow edged, red inside)
  local function ribbon(G, flip)
    local function X(x) return flip and 32 - x or x end
    -- the forked end makes each outline concave: triangulated
    local function poly(_, ...)
      local pts = { ... }
      for _, t in ipairs(love.math.triangulate(pts)) do G.polygon("fill", t) end
    end
    col(G, P.ink)
    poly("fill", X(6.5), 18.5, X(14.5), 21, X(11.5), 31.5, X(7.5), 27.5, X(1.2), 26.5)
    col(G, c255(250, 196, 40))
    poly("fill", X(7.3), 19.6, X(13.3), 21.6, X(11), 29.8, X(7.6), 26.4, X(2.6), 25.6)
    col(G, c255(240, 44, 30))
    poly("fill", X(8.6), 20.6, X(12), 22, X(10.4), 27, X(7.8), 25.2, X(5.2), 24.8)
  end
  gen("training/medal", 32, 32, function(G)
    ribbon(G, false)
    ribbon(G, true)
    col(G, P.ink); circle(G, "fill", 16, 13, 11.2)
    shadedDisc(G, 16, 13, 10.2, c255(240, 186, 24), c255(255, 252, 200))
    -- the swirl across it, and a glint up on the right
    col(G, c255(214, 150, 14)); G.setLineWidth(2)
    G.arc("line", "open", 15, 8, 9, math.rad(35), math.rad(150), 16)
    G.setColor(1, 1, 1, 0.75); circle(G, "fill", 20.5, 7.5, 1.8)
  end)
  -- the selection: a cyan bracket either side
  gen("training/ss_cur", 90, 64, function(G)
    col(G, P.tealHi); G.setLineWidth(4.5)
    G.arc("line", "open", 30, 32, 26, math.rad(140), math.rad(220), 16)
    G.arc("line", "open", 60, 32, 26, math.rad(-40), math.rad(40), 16)
  end)
  gen("training/ss_meter_bg", 128, 64, function(G)
    G.stencil(function() G.rectangle("fill", 6, 6, 122, 58) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 6, 6, 122, 58, c255(14, 163, 253, 170), c255(110, 90, 250, 170))
    G.setStencilTest()
    col(G, P.white); G.setLineWidth(1.6)
    G.line(128, 3, 3, 3, 3, 64)
    G.line(128, 7, 7, 7, 7, 64)
  end)
  gen("training/ss_page_arrow", 20, 40, function(G)
    col(G, P.ink); stroke(G, 9, 15, 4, 5, 20, 15, 36)
    col(G, P.silver); stroke(G, 5.5, 15, 4, 5, 20, 15, 36)
    G.setColor(1, 1, 1, 0.8); stroke(G, 1.6, 14, 6, 6.5, 19)
  end)
  gen("training/ss_perfect_icon1", 32, 32, function(G)
    flexer(G, 16, 15, 1.05)
    col(G, P.white)
    for i = 0, 4 do star(G, 6 + i * 5, 28, 2.4) end
  end)
  gen("training/ss_perfect_icon2", 32, 32, function(G) flexer(G, 16, 18, 1.2) end)
  -- the medal count's tab: teal up to the top edge at the left, a dark rim stepping down from
  -- a third of the way along, the right end slanted, a soft shadow under it
  gen("training/ss_pokename_bg", 190, 40, function(G)
    G.setColor(0, 0, 0, 0.25)
    fillShape(G, { 3, 3, 176, 4.5, 182, 25, 177, 33, 16, 36, 8, 33, 1, 9 })
    col(G, P.ink)
    fillShape(G, { 1, 0, 58, 0, 60, 1.5, 172, 1.5, 176, 4, 179, 21, 175, 28, 16, 32.5, 8, 29, 1, 6 })
    col(G, c255(68, 68, 72))
    fillShape(G, { 2.5, 0, 58, 0, 59.5, 3, 171, 3, 174.5, 5, 177.5, 21, 173.5, 26.8, 16.5, 31, 9.5, 28, 2.5, 6 })
    gradShape(G, { 4, 0, 58, 0, 59, 4.5, 170, 4.5, 173, 6, 175.5, 21, 172, 25.5, 17, 29.5, 11, 27, 4, 6 },
      0, 0, 190, 30, c255(17, 214, 180), c255(10, 160, 140))
  end)
  gen("training/ss_return", 30, 30, GEN["training/home_return"].draw)
  -- a course not open yet: a grey disc, crossed
  gen("training/ss_stage_icon00", 64, 64, function(G)
    col(G, P.ink); circle(G, "fill", 32, 32, 31)
    shadedDisc(G, 32, 32, 28, c255(70, 70, 76), c255(200, 200, 206))
    shadedDisc(G, 32, 32, 22, c255(96, 96, 100), c255(150, 150, 156))
    col(G, c255(50, 50, 54)); stroke(G, 3.5, 20, 44, 44, 20)
  end)
  -- the card's frame for a course without its picture
  gen("training/ss_stage_icon01", 64, 64, function(G)
    col(G, P.ink); circle(G, "fill", 32, 32, 31)
    shadedDisc(G, 32, 32, 28, c255(70, 70, 76), c255(200, 200, 206))
    col(G, c255(10, 30, 60)); circle(G, "fill", 32, 32, 23)
    col(G, c255(40, 140, 230), 0.8); G.setLineWidth(2)
    circle(G, "line", 32, 32, 21)
  end)
  -- the level band (stretched across), the card window's corners
  gen("training/ss_stage_win", 10, 30, function(G)
    vgrad(G, 0, 0, 10, 30, c255(17, 221, 187, 187), c255(0, 119, 102, 51))
  end)
  gen("training/ss_stage_win_lt", 16, 24, function(G)
    G.setBlendMode("replace")
    col(G, c255(153, 238, 238, 85)); G.rectangle("fill", 0, 0, 40, 60, 6, 6)
    col(G, GLASS); G.rectangle("fill", 3, 3, 40, 60, 4, 4)
    G.setBlendMode("alpha")
  end)
  gen("training/ss_stage_win_rt", 16, 24, function(G)
    col(G, P.steel); G.rectangle("fill", -24, 0, 40, 60, 6, 6)
    col(G, c255(85, 85, 85)); G.rectangle("fill", -24, 3, 37, 60, 4, 4)
    G.setBlendMode("replace")
    col(G, GLASS); G.rectangle("fill", -24, 5, 34, 60, 3, 3)
    G.setBlendMode("alpha")
  end)
  -- a stat row on the card: a white bar pointed at both ends
  gen("training/ss_status_win", 160, 30, function(G)
    col(G, c255(120, 120, 126)); G.polygon("fill", 0, 15, 8, 6, 152, 6, 160, 15, 152, 24, 8, 24)
    local m = G.newMesh({ { 2, 15, 0, 0, 0.97, 0.97, 0.97, 1 }, { 9, 7.5, 0, 0, 1, 1, 1, 1 }, { 151, 7.5, 0, 0, 1, 1, 1, 1 },
      { 158, 15, 0, 0, 0.92, 0.92, 0.92, 1 }, { 151, 22.5, 0, 0, 0.85, 0.85, 0.86, 1 }, { 9, 22.5, 0, 0, 0.85, 0.85, 0.86, 1 } }, "fan", "static")
    G.setColor(1, 1, 1, 1); G.draw(m)
  end)
  -- the card's title bar, its left half (the right half is this mirrored): the slanted outer
  -- end at the left, the dark rim along the bottom, a thin dark strip at the top right; the
  -- right edge is open, where the mirrored half joins it
  gen("training/ss_title_win", 200, 30, function(G)
    col(G, P.ink)
    fillShape(G, { 0, 0, 200, 0, 200, 29, 14, 29, 9, 27, 1, 9 })
    col(G, c255(68, 72, 72))
    fillShape(G, { 1.5, 0, 200, 0, 200, 27.5, 14, 27.5, 10, 25.5, 2.5, 8.5 })
    gradShape(G, { 3, 0, 170, 0, 172, 2.5, 200, 2.5, 200, 25, 13, 25, 10, 23, 3, 8 },
      0, 0, 200, 26, c255(17, 221, 187), c255(10, 170, 150))
  end)
  gen("training/ss_up_arrow", 10, 20, function(G)
    col(G, c255(120, 40, 140)); G.polygon("fill", 5, 1, 10, 8, 7, 8, 7, 19, 3, 19, 3, 8, 0, 8)
    col(G, P.white); G.polygon("fill", 5, 3, 8.5, 7.5, 6, 7.5, 6, 18, 4, 18, 4, 7.5, 1.5, 7.5)
  end)
  gen("training/tag_cleared", 60, 20, function(G)
    col(G, c255(90, 10, 10, 221)); G.rectangle("fill", 1, 3, 58, 14, 3, 3)
    G.setBlendMode("replace")
    col(G, c255(34, 0, 0, 221)); G.rectangle("fill", 2.5, 4.5, 55, 11, 2, 2)
    G.setBlendMode("alpha")
    outlined(G, "CLEARED", 30, 10, 10, c255(255, 120, 60), c255(70, 0, 0), 0.8, 52)
  end)

  -- the course pictures: the course's balloon (PlayNav's own sprites, balloon blue) in a ringed medallion
  -- over a sky and a lawn; a course whose balloon has no sprite keeps the plain medallion
  local courseBot = nil
  local function botForArt(id)
    if not courseBot then
      courseBot = {}
      for _, c in ipairs((deps.courses and deps.courses.courses) or {}) do
        local b = c.bots and c.bots[1]
        if b and b.art and not courseBot[b.art] then courseBot[b.art] = { bot = b, stat = c.stat } end
      end
    end
    local e = courseBot[id]
    return e and e.bot, e and e.stat
  end
  for n = 0, 39 do
    local id = ("training/stage_poke_%02d"):format(n)
    local shape = nil
    gen(id, 64, 64, function(G)
      local bot, stat = botForArt(id)
      local ring = stat and LABEL_RGB[stat]
      col(G, P.ink); circle(G, "fill", 32, 32, 31)
      if ring then
        shadedDisc(G, 32, 32, 28.5, { ring[1] * 0.45, ring[2] * 0.45, ring[3] * 0.45 }, ring)
      else
        shadedDisc(G, 32, 32, 28.5, c255(70, 70, 76), c255(210, 210, 216))
      end
      G.stencil(function() circle(G, "fill", 32, 32, 25) end, "replace", 1)
      G.setStencilTest("greater", 0)
      vgrad(G, 0, 0, 64, 40, c255(120, 190, 250), c255(200, 236, 255))
      vgrad(G, 0, 40, 64, 24, c255(110, 190, 90), c255(60, 140, 60))
      -- the balloon as the regimen shows it: its sprite on the arena's blue ramp, outlined
      -- (arena_draw D.drawBalloon), scaled by its visible extent
      if shape and shape.image and shape.bbox and deps.drawBalloon then
        local bb = shape.bbox
        local ppx = 42 / math.max(1, bb[3] - bb[1], bb[4] - bb[2])
        deps.drawBalloon(G, shape, 32, 33, ppx, 1)
      end
      G.setStencilTest()
    end)
    GEN[id].prepare = function()
      local bot = botForArt(id)
      shape = bot and deps.shapeFor and deps.shapeFor(bot) or nil
    end
  end

  -- ------- the regimen's gameplay pieces

  -- a goal, frame 0..8: a ring closing in to the gridded tile (white, or red for a chance goal)
  local function goal(G, f, edge, fill)
    -- frame 0 is the goal not yet there (a regimen's goals wait in it through the intro)
    if f == 0 then return end
    local k = f / 8
    if k < 1 then
      G.setColor(edge[1], edge[2], edge[3], 1 - k)
      G.setLineWidth(2.2)
      circle(G, "line", 16, 16, 15 - 6 * k)
    end
    local s = 6 + 9 * k
    G.setColor(fill[1], fill[2], fill[3], 0.55 * k)
    G.rectangle("fill", 16 - s, 16 - s, 2 * s, 2 * s, 2, 2)
    G.setColor(1, 1, 1, 0.5 * k)
    G.setLineWidth(0.8)
    for i = 1, 3 do
      local x = 16 - s + i * s / 2
      G.line(x, 16 - s, x, 16 + s)
      G.line(16 - s, x, 16 + s, x)
    end
    G.setColor(edge[1], edge[2], edge[3], math.min(1, 0.4 + k))
    G.setLineWidth(2)
    G.rectangle("line", 16 - s, 16 - s, 2 * s, 2 * s, 2, 2)
  end
  for f = 0, 8 do
    gen("lyt/st_hud/target01_" .. f, 32, 32, function(G) goal(G, f, { 1, 1, 1 }, { 0.35, 0.55, 0.95 }) end)
    gen("lyt/st_hud/big_target_" .. f, 32, 32, function(G) goal(G, f, { 1, 0.3, 0.3 }, { 0.9, 0.2, 0.2 }) end)
  end
  gen("lyt/st_hud/barrier_target", 32, 32, function(G)
    G.setColor(1, 0.85, 0.2, 1)
    G.polygon("fill", 16, 2, 30, 16, 16, 30, 2, 16)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(2)
    G.polygon("line", 16, 6, 26, 16, 16, 26, 6, 16)
  end)
  -- the attackers' ball and the Energy Shots (by type: black, yellow, orange, green, blue, weak)
  -- the ball sits small in its cell, as the game's does (the cell is scaled to the ball's size)
  local function soccer(G, patch)
    local r = 7.5
    col(G, P.ink); circle(G, "fill", 16, 16, r + 0.8)
    shadedDisc(G, 16, 16, r, c255(190, 194, 204), P.white)
    col(G, patch)
    local pts = {}
    for i = 0, 4 do
      local a = -math.pi / 2 + i * 2 * math.pi / 5
      pts[#pts + 1] = 16 + math.cos(a) * r * 0.38; pts[#pts + 1] = 16 + math.sin(a) * r * 0.38
      circle(G, "fill", 16 + math.cos(a + math.pi / 5) * r * 0.88, 16 + math.sin(a + math.pi / 5) * r * 0.88, r * 0.26)
    end
    G.polygon("fill", pts)
  end
  gen("lyt/st_hud/target_ball00", 32, 32, function(G) soccer(G, P.ink) end)
  local BALLS = { [0] = c255(40, 40, 46), c255(240, 200, 30), c255(250, 140, 30), c255(40, 170, 70),
    c255(40, 120, 230), c255(170, 175, 185) }
  for i = 0, 5 do
    gen(("training/ball_%02d"):format(i), 32, 32, function(G) soccer(G, BALLS[i]) end)
  end
  -- the last shot's brackets
  gen("lyt/st_hud/target02_c", 32, 32, function(G)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(2.4)
    for _, s in ipairs({ { 2, 2, 1, 1 }, { 30, 2, -1, 1 }, { 2, 30, 1, -1 }, { 30, 30, -1, -1 } }) do
      G.line(s[1], s[2] + 8 * s[4], s[1], s[2], s[1] + 8 * s[3], s[2])
    end
  end)
  -- the balloon's air: the arena draws its own puffs in their place
  for _, id in ipairs({ "fx/streamline02f", "fx/circle01m", "fx/kumo01m" }) do GEN[id] = { none = true } end

  -- ------- making the images

  local function render(spec)
    local G = love.graphics
    -- anything that reads a canvas back of its own (a balloon's shape) is fetched before ours
    -- is set: switching canvases mid-drawing spoiled what was drawn into it
    if spec.prepare then pcall(spec.prepare) end
    local canvas = G.newCanvas(spec.w, spec.h, { dpiscale = U.K })
    G.push("all")
    G.setCanvas({ canvas, stencil = true })
    G.origin()
    G.setScissor()
    G.clear(0, 0, 0, 0)
    G.setBlendMode("alpha")
    G.setLineStyle("smooth")
    G.setColor(1, 1, 1, 1)
    local ok, err = pcall(spec.draw, G, spec.w, spec.h)
    G.pop()
    if not ok then
      mod.log:warn("ui art failed to draw: %s", tostring(err))
      return nil
    end
    local data = canvas:newImageData()
    canvas:release()
    -- a canvas drawn with the alpha blend holds its colours multiplied by their alpha; drawn
    -- again as an image they would be multiplied twice (see-through parts too dark, soft
    -- edges with dark fringes): divide them back out
    data:mapPixel(function(_, _, r, g, b, a)
      if a > 0 and a < 1 then return math.min(1, r / a), math.min(1, g / a), math.min(1, b / a), a end
      return r, g, b, a
    end)
    local img = G.newImage(data, { dpiscale = U.K, mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear")
    return img
  end

  -- an Image for a UI id the engine draws, and true when the id is the engine's (nil, true: one
  -- the engine leaves to its drawn stand-in); nil, nil: not ours, the caller goes on
  function U.image(id)
    local img = U.images[id]
    if img ~= nil then return img or nil, true end
    local spec = GEN[id]
    if not spec then return nil end
    if spec.none then return nil, true end
    if not (love and love.graphics and love.graphics.newCanvas) then return nil end
    local ok, made = pcall(render, spec)
    img = ok and made or nil
    if not ok then mod.log:warn("ui art %s: %s", id, tostring(made)) end
    U.images[id] = img or false
    U.made = U.made + 1
    return img, true
  end

  function U.has(id) return GEN[id] ~= nil end
  function U.ids()
    local out = {}
    for id in pairs(GEN) do out[#out + 1] = id end
    table.sort(out)
    return out
  end

  return U
end
