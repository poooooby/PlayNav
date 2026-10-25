-- Driver: PLAY for a list of species, each awake with its mouth marked (play.lua app.debugMouth:
-- where a held Poke Puff is eaten, from data/amie_mouths.lua), one shot each; the touch screen's
-- rect is logged for cropping. PROBE_LIST=NAME,NAME,... (SPECIES_ names), PROBE_FALLBACK=1 PlayNav's
-- own art.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/mouth_probe.lua love .

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
  if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  if os.getenv("PROBE_FALLBACK") == "1" and Xk and Xk._test and Xk._test.forceRom then Xk._test.forceRom(false) end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s0 = Runtime.getSession()
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local loader = game.mods
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display_mode
  opts.display_mode = "combined"
  local R, Apps = X.amie, X.apps
  local list = os.getenv("PROBE_LIST") or "CHARMANDER,SQUIRTLE,PIDGEY,PIKACHU,SHUCKLE,AGGRON,LATIAS,WAILMER,LUCARIO,GRENINJA,SPRIGATITO,HYDREIGON"
  local ok, err = pcall(function()
    for name in list:gmatch("[^,]+") do
      local okS, sp = pcall(C.require, C, "species", "SPECIES_" .. name)
      if not okS then
        log("no species", name)
      else
        s0.party = {}
        Party.giveMon(s0, sp, 30)
        log(name, "open play:", R.openPlay())
        U.wait(10)
        local app = Apps:get("play")
        app.debugMouth = true
        -- awake: A wakes it (PLAY's pad), then wait out the "!" and the flash
        waitFor(function() return app.state().wake == "asleep" end, 300)
        for _ = 1, 3 do
          if app.state().wake ~= "asleep" then break end
          U.tap(game, "a"); U.wait(10)
        end
        local r = X.state().rect
        if r then log(("  touch screen rect %d %d %d %d"):format(r.x, r.y, r.w or 0, r.h or 0)) end
        waitFor(function() return app.state().wake == "awake" end, 1500)
        log("  wake:", app.state().wake)
        local t = love.timer.getTime()
        while love.timer.getTime() - t < 4 do U.wait(1) end
        log("  shot", name, U.shot(game, dir .. "/m_" .. name .. ".png") and "ok" or "MISSING")
        app.debugMouth = nil
        pcall(R.session.finish)
        U.wait(20)
      end
    end
  end)
  if not ok then log("probe body failed:", tostring(err)) end
  opts.display_mode = savedDisplay
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
