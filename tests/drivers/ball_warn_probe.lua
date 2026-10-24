-- Driver: the incoming-ball warning on Wailmer's course: the balls' shadows on the grass
-- darkening as they near (red for one that would hit), and in the last half second the ball and
-- the trainee's shadow blinking red; one ball aimed at the trainee, one wide (sim time).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/ball_warn_probe.lua love .

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
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end

  local ok, err = pcall(function()
    TR.open()
    U.wait(20)
    TR.session.enterCourses()
    U.wait(10)
    -- a new save: every course open
    for _, c in ipairs(TR.session.courseList()) do TR.store.cleared()[c.id] = true end
    local started, why = TR.session.startCourse("lv1_hp")
    log("start lv1_hp", started, why)
    waitFor(function() return TR.state().mode == "regimen" end, 900)
    waitFor(function() return TR.session.sim and TR.session.sim.phase == "play" end, 60 * 60)
    local S = TR.session.sim
    S.script, S.balls, S.spawnQueue = nil, {}, {}
    S.player.safe = 0
    S.player.x = 0.2
    local Sim = getmetatable(S).__index
    local hit = Sim.gameBall(S, { p = 0, next = 0, dx = -40, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
    local wide = Sim.gameBall(S, { p = 0, next = 0, dx = 60, dy = 10, yaw = 0, pitch = 0, aimX = 0, aimY = 0 })
    S.balls[1], S.balls[2] = hit, wide
    local eta = S:ballEta(hit)
    log(("eta %.2f"):format(eta))
    for i, left in ipairs({ 1.6, 1.0, 0.45, 0.38, 0.3, 0.2 }) do
      waitFor(function() local e = S:ballEta(hit); return not e or e <= left end, 4000)
      local e, h = S:ballEta(hit)
      log("left", e, h)
      shot(("w%02d_left_%.2f"):format(i, e or 0))
    end
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
