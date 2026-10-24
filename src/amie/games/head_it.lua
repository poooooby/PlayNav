-- HEAD IT, played from the game's own screens (a/0/1/7: bg_down on the touch screen, bg_up_rear
-- and bg_up_front on the top screen, effect's bursts, reward_heading's smoke and medallions)
-- under the game's rules (data/head_it_rules.lua, read from DllHeading.cro).
--
-- Balls of yarn come down from the top of the top screen in a straight line over the Pokemon
-- they are meant for (left, middle or right on the top screen tells which), onto the touch
-- screen; a tap on that Pokemon while the ball is at the star over its head heads it back up
-- (just: +3 and straight up; early or late: +1 and drifting). A new ball comes every
-- `interval` frames whatever happens to the last, so several can be in the air; good hits
-- shorten the interval, a miss restores it. One Pokemon at first (the middle), a second on the
-- left after 20 s, a third on the right after 40 s; the yarn is pink, yellow, then cyan. The
-- rainbow on the top screen grows with the combo (thin, from 3 wider, FEVER widest: points
-- doubled) and fades on a miss. When the clock runs out the balls still up are played out, the
-- side Pokemon leave and a giant ball drops on the middle one (the Big Yarn Bonus: 10, or 50
-- at the star). RESULTS on the top screen (Heading Points, Last Combo Record, Big Yarn Bonus,
-- TOTAL), smoke and Poke Puff medallions below, Play Again / Quit. Unlimited plays the game's
-- steps (one to three Pokemon and back, faster as it goes) until three balls are missed.
--
-- Positions: the rules' units (the touch screen's layout units, y up about its middle; the top
-- screen 240..480 above). The sim ticks at the game's 30 frames a second.

