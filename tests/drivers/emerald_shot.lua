-- Driver: boots Emerald (Gen 3) in a portrait window and exercises Pokemon-
-- Amie end to end with synthetic touches: the surface stays dormant in
-- the field, the START menu entry opens Amie, a won battle drops a puff,
-- NO resumes the field, a poisoned rematch is accepted and cleaned, cured,
-- petted and fed, DONE releases the field; then the second display.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/emerald_shot.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"

  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end

  log("driver started; phase:", game and game.phase)
  local shotW = tonumber(os.getenv("SHOT_W")) or 432
  local shotH = tonumber(os.getenv("SHOT_H")) or 768
  love.window.setMode(shotW, shotH, { resizable = true, highdpi = true })
  U.wait(2)

  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Stack3 = require("src.ui.game3.stack")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local function topId() local t = Stack3.top(); return t and t.id end

  local okMap, mapErr = pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  log("Map.load:", okMap, tostring(mapErr))
  local s = Runtime.getSession()
  if s then s.x, s.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
    -- the minigames need three healthy party members
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
    Party.giveMon(s, C:require("species", "SPECIES_WURMPLE"), 5)
  end
  U.wait(60)

  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then
    local ids = {}
    for id in pairs(loader and loader.mods or {}) do ids[#ids + 1] = id end
    log("FAIL play_nav exports missing; loaded mods:", table.concat(ids, ","))
    return
  end
  local R = X.amie
  local S = R.session
  local Apps = X.apps
  local function state() return X.state() end
  local function rectStr()
    local r = state().rect
    return r and ("%d,%d %dx%d @%s"):format(r.x, r.y, r.w, r.h, tostring(r.scale)) or "nil"
  end

  local shots = {}
  local function shot(name)
    local ok = U.shot(game, dir .. "/" .. name .. ".png")
    shots[#shots + 1] = (ok and "ok " or "MISSING ") .. name
    log("shot", name, ok and "ok" or "MISSING")
  end

  -- app-space -> window through the live rect (nil while dormant)
  local function win(ax, ay)
    local r = state().rect
    if not r then return -1, -1 end
    local tab = state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  -- DS_INPUT=mouse drives the surface with plain mouse events (no POKEPORT_TOUCH);
  -- DS_INPUT=mousewarp presses with an event but moves the real cursor only
  -- (no mousemoved event), which is what proves the per-frame mouse polling
  local inputMode = os.getenv("DS_INPUT") or "touch"
  local mouseMode = inputMode == "mouse" or inputMode == "mousewarp"
  log("input mode:", inputMode)
  -- the care phases must run on the window, not on a companion window a
  -- previous run may have left behind
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display = "split"
  -- PLAYNAV_HD=0 compares against the plain low-resolution path
  loader.modOptions.play_nav.hd_render = os.getenv("PLAYNAV_HD") ~= "0"
  local function press(id, ax, ay)
    local x, y = win(ax, ay)
    if mouseMode then
      if inputMode == "mousewarp" then love.mouse.setPosition(x, y) end
      love.mousepressed(x, y, 1, false)
    else
      love.touchpressed(id, x, y, 0, 0, 1)
    end
  end
  local function move(id, ax, ay)
    local x, y = win(ax, ay)
    if inputMode == "mousewarp" then love.mouse.setPosition(x, y)
    elseif mouseMode then love.mousemoved(x, y, 0, 0, false)
    else love.touchmoved(id, x, y, 0, 0, 1) end
  end
  local function release(id, ax, ay)
    local x, y = win(ax, ay)
    if mouseMode then
      if inputMode == "mousewarp" then love.mouse.setPosition(x, y) end
      love.mousereleased(x, y, 1, false)
    else
      love.touchreleased(id, x, y, 0, 0, 1)
    end
  end
  local function tapAt(id, ax, ay) press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(4) end

  -- ------- Alpha Sapphire art extraction (when the dump is linked into baseroms)
  if X.import then
    local I = X.import
    log("import check:", I.check(), "state:", I.state(), "lastError:", tostring(I.lastError()))
    local what = I.check()
    if what == "running" or what == "ready" then
      if what ~= "running" then I.start(); Apps:setActive("import", game) end
      local lastLogged = -1
      local shotMid = false
      for _ = 1, 60 * 60 * 5 do
        U.wait(1)
        local done, total = I.progress()
        if done ~= lastLogged and (done % 20 == 0 or done == total) then
          lastLogged = done
          log(("import progress %d / %d state %s"):format(done, total, I.state()))
        end
        if not shotMid and done >= 10 then shotMid = true; shot("00_import_progress") end
        if I.state() == "done" or I.state() == "failed" then break end
      end
      log("import finished:", I.state(), I.message())
      shot("00b_import_done")
    end
    local m = I.manifest()
    if m then
      local n, miss = 0, 0
      for _ in pairs(m.assets or {}) do n = n + 1 end
      for id, why in pairs(m.missing or {}) do miss = miss + 1; if miss <= 8 then log("  missing", id, why) end end
      log("cache manifest: version", m.version, "assets", n, "missing", miss)
      local okImg = X.assets and X.assets.image("hand/point") ~= nil
      log("assets.image(hand/point):", tostring(okImg), "ready:", tostring(X.assets and X.assets.ready()))
    end
    log("import check after run:", I.check())
  end

  -- ------- dormant in the field
  log("field: mode", state().mode, "rect", rectStr(), "surfaceWanted", tostring(X._test.surfaceWanted()))
  shot("01_field_dormant")

  -- ------- START menu entry opens Refresh
  U.tap(game, "start")
  U.wait(20)
  local StartMenu = require("src.ui.game3.start_menu")
  local idx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "play_nav_amie" then idx = i end end
  log("start menu open:", topId(), "AMIE entry at", tostring(idx), "cursor", StartMenu.cursor)
  if idx then
    local moves = idx - (StartMenu.cursor or 1)
    for _ = 1, math.abs(moves) do
      U.tap(game, moves > 0 and "down" or "up")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(30)
    local st = R.state()
    log("after menu AMIE: top", topId(), "session", st and st.phase, st and st.source,
      "mode", state().mode, "rect", rectStr())
    shot("02_menu_refresh")
    if st then
      -- the room: wait for a wander, tap the Pokemon, PLAY, BACK, CLOSE
      local home = Apps:get("home")
      U.wait(90)
      shot("02b_home_wander")
      -- a starving Pokemon takes the first tap as "I know"; the menu opens on the next
      local function openMenu(tag)
        for attempt = 1, 3 do
          local px, py = home.petPos()
          tapAt(tag .. attempt, px, py - 16)
          U.wait(8)
          if home.menuOpen() then return true end
        end
        log("menu did not open after three taps; message", tostring(R.state() and R.state().message))
        return false
      end
      openMenu("hpet")
      shot("02c_home_menu")
      local bx, by = home.buttonPos("play")
      tapAt("hplay", bx, by)
      U.wait(10)
      log("home PLAY: mode", R.state() and R.state().mode, "app", Apps:active().id)
      tapAt("hback", 225, 166)
      U.wait(10)
      log("play BACK: mode", R.state() and R.state().mode, "app", Apps:active().id)
      openMenu("hpet2")
      bx, by = home.buttonPos("switch")
      tapAt("hswitch", bx, by)
      U.wait(8)
      shot("02d_home_switch")
      tapAt("hswitchclose", 20, 60)
      U.wait(5)
      -- DECORATE: a cushion into the room, a wallpaper, a puff set out
      openMenu("hpet3")
      bx, by = home.buttonPos("decorate")
      tapAt("hdeco", bx, by)
      U.wait(8)
      log("decorate: mode", R.state() and R.state().mode, "app", Apps:active().id)
      local deco = Apps:get("decorate")
      local dg = deco.geometry()
      press("dcush", dg.slotX(1) + 17, dg.ROW.y + 20)
      for i = 1, 10 do move("dcush", dg.slotX(1) + 17 - i * 4, dg.ROW.y + 20 - i * 6); U.wait(1) end
      release("dcush", 60, 104)
      U.wait(5)
      tapAt("dtabwall", dg.tabX(1) + 20, dg.TAB.y + 6)
      U.wait(3)
      tapAt("dwall2", dg.slotX(2) + 17, dg.ROW.y + 16)
      U.wait(3)
      tapAt("dtabpuff", dg.tabX(4) + 20, dg.TAB.y + 6)
      U.wait(3)
      tapAt("dpuff", dg.slotX(1) + 17, dg.ROW.y + 16)
      U.wait(5)
      local room = R.store.room()
      log("decorate: items", #(room.items or {}), "wallpaper", room.wallpaper, "puff out", tostring(room.puffOut))
      shot("02e_decorate")
      tapAt("ddone", dg.DONE.x + 20, dg.DONE.y + 6)
      U.wait(8)
      log("decorate DONE: mode", R.state() and R.state().mode)
      -- visitors: a forced group leaves a gift; claim it
      local Vs = R.visitors
      local reqV = Vs.force(nil, { 200, 220, 255 })
      U.wait(5)
      log("visitors: gift set", tostring(reqV.set), "category", tostring(reqV.category), "pending", #Vs.pending())
      shot("02f_home_gift")
      local gx, gy = home.giftPos(#Vs.pending())
      tapAt("hgift", gx, gy)
      U.wait(8)
      log("gift claimed: message", tostring(R.state() and R.state().message), "pending", #Vs.pending(),
        "owned decor", R.decor.ownedCount(R.store.decor()))
      U.wait(60 * 3)
      shot("02g_home_decorated")
      tapAt("hclose", 225, 166)
      U.wait(10)
      log("after CLOSE from the room: top", topId(), "session", tostring(R.state()), "mode", state().mode)
    end
  else
    U.tap(game, "b")
    U.wait(10)
  end

  -- ------- battles through the engine's own battle API
  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local intent = 0
  local function prompt() local sn = bapi:snapshot(); return sn and sn.prompt, sn end
  local function runBattle()
    local okB, errB = pcall(function()
      local BattleBridge = require("src.core.game3.battle_bridge")
      local enc = { species = C:require("species", "SPECIES_ZIGZAGOON"), level = 3 }
      local ok, err = BattleBridge.startWild(Runtime._mod, game, enc, {})
      if not ok then error(tostring(err)) end
    end)
    if not okB then log("startWild failed:", tostring(errB)); return false end
    local ran = false
    for _ = 1, 1500 do
      U.wait(1)
      local p, sn = prompt()
      if p == "advance" then U.tap(game, "a"); U.wait(4)
      elseif p == "moves" then intent = intent + 1; bapi:submit({ id = intent, revision = sn.revision, kind = "back" })
      elseif p == "menu" and not ran then
        intent = intent + 1
        local ok, err = bapi:submit({ id = intent, revision = sn.revision, kind = "menu", choice = "run" })
        if ok then ran = true else log("run submit refused:", tostring(err)) end
      elseif not p and ran then
        return true
      end
    end
    log("battle did not finish; prompt:", tostring((prompt())))
    return false
  end

  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local puffsBefore = #R.puffs()
  local ok1 = runBattle()
  U.wait(30)
  log("battle 1 ran:", ok1, "amie layer after battle:", topId() == "play_nav_amie", "puffs", puffsBefore, "->", #R.puffs(),
    "mode", state().mode, "rect", rectStr())
  shot("03_after_battle")
  -- the close-up, straight from the exports (the START menu path was shot above)
  local openedPlay = R.openPlay()
  local prompted = waitFor(function() return topId() == "play_nav_amie" end, 300)
  log("openPlay:", openedPlay, "layer:", prompted, "phase:", R.state() and R.state().phase, "mode", state().mode)
  if prompted then
    U.wait(10)
    shot("04_play")
    -- the tray: ask the app where a tool sits
    local playApp = Apps:get("play")
    local function trayX(tool)
      local list = playApp.geometry.tools(S.session)
      for i, t in ipairs(list) do
        if t == tool then return playApp.geometry.trayX(list, i) + 18 end
      end
      return nil
    end
    local function tapTool(tool)
      local x = trayX(tool)
      if x then tapAt("rtool", x, 18) else log("tray has no", tool) end
    end
    if R.state().tool then tapTool(R.state().tool) end
    local affBefore = R.state().meters.affection
    press("pet", 100, 96)
    for i = 1, 80 do
      move("pet", 100 + (i % 30) * 2, 96 + math.sin(i / 5) * 5); U.wait(2)
    end
    shot("07_refresh_petting")
    release("pet", 128, 100)
    U.wait(5)
    log("petting: affection", affBefore, "->", R.state().meters.affection)
    local fullBefore = R.state().meters.fullness
    -- seed one of every variety so the row pages, page right and back,
    -- then drag the SECOND slot (Mint) onto the Pokemon
    local Rules = R.rules
    local jar = R.puffs()
    for _, p in ipairs(Rules.PUFFS) do Rules.jarAdd(jar, p.id) end
    local mintBefore = Rules.jarCount(jar, "puff/mint_basic")
    tapTool("beans")
    U.wait(3)
    shot("07b_refresh_puff_row")
    tapAt("rarrow", 227, 51)
    U.wait(3)
    shot("07c_refresh_puff_row_page2")
    tapAt("rarrow", 27, 51)
    U.wait(3)
    press("bean", 40 + 29 + 11, 40 + 11)
    for i = 1, 12 do move("bean", 80 + i * 4, 51 + i * 4); U.wait(1) end
    shot("08_refresh_bean_drag")
    -- hold the puff on the Pokemon: it is eaten bite by bite
    local bitesSeen = 0
    for _ = 1, 240 do
      U.wait(1)
      local f = R.state() and R.state().feeding
      if f and f.taken > bitesSeen then bitesSeen = f.taken; if bitesSeen == 1 then shot("08b_refresh_biting") end end
      if R.state() and not R.state().feeding and bitesSeen > 0 then break end
    end
    release("bean", 128, 100)
    U.wait(10)
    log("bean: fullness", fullBefore, "->", R.state().meters.fullness, "bites", bitesSeen, "jar", #jar,
      "mint", mintBefore, "->", Rules.jarCount(jar, "puff/mint_basic"), "message", tostring(R.state().message))
    for _, p in ipairs(Rules.PUFFS) do Rules.jarTake(jar, p.id) end
    -- petting by spot: Torchic likes its neck feathers (chest), not its head feathers;
    -- put the PUFFS tool down first, its row covers the head
    if R.state().tool then tapTool(R.state().tool) end
    U.wait(3)
    local m = R.state().meters
    m.enjoyment = 120
    local affSpot = m.affection
    press("spot", 128, 104)
    for i = 1, 40 do move("spot", 128 + (i % 10) * 3, 104 + (i % 6)); U.wait(2) end
    release("spot", 128, 104)
    U.wait(5)
    log("favored spot: affection", affSpot, "->", m.affection, "enjoyment", m.enjoyment, "message", tostring(R.state().message))
    local enjHead = m.enjoyment
    press("head", 128, 52)
    for i = 1, 40 do move("head", 128 + (i % 10) * 3, 52 + (i % 4)); U.wait(2) end
    release("head", 128, 52)
    U.wait(5)
    log("disfavored spot: enjoyment", enjHead, "->", m.enjoyment, "affection", m.affection)
    shot("08c_refresh_disfavored")
    -- a hit: two quick taps on the same place
    m.enjoyment = 50
    local enjHit = m.enjoyment
    tapAt("hit1", 120, 110); tapAt("hit2", 120, 110)
    U.wait(5)
    log("hit: enjoyment", enjHit, "->", m.enjoyment)
    -- ------- the minigames: picker, then each game for a few seconds
    tapTool("games")
    U.wait(8)
    log("games picker: mode", R.state() and R.state().mode, "app", Apps:active().id, "message", tostring(R.state() and R.state().message))
    shot("08d_games_picker")
    local geo = playApp.geometry
    -- the games run on the clock, the driver on frames: wait in seconds
    local function waitSecs(sec)
      local t0 = love.timer.getTime()
      while love.timer.getTime() - t0 < sec do U.wait(1) end
    end
    local function playGame(gameIndex, appId, value, shotName, midAction)
      if not geo then return end
      local br = geo.gameBadge(gameIndex)
      tapAt("gbadge", br.x + br.w / 2, br.y + br.h / 2)
      U.wait(3)
      local dr = geo.gameDiff(1)
      tapAt("gdiff", dr.x + dr.w / 2, dr.y + dr.h / 2)
      U.wait(5)
      local st0 = R.state()
      log(appId, "started: mode", st0 and st0.mode, "game", st0 and st0.game and st0.game.id, "app", Apps:active().id)
      local gapp = Apps:get(appId)
      local playing = waitFor(function() local g = gapp.debugState and gapp.debugState(); return g and g.phase == "play" end, 60 * 10)
      log(appId, "play phase reached:", playing)
      waitSecs(2)
      if midAction then midAction() end
      waitSecs(1.5)
      local g = gapp.debugState and gapp.debugState()
      log(appId, "mid-game: t", g and ("%.1f"):format(g.t), "score", g and g.score, "misses", g and g.misses,
        "combo", g and g.combo, "puzzles", g and g.puzzles, "correct", g and g.pz and g.pz.correct)
      shot(shotName)
      if gapp and gapp.forceEnd then gapp.forceEnd(value) end
      U.wait(5)
      local res = R.state() and R.state().lastResult
      log(appId, "result: stars", res and res.stars, "title", res and res.title, "puffs", res and #res.puffs,
        "unlocked", tostring(res and res.unlockedNew))
      shot(shotName .. "_result")
      waitSecs(1.2)
      tapAt("gcont", 128, 100)
      U.wait(8)
      log(appId, "after result: mode", R.state() and R.state().mode, "app", Apps:active().id)
    end
    playGame(1, "game_berry", 20, "08e_berry_picker", function()
      -- drag the first pile berry onto the middle Pokemon
      press("berry", 128 - 30, 40)
      for i = 1, 10 do move("berry", 128 - 30 + i * 3, 40 + i * 9); U.wait(1) end
      release("berry", 128, 130)
    end)
    playGame(2, "game_head", 45, "08f_head_it", function()
      -- tap the lane whenever a ball nears the sweet spot
      local happ = Apps:get("game_head")
      local t0 = love.timer.getTime()
      while love.timer.getTime() - t0 < 6 do
        local g = happ.debugState()
        local tapped = false
        for _, b in ipairs(g and g.balls or {}) do
          if not b.hit and b.y >= 96 and b.y <= 118 then
            tapAt("lane", 64 + (b.lane - 1) * 64, 140)
            tapped = true
            break
          end
        end
        if not tapped then U.wait(1) end
      end
    end)
    playGame(3, "game_tile", 25, "08g_tile_puzzle", function()
      tapAt("tile1", 28 + 20, 12 + 18)
      tapAt("tile2", 28 + 60, 12 + 18)
    end)
    shot("08h_games_picker_after")
    tapAt("gback", 225, 166)
    U.wait(8)
    log("back from the picker: mode", R.state() and R.state().mode, "app", Apps:active().id)
    shot("09_refresh_fed")
    tapAt("rdone", 225, 166)
    U.wait(10)
    local mons = loader.modSave.play_nav and loader.modSave.play_nav.mons
    local n = 0
    for _ in pairs(mons or {}) do n = n + 1 end
    log("after DONE: top", topId(), "session", tostring(R.state()), "mode", state().mode, "saved mons", n,
      "schema", tostring(loader.modSave.play_nav and loader.modSave.play_nav.schema))
    local x0 = Player.cellX
    U.hold(game, "right", 40)
    log("field live after refresh: cellX", x0, "->", Player.cellX)
    shot("10_after_refresh")
  end
  loader.modOptions.play_nav.prompt_always = false

  -- ------- affection benefits: the lead at 255 affection fights with attacks
  do
    local s4 = Runtime.getSession()
    local lead = s4 and s4.party and s4.party[1]
    if lead and R.benefits then
      local key = lead.personality .. ":" .. lead.otId
      local m = R.meters(key)
      m.affection = 255
      R.store.saveMons()
      local statsBefore = {}
      for k, v in pairs(R.benefits.stats) do statsBefore[k] = v end
      local okB, errB = pcall(function()
        local BattleBridge = require("src.core.game3.battle_bridge")
        local enc = { species = C:require("species", "SPECIES_ZIGZAGOON"), level = 2 }
        local ok, err = BattleBridge.startWild(Runtime._mod, game, enc, {})
        if not ok then error(tostring(err)) end
      end)
      if okB then
        local attacks = 0
        for _ = 1, 2500 do
          U.wait(1)
          local p, sn = prompt()
          if p == "advance" then U.tap(game, "a"); U.wait(3)
          elseif p == "menu" then
            intent = intent + 1
            bapi:submit({ id = intent, revision = sn.revision, kind = "menu", choice = "fight" })
          elseif p == "moves" then
            intent = intent + 1
            local okM, errM = bapi:submit({ id = intent, revision = sn.revision, kind = "move", slot = 1 })
            if okM then attacks = attacks + 1 elseif attacks == 0 then log("move submit refused:", tostring(errM)) end
          elseif p == "target" then
            intent = intent + 1
            local tid = sn.target and sn.target.battler or 1
            bapi:submit({ id = intent, revision = sn.revision, kind = "target", target = tid })
          elseif not p and attacks > 0 and not require("src.core.game3.battle").isActive() then
            break
          end
        end
        U.wait(30)
        if topId() == "play_nav_amie" then tapAt("bno", 136 + 48, 96 + 24); U.wait(10) end
        local st5 = R.benefits.stats
        log("benefits battle: attacks", attacks, "exp", statsBefore.exp, "->", st5.exp, "crit", statsBefore.crit, "->", st5.crit,
          "dodge", st5.dodge, "endure", st5.endure, "cure", st5.cure, "lead lv", lead.level, "hp", lead.hp)
        local c = R.benefits.calls or {}
        log(("benefits hooks reached: exp %d crit %d accuracy %d damage %d turn_ended %d"):format(
          c.exp or 0, c.crit or 0, c.accuracy or 0, c.damage or 0, c.turn or 0))
      else
        log("benefits battle failed to start:", tostring(errB))
      end
      m.affection = 0
      R.store.saveMons()
    end
  end

  -- ------- pinned on: landscape split and the second display
  loader.modOptions.play_nav.display = "auto"
  loader.modOptions.play_nav.surface = "always"
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(15)
  log("pinned landscape: mode", state().mode, "rect", rectStr())
  shot("11_landscape_pinned")
  love.window.setMode(shotW, shotH, { resizable = true, highdpi = true })
  U.wait(5)
  loader.modOptions.play_nav.display = "second_screen"
  U.wait(5)
  local SS = require("src.render.SecondScreen")
  local detected = waitFor(function() local ok, d = pcall(SS.detected); return ok and d end, 600)
  U.wait(30)
  log("second screen: mode", state().mode, "companion detected", detected,
    "frames pushed", X._test.state.pushAt > 0)
  shot("12_second_screen_main")
  loader.modOptions.play_nav.display = "auto"
  loader.modOptions.play_nav.surface = "when_needed"
  U.wait(5)
  log("released: mode", state().mode)

  log("summary:", table.concat(shots, "; "))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
