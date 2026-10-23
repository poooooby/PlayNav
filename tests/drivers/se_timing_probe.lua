-- Driver: how long the engine takes to start each of the game's effects Super Training uses as
-- stand-ins (src/training/regimen.lua SE, the results' SE_SUCCESS / SE_FAILURE), twice each: a
-- stall there freezes the regimen on that event.
--   SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/se_timing_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  waitFor(function() return game.phase == "field" end, 1200)
  U.wait(30)
  local host = X._test.trainingHost()
  -- PlayNav's own effects through Super Training's player (the press, the charging hum, the
  -- shots), the first time and again
  local T = X.training and X.training.session
  for round = 1, 2 do
    for _, ev in ipairs({ "press", "charging", "shot", "charged_shot", "goal_hit", "attack_warn", "ball_flight" }) do
      local t0 = love.timer.getTime()
      local ok, h = pcall(T.playSe, ev)
      local dt = love.timer.getTime() - t0
      if ok and type(h) == "table" and h.stop then h.stop() end
      log(("own round %d %-14s %.1f ms ok %s"):format(round, ev, dt * 1000, tostring(ok)))
      U.wait(10)
    end
  end
  for _, k in ipairs({ "hurt", "strong", "big" }) do
    local Hh = X.haptics
    local t0 = love.timer.getTime()
    if Hh then pcall(Hh.pattern or Hh.pulse, k) end
    log(("haptic %-8s %.1f ms"):format(k, (love.timer.getTime() - t0) * 1000))
  end
  local names = { "SE_NOT_EFFECTIVE", "SE_EXP", "SE_BALL_BOUNCE_1", "SE_BALL_BOUNCE_2", "SE_SUCCESS",
    "SE_FAILURE", "SE_SELECT" }
  for round = 1, 2 do
    for _, n in ipairs(names) do
      local t0 = love.timer.getTime()
      local ok, r = pcall(host.playSe, n)
      local dt = love.timer.getTime() - t0
      -- the frames after it: a stall may come on the next update rather than in the call
      local t1 = love.timer.getTime()
      U.wait(3)
      local after = love.timer.getTime() - t1
      log(("round %d %-18s call %.1f ms, next 3 frames %.1f ms, ok %s %s"):format(round, n, dt * 1000, after * 1000,
        tostring(ok), tostring(r)))
      U.wait(20)
    end
  end
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
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
