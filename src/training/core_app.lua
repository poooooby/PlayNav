-- SUPER TRAINING, the Core Training screen on the bottom: the Pokemon beside its training
-- bag (tap the bag to hit it, tap the Pokemon to wake it), the Effort-o-Meter with the
-- total gauge, the rest of the party, and the REGIMENS / BAGS buttons.
--
-- Laid out by the game's own layout, training_lower.bclyt (the a/0/2/7 entry 0 darc; dump
-- it with tools/clyt.py). PANE holds its panes as centre x, centre y, width, height in the
-- layout's 320x240 space, drawn in its order; everything is scaled by L onto the 256x192
-- surface. The bottom icon row and the PlayNav strip are system chrome, not this layout.

return function(mod, Pointer, T, Rules, Radar, host)

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "training_core", title = "SUPER TRAINING", live = true, hideTabs = true }
  local N = Rules.N

  function app:wantsSurface() return T.session ~= nil and T.session.mode == "core" end

  local L = 256 / 320
  -- vertex colours run top-left, top-right, bottom-left, bottom-right, as in the layout
  local WHITE4 = { { 255, 255, 255, 255 }, { 255, 255, 255, 255 }, { 255, 255, 255, 255 }, { 255, 255, 255, 255 } }
  local FADE_L = { { 124, 167, 196, 255 }, { 255, 255, 255, 255 }, { 124, 167, 196, 255 }, { 255, 255, 255, 255 } }
  local FADE_R = { { 255, 255, 255, 255 }, { 124, 167, 196, 255 }, { 255, 255, 255, 255 }, { 124, 167, 196, 255 } }
  local PANE = {
    bg = { 160, 120, 330, 250, colors = { { 0, 111, 209, 255 }, { 0, 111, 209, 255 }, { 84, 200, 255, 255 }, { 84, 200, 255, 255 } } },
    glowLow = { 160, 167, 320, 50, colors = { { 168, 226, 255, 30 }, { 168, 226, 255, 30 }, { 168, 226, 255, 255 }, { 168, 226, 255, 255 } } },
    glowHigh = { 160, 82, 320, 120, flipY = true, colors = { { 168, 226, 255, 255 }, { 168, 226, 255, 255 }, { 168, 226, 255, 30 }, { 168, 226, 255, 30 } } },
    ptn = { 160, 120, 320, 160, repeatU = 8, repeatV = 4, colors = { { 0, 80, 147, 150 }, { 0, 80, 147, 150 }, { 0, 80, 147, 150 }, { 0, 80, 147, 150 } } },
    bag = { 50, 106, 40, 100, alpha = 200 },
    mon = { 110, 138 },
    mood = { 138, 117, 32, 32 },
    hit = { 50, 120, 64, 64 },
    frameL = { 80, 50, 160, 60, colors = FADE_L },
    frameR = { 240, 50, 160, 60, flipX = true, colors = FADE_R },
    trayL = { 80, 193, 160, 60, colors = FADE_L },
    trayR = { 240, 193, 160, 60, flipX = true, colors = FADE_R },
    meter = { 240, 110, 150, 150, alpha = 180 },
    -- the hexagon's centre and corner radius (its texture centre (63.5, 85.5), r 50.5)
    hex = { 228.5, 120.5, r = 50.5 },
    gauge = { 308, 167, 4, 130, colors = { { 186, 255, 122, 123 }, { 186, 255, 122, 255 }, { 186, 255, 122, 123 }, { 186, 255, 122, 255 } } },
    shotWin = { 258, 40, 50, 40, colors = { { 255, 255, 255, 255 }, { 189, 141, 141, 255 }, { 255, 255, 255, 255 }, { 189, 141, 141, 255 } } },
    shot = { 252, 38, 32, 32 },
    perfect = { 62, 40, 50, 40, colors = { { 168, 226, 255, 255 }, { 255, 255, 255, 255 }, { 168, 226, 255, 255 }, { 255, 255, 255, 255 } } },
    label = { hp = { 227, 74 }, atk = { 271, 94 }, spa = { 184, 94 }, spd = { 184, 148 }, def = { 271, 148 }, spe = { 227, 168 } },
    name = { 160, 40, 120, 20 },
    regimens = { 32, 186, 64, 64 },
    bags = { 292, 193, 48, 48 },
    icons = { { 88, 190 }, { 124, 190 }, { 160, 190 }, { 196, 190 }, { 232, 190 } },
    iconSize = { 40, 30 },
  }

  -- hit rects in app space: the layout's rect scaled by L, less the hidden tab strip
  local BLEED = 14
  local function rect(cx, cy, w, h)
    return { x = (cx - w / 2) * L, y = (cy - h / 2) * L - BLEED, w = w * L, h = h * L }
  end
  local PIC = rect(110, 128, 80, 80)
  local BAG = rect(50, 106, 40, 100)
  local REGIMENS = rect(32, 186, 64, 64)
  local BAGS = rect(292, 193, 48, 48)
  local TOTAL = rect(308, 102, 10, 130)
  -- the room between the name frame and the tray (the layout's 320x240: y 60..165)
  local ROOM = rect(160, 112.5, 320, 105)
  local RADAR = { cx = PANE.hex[1] * L, cy = PANE.hex[2] * L - BLEED, r = PANE.hex.r * L }

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  local function fonts()
    if app.fontsFn then
      local f, s = app.fontsFn()
      if f then return f, s or f end
    end
    local f = love.graphics.getFont()
    return f, f
  end

  local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

  -- the party: the active Pokemon stands in the room; the others take the layout's icon
  -- slots in party order. partySlot(i) is where party member i can be tapped.
  local function slotOf(i)
    local party = T.party and T.party() or {}
    local n = 0
    for j, p in ipairs(party) do
      if j == i then
        if p.active then return PIC end
        local at = PANE.icons[n + 1]
        if not at then return nil end
        return rect(at[1], at[2], PANE.iconSize[1], PANE.iconSize[2])
      end
      if not p.active then n = n + 1 end
    end
    return nil
  end

  function app.geometry()
    return { PIC = PIC, BAG = BAG, RADAR = RADAR, TOTAL = TOTAL, REGIMENS = REGIMENS, BAGS = BAGS, ROOM = ROOM, partySlot = slotOf }
  end

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "core") then return end
    if ev.phase ~= "released" then return end
    -- any touch keeps the Pokemon from dozing off
    if T.touch then T.touch() end
    if not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    if inRect(x, y, BAG) then T.hitBag("tap"); return end
    if inRect(x, y, PIC) then
      if s.rec.resting then T.wake() else T.hitBag("tap") end
      return
    end
    if inRect(x, y, REGIMENS) then
      if T.enterCourses then T.enterCourses() end
      return
    end
    if inRect(x, y, BAGS) then T.enterBags(); return end
    for i, p in ipairs(T.party()) do
      local r = slotOf(i)
      if r and not p.active and inRect(x, y, r) then
        T.switchTo(p.mon)
        return
      end
    end
    -- as in the game, a tap anywhere in the room punches the bag (or wakes the Pokemon)
    if inRect(x, y, ROOM) then
      if s.rec.resting then T.wake() else T.hitBag("tap") end
    end
  end

  -- ------- the game's animations (training_lower_*.bclan, dumped with tools/clan.py), played
  -- at 30 frames a second. A track is a list of hermite keys { frame, value, slope }; two
  -- keys on one frame are a jump. Translations are the layout's (y up, from the screen's
  -- centre), rotations in degrees counter-clockwise.
  local FPS = 30
  local TRACK = {
    -- trpk_defo, pane 2i: the idle sway, bob and tilt (100-frame loop)
    idle = {
      loop = 100,
      tx = { { 0, -50, 1 }, { 10, -40, 1 }, { 10, -40, -1 }, { 20, -50, -1 }, { 30, -60, -1 }, { 30, -60, 1 }, { 40, -50, 1 }, { 40, -50, 0 } },
      ty = { { 0, -18, 0.8 }, { 5, -14, 0 }, { 10, -18, -0.8 }, { 10, -18, 0.8 }, { 15, -14, 0 }, { 20, -18, -0.8 }, { 20, -18, 0.8 },
        { 25, -14, 0 }, { 30, -18, -0.8 }, { 30, -18, 0.8 }, { 35, -14, 0 }, { 40, -18, 0 }, { 60, -18, 0 }, { 60, -18, 0.8 },
        { 65, -14, 0 }, { 70, -18, -0.8 }, { 70, -18, 0.8 }, { 75, -14, 0 }, { 80, -18, -0.8 }, { 80, -18, 0 } },
      rz = { { 0, 0, -1 }, { 10, -10, 0 }, { 20, 0, 1 }, { 30, 10, 0 }, { 40, 0, 0 } },
    },
    -- pane 40: lying down while resting (80-frame loop)
    rest = {
      loop = 80,
      tx = { { 0, -50, 0.2 }, { 20, -46, 0 }, { 40, -50, -0.2 }, { 60, -54, 0 }, { 80, -50, 0.2 } },
      ty = { { 0, -18, 0 } },
      rz = { { 0, -90, -0.5 }, { 20, -100, 0 }, { 40, -90, 0.5 }, { 60, -80, 0 }, { 80, -90, -0.5 } },
    },
    -- trpk_yaruki, pane 3z: woken up and raring to go (a jitter, two hops, a high one)
    wake = {
      frames = 43, loop = 60,
      tx = { { 0, -50, -1.5 }, { 2, -53, 0 }, { 4, -50, 0 }, { 6, -53, 0 }, { 8, -50, 0 }, { 10, -53, 0 }, { 12, -50, 0 } },
      ty = { { 12, -18, 0 }, { 16, -18, 0 }, { 16, -18, 6 }, { 19, 0, 0 }, { 22, -18, -6 }, { 22, -18, 6 }, { 25, 0, 0 },
        { 28, -18, -6 }, { 28, -18, 0 }, { 33, -18, 0 }, { 33, -18, 7.6 }, { 38, 20, 0 }, { 43, -18, -7.6 }, { 43, -18, 0 } },
      rz = { { 0, 0, 0 } },
    },
    -- trpk_punching / hit_effect, pane 42: the lunge into the bag and back
    punch = {
      tx = { { 0, -50, -22.5 }, { 2, -95, 0 }, { 4, -95, 0 }, { 6, -50, 22.5 } },
      ty = { { 0, -18, 9.5 }, { 2, 1, 0 }, { 4, -18, -9.5 }, { 4, -18, 5 }, { 5, -13, 0 }, { 6, -18, -5 } },
      rz = { { 0, 0, 10 }, { 2, 20, 0 }, { 4, 0, 0 } },
    },
    -- pane 4x: the bag's swing about its centre
    bag = { rz = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, -15, 1 }, { 5, 5, 0.084 }, { 7, 0, -2.5 } } },
    -- pane q: the background's shake
    shake = { ty = { { 0, 0, 1 }, { 2, 2, -0.25 }, { 4, -1, -0.25 }, { 6, 1, 0.25 }, { 8, 0, -0.25 } } },
    -- pane 4z (pic 50): the hit mark at the bag, frames 1..6
    mark = {
      show = { 1, 6 },
      s = { { 2, 1, 0.125 }, { 6, 1.5, 0.125 } },
      a = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, 255, 0 }, { 6, 0, 0 } },
    },
    -- pane 4y (pic 18): the second mark, a burst then a smaller one lower right, frames 1..12
    mark2 = {
      show = { 1, 12 },
      tx = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, -4.667, 0 }, { 6, -4.667, 0 }, { 6, 12, 0 }, { 12, 12, 0 } },
      ty = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, -1.556, 0 }, { 6, -1.556, 0 }, { 6, -20.667, 0 }, { 12, -20.667, 0 } },
      s = { { 0, 1, 0 }, { 2, 1, 0 }, { 2, 1, 0.1 }, { 5, 1.5, 0 }, { 6, 1.5, 0 }, { 6, 1, 0 }, { 9, 1.5, 0 } },
      a = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, 255, 20 }, { 5, 100, 0 }, { 6, 100, 0 }, { 6, 255, -25 }, { 9, 0, 0 } },
    },
  }
  -- the + pattern scrolls by (-2, -1) tiles every 200 frames (bg_anime, pane 21)
  local PTN_SCROLL = { u = -2 / 200, v = -1 / 200 }
  local HIT_FRAMES = 13

  -- value of a key track at frame f (holds the ends)
  local function eval(keys, f)
    if not keys or #keys == 0 then return nil end
    if f <= keys[1][1] then return keys[1][2] end
    for i = 1, #keys - 1 do
      local a, b = keys[i], keys[i + 1]
      if f < b[1] then
        local span = b[1] - a[1]
        if span <= 0 then return b[2] end
        local t = (f - a[1]) / span
        local t2, t3 = t * t, t * t * t
        return (2 * t3 - 3 * t2 + 1) * a[2] + (t3 - 2 * t2 + t) * a[3] * span
          + (-2 * t3 + 3 * t2) * b[2] + (t3 - t2) * b[3] * span
      end
    end
    return keys[#keys][2]
  end
  app.eval = eval
  app.TRACK = TRACK

  -- the clock: frames since the screen opened, and since the last hit on the bag
  app.clock, app.hitAt = 0, nil
  local lastHit, lastResting = 0, false
  function app:update(dt)
    app.clock = app.clock + (dt or 0) * FPS
    local s = T.session
    local hit = s and s.anim and s.anim.hit or 0
    if hit > lastHit + 1e-6 then app.hitAt = app.clock end
    lastHit = hit
    -- the moment it gets up, the wake-up clip plays
    local resting = s ~= nil and s.rec.resting and true or false
    if lastResting and not resting then app.wakeAt = app.clock end
    lastResting = resting
  end
  local function sinceHit()
    if not app.hitAt then return nil end
    local f = app.clock - app.hitAt
    if f > HIT_FRAMES then return nil end
    return f
  end

  -- ------- drawing in layout units (the caller scales by L)

  -- a pane: image (or a plain quad when img is nil) over the rect centred at (cx, cy),
  -- with the layout's four vertex colours, mirroring and repeat. Meshes are kept per key.
  app.meshes = {}
  local function pane(G, key, img, p, opts)
    opts = opts or p
    local cx, cy, w, h = p[1], p[2], p[3], p[4]
    local x0, y0 = cx - w / 2, cy - h / 2
    local cols = opts.colors or WHITE4
    local a = (opts.alpha or 255) / 255
    local u0, u1 = 0, opts.repeatU or 1
    local v0, v1 = 0, opts.repeatV or 1
    if opts.flipX then u0, u1 = u1, u0 end
    if opts.flipY then v0, v1 = v1, v0 end
    local m = app.meshes[key]
    if not m or m.img ~= img then
      local function v(x, y, u, vv, c) return { x, y, u, vv, c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255 * a } end
      local mesh = G.newMesh({
        v(x0, y0, u0, v0, cols[1]), v(x0 + w, y0, u1, v0, cols[2]),
        v(x0 + w, y0 + h, u1, v1, cols[4]), v(x0, y0 + h, u0, v1, cols[3]),
      }, "fan", "static")
      if img then
        if opts.repeatU then img:setWrap("repeat", "repeat") end
        mesh:setTexture(img)
      end
      m = { mesh = mesh, img = img }
      app.meshes[key] = m
    end
    G.draw(m.mesh)
  end

  -- an image fitted into a pane rect, optionally tinted (no mesh)
  local function fit(G, img, p, flipX, tint, alpha)
    local iw, ih = img:getDimensions()
    local sx, sy = p[3] / iw, p[4] / ih
    local t = tint or { 255, 255, 255 }
    G.setColor(t[1] / 255, t[2] / 255, t[3] / 255, (alpha or 255) / 255)
    if flipX then
      G.draw(img, p[1] + p[3] / 2, p[2] - p[4] / 2, 0, -sx, sy)
    else
      G.draw(img, p[1] - p[3] / 2, p[2] - p[4] / 2, 0, sx, sy)
    end
  end

  local function drawRoom(G)
    local bg01, ptn = art("training/home_bg01"), art("training/home_bg_ptn")
    local f = sinceHit()
    local shake = f and eval(TRACK.shake.ty, f) or 0
    G.setColor(1, 1, 1, 1)
    G.push()
    G.translate(0, -shake)
    pane(G, "bg", nil, PANE.bg)
    if bg01 then
      pane(G, "glowLow", bg01, PANE.glowLow)
      pane(G, "glowHigh", bg01, PANE.glowHigh)
    end
    G.pop()
    if ptn then
      local p, c = PANE.ptn, PANE.ptn.colors[1]
      local tw, th = ptn:getDimensions()
      ptn:setWrap("repeat", "repeat")
      local t = app.clock % 200
      app.ptnQuad = app.ptnQuad or G.newQuad(0, 0, tw * p.repeatU, th * p.repeatV, tw, th)
      app.ptnQuad:setViewport(-PTN_SCROLL.u * t * tw, -PTN_SCROLL.v * t * th, tw * p.repeatU, th * p.repeatV, tw, th)
      G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
      G.draw(ptn, app.ptnQuad, p[1] - p[3] / 2, p[2] - p[4] / 2, 0, p[3] / (tw * p.repeatU), p[4] / (th * p.repeatV))
    end
  end

  local function drawBag(G, s, small)
    local bag = s.rec.bag
    local def = bag and Rules.bag(bag.id)
    local p = PANE.bag
    local f = sinceHit()
    local swing = f and math.rad(-(eval(TRACK.bag.rz, f) or 0)) or 0
    -- an attached bag shows its own art; otherwise the game's grey punching bag
    local img = def and art(("training/sand_bag_%02d"):format(Rules.BAG_ART[def.id] or 0)) or art("training/home_sand_bag")
    if img then
      local iw, ih = img:getDimensions()
      G.setColor(1, 1, 1, (p.alpha or 255) / 255)
      G.draw(img, p[1], p[2], swing, p[3] / iw, p[4] / ih, iw / 2, ih / 2)
    else
      local rgb = (def and def.stat and T.STAT_RGB[def.stat]) or { 0.35, 0.38, 0.45 }
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.push()
      G.translate(p[1], p[2])
      G.rotate(swing)
      G.rectangle("fill", -14, -42, 28, 84, 10, 10)
      G.pop()
    end
    if bag then
      G.setFont(small)
      G.setColor(1, 1, 1, 0.95)
      G.printf(("%d/%d"):format(bag.hits, bag.needed), p[1] - 30, p[2] + p[4] / 2 + 2, 60 * L, "center", 0, 1 / L, 1 / L)
    end
  end

  local function activeIcon()
    for _, p in ipairs(T.party and T.party() or {}) do
      if p.active then return p.icon end
    end
  end

  local function drawMon(G, s, small, font)
    local f = sinceHit()
    local tr, at
    local woke = app.wakeAt and (app.clock - app.wakeAt) or nil
    local fainted = T.state and T.state().fainted
    if s.rec.resting or fainted then
      tr, at = TRACK.rest, app.clock % TRACK.rest.loop
    elseif not f and T.refreshed() then
      -- a second wind: the motivated clip on loop, for as long as it lasts
      tr, at = TRACK.wake, (woke or app.clock) % TRACK.wake.loop
    elseif woke and woke < TRACK.wake.frames and not f then
      tr, at = TRACK.wake, woke
    elseif f then
      tr, at = TRACK.punch, f
    else
      tr, at = TRACK.idle, app.clock % TRACK.idle.loop
    end
    local x = 160 + (eval(tr.tx, at) or -50)
    local y = 120 - (eval(tr.ty, at) or -18)
    local r = math.rad(-(eval(tr.rz, at) or 0))
    local icon = activeIcon()
    G.setColor(1, 1, 1, 200 / 255)
    if icon and icon.image then
      local q = icon.quads and (icon.quads[0] or icon.quads[1])
      local fw, fh = icon.w or 32, icon.h or 32
      local k = 2 * 40 / fw   -- the game's 40x30 icon drawn 80x60
      if q then
        drawPixel(icon.image, q, x, y, r, k, k, fw / 2, fh / 2)
      else
        drawPixel(icon.image, x, y, r, k, k, fw / 2, fh / 2)
      end
    elseif s.pic and s.pic.image then
      local pw, ph = s.pic.w or 64, s.pic.h or 64
      drawPixel(s.pic.image, x, y, r, 1, 1, pw / 2, ph / 2)
    end
    -- the hit marks at the bag
    local burst = f and art("training/burst")
    if burst then
      local bw, bh = burst:getDimensions()
      local m = TRACK.mark
      if f >= m.show[1] and f < m.show[2] then
        local sc = (eval(m.s, f) or 1) * 64 / bw
        G.setColor(1, 1, 1, (eval(m.a, f) or 0) / 255 * 200 / 255)
        G.draw(burst, PANE.hit[1], PANE.hit[2], 0, sc, sc, bw / 2, bh / 2)
      end
      local m2 = TRACK.mark2
      if f >= m2.show[1] and f < m2.show[2] then
        local sc = (eval(m2.s, f) or 1) * 64 / bw
        G.setColor(1, 1, 1, math.max(0, eval(m2.a, f) or 0) / 255 * 200 / 255)
        G.draw(burst, PANE.hit[1] + (eval(m2.tx, f) or 0), PANE.hit[2] - (eval(m2.ty, f) or 0), 0, sc, sc, bw / 2, bh / 2)
      end
    end
    local mood = (fainted and "sad") or (s.rec.resting and "silence") or (T.refreshed() and "smile")
      or ((s.anim.burst or 0) > 0 and "surprise") or nil
    local bubble = mood and art("training/mood_" .. mood)
    if bubble then
      fit(G, bubble, PANE.mood)
    elseif mood then
      G.setFont(font)
      G.setColor(1, 1, 1, 0.9)
      G.print(mood == "silence" and "..." or (mood == "smile" and ":)" or "!"), PANE.mood[1], PANE.mood[2], 0, 1 / L, 1 / L)
    end
    if (s.anim.burst or 0) > 0 then
      local burst = art("training/burst")
      if burst then
        local k = (0.6 + (0.7 - s.anim.burst) * 0.8) * PANE.hit[3] / 64
        G.setColor(1, 1, 1, math.min(1, s.anim.burst * 3))
        G.draw(burst, PANE.hit[1], PANE.hit[2], 0, k, k, 32, 32)
      end
    end
  end

  local function drawFrame(G)
    local top, tray = art("training/home_bg03"), art("training/home_bg02")
    G.setColor(1, 1, 1, 1)
    if top then
      pane(G, "frameL", top, PANE.frameL)
      pane(G, "frameR", top, PANE.frameR)
    end
    if tray then
      pane(G, "trayL", tray, PANE.trayL)
      pane(G, "trayR", tray, PANE.trayR)
    end
    return top ~= nil
  end

  local function drawMeter(G, s, small)
    local meter = art("training/home_meter")
    local h = PANE.hex
    local total = Rules.evTotal(s.evs)
    if not meter then
      Radar.draw(G, h[1], h[2], h.r * 0.8, { base = s.base, evs = s.evs, baseMax = 255, evMax = N.LIMITS.EV_CAP, font = small })
      return
    end
    fit(G, meter, PANE.meter, false, nil, PANE.meter.alpha)
    -- base stats inside, EVs as the yellow-green rim (the game draws this into meter_canvas)
    -- the game's steps: an axis is the base stat's pixels, then the EVs' on top (20 + 32 max,
    -- the hexagon's 50.5); the texture's pixels are layout units here
    local ri, ro = Rules.meterAxes(s.base, s.evs, Radar.ORDER)
    local inner, outer = {}, {}
    for i = 1, 6 do
      local a = -math.pi / 2 + (i - 1) * math.pi / 3
      inner[#inner + 1] = h[1] + math.cos(a) * ri[i]
      inner[#inner + 1] = h[2] + math.sin(a) * ri[i]
      outer[#outer + 1] = h[1] + math.cos(a) * ro[i]
      outer[#outer + 1] = h[2] + math.sin(a) * ro[i]
    end
    G.setColor(0.8, 1, 0.25, 1)
    G.polygon("fill", outer)
    G.setColor(0.05, 0.62, 0.45, 1)
    G.polygon("fill", inner)
    G.setLineWidth(2)
    G.setColor(0.85, 1, 0.3, 1)
    G.polygon("line", outer)
    G.setLineWidth(1)
    for k, at in pairs(PANE.label) do
      local img = art("training/label_" .. k)
      if img then fit(G, img, { at[1], at[2], 64, 20 }) end
    end
    -- the total: a green quad rising from the gauge's foot
    local g = PANE.gauge
    local frac = math.max(0, math.min(1, total / N.LIMITS.EV_TOTAL))
    if frac > 0 then
      local hh = g[4] * frac
      G.setColor(1, 1, 1, 1)
      pane(G, "gauge" .. math.floor(hh * 4), nil, { g[1], g[2] - hh / 2, g[3], hh }, g)
    end
  end

  local function drawBanner(G, s, font)
    local plateId = s.rec.supremely and "training/home_s_perfect_win"
      or (s.rec.fully and "training/home_perfect_win02") or "training/home_perfect_win00"
    local plate = art(plateId)
    G.setColor(1, 1, 1, 1)
    if plate then pane(G, "perfect" .. plateId, plate, PANE.perfect) end
    local win = art("training/home_shot_win")
    if win then pane(G, "shotWin", win, PANE.shotWin) end
    local ball = art("training/shot_" .. (s.shot or "black"))
    if ball then
      fit(G, ball, PANE.shot)
    else
      local rgb = T.SHOT_RGB[s.shot] or T.SHOT_RGB.black
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.circle("fill", PANE.shot[1], PANE.shot[2], 10, 16)
    end
    -- the name, white on the teal band, in the layout's 120x20 box
    local n = PANE.name
    G.setFont(font)
    G.setColor(1, 1, 1, 1)
    local k = math.min(1.1, n[3] * L / math.max(1, font:getWidth(s.name))) / L
    local tw, th = font:getWidth(s.name) * k, font:getHeight() * k
    G.print(s.name, math.floor(n[1] - tw / 2), math.floor(n[2] - th / 2), 0, k, k)
  end

  local function drawParty(G)
    for i, p in ipairs(T.party()) do
      if not p.active then
        local r = slotOf(i)
        if r then
          local cx, cy = (r.x + r.w / 2) / L, (r.y + BLEED + r.h / 2) / L
          local icon = p.icon
          if icon and icon.image then
            G.setColor(1, 1, 1, (p.eligible and 200 or 90) / 255)
            local q = icon.quads and (icon.quads[0] or icon.quads[1])
            local fw, fh = icon.w or 32, icon.h or 32
            local k = 40 / fw   -- the game's 40x30 icon slot
            if q then
              drawPixel(icon.image, q, cx, cy, 0, k, k, fw / 2, fh / 2)
            else
              drawPixel(icon.image, cx, cy, 0, k, k, fw / 2, fh / 2)
            end
          else
            G.setColor(1, 1, 1, p.eligible and 0.8 or 0.3)
            G.circle("fill", cx, cy, 8, 12)
          end
        end
      end
    end
  end

  local function drawButtons(G, small)
    for _, b in ipairs({ { PANE.regimens, "training/btn_regimens", "REGIMENS" }, { PANE.bags, "training/btn_bags", "BAGS" } }) do
      local img = art(b[2])
      if img then
        fit(G, img, b[1])
      else
        local p = b[1]
        G.setColor(0.25, 0.3, 0.42, 1)
        G.rectangle("fill", p[1] - p[3] / 2, p[2] - p[4] / 2, p[3], p[4] * 0.6, 6, 6)
        G.setFont(small)
        G.setColor(1, 1, 1, 0.9)
        G.printf(b[3], p[1] - p[3] / 2, p[2] - p[4] / 2 + 8, p[3] * L, "center", 0, 1 / L, 1 / L)
      end
    end
  end

  -- the PlayNav strip over the top of the bottom screen, its stepped edge at both ends, and
  -- the same strip upside down along the bottom where PlayNav's icon row sits
  local function drawStrip(G, w)
    local strip = art("training/home_strip")
    if not strip then return end
    G.setColor(1, 1, 1, 1)
    local sw, sh = strip:getDimensions()
    local hgt = 21 / L
    G.draw(strip, 0, 0, 0, (w / 2) / sw, hgt / sh)
    G.draw(strip, w, 0, 0, -(w / 2) / sw, hgt / sh)
    G.draw(strip, 0, 240, 0, (w / 2) / sw, -20 / sh)
    G.draw(strip, w, 240, 0, -(w / 2) / sw, -20 / sh)
    local arrow = art("training/home_arrow")
    if arrow then
      fit(G, arrow, { 14, 11, 18, 18 })
      fit(G, arrow, { 320 - 14, 11, 18, 18 }, true)
    end
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    G.push()
    G.translate(0, -(app.bleed or BLEED))
    G.scale(L, L)
    if not s then
      G.setColor(0.09, 0.11, 0.16, 1)
      G.rectangle("fill", 0, 0, 320, 240)
      G.setFont(font)
      G.setColor(1, 1, 1, 0.8)
      G.printf("No session", 0, 110, 320 * L, "center", 0, 1 / L, 1 / L)
      G.pop()
      return
    end
    drawRoom(G)
    drawBag(G, s, small)
    drawMon(G, s, small, font)
    drawFrame(G)
    drawMeter(G, s, small)
    drawBanner(G, s, font)
    drawButtons(G, small)
    drawParty(G)
    drawStrip(G, 320)
    if s.rec.pending then
      G.setFont(small)
      G.setColor(1, 0.95, 0.55, 1)
      G.printf("NEXT REGIMEN: " .. (Rules.EFFECT_LABEL[s.rec.pending] or s.rec.pending), 0, 152, 320 * L, "center", 0, 1 / L, 1 / L)
    end
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  return app
end
