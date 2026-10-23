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
    local n = 10
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
    col(G, P.ink)
    circle(G, "fill", cx, cy, r)
    shadedDisc(G, cx, cy, r * 0.9, P.rim, P.silver)
    shadedDisc(G, cx, cy, r * 0.74, P.limeLo, P.limeHi)
    G.setColor(1, 1, 1, 0.35)
    G.ellipse("fill", cx - r * 0.18, cy - r * 0.38, r * 0.42, r * 0.2, 24)
  end

  -- ------- the generators: id -> { w, h, draw(G, w, h) } in the texture's own units

  local GEN = {}
  local function gen(id, w, h, draw) GEN[id] = { w = w, h = h, draw = draw } end

  -- the top frame's left half (mirrored for the right): the bolted steel plate at the left,
  -- the dark rim along the teal name band, the band, and the light-blue wire under it
  gen("training/home_bg03", 160, 60, function(G)
    col(G, P.ink)
    G.polygon("fill", 10, 0, 100, 0, 96, 15, 98, 30, 160, 31, 160, 36, 98, 36, 92, 40, 38, 49, 33, 49, 25, 28, 28, 25)
    col(G, P.dark)
    G.polygon("fill", 13, 0, 96, 0, 93, 15, 95, 32, 90, 37, 40, 45, 35, 45, 28, 27, 30, 24)
    col(G, P.steel)
    G.polygon("fill", 20, 0, 82, 0, 92, 30, 87, 37, 40, 41, 37, 40, 33, 25)
    col(G, P.steelHi)
    G.setLineWidth(1)
    G.line(20, 0.5, 82, 0.5)
    G.line(82, 0.5, 91.5, 29)
    col(G, P.dark, 0.85)
    for _, b in ipairs({ { 73, 13 }, { 65, 26 }, { 81, 29 } }) do circle(G, "fill", b[1], b[2], 2.6) end
    G.setLineWidth(2)
    G.line(37, 33, 39, 39)
    -- the teal name band, its stripes darkening downward
    vgrad(G, 96, 0, 64, 30, P.tealHi, P.tealLo)
    col(G, P.ink)
    G.polygon("fill", 96, 0, 100, 0, 95, 15, 97, 30, 94, 30, 92, 15)
    col(G, P.white, 0.10)
    for y = 2, 28, 3 do G.rectangle("fill", 97, y, 63, 1) end
    col(G, P.wire)
    stroke(G, 1.6, 100, 47, 145, 47, 152, 42, 160, 42)
    stroke(G, 1.6, 152, 55, 160, 55)
  end)

  -- the bottom tray's left half: the dark plate, the teal panel behind its diagonal edge
  gen("training/home_bg02", 160, 60, function(G)
    col(G, P.ink)
    G.polygon("fill", 0, 7, 90, 17, 93, 22, 160, 26, 160, 60, 0, 60)
    col(G, P.plate)
    G.polygon("fill", 0, 9, 89, 19, 92, 24, 160, 28, 160, 60, 0, 60)
    -- the teal panel, framed in steel
    col(G, P.rim)
    G.polygon("fill", 74, 21, 92, 22, 96, 27, 160, 30, 160, 60, 52, 60)
    local m = G.newMesh({ { 77, 25, 0, 0, P.tealHi[1], P.tealHi[2], P.tealHi[3], 1 }, { 160, 33, 0, 0, P.tealHi[1], P.tealHi[2], P.tealHi[3], 1 },
      { 160, 60, 0, 0, P.teal[1], P.teal[2], P.teal[3], 1 }, { 57, 60, 0, 0, P.teal[1], P.teal[2], P.teal[3], 1 } }, "fan", "static")
    G.setColor(1, 1, 1, 1)
    G.draw(m)
    col(G, P.white, 0.10)
    for y = 34, 58, 3 do G.rectangle("fill", 70, y, 90, 1) end
    col(G, P.tealDeep)
    G.setLineWidth(2)
    G.line(78, 30, 84, 30); G.line(78, 30, 76, 34)
    G.line(72, 41, 80, 41); G.line(72, 41, 74, 36)
    col(G, P.wire)
    stroke(G, 1.6, 100, 15, 145, 18, 152, 12, 160, 10)
  end)

  -- the perspective grid (drawn white; the layout tints and fades it)
  gen("training/home_bg01", 320, 120, function(G)
    G.setColor(1, 1, 1, 1)
    G.setLineWidth(1.4)
    for i = -12, 12 do
      local xb = 160 + i * 22
      G.line(160 + i * 17, 0, xb, 120)
    end
    local y = 2
    local step = 8
    while y < 120 do
      G.line(0, y, 320, y)
      y = y + step
      step = step * 1.06
    end
  end)

  -- the + mark the backdrop tiles
  gen("training/home_bg_ptn", 32, 32, function(G)
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 14.5, 9, 3, 14, 1, 1)
    G.rectangle("fill", 9, 14.5, 14, 3, 1, 1)
  end)

  -- the PlayNav strip: steel stripes, its ends deeper than its middle, a white stepped edge
  gen("training/home_strip", 160, 30, function(G)
    vgrad(G, 0, 0, 160, 30, c255(222, 224, 230), c255(150, 154, 162))
    G.setBlendMode("replace")
    G.setColor(0, 0, 0, 0)
    G.polygon("fill", 30, 24, 160, 24, 160, 30, 24, 30)
    G.setBlendMode("alpha")
    col(G, P.white, 0.18)
    for y = 3, 22, 4 do G.rectangle("fill", 0, y, 160, 1) end
    col(G, P.white)
    stroke(G, 1.4, 0, 29, 24, 29, 30, 23.5, 160, 23.5)
  end)

  -- the round buttons
  gen("training/btn_return", 48, 48, function(G)
    limeButton(G, 24, 24, 23)
    returnGlyph(G, 24, 25, 1.1, P.ink)
  end)
  gen("training/home_return", 30, 30, function(G)
    col(G, P.ink); circle(G, "fill", 15, 15, 14.5)
    shadedDisc(G, 15, 15, 13.2, c255(150, 156, 170), P.white)
    shadedDisc(G, 15, 15, 10.5, c255(200, 220, 245), P.white)
    returnGlyph(G, 15, 15.5, 0.62, P.blue)
  end)
  gen("training/btn_bags", 48, 48, function(G)
    limeButton(G, 24, 24, 23)
    bagGlyph(G, 24, 24, 0.85, P.ink)
  end)
  -- the Regimens tab: a lime pill along the bottom left with a ball and a runner on it
  gen("training/btn_regimens", 64, 64, function(G)
    col(G, P.ink); G.rectangle("fill", -12, 14, 74, 44, 22, 22)
    col(G, P.silver); G.rectangle("fill", -10, 16, 70, 40, 20, 20)
    G.setColor(1, 1, 1, 1)
    local m = G.newMesh({ { -7, 19, 0, 0, P.limeHi[1], P.limeHi[2], P.limeHi[3], 1 }, { 57, 19, 0, 0, P.lime[1], P.lime[2], P.lime[3], 1 },
      { 57, 53, 0, 0, P.limeLo[1], P.limeLo[2], P.limeLo[3], 1 }, { -7, 53, 0, 0, P.limeLo[1], P.limeLo[2], P.limeLo[3], 1 } }, "fan", "static")
    G.stencil(function() G.rectangle("fill", -7, 19, 64, 34, 17, 17) end, "replace", 1)
    G.setStencilTest("greater", 0)
    G.draw(m)
    G.setStencilTest()
    ballGlyph(G, 18, 36, 9, P.ink)
    col(G, P.ink)
    circle(G, "fill", 42, 27, 3.2)
    stroke(G, 2.6, 42, 30, 40, 38, 35, 45)
    stroke(G, 2.6, 40, 38, 46, 44)
    stroke(G, 2.2, 41, 32, 47, 35)
    stroke(G, 2.2, 41, 32, 36, 34)
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
  end)
  gen("training/list_win", 32, 32, function(G)
    col(G, P.ink); G.rectangle("fill", 0, 0, 70, 70, 10, 10)
    col(G, c255(102, 119, 119)); G.rectangle("fill", 3, 3, 70, 70, 8, 8)
    G.setBlendMode("replace")
    col(G, c255(187, 255, 255, 68)); G.rectangle("fill", 7, 7, 70, 70, 6, 6)
    col(G, GLASS); G.rectangle("fill", 10, 10, 70, 70, 5, 5)
    G.setBlendMode("alpha")
  end)
  gen("training/meter_bar", 180, 30, function(G)
    col(G, P.ink); G.rectangle("fill", 1, 5, 178, 20, 10, 10)
    G.stencil(function() G.rectangle("fill", 3, 7, 174, 16, 8, 8) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 3, 7, 174, 16, P.limeHi, P.limeLo)
    G.setStencilTest()
    G.setColor(1, 1, 1, 0.45); G.rectangle("fill", 10, 9, 160, 3, 1.5, 1.5)
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
    col(G, P.teal, 0.85); G.polygon("fill", hex)
    col(G, P.tealHi, 0.45); G.polygon("fill", inner)
    col(G, P.tealHi, 0.8); G.setLineWidth(1.2)
    for i = 0, 2 do
      local a = -math.pi / 2 + i * math.pi / 3
      G.line(cx + math.cos(a) * r, cy + math.sin(a) * r, cx - math.cos(a) * r, cy - math.sin(a) * r)
    end
    G.polygon("line", inner)
    col(G, P.tealHi); G.setLineWidth(2.4); G.polygon("line", hex)
    -- the total's track at the right, wired to the hexagon's corner
    col(G, P.tealDeep); G.rectangle("fill", 140, 1, 6, 132, 2, 2)
    col(G, P.tealHi); G.setLineWidth(1.2); G.rectangle("line", 140, 1, 6, 132, 2, 2)
    stroke(G, 1.2, 143, 133, 143, 138, 112, 138, cx + r * 0.87, cy + r * 0.5)
  end)

  -- the stat labels: the stat's name in outlined block letters
  local LABELS = { hp = "HP", atk = "ATTACK", def = "DEFENSE", spa = "SP. ATK", spd = "SP. DEF", spe = "SPEED" }
  local LABEL_RGB = { hp = c255(196, 236, 60), atk = c255(252, 196, 40), def = c255(252, 150, 40),
    spa = c255(120, 196, 255), spd = c255(96, 156, 246), spe = c255(236, 120, 240) }
  for stat, word in pairs(LABELS) do
    gen("training/label_" .. stat, 64, 20, function(G)
      outlined(G, word, 32, 10, 11, LABEL_RGB[stat], P.ink, 1.1, 60)
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
  local function plate(G, fill, hi)
    col(G, P.ink); G.polygon("fill", 10, 1, 49, 1, 49, 39, 3, 39, 1, 36)
    col(G, P.steel); G.polygon("fill", 11, 3, 47, 3, 47, 37, 5, 37, 3, 34)
    -- the face is see-through, as the game's (about 80%)
    local a = 0.8
    local m = G.newMesh({ { 13, 5, 0, 0, hi[1], hi[2], hi[3], a }, { 45, 5, 0, 0, hi[1], hi[2], hi[3], a },
      { 45, 35, 0, 0, fill[1], fill[2], fill[3], a }, { 7, 35, 0, 0, fill[1], fill[2], fill[3], a } }, "fan", "static")
    G.setBlendMode("replace")
    G.setColor(1, 1, 1, 1); G.draw(m)
    G.setBlendMode("alpha")
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
    plate(G, c255(120, 122, 128), c255(150, 152, 158))
    col(G, P.dark, 0.6); G.setLineWidth(1.4)
    G.line(10, 22, 30, 22, 34, 18, 45, 18)
  end)
  gen("training/home_perfect_win02", 50, 40, function(G)
    plate(G, P.tealLo, P.tealHi)
    flexer(G, 26, 21, 1.05)
  end)
  gen("training/home_s_perfect_win", 50, 40, function(G)
    plate(G, P.tealLo, P.tealHi)
    flexer(G, 26, 17, 0.9)
    col(G, P.white)
    for i = 0, 4 do star(G, 14 + i * 6, 31, 2.7) end
  end)
  gen("training/home_shot_win", 50, 40, function(G)
    col(G, P.ink); G.polygon("fill", 1, 1, 49, 1, 49, 39, 10, 39)
    local m = G.newMesh({ { 4, 3, 0, 0, P.tealHi[1], P.tealHi[2], P.tealHi[3], 1 }, { 47, 3, 0, 0, P.tealHi[1], P.tealHi[2], P.tealHi[3], 1 },
      { 47, 37, 0, 0, P.tealLo[1], P.tealLo[2], P.tealLo[3], 1 }, { 11, 37, 0, 0, P.tealLo[1], P.tealLo[2], P.tealLo[3], 1 } }, "fan", "static")
    G.setColor(1, 1, 1, 1); G.draw(m)
    col(G, P.white, 0.12)
    for y = 5, 35, 3 do G.rectangle("fill", 4, y, 43, 1) end
  end)

  -- the shot types: a white ball with the type's patches, and its speed lines
  local SHOT = { black = c255(40, 40, 46), blue = c255(40, 120, 230), orange = c255(250, 140, 30),
    yellow = c255(240, 200, 30), green = c255(40, 170, 70) }
  for name, c in pairs(SHOT) do
    gen("training/shot_" .. name, 32, 32, function(G)
      col(G, c, 0.8); G.setLineWidth(1.5)
      G.line(2, 20, 9, 18); G.line(1, 25, 9, 22); G.line(4, 29, 11, 25)
      col(G, P.ink); circle(G, "fill", 19, 15, 11)
      shadedDisc(G, 19, 15, 10, c255(200, 205, 215), P.white)
      ballGlyph(G, 19, 15, 6, c)
      col(G, c)
      for i = 0, 4 do
        local a = -math.pi / 2 + i * 2 * math.pi / 5
        circle(G, "fill", 19 + math.cos(a) * 9, 15 + math.sin(a) * 9, 2.2)
      end
    end)
  end

  -- the mood bubbles: a teal screen on a stalk with its face
  local function bubble(G)
    col(G, P.steelHi); G.setLineWidth(2); G.line(9, 26, 6, 31)
    col(G, P.steelHi); G.rectangle("fill", 2, 3, 28, 23, 3, 3)
    G.setBlendMode("replace")
    vgrad(G, 4, 5, 24, 19, c255(0, 161, 161, 204), c255(0, 132, 132, 204))
    G.setBlendMode("alpha")
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
    col(G, P.steelHi); G.setLineWidth(1.2)
    G.line(10, 0.5, 3, 11); G.line(10, 0.5, 17, 11); G.line(10, 0.5, 10, 9)
    col(G, P.ink); G.rectangle("fill", 1, 9, 18, 40.5, 4.5, 4.5)
    col(G, fill); G.rectangle("fill", 2.3, 10.3, 15.4, 38, 3.5, 3.5)
    -- light on the left, shade on the right
    G.setColor(1, 1, 1, 0.22); G.rectangle("fill", 3.5, 12, 3, 34, 1.5, 1.5)
    G.setColor(0, 0, 0, 0.18); G.rectangle("fill", 14, 12, 2.5, 34, 1.2, 1.2)
    G.setColor(0, 0, 0, 0.35); G.rectangle("fill", 2.3, 13, 15.4, 2)
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
  -- a concave outline filled (triangulated), or used as a stencil for a gradient
  local function fillShape(G, pts)
    for _, t in ipairs(love.math.triangulate(pts)) do G.polygon("fill", t) end
  end
  local function gradShape(G, pts, x, y, w, h, top, bottom)
    G.stencil(function() fillShape(G, pts) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, x, y, w, h, top, bottom)
    G.setStencilTest()
  end
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
