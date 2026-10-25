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
  -- 3D SUPER TRAINING's ending (arena_draw D.ENDING): its own times for the same sounds - the
  -- leak from the cut to the ending's camera, the burst as it shoots off, the star
  H.OUTRO3D = { HISS = 0.25, BURST = 3.75, STAR = 6.0 }
  -- the exit's three sound times: the 3D ending's, else the 2D exit's phases
  local function exitTimes()
    if T.is3d and T.is3d() then
      local E = H.OUTRO3D
      return E.HISS, E.BURST, E.STAR
    end
    local O = H.OUTRO
    return O.FLY[1], O.AWAY[1], O.TWINKLE[1]
  end

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

  -- the engine draws the HUD (src/training/ui_art.lua's Assets.engine); off, the game's layout
  local function engineOn()
    local A = T.assets
    return A ~= nil and A.engine ~= nil
  end

  -- ------- the regimen begins: a fresh screen

  function H.begin(sim, s)
    H.sim, H.s = sim, s
    H.cues, H.popups, H.lastT, H.score, H.outroCues = {}, {}, nil, nil, {}
    H.charge, H.full = 0, false
    H.engine = engineOn()
    H.scoreAt, H.fullAt, H.damageAt, H.clock = nil, nil, nil, 0
    if H.engine then H.P = nil; return end
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
      local hissAt, burstAt, starAt = exitTimes()
      cue("hiss", hissAt, t, function() H.hiss = T.playSe("deflate_hiss") end)
      cue("burst", burstAt, t, function()
        if type(H.hiss) == "table" then H.hiss.stop() end
        H.hiss = nil
        T.playSe("deflate_burst")
      end)
      cue("star", starAt, t, function() T.playSe("star") end)
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

  -- the engine's HUD: the same cues (sounds), and what the drawing needs to know
  local function engineUpdate(sim, s, dt, events)
    H.clock = H.clock + (dt or 0)
    local o = s.outro
    if sim.phase == "countdown" then
      local I = H.INTRO
      for k, at in ipairs(I.PUMP_AT) do
        cue("pump" .. k, at, sim.t, function() if T.playSe then T.playSe("pump") end end)
      end
      cue("bot_name_se", I.BOT_NAME_SE, sim.t, function() if T.playSe then T.playSe("bot_name") end end)
    end
    if o and o.outcome and o.outcome.clear and T.playSe then
      local hissAt, burstAt, starAt = exitTimes()
      cue("hiss", hissAt, o.t, function() H.hiss = T.playSe("deflate_hiss") end)
      cue("burst", burstAt, o.t, function()
        if type(H.hiss) == "table" then H.hiss.stop() end
        H.hiss = nil
        T.playSe("deflate_burst")
      end)
      cue("star", starAt, o.t, function() T.playSe("star") end)
    end
    if H.score ~= sim.score then
      if H.score then H.scoreAt = H.clock end
      H.score = sim.score
    end
    local stage = sim:chargeStage()
    if stage >= 2 and not H.full then H.full = true; H.fullAt = H.clock end
    if stage == 0 then H.full = false end
    if stage >= 1 and (H.charge or 0) == 0 then H.chargeAt = H.clock end
    H.charge = stage
    -- the two rings: shown while the meter covers a shot, turning in from a pop
    local ready = sim.shotReady and sim:shotReady() and sim.phase == "play" or false
    if ready and not H.ready then H.readyAt = H.clock end
    H.ready = ready
    for _, e in ipairs(events or {}) do
      if e.kind == "goal_hit" and (e.points or 0) > 0 then
        local bx, by = sim:botOffset()
        local cyW = sim.botCY and sim:botCY() or Rules.N.BOT.CY
        local x, y = T.toScreen(Sim.project(bx, cyW + by, 1))
        H.popups[#H.popups + 1] = { t = 0, x = x, y = y, points = e.points }
      end
      if e.kind == "player_hit" then H.damageAt = H.clock end
    end
    for i = #H.popups, 1, -1 do
      local p = H.popups[i]
      p.t = p.t + (dt or 0)
      if p.t >= POPUP_S then table.remove(H.popups, i) end
    end
  end

  function H.update(dt, events)
    local sim, s = T.sim, T.session
    if not (sim and s) then return end
    if sim ~= H.sim then H.begin(sim, s) end
    if H.engine then engineUpdate(sim, s, dt, events); return end
    local P = H.P
    if not P then return end
    P:advance((dt or 0) * FPS)
    local o = s.outro
    if sim.phase == "countdown" then
      introCues(P, sim, s, sim.t)
    end
    -- the next balloon's name, in the changeover
    if sim.phase == "between" and sim.between and sim.between.swapped then
      local B, bt, k = Rules.N.BETWEEN, sim.between.t, "stage" .. sim.botIndex
      cue(k .. "_name", B.NAME[1], bt, function()
        P:setText("1q", balloonName(sim))
        P:play("enemy_name_on")
      end)
      cue(k .. "_name_off", B.NAME[2], bt, function() P:play("enemy_name_off") end)
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
    -- the two rings round the meter (6u: 6j / 6l turning, the looping guts_shot): the game shows
    -- them while the meter covers a shot (its ready flag)
    local ready = sim.shotReady and sim:shotReady() and sim.phase == "play" and not o or false
    if ready and not H.ready and not P:entry("guts_shot") then P:play("guts_shot", { loop = true }) end
    P:set("6u", "visible", ready)
    H.ready = ready
    -- the reticle and its charge
    local aim = sim.player.aim
    local rx, ry, rz = T.toScreen(Sim.project(aim.x, aim.y, 1))
    placeAt(P, "13", rx, ry)
    P:set("13", "sx", rz)
    P:set("13", "sy", rz)
    P:set("13", "visible", sim.phase == "play" and not o)
    -- Charged (frame 50): the yellow ring and the second crosshair closing in over the clip's
    -- 16 frames, which is when the full charge comes (frame 66): red
    local stage = sim:chargeStage()
    if stage > 0 and H.charge == 0 then P:play("charge") end
    if stage >= 2 and not H.full then H.full = true; P:play("just_charge") end
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
    if not (H.P or (H.engine and sim == H.sim)) then return nil end
    local pose = {}
    if sim.phase == "between" and sim.between then
      -- the changeover: the beaten balloon collapses flat and wide onto the grass; after the
      -- swap the next lies flat and inflates where it lies, then lifts to its place
      local B, t = Rules.N.BETWEEN, sim.between.t
      if t < B.SWAP_S then
        local k = smooth(B.DEFLATE[1], B.DEFLATE[2], t)
        pose.bot = { ground = true, rise = 0, sx = 1 + 0.55 * k, sy = 1 - 0.85 * k }
      else
        local k = smooth(B.INFLATE[1], B.INFLATE[2], t)
        local lift = smooth(B.INFLATE[2] - 0.4, B.INFLATE[2] + 0.4, t)
        pose.bot = { ground = true, rise = lift, sx = 1.25 - 0.25 * k, sy = 0.15 + 0.85 * k
          + (k > 0 and k < 1 and math.sin(k * math.pi) * 0.05 or 0) }
      end
      -- through black between the two
      local fo = smooth(B.FADE_OUT[1], B.FADE_OUT[2], t)
      local fi = smooth(B.FADE_IN[1], B.FADE_IN[2], t)
      pose.fade = fo * (1 - fi)
      pose.hideReticle = true
      return pose
    end
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

  -- ------- the HUD drawn by the engine, in the top screen's 240x160 units; the edge pieces go
  -- to the corners of the area it covers (T.topExtent), grown as the frame's are (EDGE_MAX)

  local WHITE3, BLACK3, INK_TEAL, INK_SCORE, INK_POP = { 255, 255, 255 }, { 0, 0, 0 }, { 0, 40, 36 }, { 10, 90, 80 }, { 20, 60, 60 }
  local LOW_RED, GLOW, WORD, INK_WORD = { 255, 110, 90 }, { 60, 230, 200 }, { 200, 255, 245 }, { 6, 90, 84 }
  local CORNERS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
  -- the meter's rings: a turn every 100 frames (guts_shot's 6j / 6l), drawn by pointedRing
  local RING_TURN_S = 100 / 30
  local pointedRing
  local fonts = {}
  local function font(px)
    local f = fonts[px]
    if not f then
      local ok, made = pcall(love.graphics.newFont, px)
      f = ok and made or love.graphics.getFont()
      fonts[px] = f
    end
    return f
  end
  local TEAL, TEAL_HI, TEAL_LO = { 30, 172, 126 }, { 80, 236, 210 }, { 8, 100, 90 }
  local function c(G2, rgb, a) G2.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, a or 1) end
  -- text of a height (units) at x, y; align "left" | "center" | "right"; an outline when ink is given
  local function say(G2, text, x, y, hgt, align, fill, ink, a)
    local f = font(48)
    local k = hgt / f:getHeight()
    local w = f:getWidth(text) * k
    local x0 = (align == "center" and x - w / 2) or (align == "right" and x - w) or x
    G2.setFont(f)
    if ink then
      c(G2, ink, a)
      local o = math.max(0.5, hgt * 0.07)
      for dx = -1, 1 do
        for dy = -1, 1 do
          if dx ~= 0 or dy ~= 0 then G2.print(text, x0 + dx * o, y + dy * o, 0, k, k) end
        end
      end
    end
    c(G2, fill, a)
    G2.print(text, x0, y, 0, k, k)
    return w
  end
  local function smooth01(a, b, t)
    local k = math.max(0, math.min(1, (t - a) / (b - a)))
    return k * k * (3 - 2 * k)
  end

  -- the bands' outlines are concave (their inner edge dips): triangulated once per area
  local bandKey, bandTris = nil, nil
  local function fillTris(G2, tris) for i = 1, #tris do G2.polygon("fill", tris[i]) end end
  local function frameBands(G2, e, kh)
    local x0, x1, y0, y1 = e.x, e.x + e.w, e.y, e.y + e.h
    local d = 10 * kh
    local key = x0 * 1e9 + x1 * 1e6 + y0 * 1e3 + y1 + kh
    if key ~= bandKey then
      local tri = love.math.triangulate
      bandTris = {
        tri({ x0, y0, x1, y0, x1, y0 + d, x1 - 46 * kh, y0 + 3 * kh, x0 + 46 * kh, y0 + 3 * kh, x0, y0 + d }),
        tri({ x0, y0 + d - 2 * kh, x0 + 46 * kh, y0 + kh, x1 - 46 * kh, y0 + kh, x1, y0 + d - 2 * kh,
          x1, y0 + d, x1 - 46 * kh, y0 + 3 * kh, x0 + 46 * kh, y0 + 3 * kh, x0, y0 + d }),
        tri({ x0, y1, x0, y1 - 4 * kh, x0 + 46 * kh, y1 - 1.5 * kh, x1 - 46 * kh, y1 - 1.5 * kh, x1, y1 - 4 * kh, x1, y1 }),
      }
      bandKey = key
    end
    -- the top: the drawn corners (src/training/ui_art.lua), the right one mirrored, and the
    -- lip between them; without them, the plain bands
    local A = T.assets
    local corner = A and A.image and A.image("training/hud_corner")
    local lip = A and A.image and A.image("training/hud_lip")
    if corner and lip then
      local cw, ch = corner:getDimensions()
      local lw, lh = lip:getDimensions()
      local s = 80 * kh / cw
      G2.setColor(1, 1, 1, 1)
      G2.draw(corner, x0, y0, 0, s, s)
      G2.draw(corner, x1, y0, 0, -s, s)
      G2.draw(lip, x0 + 80 * kh, y0, 0, (x1 - x0 - 160 * kh) / lw, 3 * kh / lh)
    else
      c(G2, TEAL)
      fillTris(G2, bandTris[1])
      c(G2, TEAL_LO)
      fillTris(G2, bandTris[2])
    end
    c(G2, TEAL_HI, 0.8)
    G2.setLineWidth(1.4 * kh)
    G2.line(x0 + 62 * kh, y0 + 10 * kh, x0 + 66 * kh, y0 + 8 * kh, x0 + 77 * kh, y0 + 7 * kh)
    G2.line(x1 - 62 * kh, y0 + 10 * kh, x1 - 66 * kh, y0 + 8 * kh, x1 - 77 * kh, y0 + 7 * kh)
    -- the bottom's thin band
    c(G2, TEAL, 0.9)
    fillTris(G2, bandTris[3])
  end

  local function brackets(G2, a)
    -- aim_app's TOPBOX: the brackets the aim screen's stand for
    c(G2, TEAL_HI, 0.5 * a)
    G2.setLineWidth(1.3)
    local cy, r = 80, 46
    G2.arc("line", "open", 57.6 + 30, cy, r, math.rad(140), math.rad(220), 24)
    G2.arc("line", "open", 182.4 - 30, cy, r, math.rad(-40), math.rad(40), 24)
  end

  local function clockText(secs)
    local m, sec = clock(secs)
    return ("%d:%02d"):format(m, sec)
  end

  local function hudParts(G2, sim, s, e, kh, inK)
    local x0, x1, y0, y1 = e.x, e.x + e.w, e.y, e.y + e.h
    local slide = (1 - inK) * 40 * kh
    -- the balloon's name, top left, on a dark wash fading right
    G2.push()
    G2.translate(-slide, 0)
    local name = balloonName(sim)
    local nh = 7.5 * kh
    local mesh = H.nameWash
    if not mesh then
      mesh = love.graphics.newMesh({ { 0, 0, 0, 0, 0, 0, 0, 0.6 }, { 1, 0, 0, 0, 0, 0, 0, 0 },
        { 1, 1, 0, 0, 0, 0, 0, 0 }, { 0, 1, 0, 0, 0, 0, 0, 0.6 } }, "fan", "static")
      H.nameWash = mesh
    end
    G2.setColor(1, 1, 1, 1)
    G2.draw(mesh, x0, y0 + 1 * kh, 0, 120 * kh, nh + 3 * kh)
    say(G2, name, x0 + 4 * kh, y0 + 2 * kh, nh, "left", WHITE3)
    G2.pop()
    -- the clock, top right: a dark teal pill, a clock face, the minutes and seconds
    G2.push()
    G2.translate(slide, 0)
    local pw, ph = 50 * kh, 15 * kh
    local px, py = x1 - pw - 4 * kh, y0 + 9 * kh
    c(G2, TEAL_LO, 0.92); G2.rectangle("fill", px, py, pw, ph, ph / 2, ph / 2)
    c(G2, TEAL, 0.9); G2.setLineWidth(1.2 * kh); G2.rectangle("line", px, py, pw, ph, ph / 2, ph / 2)
    local cx, cy = px + ph / 2 + 1.5 * kh, py + ph / 2
    c(G2, TEAL_HI); G2.circle("line", cx, cy, ph * 0.32, 20)
    G2.line(cx, cy, cx, cy - ph * 0.22); G2.line(cx, cy, cx + ph * 0.18, cy)
    local low = sim.remaining <= 10 and sim.phase == "play"
    say(G2, clockText(sim.remaining), x1 - 8 * kh, py + 1.5 * kh, ph - 3 * kh, "right",
      low and LOW_RED or TEAL_HI)
    -- the changeover's +30, rising into the clock (BONUS_S, ~0.4 s)
    if sim.phase == "between" and sim.between then
      local B, bt = Rules.N.BETWEEN, sim.between.t
      local u = (bt - (B.BONUS_S - 0.3)) / 0.7
      if u >= 0 and u <= 1 then
        local secs = (s.course and s.course.extraBotSecs) or Rules.N.CLOCK.EXTRA_BOT_S
        say(G2, "+" .. tostring(secs), px + pw * 0.3, py + ph + 4 * kh - 12 * kh * u, ph - 2 * kh, "center",
          TEAL_HI, nil, math.min(1, (1 - u) * 3))
      end
    end
    G2.pop()
    -- the score, bottom right: SCORE:, the points over the target, the trainee's name
    G2.push()
    G2.translate(slide, 0)
    local pop = H.scoreAt and math.max(0, 1 - (H.clock - H.scoreAt) / 0.25) or 0
    local dh = 16 * kh * (1 + 0.25 * pop)
    local target = sim.bot and sim.bot.target or 0
    local txt = ("%d/ %d"):format(math.floor(sim.score or 0), target)
    say(G2, T.gameLine and T.gameLine("training_coach", 111) or "SCORE:", x1 - 6 * kh, y1 - 37 * kh, 6 * kh, "right", TEAL_HI, INK_TEAL)
    say(G2, txt, x1 - 6 * kh, y1 - 29 * kh - (dh - 16 * kh) / 2, dh, "right", WHITE3, INK_SCORE)
    say(G2, s.name or "", x1 - 6 * kh, y1 - 11 * kh, 6 * kh, "right", WHITE3, BLACK3)
    G2.pop()
    -- the energy meter, bottom left: as the game's (its fill scales from the middle out with the
    -- meter), a red-orange core in a yellow rim; the two pointed rings turn round it, one each
    -- way, while it covers a shot
    G2.push()
    G2.translate(-slide, 0)
    local gx, gy, gr = x0 + 18 * kh, y1 - 18 * kh, 10 * kh
    local guts = math.max(0, math.min(1, sim.guts or 0))
    G2.setColor(0, 0, 0, 0.45); G2.circle("fill", gx, gy, gr + 2 * kh, 32)
    if guts > 0 then
      local r = gr * guts
      G2.setColor(1, 0.82, 0.22, 1); G2.circle("fill", gx, gy, r, 32)
      G2.setColor(0.98, 0.45, 0.1, 1); G2.circle("fill", gx, gy, r * 0.78, 32)
      G2.setColor(0.86, 0.12, 0.08, 1); G2.circle("fill", gx, gy, r * 0.45, 24)
    end
    if guts >= 1 then
      local p = 0.5 + 0.5 * math.sin(H.clock * 10)
      G2.setColor(1, 0.85, 0.3, 0.25 + 0.25 * p); G2.circle("fill", gx, gy, gr * (1.05 + 0.12 * p), 32)
    end
    c(G2, TEAL_HI); G2.setLineWidth(1.5 * kh); G2.circle("line", gx, gy, gr + 1 * kh, 32)
    if H.ready then
      local pop = math.min(1, (H.clock - (H.readyAt or H.clock)) / 0.2)
      local turn = H.clock * 2 * math.pi / RING_TURN_S
      G2.setLineWidth(1.3 * kh)
      pointedRing(G2, gx, gy, gr * (1.75 - 0.25 * pop), turn, 0.85 * pop, kh)
      pointedRing(G2, gx, gy, gr * (1.45 - 0.2 * pop), -turn, 0.95 * pop, kh)
    end
    G2.pop()
  end

  -- a ring with three points outward (the game's just_charge01 rings), turned by `rot`
  function pointedRing(G2, x, y, r, rot, a, kh)
    G2.setColor(0.55, 1, 0.95, 0.75 * a)
    G2.circle("line", x, y, r, 40)
    G2.setColor(0.75, 1, 0.97, a)
    for i = 0, 2 do
      local ang = rot + i * 2 * math.pi / 3
      local cx, cy = math.cos(ang), math.sin(ang)
      local px, py = -cy, cx
      local w, l = 2.2 * kh, 4.2 * kh
      G2.polygon("fill", x + cx * (r + l), y + cy * (r + l),
        x + cx * r + px * w, y + cy * r + py * w, x + cx * r - px * w, y + cy * r - py * w)
    end
  end

  local function reticle(G2, sim)
    local aim = sim.player.aim
    local rx, ry, rz = T.toScreen(Sim.project(aim.x, aim.y, 1))
    local k = rz or 1
    local h = 9 * k
    G2.setColor(1, 1, 1, 0.95)
    G2.setLineWidth(1.4)
    for _, sgn in ipairs(CORNERS) do
      local cx, cy = rx + sgn[1] * h, ry + sgn[2] * h
      G2.line(cx, cy - sgn[2] * 4 * k, cx, cy, cx - sgn[1] * 4 * k, cy)
    end
    c(G2, TEAL_HI); G2.circle("line", rx, ry, 5.5 * k, 24)
    G2.line(rx - 3 * k, ry, rx + 3 * k, ry); G2.line(rx, ry - 3 * k, rx, ry + 3 * k)
    -- Charged: a yellow ring round the crosshair and a second crosshair closing in on it over
    -- the 16 frames to the full charge, which turns it red and glowing
    local stage = H.charge or 0
    if stage == 1 then
      local rise = sim:chargeRise() or 0
      G2.setColor(1, 0.86, 0.2, 0.95)
      G2.setLineWidth(2)
      G2.circle("line", rx, ry, 8 * k, 28)
      local far = h * (1 + 3 * (1 - rise))
      G2.setColor(1, 0.9, 0.25, 0.4 + 0.6 * rise)
      G2.setLineWidth(1.6)
      for _, sgn in ipairs(CORNERS) do
        local cx, cy = rx + sgn[1] * far, ry + sgn[2] * far
        G2.line(cx, cy - sgn[2] * 5 * k, cx, cy, cx - sgn[1] * 5 * k, cy)
      end
    elseif stage >= 2 then
      local p = 0.5 + 0.5 * math.sin(H.clock * 14)
      G2.setColor(1, 0.15, 0.1, 0.25 + 0.2 * p)
      G2.circle("fill", rx, ry, (10 + 2 * p) * k, 28)
      G2.setColor(1, 0.2, 0.12, 1)
      G2.setLineWidth(2.2)
      G2.circle("line", rx, ry, 8 * k, 28)
      for _, sgn in ipairs(CORNERS) do
        local cx, cy = rx + sgn[1] * h, ry + sgn[2] * h
        G2.line(cx, cy - sgn[2] * 5 * k, cx, cy, cx - sgn[1] * 5 * k, cy)
      end
    end
    if H.fullAt and H.clock - H.fullAt < 0.3 then
      local a = 1 - (H.clock - H.fullAt) / 0.3
      G2.setColor(1, 0.9, 0.4, a)
      G2.circle("line", rx, ry, (8 + 10 * (1 - a)) * k, 28)
    end
  end

  -- big title words (Start, Success!): outlined teal letters with a glow
  local function bigWord(G2, word, cx, cy, hgt, a)
    for i = 3, 1, -1 do
      say(G2, word, cx, cy - hgt / 2, hgt, "center", GLOW, nil, a * 0.12 * i)
    end
    say(G2, word, cx, cy - hgt / 2, hgt, "center", WORD, INK_WORD, a)
  end

  local function engineDraw(G2, sim, s)
    local e = T.topExtent or { x = 0, y = 0, w = 240, h = 160 }
    local kh = math.max(1, math.min(H.EDGE_MAX, e.w / 240, e.h / 160))
    local I, o = H.INTRO, s.outro
    local t = sim.phase == "countdown" and sim.t or H.INTRO_S + 1
    frameBands(G2, e, kh)
    -- the title: teal lines open across the middle, the course's name on them, then away
    if t < 3.0 then
      local inA = smooth01(0, 0.3, t) * (1 - smooth01(2.6, 3.0, t))
      local spread = smooth01(0, 0.3, t)
      G2.setColor(0, 0.12, 0.12, 0.55 * inA); G2.rectangle("fill", e.x, 88, e.w, 54)
      c(G2, TEAL, 0.9 * inA)
      for i, y in ipairs({ 90, 95, 104, 128, 140 }) do
        local hw = e.w / 2 * spread
        G2.rectangle("fill", 120 - hw, y, hw * 2, i % 2 == 0 and 1.6 or 1)
      end
      say(G2, T.courseName and s.course and T.courseName(s.course.id) or "", 120, 111, 10, "center", TEAL_HI, nil, inA)
    end
    -- the name bands: the balloon's, then the trainee's
    local function nameBand(text, a0, a1)
      if t < a0 or t > a1 then return end
      local inK = smooth01(a0, a0 + 0.15, t)
      local a = 1 - smooth01(a1 - 0.2, a1, t)
      local x = 120 + (1 - inK) * 160
      local y = math.min(e.y + e.h - 30, 128)
      G2.setColor(0, 0.1, 0.1, 0.6 * a); G2.rectangle("fill", e.x, y, e.w, 16)
      c(G2, TEAL, a); G2.rectangle("fill", e.x, y, e.w, 1); G2.rectangle("fill", e.x, y + 15, e.w, 1)
      say(G2, text, x, y + 2, 11, "center", TEAL_HI, INK_TEAL, a)
    end
    nameBand(balloonName(sim), I.BOT_NAME[1], I.BOT_NAME[2])
    -- the next balloon's name, in the changeover
    if sim.phase == "between" and sim.between and sim.between.swapped then
      local B, bt = Rules.N.BETWEEN, sim.between.t
      local save = t
      t = bt
      nameBand(balloonName(sim), B.NAME[1], B.NAME[2])
      t = save
    end
    nameBand(s.name or "", I.PLAYER_NAME[1], I.PLAYER_NAME[2])
    -- the HUD: in at HUD_IN, out with the end
    local inK = smooth01(I.HUD_IN, I.HUD_IN + 0.3, t)
    if o then inK = inK * (1 - smooth01(H.OUTRO.HUD_OUT, H.OUTRO.HUD_OUT + 0.3, o.t)) end
    brackets(G2, 1)
    if inK > 0 then hudParts(G2, sim, s, e, kh, inK) end
    if sim.phase == "play" and not o then reticle(G2, sim) end
    -- the points over a hit, rising and fading
    for _, p in ipairs(H.popups) do
      local k = p.t / POPUP_S
      local a = k < 0.7 and 1 or (1 - (k - 0.7) / 0.3)
      say(G2, "+" .. tostring(p.points), p.x, p.y - 10 - 14 * k - 6, 12, "center", WHITE3, INK_POP, a)
    end
    -- a hit taken: the edges flash red
    if H.damageAt and H.clock - H.damageAt < 0.35 then
      local a = 1 - (H.clock - H.damageAt) / 0.35
      G2.setColor(1, 0.1, 0.1, 0.35 * a)
      G2.setLineWidth(10)
      G2.rectangle("line", e.x + 5, e.y + 5, e.w - 10, e.h - 10)
    end
    -- Start
    if sim.phase == "countdown" and t >= I.START then
      local f = (t - I.START) * FPS
      local pop = 1 + 0.6 * (1 - smooth01(0, 6, f))
      local a = smooth01(0, 3, f) * (1 - smooth01(30, 41, f))
      bigWord(G2, "Start", 120, 80, 30 * pop, a)
    end
    -- the end's word: Success! with its light, or the game-over word
    if o and o.t >= H.OUTRO.BANNER then
      local f = (o.t - H.OUTRO.BANNER) * FPS
      local a = smooth01(0, 6, f)
      local clear = o.outcome and o.outcome.clear
      if clear then
        -- a curtain of light down the screen
        G2.setColor(0, 0.2, 0.2, 0.35 * a)
        G2.rectangle("fill", e.x, e.y, e.w, e.h)
        for i = 0, 15 do
          local x = e.x + (i + 0.5) * e.w / 16
          G2.setColor(0.3, 0.95, 0.85, 0.22 * a * (0.55 + 0.45 * math.sin(f * 0.3 + i * 1.7)))
          G2.rectangle("fill", x - 3.5, e.y, 7, e.h)
        end
      end
      local pop = 1 + 0.4 * (1 - smooth01(0, 8, f))
      local word = clear and "Success!" or "Try Again..."
      local hgt = math.min(48, e.w * 0.95 / math.max(1, #word * 0.55)) * pop
      bigWord(G2, word, 120, e.y + e.h * 0.62, hgt, a)
    end
  end

  function H.draw(G2, sim, s)
    if H.engine and sim == H.sim then
      engineDraw(G2, sim, s)
      return true
    end
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
