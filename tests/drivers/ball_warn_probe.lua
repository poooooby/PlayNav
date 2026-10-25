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
  -- PROBE_3D=0 / 1: 2D or 3D SUPER TRAINING for this run only, whatever the saved option
  if os.getenv("PROBE_3D") and TR.session.arenaDraw then TR.session.arenaDraw.mode3d = os.getenv("PROBE_3D") == "1" end
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
    if os.getenv("PROBE_DODGE") then
      -- a homing ball (PROBE_DODGE_P, default 57 round; 36 wide, 37 tall) thrown at the trainee,
      -- which walks right from the throw (PROBE_DODGE=still: it stands): the ball steers after it
      -- too slowly to catch it and passes beside, its drawn size its hitbox
      local still = os.getenv("PROBE_DODGE") == "still"
      local pid = tonumber(os.getenv("PROBE_DODGE_P") or "57")
      S.player.x = 0
      local b = Sim.gameBall(S, { p = pid, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
      S.balls[1] = b
      -- (the regimen sets the move from the pad each frame, so the trainee is walked here at
      -- the plain move speed in sim time)
      local t0 = S.t
      local function walk() if not still then S.player.x = math.min(0.8, 0.72 * (S.t - t0)) end end
      for i, left in ipairs({ 1.0, 0.5, 0.25, 0.1, 0.02 }) do
        waitFor(function() walk(); local e = S:ballEta(b); return not e or e <= left end, 4000)
        local e, h = S:ballEta(b)
        log(("p%d left %.2f hits %s ball x %.3f half %.3f x %.3f trainee x %.3f"):format(pid, e or -1, tostring(h),
          b.x, b.w / 2, b.h / 2, S.player.x))
        shot(("d%02d_p%d_%s_%.2f"):format(i, pid, still and "still" or "move", e or 0))
      end
      waitFor(function() walk(); return b.z < S.player.z end, 4000)
      -- past the trainee: gone within D.GAME_BALL.PAST_FADE_S
      local tCross = S.t
      for k, after in ipairs({ 0.03, 0.06, 0.1 }) do
        waitFor(function() walk(); return S.t - tCross >= after end, 4000)
        local alive = false
        for _, o in ipairs(S.balls) do if o == b then alive = true end end
        log(("after crossing %.2f s: ball %s, depth past %.3f"):format(S.t - tCross, alive and "flying" or "gone",
          S.player.z - b.z))
        shot(("d07_%d_p%d_%s_after_%.2f"):format(k, pid, still and "still" or "move", S.t - tCross))
      end
      local D = TR.session.arenaDraw
      local R = D and D.lastRider
      log(("past: ball x %.3f trainee x %.3f playerHits %d; trainee drawn %s, hitbox +-%.1f x %.1f units"):format(b.x, S.player.x,
        S.stats.playerHits or -1, R and R.x0 and ("%.1f..%.1f x %.1f..%.1f"):format(R.x0, R.x1, R.y0, R.y1) or "?",
        0.12 * 118, 0.3 * 70))   -- (N.PLAYER.R / H at the trainee's 118 / 70 units a world unit)
      shot(("d06_p%d_%s_past"):format(pid, still and "still" or "move"))
      return
    end
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
