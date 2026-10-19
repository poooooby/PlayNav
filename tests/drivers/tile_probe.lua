-- Driver: Tile Puzzle as the game plays it (Wooble's capture 2026-10-19): the whole picture
-- with the rule window and Begin, the shuffle, START!, a tile chosen (red corners), a swap in
-- flight, a tile landing home (stars), the scene at sunset and at night, the puzzle solved
-- (FINISHED!), the smoke and medallions, the buttons, the top screen's RESULTS card, View
-- Picture, then Quit back to petting. Shots at each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/tile_probe.lua love .
-- PROBE_SHAPE=gear|3ds picks the touch screen's shape (the option event only);
-- PROBE_DIFF=easy|normal|hard|unlimited the difficulty (easy).

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
  local function waitSecs(s)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < s do U.wait(1) end
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  -- CLEAR EXTRACTED ART may be on in the player's options: a driver run never acts on it
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
    Party.giveMon(s, C:require("species", "SPECIES_WURMPLE"), 5)
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display
  opts.display = "split"
  if os.getenv("PROBE_SHAPE") then
    loader.events:emit("mod.options_changed", { mod = "play_nav", key = "screen_shape", value = os.getenv("PROBE_SHAPE") })
    log("shape:", os.getenv("PROBE_SHAPE"), "W x H", tostring(X.W) .. "x" .. tostring(X.H))
  end
  local R, Apps, S = X.amie, X.apps, X.amie.session
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function press(id, ax, ay) local x, y = win(ax, ay); love.touchpressed(id, x, y, 0, 0, 1) end
  local function release(id, ax, ay) local x, y = win(ax, ay); love.touchreleased(id, x, y, 0, 0, 1) end
  local function tapAt(id, ax, ay)
    if not ax then log("no point for", id); return end
    press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(3)
  end

  local ok, err = pcall(function()
    local diff = os.getenv("PROBE_DIFF") or "easy"
    -- open every rank for the probe (the record is restored at the end)
    local rec = R.games and R.games.record and R.games.record("tile")
    local savedUnlocked = rec and rec.unlocked
    if rec then rec.unlocked = 4 end
    log("open play:", R.openPlay())
    U.wait(10)
    log("show games:", S.showGames())
    U.wait(10)
    log("start tile:", diff, S.startGame("tile", diff))
    local app = Apps:get("game_tile")
    local st = function() return app.debugState() end
    log("art:", tostring(st() and st().art))
    U.wait(20)
    shot("t01_intro")
    tapAt("begin", app.tapPoint("begin"))
    waitFor(function() local x = st(); return x.phase == "shuffle" and x.pt > 0.35 end, 60 * 30)
    shot("t02_shuffle")
    waitFor(function() local x = st(); return x.phase == "start" and x.pt > 0.4 end, 60 * 30)
    shot("t03_start")
    waitFor(function() return st().phase == "play" end, 60 * 30)
    U.wait(10)
    shot("t04_play")
    log("tiles:", st().pz.n, "correct at start:", st().pz.correct)
    -- one tile home: choose, swap mid-flight, the landing's stars
    local a, b = app.nextMove()
    tapAt("pick", app.tapPoint("tile", b))
    U.wait(4)
    shot("t05_selected")
    log("selected:", tostring(st().pz.sel))
    press("swap", app.tapPoint("tile", a))
    waitFor(function() local m = st().pz.moving[a]; return m and m.t > 0.12 end, 120)
    shot("t06_swap")
    local rx, ry = app.tapPoint("tile", a)
    release("swap", rx, ry)
    waitFor(function() return #st().pz.bursts > 0 end, 240)
    waitFor(function() local x = st().pz.bursts[1]; return not x or x.t > 0.2 end, 120)
    shot("t07_burst")
    log("correct after one:", st().pz.correct)
    -- the scene's light: sunset and night
    st().sceneT = 20.6
    U.wait(3)
    shot("t08_sunset")
    st().sceneT = 32
    U.wait(3)
    shot("t09_night")
    -- the rest, one tile at a time
    local moves = 0
    while st().phase == "play" and moves < 80 do
      local p, q = app.nextMove()
      if not p then break end
      waitFor(function() return not app.busy() end, 240)
      tapAt("m1", app.tapPoint("tile", q))
      tapAt("m2", app.tapPoint("tile", p))
      moves = moves + 1
      if moves == 6 then waitFor(function() return not app.busy() end, 240); shot("t10_halfway") end
    end
    log("moves:", moves)
    if diff == "unlimited" then
      -- NEXT!, the next puzzle (Normal) shuffling in, then the clock runs out
      waitFor(function() local x = st(); return x.phase == "next" and x.pt > 0.3 end, 60 * 30)
      shot("t10b_next")
      waitFor(function() local x = st(); return x.phase == "play" end, 60 * 30)
      U.wait(10)
      shot("t10c_second_puzzle")
      log("second puzzle:", st().pzDiff, st().pz.n, "tiles; timer", ("%.1f"):format(st().timer))
      st().timer = 0.05
    end
    waitFor(function() return st().phase == "finished" and st().pt > 0.4 end, 60 * 30)
    shot("t11_finished")
    log("time:", ("%.1f"):format(st().elapsed or 0), "puzzles:", st().puzzles)
    waitFor(function() local x = st(); return x.phase == "smoke" and x.pt > 0.15 end, 60 * 30)
    shot("t12_smoke")
    waitFor(function() local x = st(); return x.phase == "smoke" and x.pt > 1.4 end, 60 * 30)
    shot("t13_medals")
    waitFor(function() return st().phase == "buttons" end, 60 * 60)
    U.wait(20)
    shot("t14_buttons")
    local res = R.state() and R.state().lastResult
    log("result:", res and res.stars, res and res.title, res and #(res.puffs or {}), "rank", res and tostring(res.rank),
      "times", res and res.times and table.concat(res.times, ","))
    tapAt("view", app.tapPoint("view"))
    U.wait(10)
    shot("t15_view_picture")
    tapAt("back", app.tapPoint("view"))
    U.wait(10)
    log("after view: phase", st() and st().phase)
    tapAt("quit", app.tapPoint("quit"))
    U.wait(20)
    log("after Quit: mode", R.state() and R.state().mode, "app", Apps:active().id)
    shot("t16_petting")
    S.finish()
    U.wait(5)
    if rec then rec.unlocked = savedUnlocked end
  end)
  if not ok then log("probe body failed:", tostring(err)) end
  opts.display = savedDisplay
  log("DONE")
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
