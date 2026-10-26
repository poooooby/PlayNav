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
  -- PROBE_SPECIES (e.g. LATIAS): the lead; Torchic by default
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_" .. (os.getenv("PROBE_SPECIES") or "TORCHIC")), 12)
  end
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
    -- (a secret course needs a Fully Trained Pokemon: 510 EVs)
    if id:match("^secret") then
      local mon = s.party[1]
      mon.evs = { hp = 252, atk = 252, def = 6, spa = 0, spd = 0, spe = 0 }
      local ss = TR.session.session
      if ss then ss.evs = { hp = 252, atk = 252, def = 6, spa = 0, spd = 0, spe = 0 }; ss.rec.fully = true end
    end
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
    -- PROBE_SCORE=<0..1>: the score at that share of the target, the balloon grown with it (a
    -- grown balloon must stay under the top of the view)
    if os.getenv("PROBE_SCORE") and S.bot then
      S.score = math.floor((tonumber(os.getenv("PROBE_SCORE")) or 0.95) * (S.bot.target or 300))
      U.wait(90)
      local cx, cy, _, s3 = S.botCentre3 and S:botCentre3()
      log("score", S.score, "of", S.bot.target, "grow3", tostring(S.bot.grow3), "middle y", tostring(cy), "R3", tostring(S.botR3 and S:botR3()))
      shot("a03_score")
    end
    -- PROBE_ENDING=1: the regimen cleared, then the 3D ending (arena_draw D.ENDING) shot at the
    -- end-reg-ref capture's moments (the outro's t)
    if os.getenv("PROBE_ENDING") == "1" then
      if os.getenv("PROBE_CULL") then A3.ENDING.CULL = os.getenv("PROBE_CULL") end
      -- (the score left as it is: the clearing hit itself swells the balloon to its ending size)
      TR.session.forceEnd({ clear = true, remaining = 90 })
      local function outroT()
        local o = TR.session.session and TR.session.session.outro
        return o and o.t or nil
      end
      for _, at in ipairs({ 0.05, 0.15, 0.25, 0.4, 0.6, 2.0, 3.4, 3.8, 3.95, 4.15, 4.5, 4.8, 5.0, 5.3, 5.6, 5.9, 6.3, 8.0 }) do
        if not waitFor(function() local t = outroT(); return t and t >= at end, 60 * 60) then
          log("no outro at", at, "outro", tostring(outroT()), "mode", TR.state().mode)
          break
        end
        shot(("n_%04.2f"):format(at))
        local sim = TR.session.sim or S
        log("ending", at, "in", tostring(A3.inEnding and A3.inEnding()), "score", tostring(sim.score),
          "target", tostring(sim.bot and sim.bot.target), "grow3", tostring(sim.bot and sim.bot.grow3), "same sim", tostring(sim == S))
        local L = Draw.lastEnding
        if L then log(("  top0 %.1f foot0 %.1f h0 %.1f nH %.1f ncy %.1f cy %.1f H %.1f view %.1f..%.1f"):format(L.top0, L.foot0, L.h0, L.nH, L.ncy, L.cy, L.H, L.viewTop, L.viewBottom)) end
      end
      return
    end
    -- PROBE_ENDCAM=1: the ending's fixed camera (A3.ENDING) on the arena as it stands, to set
    -- beside the end-reg-ref capture
    if os.getenv("PROBE_ENDCAM") == "1" then
      A3.setEnding(true)
      U.wait(4)
      shot("e_endcam")
      A3.setEnding(false)
      return
    end
    -- PROBE_BITS=1 (3D, a bitbot course: lv3_hp Wailord): the bitbots, then their first volley
    if os.getenv("PROBE_BITS") == "1" and S.game3d then
      waitFor(function() return #(S.bits or {}) >= 3 end, 60 * 120)
      log("bits", #(S.bits or {}))
      U.wait(6)
      shot("b_bits")
      waitFor(function()
        for _, b in ipairs(S.balls) do if b.kind == "bit" then return true end end
        return false
      end, 60 * 60)
      local t0 = S.t
      waitFor(function() return S.t - t0 > 0.5 end, 4000)
      shot("b_volley")
      return
    end
    -- PROBE_SHIELD=1 (3D, Graveler's course lv2_def): the cage from the middle, the top middle and
    -- the top left, then broken
    if os.getenv("PROBE_SHIELD") == "1" and S.game3d then
      waitFor(function() return S.barrier ~= nil end, 60 * 120)
      log("shield up", S.barrier ~= nil)
      S.balls, S.spawnQueue = {}, {}
      for _, q in ipairs({ { "middle", 0, 90 }, { "top_middle", 45, 90 }, { "top_left", 45, 120 } }) do
        S.player.el, S.player.az = q[2], q[3]
        S:place3()
        U.wait(8)
        shot("s_" .. q[1])
      end
      S.player.el, S.player.az = 0, 90
      S:place3()
      S.barrier, S.shieldBrokeAt = nil, S.t
      local t0 = S.t
      waitFor(function() return S.t - t0 > 0.35 end, 4000)
      shot("s_break")
      return
    end
    -- PROBE_POSES=1 (3D, the game's space): the middle and the four corners of the orbit, then
    -- the three distances, each held still and shot (p_*), to set beside the captures
    if os.getenv("PROBE_POSES") == "1" and S.game3d then
      -- PROBE_NEXTBOT=1: the course's next balloon first (secret_01: Tyrantrum after Aurorus)
      if os.getenv("PROBE_NEXTBOT") == "1" and S.nextBot then
        S:nextBot()
        if S.startScript then S:startScript() end
        log("next balloon", S.bot and S.bot.national, S.script and S.script.phase and S.script.phase.species)
      end
      S.script, S.balls, S.spawnQueue = nil, {}, {}
      local poses = { { "middle", 0, 90 }, { "top_left", 45, 120 }, { "top_right", 45, 60 },
        { "bottom_left", 0, 120 }, { "bottom_right", 0, 60 } }
      for _, q in ipairs(poses) do
        S.player.el, S.player.az = q[2], q[3]
        S:place3()
        U.wait(12)
        log(("pose %s: el %.0f az %.0f"):format(q[1], S.player.el, S.player.az))
        shot("p_" .. q[1])
      end
      S.player.el, S.player.az = 0, 90
      local DIST = { 180, 240, 300 }
      for _, step in ipairs({ 1, 3 }) do
        S.player.distStep, S.player.dist = step, DIST[step]
        S:place3()
        U.wait(12)
        shot(("p_dist_%d"):format(DIST[step]))
      end
      S.player.distStep, S.player.dist = 2, 240
      S:place3()
      -- the zoom lines, half way through a step nearer and one farther
      for _, d in ipairs({ -1, 1 }) do
        S:stepDistance(d)
        local t0 = S.t
        waitFor(function() return S.t - t0 > 0.45 end, 4000)
        shot(d < 0 and "p_zoom_nearer" or "p_zoom_farther")
        waitFor(function() return S.t - t0 > 1.3 end, 4000)
      end
      return
    end
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
