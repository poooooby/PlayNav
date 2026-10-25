-- Driver: the regimen picker's CONTROLS button and the controls it shows on the top screen
-- (courses_app drawControls), in 2D and with 3D SUPER TRAINING on (the right stick's in / out).
--   SHOT_DIR=<dir> [SHOT_W=1920 SHOT_H=1080] POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_TOUCH=1 POKEPORT_DRIVER=mods/play_nav/tests/drivers/controls_probe.lua love .

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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if os.getenv("PROBE_FALLBACK") == "1" and X and X._test and X._test.forceRom then X._test.forceRom(false) end
  if os.getenv("SHOT_W") then
    love.window.setMode(tonumber(os.getenv("SHOT_W")), tonumber(os.getenv("SHOT_H")) or 1080, { resizable = true, highdpi = true })
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
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local ok, err = pcall(function()
    TR.open()
    U.wait(20)
    TR.session.enterCourses()
    U.wait(30)
    local app = TR.session.coursesApp or (TR.apps and TR.apps.courses)
    shot("c01_picker")
    -- the button: a tap toggles the controls on
    local S = TR.session.session
    if app and app.toggleControls then app.toggleControls(true) elseif S then S.showControls = true end
    U.wait(10)
    log("controls shown", S and S.showControls and "yes" or "no")
    shot("c02_controls_2d")
    local Draw = TR.session.arenaDraw
    if Draw then Draw.mode3d = true end
    U.wait(10)
    shot("c03_controls_3d")
    -- B closes them first
    U.hold(game, "b", 2)
    U.wait(10)
    log("after B: controls", S and S.showControls and "shown" or "hidden", "mode", TR.state().mode)
    -- the button lit, then a regimen picked: the controls close
    if S then S.showControls = true end
    U.wait(6)
    shot("c04_button_on")
    -- (A picks the first regimen, as a tap on it would: the picker's own pad handler)
    local T = TR.session
    if T.pickerInput then T.pickerInput({ wasPressed = function(_, b) return b == "a" end, isDown = function() return false end }) end
    U.wait(8)
    log("after a regimen picked:", S and S.picked or "-", "controls", S and S.showControls and "shown" or "hidden")
  end)
  if not ok then log("ERROR", tostring(err)) end
  pcall(TR.finish)
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
