-- Driver: a pad's shoulders in a Super-Training regimen on the Game Boy games. The engine gives
-- them to GAME SPEED there (the Game Boy has no L / R); with a NaviPlay layer up they are L / R:
-- the right shoulder held raises the shield, and the game's speed setting is left as it was.
--   SHOT_DIR=<dir> POKEPORT_GAME=crystal POKEPORT_VERSION=crystal POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/gb_shoulder_probe.lua love .

local function body(game, log)
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
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if X and X._test and X._test.forceRom then X._test.forceRom(false) end
  local gen
  if game.world then
    gen = 2
    waitFor(function() return game.world and game.world.map end, 900)
  else
    gen = 1
    if not U.newGame(game) then log("FAIL no overworld"); return end
  end
  U.wait(30)
  X = game.mods.exports.play_nav
  local data = game.data
  local mon = gen == 1 and require("src.pokemon.Pokemon").new(data, "PIKACHU", 30)
    or require("src.battle.gen2.Mon").new(data, "CYNDAQUIL", 30)
  game.save.party = { mon }
  U.wait(10)
  local opts = gen == 2 and game.options or game.save.options
  local speed0 = opts and opts.speed
  -- a pad as LOVE hands it over: isGamepadDown answers false (no SELECT chord)
  local pad = { isGamepadDown = function() return false end, isGamepad = function() return true end }
  local function press(button) love.gamepadpressed(pad, button) end
  local function release(button) love.gamepadreleased(pad, button) end

  local TR = X.training
  TR.open()
  local T = TR.session
  waitFor(function() return T.session and T.session.mode == "core" and not T.session.trans end, 600)
  T.enterCourses()
  waitFor(function() return T.session.mode == "courses" and not T.session.trans end, 600)
  T.startCourse("lv1_hp")
  waitFor(function() return T.sim and T.sim.phase == "play" end, 60 * 40)
  U.wait(30)
  local sim = T.sim
  check(sim ~= nil and sim.phase == "play", "the regimen is playing")
  press("rightshoulder")
  U.wait(6)
  log(("shield with R held: %.2f"):format(sim.player.shield or 0))
  check((sim.player.shield or 0) > 0, "R held raises the shield")
  release("rightshoulder")
  U.wait(40)
  press("leftshoulder")
  U.wait(6)
  log(("shield with L held: %.2f (cooldown first: %.2f)"):format(sim.player.shield or 0, sim.player.shieldCd or 0))
  release("leftshoulder")
  U.wait(4)
  local speed1 = opts and opts.speed
  log("game speed before / after:", tostring(speed0), tostring(speed1))
  check(speed0 == speed1, "the shoulders left GAME SPEED alone")
  -- a face button still reaches the game through the layer: A fires
  local shots0 = #(sim.shots or {})
  press("a"); U.wait(2); release("a"); U.wait(4)
  log("A pressed through the layer; shots", shots0, "->", #(sim.shots or {}))
  TR.session.forceEnd({ clear = true, remaining = 50 })
  waitFor(function() return T.session.mode == "result" end, 60 * 30)
  TR.finish()
  U.wait(10)
  -- the field again: the shoulders are GAME SPEED once no layer of ours is up
  press("rightshoulder"); U.wait(2); release("rightshoulder"); U.wait(4)
  log("in the field, R: game speed", tostring(speed1), "->", tostring(opts and opts.speed))
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
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
