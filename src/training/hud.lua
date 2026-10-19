-- The regimen's top screen as the game lays it over the arena: upper.bclyt in a/1/1/4
-- (src/lytplayer.lua plays it) with the intro (the title band, the balloon's and the
-- trainee's name bands, the HUD sliding in, Start), the play HUD (the balloon's name, the
-- clock, SCORE and its digits, the trainee's name, the energy gauge, the reticle and its
-- charge rings, the +N over a hit) and the end (the HUD out, Success! or the game-over banner).
--
-- Timings (seconds from the screen's fade-in) are from a capture of Hone Sp. Atk with
-- Magnemite: the title (alert, 90 frames: it grows in, holds, flies out) 0-3, the balloon
-- rises 2.7-5.7, its name 7.1-8.1, the trainee 8.5-9.9, the HUD at 10.1, Start at 10.5
-- (game_start, 41 frames), the clock runs after it.
-- The end: the last hit, the HUD leaves, the balloon wobbles, deflates and zips away
-- (0.5-4.8), a twinkle where it vanished, Success! at 7.5 (game_clear, 51 frames), the
-- screens fade out by 9.5.
--
-- The layout is 400x240; the top screen is 240x160. It is drawn at 0.6 with the root's
-- children spread down to 160 (their positions stretch, their sizes do not), so the frame
-- reaches the corners and the bands sit where the game has them.
--
-- H = makeHud(mod, T, Rules, Sim) ; H.begin(sim, s) ; H.update(dt) ; H.draw(G2, sim, s)
-- H.pose(sim, s) -> what the arena does meanwhile ; H.INTRO_S ; H.OUTRO

return function(mod, T, Rules, Sim)
  local H = {}
  local FPS = 30

  -- PUMP_AT: the balloon lies flat on the grass and is blown up in five pumps, each with the
  -- game's pump sound (onsets measured in the capture's audio, data/training_sounds.lua), each
  -- swelling it sideways before it settles; PUMPS spans them; RISE: full, it floats up to its
  -- place. BOT_NAME_SE: the name's sound, as it slides in.
  -- PUMP_PEAK / PUMP_REST: its size (of full) at each pump's peak and where it sags to after,
  -- measured from the capture's frames (pumps 3-5; 1-2 scaled down to match)
  H.INTRO = { PUMP_AT = { 3.05, 3.69, 4.52, 5.36, 6.19 }, PUMP_PEAK = { 0.32, 0.46, 0.67, 0.89, 1.06 },
    PUMP_REST = { 0.24, 0.34, 0.45, 0.73, 0.9 }, PUMP_SWELL_S = 0.08, PUMP_SAG_S = 0.25,
    PUMPS = { 3.05, 6.6 }, RISE = { 6.6, 7.0 },
    BOT_NAME = { 7.1, 8.1 }, BOT_NAME_SE = 7.50, PLAYER_NAME = { 8.5, 9.9 }, HUD_IN = 10.1, START = 10.5 }
  H.INTRO_S = H.INTRO.START + 41 / FPS
  -- ours, on top of the capture's timings:
  -- SWAY: full and risen, the balloon sways in the air (AMP units across, BOB down, TILT
  --   radians, HZ) from IN, easing out to nothing by OUT (the game's start), so it is where the
  --   game starts it
  -- ENTER: the trainee rides in from past the area's right edge, arriving as its name shows
  -- CAM: the stadium seen close on the flat balloon (ZOOM) through the title, then zooming out
  --   and up as it fills, settled by the end of the rise
  H.SWAY = { IN = { 7.0, 7.6 }, OUT = { 9.7, 10.5 }, AMP = 4, BOB = 1.5, TILT = 0.035, HZ = 0.45 }
  H.ENTER = { 7.6, 8.5 }
  H.CAM = { ZOOM = 2.4, OUT = { 2.7, 7.0 } }
  H.OUTRO = { HUD_OUT = 0.3, WOBBLE = { 0.5, 1.5 }, FLY = { 1.5, 4.8 }, AWAY = { 4.8, 6.0 }, TWINKLE = { 6.0, 6.8 }, BANNER = 7.5,
    FADE = { 9.0, 9.5 }, END = 9.6 }

  -- 400x240 -> 240x160
  local S = 0.6
  local STRETCH = (160 / S) / 240

  local function clock(secs)
    secs = math.max(0, math.ceil(secs or 0))
    return math.floor(secs / 60), secs % 60
  end

  local function speciesName(national)
    local name = T.gameLine and T.gameLine("species", national) or nil
    if name and name ~= "" then return name end
    return T.host and T.host.speciesName and T.host.speciesName(national) or ("#" .. tostring(national))
  end

  local function balloonName(sim)
    local bot = sim and sim.bot
    if not bot then return "" end
    local suffix = T.gameLine and T.gameLine("training_coach", 50) or " Balloon"
    return speciesName(bot.national) .. suffix
  end

  local function stretchPane(P)
    -- positions spread to 160, full-height panes stretched with them
    P.stretchY = STRETCH
  end

  -- a pane at a point of the 240x160 screen (the root's children only)
  local function placeAt(P, name, x, y)
    P:set(name, "tx", (x - 120) / S)
    P:set(name, "ty", (80 - y) / (S * STRETCH))
  end
  H.placeAt = placeAt

  local DIGIT = function(d) return "num" .. d .. "_c.bclim" end
  local SCORE = function(d) return "score_nom" .. d .. ".bclim" end

  -- four digit slots, right-aligned, blanks hidden
  local function setNumber(P, panes, n, tex)
    local s = tostring(math.max(0, math.floor(n or 0)))
    for i = 1, #panes do
      local ch = s:sub(#s - #panes + i, #s - #panes + i)
      local idx = #s - (#panes - i)
      if idx >= 1 then
        P:set(panes[i], "visible", true)
        P:setImage(panes[i], P:image(tex(s:sub(idx, idx))))
      else
        P:set(panes[i], "visible", false)
      end
    end
  end

  local SCORE_PANES = { "89", "8b", "8d", "8f" }
  local TARGET_PANES = { "87", "85", "83", "81" }
  local POPUPS = { "95", "af", "aq", "b1", "bc", "bn", "by", "c9" }
  local POPUP_S = 0.9

  -- digits from the left (the +N groups: the plus, then the number)
  local function setNumberLeft(P, panes, n, tex)
    local s = tostring(math.max(0, math.floor(n or 0)))
    for i = 1, #panes do
      if i <= #s then
        P:set(panes[i], "visible", true)
        P:setImage(panes[i], P:image(tex(s:sub(i, i))))
      else
        P:set(panes[i], "visible", false)
      end
    end
  end

  local function setClock(P, secs)
    local m, sec = clock(secs)
    P:setImage("1s", P:image(DIGIT(m % 10)))
    P:setImage("1x", P:image(DIGIT(math.floor(sec / 10))))
    P:setImage("4c", P:image(DIGIT(sec % 10)))
  end

  -- ------- the regimen begins: a fresh screen

  function H.begin(sim, s)
    H.sim, H.s = sim, s
    H.cues, H.popups, H.lastT, H.score, H.outroCues = {}, {}, nil, nil, {}
    H.charge, H.full = 0, false
    local Sc = T.lyt
    local P = Sc and Sc.open("st_hud", "upper.bclyt", { "st_hud", "st_lang" }) or nil
    H.P = P
    if not P then return end
    stretchPane(P)
    -- off-screen parts the code places, and the parts that wait for their cue
    P:set("1u", "visible", false)
    for _, name in ipairs(POPUPS) do P:set(name, "visible", false) end
    P:setText("15", T.courseName and s.course and T.courseName(s.course.id) or "")
    P:setText("4y", balloonName(sim), { align = "left" })
    P:setText("4w", s.name or "", { align = "right" })
    P:setText("7z", T.gameLine and T.gameLine("training_coach", 111) or "SCORE:")
    setNumber(P, SCORE_PANES, 0, SCORE)
    setNumber(P, TARGET_PANES, sim.bot and sim.bot.target or 0, SCORE)
    P:set("8h", "visible", true)
    setClock(P, sim.remaining)
    P:play("no_mask")
    P:play("stamina", { speed = 0 })
    P:play("no_charge")
    P:play("cursor", { loop = true })
    P:play("alert")
  end

  -- cues fire once when their time passes
  local function cue(name, at, t, fn)
    if H.cues[name] or t < at then return end
    H.cues[name] = true
    fn()
  end

  local function introCues(P, sim, s, t)
    local I = H.INTRO
    for k, at in ipairs(I.PUMP_AT) do
      cue("pump" .. k, at, t, function() if T.playSe then T.playSe("pump") end end)
    end
    cue("bot_name_se", I.BOT_NAME_SE, t, function() if T.playSe then T.playSe("bot_name") end end)
    cue("bot_name", I.BOT_NAME[1], t, function()
      P:setText("1q", balloonName(sim))
      P:play("enemy_name_on")
    end)
    cue("bot_name_off", I.BOT_NAME[2], t, function() P:play("enemy_name_off") end)
    cue("player_name", I.PLAYER_NAME[1], t, function()
      P:setText("1q", s.name or "")
      P:play("enemy_name_on")
    end)
    cue("player_name_off", I.PLAYER_NAME[2], t, function() P:play("enemy_name_off") end)
    cue("hud_in", I.HUD_IN, t, function()
      P:play("gauge_l_0_in")
      P:play("gauge_l_1_in")
      P:set("1u", "visible", true)
    end)
    cue("start", I.START, t, function() P:play("game_start") end)
  end

  local function outroCues(P, sim, o)
    local O = H.OUTRO
    local t = o.t
    cue("hud_out", O.HUD_OUT, t, function()
      P:play("gauge_out")
      P:set("1u", "visible", false)
      P:set("13", "visible", false)
      P:set("58", "visible", false)
    end)
    -- the exit's sounds on our own animation's phases: the leak while it zigzags off, the
    -- burst as it zips away, the twinkle as it vanishes (data/training_sounds.lua)
    if o.outcome and o.outcome.clear and T.playSe then
      cue("hiss", O.FLY[1], t, function() H.hiss = T.playSe("deflate_hiss") end)
      cue("burst", O.AWAY[1], t, function()
        if type(H.hiss) == "table" then H.hiss.stop() end
        H.hiss = nil
        T.playSe("deflate_burst")
      end)
      cue("star", O.TWINKLE[1], t, function() T.playSe("star") end)
    end
    cue("banner", O.BANNER, t, function()
      if o.outcome and o.outcome.clear then P:play("game_clear") else P:play("ohdear") end
    end)
  end

  -- a hit's points over the balloon: the next free +N group, rising and fading
  local function popup(P, sim, points)
    local slot = nil
    for i, name in ipairs(POPUPS) do
      if not H.popups[name] then slot = name; break end
    end
    slot = slot or POPUPS[1]
    local bx, by = sim:botOffset()
    local cyW = sim.botCY and sim:botCY() or Rules.N.BOT.CY
    local x, y = T.toScreen(Sim.project(bx, cyW + by, 1))
    H.popups[slot] = { t = 0, x = x, y = y, points = points }
    local pane = P.L.byName[slot]
    local digits = {}
    for _, c in ipairs(pane and pane.children or {}) do
      if c.name ~= pane.children[1].name then digits[#digits + 1] = c.name end
    end
    setNumberLeft(P, digits, points, SCORE)
    P:set(slot, "visible", true)
    P:set(slot, "inherit", true)
  end

  local function stepPopups(P, dt)
    for name, p in pairs(H.popups) do
      p.t = p.t + dt
      if p.t >= POPUP_S then
        H.popups[name] = nil
        P:set(name, "visible", false)
      else
        -- the group (a child of the full-screen pane 7x, which sits at the middle) over the hit
        local k = p.t / POPUP_S
        P:set(name, "tx", (p.x - 120) / S)
        P:set(name, "ty", (80 - (p.y - 10 - 14 * k)) / (S * STRETCH))
        P:set(name, "alpha", k < 0.7 and 255 or math.floor(255 * (1 - (k - 0.7) / 0.3)))
      end
    end
  end

  function H.update(dt, events)
    local P, sim, s = H.P, T.sim, T.session
    if not (P and sim and s) then return end
    if sim ~= H.sim then H.begin(sim, s); P = H.P; if not P then return end end
    P:advance((dt or 0) * FPS)
    local o = s.outro
    if sim.phase == "countdown" then
      introCues(P, sim, s, sim.t)
    end
    if o then outroCues(P, sim, o) end
    -- the clock, the score and the gauge
    setClock(P, sim.remaining)
    if H.score ~= sim.score then
      H.score = sim.score
      setNumber(P, SCORE_PANES, sim.score, SCORE)
      P:play("score_num")
    end
    setNumber(P, TARGET_PANES, sim.bot and sim.bot.target or 0, SCORE)
    local st = P:entry("stamina")
    if st then st.frame = math.max(0, math.min(1, sim.guts or 0)) * (st.clip.frames - 1) end
    -- the reticle and its charge
    local aim = sim.player.aim
    local rx, ry, rz = T.toScreen(Sim.project(aim.x, aim.y, 1))
    placeAt(P, "13", rx, ry)
    P:set("13", "sx", rz)
    P:set("13", "sy", rz)
    P:set("13", "visible", sim.phase == "play" and not o)
    local stage = sim:chargeStage()
    if stage > 0 and H.charge == 0 then P:play("charge") end
    if stage >= 3 and not H.full then H.full = true; P:play("just_charge") end
    if stage == 0 and H.charge > 0 then P:play("no_charge"); H.full = false end
    H.charge = stage
    for _, e in ipairs(events or {}) do
      if e.kind == "goal_hit" and (e.points or 0) > 0 then popup(P, sim, e.points) end
      if e.kind == "player_hit" then P:play("damage") end
    end
    stepPopups(P, dt or 0)
  end

  -- ------- what the arena does meanwhile: the balloon rises in, the end's deflate and zip

  local function smooth(a, b, t)
    local k = math.max(0, math.min(1, (t - a) / (b - a)))
    return k * k * (3 - 2 * k)
  end

  function H.pose(sim, s)
    if not H.P then return nil end
    local pose = {}
    if sim.phase == "countdown" then
      local I, t = H.INTRO, sim.t
      -- five pumps, as the capture shows them (the balloon's size measured frame by frame):
      -- at each pump's sound it swells fast to PUMP_PEAK, a little wider than tall, in
      -- PUMP_SWELL_S, then sags back toward PUMP_REST until the next pump; after the last it
      -- fills out to full for the rise
      local at, peak, rest = I.PUMP_AT, I.PUMP_PEAK, I.PUMP_REST
      local i = 0
      for k = #at, 1, -1 do if t >= at[k] then i = k; break end end
      local size, swell = rest[1] * 0.6, 0
      if i > 0 then
        local dt = t - at[i]
        local before = i > 1 and rest[i - 1] or rest[1] * 0.6
        if dt < I.PUMP_SWELL_S then
          local k = smooth(0, I.PUMP_SWELL_S, dt)
          size = before + (peak[i] - before) * k
          swell = math.sin(k * math.pi * 0.5) * 0.12
        else
          local k = 1 - math.exp(-(dt - I.PUMP_SWELL_S) / I.PUMP_SAG_S)
          size = peak[i] + (rest[i] - peak[i]) * k
          swell = 0.12 * (1 - k)
        end
        if i == #at then
          -- the last: fill out to full by the rise
          size = size + (1 - size) * smooth(at[i] + 0.3, I.RISE[1], t)
        end
      end
      local progress = math.max(0, math.min(1, (t - I.PUMPS[1]) / (I.PUMPS[2] - I.PUMPS[1])))
      local rise = smooth(I.RISE[1], I.RISE[2], t)
      -- flat at first, rounding out as it fills; a little bounce as it lifts off
      local flat = 0.35 + 0.65 * progress
      pose.bot = { ground = true, rise = rise, sx = size * (1 + swell), sy = size * flat * (1 - swell * 0.5)
        + (rise > 0 and rise < 1 and math.sin(rise * math.pi) * 0.05 or 0),
        alpha = t < I.PUMPS[1] and 0 or 1 }
      -- full and up: a sway in the air, gone by the start
      local Sw = H.SWAY
      local env = smooth(Sw.IN[1], Sw.IN[2], t) * (1 - smooth(Sw.OUT[1], Sw.OUT[2], t))
      if env > 0 then
        local ph = (t - Sw.IN[1]) * Sw.HZ * 2 * math.pi
        pose.bot.dx = Sw.AMP * math.sin(ph) * env
        pose.bot.bob = Sw.BOB * math.sin(ph * 2 + 0.8) * env
        pose.bot.rz = Sw.TILT * math.sin(ph + 0.6) * env
      end
      -- the trainee: off past the right edge until it rides in for its name
      pose.playerIn = smooth(H.ENTER[1], H.ENTER[2], t)
      -- the camera: close on the flat balloon, out and up as it fills
      local out = smooth(H.CAM.OUT[1], H.CAM.OUT[2], t)
      if out < 1 then pose.cam = { zoom = 1 + (H.CAM.ZOOM - 1) * (1 - out), k = out } end
      -- the stadium comes up out of its outline under the title
      pose.veil = 1 - smooth(0.6, 2.4, t)
      pose.hideReticle = true
    end
    local o = s and s.outro
    if o then
      local O, t = H.OUTRO, o.t
      local wob = (t >= O.WOBBLE[1] and t < O.FLY[1]) and math.sin(t * 30) * 3 or 0
      local fly = smooth(O.FLY[1], O.FLY[2], t)
      local cleared = o.outcome and o.outcome.clear
      if cleared then
        -- a zigzag up and away as the air goes out of it, then it shrinks off into the sky (its
        -- puffs shrinking with it, for the distance)
        local zig = math.sin(fly * math.pi * 5) * 40 * (1 - fly)
        local away = smooth(O.AWAY[1], O.AWAY[2], t)
        local scale = (1 - 0.5 * fly) * (1 - 0.96 * away)
        -- its way out ends just above the stadium roof's edge (arena_draw D.exitOffset, from
        -- the art's place on this screen): 60% of the way on the zigzag, the rest zipping off
        local endX, endY = 100, -45
        if T.exitOffset then
          local ok, x, y = pcall(T.exitOffset, sim, T)
          if ok and x then endX, endY = x, y end
        end
        -- the last goal bursts with the final hit: none ride along; the shadow fades as it rises
        pose.bot = { dx = wob + zig + (fly * 0.6 + away * 0.4) * endX, dy = (fly * 0.55 + away * 0.45) * endY, scale = scale,
          alpha = t < O.AWAY[2] and 1 or 0, puffs = t >= O.FLY[1] and t < O.AWAY[2] and fly or nil, puffScale = scale,
          noGoals = true, shadow = 1 - fly,
          -- the game's air (arena_draw): gusts while it leaks (the zigzag), then the burst as it
          -- zips away and its trail, lasting past its going a little
          leakT = (t >= O.FLY[1] and t < O.AWAY[1]) and (t - O.FLY[1]) or nil,
          burstT = (t >= O.AWAY[1] and t < O.TWINKLE[2]) and (t - O.AWAY[1]) or nil }
        if t >= O.TWINKLE[1] and t < O.TWINKLE[2] then
          pose.twinkle = { k = (t - O.TWINKLE[1]) / (O.TWINKLE[2] - O.TWINKLE[1]), dx = endX, dy = endY }
        end
      end
      if not pose.bot then pose.bot = { noGoals = true } end
      pose.hideReticle = true
      pose.fade = smooth(O.FADE[1], O.FADE[2], t)
    end
    return pose
  end

  -- The top screen fills the playfield (T.topExtent, 240x160 units): the HUD's edges go with
  -- it. The frame bands spread across, the timer, names, score and gauges keep to their
  -- corners, full-screen washes and banners widen; the brackets (5x / 5z, which aiming maps
  -- onto: aim_app TOPBOX), goals, balls and popups stay on the arena.
  local adjustKey, adjustT = nil, nil
  H.EDGE_MAX = 1.8
  local function fitAdjust(e)
    if not e then return nil end
    local key = ("%s %.2f %.2f %.2f %.2f"):format(tostring(H.P), e.x, e.y, e.w, e.h)
    if key == adjustKey then return adjustT end
    local kx, ky = e.w / 240, e.h / 160
    local SY = S * STRETCH
    local dl, dr = e.x / S, (e.x + e.w - 240) / S
    local dt, db = -e.y / SY, -(e.y + e.h - 160) / SY
    local dcx, dcy = (e.x + e.w / 2 - 120) / S, -(e.y + e.h / 2 - 80) / SY
    -- the edge pieces grow with the area too (kh), each about its own corner of the frame
    -- (fx, fy: 0 / 120 / 240, 0 / 160) before it moves out to the area's: on a screen where the
    -- frame is small next to the area they would otherwise be tiny
    local kh = math.max(1, math.min(H.EDGE_MAX, kx, ky))
    local function corner(fx, fy, sxk, syk)
      return { mx = kh, my = kh, sx = kh, sy = kh,
        dx = (fx - 120) * (1 - kh) / S + sxk, dy = (80 - fy) * (1 - kh) / SY + syk }
    end
    local A = {
      -- the bands (top-left 5g carries top-right 5e, bottom-right 5a carries 5c), 105 from the
      -- middle: across the area, as thick as kh, from their edge
      ["5g"] = { dx = -105 * (kx - 1) + dcx, sx = kx, sy = kh, my = kh, dy = 80 * (1 - kh) / SY + dt },
      ["5a"] = { dx = 105 * (kx - 1) + dcx, sx = kx, sy = kh, my = kh, dy = (80 - 160) * (1 - kh) / SY + db },
      ["1u"] = corner(240, 0, dr, dt),        -- the timer
      ["58"] = corner(120, 160, 0, db),       -- the guts circle and its charge, down with the foot
      ["6u"] = corner(120, 160, 0, db),
      j = corner(0, 0, dl, dt),               -- the balloon's name
      w = corner(240, 160, dr, db),           -- the trainee's name, the score
      ["1j"] = { dx = dcx, dy = dt, qx = kx }, -- the caution bands
      ["1n"] = { dx = dcx, dy = db, qx = kx },
    }
    for _, n in ipairs({ "i", "m", "p", "1d", "1g" }) do A[n] = corner(240, 0, dr, dt) end
    for _, n in ipairs({ "g", "1l", "11", "6x" }) do A[n] = { dx = dcx, dy = dcy, qx = kx, qy = ky } end
    for _, n in ipairs({ "65", "6z" }) do A[n] = { dx = 100 * (kx - 1), qx = kx, qy = ky } end
    for _, n in ipairs({ "63", "71" }) do A[n] = { dx = -100 * (kx - 1), qx = kx, qy = ky } end
    for _, n in ipairs({ "67", "69", "75", "77" }) do A[n] = { qy = kx } end
    for _, n in ipairs({ "9p", "9l", "9j", "9n", "9h", "7e", "7i", "7k" }) do A[n] = { qx = kx } end
    -- framed back (a wide area), the brackets (5m: 5x / 5z) stretch to fit the area as the
    -- frame has them; aiming follows them (T.aimToScene)
    if T.bracketFit and T.bracketFit() then
      A["5m"] = { sx = kx, sy = ky, dx = dcx, dy = dcy }
    end
    -- the panes the game parks just off its screen until they are wanted (the penalty score,
    -- idle goals, balls and marks) stay off the wider area: out past the same edge
    local root = H.P and H.P.L and H.P.L.root
    for _, c in ipairs(root and root.children or {}) do
      if not A[c.name] and c.t then
        local x, y = 200 + c.t[1], 120 - c.t[2]
        local dx = (x < 0 and dl) or (x > 400 and dr) or 0
        local dy = (y < 0 and dt) or (y > 240 and db) or 0
        if dx ~= 0 or dy ~= 0 then A[c.name] = { dx = dx, dy = dy, parked = true } end
      end
    end
    adjustKey, adjustT = key, A
    return A
  end
  H.fitAdjust = fitAdjust

  function H.draw(G2, sim, s)
    local P = H.P
    if not P or sim ~= H.sim then return false end
    P.adjust = fitAdjust(T.topExtent)
    G2.push()
    G2.scale(S, S)
    P:draw(G2)
    G2.pop()
    return true
  end

  return H
end
