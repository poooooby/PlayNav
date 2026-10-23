-- Pokemon-Amie's room drawn by the engine: each id the room asks Assets for (the scalloped
-- frame, the menu's PLAY / DECORATE / SWITCH buttons and its dim, the bubbles over the
-- Pokemon, the hearts, the visitors' talk bubbles, the gift box, the shadow, and SWITCH's
-- party list: ribbons, bar, title tab, ruled card, medallions, meter icons, buttons) is drawn here
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

  -- ------- SWITCH: the party list (kawaii_windows): a pink striped room, lilac gingham ribbons
  -- with wavy edges, a striped lilac bar, a paper tab for the title, a ruled cream card, gold
  -- medallions for the party, the meters' little icons, the green Switch button, the return

  local LILAC_A, LILAC_B = c255(216, 208, 233), c255(206, 190, 223)
  local LILAC_EDGE, LILAC_LIP = c255(123, 106, 157), c255(180, 156, 205)

  -- a smooth curve through (x, y) knots, sampled every unit
  local function curve(knots, w)
    local out = {}
    for x = 0, w do
      local i = 1
      while knots[i + 1] and knots[i + 1][1] < x do i = i + 1 end
      local p1, p2 = knots[i], knots[i + 1] or knots[i]
      local p0, p3 = knots[i - 1] or p1, knots[i + 2] or p2
      local t = p2[1] > p1[1] and (x - p1[1]) / (p2[1] - p1[1]) or 0
      local t2, t3 = t * t, t * t * t
      out[x] = 0.5 * (2 * p1[2] + (-p0[2] + p2[2]) * t + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2
        + (-p0[2] + 3 * p1[2] - 3 * p2[2] + p3[2]) * t3)
    end
    return out
  end
  -- lilac gingham: 8-unit bands both ways, darker where they cross
  local function gingham(G, x, y, w, h)
    col(G, LILAC_A); G.rectangle("fill", x, y, w, h)
    col(G, LILAC_B, 0.75)
    for xx = x + 8, x + w, 16 do G.rectangle("fill", xx, y, 8, h) end
    for yy = y + 8, y + h, 16 do G.rectangle("fill", x, yy, w, 8) end
  end
  -- a gingham ribbon with one wavy edge (edge[x] its y); below: the ribbon runs down from it
  local function ribbon(G, w, h, edge, below)
    local pts = {}
    for x = 0, w do pts[#pts + 1] = x; pts[#pts + 1] = edge[x] end
    local fy = below and h or 0
    local band, sh = {}, {}
    for i = 1, #pts do band[i] = pts[i] end
    band[#band + 1] = w; band[#band + 1] = fy; band[#band + 1] = 0; band[#band + 1] = fy
    -- a soft shadow past the edge
    for x = 0, w do sh[#sh + 1] = x; sh[#sh + 1] = edge[x] + (below and -1.4 or 1.4) end
    sh[#sh + 1] = w; sh[#sh + 1] = fy; sh[#sh + 1] = 0; sh[#sh + 1] = fy
    G.setColor(0.1, 0.05, 0.2, 0.22); fillShape(G, sh)
    within(G, band, function() gingham(G, 0, -8, w, h + 16) end)
    -- the purple lip along the edge, lit on its inner side
    G.setLineJoin("bevel")
    G.setLineWidth(1.8); col(G, LILAC_EDGE); G.line(pts)
    local lip = {}
    for x = 0, w do lip[#lip + 1] = x; lip[#lip + 1] = edge[x] + (below and 1.6 or -1.6) end
    G.setLineWidth(1); col(G, LILAC_LIP); G.line(lip)
  end
  gen("lyt/amie_room/goods_win_line_dw", 320, 24, function(G, w, h)
    ribbon(G, w, h, curve({ { 0, 15 }, { 60, 15 }, { 120, 11 }, { 190, 9 }, { 240, 13 }, { 290, 17 }, { 320, 16 } }, w), true)
  end)
  gen("lyt/amie_room/goods_win_line_up", 320, 24, function(G, w, h)
    ribbon(G, w, h, curve({ { 0, 8 }, { 30, 6.5 }, { 60, 8 }, { 100, 13 }, { 140, 14 }, { 200, 12 }, { 250, 9 },
      { 300, 8 }, { 320, 9 } }, w), false)
  end)

  -- the room behind the list: soft pink stripes
  gen("lyt/amie_room/goods_win_c", 16, 16, function(G)
    col(G, c255(244, 211, 211)); G.rectangle("fill", 0, 0, 16, 16)
    col(G, c255(239, 198, 190)); G.rectangle("fill", 0, 0, 4, 16); G.rectangle("fill", 12, 0, 4, 16)
  end)

  -- the bar across the top (a window corner, mirrored): lilac stripes, a torn foot
  gen("lyt/amie_room/bar_title", 32, 36, function(G)
    local body = { 0, 0, 32, 0 }
    for x = 32, 0, -2 do
      body[#body + 1] = x; body[#body + 1] = 29.4 + ((x * 7) % 5) * 0.35
    end
    local sh = {}
    for i = 1, #body, 2 do sh[i] = body[i]; sh[i + 1] = body[i + 1] > 1 and body[i + 1] + 1.6 or body[i + 1] end
    G.setColor(0, 0, 0, 0.2); fillShape(G, sh)
    within(G, body, function()
      col(G, LILAC_A); G.rectangle("fill", 0, 0, 32, 36)
      col(G, LILAC_B); G.rectangle("fill", 8, 0, 16, 36)
      vgrad(G, 0, 22, 32, 10, { 1, 1, 1, 0 }, { 0.6, 0.5, 0.75, 0.25 })
    end)
  end)

  -- a pinked edge: a zigzag from y0 to y1 at x (dir +1: the paper lies to the right)
  local function pinked(y0, y1, x, dir, step, depth)
    local pts = {}
    local n = math.floor((y1 - y0) / step)
    for i = 0, n do
      pts[#pts + 1] = x + (i % 2 == 0 and 0 or depth) * dir
      pts[#pts + 1] = y0 + (y1 - y0) * i / n
    end
    return pts
  end
  -- the title's paper tab (a window corner, mirrored): pink paper, its pinked end, a pink rule
  gen("lyt/amie_room/bg_tab", 140, 18, function(G)
    local edge = pinked(2, 18, 3.6, 1, 2, 1.6)
    local shape = { 140, 2, 140, 18 }
    for i = #edge - 1, 1, -2 do shape[#shape + 1] = edge[i]; shape[#shape + 1] = edge[i + 1] end
    G.setColor(0.4, 0.4, 0.4, 0.25); G.rectangle("fill", 4, 1, 136, 1.2)
    within(G, shape, function()
      col(G, c255(255, 231, 221)); G.rectangle("fill", 0, 0, 140, 18)
      col(G, c255(251, 227, 215)); G.rectangle("fill", 3, 0, 4, 18)
      col(G, c255(242, 169, 176)); G.rectangle("fill", 9.6, 0, 2.2, 18)
      vgrad(G, 0, 2, 140, 3, c255(240, 200, 196, 140), c255(255, 231, 221, 0))
    end)
  end)

  -- the ruled card: cream paper, pinked ends each with a pink band, a red rule down after the
  -- picture and two across between the meters' rows
  gen("lyt/amie_room/win_pokelist", 298, 80, function(G, w, h)
    local L = pinked(5, 75, 2.2, 1, 2.4, 1.8)
    local R = pinked(5, 75, w - 2.2, -1, 2.4, 1.8)
    local shape = {}
    for i = 1, #L do shape[i] = L[i] end
    for i = #R - 1, 1, -2 do shape[#shape + 1] = R[i]; shape[#shape + 1] = R[i + 1] end
    G.setColor(0.25, 0.2, 0.2, 0.25); G.rectangle("fill", 4, 74.5, w - 8, 2)
    within(G, shape, function()
      col(G, c255(249, 249, 216)); G.rectangle("fill", 0, 0, w, h)
      for _, x in ipairs({ 3, w - 9 }) do
        col(G, c255(247, 222, 214)); G.rectangle("fill", x, 0, 6, h)
        col(G, c255(238, 172, 178)); G.rectangle("fill", x + 2, 0, 2.2, h)
      end
      -- warm light along the top and the foot
      vgrad(G, 0, 4, w, 4, c255(255, 236, 196), c255(249, 249, 216, 0))
      vgrad(G, 0, 70, w, 5, c255(255, 249, 216, 0), c255(255, 236, 187))
      col(G, c255(162, 145, 111)); G.rectangle("fill", 0, 4, w, 0.8)
      col(G, c255(120, 100, 96)); G.rectangle("fill", 0, 74.2, w, 0.8)
      -- the rules, a little uneven as if drawn by hand
      for pass = 1, 2 do
        if pass == 1 then G.setLineWidth(2.2); col(G, c255(255, 214, 190, 160))
        else G.setLineWidth(0.8); col(G, c255(214, 150, 128)) end
        G.line(112.6, 7, 112.8, 72); G.line(118, 26.6, 287, 27.2); G.line(118, 50.8, 287, 51.4)
      end
    end)
  end)

  -- a party member's medallion: gold rim, a striped cream face
  local function disc(cx, cy, r) return radial(cx, cy, r, r, 64, function() return 1 end) end
  gen("lyt/amie_room/button_pokemon", 42, 42, function(G)
    G.setColor(0, 0, 0, 0.22); circle(G, "fill", 21, 22, 20.4)
    col(G, c255(102, 68, 0)); circle(G, "fill", 21, 21, 20.2)
    within(G, disc(21, 21, 19.2), function()
      vgrad(G, 0, 1, 42, 40, c255(250, 232, 160), c255(221, 187, 85))
      vgrad(G, 0, 26, 42, 16, c255(150, 110, 30, 0), c255(150, 110, 30))
    end)
    col(G, c255(170, 136, 60)); circle(G, "fill", 21, 21, 15.8)
    within(G, disc(21, 21, 15), function()
      col(G, c255(255, 240, 210)); G.rectangle("fill", 0, 0, 42, 42)
      col(G, c255(238, 216, 150))
      for x = 9, 34, 8 do G.rectangle("fill", x, 0, 4, 42) end
      vgrad(G, 0, 6, 42, 14, { 1, 1, 1, 0.55 }, { 1, 1, 1, 0 })
      vgrad(G, 0, 28, 42, 10, { 0.8, 0.6, 0.2, 0 }, { 0.8, 0.6, 0.2, 0.3 })
    end)
    G.setColor(1, 1, 1, 0.6); G.setLineWidth(1)
    G.arc("line", "open", 21, 21, 17.6, math.pi * 1.1, math.pi * 1.6)
  end)

  -- the return: a pale blue button with a dark blue arrow turning right
  gen("lyt/amie_room/button_back", 30, 30, function(G)
    col(G, c255(10, 70, 90)); circle(G, "fill", 15, 15, 14.4)
    within(G, disc(15, 15, 13.2), function() vgrad(G, 0, 1, 30, 28, c255(176, 232, 244), c255(88, 184, 206)) end)
    col(G, c255(112, 190, 210)); G.setLineWidth(1); G.circle("line", 15, 15, 10.4, 48)
    within(G, disc(15, 15, 9.8), function() vgrad(G, 0, 4, 30, 22, c255(220, 246, 252), c255(150, 214, 228)) end)
    local blue = c255(14, 64, 168)
    G.setLineJoin("miter")
    G.setLineWidth(3.6); G.setColor(1, 1, 1, 0.9); G.line(19.6, 19.6, 9.6, 19.6, 9.6, 11.4, 15.2, 11.4)
    G.setLineWidth(2.2); col(G, blue); G.line(19.6, 19.6, 9.6, 19.6, 9.6, 11.4, 15.6, 11.4)
    local head = { 20.4, 11.4, 15.4, 7.4, 15.4, 15.4 }
    G.setColor(1, 1, 1, 0.9); fillShape(G, scaled(head, 17, 11.4, 1.3))
    col(G, blue); fillShape(G, head)
    G.setColor(1, 1, 1, 0.45); G.ellipse("fill", 12, 7.4, 5, 2)
  end)

  -- the meters' icons, full and spent
  local function smallHeart(G, c, line)
    local pts = heartPts(8, 8.4, 14, 12)
    col(G, line); fillShape(G, scaled(pts, 8, 8, 1.14))
    col(G, c); fillShape(G, pts)
  end
  gen("lyt/amie_room/heart_00", 16, 16, function(G)
    smallHeart(G, c255(255, 120, 200), c255(226, 40, 170))
    G.setColor(1, 1, 1, 0.85); G.ellipse("fill", 11, 5.6, 1.6, 1.1)
    G.setColor(1, 1, 1, 0.3); G.ellipse("fill", 6, 6.6, 3, 1.6)
  end)
  gen("lyt/amie_room/heart_01", 16, 16, function(G)
    smallHeart(G, c255(78, 78, 82), c255(60, 60, 64))
  end)
  -- a little round cake with a cherry
  local function bun(G, body, top, line, cherry)
    col(G, line); G.ellipse("fill", 8, 11.4, 7.4, 6.2); circle(G, "fill", 8, 4, 2.2)
    col(G, body); G.ellipse("fill", 8, 11.4, 6.6, 5.4)
    if top then
      within(G, radial(8, 11.4, 6.6, 5.4, 32, function() return 1 end), function()
        col(G, top); G.rectangle("fill", 0, 5, 16, 6)
        for i = 0, 4 do circle(G, "fill", 2.4 + i * 2.8, 11.2, 1.5) end
        G.setColor(1, 1, 1, 0.4); G.ellipse("fill", 5.6, 8.4, 2.6, 1.2)
      end)
    end
    col(G, cherry or body); circle(G, "fill", 8, 4.2, 1.6)
  end
  gen("lyt/amie_room/ic_hungry", 16, 18, function(G)
    bun(G, c255(255, 214, 230), c255(242, 120, 172), c255(206, 80, 136), c255(220, 30, 50))
  end)
  gen("lyt/amie_room/ic_hungry_black", 16, 18, function(G)
    bun(G, c255(78, 78, 82), nil, c255(60, 60, 64))
  end)
  gen("lyt/amie_room/ic_asobu", 18, 18, function(G)
    note(G, 9, 9, 0.75, c255(30, 168, 150), c255(120, 230, 210), c255(14, 110, 100))
  end)
  gen("lyt/amie_room/ic_asobu_black", 18, 18, function(G)
    note(G, 9, 9, 0.75, c255(78, 78, 82), nil, c255(60, 60, 64))
  end)

  -- the green Switch button: a pill, its rims, a soft diamond pattern, the swap at its left
  gen("lyt/amie_room/button_change", 278, 52, function(G, w, h)
    local function pill(inset)
      local r = h / 2 - inset
      local pts = {}
      for i = 0, 24 do
        local a = math.pi / 2 + i / 24 * math.pi
        pts[#pts + 1] = h / 2 + math.cos(a) * r; pts[#pts + 1] = h / 2 + math.sin(a) * r
      end
      for i = 0, 24 do
        local a = -math.pi / 2 + i / 24 * math.pi
        pts[#pts + 1] = w - h / 2 + math.cos(a) * r; pts[#pts + 1] = h / 2 + math.sin(a) * r
      end
      return pts
    end
    G.setColor(0.1, 0.1, 0.1, 0.25); fillShape(G, scaled(pill(0.6), w / 2, h / 2 + 1.4, 1))
    col(G, c255(55, 106, 21)); fillShape(G, pill(0.6))
    col(G, c255(167, 224, 142)); fillShape(G, pill(2.2))
    col(G, c255(80, 140, 50)); fillShape(G, pill(3.8))
    within(G, pill(4.8), function()
      vgrad(G, 0, 4, w, h - 8, c255(222, 244, 208), c255(158, 216, 125))
      -- the diamonds
      G.setColor(1, 1, 1, 0.22)
      for y = 4, h, 8 do
        for x = ((y - 4) / 8 % 2) * 8, w, 16 do fillShape(G, { x, y - 4, x + 4, y, x, y + 4, x - 4, y }) end
      end
      vgrad(G, 0, 4, w, 12, { 1, 1, 1, 0.45 }, { 1, 1, 1, 0 })
      vgrad(G, 0, h - 12, w, 8, { 0.3, 0.55, 0.2, 0 }, { 0.3, 0.55, 0.2, 0.35 })
    end)
    -- the swap: two heads and their arrows, small
    G.push(); G.translate(10, 3); G.scale(0.85, 0.85)
    pikachu(G, 20, 16); pikachu(G, 31, 37)
    curvedArrow(G, 14, 46, 9, 33, { -3, 1 })
    curvedArrow(G, 32, 6, 40, 19, { 3, -2 })
    G.pop()
  end)

  -- ------- the minigames' sparkles: a four-pointed twinkle with a soft glow, and a small dot
  -- (Berry Picker's and Head It's rewards white, Head It's head-hit ones pale blue)
  local function twinkle(G, size, core, glow)
    local c = size / 2
    -- a faint haze, then the four rays: a wide soft pair under a thin bright one
    for i = 1, 5 do
      col(G, glow, 0.05); circle(G, "fill", c, c, size * 0.07 * i)
    end
    local function rays(r, t, colour, a)
      col(G, colour, a)
      fillShape(G, { c, c - r, c + t, c - t, c + r, c, c + t, c + t, c, c + r, c - t, c + t, c - r, c, c - t, c - t })
    end
    rays(size * 0.5, size * 0.09, glow, 0.6)
    rays(size * 0.44, size * 0.045, core, 1)
    G.setColor(1, 1, 1, 1); circle(G, "fill", c, c, size * 0.06)
  end
  local function dot(G, size, core, glow)
    local c = size / 2
    for i = 5, 1, -1 do
      col(G, glow, 0.16); circle(G, "fill", c, c, size * 0.09 * i)
    end
    col(G, core); circle(G, "fill", c, c, size * 0.32)
  end
  local SPARKLE = {
    { "lyt/berry_reward/", C.white, c255(220, 236, 255) },
    { "lyt/head_reward/", C.white, c255(220, 236, 255) },
    { "lyt/tile_down/", C.white, c255(220, 236, 255) },
    { "lyt/head_effect/", c255(210, 244, 255), c255(120, 206, 240) },
  }
  for _, sp in ipairs(SPARKLE) do
    gen(sp[1] .. "twinkle0", 20, 20, function(G) twinkle(G, 20, sp[2], sp[3]) end)
    gen(sp[1] .. "twinkle1", 10, 10, function(G) dot(G, 10, sp[2], sp[3]) end)
  end

  -- ------- the minigames' cards, windows, stars, medals and smoke (Berry Picker, Head It, Tile Puzzle)

  local function each(packs, name, w, h, draw)
    for _, p in ipairs(packs) do gen("lyt/" .. p .. "/" .. name, w, h, draw) end
  end
  local BOTH_WINDOWS = { "berry_demo", "berry_front", "berry_score", "head_demo", "head_down", "head_front", "tile_down", "tile_up" }
  local PAPER_TOP, PAPER_LOW = c255(252, 246, 205), c255(242, 232, 158)
  local TAPE, TAPE_LO = c255(246, 222, 126), c255(190, 166, 86)

  -- the message window: cream note paper (corner, top edge, middle) with a soft shadow above
  -- and to the left, and a strip of tape across its corner
  local function paperGrain(G, x, y, w, h, seed)
    local rng = love.math.newRandomGenerator(seed)
    for _ = 1, math.floor(w * h * 0.35) do
      local c = rng:random() < 0.5 and PAPER_TOP or PAPER_LOW
      col(G, c, 0.35)
      G.rectangle("fill", x + rng:random() * w, y + rng:random() * h, 0.8, 0.8)
    end
  end
  local function shadowEdge(G, x, y, w, h, vertical)
    for i = 0, 2 do
      G.setColor(0, 0, 0, 0.11 * (i + 1))
      if vertical then G.rectangle("fill", x + i, y, 1, h) else G.rectangle("fill", x, y + i, w, 1) end
    end
  end
  each(BOTH_WINDOWS, "msg_win_ul", 16, 16, function(G)
    shadowEdge(G, 3, 0, 13, 3); shadowEdge(G, 0, 3, 3, 13, true)
    within(G, { 3, 3, 16, 3, 16, 16, 3, 16 }, function()
      vgrad(G, 3, 3, 13, 13, PAPER_TOP, PAPER_LOW)
      paperGrain(G, 3, 3, 13, 13, 3)
    end)
    -- the tape, across the corner
    local t = { 0.6, 6.4, 6.4, 0.6, 10.8, 4.2, 4.2, 10.8 }
    G.setColor(0, 0, 0, 0.18); fillShape(G, scaled(t, 5.7, 6.3, 1.08))
    within(G, t, function() vgrad(G, 0, 0, 12, 12, TAPE, TAPE_LO) end)
    G.setColor(1, 1, 1, 0.35); G.setLineWidth(0.6); G.line(1.8, 6.2, 6.2, 1.8)
  end)
  each(BOTH_WINDOWS, "msg_win_u", 16, 16, function(G)
    shadowEdge(G, 0, 0, 16, 3)
    vgrad(G, 0, 3, 16, 13, PAPER_TOP, PAPER_LOW)
    paperGrain(G, 0, 3, 16, 13, 5)
    -- the tape's far end, as the corner's runs into it
    local t = { 5, 2.2, 8.6, 2.2, 11.4, 6.4, 9.6, 7.6 }
    within(G, t, function() vgrad(G, 4, 2, 8, 6, TAPE, TAPE_LO) end)
  end)
  each(BOTH_WINDOWS, "msg_win_c", 32, 32, function(G)
    vgrad(G, 0, 0, 32, 32, c255(250, 242, 190), c255(244, 236, 176))
    paperGrain(G, 0, 0, 32, 32, 9)
  end)

  -- the number window's border: half see-through orange bumps, lit cream on their outer edge
  local NUM_PACKS = { "berry_score", "head_front", "tile_up" }
  local BUMP, BUMP_HI, BUMP_LO = c255(250, 187, 87), c255(254, 242, 222), c255(160, 120, 60)
  local function bump(G, cx, cy, r, ang)
    -- a disc, shaded from its outer edge (toward ang) inward
    within(G, radial(cx, cy, r, r, 24, function() return 1 end), function()
      col(G, BUMP, 0.55); G.rectangle("fill", cx - r, cy - r, 2 * r, 2 * r)
      for i = 1, 4 do
        col(G, BUMP_HI, 0.18)
        circle(G, "fill", cx + math.cos(ang) * r * (0.2 + 0.12 * i), cy + math.sin(ang) * r * (0.2 + 0.12 * i), r * (0.9 - 0.15 * i))
      end
    end)
    col(G, BUMP_LO, 0.4); G.setLineWidth(0.6)
    G.arc("line", "open", cx, cy, r - 0.3, ang + math.pi * 0.55, ang + math.pi * 1.45)
  end
  each(NUM_PACKS, "win_number_L", 10, 8, function(G) bump(G, 10, 4, 5, math.pi) end)
  each(NUM_PACKS, "win_number_R", 10, 8, function(G) bump(G, 0, 4, 5, 0) end)
  each(NUM_PACKS, "win_number_up", 8, 10, function(G) bump(G, 4, 10, 5, -math.pi / 2) end)
  each(NUM_PACKS, "win_number_dw", 8, 10, function(G) bump(G, 4, 0, 5, math.pi / 2) end)
  each(NUM_PACKS, "win_number_Lu", 10, 10, function(G) bump(G, 9, 9, 6, -math.pi * 0.75) end)
  each(NUM_PACKS, "win_number_Ld", 10, 10, function(G) bump(G, 9, 1, 6, math.pi * 0.75) end)
  each(NUM_PACKS, "win_number_Ru", 10, 10, function(G) bump(G, 1, 9, 6, -math.pi * 0.25) end)
  each(NUM_PACKS, "win_number_Rd", 10, 10, function(G) bump(G, 1, 1, 6, math.pi * 0.25) end)

  -- a five-pointed star's outline
  local function starPts(cx, cy, r, inner, turn)
    local pts = {}
    for i = 0, 9 do
      local a = -math.pi / 2 + i * math.pi / 5 + (turn or 0)
      local rr = i % 2 == 0 and r or r * inner
      pts[#pts + 1] = cx + math.cos(a) * rr
      pts[#pts + 1] = cy + math.sin(a) * rr
    end
    return pts
  end
  -- the difficulty stars: glossy, glowing white at the middle; the "h" ones only their left half
  local DIFF_STAR = {
    easy = { c255(250, 196, 30), c255(214, 150, 10) }, normal = { c255(250, 140, 36), c255(210, 96, 20) },
    hard = { c255(232, 30, 80), c255(180, 10, 56) }, infinite = { c255(190, 80, 230), c255(136, 44, 190) },
  }
  local function glossStar(G, s, half)
    local pts = starPts(10, 10.6, 9.4, 0.5)
    local function body()
      col(G, s[2]); fillShape(G, scaled(pts, 10, 10.6, 1.08))
      rings(G, pts, 10, 10.6, s[1], c255(255, 252, 236), 10, 0.15)
    end
    if half then
      within(G, { 0, 0, 10, 0, 10, 20, 0, 20 }, body)
    else
      body()
    end
  end
  for name, s in pairs(DIFF_STAR) do
    each(NUM_PACKS, "star_" .. name, 20, 20, function(G) glossStar(G, s) end)
    each(NUM_PACKS, "star_" .. name .. "h", 20, 20, function(G) glossStar(G, s, true) end)
  end

  -- Head It's mark on the Pokemon's head: a white star outline, a small star in it, sparks round
  gen("lyt/head_down/target", 32, 32, function(G)
    local outer = starPts(16, 17, 13.5, 0.5)
    G.setColor(0.1, 0.4, 0.42, 0.45); fillShape(G, scaled(outer, 16, 18, 1.1))
    G.setColor(1, 1, 1, 1); fillShape(G, outer)
    G.setColor(0.18, 0.5, 0.52, 1); fillShape(G, starPts(16, 17, 10, 0.5))
    G.setColor(1, 1, 1, 1); fillShape(G, starPts(16, 17, 4.6, 0.5))
    for i = 0, 4 do
      local a = -math.pi / 2 + (i + 0.5) * math.pi * 2 / 5
      G.setColor(1, 1, 1, 0.9); circle(G, "fill", 16 + math.cos(a) * 14.5, 17 + math.sin(a) * 14.5, 1)
    end
  end)
  -- the score's bubble: a pale oval in a teal ring
  gen("lyt/head_down/scorewindow", 64, 64, function(G)
    local o = radial(32, 34, 30, 20, 64, function() return 1 end)
    G.setColor(0.05, 0.3, 0.3, 0.3); fillShape(G, scaled(o, 32, 38, 1.04))
    rings(G, o, 32, 34, c255(40, 140, 140), c255(110, 200, 196), 6, 0.86)
    local i = radial(32, 33, 26, 16.5, 64, function() return 1 end)
    rings(G, i, 32, 33, c255(170, 226, 226), c255(230, 248, 246), 10, 0.3)
    G.setColor(1, 1, 1, 0.5); G.ellipse("fill", 30, 27, 15, 4.5)
  end)

  -- the reward medals: a ring with diagonal stripes round a pale disc; the special one gold with
  -- coloured stars and a red bow
  local MEDAL = { { 238, 136, 187 }, { 150, 204, 60 }, { 250, 196, 50 }, { 214, 170, 110 }, { 110, 64, 30 } }
  local function medalRing(G, c, cLo)
    G.setColor(0, 0, 0, 0.15); circle(G, "fill", 30, 31, 29)
    within(G, radial(30, 30, 28.4, 28.4, 64, function() return 1 end), function()
      col(G, c); G.rectangle("fill", 0, 0, 60, 60)
      col(G, cLo)
      for k = -60, 60, 7 do fillShape(G, { k, 0, k + 3.5, 0, k + 63.5, 60, k + 60, 60 }) end
      vgrad(G, 0, 0, 60, 30, { 1, 1, 1, 0.25 }, { 1, 1, 1, 0 })
    end)
  end
  local function medalFace(G, top, low)
    col(G, c255(221, 204, 153)); circle(G, "fill", 30, 30, 22.4)
    within(G, radial(30, 30, 21.4, 21.4, 64, function() return 1 end), function()
      vgrad(G, 0, 8, 60, 44, top, low)
    end)
  end
  for i, m in ipairs(MEDAL) do
    local c = c255(m[1], m[2], m[3])
    local lo = c255(math.floor(m[1] * 0.78), math.floor(m[2] * 0.78), math.floor(m[3] * 0.78))
    local hi = c255(math.min(255, m[1] + 40), math.min(255, m[2] + 40), math.min(255, m[3] + 40))
    each({ "berry_reward", "head_reward", "tile_down" }, ("wappen_%02d"):format(i), 60, 60, function(G)
      medalRing(G, hi, c)
      medalFace(G, c255(255, 255, 255), c255(255, 246, 204))
      col(G, lo, 0.5); G.setLineWidth(0.8); G.circle("line", 30, 30, 28.2, 64)
    end)
  end
  each({ "berry_reward", "head_reward", "tile_down" }, "wappen_special", 60, 60, function(G)
    medalRing(G, c255(255, 230, 120), c255(250, 214, 80))
    medalFace(G, c255(224, 246, 252), c255(196, 236, 246))
    local stars = { { 250, 70, 200 }, { 40, 200, 140 }, { 250, 130, 40 }, { 60, 170, 250 }, { 230, 60, 220 }, { 40, 200, 160 }, { 250, 140, 30 } }
    for k, sc in ipairs(stars) do
      local a = math.pi * (0.95 - 0.9 * (k - 1) / (#stars - 1))
      local x, y = 30 + math.cos(a) * 25, 31 + math.sin(a) * 25
      col(G, c255(sc[1], sc[2], sc[3])); fillShape(G, starPts(x, y, 4.2, 0.5))
      G.setColor(1, 1, 1, 0.6); circle(G, "fill", x - 0.6, y - 0.8, 1)
    end
    -- the bow on top
    local red, redLo = c255(232, 40, 40), c255(170, 20, 20)
    for s = -1, 1, 2 do
      local tail = { 30, 6, 30 + s * 18, 4, 30 + s * 26, 10, 30 + s * 16, 11 }
      col(G, redLo); fillShape(G, tail)
      local loop = { 30, 6, 30 + s * 4, 0.5, 30 + s * 12, 1, 30 + s * 12, 8, 30 + s * 4, 9 }
      col(G, red); fillShape(G, loop)
    end
    col(G, redLo); circle(G, "fill", 30, 5.5, 3)
  end)

  -- the reward smoke: soft white puffs, solid at their middles, fading out
  local function smoke(G, w, h, blobs)
    for _, b in ipairs(blobs) do
      for i = 10, 1, -1 do
        G.setColor(1, 1, 1, 0.1 + 0.02 * (10 - i))
        circle(G, "fill", b[1] * w, b[2] * h, b[3] * math.min(w, h) * i / 10)
      end
    end
  end
  each({ "berry_reward", "head_reward", "tile_down" }, "smoke0", 54, 46, function(G, w, h)
    smoke(G, w, h, { { 0.5, 0.5, 0.42 }, { 0.3, 0.45, 0.3 }, { 0.7, 0.5, 0.3 }, { 0.5, 0.3, 0.3 } })
  end)
  each({ "berry_reward", "head_reward", "tile_down" }, "smoke1", 117, 93, function(G, w, h)
    smoke(G, w, h, { { 0.5, 0.52, 0.42 }, { 0.28, 0.4, 0.3 }, { 0.72, 0.42, 0.3 }, { 0.36, 0.72, 0.28 }, { 0.68, 0.72, 0.28 } })
  end)
  each({ "berry_reward", "head_reward", "tile_down" }, "smoke2", 80, 73, function(G, w, h)
    smoke(G, w, h, { { 0.5, 0.5, 0.42 }, { 0.32, 0.36, 0.3 }, { 0.68, 0.4, 0.3 }, { 0.5, 0.72, 0.3 } })
  end)

  -- Head It's sky clouds: white, flat underneath, a light blue line along their tops
  local function cloud(G, w, h, bumps)
    local base = h - 3
    local function shape(grow)
      for _, b in ipairs(bumps) do circle(G, "fill", b[1] * w, base - b[2] * h, b[3] * h + grow) end
      G.ellipse("fill", w / 2, base, w / 2 - 1 + grow, 2.4 + grow)
    end
    G.setColor(0.62, 0.82, 0.92, 1); shape(1)
    G.setColor(1, 1, 1, 1); shape(0)
    G.setColor(0.86, 0.94, 1, 1)
    for _, b in ipairs(bumps) do
      G.setLineWidth(0.8); G.arc("line", "open", b[1] * w, base - b[2] * h, b[3] * h - 1.6, math.pi * 1.15, math.pi * 1.6)
    end
  end
  for _, p in ipairs({ "head_rear", "head_bg" }) do
    gen("lyt/" .. p .. "/cloud_01", 114, 38, function(G, w, h)
      cloud(G, w, h, { { 0.26, 0.28, 0.24 }, { 0.42, 0.5, 0.34 }, { 0.6, 0.48, 0.32 }, { 0.75, 0.3, 0.22 } })
    end)
    gen("lyt/" .. p .. "/cloud_03", 66, 18, function(G, w, h)
      cloud(G, w, h, { { 0.42, 0.42, 0.34 }, { 0.6, 0.5, 0.4 }, { 0.75, 0.32, 0.28 } })
    end)
  end

  -- the RESULTS banner: an orange ribbon with its ends folded back, the word in red
  each({ "berry_lang", "head_front" }, "result_title", 230, 44, function(G)
    local orange, orangeLo, cream = c255(255, 153, 68), c255(204, 102, 34), c255(255, 204, 136)
    for s = -1, 1, 2 do
      local cx = 115 + s * 95
      local tail = { cx, 14, cx + s * 22, 6, cx + s * 14, 22, cx + s * 22, 38, cx, 34 }
      col(G, orangeLo); fillShape(G, tail)
    end
    within(G, { 18, 4, 212, 4, 212, 36, 18, 36 }, function()
      vgrad(G, 0, 4, 230, 32, orange, c255(255, 120, 60))
      col(G, cream); G.rectangle("fill", 22, 9, 186, 22, 3, 3)
      vgrad(G, 22, 9, 186, 10, { 1, 1, 1, 0.35 }, { 1, 1, 1, 0 })
    end)
    col(G, orangeLo); G.setLineWidth(1); G.rectangle("line", 18.5, 4.5, 193, 31)
    heavy(G, "RESULTS", 115, 20, 20, c255(200, 20, 30), C.white, 1.3, 1.2)
  end)

  -- Head It's results card: see-through white with a sketched tan border, a rule across and
  -- two short ticks down the right
  gen("lyt/head_front/win_heading", 258, 116, function(G, w, h)
    local tan = c255(241, 191, 117)
    local box = { 4, 6, w - 4, 4, w - 3, h - 5, 5, h - 4 }
    local r = K.roundPts(box, 10)
    G.setColor(1, 1, 1, 1 / 3); fillShape(G, r)
    G.setLineJoin("bevel")
    G.setLineWidth(3.2); col(G, c255(252, 211, 145), 0.7); G.line(closed(r))
    G.setLineWidth(1.4); col(G, tan); G.line(closed(r))
    G.setLineWidth(1.2); col(G, tan, 0.9)
    G.line(6, 50, w - 6, 50.6)
    G.line(222, 16, 222.6, 30); G.line(222, 64, 222.4, 104)
  end)

  -- Berry Picker's results panel: a see-through white rounded card
  gen("lyt/berry_score/result", 400, 240, function(G, w, h)
    G.setColor(1, 1, 1, 136 / 255)
    G.rectangle("fill", 8, 8, w - 16, h - 16, 14, 14)
  end)

  -- Head It's hit and miss marks: plain blocks of colour
  gen("lyt/head_ball/Hit01", 40, 60, function(G) G.setColor(0.95, 0.6, 0, 1); G.rectangle("fill", 0, 0, 40, 60) end)
  gen("lyt/head_ball/Hit02", 40, 60, function(G) G.setColor(0.9, 0, 0.06, 1); G.rectangle("fill", 0, 0, 40, 60) end)
  gen("lyt/head_ball/Miss", 40, 60, function(G) G.setColor(0.63, 0.63, 0.63, 1); G.rectangle("fill", 0, 0, 40, 60) end)

  -- ------- Tile Puzzle

  -- a tile's corner marks: an L at each corner (red for the chosen tile, pale blue for one out
  -- of place), a dark edge under each
  local function corners(G, c, cLo)
    local s, t, L = 46, 2.6, 12.5
    for _, k in ipairs({ { 0, 0, 1, 1 }, { s, 0, -1, 1 }, { 0, s, 1, -1 }, { s, s, -1, -1 } }) do
      local x, y, dx, dy = k[1], k[2], k[3], k[4]
      local pts = { x + dx * 1, y + dy * 1, x + dx * L, y + dy * 1, x + dx * L, y + dy * (1 + t),
        x + dx * (1 + t), y + dy * (1 + t), x + dx * (1 + t), y + dy * L, x + dx * 1, y + dy * L }
      col(G, cLo); fillShape(G, scaled(pts, x + dx * 6, y + dy * 6, 1.12))
      col(G, c); fillShape(G, pts)
    end
  end
  gen("lyt/tile_bound/cursol", 46, 46, function(G) corners(G, c255(214, 70, 40), c255(120, 30, 20, 200)) end)
  gen("lyt/tile_bound/frame", 46, 46, function(G) corners(G, c255(150, 222, 232), c255(60, 140, 150, 160)) end)
  -- the star bursting from a tile landing home
  gen("lyt/tile_bound/star", 20, 20, function(G)
    local pts = starPts(10, 10.6, 8.6, 0.48)
    col(G, c255(200, 140, 20)); fillShape(G, scaled(pts, 10, 10.6, 1.16))
    rings(G, pts, 10, 10.6, c255(250, 200, 40), c255(255, 246, 170), 8, 0.2)
  end)

  -- the orange buttons: a pill with a double rim, and a round one with an arrow
  local ORANGE, ORANGE_HI, ORANGE_LO, ORANGE_RIM = c255(250, 170, 120), c255(255, 214, 186), c255(236, 136, 86), c255(170, 80, 40)
  local function pillPts(x, y, w, h)
    local r = h / 2
    local pts = {}
    for i = 0, 16 do
      local a = math.pi / 2 + i / 16 * math.pi
      pts[#pts + 1] = x + r + math.cos(a) * r; pts[#pts + 1] = y + r + math.sin(a) * r
    end
    for i = 0, 16 do
      local a = -math.pi / 2 + i / 16 * math.pi
      pts[#pts + 1] = x + w - r + math.cos(a) * r; pts[#pts + 1] = y + r + math.sin(a) * r
    end
    return pts
  end
  local function orangePill(G, w, h)
    G.setColor(0, 0, 0, 0.2); fillShape(G, pillPts(1, 2, w - 2, h - 2))
    col(G, ORANGE_RIM); fillShape(G, pillPts(0.6, 0.6, w - 1.2, h - 2.2))
    within(G, pillPts(1.8, 1.8, w - 3.6, h - 4.6), function()
      vgrad(G, 0, 1, w, h - 4, ORANGE_HI, ORANGE_LO)
    end)
    G.setLineWidth(1); col(G, ORANGE_HI, 0.9); G.line(closed(pillPts(4, 4, w - 8, h - 9)))
    G.setColor(1, 1, 1, 0.3); G.ellipse("fill", w / 2, 8, w / 2 - 12, 3)
  end
  gen("lyt/tile_down/button_system", 110, 32, function(G, w, h) orangePill(G, w, h) end)
  gen("game/pill_button", 110, 32, function(G, w, h) orangePill(G, w, h) end)
  gen("lyt/tile_down/play_left", 42, 42, function(G)
    G.setColor(0, 0, 0, 0.25); circle(G, "fill", 21, 22, 20.4)
    col(G, c255(40, 24, 16)); circle(G, "fill", 21, 21, 20.2)
    col(G, ORANGE_RIM); circle(G, "fill", 21, 21, 18.6)
    within(G, radial(21, 21, 17.2, 17.2, 48, function() return 1 end), function()
      vgrad(G, 0, 4, 42, 34, ORANGE_HI, ORANGE_LO)
      G.setColor(1, 1, 1, 0.3); G.ellipse("fill", 21, 11, 12, 5)
    end)
    col(G, c255(150, 60, 10)); fillShape(G, { 12, 21, 26, 12.5, 26, 29.5 })
  end)

  -- the doors that close over the puzzle: dark, a diamond pattern, their meeting edge scalloped
  local function door(G, w, h, edgeRight)
    local pts = {}
    local bumps = 12
    local inset = 6
    -- the panel, its meeting edge a column of rounded bumps
    local outer = edgeRight and 0 or w
    pts[#pts + 1] = outer; pts[#pts + 1] = 0
    for i = 0, bumps * 8 do
      local yy = i / (bumps * 8) * h
      local bulge = math.abs(math.sin(yy / h * bumps * math.pi)) * inset
      pts[#pts + 1] = edgeRight and (w - inset + bulge) or (inset - bulge)
      pts[#pts + 1] = yy
    end
    pts[#pts + 1] = outer; pts[#pts + 1] = h
    within(G, pts, function()
      G.setColor(0.05, 0.05, 0.055, 1); G.rectangle("fill", 0, 0, w, h)
      G.setColor(0.11, 0.11, 0.12, 1)
      for y = -24, h + 24, 24 do
        for x = -24, w + 24, 24 do
          local ox = ((y / 24) % 2) * 12
          fillShape(G, { x + ox, y - 10, x + ox + 10, y, x + ox, y + 10, x + ox - 10, y })
        end
      end
    end)
    G.setLineWidth(1); G.setColor(0.25, 0.25, 0.27, 1)
    local edge = {}
    for i = 3, #pts - 4, 2 do edge[#edge + 1] = pts[i]; edge[#edge + 1] = pts[i + 1] end
    G.line(edge)
  end
  gen("lyt/tile_down/door_L", 180, 240, function(G, w, h) door(G, w, h, true) end)
  gen("lyt/tile_down/door_R", 180, 240, function(G, w, h) door(G, w, h, false) end)

  -- the wool along the top screen's rows: a twisted tan thread
  gen("lyt/tile_up/line_wool", 352, 8, function(G, w)
    G.setColor(0.55, 0.42, 0.2, 0.5); G.rectangle("fill", 0, 2.6, w, 3.4, 1.6, 1.6)
    col(G, c255(232, 196, 110)); G.rectangle("fill", 0, 3, w, 2.4, 1.2, 1.2)
    G.setColor(1, 0.95, 0.8, 0.7); G.setLineWidth(0.5)
    for x = 0, w, 3 do G.line(x, 3.2, x + 2, 5.2) end
  end)

  -- the top screen: a mint field under scalloped bands, pinked fabric swatches in its corners
  local function swatch(G, cx, cy, w, h, ang, base, pattern)
    G.push(); G.translate(cx, cy); G.rotate(ang)
    local pts = {}
    local n = 12
    local function edge(x0, y0, x1, y1)
      for i = 0, n - 1 do
        local t = i / n
        local px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        local nx, ny = (y1 - y0), -(x1 - x0)
        local d = math.sqrt(nx * nx + ny * ny)
        local k = (i % 2 == 0) and 0 or 1.6
        pts[#pts + 1] = px + nx / d * k; pts[#pts + 1] = py + ny / d * k
      end
    end
    edge(-w / 2, -h / 2, w / 2, -h / 2); edge(w / 2, -h / 2, w / 2, h / 2)
    edge(w / 2, h / 2, -w / 2, h / 2); edge(-w / 2, h / 2, -w / 2, -h / 2)
    G.setColor(0, 0, 0, 0.12); fillShape(G, scaled(pts, -2, -3, 1))
    within(G, pts, function()
      col(G, base); G.rectangle("fill", -w, -h, w * 2, h * 2)
      pattern(G, w, h)
    end)
    G.pop()
  end
  local function dots(c, step, r)
    return function(G, w, h)
      col(G, c)
      for y = -h, h, step do
        for x = -w, w, step do circle(G, "fill", x + ((y / step) % 2) * step / 2, y, r) end
      end
    end
  end
  local function check(c, step)
    return function(G, w, h)
      col(G, c, 0.5)
      for x = -w, w, step * 2 do G.rectangle("fill", x, -h, step, h * 2) end
      for y = -h, h, step * 2 do G.rectangle("fill", -w, y, w * 2, step) end
    end
  end
  local function stripes(c, step)
    return function(G, w, h)
      col(G, c)
      for x = -w * 2, w * 2, step * 2 do fillShape(G, { x, -h, x + step, -h, x + step + h * 2, h, x + h * 2, h }) end
    end
  end
  gen("lyt/tile_up/bg_up", 400, 240, function(G, w, h)
    vgrad(G, 0, 0, w, h, c255(120, 226, 186), c255(150, 236, 200))
    -- the bands top and bottom, their inner edges scalloped
    for _, top in ipairs({ true, false }) do
      local y0 = top and 0 or h
      local pts = { 0, y0 }
      for x = 0, w, 2 do
        local b = 12 + math.abs(math.sin(x / w * math.pi * 9)) * 7
        pts[#pts + 1] = x; pts[#pts + 1] = top and b or h - b
      end
      pts[#pts + 1] = w; pts[#pts + 1] = y0
      col(G, c255(96, 206, 170)); fillShape(G, pts)
    end
    G.setColor(1, 1, 1, 0.18); G.rectangle("fill", 0, 60, w, 4); G.rectangle("fill", 0, 176, w, 4)
    -- the swatches
    swatch(G, 26, 14, 82, 74, -0.25, c255(255, 238, 140), dots(c255(255, 255, 255), 7, 1.6))
    swatch(G, 382, 12, 96, 70, 0.6, c255(160, 226, 250), check(c255(255, 255, 255), 5))
    swatch(G, 60, 226, 96, 70, 0.35, c255(170, 240, 214), check(c255(255, 255, 255), 5))
    swatch(G, 18, 236, 54, 50, -0.4, c255(255, 214, 160), dots(c255(255, 255, 255), 6, 1.2))
    swatch(G, 370, 232, 110, 90, -0.6, c255(250, 236, 252), check(c255(220, 200, 240), 6))
    -- ribbons across the corners
    swatch(G, 100, 10, 120, 12, -0.5, c255(214, 196, 246), stripes(c255(255, 255, 255), 3))
    swatch(G, 382, 140, 12, 150, 0.2, c255(180, 196, 246), dots(c255(255, 255, 255), 5, 1))
    swatch(G, 28, 210, 12, 90, -0.7, c255(110, 170, 240), stripes(c255(255, 255, 255), 3))
  end)

  -- ------- Tile Puzzle's picture: its sky, sea, night star and photo frames

  -- the sky strip: four columns (day, deep blue, sunset, night), each a ramp from top to foot
  local SKY = {
    { { 47, 171, 245 }, { 71, 186, 244 }, { 94, 201, 250 }, { 131, 213, 246 }, { 115, 157, 206 } },
    { { 0, 25, 124 }, { 5, 46, 161 }, { 8, 66, 198 }, { 31, 105, 212 }, { 91, 190, 247 } },
    { { 178, 161, 103 }, { 226, 184, 77 }, { 250, 193, 61 }, { 245, 154, 47 }, { 252, 71, 5 } },
    { { 2, 2, 10 }, { 2, 10, 51 }, { 9, 17, 83 }, { 16, 32, 115 }, { 35, 59, 183 } },
  }
  gen("tile/sky", 64, 128, function(G)
    for c, ramp in ipairs(SKY) do
      for i = 1, #ramp - 1 do
        local a, b = ramp[i], ramp[i + 1]
        vgrad(G, (c - 1) * 16, (i - 1) * 32, 16, 32, c255(a[1], a[2], a[3]), c255(b[1], b[2], b[3]))
      end
    end
  end)

  -- the sea: a tile of water with light caustics - cells of water, brighter along the edges
  -- where they meet, deeper toward their middles - tiling seamlessly; three moods
  local function sea(G, base, dark, light, seed)
    local N = 128
    local rng = love.math.newRandomGenerator(seed)
    local pts = {}
    for _ = 1, 64 do pts[#pts + 1] = { rng:random() * N, rng:random() * N } end
    local data = love.image.newImageData(N, N)
    data:mapPixel(function(x, y)
      -- the nearest two cell middles, the tile wrapped round
      local d1, d2 = 1e9, 1e9
      -- a gentle warp (whole waves across the tile, so it still wraps) rounds the cells' edges
      local wx = x + 0.5 + math.sin(y / N * math.pi * 6) * 2.2
      local wy = y + 0.5 + math.sin(x / N * math.pi * 6) * 2.2
      for _, p in ipairs(pts) do
        local dx = math.abs(wx - p[1]) % N; if dx > N / 2 then dx = N - dx end
        local dy = math.abs(wy - p[2]) % N; if dy > N / 2 then dy = N - dy end
        local d = dx * dx + dy * dy
        if d < d1 then d1, d2 = d, d1 elseif d < d2 then d2 = d end
      end
      d1, d2 = math.sqrt(d1), math.sqrt(d2)
      local edge = math.max(0, 1 - (d2 - d1) / 3.2) ^ 1.5
      local deep = math.min(1, d1 / 9)
      local r = base[1] + (dark[1] - base[1]) * deep * 0.6
      local g = base[2] + (dark[2] - base[2]) * deep * 0.6
      local b = base[3] + (dark[3] - base[3]) * deep * 0.6
      return r + (light[1] - r) * edge * 0.75, g + (light[2] - g) * edge * 0.75, b + (light[3] - b) * edge * 0.75, 1
    end)
    local img = love.graphics.newImage(data)
    img:setFilter("linear", "linear")
    G.setColor(1, 1, 1, 1)
    G.draw(img, 0, 0)
  end
  gen("tile/sea_day", 128, 128, function(G) sea(G, c255(143, 226, 250), c255(125, 216, 255), c255(220, 252, 255), 21) end)
  gen("tile/sea_dusk", 128, 128, function(G) sea(G, c255(165, 181, 223), c255(146, 163, 229), c255(214, 224, 252), 21) end)
  gen("tile/sea_night", 128, 128, function(G) sea(G, c255(18, 101, 183), c255(6, 97, 179), c255(70, 150, 200), 21) end)

  -- a star of the night sky: a small white twinkle
  gen("tile/night_star", 32, 32, function(G)
    G.setColor(1, 1, 1, 0.25); circle(G, "fill", 16, 16, 6)
    G.setColor(1, 1, 1, 1)
    fillShape(G, { 16, 8, 17.2, 14.8, 24, 16, 17.2, 17.2, 16, 24, 14.8, 17.2, 8, 16, 14.8, 14.8 })
  end)

  -- the photo frames: a border of fabric patches round a clear window (the texture's top
  -- 128 x 104), a dark line along its inner top and left
  local function fabric(kind, c, c2)
    return function(G, x, y, w, h)
      col(G, c); G.rectangle("fill", x, y, w, h)
      col(G, c2)
      if kind == "diamond" then
        for yy = y - 6, y + h + 6, 6 do
          for xx = x - 6, x + w + 6, 6 do
            local o = ((yy - y) / 6 % 2) * 3
            fillShape(G, { xx + o, yy - 3, xx + o + 3, yy, xx + o, yy + 3, xx + o - 3, yy })
          end
        end
      elseif kind == "stripe" then
        for k = -h, w + h, 5 do fillShape(G, { x + k, y, x + k + 2.5, y, x + k + 2.5 + h, y + h, x + k + h, y + h }) end
      elseif kind == "dots" then
        for yy = y + 2, y + h, 5 do
          for xx = x + 2, x + w, 5 do circle(G, "fill", xx + ((yy - y) / 5 % 2) * 2.5, yy, 1) end
        end
      elseif kind == "scallop" then
        for xx = x, x + w, 6 do circle(G, "fill", xx + 3, y + h, 3.4) end
      end
      vgrad(G, x, y, w, h, { 1, 1, 1, 0.25 }, { 0, 0, 0, 0.08 })
    end
  end
  local function photoFrame(G, patches)
    local B = 7
    -- the border, patch by patch, kept to the ring round the window
    G.stencil(function() G.rectangle("fill", 0, 0, 128, 104) end, "replace", 1)
    G.stencil(function() G.rectangle("fill", B, B, 128 - 2 * B, 104 - 2 * B) end, "replace", 0, true)
    G.setStencilTest("greater", 0)
    for _, p in ipairs(patches) do p[5](G, p[1], p[2], p[3], p[4]) end
    G.setStencilTest()
    -- a ragged step where two patches meet is the picture's; the inner shadow and outer edge
    G.setColor(0, 0, 0, 0.55); G.rectangle("fill", B, B, 128 - 2 * B, 1); G.rectangle("fill", B, B, 1, 104 - 2 * B)
    G.setColor(0, 0, 0, 0.2); G.setLineWidth(0.8); G.rectangle("line", 0.4, 0.4, 127.2, 103.2)
  end
  local CREAM = fabric("plain", c255(250, 222, 160), c255(0, 0, 0))
  local CYAN = fabric("diamond", c255(80, 210, 240), c255(170, 238, 250))
  gen("tile/frame_easy", 128, 128, function(G)
    photoFrame(G, {
      { 0, 0, 72, 104, CREAM }, { 72, 0, 56, 52, CYAN }, { 72, 52, 56, 52, CREAM },
      { 0, 52, 62, 52, CYAN }, { 62, 96, 66, 8, CREAM },
    })
  end)
  local LILAC = fabric("stripe", c255(206, 150, 240), c255(226, 186, 250))
  local YELLOW = fabric("dots", c255(250, 236, 140), c255(255, 250, 220))
  local PURPLE = fabric("plain", c255(190, 120, 236), c255(0, 0, 0))
  local PEACH = fabric("stripe", c255(250, 196, 140), c255(255, 222, 186))
  local PINK = fabric("stripe", c255(250, 214, 236), c255(255, 236, 248))
  local BLUE = fabric("dots", c255(150, 180, 250), c255(200, 216, 255))
  local TEAL = fabric("dots", c255(70, 200, 190), c255(150, 230, 222))
  gen("tile/frame_normal", 128, 128, function(G)
    photoFrame(G, {
      { 0, 0, 40, 8, LILAC }, { 40, 0, 20, 8, YELLOW }, { 60, 0, 36, 8, PURPLE }, { 96, 0, 32, 8, PEACH },
      { 120, 8, 8, 24, PEACH }, { 120, 32, 8, 18, PINK }, { 120, 50, 8, 54, BLUE },
      { 0, 8, 8, 48, YELLOW }, { 0, 56, 8, 48, TEAL },
      { 0, 96, 24, 8, TEAL }, { 24, 96, 38, 8, PURPLE }, { 62, 96, 50, 8, PINK }, { 112, 96, 16, 8, PURPLE },
    })
  end)
  local GREEN = fabric("plain", c255(60, 196, 150), c255(0, 0, 0))
  local MINT = fabric("scallop", c255(110, 220, 190), c255(190, 244, 228))
  local SAND = fabric("dots", c255(250, 214, 160), c255(255, 236, 206))
  gen("tile/frame_hard", 128, 128, function(G)
    photoFrame(G, {
      { 0, 0, 46, 104, GREEN }, { 46, 0, 82, 8, MINT }, { 120, 8, 8, 96, GREEN },
      { 0, 42, 8, 44, SAND }, { 120, 16, 8, 38, SAND }, { 0, 96, 78, 8, MINT }, { 78, 96, 50, 8, GREEN },
    })
  end)

  -- ------- the soft painted clouds (Tile Puzzle's horizon, PLAY's sky, the top screens): blobs
  -- built up in faint layers, cut flat along a base and shaded pale blue toward it
  local function softClouds(G, blobs, base)
    local function union(grow)
      for _, b in ipairs(blobs) do circle(G, "fill", b[1], b[2], b[3] * grow) end
    end
    for i = 1, 16 do
      G.setColor(1, 1, 1, 0.075)
      union(1.15 - i * 0.045)
    end
    -- the underside: pale blue, deepest at the base
    G.stencil(function() union(0.95) end, "replace", 1)
    G.setStencilTest("greater", 0)
    vgrad(G, 0, base - 46, 256, 46, { 0.72, 0.84, 0.98, 0 }, { 0.72, 0.84, 0.98, 0.55 })
    G.setStencilTest()
    -- the base, feathered: everything below it fades out over a few units
    G.setBlendMode("multiply", "premultiplied")
    vgrad(G, 0, base - 8, 256, 10, { 1, 1, 1, 1 }, { 0, 0, 0, 0 })
    G.setColor(0, 0, 0, 0); G.rectangle("fill", 0, base + 2, 256, 128)
    G.setBlendMode("alpha")
  end
  gen("scene/cloud", 256, 128, function(G)
    softClouds(G, { { 75, 38, 24 }, { 58, 56, 26 }, { 96, 54, 27 }, { 120, 68, 23 }, { 144, 82, 17 },
      { 168, 92, 10 }, { 36, 78, 20 }, { 86, 78, 26 }, { 115, 86, 20 }, { 60, 88, 18 }, { 148, 94, 12 } }, 100)
    softClouds(G, { { 230, 32, 8 }, { 232, 42, 8 }, { 230, 92, 8 }, { 229, 102, 7 } }, 128)
  end)
  gen("scene/cumulus", 256, 128, function(G)
    softClouds(G, { { 160, 34, 20 }, { 150, 56, 22 }, { 174, 60, 22 }, { 60, 100, 20 }, { 90, 92, 24 },
      { 120, 98, 22 }, { 190, 90, 24 }, { 220, 102, 18 }, { 140, 100, 22 }, { 40, 108, 14 }, { 240, 110, 10 },
      -- the bank joined up under the tall top
      { 118, 82, 24 }, { 140, 78, 26 }, { 162, 82, 26 }, { 104, 100, 22 }, { 160, 102, 24 }, { 205, 104, 20 } }, 118)
  end)
end
