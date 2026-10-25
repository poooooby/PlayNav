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
  -- src/training/lyt.lua: the shutters of a screen change
  do
    local src = mod.read and mod:read("src/training/lyt.lua")
    local chunk = src and load(src, "@" .. tostring(mod.path) .. "/src/training/lyt.lua")
    local ok, make = pcall(chunk or error)
    if ok and type(make) == "function" then app.lyt = make() end
  end
  local N = Rules.N

  -- the overworld stays live above this screen (the engine's pad stays for walking); a
  -- battle takes the bottom screen back
  app.fieldPlay = true
  function app:wantsSurface()
    return T.session ~= nil and T.session.mode == "core" and not (T.inBattle and T.inBattle())
  end

  local L = 256 / 320
  -- vertex colours run top-left, top-right, bottom-left, bottom-right, as in the layout
  local WHITE4 = { { 255, 255, 255, 255 }, { 255, 255, 255, 255 }, { 255, 255, 255, 255 }, { 255, 255, 255, 255 } }
  local FADE_L = { { 124, 167, 196, 255 }, { 255, 255, 255, 255 }, { 124, 167, 196, 255 }, { 255, 255, 255, 255 } }
  local FADE_R = { { 255, 255, 255, 255 }, { 124, 167, 196, 255 }, { 255, 255, 255, 255 }, { 124, 167, 196, 255 } }
  local MON_ALPHA = 200
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

  -- The screen's shape (Layout.setShape): the layout space is 320 wide and LH tall, 240 on
  -- the 3DS shape, 287.5 on Kanto Gear's. Three bands: the name frame stays at the top; the
  -- tray, buttons, party row, return button and bottom strip move down by D = LH - 240;
  -- the room between grows, and its content keeps the game's size (everything 1.0x,
  -- spread). The bag and the Pokemon (and their effects, the
  -- found bag, the hit marks) stay exactly where the game has them, so the bag's hook stays
  -- hidden under the name frame (BAG_SHIFT 0: moved down, it would show); the meter and
  -- its labels sit D/2 lower, centred in the taller room. K stays in the transform (1).
  -- On the 3DS shape D = 0: exactly the game's layout.
  local LH = 240
  local SHAPE = { D = 0, K = 1, px = 172.5, tx = 172.5, py = 112.5, ty = 112.5, bagTy = 112.5 }
  local BAG_SHIFT = 0   -- of D: how far the bag and the Pokemon move down
  local function setShape(lh)
    if lh == LH then return end
    LH = lh
    local D = math.max(0, lh - 240)
    SHAPE.D, SHAPE.K = D, 1
    SHAPE.tx = SHAPE.px
    SHAPE.ty = SHAPE.py + D / 2
    SHAPE.bagTy = SHAPE.py + D * BAG_SHIFT
    app.geo = nil
  end
  app.setShape = setShape
  -- a room point in layout units, where it now draws (bag = the bag and Pokemon group)
  local function roomPt(x, y, bag)
    return (x - SHAPE.px) * SHAPE.K + SHAPE.tx, (y - SHAPE.py) * SHAPE.K + (bag and SHAPE.bagTy or SHAPE.ty)
  end
  -- the room's transform for drawing (inside the L scale): the meter's, or the bag group's
  local function pushRoom(G, bag)
    G.push()
    G.translate(SHAPE.tx, bag and SHAPE.bagTy or SHAPE.ty)
    G.scale(SHAPE.K, SHAPE.K)
    G.translate(-SHAPE.px, -SHAPE.py)
  end
  local function roomRect(cx, cy, w, h, bag)
    local x, y = roomPt(cx, cy, bag)
    return rect(x, y, w * SHAPE.K, h * SHAPE.K)
  end
  local function lowRect(cx, cy, w, h) return rect(cx, cy + SHAPE.D, w, h) end

  -- the hit areas for the current shape (rebuilt when it changes)
  local PIC, BAG, REGIMENS, BAGS, TOTAL, ROOM, RADAR, CLOSE, ROCKET
  local function geo()
    if app.geo then return app.geo end
    PIC = roomRect(110, 128, 80, 80, true)
    BAG = roomRect(50, 106, 40, 100, true)
    REGIMENS = lowRect(32, 186, 64, 64)
    BAGS = lowRect(292, 193, 48, 48)
    TOTAL = roomRect(308, 102, 10, 130)
    -- the room between the name frame and the tray (y 60 .. 165 + D)
    ROOM = rect(160, 112.5 + SHAPE.D / 2, 320, 105 + SHAPE.D)
    local hx, hy = roomPt(PANE.hex[1], PANE.hex[2])
    RADAR = { cx = hx * L, cy = hy * L - BLEED, r = PANE.hex.r * SHAPE.K * L }
    -- PlayNav's return button (message layout pane ab, 27x27 at 305,224)
    CLOSE = { x = (305 - 18) * L, y = (224 + SHAPE.D - 18) * L - BLEED, w = 36 * L, h = 36 * L }
    app.CLOSE = CLOSE
    -- the Konami code's R button, the return button's mirror (src/training/rocket.lua)
    ROCKET = { x = (15 - 18) * L, y = CLOSE.y, w = 36 * L, h = 36 * L }
    app.geo = true
    return app.geo
  end
  geo()

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
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
  -- PlayNav's return button (message layout pane ab, 27x27 at 305,224) leaves Super Training
  local RETURN_PANE = { 305, 224, 27, 27 }
  local ROCKET_PANE = { 15, 224, 27, 27 }

  -- the Konami code's unlock over the home screen (layout units): black, the R, its glint
  local function drawUnlock(G, t, Rk)
    local black, scale, alpha, glint = Rk.unlockView(t)
    if black > 0 then
      G.setColor(0, 0, 0, black)
      G.rectangle("fill", -10, -20, 340, LH + 40)
    end
    local logo = alpha > 0 and art("rocket/logo")
    if not logo then return end
    local lw, lh = logo:getDimensions()
    local k = 150 / lh * scale
    local cx, cy = 160, LH / 2
    G.setColor(1, 1, 1, alpha)
    G.draw(logo, cx, cy, 0, k, k, lw / 2, lh / 2)
    local gl = glint and art("rocket/glint")
    if gl then
      local gw, gh = gl:getDimensions()
      G.setBlendMode("add")
      G.setColor(1, 1, 1, math.sin(glint * math.pi))
      G.draw(gl, cx - 45 + 90 * glint, cy - 50 + 30 * glint, glint * 2.5, 1.6, 1.6, gw / 2, gh / 2)
      G.setBlendMode("alpha")
    end
  end

  -- the party list once a frame: T.party asks the engine for every member's key, name and
  -- icon, and the screen wanted it eight times a frame (each slot, the active icon, the row)
  local partyAt, partyList = nil, nil
  local function party()
    if partyList and partyAt == app.clock then return partyList end
    partyList, partyAt = T.party and T.party() or {}, app.clock
    return partyList
  end
  app.partyNow = party

  -- the party: the active Pokemon stands in the room; the others take the layout's icon
  -- slots in party order. partySlot(i) is where party member i can be tapped.
  local function slotOf(i)
    local party = party()
    local n = 0
    for j, p in ipairs(party) do
      if j == i then
        geo()
        if p.active then return PIC end
        local at = PANE.icons[n + 1]
        if not at then return nil end
        return lowRect(at[1], at[2], PANE.iconSize[1], PANE.iconSize[2])
      end
      if not p.active then n = n + 1 end
    end
    return nil
  end

  function app.geometry()
    geo()
    return { PIC = PIC, BAG = BAG, RADAR = RADAR, TOTAL = TOTAL, REGIMENS = REGIMENS, BAGS = BAGS, ROOM = ROOM, CLOSE = CLOSE,
      ROCKET = ROCKET, partySlot = slotOf }
  end

  -- the round buttons give under the finger and bounce back on release (measured from a
  -- capture: about 0.93 held, then 1.07, 1, 0.96, 0.98, 1 a frame apart)
  local PRESS = 0.93
  local BOUNCE = { { 0, 1.07, 0 }, { 1, 1, -0.05 }, { 2, 0.96, 0 }, { 3, 0.98, 0.01 }, { 4, 1, 0 } }
  app.press = {}

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "core") or s.trans then return end
    -- the R's unlock holds the screen
    if T.rocketBusy and T.rocketBusy() then return end
    geo()
    local H = mod.haptics
    if ev.phase == "pressed" then
      for key, r in pairs({ regimens = REGIMENS, bags = BAGS }) do
        if inRect(ev.x, ev.y, r) then
          app.press[key] = { held = true }
          if H then H.pulse("tick") end
        end
      end
      return
    end
    if ev.phase ~= "released" then return end
    for _, pr in pairs(app.press) do
      if pr.held then pr.held, pr.at = false, app.clock end
    end
    -- any touch keeps the Pokemon from dozing off
    if T.touch then T.touch() end
    if not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    if inRect(x, y, CLOSE) then
      if H then H.pulse("tick") end
      T.finish()
      return
    end
    -- (tested before REGIMENS: that button's rect reaches over its top)
    if T.rocketUnlocked and T.rocketUnlocked() and inRect(x, y, ROCKET) then
      if H then H.pulse("tick") end
      T.goTo("rocket")
      return
    end
    -- the finishing move plays out before anything else is taken
    if T.finishing and T.finishing() then return end
    if inRect(x, y, BAG) then T.hitBag("tap"); return end
    if inRect(x, y, PIC) then
      if s.rec.resting then T.wake() else T.hitBag("tap") end
      return
    end
    if inRect(x, y, REGIMENS) then
      -- the bounce, then the shutters close and the picker comes up (T.goTo's timing and sound)
      if T.goTo then T.goTo("courses")
      else
        if T.playSe then T.playSe("transition") end
        if T.enterCourses then T.enterCourses() end
      end
      return
    end
    if inRect(x, y, BAGS) then
      if T.playSe then T.playSe("bags_open") end
      T.enterBags()
      return
    end
    for i, p in ipairs(party()) do
      local r = slotOf(i)
      if r and not p.active and inRect(x, y, r) then
        if H then H.pulse("tick") end
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
    -- sand_bag_get, pic 4e (x 90): the found bag drops from behind the top frame to hang at
    -- ty 20, bounces, and rises away at 67..80 (121-frame clip)
    giftBag = {
      ty = { { 0, 120, -5.9 }, { 17, 20, 0 }, { 17, 20, 2.5 }, { 19, 25, 0 }, { 21, 20, 0 },
        { 67, 20, 0 }, { 67, 20, 7.7 }, { 80, 120, 7.7 } },
    },
    -- sand_bag_get, pane 43: two lunges at the bag, then a spinning leap past the drop and back
    giftMon = {
      frames = 55,
      tx = { { 0, -50, -19 }, { 2, -88, 0 }, { 4, -50, 19 }, { 6, -88, 0 }, { 8, -50, 0 }, { 15, -50, 0 },
        { 15, -88, 0 }, { 40, 12, 4 }, { 44, 12, 0 }, { 44, 12, 0 }, { 55, -50, 0 } },
      ty = { { 0, -18, 4 }, { 2, -10, 0 }, { 4, -18, -4 }, { 6, -10, 0 }, { 8, -18, 0 }, { 15, -18, 0 },
        { 28, 60, 0 }, { 40, -18, 0 }, { 44, -18, 0 }, { 50, 11, 0 }, { 55, -18, 0 } },
      rz = { { 0, 0, 0 }, { 15, 0, 0 }, { 15, 0, -28.8 }, { 40, -720, 0 }, { 55, -720, 0 } },
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

  -- a cleared bag's finishing move: trpk_finish_a / b / c (pane groups 6e / 6i / 6j), 70
  -- frames each. `mon` is the Pokemon's pane (43 / 4m / 4n), `bag` the pane the bag hangs from
  -- (4u / 4v / 4w: its hook, the bag 100 below; it holds (-110, 64) until it flies off),
  -- `shake` the background (q), `fx` the marks and slashes: `at` the parent pane's centre,
  -- `tx` / `ty` offsets from it, `size` the pic, `va` its vertex alpha, `show` its frames.
  local Q_TX = { { 10, 0, -2.5 }, { 12, -5, 1.5 }, { 14, 6, 0.75 }, { 16, -2, -1.25 }, { 18, 1, 0.5 }, { 20, 0, 0 }, { 40, 0, 0 },
    { 40, 2, -0.045 }, { 42, -1, 0 }, { 44, 2, 0.25 }, { 46, 0, -0.5 }, { 48, 0, 0 } }
  local Q_TY = { { 0, 0, 1 }, { 2, 2, -0.25 }, { 4, -1, -0.25 }, { 6, 1, 0.25 }, { 8, 0, -0.25 }, { 10, 0, 0.75 }, { 12, 3, -0.75 },
    { 14, -3, -0.5 }, { 16, 1, 0.25 }, { 18, -2, -0.25 }, { 20, 0, 0 }, { 40, 0, 0 }, { 40, 2, -0.045 }, { 42, -1, 0 },
    { 44, 2, 0.25 }, { 46, 0, -0.5 }, { 48, 0, 0 } }
  local FINISH = {
    -- two jabs, a somersault leap through the slash; the bag spins about its hook and flies off
    a = {
      shake = { tx = Q_TX, ty = Q_TY },
      mon = {
        tx = { { 0, -50, -19 }, { 2, -88, 0 }, { 4, -50, 0 }, { 6, -88, 0 }, { 8, -50, 0 }, { 15, -50, 0 }, { 15, -88, 0 }, { 40, 12, 0 },
          { 44, 12, 0 }, { 44, 12, -4.133 }, { 55, -50, 0 } },
        ty = { { 0, -18, 4 }, { 2, -10, 0 }, { 4, -18, 0 }, { 6, -10, 0 }, { 8, -18, 0 }, { 15, -18, 0 }, { 15, -18, 6 }, { 28, 60, 0 },
          { 40, -18, 0 }, { 44, -18, 0 }, { 44, -18, 2.9 }, { 50, 11, 0 }, { 55, -18, 0 } },
        rz = { { 0, 0, 0 }, { 15, 0, 0 }, { 15, 0, -18 }, { 40, -720, 0 } },
      },
      bag = {
        tx = { { 55, -110, -4.133 }, { 70, -172, -4.133 } },
        ty = { { 55, 64, 1.267 }, { 70, 83, 1.267 } },
        rz = { { 0, 0, 0 }, { 3, 0, 0 }, { 3, -15, -0.531 }, { 6, -3.188, -1.25 }, { 7, -20, 0.678 }, { 11, 0.202, 2.5 }, { 15, 0, -0.051 },
          { 15, 0, -35.714 }, { 57, -1500, -35.714 } },
      },
      fx = {
        { img = "training/burst", at = { 50, 120 }, size = 64, va = 200, show = { 1, 64 },
          tx = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, -4.667, 0 }, { 6, -4.667, 0 }, { 6, 12, 0 }, { 12, 12, 0 }, { 12, 3.333, 0 } },
          ty = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, -1.556, 0 }, { 6, -1.556, 0 }, { 6, -20.667, 0 }, { 12, -20.667, 0 }, { 12, -0.667, 0 } },
          s = { { 0, 1, 0 }, { 2, 1, 0 }, { 2, 1, 0.1 }, { 5, 1.5, 0 }, { 6, 1.5, 0 }, { 6, 1, 0 }, { 9, 1.5, 0 }, { 16, 1.5, 0 },
            { 16, 1.5, 0.1 }, { 24, 3, 0.188 } },
          a = { { 0, 0, 0 }, { 2, 0, 0 }, { 2, 255, 20 }, { 5, 100, 0 }, { 6, 100, 0 }, { 6, 255, -25 }, { 9, 0, 0 }, { 16, 0, 0 },
            { 16, 255, 0 }, { 27, 0, -23.182 } } },
        { img = "training/finish_slash", at = { 85, 116 }, size = 100, show = { 1, 64 },
          s = { { 0, 1, 0 }, { 16, 1, 0.032 }, { 31, 2, 0.067 } },
          rz = { { 0, 0, 0 }, { 16, 0, 0 }, { 16, 90, -16.129 }, { 31, -500, -39.333 } },
          a = { { 0, 0, 0 }, { 16, 0, 0 }, { 16, 255, 0 }, { 31, 0, -17 } } },
      },
    },
    -- a flurry: the Pokemon bounces off the bag again and again, a mark flickering on each hit
    b = {
      shake = { tx = Q_TX, ty = Q_TY },
      mon = {
        tx = { { 0, -50, 5 }, { 3, -35, 5 }, { 3, -35, 0.571 }, { 10, -31, 0.571 }, { 10, -31, -42 }, { 13, -157, -42 }, { 13, -157, 38.167 },
          { 16, -42.5, 38.167 }, { 16, -42.5, -37.333 }, { 19, -154.5, -37.333 }, { 19, -154.5, 27 }, { 22, -73.5, 27 }, { 22, -73.5, -32 },
          { 25, -169.5, -32 }, { 25, -169.5, 26.567 }, { 28, -89.8, 26.567 }, { 28, -89.8, -23.622 }, { 31, -160.667, -23.622 },
          { 31, -160.667, 30.963 }, { 34, -67.778, 30.963 }, { 34, -67.778, -25.833 }, { 38, -171.111, 0.532 }, { 41, -64.051, 35.687 },
          { 41, -64.051, -15.659 }, { 44, -111.027, -15.659 }, { 44, -111.027, 4.559 }, { 53, -69.996, 3.814 }, { 60, -50, 2.857 } },
        ty = { { 3, -18, 0 }, { 10, -18, 0 }, { 10, -18, 17.167 }, { 13, 33.5, 17.167 }, { 13, 33.5, 4 }, { 16, 45.5, 4 }, { 16, 45.5, -13.333 },
          { 19, 5.5, -13.333 }, { 19, 5.5, -2.333 }, { 22, -1.5, -2.333 }, { 22, -1.5, 3.833 }, { 25, 10, 3.833 }, { 25, 10, -11.267 },
          { 28, -23.8, -11.267 }, { 28, -23.8, 14.822 }, { 31, 20.667, 14.822 }, { 31, 20.667, 5.704 }, { 34, 37.778, 5.704 },
          { 34, 37.778, -10.407 }, { 38, -3.852, -10.407 }, { 38, -3.852, 14.903 }, { 41, 40.858, 14.903 }, { 41, 40.858, -13.357 },
          { 44, 0.786, -13.357 }, { 44, 0.786, 4.31 }, { 53, 39.572, -1.174 }, { 60, -18, -8.225 } },
        rz = { { 0, 0, 2.222 }, { 9, 20, 0 }, { 10, 0, 17.895 }, { 28, 360, 0 }, { 44, 0, -11.25 }, { 60, 0, 0 } },
      },
      bag = {
        tx = { { 58, -110, -5.182 }, { 69, -167, -5.182 } },
        ty = { { 58, 64, 1.636 }, { 69, 82, 1.636 } },
        rz = { { 0, 0, 0 }, { 12, 0, 0 }, { 12, -15, 1.333 }, { 15, 20, -2.5 }, { 18, -30, 3.333 }, { 21, 40, -3.333 }, { 24, -50, -1.667 },
          { 27, 30, 1.667 }, { 30, -40, 3.333 }, { 33, 50, 0 }, { 36, -40, -38.387 }, { 64, -1140, -39.286 } },
      },
      fx = {
        { img = "training/burst", at = { 160, 120 }, size = 76, show = { 1, 60 },
          tx = { { 12, -110, 0 }, { 15, -110, 0 }, { 15, -118, 0 }, { 18, -118, 0 }, { 18, -96, 0 }, { 21, -96, 0 }, { 21, -118, 0 },
            { 24, -118, 0 }, { 24, -98, 0 }, { 27, -98, 0 }, { 27, -116, 0 }, { 30, -116, 0 }, { 30, -104, 0 }, { 33, -104, 0 },
            { 33, -122, 0 }, { 36, -122, 0 }, { 36, -102, 0 }, { 39, -102, 0 }, { 39, -122, 0 }, { 45, -122, 0 }, { 45, -110, 0 } },
          ty = { { 12, 0, 0 }, { 15, 0, 0 }, { 15, 26, 0 }, { 18, 26, 0 }, { 18, 6, 0 }, { 21, 6, 0 }, { 21, -14, 0 }, { 24, -14, 0 },
            { 24, 9, 0 }, { 27, 9, 0 }, { 27, -23, 0 }, { 30, -23, 0 }, { 30, -20, 0 }, { 33, -20, 0 }, { 33, 10, 0 }, { 36, 10, 0 },
            { 36, 12, 0 }, { 39, 12, 0 }, { 39, 6, 0 }, { 45, 6, 0 }, { 45, 1, 0 }, { 60, 1, 0 }, { 60, 0, 0 } },
          s = { { 0, 1, 0 }, { 12, 1, 0 }, { 12, 1, 0.071 }, { 14, 2, 0 }, { 15, 1, 0 }, { 17, 2, 0 }, { 18, 1, 0 }, { 20, 2, 0 }, { 21, 1, 0 },
            { 23, 2, 0 }, { 24, 1, 0 }, { 26, 2, 0 }, { 27, 1, 0 }, { 29, 2, 0 }, { 30, 1, 0 }, { 32, 2, 0 }, { 33, 1, 0 }, { 35, 2, 0 },
            { 36, 1, 0 }, { 38, 2, 0 }, { 39, 1, -1 }, { 39, 1, 0.5 }, { 41, 2, 0.5 }, { 41, 2, -0.25 }, { 45, 1, 0 }, { 50, 2, 0.2 } },
          a = { { 0, 0, 0 }, { 12, 0, 0 }, { 12, 255, -77.5 }, { 14, 100, -77.5 }, { 14, 100, 155 }, { 15, 255, 155 }, { 15, 255, -77.5 },
            { 17, 100, -77.5 }, { 17, 100, 155 }, { 18, 255, 155 }, { 18, 255, -77.5 }, { 20, 100, -77.5 }, { 20, 100, 155 },
            { 21, 255, 155 }, { 21, 255, -77.5 }, { 23, 100, -77.5 }, { 23, 100, 155 }, { 24, 255, 155 }, { 24, 255, -77.5 },
            { 26, 100, -77.5 }, { 26, 100, 155 }, { 27, 255, 155 }, { 27, 255, -77.5 }, { 29, 100, -77.5 }, { 29, 100, 155 },
            { 30, 255, 155 }, { 30, 255, -77.5 }, { 32, 100, -77.5 }, { 32, 100, 155 }, { 33, 255, 155 }, { 33, 255, -77.5 },
            { 35, 100, -77.5 }, { 35, 100, 155 }, { 36, 255, 155 }, { 36, 255, -77.5 }, { 38, 100, -77.5 }, { 38, 100, 155 },
            { 39, 255, 155 }, { 39, 255, -77.5 }, { 41, 100, 0 }, { 42, 100, 0 }, { 42, 0, 0 }, { 45, 0, 0 }, { 45, 255, -51 },
            { 50, 0, -51 } } },
      },
    },
    -- a spinning dash out past the bag, a slash where it turns, then the blow coming back
    c = {
      mon = {
        tx = { { 0, -50, 11.929 }, { 4, -2.286, 11.429 }, { 7, 30, 10.762 }, { 7, 30, -0.184 }, { 34, 25.021, -0.184 }, { 34, 25.021, -43.34 },
          { 37, -105, -43.34 }, { 37, -105, -2.5 }, { 39, -110, -0.25 }, { 41, -106, 2.333 }, { 42, -103, -0.5 }, { 43, -107, -2.5 },
          { 44, -108, -0.143 }, { 50, -108, 0 }, { 50, -108, 5.143 }, { 57, -72, 4.143 }, { 64, -50, 3.143 } },
        ty = { { 0, -18, 7.815 }, { 4, 13.262, 2.19 }, { 7, -2.667, -5.31 }, { 7, -2.667, -0.035 }, { 34, -3.621, -0.035 },
          { 34, -3.621, 0.874 }, { 37, -1, 0.874 }, { 37, -1, -2.5 }, { 39, -6, -0.25 }, { 41, -2, 0.667 }, { 42, -4, -0.5 }, { 43, -3, 0 },
          { 44, -4, -0.143 }, { 50, -4, 0 }, { 50, -4, 5 }, { 57, 31, -1 }, { 64, -18, -7 } },
        rz = { { 0, 0, -25.714 }, { 7, -180, -25.714 }, { 7, -180, -45.185 }, { 34, -1400, 0 }, { 35, -1400, 0 }, { 35, 90, 0 },
          { 50, 90, 0 }, { 50, 90, -6.429 }, { 64, 0, -6.429 } },
      },
      bag = {
        tx = { { 55, -110, -3.9 }, { 70, -168.5, -3.9 } },
        ty = { { 55, 64, 1.133 }, { 70, 81, 1.133 } },
        rz = { { 0, 0, 0 }, { 38, 0, 0 }, { 38, 0, -17.812 }, { 64, -1140, -43.846 } },
      },
      fx = {
        { img = "training/burst", at = { 50, 120 }, size = 76, show = { 38, 64 },
          s = { { 0, 1, 0 }, { 37, 1, 0 }, { 37, 1.5, 0.023 }, { 44, 2, 0.071 } },
          a = { { 0, 0, 0 }, { 38, 0, 0 }, { 38, 255, 0 }, { 44, 0, -42.5 } } },
        { img = "training/finish_slash", at = { 185, 120 }, size = 64, show = { 1, 64 },
          s = { { 7, 1, 0.036 }, { 35, 2, 0.036 } },
          rz = { { 7, 0, -50 }, { 35, -1400, -50 } },
          a = { { 0, 0, 0 }, { 7, 0, 0 }, { 7, 255, 0 }, { 35, 0, -9.107 } } },
      },
    },
  }
  -- the glow about the Pokemon (effect, pane 49 at 109,144): two efect_light quarters mirrored
  -- into a sun each, orange 45 and yellow 47, turning opposite ways (100 frames)
  -- the glow follows the sprite: `perSprite` times the sprite's larger visible side (a
  -- capture shows about 95 across for a sprite about 50 across); `size` when that is unknown
  local GLOW = {
    at = { 109, 144 }, size = 96, perSprite = 1.9,
    { rgb = { 255, 151, 6 }, s = { { 0, 0.5, 0.017 }, { 30, 1, 0 }, { 70, 1, 0 }, { 70, 1, -0.007 }, { 100, 0.5, -0.017 } },
      rz = { { 0, 0, 3.6 }, { 100, 360, 3.6 } }, a = { { 0, 0, 8.5 }, { 30, 255, 3.643 }, { 70, 255, -3.643 }, { 100, 0, -8.5 } } },
    { rgb = { 255, 252, 89 }, s = { { 0, 0.5, 0.013 }, { 30, 0.9, 0 }, { 70, 0.9, 0 }, { 70, 0.9, -0.006 }, { 100, 0.5, -0.013 } },
      rz = { { 0, 0, -3.6 }, { 100, -360, -3.6 } }, a = { { 0, 0, 6 }, { 30, 180, 2.571 }, { 70, 180, -2.571 }, { 100, 0, -6 } } },
  }
  -- sand_bag_return (pane 56): the next bag drops onto its hook with a bounce (22 frames)
  local BAG_RETURN = { { 0, 160, -5.333 }, { 18, 64, -5.333 }, { 18, 64, 2 }, { 20, 68, 2 }, { 20, 68, -2 }, { 22, 64, -2 } }
  -- the stat's label and its +N (hp_up / kougeki_up / bougyo_up / tokukou_up / tokubou_up /
  -- subayasa_up) and the gauge's arrow (arrow_scale) pulse 1 -> 1.2 every 7 frames
  local function pulse(f)
    f = f % 120
    return (f >= 1 and math.floor((f - 1) / 7) % 2 == 0) and 1.2 or 1
  end
  app.FINISH = FINISH

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
  -- the active sprite's larger visible side in layout units (as drawn: the icon at 2x its
  -- 40x30 slot), read once per icon from a small canvas
  local function measureSprite(icon)
    local G = love and love.graphics
    if not (G and G.newCanvas and icon and icon.image) then return nil end
    local fw, fh = icon.w or 32, icon.h or 32
    local ok, data = pcall(function()
      -- one canvas pixel per sprite unit (the screen's density would scale the scan)
      local c = G.newCanvas(fw, fh, { dpiscale = 1 })
      local prev = G.getCanvas()
      G.push("all")
      G.setCanvas(c)
      G.clear(0, 0, 0, 0)
      G.origin()
      G.setColor(1, 1, 1, 1)
      local q = icon.quads and (icon.quads[0] or icon.quads[1])
      if q then G.draw(icon.image, q, 0, 0) else G.draw(icon.image, 0, 0) end
      G.pop()
      G.setCanvas(prev)
      return c:newImageData()
    end)
    if not ok or not data then return nil end
    local x0, y0, x1, y1 = fw, fh, -1, -1
    for y = 0, fh - 1 do
      for x = 0, fw - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a > 0.1 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    if x1 < 0 then return nil end
    local k = 2 * 40 / fw
    return math.max(x1 - x0 + 1, y1 - y0 + 1) * k
  end

  function app:update(dt)
    app.clock = app.clock + (dt or 0) * FPS
    local s = T.session
    local hit = s and s.anim and s.anim.hit or 0
    if hit > lastHit + 1e-6 then app.hitAt = app.clock end
    lastHit = hit
    if s and s.anim and s.anim.finish then
      local icon
      for _, p in ipairs(party()) do
        if p.active then icon = p.icon end
      end
      local img = icon and icon.image
      if img and not (app.spriteExtent and app.spriteExtent.image == img) then
        app.spriteExtent = { image = img, size = measureSprite(icon) }
      end
    end
    -- the moment it gets up, the wake-up clip plays
    local resting = s ~= nil and s.rec.resting and true or false
    if lastResting and not resting then app.wakeAt = app.clock end
    lastResting = resting
  end
  local drawFinishFx
  -- the finishing move under way: the session's record and its frame
  local function finishing()
    local s = T.session
    local fin = s and s.anim and s.anim.finish
    if not fin then return nil end
    return fin, fin.t * 30
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
  local WHITE3 = { 255, 255, 255 }
  local function fit(G, img, p, flipX, tint, alpha)
    local iw, ih = img:getDimensions()
    local sx, sy = p[3] / iw, p[4] / ih
    local t = tint or WHITE3
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
    local shakeX = 0
    local fin, ff = finishing()
    if fin and ff < 70 and FINISH[fin.clip].shake then
      shake = eval(FINISH[fin.clip].shake.ty, ff) or 0
      shakeX = eval(FINISH[fin.clip].shake.tx, ff) or 0
    end
    G.setColor(1, 1, 1, 1)
    G.push()
    G.translate(shakeX, -shake)
    -- the backdrop's gradient runs the whole (taller) screen
    G.push()
    G.scale(1, LH / 240)
    pane(G, "bg", nil, PANE.bg)
    G.pop()
    if bg01 then
      G.push()
      G.translate(0, SHAPE.D)
      pane(G, "glowLow", bg01, PANE.glowLow)
      G.pop()
      pane(G, "glowHigh", bg01, PANE.glowHigh)
    end
    G.pop()
    if ptn then
      -- the + pattern: the same tile size, more rows on the taller room
      local p, c = PANE.ptn, PANE.ptn.colors[1]
      local ph = p[4] + SHAPE.D
      local rv = p.repeatV * ph / p[4]
      local tw, th = ptn:getDimensions()
      ptn:setWrap("repeat", "repeat")
      local t = app.clock % 200
      app.ptnQuad = app.ptnQuad or G.newQuad(0, 0, tw * p.repeatU, th * rv, tw, th)
      app.ptnQuad:setViewport(-PTN_SCROLL.u * t * tw, -PTN_SCROLL.v * t * th, tw * p.repeatU, th * rv, tw, th)
      G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
      G.draw(ptn, app.ptnQuad, p[1] - p[3] / 2, p[2] - p[4] / 2, 0, p[3] / (tw * p.repeatU), ph / (th * rv))
    end
  end

  local function bagArt(def)
    return def and art(Rules.bagArt(def.id)) or art("training/home_sand_bag")
  end
  -- the alley's R+ bags glow behind: the halo (twice the bag's size) drawn as the bag is, its
  -- origin moved by the half-size difference (ox, oy: the bag's origin in its own texels)
  local function bagGlow(G, def, img, x, y, r, sx, sy, ox, oy, a)
    local glow = def and def.glow and art("training/rbag_glow_" .. def.stat)
    if not glow then return end
    local iw, ih = img:getDimensions()
    local gw, gh = glow:getDimensions()
    G.setColor(1, 1, 1, a or 1)
    G.draw(glow, x, y, r, sx, sy, ox + (gw - iw) / 2, oy + (gh - ih) / 2)
  end

  local function drawBag(G, s, small)
    local fin, ff = finishing()
    if fin then
      -- the cleared bag spins on its hook and flies off; then the room is empty
      if ff >= 70 then return end
      local tr = FINISH[fin.clip].bag
      local fdef = Rules.bag(fin.bag)
      local img = bagArt(fdef)
      if not img then return end
      local iw, ih = img:getDimensions()
      local p = PANE.bag
      local fx, fy, fr = 160 + eval(tr.tx, ff), 120 - eval(tr.ty, ff), math.rad(-(eval(tr.rz, ff) or 0))
      bagGlow(G, fdef, img, fx, fy, fr, p[3] / iw, p[4] / ih, iw / 2, 0, (p.alpha or 255) / 255)
      G.setColor(1, 1, 1, (p.alpha or 255) / 255)
      G.draw(img, fx, fy, fr, p[3] / iw, p[4] / ih, iw / 2, 0)
      return
    end
    local bag = s.rec.bag
    local def = bag and Rules.bag(bag.id)
    local p = PANE.bag
    local f = sinceHit()
    local swing = f and math.rad(-(eval(TRACK.bag.rz, f) or 0)) or 0
    -- the next bag drops back onto its hook (its top at 120 - ty, 64 when hung)
    local drop = s.anim.bagReturn and (eval(BAG_RETURN, s.anim.bagReturn * 30) - 64) or 0
    if drop ~= 0 then
      G.push()
      G.translate(0, -drop)
    end
    -- an attached bag shows its own art; otherwise the game's grey punching bag
    local img = bagArt(def)
    if img then
      local iw, ih = img:getDimensions()
      bagGlow(G, def, img, p[1], p[2], swing, p[3] / iw, p[4] / ih, iw / 2, ih / 2, (p.alpha or 255) / 255)
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
    if drop ~= 0 then G.pop() end
  end

  -- the clip's marks and slashes, then the glow (frames 70..170)
  function drawFinishFx(G, fin, ff)
    if ff < 70 then
      for _, fx in ipairs(FINISH[fin.clip].fx) do
        local img = art(fx.img)
        if img and ff >= fx.show[1] and ff < fx.show[2] then
          local a = math.max(0, math.min(255, eval(fx.a, ff) or 0)) / 255 * (fx.va or 255) / 255
          if a > 0 then
            local iw, ih = img:getDimensions()
            local sc = (eval(fx.s, ff) or 1) * fx.size / iw
            local x = fx.at[1] + (fx.tx and eval(fx.tx, ff) or 0)
            local y = fx.at[2] - (fx.ty and eval(fx.ty, ff) or 0)
            G.setColor(1, 1, 1, a)
            G.draw(img, x, y, math.rad(-(fx.rz and eval(fx.rz, ff) or 0)), sc, sc, iw / 2, ih / 2)
          end
        end
      end
      return
    end
    local gf = ff - 70
    local light = art("training/finish_light")
    if not light or gf >= 100 then return end
    local iw, ih = light:getDimensions()
    local ext = app.spriteExtent and app.spriteExtent.size
    local size = ext and ext * GLOW.perSprite or GLOW.size
    for _, g in ipairs(GLOW) do
      local a = math.max(0, math.min(255, eval(g.a, gf) or 0)) / 255
      local sc = (eval(g.s, gf) or 1) * size / 2 / iw   -- a quarter each way from the centre
      G.setColor(g.rgb[1] / 255, g.rgb[2] / 255, g.rgb[3] / 255, a)
      G.push()
      G.translate(GLOW.at[1], GLOW.at[2])
      G.rotate(math.rad(-(eval(g.rz, gf) or 0)))
      -- the quarter's bright corner (its lower left) at the centre, mirrored four ways
      G.draw(light, 0, 0, 0, sc, sc, 0, ih)
      G.draw(light, 0, 0, 0, -sc, sc, 0, ih)
      G.draw(light, 0, 0, 0, sc, -sc, 0, ih)
      G.draw(light, 0, 0, 0, -sc, -sc, 0, ih)
      G.pop()
    end
  end

  local function activeIcon()
    for _, p in ipairs(party()) do
      if p.active then return p.icon end
    end
  end

  local function drawMon(G, s, small, font)
    local f = sinceHit()
    local tr, at
    local woke = app.wakeAt and (app.clock - app.wakeAt) or nil
    local fainted = T.fainted and T.fainted() or false
    local fin, ff = finishing()
    local gift = s.anim and s.anim.gift
    if fin then
      if ff < 70 then
        tr, at = FINISH[fin.clip].mon, ff
      else
        tr, at = TRACK.punch, 6   -- back at its spot (-50, -18), still under the glow
      end
    elseif gift and gift.t * 30 < TRACK.giftMon.frames then
      -- the found bag's presentation: the lunges and the spinning leap (sand_bag_get)
      tr, at = TRACK.giftMon, gift.t * 30
    elseif s.rec.resting or fainted then
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
    G.setColor(1, 1, 1, MON_ALPHA / 255)
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
    if fin then
      drawFinishFx(G, fin, ff)
      return
    end
    -- the smile hides while it strikes (a punch, the found bag's lunges) and shows again
    -- once it is back at its spot; the finish returned above
    local striking = f or (gift and gift.t * 30 < TRACK.giftMon.frames)
    local mood = (fainted and "sad") or (s.rec.resting and "silence")
      or (T.refreshed() and not striking and "smile")
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

  -- the found bag's presentation (sand_bag_get, pic 4e): the bag drops down at x 90 showing
  -- its own art, hangs, and rises back behind the top frame (drawn after this, covering it)
  local function drawGift(G, s)
    local gift = s.anim and s.anim.gift
    if not gift then return end
    local f = gift.t * 30
    if f >= 80 then return end
    local ty = eval(TRACK.giftBag.ty, f)
    local img = bagArt(Rules.bag(gift.id))
    if not img then return end
    local iw, ih = img:getDimensions()
    -- see-through like the hanging bag (pane 4e takes the bag's alpha, 200)
    G.setColor(1, 1, 1, (PANE.bag.alpha or 255) / 255)
    G.draw(img, 90, 120 - ty, 0, 40 / iw, 100 / ih, iw / 2, ih / 2)
  end

  local function drawFrame(G)
    local top, tray = art("training/home_bg03"), art("training/home_bg02")
    G.setColor(1, 1, 1, 1)
    if top then
      pane(G, "frameL", top, PANE.frameL)
      pane(G, "frameR", top, PANE.frameR)
    end
    if tray then
      G.push()
      G.translate(0, SHAPE.D)
      pane(G, "trayL", tray, PANE.trayL)
      pane(G, "trayR", tray, PANE.trayR)
      G.pop()
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
    local up = s.anim and s.anim.statUp
    local uf = up and up.t * 30
    for k, at in pairs(PANE.label) do
      local img = art("training/label_" .. k)
      local sc = (up and up.stat == k) and pulse(uf) or 1
      if img then fit(G, img, { at[1], at[2], 64 * sc, 20 * sc }) end
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

  -- after a stat bag: the +N over the stat's label and the arrow at the gauge's top. In the
  -- layout these panes come after the name frame (57, 3h..3r, 5k), so they draw over it.
  local function drawStatUp(G, s, small)
    local up = s.anim and s.anim.statUp
    if not up then return end
    local uf, sc = up.t * 30, pulse(up.t * 30)
    local at = PANE.label[up.stat]
    if at then
      -- the +N (point_up_win 3p 40x20, 17 above the label, alpha 180; text 3d)
      local cx, cy = at[1], at[2] - 17 * sc
      local win = art("training/point_up_win")
      if win then fit(G, win, { cx, cy, 40 * sc, 20 * sc }, false, nil, 180) end
      G.setFont(small)
      local txt = ("+%d"):format(up.added)
      local k = 13 * sc / math.max(1, small:getHeight())
      G.setColor(1, 0.62, 0.2, 1)
      G.print(txt, cx - small:getWidth(txt) * k / 2, cy - small:getHeight() * k / 2 - 1, 0, k, k)
    end
    -- the arrow (arrow_up_anime: pane 5k climbs 128 over the gauge; the arrow pic 5i sits 6
    -- right and 12 up of it, light green at alpha 200), pulsing (arrow_scale)
    local frac = math.max(0, math.min(1, Rules.evTotal(s.evs) / N.LIMITS.EV_TOTAL))
    local ax, ay = 314, 174 - 128 * frac
    local arrow = art("training/arrow")
    if arrow then
      fit(G, arrow, { ax, ay, 16 * sc, 16 * sc }, false, { 222, 255, 151 }, 200)
    else
      G.setColor(222 / 255, 1, 151 / 255, 200 / 255)
      G.polygon("fill", ax, ay - 7 * sc, ax - 6 * sc, ay, ax + 6 * sc, ay)
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
    for i, p in ipairs(party()) do
      if not p.active then
        local r = slotOf(i)
        if r then
          local cx, cy = (r.x + r.w / 2) / L, (r.y + BLEED + r.h / 2) / L
          local icon = p.icon
          -- a 2-unit hop every half second, its icon's two frames in turn (the game's party
          -- icons); resting, the icon turned a quarter so it lies face up, so the player knows
          -- to come and wake it
          local frame = math.floor(app.clock / 15) % 2
          local lift = frame == 1 and 2 or 0
          local rot = p.resting and math.pi / 2 or 0
          if icon and icon.image then
            G.setColor(1, 1, 1, (p.eligible and 200 or 90) / 255)
            local q = icon.quads and (icon.quads[frame % (icon.frames or 1)] or icon.quads[0] or icon.quads[1])
            local fw, fh = icon.w or 32, icon.h or 32
            local k = 40 / fw   -- the game's 40x30 icon slot
            if q then
              drawPixel(icon.image, q, cx, cy - lift, rot, k, k, fw / 2, fh / 2)
            else
              drawPixel(icon.image, cx, cy - lift, rot, k, k, fw / 2, fh / 2)
            end
          else
            G.setColor(1, 1, 1, p.eligible and 0.8 or 0.3)
            G.circle("fill", cx, cy, 8, 12)
          end
        end
      end
    end
  end

  local function buttonScale(key)
    local pr = app.press[key]
    if not pr then return 1 end
    if pr.held then return PRESS end
    local f = app.clock - (pr.at or app.clock)
    if f > 4 then app.press[key] = nil; return 1 end
    return eval(BOUNCE, f) or 1
  end

  -- hoisted, with a reused rect: drawButtons runs every home-screen frame
  local BUTTON_ROWS = { { PANE.regimens, "training/btn_regimens", "REGIMENS", "regimens" },
    { PANE.bags, "training/btn_bags", "BAGS", "bags" } }
  local buttonRect = { 0, 0, 0, 0 }
  local function drawButtons(G, small)
    for _, b in ipairs(BUTTON_ROWS) do
      local img = art(b[2])
      if img then
        local k = buttonScale(b[4])
        local p = b[1]
        buttonRect[1], buttonRect[2], buttonRect[3], buttonRect[4] = p[1], p[2], p[3] * k, p[4] * k
        fit(G, img, buttonRect)
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
  -- the strip's middle is recessed (its texture's last 6 of 30 rows are clear there): sized so
  -- that recessed edge meets the buttons' flat lower edge (217.5), the raised ends overlapping
  -- them
  local BOTTOM_STRIP_H = (240 - 217.5) * 30 / 24
  local function drawStrip(G, w)
    local strip = art("training/home_strip")
    if not strip then return end
    G.setColor(1, 1, 1, 1)
    local sw, sh = strip:getDimensions()
    local hgt = 21 / L
    G.draw(strip, 0, 0, 0, (w / 2) / sw, hgt / sh)
    G.draw(strip, w, 0, 0, -(w / 2) / sw, hgt / sh)
    -- upside down along the bottom, its recessed middle on the buttons' flat edge
    G.draw(strip, 0, LH, 0, (w / 2) / sw, -BOTTOM_STRIP_H / sh)
    G.draw(strip, w, LH, 0, -(w / 2) / sw, -BOTTOM_STRIP_H / sh)
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    -- the shape follows the height the surface hands us
    setShape(math.max(240, ((h or 178) + (app.bleed or BLEED)) / L))
    geo()
    G.push()
    G.translate(0, -(app.bleed or BLEED))
    G.scale(L, L)
    if not s then
      G.setColor(0.09, 0.11, 0.16, 1)
      G.rectangle("fill", 0, 0, 320, LH)
      G.setFont(font)
      G.setColor(1, 1, 1, 0.8)
      G.printf("No session", 0, 110, 320 * L, "center", 0, 1 / L, 1 / L)
      G.pop()
      return
    end
    drawRoom(G)
    pushRoom(G, true)
    drawBag(G, s, small)
    drawMon(G, s, small, font)
    drawGift(G, s)
    G.pop()
    drawFrame(G)
    pushRoom(G)
    drawMeter(G, s, small)
    G.pop()
    drawBanner(G, s, font)
    pushRoom(G)
    drawStatUp(G, s, small)
    G.pop()
    G.push()
    G.translate(0, SHAPE.D)
    drawButtons(G, small)
    G.pop()
    drawParty(G)
    drawStrip(G, 320)
    local ret = art("training/home_return")
    if ret then
      G.push()
      G.translate(0, SHAPE.D)
      fit(G, ret, RETURN_PANE)
      G.pop()
    end
    -- the Konami code's R button, opposite the return (shown once the unlock has faded back)
    local unlock = s.anim and s.anim.rocket
    local Rk = T.rocket
    if T.rocketUnlocked and T.rocketUnlocked() and not (unlock and Rk and unlock.t < Rk.UNLOCK.FADE + Rk.UNLOCK.GROW + Rk.UNLOCK.HOLD) then
      local rb = art("rocket/button")
      if rb then
        G.push()
        G.translate(0, SHAPE.D)
        fit(G, rb, ROCKET_PANE)
        G.pop()
      end
    end
    if finishing() then
      -- the strip gives way to the night-blue band and the icon row dims, as in the game
      G.setColor(0.07, 0.11, 0.27, 1)
      G.rectangle("fill", 0, 0, 320, 21 / L)
      G.setColor(0, 0, 0, 136 / 255)
      G.rectangle("fill", 0, LH - BOTTOM_STRIP_H, 320, BOTTOM_STRIP_H)
    end
    -- the found bag's words come up over a dimmed room
    if s.anim and s.anim.gift and s.anim.gift.worded then
      G.setColor(0, 0, 0, 128 / 255)
      G.rectangle("fill", 0, 0, 320, LH)
    end
    -- the session's words, in the game's two-line message window
    local words = s.message or s.cheerText
    if words then
      local win = art("training/win_bl")
      local mx, my, mw, mh = 160, 50, 310, 60
      if win then
        local tw, th = win:getDimensions()
        app.winQuads = app.winQuads or {
          corner = G.newQuad(0, 0, tw, th, tw, th), h = G.newQuad(tw - 1, 0, 1, th, tw, th),
          v = G.newQuad(0, th - 1, tw, 1, tw, th), fill = G.newQuad(tw - 1, th - 1, 1, 1, tw, th) }
        local q, x0, y0 = app.winQuads, mx - mw / 2, my - mh / 2
        local iw, ih = mw - 2 * tw, mh - 2 * th
        G.setColor(1, 1, 1, 1)
        G.draw(win, q.corner, x0, y0); G.draw(win, q.corner, x0 + mw, y0, 0, -1, 1)
        G.draw(win, q.corner, x0, y0 + mh, 0, 1, -1); G.draw(win, q.corner, x0 + mw, y0 + mh, 0, -1, -1)
        G.draw(win, q.h, x0 + tw, y0, 0, iw, 1); G.draw(win, q.h, x0 + tw, y0 + mh, 0, iw, -1)
        G.draw(win, q.v, x0, y0 + th, 0, 1, ih); G.draw(win, q.v, x0 + mw, y0 + th, 0, -1, ih)
        G.draw(win, q.fill, x0 + tw, y0 + th, 0, iw, ih)
      else
        G.setColor(0.07, 0.85, 0.73, 0.85)
        G.rectangle("fill", mx - mw / 2, my - mh / 2, mw, mh, 8, 8)
      end
      G.setFont(small)
      local k = math.min(18 / math.max(1, small:getHeight()), 200 / math.max(1, small:getWidth("Trains Speed stat a fair amount.")))
      G.setColor(0.03, 0.25, 0.22, 0.7)
      G.printf(words, mx - mw / 2 + 13, my - mh / 2 + 9, (mw - 24) / k, "left", 0, k, k)
      G.setColor(1, 1, 1, 1)
      G.printf(words, mx - mw / 2 + 12, my - mh / 2 + 8, (mw - 24) / k, "left", 0, k, k)
    end
    -- a screen change: the shutters close over the home screen, or open on it
    local tv = T.transView and T.transView("bottom")
    if tv and tv.shutter and app.lyt then app.lyt.shutters(G, art, 320, LH, tv.shutter, tv.f) end
    -- into the alley and back: a fade through black
    if tv and tv.black and tv.black > 0 then
      G.setColor(0, 0, 0, tv.black)
      G.rectangle("fill", -10, -20, 340, LH + 40)
    end
    -- the Konami code: to black, the R grows in with its glint, and back
    if unlock and Rk then drawUnlock(G, unlock.t, Rk) end
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  return app
end
