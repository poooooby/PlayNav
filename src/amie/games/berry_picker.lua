-- BERRY PICKER, played from the game's own screens (a/0/1/6: background_rear / _front,
-- nuts, balloon, demoanimation02, nuts_animation, reward on the touch screen, score on the
-- top screen; Wooble's capture "Berry Game.mp4", 2026-10-17). Up to three of the player's
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
  local MON_FOOT, MON_H = 236, 84                              -- a Pokemon's feet and height (the models')
  local BUBBLE_LIFT = 55                                       -- the bubble set above the spot's anchor

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

  local function activeSlots(n)
    if n == 1 then return { 2 } end
    if n == 2 then return { 1, 3 } end
    return { 1, 2, 3 }
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

  -- a want nobody else on screen is asking for (each kind has one bubble set)
  local function pickWant(exclude)
    for _ = 1, 20 do
      local k = math.random(1, st.kinds)
      local clash = false
      for _, sl in pairs(st.slots) do if sl.visible and sl.want == k and sl ~= exclude then clash = true end end
      if not clash then return k end
    end
    return math.random(1, st.kinds)
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

  local function showSlot(i)
    local sl = st.slots[i]
    sl.visible = true
    sl.want = pickWant(sl)
    sl.patience = patienceFor()
    sl.left = sl.patience
    sl.shownAt = st.t
    sl.hideTimer = 0
    bubble(i, sl.want, "open", "wait")
  end

  local function advanceRotation()
    st.servedInRot = st.servedInRot + 1
    if st.servedInRot >= st.rot.count and st.rotIndex < #st.rotation then
      st.rotIndex = st.rotIndex + 1
      st.rot = st.rotation[st.rotIndex]
      st.servedInRot = 0
      for i = 1, 3 do
        local sl = st.slots[i]
        if sl.visible then bubble(i, sl.want, "close") end
        sl.visible = false
        sl.hideTimer = 0.4
      end
    end
  end

  local function miss(i, timedOut)
    local sl = st.slots[i]
    bubble(i, sl.want, timedOut and "timeup" or "mistake", "close")
    sl.visible = false
    sl.hideTimer = 1.0
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
    for i, sl in ipairs(st.slots) do
      if sl.visible then bubble(i, sl.want, "timeup", "close") end
      sl.visible = false
    end
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
      served = 0, slots = {}, result = nil, best = Games.best and Games.best("berry", game.diff) or 0,
      viewY = 0, shown = 0 }
    st.rot = st.rotation[1]
    for i = 1, 3 do
      local mon = game.participants[i] and game.participants[i].mon
      st.slots[i] = { mon = mon, visible = false, hideTimer = 0.3 + i * 0.2,
        pic = mon and host.frontPic and host.frontPic(mon) or nil }
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
      Sc:setText("2m", Games.line("berry", "highScore", nil, "HIGH SCORE:"), { align = "right" })
      Sc:setText("2o", tostring(st.best or 0), { align = "right" })
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
        if (x - px) ^ 2 + (y - py) ^ 2 <= 24 ^ 2 then
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
      if ev.phase ~= "released" then return end
      for i, sl in ipairs(st.slots) do
        local hit
        if N then
          local bx, by, bw, bh = N:box(DROP[i])
          hit = bx and x >= bx and x <= bx + bw and y >= by and y <= by + bh
        else
          hit = math.abs(x - SPOT_X[i]) <= 45 and math.abs(y - SPOT_Y) <= 50
        end
        if sl.visible and hit then
          if sl.want == d.kind then
            local quick = (st.t - sl.shownAt) <= 1.5
            st.score = st.score + 1
            st.served = st.served + 1
            bubble(i, sl.want, quick and "right2" or "right1", "close")
            sl.visible = false
            sl.hideTimer = 0.5
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
    end
  end

  -- ------- update

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
    -- a bubble's clip ends: its next one (wait loops; close hides the set)
    if st.art then
      local B = screen("balloon")
      for _, sl in ipairs(st.slots) do
        local b = sl.bal
        if b and B:finished(b.clip) and b.after then
          local after = b.after
          b.after = nil
          if after == "wait" then
            b.clip = ("balloon_wait_%02d"):format(b.kind - 1)
            B:play(b.clip, { loop = true })
          elseif after == "close" then
            b.clip = ("balloon_close_%02d"):format(b.kind - 1)
            B:play(b.clip)
            b.after = "hide"
          end
        elseif b and b.after == "hide" and B:finished(b.clip) then
          B:set(SET[b.kind], "visible", false)
          sl.bal = nil
        end
        if sl.hop then sl.hop = sl.hop + dt; if sl.hop > 0.35 then sl.hop = nil end end
      end
    end

    if st.phase == "countdown" then
      local Dm = st.art and screen("demo")
      if Dm then
        if Dm:finished(st.demoClip) then setPhase("play"); st.t = 0; host.playSe("SE_SUCCESS") end
      else
        st.count = 3 - math.floor(st.t)
        if st.t >= 3 then setPhase("play"); st.t = 0; host.playSe("SE_SUCCESS") end
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
      local want = activeSlots(st.rot.n)
      local active = {}
      for _, i in ipairs(want) do active[i] = true end
      for i, sl in ipairs(st.slots) do
        sl.active = active[i] or false
        if active[i] then
          if sl.visible then
            sl.left = sl.left - dt
            if sl.left <= 0 then miss(i, true) end
          else
            sl.hideTimer = (sl.hideTimer or 0) - dt
            if sl.hideTimer <= 0 then showSlot(i) end
          end
        elseif sl.visible then
          bubble(i, sl.want, "close")
          sl.visible = false
        end
      end
      local F = st.art and screen("front")
      if F then
        F:set("4", "visible", true)
        local secs = math.ceil(st.timer)
        if st.lives then
          F:setText("2", ("%d / 3"):format(st.misses), { align = "right" })
        else
          F:setText("2", Games.line("berry", "timeLeft", { N = ("%02d"):format(secs) }, ("Time Left: %02d"):format(secs)), { align = "right" })
        end
        local hurry = not st.lives and st.timer <= 5
        if hurry ~= st.hurry then
          st.hurry = hurry
          F:play(hurry and "timeup_anm" or "time_anm", { loop = hurry })
        end
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
        -- the heap: its berries by difficulty (pile_level0..3 pick nuts_pile / 2 / 3), its
        -- size by the berries picked (the capture: 35 make a mound half the screen tall;
        -- about 75 fill it), standing on the ground
        local level = ({ easy = 0, normal = 1, hard = 2, unlimited = 3 })[st.diff] or 0
        local k = math.max(0.15, math.min(1, (st.score or 0) / 75))
        Rr:set("2", "visible", true)
        Rr:play("pile_level" .. level)
        Rr:set("2", "sx", k)
        Rr:set("2", "sy", k)
        Rr:set("2", "ty", 120 * k - 120)
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
          Sc:setText("2o", tostring(st.score), { align = "right" })
        end
      end
    elseif st.phase == "smoke" then
      -- under the smoke the heap goes and the Pokemon and the medallions come
      if st.pt > 0.2 and not st.revealed then
        st.revealed = true
        Rr:set("2", "visible", false)
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
    G2.setColor(1, 1, 1, alpha or 1)
    -- facing the tree's middle
    local face = i == 1 and -1 or 1
    if i == 2 then face = 1 end
    drawPixel(pic.image, SPOT_X[i], MON_FOOT - hop, 0, k * face, k, (pic.w or 64) / 2, pic.h or 64)
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
    G2.pop()
    local phase = st.phase
    local scene = (st.viewY or 0) < 1 and phase ~= "rain"
    if scene then
      -- the Pokemon: all three for the demo and the end, the asking ones in play
      for i, sl in ipairs(st.slots) do
        local show = phase == "countdown" or (phase == "smoke" and st.revealed) or phase == "buttons"
          or ((phase == "play" or phase == "timeUp") and sl.active)
        if show then drawMon(G2, i, sl) end
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
          local x, y = tx, ty
          if dragged then x, y = drag.x, drag.y end
          N:set(NUT[k], "tx", x - 160)
          N:set(NUT[k], "ty", 120 - y)
          N:set(GHOST[k], "visible", dragged or false)
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
    -- the rain until it has all landed (its last frame parks a row of berries up top)
    if phase == "rain" and not st.downAt then Rn:draw(G2) end
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

  local STARS = { "4i", "4k", "4m", "4o", "4q" }
  local STAR_TEX = { easy = "star_easy", normal = "star_normal", hard = "star_hard", unlimited = "star_infinite" }
  local DIGIT_PANES = { "33", "2z", "2x", "2v" }
  local DIGIT_ANCHORS = { [1] = { "3k" }, [2] = { "3h", "3i" }, [3] = { "3d", "3e", "3f" }, [4] = { "38", "39", "3a", "3b" } }

  local function dressCard(Sc)
    local v = math.max(0, math.min(9999, st.shown or 0))
    local digits = tostring(v)
    local n = #digits
    local anchors = DIGIT_ANCHORS[n]
    for j, pane in ipairs(DIGIT_PANES) do
      if j <= n then
        local bx, by, bw, bh = Sc:box(anchors[j])
        local d = digits:sub(j, j)
        Sc:set(pane, "visible", true)
        Sc:setImage(pane, Sc:image(d .. ".bclim"))
        Sc:set(pane, "tx", bx + bw / 2 - 200)
        Sc:set(pane, "ty", 120 - (by + bh / 2))
      else
        Sc:set(pane, "visible", false)
      end
    end
    Sc:setText("2q", Games.line("berry", "count", nil, "Berries"), { align = "center", valign = "center" })
    local tex = STAR_TEX[st.diff] or "star_easy"
    local stars = st.cardDone and st.result and st.result.stars or 0
    for j, pane in ipairs(STARS) do
      Sc:set(pane, "visible", true)
      local full, half = stars >= j, stars >= j - 0.5
      Sc:setImage(pane, Sc:image((half and not full) and (tex .. "h.bclim") or (tex .. ".bclim")))
      Sc:set(pane, "alpha", (full or half) and 255 or 60)
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
    if st.phase ~= "countdown" and st.phase ~= "play" then dressCard(Sc) end
    local k = math.min(e.w / 400, e.h / 240)
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
  function app.wanted(i) local sl = st and st.slots[i]; return sl and sl.visible and sl.want or nil end

  function app:releaseAll() drag = nil end
  app.leave = app.releaseAll
  return app
end
