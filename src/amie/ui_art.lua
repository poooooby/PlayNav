-- Pokemon-Amie's room drawn by the engine: each id the room asks Assets for (the scalloped
-- frame, the menu's PLAY / DECORATE / SWITCH buttons and its dim, the bubbles over the
-- Pokemon, the hearts, the visitors' talk bubbles, the gift box, the shadow) is drawn here
-- once at the texture's own size, through Super Training's maker (src/training/ui_art.lua:
-- gen, the kit). The room keeps its layout and animation: only where the pixels come from
-- changes.

return function(mod, K, gen)
  local c255, col, circle, vgrad = K.c255, K.col, K.circle, K.vgrad
  local fillShape, within, closed, outlined, font = K.fillShape, K.within, K.closed, K.outlined, K.font

  local C = {
    lilac = c255(212, 187, 245), lilacRim = c255(172, 148, 214), lilacHi = c255(232, 214, 252),
    cream = c255(241, 241, 191), creamHi = c255(250, 250, 205), creamLo = c255(228, 228, 176),
    pinkRim = c255(198, 36, 98), pinkBand = c255(252, 226, 236), pinkA = c255(247, 176, 204),
    pinkB = c255(252, 214, 228), magenta = c255(200, 16, 100),
    greenRim = c255(44, 128, 62), greenBand = c255(236, 250, 230), greenA = c255(196, 238, 186),
    greenB = c255(226, 248, 218), greenInk = c255(20, 92, 62),
    heart = c255(240, 70, 128), heartHi = c255(255, 150, 182), heartLo = c255(206, 34, 96),
    white = c255(255, 255, 255), ink = c255(64, 64, 70), grey = c255(98, 98, 104),
    blue = c255(36, 112, 204), orange = c255(246, 150, 28), orangeHi = c255(255, 214, 90),
  }

  -- ------- shapes

  -- a closed outline whose radius follows r(theta) about (cx, cy), squashed to rx / ry
  local function radial(cx, cy, rx, ry, n, rf)
    local pts = {}
    for i = 0, n - 1 do
      local a = i / n * math.pi * 2
      local k = rf(a)
      pts[#pts + 1] = cx + math.cos(a) * rx * k
      pts[#pts + 1] = cy + math.sin(a) * ry * k
    end
    return pts
  end
  -- an oval with scalloped edges (bumps outward, cusps between)
  local function scallop(cx, cy, rx, ry, bumps, amp)
    return radial(cx, cy, rx, ry, bumps * 12, function(a)
      return 1 - amp + amp * math.abs(math.sin(a * bumps / 2))
    end)
  end
  -- a soft-lobed blob (the bubbles' cloud)
  local function lobes(cx, cy, r, n, amp, turn)
    return radial(cx, cy, r, r, n * 16, function(a) return 1 + amp * math.cos(n * (a + (turn or 0))) end)
  end
  -- a heart: the classic curve, centred on (cx, cy), w across
  local function heartPts(cx, cy, w, h)
    local pts = {}
    for i = 0, 47 do
      local t = i / 48 * math.pi * 2
      local x = 16 * math.sin(t) ^ 3
      local y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
      pts[#pts + 1] = cx + x / 32 * w
      pts[#pts + 1] = cy - (y + 2) / 30 * h
    end
    return pts
  end
  local function scaled(pts, cx, cy, k)
    local out = {}
    for i = 1, #pts, 2 do
      out[i] = cx + (pts[i] - cx) * k
      out[i + 1] = cy + (pts[i + 1] - cy) * k
    end
    return out
  end
  local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
      (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t }
  end
  -- a shape filled from its edge colour to its middle's, in rings (a soft radial shade)
  local function rings(G, pts, cx, cy, edge, mid, steps, inner)
    steps = steps or 12
    for i = 0, steps do
      local t = i / steps
      col(G, mix(edge, mid, t))
      fillShape(G, scaled(pts, cx, cy, 1 - t * (1 - (inner or 0.35))))
    end
  end
  -- a glossy heart (button, bubbles, particles)
  local function glossHeart(G, cx, cy, w, h, line)
    local pts = heartPts(cx, cy, w, h)
    if line then
      col(G, line); fillShape(G, scaled(pts, cx, cy - h * 0.05, 1.16))
    end
    within(G, pts, function()
      vgrad(G, cx - w, cy - h * 0.6, w * 2, h * 1.2, C.heartHi, C.heartLo)
      G.setColor(1, 1, 1, 0.25)
      G.ellipse("fill", cx - w * 0.12, cy - h * 0.2, w * 0.36, h * 0.24)
    end)
    G.setColor(1, 1, 1, 0.92)
    G.ellipse("fill", cx + w * 0.22, cy - h * 0.24, w * 0.09, h * 0.08)
  end
  -- text a little heavier than the font: the fill drawn three times across
  local function heavy(G, text, cx, cy, size, fill, line, ow, track)
    local f = font(size)
    G.setFont(f)
    local tw = 0
    for ch in text:gmatch(".") do tw = tw + f:getWidth(ch) + (track or 0) end
    tw = tw - (track or 0)
    local x0 = cx - tw / 2
    local y = cy - f:getHeight() / 2
    local function pass(c, d, offs)
      col(G, c)
      local x = x0
      for ch in text:gmatch(".") do
        for _, o in ipairs(offs) do G.print(ch, x + o[1] * d, y + o[2] * d) end
        x = x + f:getWidth(ch) + (track or 0)
      end
    end
    pass(line, ow, { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 },
      { -1.3, 0 }, { 1.3, 0 }, { 0, 1.3 } })
    pass(fill, 0.28, { { -1, 0 }, { 0, 0 }, { 1, 0 } })
  end

  -- ------- the frame: the room seen through a scalloped window, a lilac lace round it.
  -- One quarter (the pane mirrors it four ways): the window's middle is the bottom-left corner,
  -- its edge a ring of bumps with a dot in each.
  local FRAME_R, FRAME_BUMPS = 116.5, 16
  local function frameWindow(G, grow)
    circle(G, "fill", 0, 128, FRAME_R + grow)
    local br = FRAME_R * math.sin(math.pi / 4 / FRAME_BUMPS) * 1.12
    for i = 0, FRAME_BUMPS - 1 do
      local a = (i + 0.5) / FRAME_BUMPS * math.pi / 2
      circle(G, "fill", math.sin(a) * FRAME_R, 128 - math.cos(a) * FRAME_R, br + grow)
    end
  end
  gen("lyt/amie_room/frame", 128, 128, function(G)
    -- the lace outside the window: a darker lip on its edge, light just past it
    G.stencil(function() frameWindow(G, 0) end, "replace", 1)
    G.setStencilTest("equal", 0)
    col(G, C.lilac); G.rectangle("fill", 0, 0, 128, 128)
    col(G, C.lilacHi, 0.5); frameWindow(G, 2.4)
    col(G, C.lilacRim); frameWindow(G, 1.3)
    G.setStencilTest()
    -- the dots, one in each bump
    for i = 0, FRAME_BUMPS - 1 do
      local a = (i + 0.5) / FRAME_BUMPS * math.pi / 2
      local x, y = math.sin(a) * (FRAME_R - 0.5), 128 - math.cos(a) * (FRAME_R - 0.5)
      col(G, C.lilacRim, 0.6); circle(G, "fill", x, y, 1.4)
      col(G, C.lilacHi, 0.9); circle(G, "fill", x, y, 0.95)
    end
  end)

  -- ------- the menu's dim: cream paper (the layout tints it)
  gen("lyt/amie_room/msg_win_c", 32, 32, function(G)
    col(G, C.cream); G.rectangle("fill", 0, 0, 32, 32)
    local rng = love.math.newRandomGenerator(11)
    for _ = 1, 260 do
      local c = rng:random() < 0.5 and C.creamHi or C.creamLo
      col(G, c, 0.8)
      G.rectangle("fill", rng:random() * 32, rng:random() * 32, 0.5 + rng:random() * 1.2, 0.5 + rng:random())
    end
  end)

  -- ------- the menu's buttons: a scalloped oval, a striped face, its picture and its word

  local function scallopButton(G, w, h, rim, band, a, b, stripe)
    local cx, cy = w / 2, h / 2
    local outer = scallop(cx, cy, w / 2 - 0.6, h / 2 - 0.6, 22, 0.07)
    -- a soft shadow under it, the dark rim, the pale band
    G.setColor(0, 0, 0, 0.18); fillShape(G, scaled(outer, cx, cy + 1.2, 0.99))
    col(G, rim); fillShape(G, outer)
    col(G, band); fillShape(G, scaled(outer, cx, cy, 0.94))
    local face = scallop(cx, cy, w / 2 - 6, h / 2 - 5.4, 22, 0.06)
    within(G, face, function()
      col(G, a); G.rectangle("fill", 0, 0, w, h)
      col(G, b)
      for x = -stripe / 2, w, stripe * 2 do G.rectangle("fill", x, 0, stripe, h) end
      -- light from the top, a little shade at the foot
      vgrad(G, 0, 0, w, h * 0.45, { 1, 1, 1, 0.35 }, { 1, 1, 1, 0 })
      vgrad(G, 0, h * 0.7, w, h * 0.3, { 1, 1, 1, 0 }, { 0, 0, 0, 0.06 })
    end)
    -- the band's inner edge, tinted with the rim
    G.setLineWidth(0.8); col(G, rim, 0.35); G.line(closed(face))
  end

  gen("ui/btn_play", 90, 54, function(G)
    scallopButton(G, 90, 54, C.pinkRim, C.pinkBand, C.pinkB, C.pinkA, 7)
    glossHeart(G, 45, 17.5, 23, 18, c255(255, 236, 242))
    heavy(G, "PLAY", 45, 36.5, 14, C.magenta, C.white, 1.2, 1.6)
  end)

  -- a little house in pink
  local function house(G, cx, cy)
    local roof, roofLo, wall, door = c255(236, 92, 160), c255(196, 56, 124), c255(252, 206, 228), c255(208, 112, 160)
    col(G, C.white); fillShape(G, { cx - 13, cy - 1, cx, cy - 11.5, cx + 13, cy - 1, cx + 10, cy - 1, cx + 10, cy + 10.5,
      cx - 10, cy + 10.5, cx - 10, cy - 1 })
    col(G, wall); G.rectangle("fill", cx - 8.6, cy - 2, 17.2, 11)
    col(G, door); G.rectangle("fill", cx - 2.6, cy + 2.6, 5.2, 6.4, 1, 1)
    within(G, { cx - 12, cy - 0.6, cx, cy - 10.4, cx + 12, cy - 0.6, cx + 9, cy + 1.2, cx, cy - 6, cx - 9, cy + 1.2 }, function()
      vgrad(G, cx - 13, cy - 11, 26, 13, roof, roofLo)
    end)
    G.setColor(1, 1, 1, 0.5); G.setLineWidth(0.8); G.line(cx - 9, cy - 2.2, cx, cy - 9.4)
  end
  gen("ui/btn_decorate", 74, 46, function(G)
    scallopButton(G, 74, 46, C.greenRim, C.greenBand, C.greenB, C.greenA, 6)
    house(G, 37, 14)
    heavy(G, "DECORATE", 37, 30.5, 9, C.greenInk, C.white, 1, 0.3)
  end)

  -- a Pikachu's head as a pale pink silhouette: a wide head, rounder below, and two long ears
  -- leaning out, edged in the button's dark green
  local function pikachu(G, cx, cy)
    local fill, hi, line = c255(252, 196, 244), c255(255, 230, 252), c255(52, 132, 62)
    local function shape(mode)
      local pts = {}
      for i = 0, 31 do
        local a = i / 32 * math.pi * 2
        local ry = math.sin(a) > 0 and 3.9 or 2.5
        pts[#pts + 1] = cx + math.cos(a) * 4.9
        pts[#pts + 1] = cy + math.sin(a) * ry
      end
      -- the ears: long ovals leaning out from the head's top corners, pointed at the tip
      local function ear(sx)
        local e, ang = {}, 0.55 * sx
        local ex, ey = cx + 4.3 * sx, cy - 4.6
        for i = 0, 19 do
          local a = i / 20 * math.pi * 2
          local ry = math.sin(a) < 0 and 4.6 or 3.4
          local rx = 1.75 * (math.sin(a) < 0 and (0.35 + 0.65 * math.cos(a) ^ 2) ^ 0.5 or 1)
          local px, py = math.cos(a) * rx, math.sin(a) * ry
          e[#e + 1] = ex + px * math.cos(ang) - py * math.sin(ang)
          e[#e + 1] = ey + px * math.sin(ang) + py * math.cos(ang)
        end
        return e
      end
      local earL, earR = ear(-1), ear(1)
      if mode == "line" then
        G.line(closed(pts)); G.line(closed(earL)); G.line(closed(earR))
      else
        fillShape(G, pts); fillShape(G, earL); fillShape(G, earR)
      end
    end
    G.setLineJoin("bevel")
    col(G, line); G.setLineWidth(1.2); shape("line")
    G.stencil(function() shape("fill") end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, cx - 8, cy - 10, 16, 15, hi, fill)
    G.setStencilTest()
  end
  local function curvedArrow(G, x0, y0, x1, y1, bend)
    local pink, pinkLo = c255(246, 72, 160), c255(178, 30, 112)
    local mx, my = (x0 + x1) / 2 + bend[1], (y0 + y1) / 2 + bend[2]
    local pts = {}
    for i = 0, 12 do
      local t = i / 12
      local u = 1 - t
      pts[#pts + 1] = u * u * x0 + 2 * u * t * mx + t * t * x1
      pts[#pts + 1] = u * u * y0 + 2 * u * t * my + t * t * y1
    end
    G.setLineJoin("bevel")
    G.setLineWidth(3.2); col(G, pinkLo); G.line(pts)
    G.setLineWidth(2); col(G, pink); G.line(pts)
    local n = #pts
    local dx, dy = pts[n - 1] - pts[n - 5], pts[n] - pts[n - 4]
    local d = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / d, dy / d
    local hx, hy = x1 + dx * 3.6, y1 + dy * 3.6
    local tri = { hx, hy, x1 - dy * 3.6, y1 + dx * 3.6, x1 + dy * 3.6, y1 - dx * 3.6 }
    col(G, pinkLo); fillShape(G, scaled(tri, x1 + dx * 1.2, y1 + dy * 1.2, 1.3))
    col(G, pink); fillShape(G, tri)
  end
  gen("ui/btn_switch", 74, 46, function(G)
    scallopButton(G, 74, 46, C.greenRim, C.greenBand, C.greenB, C.greenA, 6)
    pikachu(G, 27.5, 15.5)
    pikachu(G, 44.5, 18)
    curvedArrow(G, 23, 23, 16.5, 14, { -4, 1.5 })
    curvedArrow(G, 48, 6.5, 56, 15, { 4, -2.5 })
    -- the word on a white tab
    G.setColor(1, 1, 1, 0.92); G.rectangle("fill", 16, 25, 42, 11, 2, 2)
    heavy(G, "SWITCH", 37, 30.5, 10, C.greenInk, C.white, 0.8, 0.4)
  end)

  -- ------- the bubbles over the Pokemon: a soft cloud with its wish in it

  local function cloud(G, edge, mid, glow)
    local pts = lobes(24, 24, 19, 8, 0.09, math.pi / 8)
    col(G, glow, 0.35); fillShape(G, scaled(pts, 24, 24, 1.2))
    col(G, glow, 0.55); fillShape(G, scaled(pts, 24, 24, 1.1))
    rings(G, pts, 24, 24, edge, mid, 14, 0.3)
  end
  -- a cupcake with a cherry
  local function cupcake(G, cx, cy)
    local cup, cupLo, cream, top, topLo = c255(236, 128, 176), c255(206, 92, 146), c255(255, 214, 230),
      c255(242, 112, 168), c255(214, 70, 136)
    within(G, { cx - 10.5, cy + 1, cx + 10.5, cy + 1, cx + 8, cy + 11, cx - 8, cy + 11 }, function()
      vgrad(G, cx - 11, cy + 1, 22, 10, cup, cupLo)
      G.setColor(1, 1, 1, 0.25)
      for x = cx - 9, cx + 9, 3.6 do G.rectangle("fill", x, cy + 1, 0.8, 10) end
    end)
    -- the cream between, wavy
    col(G, cream)
    for i = 0, 6 do circle(G, "fill", cx - 9.6 + i * 3.2, cy + 1.2, 2.1) end
    -- the dome of icing
    within(G, { cx - 11, cy + 1, cx - 10, cy - 5, cx - 6, cy - 9, cx, cy - 10.5, cx + 6, cy - 9, cx + 10, cy - 5, cx + 11, cy + 1 },
      function() vgrad(G, cx - 11, cy - 11, 22, 12, top, topLo) end)
    G.setColor(1, 1, 1, 0.55); G.ellipse("fill", cx + 3.4, cy - 6.6, 2.8, 1.5)
    -- the cherry and its stalk
    col(G, c255(120, 70, 40)); G.setLineWidth(0.8); G.line(cx + 0.4, cy - 12.6, cx + 2.6, cy - 16)
    col(G, c255(214, 20, 40)); circle(G, "fill", cx, cy - 11.6, 2.6)
    G.setColor(1, 1, 1, 0.75); circle(G, "fill", cx + 0.8, cy - 12.6, 0.8)
  end
  gen("lyt/amie_room/icon_okashi", 48, 48, function(G)
    cloud(G, c255(246, 156, 186), c255(253, 236, 242), c255(250, 170, 200))
    cupcake(G, 24, 25)
  end)
  -- a music note, glossy green
  local function note(G, cx, cy, s, c, hi, line)
    G.push(); G.translate(cx, cy); G.scale(s, s)
    for pass = 1, 2 do
      local g = pass == 1 and 0.9 or 0
      col(G, pass == 1 and line or c)
      G.push(); G.translate(-3.2, 5.6); G.rotate(-0.35); G.ellipse("fill", 0, 0, 5.2 + g, 4 + g); G.pop()
      G.rectangle("fill", 0.2 - g, -9 - g, 2.4 + g * 2, 15.5 + g)
      fillShape(G, { 0.2 - g, -9.6 - g, 8.6 + g, -4.6, 7 + g, -0.8 + g, 2.6, -4.2 + g })
    end
    G.setColor(1, 1, 1, 0.55); G.ellipse("fill", -4.4, 4.8, 1.8, 1)
    if hi then col(G, hi); G.rectangle("fill", 0.7, -8, 0.8, 12) end
    G.pop()
  end
  gen("lyt/amie_room/icon_asobi", 48, 48, function(G)
    cloud(G, c255(128, 214, 128), c255(232, 250, 226), c255(140, 224, 140))
    note(G, 23, 24, 1.15, c255(36, 168, 90), c255(120, 230, 160), c255(18, 110, 64))
  end)

  -- ------- hearts and notes that float up
  gen("lyt/amie_room/particle_01", 30, 30, function(G)
    local pts = heartPts(15, 15.5, 26, 22)
    col(G, C.heart, 0.25); fillShape(G, scaled(pts, 15, 15, 1.12))
    col(G, C.heart, 0.4); fillShape(G, scaled(pts, 15, 15, 1.05))
    glossHeart(G, 15, 15.5, 22, 18.5)
  end)
  gen("lyt/amie_room/particle_00", 30, 30, function(G)
    note(G, 15, 13.5, 1.05, c255(224, 162, 70), c255(255, 214, 140), c255(196, 128, 46))
  end)

  -- ------- the shadow under a Pokemon
  gen("lyt/amie_room/shadow", 40, 20, function(G)
    for i = 0, 6 do
      local t = i / 6
      G.setColor(0.467, 0.467, 0.467, 0.16 + t * 0.12)
      G.ellipse("fill", 20, 10, 19.6 - t * 3, 9.4 - t * 1.5)
    end
  end)

  -- ------- the visitors' talk: a white bubble with its tail down-right, and what they say
  gen("lyt/amie_room/talk_bubble_L", 32, 32, function(G)
    local tail = { 21, 22, 28.6, 30.4, 25.6, 19.4 }
    col(G, C.ink); circle(G, "fill", 15.5, 14.5, 13.2); fillShape(G, scaled(tail, 25, 24, 1.25))
    col(G, C.white); circle(G, "fill", 15.5, 14.5, 11.8); fillShape(G, tail)
    G.setColor(0.9, 0.92, 0.96, 1); G.setLineWidth(1)
    G.arc("line", "open", 15.5, 14.5, 10.6, 0.3, 1.9)
  end)
  gen("lyt/amie_room/talk_heart", 32, 32, function(G)
    glossHeart(G, 15.5, 15, 15, 12.5, c255(220, 40, 160))
  end)
  local function bang(G, x, y)
    col(G, C.grey)
    fillShape(G, { x - 3.1, y - 6.6, x + 3.1, y - 6.6, x + 1.3, y + 2.6, x - 1.3, y + 2.6 })
    circle(G, "fill", x, y - 6.8, 3.1)
    circle(G, "fill", x, y + 6.2, 2.1)
  end
  gen("lyt/amie_room/talk_exc1", 32, 32, function(G) bang(G, 15.5, 14.5) end)
  gen("lyt/amie_room/talk_exc2", 32, 32, function(G) bang(G, 12.5, 14.5); bang(G, 18.5, 14.5) end)
  gen("lyt/amie_room/talk_exc3", 32, 32, function(G) bang(G, 10, 14.5); bang(G, 15.5, 14.5); bang(G, 21, 14.5) end)
  gen("lyt/amie_room/talk_question", 32, 32, function(G)
    col(G, C.blue)
    G.setLineWidth(3.2)
    local pts = {}
    for i = 0, 14 do
      local a = math.pi * 1.05 - i / 14 * math.pi * 1.45
      pts[#pts + 1] = 15.5 + math.cos(a) * 4.6
      pts[#pts + 1] = 10.5 - math.sin(a) * 4.6
    end
    pts[#pts + 1] = 15.5; pts[#pts + 1] = 17
    K.stroke(G, 3.2, unpack(pts))
    circle(G, "fill", 15.5, 21.6, 1.9)
  end)
  gen("lyt/amie_room/talk_silent", 32, 32, function(G)
    col(G, C.grey)
    for i = -1, 1 do circle(G, "fill", 15.5 + i * 5, 15, 1.7) end
  end)
  gen("lyt/amie_room/talk_onpu", 32, 32, function(G)
    note(G, 15.5, 14, 1, C.orange, C.orangeHi, c255(206, 110, 10))
  end)

  -- ------- a gift box with its bow, on its shadow: a box seen from above and to the left,
  -- its lid, front, side and top lit differently, the ribbon running round all three
  gen("lyt/amie_room/gift", 32, 40, function(G)
    local top, front, frontLo, side, sideLo = c255(255, 220, 238), c255(250, 176, 214), c255(232, 140, 188),
      c255(218, 120, 172), c255(190, 92, 146)
    local rib, ribHi, ribLo, ribSide = c255(232, 24, 92), c255(255, 96, 150), c255(176, 10, 64), c255(186, 14, 70)
    G.setColor(0.1, 0.2, 0.1, 0.4); G.ellipse("fill", 16.5, 35.2, 13, 3.6)
    -- the body under the lid
    within(G, { 5, 20, 21, 20, 21, 34, 5, 34 }, function() vgrad(G, 5, 20, 16, 14, front, frontLo) end)
    within(G, { 21, 20, 27, 16, 27, 30, 21, 34 }, function() vgrad(G, 21, 16, 6, 18, side, sideLo) end)
    -- the lid: front band, side band, top
    within(G, { 4, 16, 22, 16, 22, 20.6, 4, 20.6 }, function() vgrad(G, 4, 16, 18, 4.6, top, front) end)
    col(G, side); fillShape(G, { 22, 16, 28, 12, 28, 16.6, 22, 20.6 })
    col(G, top); fillShape(G, { 4, 16, 10, 12, 28, 12, 22, 16 })
    G.setColor(0, 0, 0, 0.12); G.rectangle("fill", 5, 20.6, 16, 1.2)
    G.setColor(1, 1, 1, 0.7); G.setLineWidth(0.6); G.line(4.3, 16.2, 21.8, 16.2)
    -- the ribbon: down the front, down the side, crossing on the top
    col(G, rib); G.rectangle("fill", 11, 16, 4, 18)
    col(G, ribHi); G.rectangle("fill", 11, 16, 1, 18)
    col(G, ribSide); fillShape(G, { 23.6, 19.4, 25.6, 18.1, 25.6, 31.1, 23.6, 32.4 })
    col(G, rib); fillShape(G, { 11, 16, 15, 16, 21, 12, 17, 12 })
    col(G, rib); fillShape(G, { 6.2, 13.3, 24.2, 13.3, 25.6, 14.5, 7.6, 14.5 })
    -- the bow: two loops and their tails, on the top's middle
    local bx, by = 16, 13.6
    for sx = -1, 1, 2 do
      local tail = { bx, by, bx + sx * 3, by + 6.2, bx + sx * 5.2, by + 5.2, bx + sx * 1.6, by }
      col(G, ribLo); fillShape(G, tail)
      local lp = { bx, by, bx + sx * 2.6, by - 7.8, bx + sx * 8, by - 8.8, bx + sx * 8.6, by - 3.4, bx + sx * 4, by + 0.8 }
      col(G, ribLo); fillShape(G, scaled(lp, bx + sx * 5.5, by - 3.5, 1.12))
      within(G, lp, function()
        vgrad(G, bx - 11, by - 9, 22, 11, ribHi, rib)
        col(G, ribLo, 0.8); G.ellipse("fill", bx + sx * 6.2, by - 3.6, 2.2, 1.6)
      end)
      G.setColor(1, 1, 1, 0.5); G.ellipse("fill", bx + sx * 6, by - 6.6, 2, 0.9)
    end
    col(G, ribLo); circle(G, "fill", bx, by - 0.4, 2.8)
    col(G, rib); circle(G, "fill", bx - 0.2, by - 0.8, 2.2)
    G.setColor(1, 1, 1, 0.5); circle(G, "fill", bx - 0.8, by - 1.5, 0.7)
  end)
end
