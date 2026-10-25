-- Super Training's UI drawn by the engine: each id the screens ask Assets for (frames,
-- windows, buttons, labels, plates, moods, effects, the shutters' edges, the bags) is drawn
-- here once into a canvas of the texture's own size (in layout units) at K times the density,
-- read back into an Image, and handed out in its place. The screens keep their layout and
-- animation code: only where the pixels come from changes. Sprites Wooble supplies later go
-- in assets/ and take the same ids.

return function(mod, deps)
  local U = { K = 4, images = {}, made = 0 }
  local Rules = deps.Rules

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

  -- ------- glyphs and the round buttons

  -- an open polyline with its inner corners rounded (r units)
  local function roundPath(pts, r)
    local out = { pts[1], pts[2] }
    local n = #pts / 2
    for i = 2, n - 1 do
      local px, py = pts[(i - 2) * 2 + 1], pts[(i - 2) * 2 + 2]
      local x, y = pts[(i - 1) * 2 + 1], pts[(i - 1) * 2 + 2]
      local nx, ny = pts[i * 2 + 1], pts[i * 2 + 2]
      local d1 = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
      local d2 = math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)
      local rr = math.min(r, d1 * 0.5, d2 * 0.5)
      local ax, ay = x + (px - x) * rr / d1, y + (py - y) * rr / d1
      local bx, by = x + (nx - x) * rr / d2, y + (ny - y) * rr / d2
      for s = 0, 6 do
        local t = s / 6
        local u = 1 - t
        out[#out + 1] = u * u * ax + 2 * u * t * x + t * t * bx
        out[#out + 1] = u * u * ay + 2 * u * t * y + t * t * by
      end
    end
    out[#out + 1] = pts[#pts - 1]; out[#out + 1] = pts[#pts]
    return out
  end

  -- the return arrow about (cx, cy) at scale s (its box 24 x 20 at s 1): a bar along the top
  -- to the arrowhead at the right, down the left round its corners, back along the foot; with
  -- dots, two little blocks after the foot
  local function returnArrow(G, cx, cy, s, dots, chevron)
    local function X(x) return cx + x * s end
    local function Y(y) return cy + y * s end
    G.setLineJoin("miter")
    G.setLineWidth(3.2 * s)
    if chevron then
      -- the top bar rising a little toward the head; the head two thick strokes
      G.line(roundPath({ X(9.4), Y(-6.2), X(-7.6), Y(-3.2), X(-7.6), Y(6.6), X(5.2), Y(6.6) }, 2.6 * s))
      G.setLineWidth(3.4 * s)
      G.line(X(3.4), Y(-11.6), X(10.4), Y(-6.4), X(4.8), Y(0.4))
    else
      G.line(roundPath({ X(5.6), Y(-4), X(-7.6), Y(-4), X(-7.6), Y(6.6), X(5.2), Y(6.6) }, 2.6 * s))
      G.polygon("fill", X(4.8), Y(-9.6), X(11.6), Y(-4), X(4.8), Y(1.6))
    end
    if dots then
      G.rectangle("fill", X(7), Y(5.1), 2.4 * s, 3 * s)
      G.rectangle("fill", X(10.2), Y(5.1), 2.4 * s, 3 * s)
    end
  end

  -- a bit of a circle with an arrowhead at its end (angles in radians, a0 to a1)
  local function arrowArc(G, cx, cy, r, a0, a1, w, head)
    local pts = {}
    for i = 0, 12 do
      local a = a0 + (a1 - a0) * i / 12
      pts[#pts + 1] = cx + math.cos(a) * r; pts[#pts + 1] = cy + math.sin(a) * r
    end
    G.setLineWidth(w); G.line(pts)
    local sg = (a1 > a0) and 1 or -1
    local ex, ey = cx + math.cos(a1) * r, cy + math.sin(a1) * r
    local tx, ty = -math.sin(a1) * sg, math.cos(a1) * sg
    local nx, ny = -ty, tx
    G.polygon("fill", ex + tx * head * 1.1, ey + ty * head * 1.1, ex + nx * head, ey + ny * head,
      ex - nx * head, ey - ny * head)
  end

  -- the punching bag between two circling arrows
  local function bagGlyph(G, c, stripe)
    col(G, c)
    G.setLineWidth(0.9)
    G.line(24, 6.6, 21.3, 13.4); G.line(24, 6.6, 26.7, 13.4); G.line(24, 6.6, 24, 13)
    circle(G, "fill", 24, 6.6, 1)
    local body = roundPts({ 20.4, 13, 27.6, 13, 29.8, 18, 29.8, 30, 27.4, 33.6, 20.6, 33.6, 18.2, 30, 18.2, 18 }, 2.6)
    fillShape(G, body)
    within(G, body, function()
      col(G, stripe, 0.4); G.setLineWidth(0.7)
      for y = 16.5, 32, 3.4 do G.line(17, y, 31, y) end
    end)
    col(G, c)
    arrowArc(G, 24, 23.5, 10.6, math.rad(208), math.rad(150), 3, 3)
    arrowArc(G, 24, 23.5, 10.6, math.rad(28), math.rad(-30), 3, 3)
  end

  -- the lime round button: a black ring, a thin bright silver bezel, the lime face darker at
  -- the top and yellow-green at the foot, a gloss across its top
  local function limeButton(G, cx, cy, r)
    local face = r * 0.84
    G.setColor(0.04, 0.05, 0.04, 1); circle(G, "fill", cx, cy, r)
    -- the silver bezel, bevelled: dark toward the top, bright at the foot, a lit inner lip
    -- below and a shaded one above
    G.stencil(function() circle(G, "fill", cx, cy, r * 0.93) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, cx - r, cy - r, 2 * r, 2 * r, c255(122, 128, 122), c255(252, 253, 250))
    G.setStencilTest()
    G.setLineWidth(r * 0.05)
    G.setColor(0, 0, 0, 0.35); G.arc("line", "open", cx, cy, face + r * 0.025, math.rad(200), math.rad(340), 32)
    G.setColor(1, 1, 1, 0.8); G.arc("line", "open", cx, cy, face + r * 0.025, math.rad(20), math.rad(160), 32)
    -- the face: lime, darker under the bezel at the top, yellow light bouncing up at the foot
    G.stencil(function() circle(G, "fill", cx, cy, face) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, cx - r, cy - face, 2 * r, 2 * face, c255(84, 206, 0), c255(204, 255, 46))
    G.setColor(1, 1, 0.75, 0.3); G.ellipse("fill", cx, cy + face * 0.62, face * 0.66, face * 0.36, 32)
    -- the inner shadow round the edge, heaviest at the top
    G.setLineWidth(face * 0.22); G.setColor(0.1, 0.3, 0.02, 0.3); circle(G, "line", cx, cy, face)
    vgrad(G, cx - r, cy - face, 2 * r, face * 0.5, { 0.08, 0.28, 0, 0.35 }, { 0.08, 0.28, 0, 0 })
    G.setStencilTest()
    -- the gloss: a white sheen over the face's upper half, its lower edge curved
    G.stencil(function() circle(G, "fill", cx, cy, face * 0.94) end, "replace", 1)
    G.stencil(function() G.ellipse("fill", cx, cy - face * 0.42, face * 0.8, face * 0.56, 48) end, "increment", 1, true)
    G.setStencilTest("equal", 2)
    vgrad(G, cx - r, cy - face, 2 * r, face * 1.02, { 1, 1, 1, 0.4 }, { 1, 1, 1, 0.02 })
    G.setStencilTest()
    -- a glint at the upper left
    G.setColor(1, 1, 1, 0.85); G.ellipse("fill", cx - face * 0.42, cy - face * 0.56, face * 0.16, face * 0.08, 20)
    G.setLineWidth(0.6); G.setColor(0.2, 0.35, 0.1, 0.55); circle(G, "line", cx, cy, face)
  end

  -- ------- the generators: id -> { w, h, draw(G, w, h) } in the texture's own units

  local GEN = {}
  local function gen(id, w, h, draw, prepare) GEN[id] = { w = w, h = h, draw = draw, prepare = prepare } end

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

  -- the + mark the backdrop tiles: a thin cross over a soft diamond of light
  gen("training/home_bg_ptn", 32, 32, function(G)
    for i = 5, 1, -1 do
      local r = 1.2 + i * 1.1
      G.setColor(1, 1, 1, 0.045)
      G.polygon("fill", 16, 16 - r, 16 + r, 16, 16, 16 + r, 16 - r, 16)
    end
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 15.4, 11.2, 1.2, 9.6, 0.5, 0.5)
    G.rectangle("fill", 11.2, 15.4, 9.6, 1.2, 0.5, 0.5)
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
    limeButton(G, 24, 24, 22.5)
    -- the arrow's extent (x -9.2..12.9, y -13..8.2 about its point) centred on the button's
    col(G, c255(10, 58, 12)); returnArrow(G, 22.15, 26.4, 1, true, true)
  end)
  -- PlayNav's small return: a dark blue ring, a white face shaded to grey at its lower right,
  -- the blue return arrow
  gen("training/home_return", 30, 30, function(G)
    G.setColor(0.08, 0.2, 0.42, 1); circle(G, "fill", 15, 15, 14)
    G.setColor(0.2, 0.36, 0.62, 1); G.setLineWidth(0.7); circle(G, "line", 15, 15, 13)
    G.stencil(function() circle(G, "fill", 15, 15, 11.8) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 3, 3, 24, 24, c255(250, 250, 252), c255(184, 188, 196))
    G.setColor(1, 1, 1, 0.5); G.ellipse("fill", 13, 10, 8, 5, 24)
    G.setStencilTest()
    col(G, c255(36, 104, 206)); returnArrow(G, 15.6, 14.4, 0.66)
    G.setColor(0.6, 0.8, 1, 0.7); G.setLineWidth(0.5); G.line(11.4, 11.1, 18.6, 11.1)
  end)
  gen("training/btn_bags", 48, 48, function(G)
    limeButton(G, 24, 24, 22.5)
    bagGlyph(G, c255(10, 58, 12), c255(120, 200, 60))
  end)
  -- the Regimens button: the bottom-left corner of a lime panel that runs off the screen's
  -- left and bottom edges, its top edge sloping down with a step, its right end round; a black
  -- edge, a silver bezel with a teal stripe along its upper slope, a drop shadow on the right;
  -- on the lime, a ball whose swoosh trails off to a small figure
  -- (the outline runs well past the texture's left and bottom, so the rim drawn along it shows
  -- only on the top and the round end: the panel is cut off by the screen's edges)
  local REG = { -20, -4.9, 33, 15.6, 35.2, 17.6, 42, 21, 48, 24, 52, 27, 55, 31, 57.5, 35.5, 59, 41, 59.6, 47,
    59.2, 53, 57.8, 58, 56, 61.5, 54.2, 66, 53.2, 82, -20, 82 }
  local GLYPH = c255(8, 48, 4)
  -- the ball's trail: one shape growing out of the ball's outline - thin at its upper left,
  -- thickening round the bottom, then sweeping off to the right and tapering to the figure's
  -- feet (tx, ty); w the thickest
  local function swoosh(G, bx, by, br, tx, ty, w)
    local function ease(t) return t * t * (3 - 2 * t) end
    local inner, outer = {}, {}
    local A0, A1 = math.rad(205), math.rad(90)
    for i = 0, 20 do
      local t = i / 20
      local a = A0 + (A1 - A0) * t
      local ww = w * ease(t)
      inner[#inner + 1] = bx + math.cos(a) * (br - 0.4); inner[#inner + 1] = by + math.sin(a) * (br - 0.4)
      outer[#outer + 1] = bx + math.cos(a) * (br + ww); outer[#outer + 1] = by + math.sin(a) * (br + ww)
    end
    -- the tail: a curve from the ball's foot, its top edge leaving the ball, tapering
    local x0, y0 = bx, by + br + w / 2
    local x1, y1 = bx + (tx - bx) * 0.4, by + br + w * 1.9
    local upper, lower = {}, {}
    for i = 1, 20 do
      local t = i / 20
      local u = 1 - t
      local x, y = u * u * x0 + 2 * u * t * x1 + t * t * tx, u * u * y0 + 2 * u * t * y1 + t * t * ty
      local dx, dy = 2 * u * (x1 - x0) + 2 * t * (tx - x1), 2 * u * (y1 - y0) + 2 * t * (ty - y1)
      local d = math.sqrt(dx * dx + dy * dy)
      local hw = (w + (w * 0.3 - w) * ease(t)) / 2
      upper[#upper + 1] = x + dy / d * hw; upper[#upper + 1] = y - dx / d * hw
      lower[#lower + 1] = x - dy / d * hw; lower[#lower + 1] = y + dx / d * hw
    end
    local pts = {}
    for i = 1, #inner do pts[#pts + 1] = inner[i] end
    for i = 1, #upper do pts[#pts + 1] = upper[i] end
    for i = #lower - 1, 1, -2 do pts[#pts + 1] = lower[i]; pts[#pts + 1] = lower[i + 1] end
    for i = #outer - 1, 1, -2 do pts[#pts + 1] = outer[i]; pts[#pts + 1] = outer[i + 1] end
    fillShape(G, pts)
  end
  gen("training/btn_regimens", 64, 64, function(G)
    local O = roundPts(REG, 1.4, { [1] = true, [15] = true, [16] = true })
    -- a soft shadow off the right end
    G.push(); G.translate(1.6, 0.6)
    G.setColor(0, 0, 0, 0.32); fillShape(G, O)
    G.pop()
    local edge = closed(O)
    within(G, O, function()
      -- the lime face, brighter toward the foot, with fine lines and a gloss
      vgrad(G, -6, 0, 70, 66, c255(84, 200, 0), c255(204, 255, 46))
      scan(G, -6, 0, 70, 66, 0.05, 1.1)
      G.setColor(1, 1, 0.75, 0.25); G.ellipse("fill", 26, 62, 30, 9, 40)
      -- the inner shadow under the bezel
      G.setLineJoin("bevel")
      G.setLineWidth(15); G.setColor(0.08, 0.28, 0, 0.3); G.line(edge)
      -- the gloss along the upper part, curving down at its edge, and a glint
      G.stencil(function() fillShape(G, O) end, "replace", 1)
      G.stencil(function() G.ellipse("fill", 40, 20, 24, 14, 48) end, "increment", 1, true)
      G.setStencilTest("equal", 2)
      vgrad(G, 16, 18, 50, 16, { 1, 1, 1, 0.3 }, { 1, 1, 1, 0.02 })
      G.stencil(function() fillShape(G, O) end, "replace", 1)
      G.setStencilTest("greater", 0)
      G.setColor(1, 1, 1, 0.8); G.ellipse("fill", 40, 27, 4, 1.6, 20)
      -- the rim, polished metal inward from the edge: a dark lip at the face, bright chrome,
      -- a teal-blue inlay set in it, mid steel, dark steel, the black edge
      G.setLineJoin("bevel")
      G.setLineWidth(11.4); G.setColor(0.22, 0.26, 0.28, 1); G.line(edge)
      G.setLineWidth(10.2); G.setColor(0.72, 0.75, 0.77, 1); G.line(edge)
      G.setLineWidth(8.8); G.setColor(0.97, 0.98, 0.99, 1); G.line(edge)
      G.setLineWidth(6.6); G.setColor(0.78, 0.81, 0.83, 1); G.line(edge)
      G.setLineWidth(4.6); G.setColor(0.56, 0.6, 0.63, 1); G.line(edge)
      G.setLineWidth(3.2); G.setColor(0.32, 0.35, 0.37, 1); G.line(edge)
      G.setLineWidth(1.9); G.setColor(0, 0, 0, 1); G.line(edge)
      -- the teal inlay along the upper slope only, set in a dark channel, ending short of the step
      local inlay = { -6, 3.4, 29.4, 17 }
      G.setLineWidth(2.8); G.setColor(0.06, 0.2, 0.24, 1); G.line(inlay)
      circle(G, "fill", 29.4, 17, 1.4)
      G.setLineWidth(1.6); G.setColor(0.29, 0.87, 0.74, 1); G.line(-6, 3.4, 29, 16.85)
      circle(G, "fill", 29, 16.85, 0.8)
      G.setLineWidth(0.5); G.setColor(0.75, 1, 0.95, 0.8); G.line(-6, 3.0, 28.8, 16.4)
    end)
    -- the ball: a dark ring, lime inside, the middle patch and the seams out to the edge
    local bx, by, br = 17.5, 36.5, 8.5
    -- the swoosh first: it curls out from behind the ball and round to the figure's feet
    col(G, GLYPH); swoosh(G, bx, by, br, 40.6, 46.8, 5.2)
    -- the classic pattern: a dark middle patch, seams out from its corners to dark patches cut
    -- off by the ball's edge, the white panels between them lime
    col(G, GLYPH); circle(G, "fill", bx, by, br)
    col(G, c255(140, 230, 50)); circle(G, "fill", bx, by, br - 1.5)
    G.stencil(function() circle(G, "fill", bx, by, br - 1.5) end, "replace", 1)
    G.setStencilTest("greater", 0)
    col(G, GLYPH)
    local pent = {}
    for i = 0, 4 do
      local a = -math.pi / 2 + i * 2 * math.pi / 5
      pent[#pent + 1] = bx + math.cos(a) * 3.2; pent[#pent + 1] = by + math.sin(a) * 3.2
      G.setLineWidth(1.1)
      G.line(bx + math.cos(a) * 3.2, by + math.sin(a) * 3.2, bx + math.cos(a) * 5.6, by + math.sin(a) * 5.6)
      local q = {}
      for k = 0, 4 do
        local e = a + math.pi + k * 2 * math.pi / 5
        q[#q + 1] = bx + math.cos(a) * 8.2 + math.cos(e) * 2.9; q[#q + 1] = by + math.sin(a) * 8.2 + math.sin(e) * 2.9
      end
      G.polygon("fill", q)
      local b = a + math.pi / 5
      G.line(bx + math.cos(a) * 5.6, by + math.sin(a) * 5.6, bx + math.cos(b) * 6.4, by + math.sin(b) * 6.4,
        bx + math.cos(a + 2 * math.pi / 5) * 5.6, by + math.sin(a + 2 * math.pi / 5) * 5.6)
    end
    G.polygon("fill", pent)
    G.setStencilTest()
    -- the figure: two ears, a head, a body on a little base
    G.polygon("fill", 41.8, 34.4, 42.4, 31.6, 43.6, 34)
    G.polygon("fill", 44.4, 34, 45.6, 31.6, 46.2, 34.4)
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
    -- a spiky dark teal burst, its points sharp, a slightly lighter edge
    local pts = {}
    local n = 28
    for i = 0, n - 1 do
      local a = i / n * 2 * math.pi
      local rr = (i % 2 == 0) and 1 or 0.76
      pts[#pts + 1] = 20 + math.cos(a) * 19.5 * rr
      pts[#pts + 1] = 10 + math.sin(a) * 9.6 * rr
    end
    G.setColor(0.07, 0.19, 0.18, 0.94)
    fillShape(G, pts)
    G.setLineJoin("bevel"); G.setLineWidth(0.5); G.setColor(0.2, 0.36, 0.34, 0.9); G.line(closed(pts))
  end)
  gen("training/arrow", 16, 16, function(G)
    -- a block arrow: a wide head on a short stem, white with a soft dark edge, corners rounded
    local pts = roundPts({ 8, 1, 15, 8.2, 10.8, 8.2, 10.8, 15, 5.2, 15, 5.2, 8.2, 1, 8.2 }, 0.9)
    G.setLineJoin("bevel")
    G.setColor(0.08, 0.12, 0.2, 0.35); G.setLineWidth(2.4); G.line(closed(pts))
    G.setColor(0.08, 0.12, 0.2, 0.8); G.setLineWidth(1.1); G.line(closed(pts))
    col(G, P.white); fillShape(G, pts)
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
  -- the flexing figure: head, broad shoulders tapering to the waist, upper arms out, fists up
  local function flexer(G, cx, cy, s, c)
    col(G, c or P.white)
    circle(G, "fill", cx, cy - 8.2 * s, 3.3 * s)
    fillShape(G, roundPts({ cx - 7.6 * s, cy - 4.8 * s, cx + 7.6 * s, cy - 4.8 * s, cx + 4.8 * s, cy + 3.6 * s,
      cx + 4.2 * s, cy + 8.6 * s, cx - 4.2 * s, cy + 8.6 * s, cx - 4.8 * s, cy + 3.6 * s }, 1.6 * s))
    for _, k in ipairs({ -1, 1 }) do
      stroke(G, 4.2 * s, cx + k * 6.4 * s, cy - 3.6 * s, cx + k * 10 * s, cy - 3.4 * s, cx + k * 10.4 * s, cy - 8.6 * s)
      circle(G, "fill", cx + k * 8.4 * s, cy - 5.4 * s, 2.7 * s)
      circle(G, "fill", cx + k * 10.4 * s, cy - 9.4 * s, 2.6 * s)
    end
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

  -- the mood bubbles: a tilted teal screen with a light edge on a stalk, its face in glowing cyan
  local SCREEN = { 4, 1.2, 30.4, 1.2, 28.8, 22.2, 1.6, 23.6 }
  local FACE_C = c255(118, 240, 252)
  local function bubble(G)
    G.setLineWidth(2.6); G.setColor(0.16, 0.36, 0.44, 0.8); G.line(9.6, 23.4, 4.8, 30.8)
    G.setLineWidth(1.5); G.setColor(0.7, 0.86, 0.92, 1); G.line(9.6, 23.4, 4.8, 30.8)
    gradShape(G, SCREEN, 0, 0, 32, 24, c255(0, 116, 128), c255(32, 178, 184))
    within(G, SCREEN, function()
      scan(G, 0, 0, 32, 24, 0.06, 1.4)
      vgrad(G, 0, 0, 32, 5, { 1, 1, 1, 0.12 }, { 1, 1, 1, 0 })
    end)
    G.setLineJoin("bevel")
    G.setLineWidth(1.8); G.setColor(0.6, 0.92, 0.96, 0.3); G.line(closed(SCREEN))
    G.setLineWidth(0.8); G.setColor(0.68, 0.94, 0.98, 0.95); G.line(closed(SCREEN))
  end
  -- each face drawn twice: a soft wide pass, then the sharp one
  local function glowFace(G, draw)
    for _, pass in ipairs({ { 0.22, 1.9 }, { 1, 0 } }) do
      G.setColor(FACE_C[1], FACE_C[2], FACE_C[3], pass[1])
      draw(pass[2])
    end
  end
  local FACE = {
    smile = function(G)
      glowFace(G, function(g)
        G.rectangle("fill", 9.4 - g / 2, 4.8 - g / 2, 2.8 + g, 5.8 + g, 0.6, 0.6)
        G.rectangle("fill", 20 - g / 2, 4.8 - g / 2, 2.8 + g, 5.8 + g, 0.6, 0.6)
        local pts = {}
        for i = 0, 16 do
          local a = math.pi * i / 16
          pts[#pts + 1] = 16.2 + math.cos(a) * (8.6 + g / 2); pts[#pts + 1] = 12 + math.sin(a) * (6.2 + g / 2)
        end
        G.polygon("fill", pts)
      end)
    end,
    silence = function(G)
      glowFace(G, function(g)
        for _, x in ipairs({ 6.4, 14.2, 22 }) do G.rectangle("fill", x - g / 2, 10 - g / 2, 3.6 + g, 3.6 + g, 0.4, 0.4) end
      end)
    end,
    sad = function(G)
      glowFace(G, function(g)
        G.setLineWidth(2.2 + g)
        G.line(8, 9.6, 11.8, 7.2); G.line(24, 9.6, 20.2, 7.2)
        G.arc("line", "open", 16, 22.4, 7.4, math.rad(205), math.rad(335), 16)
      end)
    end,
    surprise = function(G)
      glowFace(G, function(g)
        G.rectangle("fill", 13.8 - g / 2, 2.6 - g / 2, 4.4 + g, 11.4 + g, 1, 1)
        G.rectangle("fill", 13.8 - g / 2, 15.6 - g / 2, 4.4 + g, 3.8 + g, 0.8, 0.8)
      end)
    end,
    perfect = function(G)
      flexer(G, 16, 13.4, 0.82, FACE_C)
    end,
  }
  for name, face in pairs(FACE) do
    gen("training/mood_" .. name, 32, 32, function(G) bubble(G); face(G) end)
  end

  -- the effects: the hit mark, the finishing move's slash, a quarter of its glow
  -- the hit mark: a starburst of thin spikes, white-hot in the middle, a long streak across it,
  -- sparks round it
  gen("training/burst", 64, 64, function(G)
    local function streak(x0, y0, x1, y1, w, c, a)
      local mx, my = (x0 + x1) / 2, (y0 + y1) / 2
      local dx, dy = x1 - x0, y1 - y0
      local d = math.sqrt(dx * dx + dy * dy)
      local nx, ny = -dy / d * w / 2, dx / d * w / 2
      G.setColor(c[1], c[2], c[3], a)
      G.polygon("fill", x0, y0, mx + nx, my + ny, x1, y1, mx - nx, my - ny)
    end
    streak(3, 8, 61, 56, 2.4, c255(200, 120, 50), 0.85)
    streak(14, 2, 50, 62, 1.4, c255(220, 150, 60), 0.6)
    local function star(rLong, rShort, rIn, rot)
      local pts = {}
      for i = 0, 23 do
        local a = rot + i * math.pi / 12
        local rr = (i % 2 == 1) and rIn or ((i % 4 == 0) and rLong or rShort)
        pts[#pts + 1] = 32 + math.cos(a) * rr; pts[#pts + 1] = 32 + math.sin(a) * rr
      end
      return pts
    end
    col(G, c255(248, 176, 36)); fillShape(G, star(25, 16, 7.2, 0.1))
    col(G, c255(255, 226, 80)); fillShape(G, star(19, 12, 6, 0.1))
    for i = 7, 1, -1 do
      G.setColor(1, 0.98, 0.84, 0.16 * (8 - i) / 7 + 0.1)
      circle(G, "fill", 32, 32, i * 1.3)
    end
    col(G, c255(250, 222, 90))
    for _, d in ipairs({ { 9, 7 }, { 55, 10 }, { 57, 50 }, { 6, 42 }, { 30, 3 }, { 61, 30 }, { 20, 58 }, { 44, 59 } }) do
      G.rectangle("fill", d[1] - 1.1, d[2] - 1.1, 2.2, 2.2)
    end
  end)
  -- the finishing move's slash: a crescent opening to the right, its outer edge flaring in
  -- flames, orange outside and yellow within
  gen("training/finish_slash", 64, 64, function(G)
    local A0, A1, N = math.rad(108), math.rad(252), 64
    local FLARE = { 0, 0, 9, 0, 0, 3, 0, 0, 0, 12, 0, 1, 0, 0, 6, 0, 0, 0, 10, 0, 2, 0, 0, 0, 7, 0 }
    local outer, smooth, inner = {}, {}, {}
    for i = 0, N do
      local a = A0 + (A1 - A0) * i / N
      local f = FLARE[(i % #FLARE) + 1] * math.sin(math.pi * i / N)
      outer[#outer + 1] = 44 + math.cos(a) * (27 + f); outer[#outer + 1] = 32 + math.sin(a) * (29 + f)
      smooth[#smooth + 1] = 44 + math.cos(a) * 25.5; smooth[#smooth + 1] = 32 + math.sin(a) * 27.5
      inner[#inner + 1] = 51 + math.cos(a) * 24; inner[#inner + 1] = 32 + math.sin(a) * 26
    end
    local function band(a, b)
      local pts = {}
      for i = 1, #a, 2 do pts[#pts + 1] = a[i]; pts[#pts + 1] = a[i + 1] end
      for i = #b - 1, 1, -2 do pts[#pts + 1] = b[i]; pts[#pts + 1] = b[i + 1] end
      return pts
    end
    col(G, c255(244, 132, 28)); fillShape(G, band(outer, inner))
    col(G, c255(255, 206, 54)); fillShape(G, band(smooth, inner))
    G.setLineWidth(1); G.setColor(1, 0.96, 0.7, 0.9); G.line(inner)
  end)
  -- a quarter of the finishing move's glow (drawn four ways): white light in the lower left
  -- corner, a soft beam out along the diagonal and one along each edge
  gen("training/finish_light", 32, 32, function(G)
    local fan = { { 0, 32, 0, 0, 1, 1, 1, 0.95 } }
    for i = 0, 12 do
      local a = -math.pi / 2 + (math.pi / 2) * i / 12
      fan[#fan + 1] = { math.cos(a) * 20, 32 + math.sin(a) * 20, 0, 0, 1, 1, 1, 0 }
    end
    G.setColor(1, 1, 1, 1); G.draw(G.newMesh(fan, "fan", "static"))
    local core = { { 0, 32, 0, 0, 1, 1, 1, 1 } }
    for i = 0, 12 do
      local a = -math.pi / 2 + (math.pi / 2) * i / 12
      core[#core + 1] = { math.cos(a) * 13, 32 + math.sin(a) * 13, 0, 0, 1, 1, 1, 0 }
    end
    G.draw(G.newMesh(core, "fan", "static"))
    local function beam(a, len, w0, w1, alpha)
      local dx, dy = math.cos(a), math.sin(a)
      local nx, ny = -dy, dx
      local ex, ey = dx * len, 32 + dy * len
      G.draw(G.newMesh({ { nx * w0, 32 + ny * w0, 0, 0, 1, 1, 1, alpha }, { ex + nx * w1, ey + ny * w1, 0, 0, 1, 1, 1, 0 },
        { ex - nx * w1, ey - ny * w1, 0, 0, 1, 1, 1, 0 }, { -nx * w0, 32 - ny * w0, 0, 0, 1, 1, 1, alpha } }, "fan", "static"))
    end
    beam(-math.pi / 4, 30, 2, 5, 0.75)
    beam(0, 32, 1.4, 2.6, 0.6)
    beam(-math.pi / 2, 32, 1.4, 2.6, 0.6)
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

  -- ------- the bags: three chains to the hook, a black-edged body lit from the right, a collar
  -- along its top, and its own motif in the bag's colours

  local INK = c255(41, 41, 41)
  -- the body's outline and its inside (the motifs are drawn inside: x X0..X1, y Y0..Y1)
  local BODY_OUT = { 2.6, 13.6, 16.4, 13.6, 17.4, 16, 17.4, 43.8, 13.6, 47.8, 5.4, 47.8, 1.6, 43.8, 1.6, 16 }
  local BODY_IN = { 3.4, 14.5, 15.6, 14.5, 16.5, 16.6, 16.5, 43.6, 13.2, 46.9, 5.8, 46.9, 2.5, 43.6, 2.5, 16.6 }
  local X0, X1, Y0 = 2.5, 16.5, 16.6

  local function chain(G, x0, y0, x1, y1, light, dark)
    G.setLineWidth(2.6); col(G, INK); G.line(x0, y0, x1, y1)
    local n = math.floor(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / 1.5)
    G.setLineWidth(1.1)
    for i = 0, n - 1 do
      local t0, t1 = i / n, (i + 0.7) / n
      col(G, (i % 2 == 0) and light or dark)
      G.line(x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0, x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
    end
  end
  -- light from the right: a lit strip at the far left, the colour, a lighter band, the highlight
  local SHADE = { { 2.5, 0.16 }, { 3.2, 0.16 }, { 3.6, 0 }, { 12.4, 0 }, { 12.8, 0.15 }, { 14.7, 0.15 },
    { 15.1, 0.32 }, { 16.5, 0.32 } }
  local function shade(G)
    local v = {}
    for _, s in ipairs(SHADE) do
      v[#v + 1] = { s[1], 0, 0, 0, 1, 1, 1, s[2] }; v[#v + 1] = { s[1], 50, 0, 0, 1, 1, 1, s[2] }
    end
    G.setColor(1, 1, 1, 1); G.draw(G.newMesh(v, "strip", "static"))
  end
  local function bag(G, base, motif)
    local outer, inner = roundPts(BODY_OUT, 1.4), roundPts(BODY_IN, 1)
    G.push(); G.translate(0.6, 0.6); G.setColor(0, 0, 0, 0.25); fillShape(G, outer); G.pop()
    col(G, INK); fillShape(G, outer)
    within(G, inner, function()
      col(G, base); G.rectangle("fill", 0, 0, 20, 50)
      if motif then motif(G) end
      shade(G)
      -- the collar: lighter, a dark seam under it, its stitches
      G.setColor(1, 1, 1, 0.14); G.rectangle("fill", 0, 14.5, 20, 2.1)
      G.setColor(0, 0, 0, 0.4); G.rectangle("fill", 0, 16.4, 20, 0.7)
      G.setColor(1, 1, 1, 0.18)
      for x = 3.5, 16, 1.6 do G.rectangle("fill", x, 15.4, 0.8, 0.3) end
      -- the foot darker, its corners darkest
      vgrad(G, 0, 42.5, 20, 4.3, { 0, 0, 0, 0 }, { 0, 0, 0, 0.32 })
      G.setColor(0, 0, 0, 0.18); circle(G, "fill", 2.5, 46.7, 3); circle(G, "fill", 16.5, 46.7, 3)
      -- the canvas: a fine weave and a grain
      scan(G, 0, 14.5, 20, 33, 0.045, 0.75)
      grain(G, 2.5, 14.5, 14, 32, 0.08, 41)
    end)
    -- the chains last: they come down over the collar's ends
    local LT, DK = c255(165, 173, 173), c255(123, 123, 123)
    chain(G, 9.5, 1.6, 4.3, 14.6, LT, DK)
    chain(G, 9.5, 1.6, 14.7, 14.6, LT, DK)
    chain(G, 9.5, 2.5, 9.5, 14, c255(115, 123, 132), c255(66, 66, 74))
    col(G, INK); circle(G, "fill", 9.5, 1.8, 1.4)
    G.setColor(0.65, 0.68, 0.68, 1); circle(G, "fill", 9.5, 1.8, 0.6)
  end

  -- motif pieces
  local function rect(G, c, x, y, w, h, r) col(G, c); G.rectangle("fill", x, y, w, h, r or 0.5, r or 0.5) end
  local function dot(G, c, x, y, r) col(G, c); circle(G, "fill", x, y, r) end
  local function diamond(G, c, x, y, w, h) col(G, c); G.polygon("fill", x, y - h / 2, x + w / 2, y, x, y + h / 2, x - w / 2, y) end
  local function tri(G, c, ...) col(G, c); G.polygon("fill", ...) end
  local function path(G, c, w, pts) col(G, c); G.setLineJoin("miter"); G.setLineWidth(w); G.line(pts) end
  -- everything under an edge across the bag at y: "wave", "bump" (scallops), "spike"; amp high
  local function below(G, c, y, amp, n, kind, phase)
    local pts = { X0 - 1, 50 }
    for i = 0, 40 do
      local x = X0 - 1 + (X1 - X0 + 2) * i / 40
      local u = (x - X0) / (X1 - X0) * n + (phase or 0)
      local d
      if kind == "spike" then d = 1 - 2 * math.abs(u % 1 - 0.5)
      elseif kind == "bump" then d = math.abs(math.sin(u * math.pi))
      else d = math.sin(u * 2 * math.pi) end
      pts[#pts + 1] = x; pts[#pts + 1] = y - amp * d
    end
    pts[#pts + 1] = X1 + 1; pts[#pts + 1] = 50
    col(G, c); fillShape(G, pts)
  end
  -- the gold badge with a ball on it (red over white)
  local function emblem(G, x, y, w, h)
    local hh = h / 2
    local pts = { x - w / 2, y, x - w / 2 + hh, y - hh, x + w / 2 - hh, y - hh, x + w / 2, y, x + w / 2 - hh, y + hh, x - w / 2 + hh, y + hh }
    col(G, c255(99, 84, 40)); G.setLineWidth(0.8); G.setLineJoin("bevel"); G.line(closed(pts))
    col(G, c255(189, 173, 107)); G.polygon("fill", pts)
    local r = h * 0.32
    col(G, c255(222, 82, 74)); G.arc("fill", x, y, r, math.pi, 2 * math.pi, 16)
    col(G, c255(236, 236, 240)); G.arc("fill", x, y, r, 0, math.pi, 16)
    G.setLineWidth(0.35); col(G, INK); G.line(x - r, y, x + r, y)
  end

  local C = c255
  local BLUE, SKY, RED, PINK, PALE = C(58, 107, 148), C(148, 189, 230), C(181, 49, 66), C(197, 115, 148), C(165, 181, 206)
  local MOSS, KHAKI, DEEP, GOLD, MAUVE = C(82, 107, 99), C(148, 132, 66), C(58, 74, 66), C(189, 173, 107), C(115, 99, 115)
  local GREY, DGREY, DDGREY, CYAN, LGREY = C(132, 132, 132), C(66, 66, 66), C(49, 49, 49), C(74, 160, 214), C(196, 196, 200)
  local MIST, LAV, CRACK, LILAC, YEL, SLATE = C(148, 165, 189), C(107, 123, 197), C(123, 132, 140), C(165, 165, 247), C(247, 214, 82), C(82, 82, 82)
  local SAGE, GREEN, PINE, MUSTARD, SCARLET, BRICK, AQUA = C(156, 181, 156), C(49, 115, 66), C(41, 74, 49), C(206, 173, 41), C(214, 74, 58), C(173, 58, 41), C(148, 173, 173)
  local NIGHT, DUSK, MAGENTA, FANG, PLUM = C(82, 99, 132), C(58, 58, 58), C(156, 66, 123), C(165, 173, 173), C(115, 66, 132)

  local BAGS = {
    hp_s = { BLUE, function(G)
      dot(G, PINK, X0 + 1.2, 21, 1.9); dot(G, PINK, X1 - 1.2, 21, 1.9)
      dot(G, PALE, X0 + 0.8, 28, 1.4); dot(G, PALE, X1 - 0.8, 28, 1.4)
      path(G, DUSK, 0.9, { X0 - 1, 40, 5, 37.6, 7.5, 40.4, 10, 37.6, 12.5, 40.4, 15, 37.6, X1 + 1, 40 })
    end },
    hp_m = { BLUE, function(G)
      rect(G, RED, X0 - 0.5, 19.5, 2.4, 5.5); rect(G, RED, X1 - 1.9, 19.5, 2.4, 5.5)
      below(G, SKY, 36.5, 0.9, 2, "wave")
    end },
    hp_l = { BLUE, function(G)
      rect(G, RED, X0 - 0.5, Y0, 2, 4.6); rect(G, RED, X1 - 1.5, Y0, 2, 4.6)
      for _, b in ipairs({ { 5, 28, 1.5 }, { 9.5, 26.2, 1.1 }, { 14, 28, 1.5 }, { 7.2, 31.2, 1 }, { 11.8, 31.2, 1 } }) do dot(G, SKY, b[1], b[2], b[3]) end
      below(G, SKY, 35.5, 1.4, 3.5, "bump")
    end },
    atk_s = { MOSS, function(G)
      for _, x in ipairs({ 4.2, 8.4, 12.6 }) do rect(G, KHAKI, x, Y0 - 1, 2.1, 7.6, 0.3) end
      rect(G, DEEP, X0, 29.6, X1 - X0, 2.2, 0)
      for _, y in ipairs({ 35.5, 38.5, 41.5 }) do path(G, DEEP, 0.7, { X0, y, 7, y + 0.5 }); path(G, DEEP, 0.7, { 12, y + 0.5, X1, y }) end
    end },
    atk_m = { MAUVE, function(G)
      for _, x in ipairs({ 4.2, 8.4, 12.6 }) do rect(G, KHAKI, x, Y0 - 1, 2.1, 6.6, 0.3) end
      rect(G, DEEP, X0 - 1, 35.5, 20, 12, 0)
      emblem(G, 9.5, 40.4, 10.4, 5.6)
    end },
    atk_l = { MOSS, function(G)
      for _, x in ipairs({ 4.2, 8.4, 12.6 }) do rect(G, KHAKI, x, Y0 - 1, 2.1, 6.6, 0.3) end
      rect(G, GOLD, X0, 25.4, X1 - X0, 1.2, 0); rect(G, KHAKI, X0, 27.8, X1 - X0, 1.2, 0)
      rect(G, DEEP, X0 - 1, 37.5, 20, 12, 0)
      emblem(G, 9.5, 41.2, 11.4, 6.2)
    end },
    def_s = { GREY, function(G)
      rect(G, CYAN, X0 - 0.4, 21.5, 1.6, 3, 0.3); rect(G, CYAN, X1 - 1.2, 21.5, 1.6, 3, 0.3)
      dot(G, DGREY, 6.2, 32.5, 1.9); dot(G, DGREY, 12.8, 32.5, 1.9)
      below(G, DGREY, 39, 2, 1, "bump")
    end },
    def_m = { GREY, function(G)
      col(G, LGREY)
      for i = 0, 8 do
        local t = i / 8
        circle(G, "fill", 3.4 + 6.1 * t, 19.2 + 6 * t, 0.55); circle(G, "fill", 15.6 - 6.1 * t, 19.2 + 6 * t, 0.55)
      end
      for _, y in ipairs({ 22, 26, 30, 34, 38 }) do rect(G, DGREY, X0 + 0.3, y, 1.4, 1.4, 0.2); rect(G, DGREY, X1 - 1.7, y, 1.4, 1.4, 0.2) end
      dot(G, DGREY, 6.4, 31, 1.6); dot(G, DGREY, 12.6, 31, 1.6)
      below(G, DGREY, 40.5, 1.6, 1, "bump")
    end },
    def_l = { GREY, function(G)
      below(G, DGREY, 21.2, 0.8, 2, "wave")
      rect(G, GREY, X0 - 1, 22.4, 20, 30, 0)
      dot(G, DGREY, X0 + 0.8, 27.5, 2.3); dot(G, DGREY, X1 - 0.8, 27.5, 2.3)
      dot(G, LGREY, X0 + 1, 34, 1.4); dot(G, LGREY, X1 - 1, 34, 1.4)
      tri(G, DGREY, 6, 33.5, 13, 33.5, 10.8, 40, 8.2, 40)
      rect(G, DGREY, 8.2, 39, 2.6, 9, 0)
      path(G, DDGREY, 0.6, { 6.6, 34.4, 12.4, 34.4 })
    end },
    spa_s = { MIST, function(G)
      col(G, LAV); G.ellipse("fill", 9.5, 17.6, 5.6, 3.8, 32)
      col(G, LILAC); G.ellipse("fill", 8.4, 17.4, 2.2, 1.2, 20)
      path(G, CRACK, 0.8, { X0 - 1, 35, 6, 33.2, 9, 33.8, 12.5, 30, X1 + 1, 28.6 })
      path(G, CRACK, 0.6, { 12.5, 30, 13.6, 33.4 })
      rect(G, YEL, 13.8, 32.4, 1.2, 2.2, 0.2)
    end },
    spa_m = { MIST, function(G)
      rect(G, SLATE, X0 - 1, 14, 20, 7.2, 0)
      rect(G, SLATE, X0 - 1, 41.5, 20, 8, 0)
      col(G, LAV); G.ellipse("fill", 9.5, 26.6, 3.4, 4.6, 32); G.ellipse("fill", 9.5, 35, 2.7, 3.6, 32)
      G.rectangle("fill", 8, 28, 3, 6)
      col(G, LILAC); G.ellipse("fill", 9.5, 35.4, 0.9, 1.6, 16)
      rect(G, YEL, X0 + 0.5, 27.6, 1.4, 2.8, 0.2); rect(G, YEL, X1 - 1.9, 27.6, 1.4, 2.8, 0.2)
    end },
    spa_l = { SLATE, function(G)
      tri(G, LAV, 7.2, 14, 11.8, 14, 11.8, 21, 9.5, 23.2, 7.2, 21)
      rect(G, MIST, 3.8, 28, 11.4, 15.4, 0.6)
      path(G, SLATE, 0.7, { 7, 28, 7, 43.4 }); path(G, SLATE, 0.7, { 12, 28, 12, 43.4 })
      path(G, SLATE, 0.8, { X0, 33.6, X1, 33.6 })
      for x = 4.2, 15, 1.5 do path(G, SLATE, 0.5, { x, 32.6, x, 34.6 }) end
      rect(G, YEL, X0 + 0.3, 32.6, 1.6, 2, 0.2); rect(G, YEL, X1 - 1.9, 32.6, 1.6, 2, 0.2)
    end },
    spd_s = { SAGE, function(G)
      rect(G, MUSTARD, X0 - 1, 18.4, 20, 2.6, 0)
      for x = X0 + 0.6, X1, 2.6 do dot(G, MUSTARD, x, 19.7, 1.6) end
      dot(G, SCARLET, X0 + 0.5, 26, 1.6); dot(G, SCARLET, X1 - 0.5, 26, 1.6)
      below(G, GREEN, 36.5, 3, 3, "spike")
    end },
    spd_m = { SAGE, function(G)
      rect(G, GREEN, 7, Y0 - 1, 1.5, 8.5, 0.3); rect(G, GREEN, 10.5, Y0 - 1, 1.5, 8.5, 0.3)
      rect(G, MUSTARD, X0 - 0.4, 23, 1.6, 4.6, 0.3); rect(G, MUSTARD, X1 - 1.2, 23, 1.6, 4.6, 0.3)
      below(G, GREEN, 38.5, 7.5, 2, "spike")
    end },
    spd_l = { AQUA, function(G)
      rect(G, BRICK, X0 - 1, 14, 20, 15, 0)
      rect(G, GREEN, X0 - 0.4, 18.6, 1.8, 2.8, 0.3); rect(G, GREEN, X1 - 1.4, 18.6, 1.8, 2.8, 0.3)
      rect(G, AQUA, 5.2, 21.2, 8.6, 7.2, 2)
      rect(G, GREEN, 6.4, 23.4, 1.8, 1.5, 0.3); rect(G, GREEN, 10.8, 23.4, 1.8, 1.5, 0.3)
      below(G, GREEN, 34, 2.4, 2.5, "spike")
      for _, d in ipairs({ { 6, 39.6 }, { 13, 39.6 }, { 9.5, 44 } }) do diamond(G, PINE, d[1], d[2], 3.6, 4.2) end
    end },
    spe_s = { NIGHT, function(G)
      tri(G, MAGENTA, X0 - 0.5, 14, X0 + 2.4, 14, X0 - 0.5, 22); tri(G, MAGENTA, X1 + 0.5, 14, X1 - 2.4, 14, X1 + 0.5, 22)
      rect(G, DUSK, 5.4, 22.2, 8.2, 5.4, 1.6)
      for _, x in ipairs({ 7, 9.5, 12 }) do dot(G, FANG, x, 23.4, 0.55) end
      rect(G, DUSK, 7.6, 38, 3.8, 10, 0.6)
    end },
    spe_m = { NIGHT, function(G)
      tri(G, MAGENTA, X0 - 0.5, 14, X0 + 2.4, 14, X0 - 0.5, 20); tri(G, MAGENTA, X1 + 0.5, 14, X1 - 2.4, 14, X1 + 0.5, 20)
      rect(G, DUSK, 4, 19.6, 11, 25, 3.2)
      tri(G, FANG, 6.2, 19.8, 7.8, 19.8, 7, 22.2); tri(G, FANG, 11.2, 19.8, 12.8, 19.8, 12, 22.2)
      tri(G, FANG, 6.2, 44.4, 7.8, 44.4, 7, 42); tri(G, FANG, 11.2, 44.4, 12.8, 44.4, 12, 42)
    end },
    spe_l = { PLUM, function(G)
      rect(G, DGREY, X0 - 1, 38.5, 20, 10, 0)
      rect(G, DGREY, 7.5, 13.6, 4, 5, 0.6)
      tri(G, MUSTARD, X0 + 0.6, 27, 6.8, 27.4, 6.2, 29.6, X0 + 1.2, 29.2)
      tri(G, MUSTARD, X1 - 0.6, 27, 12.2, 27.4, 12.8, 29.6, X1 - 1.2, 29.2)
      tri(G, FANG, 8, 33.4, 11, 33.4, 9.5, 31.2)
    end },
    strength = { C(156, 132, 25), function(G)
      local L = C(222, 197, 115)
      diamond(G, L, 9.5, 30.6, 5.6, 6.4)
      for _, d in ipairs({ { 5.4, 25.4 }, { 13.6, 25.4 }, { 5.4, 35.8 }, { 13.6, 35.8 } }) do diamond(G, L, d[1], d[2], 4.6, 5.4) end
    end },
    toughen_up = { C(16, 107, 189), function(G)
      for _, p in ipairs({ { 5.2, 25.6 }, { 10.4, 25.6 }, { 5.2, 31 }, { 10.4, 31 } }) do rect(G, C(115, 181, 222), p[1], p[2], 3.6, 3.6, 0.4) end
    end },
    swiftness = { PLUM, function(G)
      local L = C(181, 156, 189)
      for _, x in ipairs({ 5.5, 9.5, 13.5 }) do tri(G, L, x - 2, 38.2, x + 2, 38.2, x, 34.6) end
      for _, x in ipairs({ 7.5, 11.5 }) do tri(G, L, x - 2, 33.4, x + 2, 33.4, x, 29.8) end
    end },
    big_shot = { GREEN, function(G)
      for _, d in ipairs({ { 9.5, 31 }, { X0, 26 }, { X1, 26 }, { X0, 36 }, { X1, 36 } }) do dot(G, SAGE, d[1], d[2], 2.4) end
    end },
    double_up = { C(66, 66, 74), function(G)
      local Y = C(181, 156, 41)
      rect(G, Y, X0 - 1, 20.6, 20, 1.4, 0); rect(G, Y, X0 - 1, 40.6, 20, 1.4, 0)
      path(G, Y, 1.4, { 3.8, 30, 7.4, 35.4 }); path(G, Y, 1.4, { 7.4, 30, 3.8, 35.4 })
      path(G, Y, 1.6, { 9.2, 25.8, 14.3, 25.8, 14.3, 30, 9.4, 32.6, 9.4, 35.6, 14.6, 35.6 })
    end },
    team_flare = { C(173, 49, 33), function(G)
      rect(G, DDGREY, 3.6, 21, 11.8, 19.6, 1.5)
      rect(G, C(123, 123, 123), 4.6, 22, 9.8, 17.6, 1)
      col(G, C(173, 49, 33))
      fillShape(G, { 9.5, 23.6, 12.6, 27, 11.6, 30.2, 13.2, 31.8, 10.8, 38, 10.2, 33.8, 7.6, 36.6, 6.6, 30.4, 8.2, 28.6 })
    end },
    reset = { MIST },
    soothing = { C(222, 99, 123), function(G) rect(G, C(222, 173, 173), X0 - 1, 34, 20, 2.6, 0) end },
  }
  local PLAIN = C(66, 66, 74)
  gen("training/home_sand_bag", 20, 50, function(G) bag(G, PLAIN) end)
  gen("training/sand_bag_00", 20, 50, function(G) bag(G, PLAIN) end)
  for i, id in ipairs(Rules.GAME_ORDER) do
    local def = BAGS[id] or { C(120, 120, 130) }
    gen(("training/sand_bag_%02d"):format(i), 20, 50, function(G) bag(G, def[1], def[2]) end)
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
    -- the coin: a black edge, a gold rim, the face inside its own ring, a swirl, a glint
    col(G, P.ink); circle(G, "fill", 16, 12.6, 11.8)
    shadedDisc(G, 16, 12.6, 10.9, c255(222, 160, 18), c255(255, 234, 96))
    shadedDisc(G, 16, 12.6, 8.6, c255(248, 206, 40), c255(255, 252, 196))
    G.setLineWidth(0.7); col(G, c255(206, 146, 14)); circle(G, "line", 16, 12.6, 8.6)
    col(G, c255(220, 164, 30)); G.setLineWidth(1.8)
    local sw = {}
    for i = 0, 16 do
      local t = i / 16
      local u = 1 - t
      sw[#sw + 1] = u * u * u * 20.6 + 3 * u * u * t * 12 + 3 * u * t * t * 21 + t * t * t * 11.6
      sw[#sw + 1] = u * u * u * 8 + 3 * u * u * t * 8.6 + 3 * u * t * t * 16 + t * t * t * 17
    end
    G.line(sw)
    G.setColor(1, 1, 1, 0.8); G.ellipse("fill", 11.6, 7.6, 2.2, 1.3, 16)
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
    flexer(G, 16, 13.6, 1.08)
    col(G, P.white)
    for i = 0, 4 do star(G, 5.6 + i * 5.2, 25.4, 3) end
  end)
  gen("training/ss_perfect_icon2", 32, 32, function(G) flexer(G, 16, 16.6, 1.12) end)
  -- the medal count's tab: teal up to the top edge at the left, a dark rim stepping down from
  -- a third of the way along, the right end slanted, a soft shadow under it
  gen("training/ss_pokename_bg", 190, 40, function(G)
    -- (flush with the screen's top across its whole width: the dark rim and the grey band
    -- reach the top over the right part, where the teal starts lower)
    G.setColor(0, 0, 0, 0.25)
    fillShape(G, { 0, 0, 180, 0, 182, 25, 177, 33, 16, 36, 8, 33, 0, 9 })
    col(G, P.ink)
    fillShape(G, { 0, 0, 178.5, 0, 179.6, 4, 179, 21, 175, 28, 16, 32.5, 8, 29, 0, 6 })
    col(G, c255(68, 68, 72))
    fillShape(G, { 1.4, 0, 176.8, 0, 177.8, 4.6, 177.5, 21, 173.5, 26.8, 16.5, 31, 9.5, 28, 1.4, 6 })
    G.setColor(0.36, 0.42, 0.42, 1); G.rectangle("fill", 60, 0, 116, 2.2)
    local face = { 4, 0, 58, 0, 59, 4.5, 170, 4.5, 173, 6, 175.5, 21, 172, 25.5, 17, 29.5, 11, 27, 4, 6 }
    gradShape(G, face, 0, 0, 190, 30, c255(17, 214, 180), c255(10, 160, 140))
    -- the game's bright stripe every third row
    within(G, face, function()
      G.setColor(17 / 255, 230 / 255, 196 / 255, 0.55)
      for y = 1, 29, 3 do G.rectangle("fill", 0, y, 190, 1) end
    end)
  end)
  gen("training/ss_return", 30, 30, GEN["training/home_return"].draw)
  -- a course not open yet: a grey disc, crossed
  -- a course not open yet: a grey disc with a black edge, a bevelled rim lit from above, the
  -- face inside its dark ring, an embossed slash across it, a shadow under it
  gen("training/ss_stage_icon00", 64, 64, function(G)
    G.setColor(0, 0, 0, 0.3); G.ellipse("fill", 33, 35, 30.5, 29.5, 64)
    col(G, P.ink); circle(G, "fill", 32, 32, 30.6)
    G.stencil(function() circle(G, "fill", 32, 32, 29.2) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 2, 2, 60, 60, c255(190, 190, 196), c255(64, 64, 68))
    G.setStencilTest()
    G.setColor(0.15, 0.15, 0.17, 1); circle(G, "fill", 32, 32, 25.8)
    G.stencil(function() circle(G, "fill", 32, 32, 24.8) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 6, 6, 52, 52, c255(124, 124, 128), c255(94, 94, 98))
    G.setStencilTest()
    G.setLineWidth(0.6); G.setColor(1, 1, 1, 0.1); circle(G, "line", 32, 32, 23.4)
    col(G, c255(40, 50, 48)); stroke(G, 4.6, 21, 43, 43, 21)
    G.setColor(0.62, 0.7, 0.68, 0.7); G.setLineWidth(1.1); G.line(20.4, 41, 41, 20.4)
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
  -- (see-through teal, a brighter stripe every third row, a light line along its top, a faint
  -- dark then light line at its foot)
  gen("training/ss_stage_win", 10, 30, function(G)
    G.setBlendMode("replace")
    col(G, c255(17, 204, 170, 187)); G.rectangle("fill", 0, 1, 10, 27)
    col(G, c255(17, 221, 187, 187))
    for y = 1, 26, 3 do G.rectangle("fill", 0, y, 10, 1) end
    col(G, c255(17, 187, 153, 119)); G.rectangle("fill", 0, 0, 10, 1)
    col(G, c255(0, 119, 102, 51)); G.rectangle("fill", 0, 28, 10, 1)
    col(G, c255(119, 221, 221, 34)); G.rectangle("fill", 0, 29, 10, 1)
    G.setBlendMode("alpha")
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
      local C = deps.courses
      local version = deps.gameVersion and deps.gameVersion() or nil
      for _, c in ipairs((C and C.courses) or {}) do
        -- the version's line first; the final course's other line has a picture of its own
        local mine = (C.botsFor and C.botsFor(c, version)) or c.bots
        for _, bots in ipairs({ mine, c.bots, c.alphaBots or {} }) do
          local b = bots and bots[1]
          if b and b.art and not courseBot[b.art] then courseBot[b.art] = { bot = b, stat = c.stat } end
        end
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
        -- as bright as the stat's label: its own colour at the rim, lighter toward the light
        local hi = { ring[1] + (1 - ring[1]) * 0.45, ring[2] + (1 - ring[2]) * 0.45, ring[3] + (1 - ring[3]) * 0.45 }
        shadedDisc(G, 32, 32, 28.5, ring, hi)
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

  -- ------- the results screens' pieces (src/training/results.lua lays them out)

  -- the title bar's left half (the right half is this mirrored; results.lua stretches the
  -- plain teal at x 150 and keeps the inner end, so the tab stays at the middle): solid teal
  -- with a bright stripe every third row, darker inside along the left edge, the long chamfer
  -- and the foot; the rim round it a dark line, grey, a lighter grey, then dark and black,
  -- with a soft shadow; at the inner end a grey tab along the top
  local TITLE_TEAL = { 6.4, 0, 171, 0, 173.2, 2.6, 200, 2.6, 200, 24.4, 16.6, 24.4, 6.4, 9.2 }
  gen("training/res_title", 200, 30, function(G)
    local function rim(inset)
      local i = inset
      return roundPts({ i, 0, 200, 0, 200, 29 - i, 13.4 + i * 0.6, 29 - i, i, 7.4 + i * 0.4 }, 1.2,
        { [1] = true, [2] = true, [3] = true })
    end
    G.push(); G.translate(0, 0.9); G.setColor(0, 0, 0, 0.3); fillShape(G, rim(0)); G.pop()
    col(G, c255(0, 17, 17)); fillShape(G, rim(0))
    col(G, c255(17, 34, 34)); fillShape(G, rim(1))
    col(G, c255(85, 102, 102)); fillShape(G, rim(2))
    gradShape(G, rim(3), 0, 0, 200, 30, c255(72, 86, 86), c255(64, 68, 68))
    local teal = roundPts(TITLE_TEAL, 0.8, { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true })
    col(G, c255(17, 204, 170)); fillShape(G, teal)
    within(G, teal, function()
      G.setColor(17 / 255, 221 / 255, 187 / 255, 1)
      for y = 1, 24, 3 do G.rectangle("fill", 0, y, 200, 1) end
      -- the inner shadow: down the left edge and the chamfer, along the foot
      G.setLineJoin("bevel")
      G.setLineWidth(5.2); G.setColor(0, 170 / 255, 153 / 255, 0.55); G.line(6.4, -1, 6.4, 9.2, 16.6, 24.4)
      G.setLineWidth(2.6); G.setColor(0, 153 / 255, 153 / 255, 0.9); G.line(6.4, -1, 6.4, 9.2, 16.6, 24.4)
      vgrad(G, 0, 19.6, 200, 4, { 0, 170 / 255, 153 / 255, 0 }, { 0, 153 / 255, 153 / 255, 1 })
      G.setColor(17 / 255, 119 / 255, 136 / 255, 1); G.rectangle("fill", 0, 23.6, 200, 1)
      scan(G, 0, 0, 200, 25, 0.04, 1)
    end)
    -- the tab at the inner end
    local tab = { 171, 0, 200, 0, 200, 2.6, 173.2, 2.6 }
    gradShape(G, tab, 170, 0, 30, 2.6, c255(85, 102, 102), c255(51, 68, 68))
    G.setLineWidth(0.5); G.setColor(34 / 255, 85 / 255, 68 / 255, 1); G.line(173.2, 2.4, 200, 2.4)
  end)

  -- a stat row's plate: dark glass, rounded at the left, a bevelled point at the right; drawn in
  -- three parts (x 0..30, the column at 30 stretched, 31..64)
  gen("training/res_row", 64, 26, function(G)
    local outer = roundPts({ 0, 0.6, 52, 0.6, 63.6, 13, 52, 25.4, 0, 25.4 }, 1.6)
    local inner = roundPts({ 1.2, 1.8, 51.4, 1.8, 61.8, 13, 51.4, 24.2, 1.2, 24.2 }, 1.2)
    G.setBlendMode("replace")
    col(G, c255(10, 16, 24, 190)); fillShape(G, outer)
    gradShape(G, inner, 0, 1.8, 64, 22.4, c255(44, 56, 70, 168), c255(18, 24, 34, 168))
    G.setBlendMode("alpha")
    within(G, inner, function()
      scan(G, 0, 1.8, 64, 22.4, 0.05, 1)
      G.setColor(1, 1, 1, 0.1); G.polygon("fill", 51.4, 1.8, 61.8, 13, 51.4, 13)
      G.setColor(0, 0, 0, 0.18); G.polygon("fill", 51.4, 13, 61.8, 13, 51.4, 24.2)
    end)
    G.setLineWidth(0.6); G.setColor(1, 1, 1, 0.3); G.line(2.4, 2.5, 51.2, 2.5, 60.8, 12.6)
  end)

  -- the course's medallion frame: a steel ring, dark rays round it, a teal light on its rim
  gen("training/res_frame", 72, 72, function(G)
    for i = 0, 23 do
      local a0, a1 = i * math.pi / 12, i * math.pi / 12 + math.pi / 24
      G.setColor(0.08, 0.12, 0.16, 0.45)
      G.polygon("fill", 36 + math.cos(a0) * 27, 36 + math.sin(a0) * 27, 36 + math.cos(a0) * 35.5, 36 + math.sin(a0) * 35.5,
        36 + math.cos(a1) * 35.5, 36 + math.sin(a1) * 35.5, 36 + math.cos(a1) * 27, 36 + math.sin(a1) * 27)
    end
    col(G, P.ink); circle(G, "fill", 36, 36, 31)
    shadedDisc(G, 36, 36, 29.4, c255(64, 66, 72), c255(206, 208, 214))
    col(G, c255(16, 20, 26)); circle(G, "fill", 36, 36, 25.2)
    neon(G, 0.7, P.tealHi, 0.75, (function()
      local pts = {}
      for i = 0, 48 do pts[#pts + 1] = 36 + math.cos(i * math.pi / 24) * 30.2; pts[#pts + 1] = 36 + math.sin(i * math.pi / 24) * 30.2 end
      return pts
    end)(), false)
  end)

  -- the time window: teal glass hung from the screen's top, its left foot rounded, a steel
  -- bracket down its right side
  gen("training/res_timewin", 200, 60, function(G)
    local glass = roundPts({ 0, 0, 188, 0, 188, 56, 7, 56, 0, 49 }, 3, { [1] = true, [2] = true })
    G.setLineJoin("bevel")
    for i = 3, 1, -1 do col(G, P.tealHi, 0.07 * (4 - i)); G.setLineWidth(i * 1.3); G.line(closed(glass)) end
    G.setBlendMode("replace")
    gradShape(G, glass, 0, 0, 188, 56, c255(110, 240, 222, 225), c255(30, 196, 174, 215))
    G.setBlendMode("alpha")
    local panel = roundPts({ 6, 4, 182, 4, 182, 51, 10, 51, 6, 47 }, 2.4)
    within(G, glass, function()
      scan(G, 0, 0, 188, 56, 0.06, 1.1)
      vgrad(G, 0, 0, 188, 8, { 1, 1, 1, 0.3 }, { 1, 1, 1, 0 })
    end)
    G.setLineWidth(0.7); G.setColor(1, 1, 1, 0.55); G.line(closed(panel))
    rimLight(G, glass, 0.8)
    local bracket = roundPts({ 185, 0, 196, 0, 200, 5, 200, 52, 196, 57, 185, 57 }, 1.4, { [1] = true, [2] = true })
    col(G, P.ink); fillShape(G, bracket)
    gradShape(G, roundPts({ 186.4, 0, 195.4, 0, 198.8, 5.4, 198.8, 51.6, 195.4, 55.6, 186.4, 55.6 }, 1.2, { [1] = true, [2] = true }),
      186, 0, 14, 57, c255(150, 154, 160), c255(60, 64, 70))
    screw(G, 192.6, 12, 1.8); screw(G, 192.6, 45, 1.8)
  end)

  -- the band across the touch screen (stretched sideways): a darker strip for its words over
  -- lighter teal fading down, lit edges
  gen("training/res_band", 32, 40, function(G)
    G.setBlendMode("replace")
    vgrad(G, 0, 0, 32, 20, c255(14, 104, 104, 225), c255(16, 120, 116, 215))
    vgrad(G, 0, 20, 32, 20, c255(70, 220, 200, 190), c255(30, 180, 160, 110))
    G.setBlendMode("alpha")
    scan(G, 0, 0, 32, 40, 0.06, 1.1)
    G.setColor(0.75, 1, 0.97, 0.7); G.rectangle("fill", 0, 0, 32, 0.8)
    G.setColor(0.75, 1, 0.97, 0.45); G.rectangle("fill", 0, 19.6, 32, 0.6)
  end)

  -- the bags banner: lime glass across the screen, its top stepping down to the right, its
  -- foot stepping down further along
  gen("training/res_banner", 340, 62, function(G)
    local band = { 0, 1, 213, 1, 220, 7, 340, 7, 340, 61, 110, 61, 103, 54, 0, 54 }
    G.setBlendMode("replace")
    gradShape(G, band, 0, 1, 340, 60, c255(214, 244, 130, 205), c255(160, 210, 70, 195))
    G.setBlendMode("alpha")
    within(G, band, function()
      scan(G, 0, 0, 340, 62, 0.07, 1.1)
      vgrad(G, 0, 1, 340, 8, { 1, 1, 1, 0.3 }, { 1, 1, 1, 0 })
    end)
    G.setLineJoin("bevel")
    G.setLineWidth(0.9); G.setColor(0.3, 0.4, 0.12, 0.85)
    G.line(0, 1.4, 213, 1.4, 220, 7.4, 340, 7.4)
    G.line(0, 53.6, 103, 53.6, 110, 60.6, 340, 60.6)
    G.setLineWidth(0.5); G.setColor(1, 1, 0.85, 0.55)
    G.line(0, 2.6, 212.5, 2.6, 219.5, 8.6, 340, 8.6)
  end)

  -- the hooked up-arrow (the results' gauge and the trained row): white, a dark outline; the
  -- stem turns to the right at its foot
  gen("training/res_arrow", 10, 20, function(G)
    local head = { 5, 0.8, 9.4, 6.6, 6.6, 6.6, 3.4, 6.6, 0.6, 6.6 }
    local stem = { 5, 6, 5, 15.8, 9, 15.8 }
    G.setLineJoin("miter")
    col(G, c255(14, 20, 34)); G.setLineWidth(4.6); G.line(stem)
    G.polygon("fill", 5, -0.8, 11.2, 7.6, -1.2, 7.6)
    col(G, P.white); G.setLineWidth(2.4); G.line(stem)
    G.polygon("fill", head[1], head[2], head[3], head[4], head[9], head[10])
    G.setColor(0.75, 0.85, 1, 0.6); G.setLineWidth(0.5); G.line(4.2, 7, 4.2, 15)
  end)

  -- the regimen HUD's top corner (the left one; the right is this mirrored): a dark charcoal
  -- wedge with a grey edge outside, the teal band sloping down to the screen's edge with its
  -- lit upper edge and darker foot, a fine texture; the teal meets the lip at the inner end
  local CORNER_TEAL = { 0, 9.6, 60, 5, 72, 0, 80, 0, 80, 2.4, 68, 2.4, 54, 9.6, 0, 17.6 }
  gen("training/hud_corner", 80, 20, function(G)
    local dark = roundPts({ 0, 0, 73, 0, 60.4, 5.4, 0, 10 }, 0.8, { [1] = true, [2] = true, [4] = true })
    gradShape(G, dark, 0, 0, 74, 10, c255(52, 58, 64), c255(22, 26, 30))
    G.setLineJoin("bevel"); G.setLineWidth(0.6); G.setColor(0.55, 0.58, 0.62, 0.9)
    G.line(73, 0.2, 60.4, 5.4, 0, 10)
    gradShape(G, CORNER_TEAL, 0, 0, 80, 12, c255(96, 232, 210, 240), c255(22, 160, 146, 240))
    within(G, CORNER_TEAL, function()
      scan(G, 0, 0, 80, 12, 0.08, 0.8)
      grain(G, 0, 0, 80, 12, 0.05, 61)
    end)
    G.setLineWidth(0.5); G.setColor(0.8, 1, 0.96, 0.75); G.line(0, 10.2, 60.2, 5.6, 72.4, 0.5, 80, 0.5)
    G.setLineWidth(0.6); G.setColor(0.02, 0.32, 0.3, 0.8); G.line(0, 17.3, 54, 9.3, 68, 2.1, 80, 2.1)
  end)
  -- the lip along the top between the corners (stretched across): the same teal, lit on top
  gen("training/hud_lip", 8, 3, function(G)
    vgrad(G, 0, 0, 8, 2.4, c255(110, 236, 214, 240), c255(30, 170, 154, 240))
    G.setColor(0.8, 1, 0.96, 0.75); G.rectangle("fill", 0, 0.3, 8, 0.45)
    G.setColor(0.02, 0.32, 0.3, 0.8); G.rectangle("fill", 0, 1.8, 8, 0.6)
  end)

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
  -- the shield's target (Wooble's Graveler capture): a lime-yellow ring with four spikes out on
  -- the diagonals, glowing, a faint light inside
  gen("lyt/st_hud/barrier_target", 32, 32, function(G)
    G.setLineStyle("smooth")
    for pass = 1, 2 do
      local glow = pass == 1
      G.setColor(0.82, 1, 0.2, glow and 0.35 or 1)
      G.setLineWidth(glow and 4.2 or 1.8)
      circle(G, "line", 16, 16, 8.2)
      for q = 0, 3 do
        local a = math.pi / 4 + q * math.pi / 2
        local ca, sa = math.cos(a), math.sin(a)
        local px, py = -sa, ca
        local w = glow and 3.6 or 2.6
        G.polygon("fill", 16 + ca * 7 + px * w, 16 + sa * 7 + py * w, 16 + ca * 7 - px * w, 16 + sa * 7 - py * w,
          16 + ca * (glow and 15.5 or 14.5), 16 + sa * (glow and 15.5 or 14.5))
      end
    end
    G.setColor(0.95, 1, 0.75, 0.35)
    circle(G, "fill", 16, 16, 5)
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

  -- the kit, for the other screens' drawn art (src/amie/ui_art.lua adds its ids with gen)
  U.gen = gen
  U.kit = { c255 = c255, col = col, circle = circle, vgrad = vgrad, shadedDisc = shadedDisc, stroke = stroke,
    font = font, outlined = outlined, roundPts = roundPts, fillShape = fillShape, within = within,
    gradShape = gradShape, closed = closed, grain = grain }

  function U.has(id) return GEN[id] ~= nil end
  function U.ids()
    local out = {}
    for id in pairs(GEN) do out[#out + 1] = id end
    table.sort(out)
    return out
  end

  return U
end
