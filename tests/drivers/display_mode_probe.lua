-- Driver: DISPLAY MODE K-GEAR against the installed Kanto Gear: NaviPlay's choice follows the
-- Gear's display_mode as the loader holds it, through each of the Gear's modes (set in memory
-- only, put back after; options.lua is never written).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/display_mode_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  X._test.keepArt()
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  -- a Gear disabled on this machine: its record counted as running for this run only
  local rec = loader.mods and loader.mods.kanto_gear
  local recState0 = rec and rec.state
  if rec and rec.state == "disabled" then
    log("kanto gear is disabled here: counted as running for the run")
    rec.state = "loaded"
  end
  local opts = loader.modOptions
  opts.play_nav = opts.play_nav or {}
  opts.kanto_gear = opts.kanto_gear or {}
  local display0, gear0 = opts.play_nav.display_mode, opts.kanto_gear.display_mode
  opts.play_nav.display_mode = "kanto_gear"
  log("raw: option", tostring(X._test.displayOption()), "gear", tostring(X._test.gearDisplay()),
    "rec", tostring(loader.mods and loader.mods.kanto_gear and loader.mods.kanto_gear.state))
  log("gear's own setting:", tostring(gear0), "-> NaviPlay", X._test.displayChoice())
  for _, m in ipairs({ "separate", "combined", "fullscreen", "phone" }) do
    opts.kanto_gear.display_mode = m
    U.wait(3)
    log("gear", m, "-> NaviPlay", X._test.displayChoice(), "mode now", tostring(X.state().mode))
  end
  opts.kanto_gear.display_mode = nil
  log("gear unset (its default) -> NaviPlay", X._test.displayChoice())
  opts.play_nav.display_mode, opts.kanto_gear.display_mode = display0, gear0
  if rec then rec.state = recState0 end
  log("restored:", tostring(opts.play_nav.display_mode), tostring(opts.kanto_gear.display_mode))
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
