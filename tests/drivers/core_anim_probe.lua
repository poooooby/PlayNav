-- Driver: the Super Training home screen in motion. Opens Super Training, shoots the idle
-- loop (the Pokemon's sway and bob, the scrolling pattern), then lands a hit on the bag and
-- shoots the lunge, the bag's swing, the hit marks and the shake frame by frame, then the
-- resting pose and the wake-up (the app's
-- clock is stepped by hand, 1/30 s a shot, so the shots are the game's own frames).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/core_anim_probe.lua love .

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
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
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
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 10)
  end
  U.wait(30)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = "combined"
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local TR = X.training
  log("open:", TR.open())
  U.wait(10)
  local core = X.apps and X.apps:get("training_core")
  if not core then log("FAIL no core app"); return end
  -- hold the app's clock: freeze its update, step it by hand
  local update = core.update
  core.update = function() end
  local function step(frames)
    update(core, frames / 30)
    U.wait(2)
  end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  for i = 0, 9 do
    shot(("idle_%02d"):format(i))
    step(4)
  end
  TR.session.hitBag("tap")
  update(core, 0)
  for i = 0, 13 do
    shot(("hit_%02d"):format(i))
    step(1)
  end
  -- resting, then a tap: the wake-up clip
  TR.session.lieDown("idle")
  update(core, 0)
  for i = 0, 3 do
    shot(("rest_%02d"):format(i))
    step(10)
  end
  TR.session.wake()
  update(core, 0)
  for i = 0, 11 do
    shot(("wake_%02d"):format(i))
    step(4)
  end
  log("after wake: second wind", tostring(TR.session.state().secondWind), "next punch in",
    tostring((TR.session.state().nextAutoAt or 0) - TR.session.wall()))
  core.update = update
  TR.session.finish()
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
