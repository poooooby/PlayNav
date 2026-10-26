-- Driver: PlayNav on the Game Boy games (Gen 1 Red / Blue / Yellow, Gen 2 Gold / Silver /
-- Crystal). Boots, gives a party, then plays every feature through taps and the exports and
-- shoots each screen: the PLAYNAV menu from START, Super Training (home, a bag cleared - the
-- Stat Exp it writes - the drawer, the picker, a regimen and its results, the Konami alley and
-- a Special R), Pokemon-Amie (the room, PLAY, petting, a puff, each minigame), a battle's
-- after-effects. Logs the host, the profile, the stats, Stat Exp before / after, and every canvas
-- switched to while another was set by PlayNav (must be none: Android).
--   SHOT_DIR=<dir> POKEPORT_GAME=red POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/gb_probe.lua love .
--   (POKEPORT_GAME=crystal POKEPORT_VERSION=crystal for Gen 2; PROBE_FALLBACK=1 PlayNav's own
--   assets; PROBE_ONLY=training|amie|egg|menu)

local function body(game, log, dir)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local fails = 0
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log((ok and "ok   " or "FAIL ") .. what)
    return ok
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
  U.wait(2)

  -- nested canvases: setCanvas(c) while another canvas is set, from PlayNav's files. The ones
  -- inside the engine's own canvases (the captured game, the renderer's frame) are what Android
  -- breaks on; inside PlayNav's own touch screen they are as on Gen 3.
  local nested, nestedBy, inEngine = 0, {}, 0
  do
    local origSet, getC = love.graphics.setCanvas, love.graphics.getCanvas
    local GV = require("src.render.GameViewport")
    local Rd = require("src.render.Renderer")
    local function engineCanvas(c)
      return c ~= nil and (c == GV.canvas or c == Rd.canvas or c == Rd.presentCanvas or c == Rd.worldCanvas)
    end
    love.graphics.setCanvas = function(...)
      local outer = getC()
      if select("#", ...) > 0 and (...) ~= nil and outer ~= nil then
        local tb = debug.traceback("", 2)
        local file = tb:match("play_nav[/\\]([%w_/\\]+%.lua)")
        if file then
          nested = nested + 1
          local eng = engineCanvas(outer)
          if eng then inEngine = inEngine + 1 end
          local key = file .. (eng and " [in the engine's]" or "")
          nestedBy[key] = (nestedBy[key] or 0) + 1
        end
      end
      return origSet(...)
    end
  end
  local function nestedLog()
    local parts = {}
    for f, n in pairs(nestedBy) do parts[#parts + 1] = f .. " " .. n end
    table.sort(parts)
    log(("canvases set inside another by PlayNav: %d (%s)"):format(nested, #parts > 0 and table.concat(parts, ", ") or "none"))
  end

  local gen = game.save and game.save.player and game.world and 2 or nil
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if os.getenv("PROBE_FALLBACK") == "1" and X and X._test and X._test.forceRom then X._test.forceRom(false) end

  -- into the field
  if game.world then
    gen = 2
    waitFor(function() return game.world and game.world.map end, 900)
  else
    gen = 1
    if not U.newGame(game) then log("FAIL no overworld"); return end
  end
  U.wait(30)
  X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local loader = game.mods
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = os.getenv("PROBE_DISPLAY") or "combined"
  if X._test.forceRom and os.getenv("PROBE_FALLBACK") ~= "1" and X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local host = X._test.refreshHost()
  local th = X.training and X.training.host
  log("gen", gen, "host", host and host.name, "version", tostring(host and host.profile and host.profile.version),
    "family", tostring(th and th.songFamily and th.songFamily()))

  -- a party
  local data = game.data
  local function newMon(species, level)
    if gen == 1 then return require("src.pokemon.Pokemon").new(data, species, level) end
    return require("src.battle.gen2.Mon").new(data, species, level)
  end
  if #(game.save.party or {}) == 0 or os.getenv("PROBE_PARTY") ~= "keep" then
    local lead = gen == 1 and "PIKACHU" or "CYNDAQUIL"
    game.save.party = { newMon(lead, 20), newMon(gen == 1 and "BULBASAUR" or "TOTODILE", 12), newMon("PIDGEY", 8) }
  end
  if gen == 1 then game.save.money = 200000 else game.save.player.money = 200000 end
  U.wait(10)
  local mon = game.save.party[1]
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function tapAt(id, ax, ay)
    local x, y = win(ax, ay)
    love.touchpressed(id, x, y, 0, 0, 1); U.wait(2); love.touchreleased(id, x, y, 0, 0, 1); U.wait(3)
  end
  local function tapRect(r) tapAt("probe", r.x + r.w / 2, r.y + r.h / 2) end
  local only = os.getenv("PROBE_ONLY")
  local function want(part) return only == nil or only == part end

  -- the PLAYNAV entry in START
  if want("menu") then
    U.tap(game, "start"); U.wait(20)
    local top = game.stack:top()
    local items = top and (top.items or (top.menu and top.menu.items)) or {}
    local found = false
    for _, e in ipairs(items) do if type(e) == "table" and e.label == "PLAYNAV" then found = true end end
    check(found, "START lists PLAYNAV")
    shot("m01_start_menu")
    U.tap(game, "b"); U.wait(20)
    if game.stack:top() and game.stack:top().screenId then U.tap(game, "b"); U.wait(10) end
    check(X.menu.open() ~= false, "the PlayNav menu opens")
    U.wait(40)
    shot("m02_playnav_menu")
    X.menu.close()
    U.wait(10)
  end

  -- ------- Super Training
  local TR = X.training
  local Rules = TR.rules
  log("stats trained:", table.concat(Rules.STATS, " "), "total cap", tostring(Rules.EV_TOTAL), "max", Rules.evTotalMax())
  if want("training") or want("egg") then
    -- the Stat Exp mapping
    local se0 = {}
    for k, v in pairs(mon.statExp or {}) do se0[k] = v end
    local evs = th.evsOf(mon)
    Rules.addEv(evs, "spa", 12)
    Rules.addEv(evs, "atk", 252)
    th.setEvs(mon, evs)
    log(("Stat Exp after +12 Sp. Atk, +252 Attack: special %s, attack %s (was %s / %s)"):format(
      tostring(mon.statExp.special), tostring(mon.statExp.attack), tostring(se0.special), tostring(se0.attack)))
    check(mon.statExp.special == 144 and mon.statExp.attack == 63504, "Special 12 -> Stat Exp 144, Attack 252 -> 63504")
    local back = th.evsOf(mon)
    check(back.spc == 12 and back.spa == 12 and back.spd == 12 and back.atk == 252, "read back as EVs 12 / 252")
    -- an odd Stat Exp (a battle's) is kept when a write leaves its EV alone
    mon.statExp.defense = 1000
    evs = th.evsOf(mon)
    Rules.addEv(evs, "hp", 4)
    th.setEvs(mon, evs)
    check(mon.statExp.defense == 1000, "an untouched stat keeps its Stat Exp (1000)")
    th.setEvs(mon, { hp = 0, atk = 0, def = 0, spe = 0, spc = 0 })

    check(TR.open() ~= false, "Super Training opens")
    local T = TR.session
    waitFor(function() return T.session and T.session.mode == "core" and not T.session.trans end, 600)
    U.wait(60)
    shot("t01_home")
    local s = T.session
    local core = X.apps:get("training_core")
    local drawer = X.apps:get("training_bags")
    -- a Special bag M from the drawer: +4 Special (Stat Exp 16)
    local bags = TR.store.bags()
    for i = #bags, 1, -1 do table.remove(bags, i) end
    bags[1] = "spc_m"
    tapRect(core.geometry().BAGS)
    waitFor(function() return s.mode == "bags" end, 300)
    U.wait(30)
    shot("t02_drawer")
    local g = drawer.geometry()
    tapRect(g.slotRect(1)); U.wait(8)
    tapRect(g.button(1, 3)); U.wait(8)
    tapRect(g.button(1, 2)); U.wait(8)
    waitFor(function() return s.mode == "core" end, 600)
    U.wait(20)
    check(s.rec.bag and s.rec.bag.id == "spc_m", "the Special Bag M hangs")
    s.rec.secondWind, s.rec.resting = nil, nil
    local taps = 0
    while s.rec.bag and taps < 120 do
      waitFor(function() return (s.anim.lock or 0) <= 0 and not s.anim.finish end, 600)
      tapRect(core.geometry().BAG)
      taps = taps + 1
    end
    waitFor(function() return s.anim.finish and s.anim.finish.t > 1.2 end, 600)
    shot("t03_finish")
    waitFor(function() return not s.anim.finish end, 3000)
    U.wait(20)
    log(("Special Bag M: %d taps, Stat Exp special %s, EVs spc %d"):format(taps, tostring(mon.statExp.special), th.evsOf(mon).spc))
    check(mon.statExp.special == 16, "the bag wrote Special Stat Exp 16 (+4 EVs)")
    shot("t04_home_after")
    -- no total cap: every stat to 252 is Fully Trained
    th.setEvs(mon, { hp = 252, atk = 252, def = 252, spe = 252, spc = 251 })
    check(not Rules.isFullyTrained(th.evsOf(mon)), "251 Special: not Fully Trained")
    check(Rules.statRoom(th.evsOf(mon), "spd") == 1, "room for 1 more Special (no 510 total)")
    th.setEvs(mon, { hp = 252, atk = 252, def = 252, spe = 252, spc = 252 })
    check(Rules.isFullyTrained(th.evsOf(mon)), "all five at 252: Fully Trained")
    check(mon.statExp.special == 63504, "Special Stat Exp 63504")
    th.setEvs(mon, { hp = 0, atk = 0, def = 0, spe = 0, spc = 0 })
    T.refreshMon()

    if want("training") then
      -- the picker and a regimen
      T.enterCourses()
      waitFor(function() return s.mode == "courses" and not s.trans end, 600)
      U.wait(30)
      shot("t05_picker")
      log("start course:", tostring(T.startCourse("lv1_spa")))
      waitFor(function() return s.mode == "regimen" and T.sim and T.sim.phase == "play" end, 60 * 40)
      U.wait(60)
      log("top screen hd:", tostring(X.hdTop and X.hdTop.why), "mode", X.state().mode, "rect", X.state().rect and "yes" or "no")
      shot("t06_regimen")
      log("forcing the end")
      T.forceEnd({ clear = true, remaining = 50 })
      log("result reached:", tostring(waitFor(function() return s.mode == "result" end, 60 * 30)), s.mode)
      U.wait(120)
      log("shooting results")
      shot("t07_results")
      log(("after the regimen: EVs %s, Stat Exp special %s"):format(
        tostring(th.evsOf(mon).spc), tostring(mon.statExp.special)))
      check(th.evsOf(mon).spc > 0, "a Sp. Atk regimen trained Special")
      for _ = 1, 12 do if s.mode ~= "result" then break end; T.resultNext(); U.wait(40) end
      waitFor(function() return s.mode == "courses" and not s.trans end, 60 * 10)
      T.goTo("core")
      waitFor(function() return s.mode == "core" and not s.trans end, 600)
      U.wait(20)
    end

    if want("egg") or only == nil then
      for _, b in ipairs(T.rocket.KONAMI) do U.tap(game, b); U.wait(4) end
      U.wait(4)
      check(T.rocketBusy(), "the code plays the R's unlock")
      check(not (game.stack:top() and (game.stack:top().screenId == "StartMenu" or game.stack:top().screenId == "Gen2StartMenu")),
        "the code's START menu closed")
      waitFor(function() return not T.rocketBusy() end, 3000)
      T.goTo("rocket")
      waitFor(function() return s.mode == "rocket" and not s.trans end, 3000)
      U.wait(20)
      for _ = 1, 6 do T.rocketTap("advance"); U.wait(30) end
      waitFor(function() return s.rocket and s.rocket.phase == "shop" end, 3000)
      U.wait(30)
      shot("e01_shop")
      local list = T.rocket.STOCK
      log("the shop:", table.concat(list, " "))
      check(#list == 10, "ten bags on sale (five stats x R / R+)")
      local idx
      for i, id in ipairs(list) do if id == "spc_r" then idx = i end end
      local n0 = #TR.store.bags()
      if idx then
        T.rocketTap("row", idx); U.wait(5)
        T.rocketTap("row", idx); U.wait(20)
        T.rocketTap("yes"); U.wait(30)
      end
      check(#TR.store.bags() == n0 + 1, "a Special Bag R bought")
      shot("e02_bought")
      T.rocketTap("back"); U.wait(20); T.rocketTap("advance")
      waitFor(function() return s.mode == "core" and not s.trans end, 3000)
    end
    TR.finish()
    U.wait(20)
  end

  -- ------- Pokemon-Amie
  if want("amie") then
    local A = X.amie
    check(A.open() ~= false, "Pokemon-Amie opens")
    U.wait(90)
    shot("a01_room")
    A.session.enterPlay()
    U.wait(120)
    shot("a02_play")
    local play = X.apps:get("play")
    if play and play.tapPoint then tapAt("probe", play.tapPoint("pet")); U.wait(60) end
    shot("a03_awake")
    for _, id in ipairs({ "berry", "head", "tile" }) do
      local ok = A.session.startGame and A.session.startGame(id, "easy")
      U.wait(200)
      shot("a04_game_" .. id)
      log("game", id, tostring(ok))
      local gapp = X.apps:get("game_" .. id)
      if gapp and gapp.quit then pcall(gapp.quit, gapp) end
      U.wait(60)
    end
    A.session.finish()
    U.wait(30)
  end

  nestedLog()
  check(inEngine == 0, ("no canvas set by PlayNav inside the engine's (%d)"):format(inEngine))
  log(("%d failures"):format(fails))
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
  local ok, err = xpcall(function() body(game, log, dir) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
