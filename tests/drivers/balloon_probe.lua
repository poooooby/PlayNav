-- Driver: boots Emerald, opens Super Training and starts several regimens one after another,
-- shooting each Balloon Bot (the Pokemon's own sprite in balloon blue) three times a second
-- apart so the goals can be seen travelling over the sprite. Logs, per shot, every goal's
-- cell and whether it is walkable on the bot's shape.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/balloon_probe.lua love .

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
  local function waitSecs(secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do U.wait(1) end
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
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 30)
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = "combined"
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local Sim = TR.sim
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end

  log("open:", TR.open())
  U.wait(10)
  local S = TR.session
  -- every course open for the probe
  S.session.rec.fully = true
  for _, c in ipairs(S.courseList()) do TR.store.cleared()[c.id] = true end
  -- BALLOON_VERSION=sapphire etc.: the GBA game the courses are for (the final course's line)
  if os.getenv("BALLOON_VERSION") and TR.host then
    local v = os.getenv("BALLOON_VERSION")
    TR.host.gameVersion = function() return v end
    log("version stood in:", v)
  end
  local ids = { os.getenv("BALLOON_COURSES") or "lv1_hp,lv2_spe,lv2_def,lv3_def,secret_04,secret_10" }
  for id in ids[1]:gmatch("[^,]+") do
    S.session.rec.resting = nil
    S.enterCourses()
    U.wait(3)
    local ok, why = S.startCourse(id)
    log("start", id, tostring(ok), tostring(why))
    if ok then
      -- the regimen fades in and builds its sim after the transition; then the intro plays
      for _ = 1, 3000 do if S.sim then break end; U.wait(1) end
      for _ = 1, 3000 do if S.sim and S.sim.phase == "play" then break end; U.wait(1) end
      local sim = S.sim
      if not sim then log("  FAIL no sim"); break end
      log(("  shape for bot 1: %s"):format(sim.shape and (#sim.shape.list .. " cells") or "none (badge)"))
      waitSecs(1.5)   -- the first goals
      for k = 1, 3 do
        local offs, n = 0, 0
        for _, g in ipairs(sim.goals) do
          if g.ci then
            n = n + 1
            if not Sim.walkable(sim.shape, g.ci, g.cj) then offs = offs + 1 end
          end
        end
        log(("  t %.1f goals %d on shape %d off %d"):format(sim.t, #sim.goals, n, offs))
        shot(("%s_%d"):format(id, k))
        waitSecs(1.0)
      end
      -- the player's Pokemon on the move: hold right, shoot mid-hop, let go, shoot the landing
      if os.getenv("BALLOON_MOVE") then
        for k = 1, 4 do
          U.hold(game, k <= 2 and "right" or "left", 6)
          shot(("%s_move_%d"):format(id, k))
        end
        U.wait(3)
        shot(("%s_stop"):format(id))
      end
      -- the see-through rider: over a goal it fades, clear of every target it is solid
      if os.getenv("BALLOON_RIDER") then
        local D = TR.session.arenaDraw
        local p = sim.player
        local N_X = 0.8
        local function report(what)
          waitSecs(0.6)
          local r = D and D.lastRider or {}
          log(("  rider %s: opacity %.2f covers %s"):format(what, r.a or -1, tostring(r.covers)))
          shot(("%s_rider_%s"):format(id, what))
        end
        for _ = 1, 600 do if sim.goals[1] then break end; U.wait(1) end
        local g = sim.goals[1]
        if g then
          local gx, gy = sim:goalPos(g)
          p.x = math.max(-N_X, math.min(N_X, gx))
          p.y = math.max(0, math.min(1.25, gy - 0.25))
          report("over_goal")
        end
        p.x, p.y = 0.8, 0
        for _, b in ipairs(sim.bits or {}) do b.dead = true end
        sim.goals, sim.balls = {}, {}
        sim.pendingAttack, sim.scheduleIdx = nil, math.huge
        report("clear")
        -- an attack on its way in: it fades as the ball reaches it
        sim:launch({ kind = "big" })
        for _ = 1, 3000 do
          local b = sim.balls[1]
          if b and b.z < 0.35 then break end
          U.wait(1)
        end
        local r = D and D.lastRider or {}
        log(("  rider attack_coming: opacity %.2f covers %s"):format(r.a or -1, tostring(r.covers)))
        shot(("%s_rider_attack"):format(id))
      end
      S.quitRegimen()
      U.wait(5)
    end
  end
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
