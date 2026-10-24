-- Driver: 3D SUPER TRAINING (arena3d) in a regimen - the stadium (the card's model, or the
-- drawn stand-in with PROBE_FALLBACK=1), the camera behind the trainee following it left,
-- middle and right, a ball in flight, the reticle where the camera puts the aim; logs whether
-- the device draws it (available, why), the depth format and the canvas size. The option is
-- set for the run only (Draw.mode3d), never saved.
--   SHOT_DIR=<dir> [SHOT_W=1920 SHOT_H=1080] [PROBE_COURSE=lv2_spd] POKEPORT_GAME=emerald \
--   POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 POKEPORT_DRIVER=mods/play_nav/tests/drivers/arena3d_probe.lua love .

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
    if os.getenv("PROBE_FALLBACK") == "1" and Xk and Xk._test and Xk._test.forceRom then Xk._test.forceRom(false) end
  end
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
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end

  local ok, err = pcall(function()
    local Draw = TR.session.arenaDraw
    if not (Draw and Draw.arena3d) then log("FAIL no arena3d on the arena drawer"); return end
    local A3 = Draw.arena3d
    Draw.mode3d = true
    local avail, why = A3.available()
    log("available", avail, why or "", "depth", A3.depthFormat() or "-")
    TR.open()
    U.wait(20)
    TR.session.enterCourses()
    U.wait(10)
    for _, c in ipairs(TR.session.courseList()) do TR.store.cleared()[c.id] = true end
    local id = os.getenv("PROBE_COURSE") or "lv1_hp"
    local started, w = TR.session.startCourse(id)
    log("start", id, started, w)
    waitFor(function() return TR.state().mode == "regimen" end, 900)
    waitFor(function() return TR.session.sim and TR.session.sim.t > 3 end, 60 * 60)
    shot("a01_intro")
    waitFor(function() return TR.session.sim and TR.session.sim.phase == "play" end, 60 * 60)
    local S = TR.session.sim
    local Sim = getmetatable(S).__index
    U.wait(20)
    log("in3d", Draw.in3d(), "canvas", A3.lastSize())
    -- the card's eight Poke Ball emblems (r 886, y 401) marked where the camera puts them
    Draw.debugMarks = {}
    for k = 0, 7 do
      local a = math.rad(k * 45)
      Draw.debugMarks[#Draw.debugMarks + 1] = { math.sin(a) * 886, 401, math.cos(a) * 886 }
    end
    U.wait(2)
    shot("a02_play_middle")
    Draw.debugMarks = nil
    -- the orbit: the trainee pressed against each edge (the pad held, as a player would: the
    -- regimen sets the move from it each frame), the border lit on that side
    local function holdUntil(btn, secs)
      local t0 = S.t
      waitFor(function() game.input.state[btn] = true; return S.t - t0 > secs end, 6000)
    end
    for i, e in ipairs({ { "left", "edge_left" }, { "right", "edge_right" }, { "up", "edge_top" } }) do
      holdUntil(e[1], S.game3d and 4.5 or 2.6)
      local az, el, r = A3.orbitNow()
      log(("%s: edge %d, azimuth %.1f elevation %.1f radius %.0f"):format(e[2], S.player.edge or -1, az, el, r))
      shot(("a0%d_%s"):format(2 + i, e[2]))
      game.input.state[e[1]] = false
    end
    -- back to the middle and the grass
    if S.game3d then
      S.player.az, S.player.el = 90, 0
      S:place3()
    else
      S.player.x, S.player.y = 0, 0
    end
    U.wait(10)
    -- forward / back: the game's three distances
    for i, d in ipairs({ -1, 1, 1 }) do
      S:stepDistance(d)
      local t0 = S.t
      waitFor(function() return S.t - t0 > 1.3 end, 6000)
      local _, _, r = A3.orbitNow()
      log(("distance step %d: radius %.0f, depth z %.3f"):format(d, r, S.player.z))
      shot(("a0%d_dist_%d"):format(5 + i, math.floor(r + 0.5)))
    end
    S:stepDistance(-1)
    U.wait(40)
    -- where the Poke Ball sits against the balloon at the start
    do
      local by
      if S.game3d then
        local cx, cy = S:botCentre3()
        local halfH = S.shape and S.shape.halfH or 1
        _, by = A3.projectModel(cx, cy + halfH * S:botR3(), 0)
      else
        _, by = A3.project(0, (S.botCY and S:botCY() or 1) + 0.3, 1)
      end
      local _, pby = A3.projectModel(0, 401, -886)
      log(("Poke Ball y %.1f, balloon top y %.1f"):format(pby, by))
    end
    -- the aim: the reticle where the camera puts it
    S:aim(0.3, 1.2)
    local rx, ry = A3.project(0.3, 1.2, 1)
    local sx, sy = -1, -1
    if TR.session.sceneToAim then sx, sy = TR.session.sceneToAim(Sim.project(0.3, 1.2, 1)) end
    log(("aim (0.3, 1.2): on screen %.1f, %.1f; sceneToAim %.1f, %.1f"):format(rx, ry, sx, sy))
    -- frame time, 3D against 2D (a driver run is uncapped: the engine's whole frame)
    local function frameMs(n)
      local t0 = love.timer.getTime()
      U.wait(n)
      return (love.timer.getTime() - t0) / n * 1000
    end
    local ms3 = frameMs(120)
    Draw.mode3d = false
    local ms2 = frameMs(120)
    Draw.mode3d = true
    -- (the regimen puts the sim back in the game's space on the next frames)
    waitFor(function() return S.game3d end, 120)
    log(("frame time: 3D %.2f ms, 2D %.2f ms"):format(ms3, ms2))
    -- a ball in flight at the trainee
    S.script, S.balls, S.spawnQueue = nil, {}, {}
    S.player.safe = S.game3d and 0 or 9
    local b
    if S.game3d then
      local pid = 57
      b = S:gameBall3({ p = pid, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
    else
      b = Sim.gameBall(S, { p = 0, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
    end
    S.balls[1] = b
    for i, left in ipairs({ 1.0, 0.4, 0.2 }) do
      waitFor(function() local e = S:ballEta(b); return not e or e <= left end, 4000)
      log(("ball %.1f s out: %d in flight, at %.1f, %.1f, %.1f"):format(left, #S.balls, b.x or 0, b.y or 0, b.z or 0))
      local bx, by, bk = A3.project(b.x, b.y, b.z)
      log(("  on screen %.1f, %.1f r %.1f past %s (frame units)"):format(bx or -1, by or -1, (b.r or 0) * 118 * (bk or 0), tostring(b.past)))
      shot(("a1%d_ball_%.1f"):format(i, left))
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
