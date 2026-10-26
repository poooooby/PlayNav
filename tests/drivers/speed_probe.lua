-- Driver: Super Training's regimens at 1X whatever GAME SPEED is. The engine's speed lookup
-- is stood in for (4X, the player's options untouched): the logic speed is read on Core
-- Training, the picker, through a regimen (its fade, the play, the outro), the results and
-- back; and the regimen's own clock is timed against the wall clock while it plays.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/speed_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
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
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local TR = X.training

  -- GAME SPEED 4X, as the player's option would give it (the instance's lookup only)
  local resolve0 = game._resolveLogicSpeed
  local SPEED = tonumber(os.getenv("PROBE_SPEED")) or 4
  game._resolveLogicSpeed = function() return SPEED end
  game.speedOverride = nil
  local function speed(where) log(("%-34s logic speed %s"):format(where, tostring(game:logicSpeed()))) end

  local ok, err = pcall(function()
    speed("field (4X stands in)")
    log("training open:", tostring(TR.open()))
    U.wait(20)
    speed("Core Training")
    TR.session.enterCourses()
    U.wait(20)
    speed("the regimen picker")
    log("start course:", tostring(TR.session.startCourse("lv1_hp")))
    U.wait(5)
    speed("the fade into the regimen")
    waitFor(function() return TR.state().mode == "regimen" end, 900)
    speed("the regimen")
    -- the regimen's clock against the wall clock while it plays
    waitFor(function() local sim = TR.session.sim; return sim and sim.phase == "play" end, 60 * 60)
    local sim = TR.session.sim
    local r0, t0 = sim and sim.remaining, love.timer.getTime()
    waitSecs(3)
    local r1, t1 = sim and sim.remaining, love.timer.getTime()
    if r0 and r1 then
      log(("regimen clock: %.2f s in %.2f s of wall time (x%.2f)"):format(r0 - r1, t1 - t0, (r0 - r1) / (t1 - t0)))
    end
    speed("the regimen, playing")
    TR.session.forceEnd({ clear = true, remaining = sim and sim.remaining })
    waitFor(function() return TR.state().mode == "result" end, 60 * 30)
    speed("the results")
    TR.finish()
    U.wait(20)
    speed("closed, back in the field")
    -- the easter egg (src/training/rocket.lua): the R's unlock, the way in, the alley, the way out
    local T = TR.session
    log("training open again:", tostring(TR.open()))
    U.wait(20)
    speed("Core Training again")
    for _, b in ipairs(T.rocket.KONAMI) do U.tap(game, b); U.wait(4) end
    U.wait(2)
    log("unlock playing:", tostring(T.rocketBusy()))
    speed("the R's unlock")
    waitFor(function() return not T.rocketBusy() end, 3000)
    U.wait(5)
    speed("home, after the unlock")
    T.goTo("rocket")
    U.wait(5)
    speed("the fade into the alley")
    waitFor(function() return T.session.mode == "rocket" and not T.session.trans end, 3000)
    speed("the alley")
    -- the alley's clock against the wall clock (compare a PROBE_SPEED=1 run: the same ratio)
    local st0, w0 = T.rocket.state().clock, love.timer.getTime()
    waitSecs(2)
    local st1, w1 = T.rocket.state().clock, love.timer.getTime()
    log(("alley clock: %.2f s in %.2f s of wall time (x%.2f)"):format(st1 - st0, w1 - w0, (st1 - st0) / (w1 - w0)))
    T.rocketTap("advance"); U.wait(2); T.rocketTap("advance"); T.rocketTap("advance"); U.wait(5)
    T.rocketTap("back"); U.wait(2); T.rocketTap("back")
    U.wait(3)
    speed("the fade out of the alley")
    waitFor(function() return T.session.mode == "core" and not T.session.trans end, 3000)
    U.wait(5)
    speed("home again")
    TR.finish()
  end)
  if not ok then log("ERROR", tostring(err)) end
  game._resolveLogicSpeed = resolve0
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