return function(mod, Pointer, G, Games, Rules, host)

  -- pixel art (GBA sprites) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "game_head", title = "HEAD IT", live = true }

  function app:wantsSurface()
    local s = G.session
    return s ~= nil and s.mode == "game" and s.game and s.game.id == "head" or false
  end

  local HR = nil
  do
    local ok, src = pcall(mod.read, mod, "data/head_it_rules.lua")
    if ok and src then
      local fn = load(src, "=head_it_rules")
      if fn then
        local ok2, t = pcall(fn)
        if ok2 then HR = t end
      end
    end
  end
  app.rules = HR
  local FPS = HR and HR.FPS or 30
  local TICK = 1 / FPS

  local L = 256 / 320
  local BLEED = 14
  -- the screen's shape: the touch screen is the game's 320x240 anchored to the bottom of a
  -- taller screen (Kanto Gear's, D more), the score and the windows kept at the top
  local LH, D = 240, 0
  local function bleed() return app.bleed or BLEED end
  local function setShape(h)
    local lh = math.max(240, ((h or 178) + bleed()) / L)
    if lh == LH then return end
    LH, D = lh, lh - 240
  end
  app.setShape = setShape

  local MON_FOOT, MON_H, MON_W = 236, 92, 124  -- where the feet go at full height, the height, the widest
  local STAR_Y = 160                          -- the star over the heads (bg_down 1p / 1r / 1t)
  local HEAD_TOP = MON_FOOT - MON_H           -- every sprite's top: the star lands on its head
  local HEAD_FRAMES = 8                       -- a heading's bob; the column takes no tap meanwhile
  local ENTER_S, LEAVE_S = 0.5, 0.4
  local SCORE_AT = { 30, 25 }                 -- the score bubble (bg_down 4)
  local COLOR_OF_STAGE = { "ball00", "ball02", "ball01" }  -- pink, yellow, cyan
  local PURPLE = "ball03"
  -- the just hit's twinkles, where they end (effect hit00_just at frame 30; y up)
  local TWINKLES = { { 75, 20.5 }, { -66.4, 12.4 }, { -40.1, -16.2 }, { 35.8, -19.6 }, { -58.7, 6.7 }, { 61.1, -3.3 } }
  local BUTTONS = { again = { 160, 180, 126, 26 }, quit = { 160, 210, 126, 26 } }

  local st = nil
  local seenDemo = false
  local players = {}

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local OPEN = {
    down = { "head_down", "bg_down.bclyt" }, rear = { "head_rear", "bg_up_rear.bclyt" },
    -- (RESULTS' ribbon in English is Berry Picker's language pack's; Head It's own is Japanese)
    front = { "head_front", "bg_up_front.bclyt", { "berry_lang", "head_front" } },
    reward = { "head_reward", "reward_heading.bclyt" },
  }
  local function screen(name)
    local p = players[name]
    if p == nil then
      local S, o = mod.lyt, OPEN[name]
      p = S and S.open(o[1], o[2], o[3] or { o[1] }) or false
      players[name] = p
    end
    return p or nil
  end

  local function roll(a, b)
    local g = st and st.rng
    if g then return g:random(a, b) end
    return math.random(a, b)
  end
  local function rand()
    local g = st and st.rng
    if g then return g:random() end
    return math.random()
  end

  local function setPhase(p) st.phase, st.pt = p, 0 end

  -- ------- the Pokemon (slot 1 middle, 2 left, 3 right)

  local boxes = setmetatable({}, { __mode = "k" })
  -- a sprite's opaque extent, read back once (never during a draw: it uses a canvas)
  local function opaqueBox(img)
    if not img then return nil end
    local b = boxes[img]
    if b then return b end
    local w, h = img:getDimensions()
    b = { x0 = 0, y0 = 0, x1 = w, y1 = h }
    pcall(function()
      -- one canvas pixel per sprite unit (the default density is the screen's, 2-3 on a
      -- high-DPI device, and the scan would read only the top-left corner)
      local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.origin()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.setCanvas()
      love.graphics.pop()
      local data = c:newImageData()
      local x0, y0, x1, y1 = w, h, -1, -1
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local _, _, _, a = data:getPixel(x, y)
          if a > 0.1 then
            if x < x0 then x0 = x end
            if x > x1 then x1 = x end
            if y < y0 then y0 = y end
            if y > y1 then y1 = y end
          end
        end
      end
      if x1 >= x0 then b.x0, b.y0, b.x1, b.y1 = x0, y0, x1 + 1, y1 + 1 end
    end)
    boxes[img] = b
    return b
  end

  local function slotX(i) return HR.SLOT_X[i] end

  local function showMon(i)
    local m = st.mons[i]
    if m.shown then return end
    m.shown, m.leaving, m.t = true, false, 0
    m.burst = 0
  end
  local function hideMon(i)
    local m = st.mons[i]
    if not m.shown or m.leaving then return end
    m.leaving, m.t = true, 0
  end
  local function monUp(i)
    local m = st.mons[i]
    return m.shown and not m.leaving and m.t >= ENTER_S
  end
  -- a ball still falling on Pokemon i (one it can head)
  local function fallingOn(i)
    for _, b in ipairs(st.balls) do
      if b.slot == i and b.state == "fall" and not b.missed and not b.gone then return true end
    end
    return false
  end

  -- ------- the HUD's words

  local function banner(text, color, hold)
    if text then
      st.banner = { text = text, color = color or { 0.1, 0.08, 0.07 }, t = 0, hold = hold, closing = false }
    elseif st.banner then
      st.banner.closing, st.banner.ct = true, 0
    end
  end

  -- ------- the game's numbers

  local function stageRow()
    if st.diff == "unlimited" then
      local r = st.urec
      -- { start, per good, per just, minimum, at fever, frames, fever combo }
      return { r[2], r[3], r[4], r[5], r[5], r[6], HR.UNLIMITED_FEVER }
    end
    return HR.STAGES[st.diff][st.stage + 1]
  end

  local function pattern()
    if st.diff == "unlimited" then
      local idx = HR.PATTERN_ORDER[st.upat] or 0
      return HR.PATTERNS.unlimited[idx + 1]
    end
    return HR.PATTERNS[st.diff]
  end

  local function monsNow() return st.stage + 1 end

  -- ------- balls

  -- how far a ball with this flight falls in n frames
  local function fallIn(grp, n)
    local v, y = grp[1], 0
    for _ = 1, n do v = v + grp[2]; y = y + v end
    return y
  end

  local function launch()
    local pat = pattern()
    local n = monsNow()
    local slot = 1
    if n == 2 then slot = (roll(0, 1) == 0) and 2 or 1
    elseif n >= 3 then slot = ({ 2, 1, 3 })[roll(1, 3)] end
    local kind = 0
    if not st.lastCrush then
      local r = roll(0, 99)
      if r < pat.crush then kind = 1 elseif r < pat.crush + pat.purple then kind = 2 end
    end
    local grp
    if kind == 1 then
      grp = pat.groups[3 + st.stage + 1]
      -- kept only if it falls far enough within one interval
      if fallIn(grp, math.floor(st.interval)) <= HR.CRUSH_MIN_FALL then kind, grp = 0, nil end
    end
    if kind == 2 then grp = pat.groups[7] end
    if kind == 0 then grp = pat.groups[st.stage + 1] end
    st.lastCrush = kind == 1
    local look = kind == 2 and PURPLE or COLOR_OF_STAGE[st.stage + 1]
    st.balls[#st.balls + 1] = { slot = slot, x = slotX(slot), y = HR.SPAWN_Y, v = grp[1], g = grp[2], grp = grp,
      kind = kind, look = look, state = "fall", f = 0 }
  end

  local function dropGiant()
    local grp = pattern().groups[8]
    st.giant = { slot = 1, x = 0, y = HR.GIANT_Y, v = grp[1], g = grp[2], grp = grp, kind = 3, look = "giant",
      state = "fall", f = 0, giant = true }
    st.balls[#st.balls + 1] = st.giant
  end

  -- the ball's test point, screen y down from the touch screen's top
  local function testY(b)
    if b.giant then return 120 - b.y + HR.GIANT_H * HR.GIANT_DROP end
    return 120 - b.y + HR.BALL_H * HR.TEST_DROP
  end
  local function grade(b)
    local y, W = testY(b), HR.WINDOW
    if y >= W.just[1] and y < W.just[2] then return "just" end
    if (y >= W.goodHigh[1] and y < W.goodHigh[2]) or (y >= W.goodLow[1] and y < W.goodLow[2]) then return "good" end
    return nil
  end

  -- ------- effects (drawn in code from the game's textures; screen = touch-screen layout units)

  local fx = {}
  local function effect(kind, x, y, extra)
    local e = extra or {}
    e.kind, e.x, e.y, e.t = kind, x, y, 0
    fx[#fx + 1] = e
  end

  local function addPoints(n)
    st.score = math.min(HR.CAP, st.score + n)
  end

  local resultTotal   -- (below: the results card's running total and step)

  local function setFever(on)
    if on == st.fever then return end
    st.fever = on
    if on then G.se("fever", "SE_SUCCESS") end
  end

  local function hitBall(b, how)
    local row = stageRow()
    b.state, b.f, b.how = "squash", 0, how
    local grp = b.grp
    if how == "just" then b.v, b.decel = grp[5], grp[6] else b.v, b.decel, b.dir = grp[3], grp[4], (roll(0, 1) == 0) and -1 or 1 end
    local headY = 120 - STAR_Y
    if b.giant then
      st.bigBonus = HR.BIG_BONUS[how] or 0
      effect(how == "just" and "just" or "good", b.x, headY, { giant = true })
      if mod.haptics then mod.haptics.pattern("big") end
      G.se(how == "just" and "giant_just" or "giant_good", how == "just" and "SE_SUCCESS" or "SE_PIN")
      return
    end
    local pts = (how == "just" and HR.POINTS.just or HR.POINTS.good) * (st.fever and HR.POINTS.fever or 1)
    st.combo = math.min(HR.CAP, st.combo + 1)
    st.maxCombo = math.max(st.maxCombo, st.combo)
    local c = st.combo
    for _, m in ipairs(HR.MILESTONE) do
      if c % m.every == 0 then pts = pts + m.points; break end
    end
    addPoints(pts)
    st.hits = st.hits + 1
    if c >= HR.COMBO_SHOW then st.comboShow = { n = c, t = 0 } end
    -- a combo begins (its first popup, 3 hits): the game's combo sound (the 10s have their own below)
    if c == 3 then G.se("combo3") end
    -- the interval: shorter with every hit, between the stage's minimum and its start
    st.interval = st.interval + (how == "just" and row[3] or row[2])
    st.interval = math.max(row[4], math.min(row[1], st.interval))
    if not st.fever and c >= row[7] then
      setFever(true)
      st.interval = row[5]
    end
    st.rainbow = st.fever and 3 or (c >= HR.COMBO_SHOW and 2 or 1)
    st.rainbowT = 0
    effect(how == "just" and "just" or "good", b.x, headY)
    -- the points fly to the score bubble as a star
    effect("star", b.x, headY, { pts = pts })
    if mod.haptics then mod.haptics.pulse(how == "just" and "strong" or "medium") end
    G.se((how == "just" and "head_just" or "head_good") .. (st.fever and "_fever" or ""), how == "just" and "SE_PIN" or "SE_SELECT")
    if c % 10 == 0 then
      local mon = st.participants[b.slot] and st.participants[b.slot].mon
      if mon then host.playCry(mon) end
      -- a combo milestone: bigger at 50 and 100
      if mod.haptics then
        mod.haptics.pattern(c % 100 == 0 and "big" or (c % 50 == 0 and "success" or "happy"))
      end
      G.se(c % 100 == 0 and "combo100" or (c % 50 == 0 and "combo50" or "combo10"))
    end
  end

  local function missBall(b)
    b.missed = true
    if b.giant then
      st.bigBonus = 0
      effect("miss", b.x, 0)
      G.se("giant_miss", "SE_NOT_EFFECTIVE")
      return
    end
    st.combo = 0
    st.misses = st.misses + 1
    st.interval = stageRow()[1]
    setFever(false)
    if st.rainbow then st.rainbowOut, st.lastBand = 0, st.rainbow end
    st.rainbow = nil
    effect("miss", b.x, 0)
    G.se("head_miss", "SE_NOT_EFFECTIVE")
  end

  local function stepBall(b)
    b.f = b.f + 1
    if b.state == "fall" then
      b.v = b.v + b.g
      b.y = b.y - b.v
      if not b.missed and not b.demo and testY(b) >= HR.WINDOW.miss[1] then missBall(b) end
      if b.y < HR.OUT_BOTTOM then
        b.gone = true
        if b.missed and st.lives and not b.giant then
          st.lives = st.lives - 1
          if st.lives <= 0 then st.outOfLives = true end
        end
      end
    elseif b.state == "squash" then
      if b.f >= 2 then b.state, b.f = "rise", 0 end
    elseif b.state == "rise" then
      b.y = b.y + b.v
      b.v = math.max(HR.RISE_FLOOR, b.v - b.decel)
      if b.dir then b.x = b.x + b.dir * HR.DRIFT end
      -- (gone once wholly past the top screen's edge)
      if b.y > HR.OUT_TOP + (b.giant and HR.GIANT_H or HR.BALL_H) / 2 then b.gone = true end
    end
  end

  local function liveBalls()
    for _, b in ipairs(st.balls) do
      if not b.gone then return true end
    end
    return false
  end

  -- ------- the stages

  local function enterStage(stage)
    local before = st.stage
    st.stage = stage
    st.stageF = 0
    st.interval = stageRow()[1]
    st.counter = -1
    st.toLeave = st.toLeave or {}
    for i = 1, 3 do
      if i <= stage + 1 then
        st.toLeave[i] = nil
        if i > before + 1 or not st.mons[i].shown then
          if i > 1 then effect("appear", slotX(i), 120 - MON_FOOT) end
          showMon(i)
        end
      elseif st.mons[i].shown and not st.mons[i].leaving then
        -- (a side with yarn still coming down on it stays to head it, then goes)
        st.toLeave[i] = true
      end
    end
    if stage > before then st.entering = ENTER_S * FPS end
  end

  local function unlimitedStep(pos)
    st.upos = pos
    local rec = HR.UNLIMITED_ORDER[pos + 1]
    st.urec = HR.UNLIMITED_STEPS[rec + 1]
    enterStage(st.urec[1] - 1)
  end

  local function nextUnlimited()
    local wasThree = st.urec[1] == 3
    local pos = st.upos + 1
    if pos >= #HR.UNLIMITED_ORDER then pos = HR.UNLIMITED_LOOP_TO end
    if wasThree then
      st.upat = st.upat + 1
      if st.upat > #HR.PATTERN_ORDER then st.upat = HR.PATTERN_LOOP_TO + 1 end
    end
    unlimitedStep(pos)
  end

  -- ------- the end

  local function finish()
    if st.result then return end
    st.final = st.score + st.maxCombo + (st.bigBonus or 0)
    st.result = G.endGame(st.final, false, true)
  end

  local PUFF_TIER = { basic = 1, frosted = 2, fancy = 3, deluxe = 4, supreme = 5 }
  local function layMedals()
    local R = screen("reward")
    if not R then return end
    local panes = {}
    for _, c in ipairs(R.L.root.children) do
      if c.kind == "pic" and c.children[1] then panes[#panes + 1] = c end
    end
    for _, c in ipairs(panes) do R:set(c.name, "visible", false) end
    local puffs = (st.result and st.result.puffs) or {}
    local n = math.min(#puffs, 12)
    local perRow = math.min(6, n)
    for j = 1, n do
      local pane = panes[j]
      local child = pane and pane.children[1]
      if pane and child then
        local row = math.floor((j - 1) / 6)
        local col = (j - 1) % 6
        local inRow = (row == 0) and perRow or (n - 6)
        local x = 160 + (col - (inRow - 1) / 2) * 50
        local y = 88 + row * 56
        R:set(pane.name, "visible", true)
        R:set(child.name, "visible", true)
        R:set(pane.name, "tx", x - 160)
        R:set(pane.name, "ty", 120 - y)
        local tier = PUFF_TIER[Rules.puffTier and Rules.puffTier(puffs[j]) or "basic"] or 1
        R:setImage(pane.name, R:image(("wappen_%02d.bclim"):format(tier)))
        local img = art(puffs[j])
        if img then R:setImage(child.name, img) end
        -- each bobs and rocks as Berry Picker's do (the game's sweets clip, made on pane 0)
        R:play("sweets", { as = pane.name, sample = "0", loop = true, from = (j * 7) % 40 })
      end
    end
  end

  -- ------- start / quit

  function app:start(game)
    if not HR then
      mod.log:warn("head it: data/head_it_rules.lua did not load; reinstall the mod")
      G.endGame(nil, true)
      return
    end
    st = { diff = game.diff, participants = game.participants, phase = "intro", pt = 0, t = 0, acc = 0,
      score = 0, combo = 0, maxCombo = 0, hits = 0, misses = 0, fever = false, bigBonus = 0,
      timer = HR.TIME, lives = (game.diff == "unlimited") and HR.LIVES or nil,
      balls = {}, stage = 0, stageF = 0, interval = 90, counter = -1, mons = {}, upat = 1,
      shownScore = 0, demo = not seenDemo }
    seenDemo = true
    fx = {}
    do
      local ok, g = pcall(function()
        local t = love.timer.getTime()
        return love.math.newRandomGenerator(os.time() + math.floor((t - math.floor(t)) * 1e6))
      end)
      st.rng = ok and g or nil
    end
    for i = 1, 3 do
      local p = game.participants and game.participants[i]
      local mon = p and p.mon
      st.mons[i] = { mon = mon, pic = mon and host.frontPic and host.frontPic(mon) or nil,
        shown = false, leaving = false, t = 0, head = 0 }
    end
    st.best = Games.highScore and Games.highScore("head", game.diff) or 0
    st.art = true
    for name in pairs(OPEN) do if not screen(name) then st.art = false end end
    if st.art then
      for name in pairs(OPEN) do
        local P = screen(name)
        P.active, P.over, P.texts, P.images = {}, {}, {}, {}
      end
      local Dn, Rr, F, Rw = screen("down"), screen("rear"), screen("front"), screen("reward")
      -- the touch screen: the score bubble only; the rest is drawn in code
      for _, n in ipairs({ "v", "y", "z", "18", "1b", "a", "11", "1e", "9", "1n", "1o", "1y", "25", "2c", "2j", "5" }) do
        Dn:set(n, "visible", false)
      end
      Dn:set("4", "visible", false)
      -- the top screen: the sky and the rainbow band (shown by the combo)
      for _, n in ipairs({ "0", "9", "11" }) do Rr:set(n, "visible", false) end
      for _, n in ipairs({ "v", "x", "z" }) do Rr:set(n, "visible", false) end
      -- HIGH SCORE and the clock (Unlimited: Chances), the RESULTS window waiting
      F:set("6", "visible", false)
      F:set("3a", "visible", false)
      F:set("5j", "visible", false)
      F:set("3p", "visible", false)
      F:set("2", "visible", false)
      F:setText("3f", Games.line("head", "highScore", nil, "HIGH SCORE:"), { align = "left", valign = "center" })
      F:setText("3h", tostring(st.best or 0), { align = "left", valign = "center" })
      Rw:set("q", "visible", false)
      for _, c in ipairs(Rw.L.root.children) do
        if c.kind == "pic" then Rw:set(c.name, "visible", false) end
      end
    end
    if st.diff == "unlimited" then unlimitedStep(0) end
    showMon(1)
    game.hud = ("HEAD IT  %s"):format(Games.DIFF_LABEL[game.diff])
  end

  local function playing()
    return st and (st.phase == "intro" or st.phase == "demo" or st.phase == "ready" or st.phase == "play" or st.phase == "timeup"
      or st.phase == "leave" or st.phase == "giant")
  end

  function app:quit()
    if playing() then
      st = nil
      G.endGame(nil, true)
    end
  end

  -- the driver ends a run early with a chosen score (straight to the results)
  function app.forceEnd(score)
    if playing() then
      st.score = score or st.score
      st.balls, st.giant = {}, nil
      finish()
      setPhase("results")
      for i = 1, 3 do showMon(i) end
    end
  end

  -- ------- input (scene units: the game's 320x240, D lower on a taller screen)

  local function toScene(x, y) return x / L, (y + bleed()) / L - D end
  local function fromScene(x, y) return x * L, (y + D) * L - bleed() end
  local function inButton(b, x, y) return math.abs(x - b[1]) <= b[3] / 2 and math.abs(y - b[2]) <= b[4] / 2 end

  -- the column a touch is in (bg 1f / 1g / 1h), as a slot
  local function columnAt(x, y)
    if y < HR.TOUCH.top then return nil end
    for i = 1, 3 do
      if math.abs(x - (160 + slotX(i))) <= HR.TOUCH.w / 2 then return i end
    end
    return nil
  end

  -- a tap on a Pokemon: it heads, and the lowest ball falling on it is judged
  local function tapSlot(i)
    local m = st.mons[i]
    if not monUp(i) or m.head > 0 then return false end
    m.head = HEAD_FRAMES
    local best
    for _, b in ipairs(st.balls) do
      if b.slot == i and b.state == "fall" and not b.missed and not b.gone then
        if not best or b.y < best.y then best = b end
      end
    end
    local how = best and grade(best)
    if how then hitBall(best, how) end
    return how ~= nil
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (st and s and s.mode == "game") then return end
    local x, y = toScene(ev.x, ev.y)
    if st.phase == "buttons" then
      if not (ev.phase == "released" and Pointer.isTap(rec, 16, 1.0)) then return end
      if inButton(BUTTONS.again, x, y) then
        G.se("again", "SE_SELECT")
        local game = s.game
        G.startGame(game.id, game.diff)
      elseif inButton(BUTTONS.quit, x, y) then
        G.se("quit", "SE_SELECT")
        st = nil
        G.leaveGame({ toPetting = true })
      end
      return
    end
    if not st.art and st.result and st.phase ~= "giant" then
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) and st.pt > 1.0 then st = nil; G.leaveGame({ toPetting = true }) end
      return
    end
    if ev.phase ~= "pressed" then return end
    if st.phase == "play" or st.phase == "timeup" or st.phase == "giant" then
      local i = columnAt(x, y)
      if i then tapSlot(i) end
    end
  end

  -- ------- update

  local function stepMons(dt)
    for _, m in ipairs(st.mons) do
      m.t = m.t + dt
      if m.leaving and m.t >= LEAVE_S then m.shown, m.leaving = false, false end
      if m.pic and m.pic.image and not m.box then m.box = opaqueBox(m.pic.image) end
    end
  end

  local function tickPlay()
    if st.entering and st.entering > 0 then st.entering = st.entering - 1 end
    -- the sides a step sent away go once nothing is falling on them
    for i, go in pairs(st.toLeave or {}) do
      if go and not fallingOn(i) then
        st.toLeave[i] = nil
        hideMon(i)
      end
    end
    -- the clock, and the stages it moves through
    if st.diff ~= "unlimited" then
      st.timer = st.timer - 1
      st.stageF = st.stageF + 1
      local row = stageRow()
      if st.stage < 2 and st.stageF >= row[6] then enterStage(st.stage + 1) end
    else
      st.stageF = st.stageF + 1
      if st.stageF >= st.urec[6] then nextUnlimited() end
    end
    -- a ball every interval
    if not (st.entering and st.entering > 0) then
      st.counter = st.counter + 1
      if st.counter == 0 or st.counter >= st.interval then
        launch()
        st.counter = 0
      end
    end
  end

  local function tickBalls()
    for i = #st.balls, 1, -1 do
      local b = st.balls[i]
      stepBall(b)
      if b.gone then table.remove(st.balls, i) end
    end
    for _, m in ipairs(st.mons) do if m.head > 0 then m.head = m.head - 1 end end
  end

  local function tick()
    st.frame = (st.frame or 0) + 1
    local ph = st.phase
    if ph == "play" then
      tickPlay()
      tickBalls()
      if st.outOfLives then
        -- Unlimited: the third miss ends it at once, no giant
        finish()
        for i = 1, 3 do hideMon(i) end
        setPhase("results")
        return
      end
      if st.diff ~= "unlimited" and st.timer <= 0 then
        st.timer = 0
        setPhase("timeup")
        if mod.haptics then mod.haptics.pattern("big") end; G.se("head_time_up")
      end
    elseif ph == "timeup" then
      -- the balls still up are played out
      tickBalls()
      if not liveBalls() then
        st.endF = (st.endF or 0) + 1
        if st.endF >= HR.END_WAIT then
          setPhase("leave")
          hideMon(2)
          hideMon(3)
          -- the sides leave; "!!" for the giant to come
          G.se("head_leave")
          G.se("giant_alert")
        end
      end
    elseif ph == "giant" then
      tickBalls()
    elseif ph == "demo" then
      tickBalls()
    end
  end

  local function advanceAll(frames)
    for _, P in pairs(players) do if P then P:advance(frames) end end
  end

  function app:update(dt)
    local s = G.session
    if not (st and s and s.mode == "game") then app.live = false; return end
    app.live = true
    dt = math.min(dt or 0, 0.1)
    st.t = st.t + dt
    st.pt = st.pt + dt
    if st.art then advanceAll(dt * FPS) end
    stepMons(dt)
    for i = #fx, 1, -1 do
      local e = fx[i]
      e.t = e.t + dt
      if e.kind == "star" and e.t >= 0.45 and not e.landed then
        e.landed = true
        st.shownScore = st.score
        st.scorePop = 0
      end
      if e.t > (e.kind == "miss" and 1.0 or (e.kind == "appear" and 0.8 or 0.6)) then table.remove(fx, i) end
    end
    if st.scorePop then st.scorePop = st.scorePop + dt; if st.scorePop > 0.3 then st.scorePop = nil end end
    if st.comboShow then st.comboShow.t = st.comboShow.t + dt; if st.comboShow.t > 1.4 then st.comboShow = nil end end
    if st.rainbowOut then st.rainbowOut = st.rainbowOut + dt; if st.rainbowOut > 0.5 then st.rainbowOut = nil end end
    if st.rainbow then st.rainbowT = (st.rainbowT or 0) + dt end
    if st.phase == "results" or st.phase == "smoke" or st.phase == "buttons" then st.rt = (st.rt or 0) + dt end
    if st.banner then
      local b = st.banner
      b.t = b.t + dt
      if b.closing then b.ct = b.ct + dt; if b.ct > 0.33 then st.banner = nil end end
    end
    -- the fixed-rate sim: the game's frames
    st.acc = st.acc + dt
    while st.acc >= TICK do
      st.acc = st.acc - TICK
      tick()
      if not st then return end
    end
    if not st then return end
    local ph = st.phase
    local count = math.max(0, math.ceil(st.timer / FPS))
    if ph == "intro" then
      -- the middle Pokemon rises, the rule window, then (the first game a session) the demo
      if st.pt > 0.4 and not st.saidHow then
        st.saidHow = true
        local how = Games.line("head", "howTo", nil, "Tap Pokémon to knock back the balls of yarn!")
        if st.diff == "unlimited" then how = how .. "\n" .. Games.line("head", "missThree", nil, "Miss three balls of yarn, and it's game over!") end
        banner(how)
      end
      if st.pt > 3.0 and st.banner and not st.banner.closing then banner(nil) end
      if st.pt > 3.4 then
        if st.demo then
          setPhase("demo")
          st.demoBall = nil
        else
          setPhase("ready")
        end
      end
    elseif ph == "demo" then
      -- the pen comes to the Pokemon, a ball falls and the pen taps it at the star
      if not st.demoBall and st.pt > 0.6 then
        local grp = pattern().groups[1]
        st.demoBall = { slot = 1, x = 0, y = HR.SPAWN_Y, v = grp[1], g = grp[2], grp = grp, kind = 0, look = COLOR_OF_STAGE[1],
          state = "fall", f = 0, demo = true }
        st.balls[#st.balls + 1] = st.demoBall
      end
      local b = st.demoBall
      if b and b.state == "fall" and grade(b) == "just" then
        st.mons[1].head = HEAD_FRAMES
        b.state, b.f, b.v, b.decel = "squash", 0, b.grp[5], b.grp[6]
        effect("just", 0, 120 - STAR_Y)
        st.penTap = st.pt
      end
      if b and b.missed then b.gone = true end
      if st.pt > 3.4 then
        st.balls = {}
        st.mons[1].head = 0
        setPhase("ready")
      end
    elseif ph == "ready" then
      if st.pt < 0.1 and not st.saidReady then
        st.saidReady = true
        banner(Games.line("head", "ready", nil, "READY"), { 0.85, 0.05, 0.1 })
      end
      if st.pt > 1.6 and not st.saidStart then
        st.saidStart = true
        banner(Games.line("head", "start", nil, "START!"), { 0.1, 0.12, 0.85 })
        G.se("go", "SE_SUCCESS")
      end
      if st.pt > 2.4 then
        banner(nil)
        st.hud = true
        st.acc = 0
        st.counter = -1
        setPhase("play")
      end
    elseif ph == "leave" then
      if st.pt > LEAVE_S + 0.2 then
        -- the giant comes down on the middle Pokemon, "!!" over it
        setPhase("giant")
        dropGiant()
        G.se("giant_fall")
      end
    elseif ph == "giant" then
      -- headed, or missed: the bonus is settled
      local gb = st.giant
      if not gb or gb.gone or gb.missed or gb.state ~= "fall" then
        st.giantEnd = st.giantEnd or st.pt
        if st.pt - st.giantEnd > 1.2 then
          finish()
          hideMon(1)
          setPhase("results")
        end
      end
    elseif ph == "results" then
      -- the card's sounds (Wooble's capture): NUMBER as it comes, each bonus row counting
      -- (ADDSCORE, a loop) then settling (SCORE), the rank's stars (VALUE1-3 by how many)
      local _, step = resultTotal()
      if step ~= st.sndStep then
        st.sndStep = step
        if step == 0 then
          G.se("results_card")
        elseif step <= 2 then
          st.addSound, st.addAt = G.se("result_add"), st.rt or 0
        elseif step == 3 then
          local stars = st.result and st.result.stars or 0
          G.se(stars >= 5 and "rank_high" or (stars >= 3 and "rank_mid" or "rank_low"))
        end
      end
      if st.addSound and (st.rt or 0) - st.addAt > 0.55 then
        pcall(st.addSound.stop)
        st.addSound = nil
        G.se("result_row")
      end
      -- the card's rows come in on the top screen; the Pokemon come back below
      if st.pt > 0.6 and not st.monsBack then
        st.monsBack = true
        st.balls = {}
        for i = 1, 3 do st.mons[i].leaving = false; st.mons[i].shown = false; showMon(i) end
      end
      if st.pt > 3.6 then
        setPhase("smoke")
        local Rw = screen("reward")
        if Rw then Rw:set("q", "visible", true); Rw:play("anm_smoke") end
        G.se("puffs")
      end
    elseif ph == "smoke" then
      if st.pt > 0.25 and not st.revealed then
        st.revealed = true
        layMedals()
        local n = st.result and #(st.result.puffs or {}) or 0
        banner(Games.line("head", n == 1 and "puffReceived" or "puffsReceived", nil, "Poké Puffs received!"))
      end
      if st.pt > 2.4 then
        if st.result and st.result.unlockedNew and not st.saidRank then
          st.saidRank = true
          banner(Games.line("head", "nextRank", nil, "You can now access the next rank!"))
          st.pt = 0.4
        else
          banner(nil)
          setPhase("buttons")
        end
      end
    end
    if s.game and st then
      -- rebuilt only when a part changes (once a second or on a hit), not every tick
      local stamp = st.score * 1e6 + st.combo * 1e3 + (st.lives or count) + (st.fever and 0.5 or 0)
      if st.hudFor ~= stamp then
        st.hudFor = stamp
        s.game.hud = ("HEAD IT  %s   %d pts  combo %d%s%s"):format(Games.DIFF_LABEL[st.diff], st.score, st.combo,
          st.fever and "  FEVER" or "", st.lives and ("  chances %d"):format(st.lives) or ("  %ds"):format(count))
      end
    end
  end

  -- ------- drawing

  local hudFonts = {}
  -- reused colour tables and cached lines (only the alpha moves frame to frame)
  local COMBO_COL, COMBO_OUT = { 0.86, 0.06, 0.18, 1 }, { 1, 1, 1, 0.8 }
  local FEVER_COL, WHITE3 = { 1, 0.62, 0.1, 1 }, { 1, 1, 1 }
  local STAMP_COL = { 0.85, 0.08, 0.12, 1 }
  local TIMER_RED = { 230, 0, 30, 255 }
  local SIGNAL = { "signal_red.bclim", "signal_yellow.bclim", "signal_blue.bclim" }
  local CHANCE_BALLS = { "3j", "3l", "3n" }
  local feverLine, stampLine
  -- text `px` layout units tall, rasterised at its size on screen
  local function hudText(G2, P, s, x, y, px, align, color, outline, rot)
    local x0, y0 = G2.transformPoint(0, 0)
    local x1, y1 = G2.transformPoint(0, 1)
    local k = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    if k <= 0 then return end
    local size = math.max(4, math.floor(px * k * 0.64 + 0.5))
    local f = hudFonts[size]
    if f == nil then
      local ok, font = pcall(function()
        if P and P.opts and P.opts.font then return P.opts.font(size) end
        return love.graphics.newFont(size)
      end)
      f = ok and font or false
      hudFonts[size] = f
    end
    if not f then return end
    G2.setFont(f)
    G2.push()
    G2.translate(x, y)
    if rot then G2.rotate(rot) end
    local lines = {}
    for line in tostring(s):gmatch("[^\n]+") do lines[#lines + 1] = line end
    local lh = f:getHeight() / k
    local top = -lh * #lines / 2
    for li, line in ipairs(lines) do
      local tw = f:getWidth(line) / k
      local ax = 0
      if align == "center" then ax = -tw / 2 elseif align == "right" then ax = -tw end
      local ty = top + (li - 1) * lh
      if outline then
        G2.setColor(outline[1], outline[2], outline[3], (outline[4] or 1) * (color[4] or 1))
        local o = math.max(1.2, 1 / k)
        for dx = -1, 1 do
          for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then G2.print(line, ax + dx * o, ty + dy * o, 0, 1 / k, 1 / k) end
          end
        end
      end
      G2.setColor(color[1], color[2], color[3], color[4] or 1)
      G2.print(line, ax, ty, 0, 1 / k, 1 / k)
    end
    G2.pop()
  end

  -- the game's message window (msg_win_ul / _u / _c: corners, edges, middle), sy opening it
  local function drawWindow(G2, cx, cy, w, h, sy)
    local ul, u, c = art("lyt/head_down/msg_win_ul"), art("lyt/head_down/msg_win_u"), art("lyt/head_down/msg_win_c")
    G2.push()
    G2.translate(cx, cy)
    G2.scale(1, sy or 1)
    local x0, y0 = -w / 2, -h / 2
    if not (ul and u and c) then
      G2.setColor(0.98, 0.95, 0.75, 1)
      G2.rectangle("fill", x0, y0, w, h, 6, 6)
      G2.setColor(0.85, 0.7, 0.3, 1)
      G2.rectangle("line", x0, y0, w, h, 6, 6)
      G2.pop()
      return
    end
    local e = 8   -- the frame's width on screen
    G2.setColor(1, 1, 1, 1)
    local cw, ch = c:getDimensions()
    G2.draw(c, x0 + e, y0 + e, 0, (w - 2 * e) / cw, (h - 2 * e) / ch)
    local uw, uh = u:getDimensions()
    local s = e / uh
    -- top and bottom edges, then left and right (the top edge turned)
    G2.draw(u, x0 + e, y0, 0, (w - 2 * e) / uw, s)
    G2.draw(u, x0 + e, y0 + h, 0, (w - 2 * e) / uw, -s)
    G2.draw(u, x0, y0 + h - e, -math.pi / 2, (h - 2 * e) / uw, s)
    G2.draw(u, x0 + w, y0 + e, math.pi / 2, (h - 2 * e) / uw, s)
    local kw, kh = ul:getDimensions()
    local ks = e / kh
    G2.draw(ul, x0, y0, 0, ks, ks)
    G2.draw(ul, x0 + w, y0, 0, -ks, ks)
    G2.draw(ul, x0, y0 + h, 0, ks, -ks)
    G2.draw(ul, x0 + w, y0 + h, 0, -ks, -ks)
    G2.pop()
  end

  local function drawBanner(G2, P)
    local b = st.banner
    if not b then return end
    local open = math.min(1, b.t / 0.33)
    if b.closing then open = math.max(0, 1 - b.ct / 0.33) end
    if open <= 0 then return end
    local big = b.color[1] > 0.5 or b.color[3] > 0.5
    local lines = select(2, b.text:gsub("\n", "\n")) + 1
    local w = big and 92 or 300
    local h = big and 26 or (12 + 12 * math.max(2, lines))
    local cy = big and 132 or 20 + h / 2
    drawWindow(G2, 160, cy - D, w, h, open)
    if open >= 0.6 then
      local wrapped = b.text
      if not big and lines == 1 and #wrapped > 34 then
        -- the game's two lines: break at the space nearest the middle
        local mid, at = math.floor(#wrapped / 2), nil
        for i = 1, #wrapped do
          if wrapped:sub(i, i) == " " and (not at or math.abs(i - mid) < math.abs(at - mid)) then at = i end
        end
        if at then wrapped = wrapped:sub(1, at - 1) .. "\n" .. wrapped:sub(at + 1) end
      end
      hudText(G2, P, wrapped, 160, cy - D, big and 20 or 13, "center", b.color)
    end
  end

  -- the ball textures' ids, built once: ballArt runs per ball per frame
  local BALL_ID = setmetatable({}, { __index = function(t, look)
    local row = { [0] = ("lyt/head_ball/%s_00"):format(look),
      ("lyt/head_ball/%s_01"):format(look), ("lyt/head_ball/%s_02"):format(look) }
    t[look] = row
    return row
  end })
  local GIANT_ID = { [0] = "lyt/head_ball/giant00", "lyt/head_ball/giant01", "lyt/head_ball/giant02" }
  local function ballArt(b, frame)
    if b.giant then return art(GIANT_ID[frame % 3]) end
    return art(BALL_ID[b.look][frame % 3])
  end

  -- a ball in screen units of either screen: (sx, sy) its middle
  local function drawBall(G2, b, sx, sy)
    local falling = b.state == "fall"
    local rate = falling and 5 or 3
    local img = ballArt(b, math.floor(b.f / rate))
    local w, h = 60, 90
    if b.giant then w, h = 175, 350 end
    local sqy = 1
    if b.state == "squash" then sqy = 1 - 0.25 * math.min(1, b.f / 2); sy = sy + 11 * math.min(1, b.f / 2) end
    G2.setColor(1, 1, 1, 1)
    if img then
      local iw, ih = img:getDimensions()
      -- rising, the yarn turns over (the clip's back: tail below)
      local r = (b.state == "rise") and math.pi or 0
      G2.draw(img, sx, sy, r, w / iw, h / ih * sqy, iw / 2, ih / 2)
    else
      G2.setColor(1, 0.55, 0.75, 1)
      G2.circle("fill", sx, sy + h * 0.15, w * 0.4, 20)
    end
  end

  local function drawMon(G2, i)
    local m = st.mons[i]
    if not m.shown or not m.pic or not m.pic.image then return end
    local img = m.pic.image
    local bx = m.box or { x0 = 0, y0 = 0, x1 = img:getWidth(), y1 = img:getHeight() }
    local bw, bh = math.max(1, bx.x1 - bx.x0), math.max(1, bx.y1 - bx.y0)
    local k = math.min(MON_H / bh, MON_W / bw)
    -- rising in from below, sinking away when leaving
    local f = math.min(1, m.t / ENTER_S)
    if m.leaving then f = 1 - math.min(1, m.t / LEAVE_S) end
    local sink = (1 - f) ^ 2 * (MON_H + 20)
    -- a heading: the head bobs up and back
    local lift = 0
    if m.head > 0 then
      local p = 1 - m.head / HEAD_FRAMES
      lift = math.sin(p * math.pi) * 10
    end
    -- idle: breathing and a bob, each to its own beat; livelier over RESULTS, with a hop now and then
    local resting = st.phase == "results" or st.phase == "smoke" or st.phase == "buttons"
    local t = st.t + i * 1.7
    local bob = (0.5 + 0.5 * math.sin(t * 2.2)) * (resting and 3 or 1)
    local breath = math.sin(t * 2.2) * (resting and 0.025 or 0.012)
    if resting then
      local hp = (t % 2.6) / 0.35
      if hp < 1 then bob = bob + math.sin(hp * math.pi) * 8 end
    end
    lift = lift + bob
    local x = 160 + slotX(i)
    -- the side Pokemon face the middle
    local face = (i == 3) and -1 or 1
    G2.setColor(1, 1, 1, 1)
    -- by its top, so a sprite shrunk to fit its width still has the star on its head
    -- (breathing about the feet)
    local ky = k * (1 + breath)
    drawPixel(img, x, HEAD_TOP - lift + sink + (k - ky) * bh, 0, k * face * (1 - breath * 0.5), ky, (bx.x0 + bx.x1) / 2, bx.y0)
  end

  local function drawStars(G2)
    local star = art("lyt/head_down/target")
    if not star then return end
    for i = 1, 3 do
      local m = st.mons[i]
      if monUp(i) and (st.phase == "play" or st.phase == "timeup" or st.phase == "demo" or (st.phase == "giant" and i == 1)) then
        local iw, ih = star:getDimensions()
        G2.setColor(1, 1, 1, 0.9)
        G2.draw(star, 160 + slotX(i), STAR_Y - (m.head > 0 and math.sin((1 - m.head / HEAD_FRAMES) * math.pi) * 10 or 0), 0, 32 / iw, 32 / ih, iw / 2, ih / 2)
      end
    end
  end

  local function drawFx(G2, P)
    local hit = art("lyt/head_effect/hit01")
    local tw0, tw1 = art("lyt/head_effect/twinkle0"), art("lyt/head_effect/twinkle1")
    local gold = art("lyt/head_down/star")
    for _, e in ipairs(fx) do
      local x, y = 160 + e.x, 120 - e.y
      local f = e.t * FPS
      if e.kind == "good" or e.kind == "just" then
        -- the puff of cloud at the head: grows to twice its size in 5 frames, gone by 15
        if hit then
          local s = (f < 2 and 1 + 0.05 * f) or (f < 5 and 1.1 + 0.3 * (f - 2)) or 2
          if e.giant then s = s * 1.6 end
          local a = f < 10 and 1 or math.max(0, 1 - (f - 10) / 5)
          local iw, ih = hit:getDimensions()
          G2.setColor(1, 1, 1, a)
          G2.draw(hit, x, y, 0, 64 / iw * s, 32 / ih * s, iw / 2, ih / 2)
        end
        if e.kind == "just" and (tw0 or tw1) then
          for j, d in ipairs(TWINKLES) do
            local p = math.min(1, f / 30)
            local img = (j % 2 == 0) and tw1 or tw0
            if img then
              local a = math.max(0, 1 - p)
              local iw, ih = img:getDimensions()
              local sz = (j % 2 == 0) and 10 or 20
              G2.setColor(1, 1, 1, a)
              G2.draw(img, x + d[1] * p, y - d[2] * p, f * 0.2, sz / iw, sz / ih, iw / 2, ih / 2)
            end
          end
        end
      elseif e.kind == "star" and gold and not e.landed then
        -- the points: a gold star from the head to the score bubble
        local p = math.min(1, e.t / 0.45)
        local q = p * p * (3 - 2 * p)
        local tx, ty = SCORE_AT[1] + 20, SCORE_AT[2] - D
        local sx = x + (tx - x) * q
        local sy = y + (ty - y) * q - math.sin(p * math.pi) * 30
        local iw, ih = gold:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(gold, sx, sy, p * 6, 20 / iw, 19 / ih, iw / 2, ih / 2)
      elseif e.kind == "miss" then
        -- MISS! by the Pokemon's feet, tilted, popping in and fading
        local a = e.t < 0.7 and 1 or math.max(0, 1 - (e.t - 0.7) / 0.3)
        local s = e.t < 0.12 and (0.5 + 0.6 * e.t / 0.12) or (e.t < 0.2 and 1.1 - (e.t - 0.12) / 0.08 * 0.1 or 1)
        G2.push()
        G2.translate(x + 42, 222 - e.t * 6)
        G2.scale(s, s)
        hudText(G2, P, Games.line("head", "miss", nil, "MISS!"), 0, 0, 22, "center", { 0.86, 0.06, 0.16, a }, { 1, 1, 1 }, -math.rad(15))
        G2.pop()
      elseif e.kind == "appear" then
        -- a Pokemon joining: pink stars burst from its feet
        local img = art("lyt/head_down/star_appear")
        if img then
          local iw, ih = img:getDimensions()
          for j = 0, 7 do
            local ang = -math.pi * (0.1 + 0.8 * j / 7)
            local p = math.min(1, e.t / 0.6)
            local r = 20 + 50 * p
            G2.setColor(1, 1, 1, 1 - p)
            G2.draw(img, x + math.cos(ang) * r, y + math.sin(ang) * r, p * 4, 16 / iw, 16 / ih, iw / 2, ih / 2)
          end
        end
      end
    end
    -- one "!!" over the middle Pokemon while the giant comes (popping in)
    if st.phase == "giant" and st.giant and st.giant.state == "fall" and not st.giant.missed then
      local img = art("lyt/head_effect/exc2")
      if img then
        local iw, ih = img:getDimensions()
        local s = st.pt < 0.1 and st.pt / 0.1 * 1.2 or (st.pt < 0.18 and 1.2 - (st.pt - 0.1) / 0.08 * 0.2 or 1)
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, 160, STAR_Y - 40, 0, 50 / iw * s, 50 / ih * s, iw / 2, ih / 2)
      end
    end
  end

  local function drawButton(G2, b, label, back, font)
    local img = art("game/pill_button")
    local x0, y0 = b[1] - b[3] / 2, b[2] - b[4] / 2
    if img then
      local iw, ih = img:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(img, x0, y0, 0, b[3] / iw, b[4] / ih)
    else
      G2.setColor(0.96, 0.55, 0.35, 1)
      G2.rectangle("fill", x0, y0, b[3], b[4], 12, 12)
    end
    if font then
      G2.setFont(font)
      local k = 14 / font:getHeight()
      G2.setColor(1, 1, 1, 1)
      G2.print(label, x0 + 12, b[2] - font:getHeight() * k / 2, 0, k, k)
    end
    if back then
      local ic = art("lyt/amie_deco/button_back") or art("training/home_return")
      if ic then
        local iw, ih = ic:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(ic, x0 + b[3] - 24, b[2] - 9, 0, 18 / iw, 18 / ih)
      end
    end
    if st and st.focus and BUTTONS[st.focus] == b then Games.drawFocus(G2, b) end
  end

  -- the touch screen's sky (bg_DOWN), scaled to cover a taller screen: its foot (the clouds the
  -- Pokemon stand in) on the screen's foot, the sides cropped evenly
  local function drawBackdrop(G2)
    local bg = art("lyt/head_bg/bg_DOWN")
    if not bg then
      G2.setColor(0.6, 0.85, 0.98, 1)
      G2.rectangle("fill", 0, -D - 20, 320, LH + 40)
      return
    end
    local iw, ih = bg:getDimensions()
    -- (the bleed above the screen's top is covered too)
    local k = (240 + D + 20) / 240
    G2.setColor(1, 1, 1, 1)
    G2.draw(bg, 160 - 160 * k, 240 - 240 * k, 0, 320 / iw * k, 240 / ih * k)
  end

  function app:draw(G2, w, h)
    setShape(h)
    local font
    if app.fontsFn then font = app.fontsFn() end
    if not st then return end
    G2.push()
    G2.translate(0, -bleed())
    G2.scale(L, L)
    G2.translate(0, D)
    drawBackdrop(G2)
    local Dn = st.art and screen("down")
    -- the Pokemon in the order they stand back to front: the sides behind the middle
    drawMon(G2, 2)
    drawMon(G2, 3)
    drawMon(G2, 1)
    drawStars(G2)
    -- the balls on the touch screen (and the gap above it on a taller screen)
    for _, b in ipairs(st.balls) do
      local sy = 120 - b.y
      if sy > -D - 200 and sy < 300 then drawBall(G2, b, 160 + b.x, sy) end
    end
    drawFx(G2, Dn)
    -- the score bubble, the combo, the windows (at the top of a taller screen)
    if Dn then
      if Dn.shapeD ~= D then
        Dn.shapeD = D
        Dn.adjust = D > 0 and { ["4"] = { dy = D } } or nil  -- (y up)
      end
      local showScore = st.hud and (st.phase == "play" or st.phase == "timeup" or st.phase == "leave" or st.phase == "giant")
      Dn:set("4", "visible", showScore and true or false)
      if showScore then
        if st.scoreTextFor ~= (st.shownScore or 0) then     -- formatted only when it changes
          st.scoreTextFor = st.shownScore or 0
          st.scoreText = ("%03d"):format(st.scoreTextFor)
        end
        Dn:setText("2", st.scoreText, { align = "center", valign = "center",
          scale = st.scorePop and (1 + 0.25 * (1 - st.scorePop / 0.3)) or nil })
      end
      Dn:draw(G2)
    end
    if st.comboShow then
      local c = st.comboShow
      local a = c.t < 1.0 and 1 or math.max(0, 1 - (c.t - 1.0) / 0.4)
      local s = c.t < 0.15 and (0.5 + 0.6 * c.t / 0.15) or (c.t < 0.25 and 1.1 - (c.t - 0.15) or 1)
      G2.push()
      G2.translate(165, 70 - D)
      G2.scale(s, s)
      c.text = c.text or Games.line("head", "combo", { N = c.n }, ("%d-HIT COMBO"):format(c.n))
      COMBO_COL[4] = a
      hudText(G2, Dn, c.text, 0, 0, 24, "center", COMBO_COL, COMBO_OUT)
      G2.pop()
    end
    if st.fever and (st.phase == "play" or st.phase == "timeup") then
      feverLine = feverLine or Games.line("head", "fever", nil, "FEVER")
      FEVER_COL[4] = 0.7 + 0.3 * math.sin(st.t * 8)
      hudText(G2, Dn, feverLine, 278, 26 - D, 18, "center", FEVER_COL, WHITE3)
    end
    -- the demo's pen
    if st.phase == "demo" then
      local pen = art("lyt/head_demo/TouchPen")
      if pen then
        local iw, ih = pen:getDimensions()
        local p = math.min(1, st.pt / 0.6)
        local px, py = 160 + 60 * (1 - p) + 22, 168 + 30 * (1 - p)
        if st.penTap and st.pt - st.penTap < 0.2 then py = py + 6 end
        G2.setColor(1, 1, 1, 1)
        G2.draw(pen, px, py, 0, 64 / iw, 64 / ih, iw * 0.2, ih * 0.15)
      end
    end
    if st.phase == "smoke" or st.phase == "buttons" then
      local Rw = st.art and screen("reward")
      if Rw then
        Rw.adjust = nil
        G2.push()
        G2.translate(0, -D / 2)
        Rw:draw(G2)
        G2.pop()
      end
    end
    drawBanner(G2, Dn)
    if st.phase == "buttons" then
      drawButton(G2, BUTTONS.again, Games.line("head", "playAgain", nil, "Play Again"), false, font)
      drawButton(G2, BUTTONS.quit, Games.line("head", "quit", nil, "Quit"), true, font)
    end
    if not st.art and st.result then
      G2.setColor(0, 0, 0, 0.5)
      G2.rectangle("fill", 40, 80, 240, 80)
      G2.setColor(1, 1, 1, 1)
      if font then G2.setFont(font) end
      G2.printf((st.result.title or "") .. "  " .. tostring(st.result.stars or 0) .. "*\n" .. tostring(st.final or 0), 40, 100, 240, "center")
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  -- ------- the top screen (session Layer.drawScene in a game hands it the playfield e, 240x160
  -- units): bg_up_rear's sky and rainbow, the yarn on its way, bg_up_front's HUD and RESULTS

  local STAR_TEX = { easy = "star_easy", normal = "star_normal", hard = "star_hard", unlimited = "star_infinite" }
  local RANK_STARS = { "59", "5b", "5d", "5f", "5h" }
  local STAR_FULL = { easy = { "v", "t", "x", "z", "11" }, hard = { "1d", "1p", "1r", "1t", "1v" },
    normal = { "1h", "25", "27", "29", "2b" }, unlimited = { "1l", "2l", "2n", "2p", "2r" } }
  local STAR_HALF = { easy = { "13", "15", "17", "19", "1b" }, hard = { "1f", "1x", "1z", "21", "23" },
    normal = { "1j", "2d", "2f", "2h", "2j" }, unlimited = { "1n", "2t", "2v", "2x", "2z" } }
  local DIGIT_GROUPS = { { "47" }, { "44", "45" }, { "40", "41", "42" }, { "3v", "3w", "3x", "3y" } }
  local RESULT_STEP = 0.8

  local function placeAt(P, name, cx, cy)
    P:set(name, "tx", cx - 200)
    P:set(name, "ty", 120 - cy)
    local bx, by, bw, bh = P:box(name)
    if not bx then return end
    P:set(name, "tx", cx - 200 + cx - (bx + bw / 2))
    P:set(name, "ty", 120 - cy - (cy - (by + bh / 2)))
  end

  function resultTotal()
    local step = math.floor((st.rt or 0) / RESULT_STEP)
    local total = st.score
    if step >= 1 then total = total + st.maxCombo end
    if step >= 2 then total = total + (st.bigBonus or 0) end
    return total, step
  end

  local function dressResults(F)
    local res = st.result or {}
    F:set("3a", "visible", false)
    F:set("5j", "visible", false)
    F:set("3p", "visible", false)
    F:set("6", "visible", true)
    local inResults = st.phase == "results" or st.phase == "smoke" or st.phase == "buttons"
    local _, step = resultTotal()
    if not inResults then step = 3 end
    F:setText("b", Games.line("head", "score", nil, "SCORE:"), { valign = "center" })
    F:setText("9", Games.line("head", "headingPoints", nil, "Heading Points"), { valign = "center" })
    F:setText("j", ("%03d"):format(st.score), { valign = "center" })
    F:setText("d", Games.line("head", "bonus", nil, "BONUS:"), { valign = "center" })
    F:setText("f", Games.line("head", "lastCombo", nil, "Last Combo Record"), { valign = "center" })
    F:setText("h", Games.line("head", "bigYarn", nil, "Big Yarn Bonus"), { valign = "center" })
    F:set("h", "visible", true)
    F:set("l", "visible", step >= 1)
    F:setText("l", ("%03d"):format(st.maxCombo), { valign = "center" })
    F:set("n", "visible", step >= 2)
    F:setText("n", ("%03d"):format(st.bigBonus or 0), { valign = "center" })
    F:setText("57", Games.line("head", "total", nil, "TOTAL:"), { align = "center", valign = "center" })
    F:set("7", "visible", false)
    -- the digit pictures the layout parks below its 400 x 240 (a tall playfield shows them)
    for _, n in ipairs({ "3s", "r", "36", "38" }) do F:set(n, "visible", false) end
    for _, g in ipairs(DIGIT_GROUPS) do for _, n in ipairs(g) do F:set(n, "visible", false) end end
    -- the title and the stars
    local diff = STAR_TEX[st.diff] and st.diff or "easy"
    for d in pairs(STAR_FULL) do
      for j = 1, 5 do F:set(STAR_FULL[d][j], "visible", false); F:set(STAR_HALF[d][j], "visible", false) end
    end
    local shown = step >= 3
    F:set("p", "visible", shown)
    F:setText("p", res.title or "", { align = "center", valign = "center" })
    local stars = res.stars or 0
    for j, name in ipairs(RANK_STARS) do
      F:set(name, "visible", true)
      F:setImage(name, F:image(STAR_TEX[diff] .. ".bclim"))
      local full, half = stars >= j, stars >= j - 0.5
      if shown and (full or half) then
        local gold = (full and STAR_FULL or STAR_HALF)[diff][j]
        local p = F.L.byName[gold]
        local bx, by, bw, bh = F:box(name)
        if p and bx then
          local k = p.w > 0 and bw / p.w or 1
          F:set(gold, "visible", true)
          F:set(gold, "sx", k)
          F:set(gold, "sy", k)
          placeAt(F, gold, bx + bw / 2, by + bh / 2)
        end
      end
    end
    -- HIGH SCORE: a new best (drawn over TOTAL by drawStamp)
    F:set("3b", "visible", false)
    if shown and res.newHigh and not st.stampAt then
      st.stampAt = st.rt or 0
      if mod.haptics then mod.haptics.pattern("success") end; G.se("stamp")
    end
  end

  -- the HIGH SCORE stamp at the layout's 3b (its corner of TOTAL, overlapping the number's
  -- left, tilted 30 degrees, the texture's 100 x 30), drawn over the digits; slammed in as the
  -- highscore clip does (3x down to 1x in 10 frames, then a nudge)
  local STAMP = { x = 302, y = 118, w = 100, h = 30, text = 13 }
  local function drawStamp(G2, F)
    if not st.stampAt then return end
    local f = ((st.rt or 0) - st.stampAt) * FPS
    local s = f < 10 and (3 - 2 * f / 10) or 1
    local dx = (f >= 10 and f < 16) and -2 * math.sin((f - 10) / 6 * math.pi) or 0
    local img = F:image("stamp.bclim")
    G2.push()
    G2.translate(STAMP.x + dx, STAMP.y)
    G2.rotate(-math.rad(30))
    G2.scale(s, s)
    local w, h = STAMP.w, STAMP.h
    if img then
      local iw, ih = img:getDimensions()
      G2.setColor(1, 1, 1, math.min(1, f / 3))
      G2.draw(img, -w / 2, -h / 2, 0, w / iw, h / ih)
    end
    stampLine = stampLine or (Games.line("head", "highScore", nil, "HIGH SCORE:"):gsub(":%s*$", ""))
    STAMP_COL[4] = math.min(1, f / 3)
    hudText(G2, F, stampLine, 0, 0, STAMP.text, "center", STAMP_COL)
    G2.pop()
  end

  -- TOTAL in the game's big digits, in the digit panes for its length; returns its middle
  local function drawTotal(G2, F)
    local total = resultTotal()
    if not (st.phase == "results" or st.phase == "smoke" or st.phase == "buttons") then total = st.final or total end
    local s = tostring(math.max(0, math.floor(total)))
    if #s > 4 then s = s:sub(-4) end
    local group = DIGIT_GROUPS[#s]
    local x0, x1, my = nil, nil, nil
    for i = 1, #s do
      local bx, by, bw, bh = F:box(group[i])
      local img = F:image(s:sub(i, i) .. ".bclim")
      if bx and img then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, bx + bw / 2, by + bh / 2, 0, 40 / iw, 40 / ih, iw / 2, ih / 2)
        x0, x1, my = x0 or (bx + bw / 2), bx + bw / 2, by + bh / 2
      end
    end
    if x0 then return (x0 + x1) / 2, my end
    return 329, 122
  end

  function app.drawTop(G2, e)
    if not (st and st.art) then return false end
    local Rr, F = screen("rear"), screen("front")
    if not (Rr and F) then return false end
    e = e or { x = 0, y = 0, w = 240, h = 160 }
    -- the sky across the whole playfield
    local sky = Rr:image("sky.bclim")
    if sky then
      local iw, ih = sky:getDimensions()
      local k = math.max(e.w / iw, e.h / ih)
      G2.setColor(1, 1, 1, 1)
      G2.draw(sky, e.x + (e.w - iw * k) / 2, e.y + (e.h - ih * k) / 2, 0, k, k)
    end
    -- the layout centred across the playfield; while playing against its top edge (the HUD at
    -- the top), RESULTS in the middle of its height
    local k = math.min(e.w / 400, e.h / 240)
    local below = e.h / k - 240
    local playing = not (st.phase == "results" or st.phase == "smoke" or st.phase == "buttons")
    G2.push()
    G2.translate(e.x + (e.w - 400 * k) / 2, e.y + (playing and 0 or below / 2 * k))
    G2.scale(k, k)
    -- the rainbow (bg_up_rear u: v / x / z, 400 x 170 about (200, 155)): thin from the first
    -- hit, wider from 3, widest in FEVER (blinking as the fever clip does); it fades on a miss
    local band, a = st.rainbow, 1
    if band then a = math.min(1, (st.rainbowT or 0) / 0.2)
    elseif st.rainbowOut and st.lastBand then band, a = st.lastBand, 1 - st.rainbowOut / 0.5 end
    if band then st.lastBand = st.rainbow or st.lastBand end
    if st.phase == "results" or st.phase == "smoke" or st.phase == "buttons" then band = nil end
    local img = band and Rr:image(SIGNAL[band])
    if img then
      if band == 3 then a = a * (0.75 + 0.25 * math.cos((st.rainbowT or 0) * math.pi * 2 * 0.75)) end
      local iw, ih = img:getDimensions()
      G2.setColor(1, 1, 1, a)
      G2.draw(img, 0, 70, 0, 400 / iw, 170 / ih)
    end
    if playing then
      F:set("6", "visible", false)
      F:set("3a", "visible", st.hud and true or false)
      local unlimited = st.diff == "unlimited"
      F:set("4", "visible", not unlimited)
      if not unlimited then
        local left = math.max(0, math.ceil(st.timer / FPS))
        local red = st.timer > 0 and left <= 5
        if st.timeTextFor ~= left then     -- the line changes once a second, not once a frame
          st.timeTextFor = left
          st.timeText = Games.line("head", "timeLeft", { N = ("%02d"):format(left) }, ("Time Left: %02d"):format(left))
        end
        F:setText("4", st.timeText, { align = "center", valign = "center", color = red and TIMER_RED or nil })
        -- the last seconds beat (timeup_anm's 5m)
        if red then
          local into = (st.timer % FPS) / FPS
          F:set("5m", "ty", -3 * math.sin(into * math.pi))
        else
          F:clear("5m", "ty")
        end
      end
      F:set("5j", "visible", unlimited and st.hud and true or false)
      F:set("3p", "visible", unlimited and st.hud and true or false)
      if unlimited then
        F:setText("0", Games.line("head", "chances", nil, "Chances:"), { align = "right", valign = "center" })
        F:set("5k", "visible", false)
        for j, n in ipairs(CHANCE_BALLS) do
          F:set(n, "visible", true)
          F:set(n, "sx", 0.55)
          F:set(n, "sy", 0.55)
          F:set(n, "alpha", (st.lives or 0) >= j and 255 or 60)
          placeAt(F, n, 236 + (j - 1) * 24, 55)
        end
      end
      F:draw(G2)
      -- the yarn on its way (over the words, as the game draws it): the top screen's height is
      -- the rules' y 480 .. 240 whatever the playfield's shape, so a ball leaves its foot as it
      -- is due on the touch screen
      local ky = (240 + below) / 240
      for _, b in ipairs(st.balls) do
        local sy = (480 - b.y) * ky
        if sy > -200 and sy < (240 + below) + 200 then drawBall(G2, b, 200 + b.x, sy) end
      end
    else
      dressResults(F)
      F:draw(G2)
      drawTotal(G2, F)
      drawStamp(G2, F)
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
    return true
  end

  -- ------- for the driver and tests

  function app.debugState() return st end
  app.screen = screen
  function app.busy()
    if not st then return false end
    return st.phase ~= "play" and st.phase ~= "buttons"
  end
  -- the pad (the session asks first): left / up or A / right head the left / middle / right
  -- Pokemon, as a tap on it does; on the end buttons up / down, A and B (Games.padButtons)
  function app.padInput(input)
    local s = G.session
    if not (st and s and s.mode == "game") then return false end
    if st.phase == "buttons" then
      return Games.padButtons(input, st, { "again", "quit" }, function(n) G.padTap(app, app.tapPoint(n)) end)
    end
    if st.phase == "play" or st.phase == "timeup" or st.phase == "giant" then
      local slot = (input:wasPressed("left") and 2) or (input:wasPressed("right") and 3)
        or ((input:wasPressed("up") or input:wasPressed("a")) and 1) or nil
      if slot then G.padTap(app, app.tapPoint("slot", slot)); return true end
    end
    return false
  end

  function app.tapPoint(what, i)
    if not st then return nil end
    if what == "slot" then return fromScene(160 + slotX(i or 1), 200) end
    local b = BUTTONS[what]
    if b then return fromScene(b[1], b[2]) end
    return nil
  end
  -- the slot of a ball in the star's window now (what a perfect player taps), or nil
  function app.nextTap(want)
    if not st then return nil end
    for _, b in ipairs(st.balls) do
      if b.state == "fall" and not b.missed and not b.demo and grade(b) == (want or "just") then return b.slot end
    end
    return nil
  end

  function app:releaseAll() end
  app.leave = app.releaseAll
  return app
end
