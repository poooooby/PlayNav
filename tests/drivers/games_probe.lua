-- Driver: boots Emerald, opens the Amie room from the START menu, goes to
-- play, opens the minigame picker and starts Berry Picker, then logs the
-- game's internal clock for a few seconds. A quick probe for the game loop.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/games_probe.lua love .

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
  love.window.setMode(432, 768, { resizable = true, highdpi = true })
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
  local R, Apps, S = X.amie, X.apps, X.amie.session
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display = "split"
  -- wait out the import if it is running
  if X.import then waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120) end
  log("open play:", R.openPlay())
  U.wait(10)
  log("enter games:", S.enterGames())
  U.wait(10)
  log("start berry:", S.startGame("berry", "easy"))
  local app = Apps:get("game_berry")
  local t0 = love.timer.getTime()
  for i = 1, 12 do
    U.wait(30)
    local st = app.debugState()
    log(("probe %d: wall %.2f  phase %s  t %.2f  count %s  live %s  active %s  mode %s  surfaceMode %s"):format(
      i, love.timer.getTime() - t0, st and st.phase, st and st.t or -1, tostring(st and st.count),
      tostring(app.live), Apps:active().id, R.state() and R.state().mode, X.state().mode))
  end
  U.shot(game, dir .. "/probe_berry.png")
  app.forceEnd(20)
  U.wait(5)
  local res = R.state() and R.state().lastResult
  log("forceEnd result:", res and res.stars, res and res.title)
  U.shot(game, dir .. "/probe_result.png")
  S.leaveGame()
  U.wait(5)
  log("left: mode", R.state() and R.state().mode)
  U.shot(game, dir .. "/probe_picker.png")
  -- Head It: the HUD with the game's words, then its result breakdown
  log("start head:", S.startGame("head", "easy"))
  local headApp = Apps:get("game_head")
  U.wait(240)
  local hs = headApp.debugState()
  if hs then hs.combo = 4; hs.score = 12 end
  U.wait(2)
  U.shot(game, dir .. "/probe_head.png")
  headApp.forceEnd(40)
  U.wait(5)
  U.shot(game, dir .. "/probe_head_result.png")
  S.leaveGame()
  U.wait(5)
  -- Tile Puzzle: the status line and its result
  log("start tile:", S.startGame("tile", "easy"))
  local tileApp = Apps:get("game_tile")
  U.wait(240)
  U.shot(game, dir .. "/probe_tile.png")
  tileApp.forceEnd(35)
  U.wait(5)
  U.shot(game, dir .. "/probe_tile_result.png")
  S.leaveGame()
  U.wait(5)
  S.finish()
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
