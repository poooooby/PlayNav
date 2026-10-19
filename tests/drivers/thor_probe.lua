-- Driver: a Super Training regimen on a Thor-like device: the touch screen on a second display
-- (the engine's SecondScreen bridge stood in for) and a 1920x1080 window as the top display.
-- The regimen fills the whole top display and frames the scene further back, so the beaten
-- balloon's flight over the stadium's roof and its star show. Shots of the intro, play and
-- the outro.
--   SHOT_DIR=<dir> SHOT_W=1920 SHOT_H=1080 POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_TOUCH=1 POKEPORT_DRIVER=mods/play_nav/tests/drivers/thor_probe.lua love .

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1920, tonumber(os.getenv("SHOT_H")) or 1080, { resizable = true, highdpi = true })
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
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  -- the second display: the engine's bridge, its calls stood in for (restored at the end)
  local SS = require("src.render.SecondScreen")
  local saved = {}
  for _, k in ipairs({ "usable", "available", "detected", "push", "pollTouch", "setEnabled" }) do saved[k] = SS[k] end
  SS.usable = function() return true end
  SS.available = function() return true end
  SS.detected = function() return true end
  SS.push = function() return true end
  SS.pollTouch = function() return nil end
  SS.setEnabled = function() return true end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display
  opts.display = "second_screen"
  local TR = X.training
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end

  local ok, err = pcall(function()
    log("training open:", TR.open())
    waitFor(function() return X.state().mode == "second_screen" end, 300)
    log("display mode:", X.state().mode)
    U.wait(20)
    log("start course:", TR.session.startCourse("lv1_hp"))
    local function simNow() return TR.session.sim end
    waitFor(function() local sim = simNow(); return sim and sim.phase == "countdown" and sim.t > 4 end, 60 * 60)
    shot("h01_intro_rise")
    waitFor(function() local sim = simNow(); return sim and sim.phase == "play" end, 60 * 60)
    waitSecs(1.5)
    shot("h02_play")
    local T = TR.session
    -- the view the arena drew with (D.view records what it last returned)
    local D = T.Draw
    if D and D.lastView then
      local v = D.lastView
      log(("view z %.3f pivot %.1f,%.1f extent %.1f %.1f %.1f %.1f"):format(v.z, v.px, v.py, v.ex, v.ey, v.ew, v.eh))
    else
      log("view: not recorded")
    end
    local sim = simNow()
    if sim and sim.phase == "play" then log("forceEnd:", T.forceEnd({ clear = true, remaining = sim.remaining })) end
    for _, at in ipairs({ { 3.0, "h03_outro_fly" }, { 5.3, "h04_outro_away" }, { 6.4, "h05_outro_twinkle" } }) do
      waitFor(function() local o = T.session and T.session.outro; return not o or o.t >= at[1] end, 60 * 30)
      shot(at[2])
    end
    waitFor(function() return TR.state().mode == "result" end, 60 * 30)
    U.wait(10)
    T.finish()
    U.wait(5)
  end)
  if not ok then log("probe body failed:", tostring(err)) end
  opts.display = savedDisplay
  for k, v in pairs(saved) do SS[k] = v end
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
