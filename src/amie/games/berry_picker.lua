-- BERRY PICKER, played from the game's own screens (a/0/1/6: background_rear / _front,
-- nuts, balloon, demoanimation02, nuts_animation, reward on the touch screen, score on the
-- top screen). Up to three of the player's
-- Pokemon stand under the tree and think of the berry they want; drag the right one down from
-- the tree before their patience runs out. 60 seconds on Easy / Normal / Hard, three misses
-- on Unlimited. Rules: Bulbapedia "Berry Picker" (unchanged from the drawn version).
--
-- Flow, as the game: the demo (the hand feeds each Pokemon, READY, START!) -> play -> TIME'S
-- UP -> the view rises into the canopy while berries rain onto the heap (the top screen's
-- RESULTS card counts up) -> a burst of smoke and the Poke Puff medallions with "Poke Puffs
-- Received!" (and "You can now access the next rank!") -> Play Again / Quit. These clips run
-- at 60 frames a second (measured on the capture: the demo's window, 280 frames, 4.4 s).

return function(mod, Pointer, G, Games, Rules, host)

  -- pixel art (GBA sprites) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "game_berry", title = "BERRY", live = true }

  function app:wantsSurface()
    local s = G.session
    return s ~= nil and s.mode == "game" and s.game and s.game.id == "berry" or false
  end

  local L = 256 / 320
  local BLEED = 14
  local FPS = 60
  -- the screen's shape: the scene is the game's 320x240, anchored to the bottom; a taller
  -- screen (Kanto Gear's) shows D more of the canopy above it, the timer and the message
  -- window staying at the top (D = 0 on the 3DS shape)
  local LH, D = 240, 0
  local function bleed() return app.bleed or BLEED end
  local function setShape(h)
    local lh = math.max(240, ((h or 178) + bleed()) / L)
    if lh == LH then return end
    LH, D = lh, lh - 240
    app.shapeDirty = true
  end
  app.setShape = setShape

  local BERRY_KINDS = { -- recipe ids in difficulty order: Razz, Bluk, Pinap, Wepear, Magost, Durin, Nomel
    "berry/01", "berry/02", "berry/03", "berry/04", "berry/05", "berry/06", "berry/07" }
  local KINDS_FOR = { easy = 3, normal = 5, hard = 7, unlimited = 5 }
  -- the layouts' panes per berry kind (kinomi00..06)
  local NUT = { "1g", "5", "7", "9", "b", "d", "f" }          -- nuts: the berry
  local GHOST = { "w", "y", "10", "12", "14", "16", "18" }    -- nuts: its faint copy left on the tree
  local SET = { "2v", "2w", "2x", "2y", "2z", "30", "31" }    -- balloon: the thought bubble set
  -- the three spots (balloon anchors 2s / 2t / 2u, nuts drop boxes 1j / 1k / 1l)
  local SPOT_X = { 56, 160, 265 }
  local SPOT_Y = 190
  local DROP = { "1j", "1k", "1l" }
  local COUNT = { "8", "a", "c" }                              -- front: the +N over each spot
  -- a Pokemon's feet and height: the models fill more of the space than a 64x64 sprite's
  -- frame does, so the frame is drawn a size up
  local MON_FOOT, MON_H = 238, 104
  -- the bubble set above the spot's anchor (the bubbles' middles at y ~148)
  local BUBBLE_LIFT = 4
  -- the timer (front pane 2, right aligned): its right edge and middle in scene units, the
  -- font a size up, red and beating from 5 seconds left (the capture: right edge ~290, middle
  -- ~14, glyphs ~15 tall)
  local TIMER = { x = 292, y = 16, w = 160, scale = 1.35, beat = 0.22, BEAT_S = 0.3,
    white = { 255, 255, 255, 255 }, red = { 230, 30, 40, 255 } }
  -- the top screen's HIGH SCORE bar (score 2m / 2o): the capture's glyphs are ~1.35 ours
  local HIGH_SCALE = 1.35
  -- an asking Pokemon rises from below the screen, thinks of its berry once up, and drops back
  -- down off screen when its bubble has closed
  local RISE_S = 0.22
  local MON_DROP = MON_H + 16
  -- a berry let go anywhere but on an asking Pokemon falls and is lost; its kind is back on
  -- the tree once it has fallen off the bottom
  local FALL_G, FALL_OUT = 900, 270

  local st = nil      -- the running game
  local drag = nil    -- { kind, x, y, id } (scene units)
  local seenDemo = false
  local players = {}  -- the screens, opened once the art is there

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local OPEN = {
    rear = { "berry_rear", "background_rear.bclyt" }, front = { "berry_front", "background_front.bclyt" },
    nuts = { "berry_nuts", "nuts.bclyt" }, balloon = { "berry_balloon", "balloon.bclyt" },
    demo = { "berry_demo", "demoanimation02.bclyt" }, rain = { "berry_nutsanim", "nuts_animation.bclyt" },
    reward = { "berry_reward", "reward.bclyt" }, score = { "berry_score", "score.bclyt", { "berry_score", "berry_lang" } },
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
  local function allScreens()
    for name in pairs(OPEN) do if not screen(name) then return false end end
    return true
  end

  -- ------- the rules (Bulbapedia "Berry Picker")

  local function rotationFor(diff)
    if diff == "unlimited" then
      return { { n = 1, count = 5 }, { n = 2, count = 10 }, { n = 3, count = 15 },
        { n = 1, count = 5 }, { n = 2, count = 15 }, { n = 3, count = 30 },
        { n = 2, count = 10 }, { n = 3, count = 20 }, { n = 1, count = 5 }, { n = 3, count = math.huge } }
    end
    return { { n = 1, count = 10 }, { n = 2, count = 15 }, { n = 3, count = math.huge } }
  end

  local function patienceFor()
    local diff = st.diff
    if diff == "unlimited" then
      if st.served < 110 then return 3 end
      return math.max(1.2, 3 - (st.served - 110) * 0.02)
    end
    if diff == "hard" and st.rot.n == 2 then return math.max(2, 3 - st.servedInRot * 0.08) end
    return 3
  end

  -- the game's own dice: math.random is never seeded in the engine (every launch rolled the
  -- same askers and wants), and reseeding it would change every other mod's rolls too; a
  -- LOVE generator seeded per round from the clock instead
  local function roll(a, b)
    local g = st and st.rng
    if g then return g:random(a, b) end
    return math.random(a, b)
  end

  -- a want nobody else on screen is asking for (each kind has one bubble set)
  local function pickWant(exclude)
    for _ = 1, 20 do
      local k = roll(1, st.kinds)
      local clash = false
      for _, sl in pairs(st.slots) do
        -- (a bubble still closing holds its set too)
        if sl ~= exclude and ((sl.visible and sl.want == k) or (sl.bal and sl.bal.kind == k)) then clash = true end
      end
      if not clash then return k end
    end
    return roll(1, st.kinds)
  end

  -- ------- the bubbles (balloon: one set per berry kind, moved onto the spot that wants it)

  local function bubble(i, kind, clip, after)
    local B = screen("balloon")
    local sl = st.slots[i]
    if not (B and kind) then return end
    local set = SET[kind]
    B:set(set, "tx", SPOT_X[i] - 160)
    -- over the Pokemon's head (the game floats it above its model; our sprites stand
    -- MON_H tall on the spot)
    B:set(set, "ty", 120 - (SPOT_Y - BUBBLE_LIFT))
    B:set(set, "visible", true)
    local name = ("balloon_%s_%02d"):format(clip, kind - 1)
    B:play(name)
    sl.bal = { kind = kind, clip = name, after = after }
  end

  -- a slot starts asking: the Pokemon rises; its bubble opens (and its patience runs) once
  -- it is up (update)
  local function showSlot(i)
    local sl = st.slots[i]
    sl.visible = true
    sl.asking = false
    sl.want = pickWant(sl)
    sl.patience = patienceFor()
    sl.left = sl.patience
    sl.hideTimer = 0
  end

  -- a slot stops asking: its bubble closes, then the Pokemon drops (update)
  local function hideSlot(i, clip, wait)
    local sl = st.slots[i]
    if sl.visible and sl.asking then bubble(i, sl.want, clip or "close", clip and "close" or nil) end
    sl.visible, sl.asking = false, false
    if wait then sl.hideTimer = wait end
  end

  local function advanceRotation()
    st.servedInRot = st.servedInRot + 1
    if st.servedInRot >= st.rot.count and st.rotIndex < #st.rotation then
      st.rotIndex = st.rotIndex + 1
      st.rot = st.rotation[st.rotIndex]
      st.servedInRot = 0
      for i = 1, 3 do hideSlot(i, nil, 0.3) end
    end
  end

  local function miss(i, timedOut)
    local sl = st.slots[i]
    hideSlot(i, timedOut and "timeup" or "mistake", 0.3)
    st.misses = st.misses + 1
    host.playSe("SE_NOT_EFFECTIVE")
    advanceRotation()
  end

  -- ------- the end

  local function setPhase(p)
    st.phase, st.pt = p, 0
  end

  local function finish()
    st.result = G.endGame(st.score, false, true)
    drag = nil
    setPhase("timeUp")
    local F = screen("front")
    if F then F:play("anm_timeUp"); F:setText("5", Games.line("berry", "timesUp", nil, "TIME'S UP"), { align = "center", valign = "center" }) end
    for i = 1, #st.slots do hideSlot(i, "timeup") end
  end

  local PUFF_TIER = { basic = 1, frosted = 2, fancy = 3, deluxe = 4, supreme = 5 }
  local medals = {}   -- { pane, child } in use

  local function layMedals()
    local R = screen("reward")
    medals = {}
    if not R then return end
    local panes = {}
    for _, name in ipairs(R.L.groups["6m"] or {}) do panes[#panes + 1] = name end
    table.insert(panes, 1, "0")
    for _, name in ipairs(panes) do R:set(name, "visible", false) end
    local puffs = (st.result and st.result.puffs) or {}
    local n = math.min(#puffs, 12)
    local perRow = math.min(6, n)
    for j = 1, n do
      local name = panes[j]
      local pane = R.L.byName[name]
      local child = pane and pane.children[1]
      if pane and child then
        local row = math.floor((j - 1) / 6)
        local col = (j - 1) % 6
        local inRow = (row == 0) and perRow or (n - 6)
        local x = 160 + (col - (inRow - 1) / 2) * 50
        local y = 88 + row * 56
        R:set(name, "visible", true)
        R:set(name, "tx", x - 160)
        R:set(name, "ty", 120 - y)
        local tier = PUFF_TIER[Rules.puffTier and Rules.puffTier(puffs[j]) or "basic"] or 1
        R:setImage(name, R:image(("wappen_%02d.bclim"):format(tier)))
        local img = art(puffs[j])
        if img then R:setImage(child.name, img) end
        R:play("get_item", { as = name, sample = "0", loop = true, from = (j * 7) % 40 })
        medals[#medals + 1] = name
      end
    end
  end

  local function frontWindow(text)
    local F = screen("front")
    if not F then return end
    F:setText("z", text, { align = "center", valign = "center" })
    F:play("window_open")
  end

  -- ------- start / quit

  function app:start(game)
    st = { diff = game.diff, participants = game.participants, phase = "countdown", t = 0, pt = 0, count = 3,
      timer = 60, score = 0, misses = 0, lives = (game.diff == "unlimited") and 3 or nil,
      kinds = KINDS_FOR[game.diff] or 3, rotation = rotationFor(game.diff), rotIndex = 1, servedInRot = 0,
      served = 0, slots = {}, result = nil, best = Games.highScore and Games.highScore("berry", game.diff) or 0,
      viewY = 0, shown = 0 }
    st.rot = st.rotation[1]
    for i = 1, 3 do
      local mon = game.participants[i] and game.participants[i].mon
      -- the demo shows all three standing (stay); they drop when play starts
      st.slots[i] = { mon = mon, visible = false, hideTimer = 0.1 + i * 0.15, lift = 1, stay = true,
        pic = mon and host.frontPic and host.frontPic(mon) or nil }
    end
    st.falling = {}
    st.picked = {}    -- the kind of every berry delivered, for the heap
    do
      local ok, g = pcall(function()
        local t = love.timer.getTime()
        return love.math.newRandomGenerator(os.time() + math.floor((t - math.floor(t)) * 1e6))
      end)
      st.rng = ok and g or nil
    end
    drag = nil
    medals = {}
    -- the screens from their first frame
    st.art = allScreens()
    if st.art then
      for name in pairs(OPEN) do
        local P = screen(name)
        P.active, P.over, P.texts, P.images = {}, {}, {}, {}
      end
      local Rr, F, Dm, N, B, Sc = screen("rear"), screen("front"), screen("demo"), screen("nuts"), screen("balloon"), screen("score")
      Rr:play("anm_clouds", { loop = true })
      Rr:play("anm_grass", { loop = true })
      for _, n in ipairs({ "2", "4", "6", "8" }) do Rr:set(n, "visible", false) end
      for k = 1, #NUT do N:set(GHOST[k], "visible", false) end
      for k = 1, #SET do B:set(SET[k], "visible", false) end
      F:set("4", "visible", false)
      -- the demo: the long one the first time this session, the short one after
      Dm:setText("18", Games.line("berry", "howTo", nil, "Pick Berries for your Pokémon!"), { align = "center", valign = "center" })
      Dm:setText("w", Games.line("berry", "ready", nil, "READY"), { align = "center", valign = "center" })
      Dm:setText("y", Games.line("berry", "start", nil, "START!"), { align = "center", valign = "center" })
      st.demoClip = seenDemo and "anm_demo_short" or "anm_demo"
      seenDemo = true
      Dm:play(st.demoClip)
      -- the top screen: the HIGH SCORE bar, the card waiting for the end
      Sc:set("2h", "visible", false)
      Sc:set("2i", "visible", false)
      Sc:set("2u", "visible", false)
      -- 2u's star pictures are the layout's palette; only its title text is shown
      for _, c in ipairs(Sc.L.byName["2u"].children) do
        if c.kind == "pic" then Sc:set(c.name, "visible", false) end
      end
      Sc:set("4s", "visible", false)
      -- the HIGH SCORE bar a size up, its number left in its box as the game sets it (it was
      -- forced right, against the screen's edge)
      Sc:setText("2m", Games.line("berry", "highScore", nil, "HIGH SCORE:"), { align = "right", valign = "center", scale = HIGH_SCALE })
      Sc:setText("2o", tostring(st.best or 0), { valign = "center", scale = HIGH_SCALE })
      -- and off the top edge: the bar's middle from y 10 to 15
      Sc:set("2m", "ty", 105)
      Sc:set("2o", "ty", 105)
    end
    game.hud = ("BERRY PICKER  %s"):format(Games.DIFF_LABEL[game.diff])
  end

  function app:quit()
    if st and (st.phase == "countdown" or st.phase == "play") then st = nil; G.endGame(nil, true) end
  end

  -- the driver ends a run early with a chosen score
  function app.forceEnd(score)
    if st and st.phase == "play" then st.score = score or st.score; finish() end
  end

  -- ------- where things are (scene units: the game's 320x240, y down)

  local function treePos(k)
    local n = st and st.kinds or 3
    if n <= 3 then
      local xs = { 52, 160, 268 }
      return xs[k], 40
    end
    local x = 36 + (k - 1) * (248 / (n - 1))
    return x, (k % 2 == 0) and 58 or 40
  end
  -- app point -> scene point (the scene drawn D lower)
  local function toScene(x, y) return x / L, (y + bleed()) / L - D end
  local function fromScene(x, y) return x * L, (y + D) * L - bleed() end

  local BUTTONS = { again = { 160, 170, 126, 28 }, quit = { 160, 204, 126, 28 } }
  local function inButton(b, x, y)
    return math.abs(x - b[1]) <= b[3] / 2 and math.abs(y - b[2]) <= b[4] / 2
  end

  -- ------- input

  function app:pointer(ev, rec)
    local s = G.session
    if not (st and s and s.mode == "game") then return end
    local x, y = toScene(ev.x, ev.y)
    if st.phase == "buttons" then
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) then
        if inButton(BUTTONS.again, x, y) then
          host.playSe("SE_SELECT")
          local game = s.game
          G.startGame(game.id, game.diff)
        elseif inButton(BUTTONS.quit, x, y) then
          host.playSe("SE_SELECT")
          st = nil
          G.leaveGame({ toPetting = true })
        end
      end
      return
    end
    if not st.art and st.phase ~= "play" and st.phase ~= "countdown" then
      -- no art: a tap leaves once the result is in
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) and st.pt > 1.0 then st = nil; G.leaveGame({ toPetting = true }) end
      return
    end
    if st.phase ~= "play" then return end
    if ev.phase == "pressed" then
      for k = 1, st.kinds do
        local px, py = treePos(k)
        -- a kind still falling from a lost drop is not on the tree yet
        if not st.falling[k] and (x - px) ^ 2 + (y - py) ^ 2 <= 24 ^ 2 then
          drag = { kind = k, x = x, y = y, id = ev.id }
          local N = screen("nuts")
          if N then N:play("kinomi_catch", { as = NUT[k], sample = "3" }) end
          host.playSe("SE_SELECT")
          return
        end
      end
    elseif ev.phase == "moved" then
      if drag and drag.id == ev.id then drag.x, drag.y = x, y end
    else
      if not (drag and drag.id == ev.id) then return end
      local d = drag
      drag = nil
      local N = screen("nuts")
      if N then N:play("kinomi_not_catch", { as = NUT[d.kind], sample = "3" }) end
      -- let go anywhere but on an asking Pokemon (or the touch lost): the berry drops to the
      -- ground and is lost; its kind is back on the tree once it is off the bottom
      if ev.phase == "released" and x and y then d.x, d.y = x, y end
      local function lose()
        st.falling[d.kind] = { x = d.x, y = d.y, vy = 0 }
      end
      if ev.phase ~= "released" then lose(); return end
      for i, sl in ipairs(st.slots) do
        local hit
        if N then
          local bx, by, bw, bh = N:box(DROP[i])
          hit = bx and x >= bx and x <= bx + bw and y >= by and y <= by + bh
        else
          hit = math.abs(x - SPOT_X[i]) <= 45 and math.abs(y - SPOT_Y) <= 50
        end
        if sl.visible and sl.asking and hit then
          if sl.want == d.kind then
            local quick = (st.t - sl.shownAt) <= 1.5
            st.score = st.score + 1
            st.served = st.served + 1
            st.picked[#st.picked + 1] = d.kind
            bubble(i, sl.want, quick and "right2" or "right1", "close")
            sl.visible, sl.asking = false, false
            sl.hideTimer = 0.2
            sl.hop = 0
            host.playSe(quick and "SE_PIN" or "SE_SELECT")
            if st.score % 10 == 0 then
              host.playCry(sl.mon)
              local F = screen("front")
              if F then
                for j, c in ipairs(COUNT) do F:set(c, "visible", j == i) end
                F:setText(COUNT[i], tostring(st.score), { align = "center", valign = "center",
                  color = { 255, 255, 255, 255 }, outline = { 200, 90, 30, 255 } })
                F:play("anm_GetsNum")
              end
            end
            advanceRotation()
          else
            miss(i, false)
          end
          return
        end
      end
      lose()
    end
  end

  -- ------- update

  -- The heap at the end: one berry for every berry picked, each the kind
  -- that was delivered, at the tree berries' own size, stacked in a mound on the ground -
  -- rows each one shorter from the ground up, none wider than PILE.maxRow (then a trapezoid),
  -- squeezed if it would stand taller than PILE.maxH. Replaces the layout's single heap
  -- picture (rear pane 2, pile_level0..3), which only grew with the count.
  local PILE = { dx = 24, dy = 17, maxRow = 11, maxH = 200, baseY = 220, x = 160 }
  local function buildPile()
    local n = math.max(0, math.floor(st.score or 0))
    if n == 0 then return {} end
    -- row widths from the top: 1, 2, 3 ... up to maxRow, then maxRow again, until they hold n;
    -- the overshoot comes off the top
    local rows, sum = {}, 0
    while sum < n do
      local w = math.min(#rows + 1, PILE.maxRow)
      rows[#rows + 1] = w
      sum = sum + w
    end
    local over = sum - n
    while over > 0 do
      if rows[1] <= over then over = over - table.remove(rows, 1)
      else rows[1] = rows[1] - over; over = 0 end
    end
    local dy = math.min(PILE.dy, PILE.maxH / math.max(1, #rows))
    local pile, i = {}, 0
    for r = #rows, 1, -1 do          -- the ground row first, so higher rows draw over it
      local c = rows[r]
      local level = #rows - r
      for j = 1, c do
        i = i + 1
        local kind = st.picked[i] or ((i * 7) % st.kinds) + 1   -- forceEnd sets a bare count
        -- a little give, the same every time, so it reads as a heap rather than a grid
        local jx, jy = (i * 37) % 7 - 3, (i * 53) % 5 - 2
        pile[#pile + 1] = { kind = kind, x = PILE.x + (j - (c + 1) / 2) * PILE.dx + jx,
          y = PILE.baseY - level * dy + jy }
      end
    end
    return pile
  end

  local function drawPile(G2)
    local N = screen("nuts")
    if not (N and st.pile) then return end
    G2.setColor(1, 1, 1, 1)
    for _, b in ipairs(st.pile) do
      local img = N:image(("kinomi%02d.bclim"):format(b.kind - 1))
      local p = N.L.byName[NUT[b.kind]]
      if img and p then
        local iw, ih = img:getDimensions()
        G2.draw(img, b.x, b.y, 0, p.w / iw, p.h / ih, iw / 2, ih / 2)
      end
    end
  end

  local function advanceAll(frames)
    for _, P in pairs(players) do if P then P:advance(frames) end end
  end

  local RAIN = { "anm_nutsfall_start", "anm_nutsfall_loop", "anm_nutsfall_loop", "anm_nutsfall_end" }

  function app:update(dt)
    local s = G.session
    if not (st and s and s.mode == "game") then app.live = false; return end
    app.live = true
    dt = dt or 0
    st.t = st.t + dt
    st.pt = (st.pt or 0) + dt
    if st.art then advanceAll(dt * FPS) end
    -- the Pokemon rise to ask and drop when their bubble has gone; lost berries fall
    for _, sl in ipairs(st.slots) do
      local target = (sl.visible or sl.bal ~= nil or sl.stay) and 1 or 0
      local lift = sl.lift or 0
      if lift < target then sl.lift = math.min(target, lift + dt / RISE_S)
      elseif lift > target then sl.lift = math.max(target, lift - dt / RISE_S) end
    end
    for k, f in pairs(st.falling) do
      f.vy = f.vy + FALL_G * dt
      f.y = f.y + f.vy * dt
      if f.y > FALL_OUT then st.falling[k] = nil end
    end
    -- a bubble's clip ends: its next one (wait loops; close hides the set)
    if st.art then
      local B = screen("balloon")
      for _, sl in ipairs(st.slots) do
        local b = sl.bal
        -- a clip has ended: wait loops, close plays, and a finished close (or a close
        -- played on its own) hides the set; the Pokemon drops once its bubble is gone
        if b and B:finished(b.clip) then
          local after = b.after
          b.after = nil
          if after == "wait" then
            b.clip = ("balloon_wait_%02d"):format(b.kind - 1)
            B:play(b.clip, { loop = true })
          elseif after == "close" then
            b.clip = ("balloon_close_%02d"):format(b.kind - 1)
            B:play(b.clip)
            b.after = "hide"
          else
            B:set(SET[b.kind], "visible", false)
            sl.bal = nil
          end
        end
        if sl.hop then sl.hop = sl.hop + dt; if sl.hop > 0.35 then sl.hop = nil end end
      end
    end

    if st.phase == "countdown" then
      local Dm = st.art and screen("demo")
      local go
      if Dm then
        go = Dm:finished(st.demoClip)
      else
        st.count = 3 - math.floor(st.t)
        go = st.t >= 3
      end
      if go then
        setPhase("play"); st.t = 0; host.playSe("SE_SUCCESS")
        -- the demo's Pokemon drop away; each comes back up when it asks
        for _, sl in ipairs(st.slots) do sl.stay = false end
      end
      return
    end

    if st.phase == "play" then
      if st.diff ~= "unlimited" then
        st.timer = st.timer - dt
        if st.timer <= 0 then st.timer = 0; finish(); return end
      elseif st.misses >= 3 then
        finish()
        return
      end
      -- how many ask at once follows the rotation (one, then two, then three); WHICH of
      -- the Pokemon rises is picked at random. The pick is made from every Pokemon not
      -- asking - one still dropping included, then it rises once it is down - because a
      -- pick among those already down was forced in quick play (the last two served still
      -- on their way down: 2 1 3 2 1 3 ...); the last asker only when there is no other.
      local asking = 0
      for i, sl in ipairs(st.slots) do
        if sl.visible and not sl.asking then
          -- up: it thinks of its berry, and its patience starts
          if (sl.lift or 0) >= 1 then
            sl.asking = true
            sl.shownAt = st.t
            bubble(i, sl.want, "open", "wait")
          end
        elseif sl.visible then
          sl.left = sl.left - dt
          if sl.left <= 0 then miss(i, true) end
        elseif (sl.lift or 0) <= 0 then
          -- the next one waits until the last has dropped out of sight
          sl.hideTimer = (sl.hideTimer or 0) - dt
        end
        if sl.visible or sl.queued then asking = asking + 1 end
      end
      if asking < st.rot.n then
        local hasMon = false
        for _, sl in ipairs(st.slots) do if sl.mon then hasMon = true end end
        local free, fresh = {}, {}
        for i, sl in ipairs(st.slots) do
          if not sl.visible and not sl.queued and (sl.mon or not hasMon) then
            free[#free + 1] = i
            if i ~= st.lastAsker then fresh[#fresh + 1] = i end
          end
        end
        local pool = #fresh > 0 and fresh or free
        if #pool > 0 then
          local i = pool[roll(1, #pool)]
          st.lastAsker = i
          st.slots[i].queued = true
        end
      end
      -- a picked Pokemon rises once it is down and rested
      for i, sl in ipairs(st.slots) do
        if sl.queued and not sl.visible and (sl.lift or 0) <= 0 and (sl.hideTimer or 0) <= 0 then
          sl.queued = false
          showSlot(i)
        end
      end
      local F = st.art and screen("front")
      if F then
        -- "Time Left: NN", larger and in from the corner as the game has it; red from 5
        -- seconds left with a beat
        -- each second. The game's timeup_anm reds it by vertex-colour tracks the text
        -- drawer does not read (and it collapses the message window p), so it is done here.
        F:set("4", "visible", true)
        F:set("2", "tx", TIMER.x - TIMER.w / 2 - 160)
        F:set("2", "ty", 120 - TIMER.y)
        local secs = math.ceil(st.timer)
        local hurry = not st.lives and secs <= 5
        local color = hurry and TIMER.red or TIMER.white
        local text
        if st.lives then
          text = ("%d / 3"):format(st.misses)
        else
          text = Games.line("berry", "timeLeft", { N = ("%02d"):format(secs) }, ("Time Left: %02d"):format(secs))
        end
        F:setText("2", text, { align = "right", valign = "center", color = color, scale = TIMER.scale })
        -- the beat: a swell as each second turns over, easing back within BEAT_S
        local beat = 1
        if hurry then
          local into = secs - st.timer
          beat = 1 + TIMER.beat * math.max(0, 1 - into / TIMER.BEAT_S) ^ 2
        end
        F:set("2", "sx", beat)
        F:set("2", "sy", beat)
      end
      s.game.hud = ("BERRY PICKER  %s   %d berries%s"):format(Games.DIFF_LABEL[st.diff], st.score,
        st.lives and ("   misses %d/3"):format(st.misses) or ("   %ds"):format(math.ceil(st.timer)))
      return
    end

    if not st.art then return end
    local Rr, F, Rn, Rw, Sc = screen("rear"), screen("front"), screen("rain"), screen("reward"), screen("score")
    if st.phase == "timeUp" then
      if F:finished("anm_timeUp") or st.pt > 2.2 then
        setPhase("rain")
        st.rainStep = 1
        Rn:play(RAIN[1])
        F:set("4", "visible", false)
        -- the top screen's card comes up and counts while it rains
        Sc:set("2h", "visible", true)
        for _, n in ipairs({ "4i", "4k", "4m", "4o", "4q" }) do Sc:set(n, "visible", false) end
        Sc:set("2u", "visible", false)
      end
    elseif st.phase == "rain" then
      -- up into the canopy, the berries rain, back down onto the heap
      local up = 0.5
      if Rn:finished(RAIN[st.rainStep]) and st.rainStep < #RAIN then
        st.rainStep = st.rainStep + 1
        Rn:play(RAIN[st.rainStep])
      end
      local rained = st.rainStep == #RAIN and Rn:finished(RAIN[#RAIN])
      if not st.downAt and rained then
        st.downAt = st.pt
        -- the heap: every berry picked, stacked on the ground (buildPile)
        st.pile = buildPile()
      end
      -- as far as the tree's canopy reaches (the 320x500 picture's top, 260 above the scene;
      -- a taller screen already shows D of it)
      local top = 260 - D
      if st.downAt then
        st.viewY = top * math.max(0, 1 - (st.pt - st.downAt) / up)
      else
        st.viewY = top * math.min(1, st.pt / up)
      end
      st.shown = math.floor((st.score or 0) * math.min(1, st.pt / 3) + 0.5)
      if st.downAt and st.pt - st.downAt > up + 1.0 then
        st.viewY = 0
        st.shown = st.score
        -- the card's stars, title and (a new best) the stamp
        st.cardDone = true
        setPhase("smoke")
        Rw:play("anm_smoke")
        if st.score > (st.best or 0) and st.score > 0 then
          Sc:set("4s", "visible", true)
          Sc:setText("4u", Games.line("berry", "stamp", nil, "HIGH SCORE"), { align = "center", valign = "center" })
          Sc:play("highsc_anime")
          Sc:setText("2o", tostring(st.score), { valign = "center", scale = HIGH_SCALE })
        end
      end
    elseif st.phase == "smoke" then
      -- under the smoke the heap goes and the Pokemon and the medallions come
      if st.pt > 0.2 and not st.revealed then
        st.revealed = true
        -- all three stand under the smoke, as the game reveals them
        for _, sl in ipairs(st.slots) do sl.stay, sl.lift = true, 1 end
        st.pile = nil
        layMedals()
        local n = st.result and #(st.result.puffs or {}) or 0
        frontWindow(Games.line("berry", n == 1 and "puffReceived" or "puffsReceived", nil, "Poké Puffs Received!"))
      end
      if st.pt > 2.4 then
        if st.result and st.result.unlockedNew and not st.saidRank then
          st.saidRank = true
          frontWindow(Games.line("berry", "nextRank", nil, "You can now access the next rank!"))
          st.pt = 0.4
        else
          F:play("window_close")
          setPhase("buttons")
        end
      end
    end
  end

  -- ------- drawing (scene units under scale(L), the scene D lower)

  local function drawMon(G2, i, sl, alpha)
    local pic = sl.pic
    if not (pic and pic.image) then return end
    local k = MON_H / (pic.h or 64)
    local hop = sl.hop and math.sin(sl.hop / 0.35 * math.pi) * 10 or 0
    -- below the screen's foot when down, eased into place as it rises
    local sink = (1 - (sl.lift or 0)) ^ 2 * MON_DROP
    G2.setColor(1, 1, 1, alpha or 1)
    -- facing the tree's middle
    local face = i == 1 and -1 or 1
    if i == 2 then face = 1 end
    drawPixel(pic.image, SPOT_X[i], MON_FOOT - hop + sink, 0, k * face, k, (pic.w or 64) / 2, pic.h or 64)
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
      -- the label at the game's size: about 15 units tall, white, from the pill's left
      G2.setFont(font)
      local k = 15 / font:getHeight()
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
  end

  local function drawNoArt(G2)
    G2.setColor(0.4, 0.75, 0.4, 1)
    G2.rectangle("fill", 0, -20, 320, LH + 40)
    G2.setColor(1, 1, 1, 1)
    G2.print("Berry Picker needs the game's art.", 20, 100, 0, 1 / L, 1 / L)
    G2.print(("Berries: %d"):format(st.score), 20, 130, 0, 1 / L, 1 / L)
  end

  function app:draw(G2, w, h)
    setShape(h)
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    if not st then return end
    G2.push()
    G2.translate(0, -bleed())
    G2.scale(L, L)
    if not st.art then drawNoArt(G2); G2.pop(); return end
    local Rr, F, N, B, Dm, Rn, Rw = screen("rear"), screen("front"), screen("nuts"), screen("balloon"),
      screen("demo"), screen("rain"), screen("reward")
    G2.push()
    G2.translate(0, D)
    -- the sky, clouds, grass and tree (risen with the view at the end)
    G2.push()
    G2.translate(0, st.viewY or 0)
    Rr:draw(G2)
    -- the heap on the ground, coming down with it (until the smoke takes it)
    if st.pile then drawPile(G2) end
    G2.pop()
    local phase = st.phase
    local scene = (st.viewY or 0) < 1 and phase ~= "rain"
    if scene then
      -- the Pokemon: all three for the demo and the end; in play the asking ones, rising
      -- and dropping (lift)
      for i, sl in ipairs(st.slots) do
        local show = phase == "countdown" or (phase == "smoke" and st.revealed) or phase == "buttons"
          or phase == "play" or phase == "timeUp"
        if show and (sl.lift or 0) > 0 then drawMon(G2, i, sl) end
      end
      B:draw(G2)
    end
    -- the berries on the tree (the demo has its own while it runs)
    if phase == "play" or phase == "timeUp" then
      for k = 1, #NUT do
        if k <= st.kinds then
          local tx, ty = treePos(k)
          N:set(NUT[k], "visible", true)
          local dragged = drag and drag.kind == k
          local lost = st.falling[k]
          local x, y = tx, ty
          if dragged then x, y = drag.x, drag.y elseif lost then x, y = lost.x, lost.y end
          N:set(NUT[k], "tx", x - 160)
          N:set(NUT[k], "ty", 120 - y)
          N:set(GHOST[k], "visible", (dragged or lost) and true or false)
          N:set(GHOST[k], "tx", tx - 160)
          N:set(GHOST[k], "ty", 120 - ty)
        else
          N:set(NUT[k], "visible", false)
          N:set(GHOST[k], "visible", false)
        end
      end
      N:draw(G2)
    elseif phase == "countdown" then
      Dm:draw(G2)
    end
    -- the rain until it has all landed. The clips park their berries at y -23 and let some
    -- peek in at y 14 before they drop to 265 (the game's 240 tall screen); a taller screen
    -- (and even the 3DS one, a little) would show them bunched at the top.
    -- Their heights are remapped so the parked and peeking ones sit above the visible top
    -- (-D) and the fall still leaves through the bottom: ty' = my * ty + dy, ty 106 -> above
    -- 140 + D, ty -145 -> below -140.
    if phase == "rain" and not st.downAt then
      if Rn.rainD ~= D then
        Rn.rainD = D
        local my = (280 + D) / 251
        local adj = {}
        for _, c in ipairs(Rn.L.root.children) do adj[c.name] = { my = my, dy = -140 + 145 * my } end
        Rn.adjust = adj
      end
      Rn:draw(G2)
    end
    if phase == "smoke" or phase == "buttons" then Rw:draw(G2) end
    G2.pop()
    -- the timer and the message window at the top; TIME'S UP and the counts with the scene
    if app.shapeDirty or F.shapeD ~= D then
      F.shapeD = D
      F.adjust = D > 0 and { o = { dy = -D }, ["7"] = { dy = -D } } or nil
      app.shapeDirty = false
    end
    F:draw(G2)
    if phase == "buttons" then
      G2.push()
      G2.translate(0, D)
      drawButton(G2, BUTTONS.again, Games.line("berry", "playAgain", nil, "Play Again"), false, font)
      drawButton(G2, BUTTONS.quit, Games.line("berry", "quit", nil, "Quit"), true, font)
      G2.pop()
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  -- ------- the top screen (session Layer.drawScene in a game hands it the playfield e,
  -- 240x160 units): score.bclyt, the canopy across it, the layout from its top

  -- the stars: 4i..4q are the five faint backdrops (the star texture under black vertex
  -- colours at alpha 60); the gold ones are 2u's palette pictures (white, full colour), five
  -- rows of a full and a half star per difficulty, moved onto the backdrops (the slots
  -- 2c..2g share their middles)
  local STARS = { "4i", "4k", "4m", "4o", "4q" }
  local STAR_TEX = { easy = "star_easy", normal = "star_normal", hard = "star_hard", unlimited = "star_infinite" }
  local STAR_ROW = {   -- [slot] = { [diff] = { full, half } }
    { easy = { "4", "6" }, hard = { "8", "a" }, unlimited = { "c", "e" }, normal = { "g", "i" } },
    { easy = { "1w", "1y" }, hard = { "20", "22" }, unlimited = { "24", "26" }, normal = { "28", "2a" } },
    { easy = { "1g", "1i" }, hard = { "1k", "1m" }, unlimited = { "1o", "1q" }, normal = { "1s", "1u" } },
    { easy = { "10", "12" }, hard = { "14", "16" }, unlimited = { "18", "1a" }, normal = { "1c", "1e" } },
    { easy = { "k", "m" }, hard = { "o", "q" }, unlimited = { "s", "u" }, normal = { "w", "y" } },
  }
  local DIGIT_PANES = { "33", "2z", "2x", "2v" }
  local DIGIT_ANCHORS = { [1] = { "3k" }, [2] = { "3h", "3i" }, [3] = { "3d", "3e", "3f" }, [4] = { "38", "39", "3a", "3b" } }

  -- put a pane's middle at (cx, cy) on the card (layout units, y down): its translation is
  -- set, its box measured, and the difference taken off (a pane's origin need not be its
  -- middle; the parents' own offsets come along)
  local function placeAt(Sc, name, cx, cy)
    local p = Sc.L.byName[name]
    if not p then return end
    Sc:set(name, "tx", cx - 200)
    Sc:set(name, "ty", 120 - cy)
    local bx, by, bw, bh = Sc:box(name)
    if not bx then return end
    local ex, ey = cx - (bx + bw / 2), cy - (by + bh / 2)
    Sc:set(name, "tx", cx - 200 + ex)
    Sc:set(name, "ty", 120 - cy - ey)
  end

  local function boxMiddle(Sc, name)
    local bx, by, bw, bh = Sc:box(name)
    if not bx then return nil end
    return bx + bw / 2, by + bh / 2, bw, bh
  end

  local function dressCard(Sc)
    local v = math.max(0, math.min(9999, st.shown or 0))
    local digits = tostring(v)
    local n = #digits
    local anchors = DIGIT_ANCHORS[n]
    -- the count sits in the middle of its tan box 3y (the anchors 3k... are 6 below it):
    -- the anchors' spacing, the group centred on the box
    local mx, my = boxMiddle(Sc, "3y")
    local sum = 0
    for j = 1, n do sum = sum + (boxMiddle(Sc, anchors[j]) or 0) end
    local shift = mx and (mx - sum / n) or 0
    for j, pane in ipairs(DIGIT_PANES) do
      if j <= n then
        local ax, ay = boxMiddle(Sc, anchors[j])
        Sc:set(pane, "visible", true)
        Sc:setImage(pane, Sc:image(digits:sub(j, j) .. ".bclim"))
        if ax then placeAt(Sc, pane, ax + shift, my or ay) end
      else
        Sc:set(pane, "visible", false)
      end
    end
    Sc:setText("2q", Games.line("berry", "count", nil, "Berries"), { align = "center", valign = "center" })
    local diff = STAR_TEX[st.diff] and st.diff or "easy"
    local tex = STAR_TEX[diff]
    local stars = st.cardDone and st.result and st.result.stars or 0
    -- all five backdrops, in the difficulty's shape, as the layout colours them
    for _, pane in ipairs(STARS) do
      Sc:set(pane, "visible", true)
      Sc:setImage(pane, Sc:image(tex .. ".bclim"))
    end
    for _, c in ipairs(Sc.L.byName["2u"].children) do
      if c.kind == "pic" then Sc:set(c.name, "visible", false) end
    end
    -- the gold ones over them, each the size of its backdrop, a half star where the count
    -- ends on one
    for j = 1, 5 do
      local full, half = stars >= j, stars >= j - 0.5
      if full or half then
        local name = STAR_ROW[j][diff][full and 1 or 2]
        local p = Sc.L.byName[name]
        local cx, cy, bw = boxMiddle(Sc, STARS[j])
        if p and cx then
          local k = p.w > 0 and bw / p.w or 1
          Sc:set(name, "visible", true)
          Sc:set(name, "sx", k)
          Sc:set(name, "sy", k)
          placeAt(Sc, name, cx, cy)
        end
      end
    end
    Sc:set("2u", "visible", st.cardDone or false)
    if st.cardDone and st.result then
      Sc:setText("0", st.result.title or "", { align = "center", valign = "center", color = { 90, 60, 40, 255 } })
    end
  end

  function app.drawTop(G2, e)
    if not (st and st.art) then return false end
    local Sc = screen("score")
    if not Sc then return false end
    e = e or { x = 0, y = 0, w = 240, h = 160 }
    -- the canopy across the whole playfield
    local bg = Sc:image("game01_bgDown.bclim")
    if bg then
      local iw, ih = bg:getDimensions()
      local k = math.max(e.w / iw, e.h / ih)
      G2.setColor(1, 1, 1, 1)
      G2.draw(bg, e.x + (e.w - iw * k) / 2, e.y + (e.h - ih * k) / 2, 0, k, k)
    end
    -- the HIGH SCORE bar keeps to the top; the RESULTS card (2h, its title 2u, the stamp 4s)
    -- is centred in the height
    local k = math.min(e.w / 400, e.h / 240)
    local off = math.max(0, (e.h / k - 240) / 2)
    if Sc.cardOff ~= off then
      Sc.cardOff = off
      Sc.adjust = off > 0 and { ["2h"] = { dy = -off }, ["2u"] = { dy = -off }, ["4s"] = { dy = -off } } or nil
    end
    if st.phase ~= "countdown" and st.phase ~= "play" then
      -- the digits are placed from their anchors' boxes in the card's own space
      local adjust = Sc.adjust
      Sc.adjust = nil
      dressCard(Sc)
      Sc.adjust = adjust
    end
    G2.push()
    G2.translate(e.x + (e.w - 400 * k) / 2, e.y)
    G2.scale(k, k)
    Sc:draw(G2)
    G2.pop()
    G2.setColor(1, 1, 1, 1)
    return true
  end

  -- ------- for the driver and tests

  function app.debugState() return st end
  app.screen = screen
  function app.tapPoint(what, i)
    if not st then return nil end
    if what == "berry" then return fromScene(treePos(i or 1)) end
    if what == "slot" then return fromScene(SPOT_X[i or 2], SPOT_Y) end
    if what == "again" then return fromScene(BUTTONS.again[1], BUTTONS.again[2]) end
    if what == "quit" then return fromScene(BUTTONS.quit[1], BUTTONS.quit[2]) end
    return nil
  end
  -- the berry a visible slot wants, for the driver to deliver right
  function app.wanted(i) local sl = st and st.slots[i]; return sl and sl.visible and sl.asking and sl.want or nil end

  function app:releaseAll() drag = nil end
  app.leave = app.releaseAll
  return app
end
