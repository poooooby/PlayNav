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

  -- PUMPS: the balloon lies flat on the grass and is blown up in three pumps (each swells it
  -- sideways, then it settles a little); RISE: full, it floats up to its place
  H.INTRO = { PUMPS = { 2.7, 4.9 }, RISE = { 4.9, 5.7 }, BOT_NAME = { 7.1, 8.1 }, PLAYER_NAME = { 8.5, 9.9 },
    HUD_IN = 10.1, START = 10.5 }
  H.INTRO_S = H.INTRO.START + 41 / FPS
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
    local x, y = Sim.project(bx, cyW + by, 1)
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
    local rx, ry = Sim.project(aim.x, aim.y, 1)
    placeAt(P, "13", rx, ry)
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
      -- three pumps: each from one size to the next with a sideways swell, then a settle
      local LEVELS = { 0.18, 0.5, 0.78, 1.0 }
      local pumps = #LEVELS - 1
      local span = (I.PUMPS[2] - I.PUMPS[1]) / pumps
      local u = (t - I.PUMPS[1]) / span
      local i = math.max(0, math.min(pumps - 1, math.floor(u)))
      local f = math.max(0, math.min(1, u - i))
      local from, to = LEVELS[i + 1], LEVELS[i + 2]
      local blow = f < 0.6 and smooth(0, 0.6, f) or 1
      local settle = f >= 0.6 and math.sin((f - 0.6) / 0.4 * math.pi) * 0.04 or 0
      local size = from + (to - from) * blow - settle
      if t >= I.PUMPS[2] then size = 1 end
      local progress = math.max(0, math.min(1, (t - I.PUMPS[1]) / (I.PUMPS[2] - I.PUMPS[1])))
      local swell = (f < 0.6 and t < I.PUMPS[2]) and math.sin(f / 0.6 * math.pi) * 0.12 or 0
      local rise = smooth(I.RISE[1], I.RISE[2], t)
      -- flat at first, rounding out as it fills; a little bounce as it lifts off
      local flat = 0.35 + 0.65 * progress
      pose.bot = { ground = true, rise = rise, sx = size * (1 + swell), sy = size * flat * (1 - swell * 0.5)
        + (rise > 0 and rise < 1 and math.sin(rise * math.pi) * 0.05 or 0),
        alpha = t < I.PUMPS[1] and 0 or 1 }
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
        -- (the balloon hovers high: keep its way out inside the sky)
        local endX, endY = 60 + 40, -25 - 20
        -- the last goal bursts with the final hit: none ride along; the shadow fades as it rises
        pose.bot = { dx = wob + zig + fly * 60 + away * 40, dy = -fly * 25 - away * 20, scale = scale,
          alpha = t < O.AWAY[2] and 1 or 0, puffs = t >= O.FLY[1] and t < O.AWAY[2] and fly or nil, puffScale = scale,
          noGoals = true, shadow = 1 - fly }
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

  function H.draw(G2, sim, s)
    local P = H.P
    if not P or sim ~= H.sim then return false end
    G2.push()
    G2.scale(S, S)
    P:draw(G2)
    G2.pop()
    return true
  end

  return H
end
