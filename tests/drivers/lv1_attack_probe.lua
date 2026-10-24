-- Driver: the Lv1 balloons' attacks as Wooble's captures show them: Magnemite's magenta aura and
-- wind-up (dip, snap up, held while the ball flies), Axew's ring of 8 and Noibat's strays
-- spreading past the trainee (sim time; driver runs step faster).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/lv1_attack_probe.lua love .

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
    if os.getenv("PROBE_FALLBACK") == "1" then X._test.forceRom(false) end
    TR.open()
    U.wait(20)
    for _, c in ipairs(TR.session.courseList()) do TR.store.cleared()[c.id] = true end
    local function course(id, steps)
      TR.session.enterCourses()
      U.wait(10)
      log("start", id, TR.session.startCourse(id))
      waitFor(function() return TR.state().mode == "regimen" end, 900)
      waitFor(function() return TR.session.sim and TR.session.sim.phase == "play" end, 60 * 60)
      local S = TR.session.sim
      S.player.safe = 1e9
      for _, st in ipairs(steps) do
        waitFor(function() return st.when(S) end, 60 * 60)
        if st.after then local t0 = S.t; waitFor(function() return S.t - t0 >= st.after end, 2000) end
        shot(id .. "_" .. st.name)
      end
      TR.session.forceEnd("timeout")
      waitFor(function() return TR.state().mode ~= "regimen" end, 60 * 60)
      pcall(TR.session.leaveResult)
      U.wait(30)
    end
    -- PROBE_ONLY=lv2: the stage 2 balls (black, blue homing, stretched) and Tentacruel's bitbots
    if os.getenv("PROBE_ONLY") == "lv2" then
      local function flying(age) return function(S)
        for _, b in ipairs(S.balls) do if b.game and S.t - b.t0 > age then return true end end
      end end
      course("lv2_atk", { { name = "1_black_ball", when = flying(0.9) } })
      course("lv2_spa", { { name = "1_homing_round", when = flying(1.2) } })
      course("lv2_spd", {
        { name = "1_bitbots", when = function(S) return #S.bits >= 3 end, after = 1.0 },
        { name = "2_wide_homing", when = function(S)
          for _, b in ipairs(S.balls) do if b.game and b.w and S.t - b.t0 > 1.2 then return true end end
        end },
      })
      course("lv2_spe", { { name = "1_dive", when = function(S) return (S.bot.thrown or 0) > 0 end, after = 0.4 } })
      return
    end
    -- PROBE_ONLY=grow: Graveler grown near its target; Magneton's cleared group (puffs, red goal)
    if os.getenv("PROBE_ONLY") == "grow" then
      course("lv2_atk", {
        { name = "1_start", when = function(S) return S.phase == "play" end, after = 0.5 },
        { name = "2_grown", when = function(S) S.score = 1400; return S.bot.scale > 1.5 end, after = 0.3 },
      })
      course("lv2_spa", {
        { name = "1_cleared", when = function(S)
          S.groupsCleared = 1
          for _, g in ipairs(S.goals) do if g.kind == "white" then S.groupScored = S.groupSize; g.kind = "dead_" end end
          local keep = {}
          for _, g in ipairs(S.goals) do if g.kind ~= "dead_" then keep[#keep + 1] = g end end
          S.goals = keep
          return S.clearPuffAt ~= nil
        end, after = 0.2 },
        { name = "2_red", when = function(S) return S:chanceUp() end, after = 0.4 },
      })
      return
    end
    -- PROBE_ONLY=lv3: Golem's shield and wall, Wailord's giant ball and bitbots, Magnezone
    if os.getenv("PROBE_ONLY") == "lv3" then
      course("lv3_def", {
        { name = "1_shield", when = function(S) return S.barrier ~= nil and S.barrier.t > 2 end },
        { name = "2_wall", when = function(S)
          if S.barrier then for _, g in ipairs(S.goals) do if g.kind == "marker" and g.age > 1.3 then S:hitGoal(g, { points = 0 }) end end end
          local n = 0
          for _, b in ipairs(S.balls) do if b.game and S.t - b.t0 > 1.6 then n = n + 1 end end
          return n >= 8
        end },
      })
      course("lv3_hp", {
        { name = "1_giant", when = function(S) for _, b in ipairs(S.balls) do if b.game and b.r > 0.2 and S.t - b.t0 > 1.0 then return true end end end },
        { name = "2_weave", when = function(S) local n = 0 for _, b in ipairs(S.balls) do if b.game and b.game.ampX ~= 0 and S.t - b.t0 > 0.9 then n = n + 1 end end return n >= 4 end },
      })
      course("lv3_spa", { { name = "1_stream", when = function(S) local n = 0 for _, b in ipairs(S.balls) do if b.game then n = n + 1 end end return n >= 2 end } })
      return
    end
    -- PROBE_ONLY=shield: Graveler's shield and its target alone
    if os.getenv("PROBE_ONLY") == "shield" then
      course("lv2_def", {
        { name = "1_shield", when = function(S) return S.barrier ~= nil end, after = 1.0 },
        { name = "2_shield_later", when = function(S) return S.barrier ~= nil and S.barrier.t > 4 end },
        -- its target hit: the shield shatters
        { name = "3_break_0.1", when = function(S)
          if S.barrier then for _, g in ipairs(S.goals) do if g.kind == "marker" then S:hitGoal(g, { points = 0 }) end end end
          return S.shieldBrokeAt ~= nil
        end, after = 0.1 },
        { name = "4_break_0.35", when = function(S) return S.t - S.shieldBrokeAt >= 0.35 end },
        { name = "5_break_0.7", when = function(S) return S.t - S.shieldBrokeAt >= 0.7 end },
      })
      return
    end
    course("lv1_spa", {
      { name = "1_aura", when = function(S) return (S.bot.aura or 0) > 0 end, after = 0.6 },
      { name = "2_windup_dip", when = function(S) return S.bot.windup and S.bot.windup.t > S.bot.windup.len * 0.55 end },
      { name = "3_thrown", when = function(S) return (S.bot.thrown or 0) > 0 end, after = 0.5 },
    })
    course("lv1_atk", {
      { name = "1_ring", when = function(S) for _, b in ipairs(S.balls) do if b.game and S.t - b.t0 > 0.9 then return #S.balls >= 6 end end end },
      { name = "2_ring_near", when = function(S) for _, b in ipairs(S.balls) do if b.game and S.t - b.t0 > 1.25 then return #S.balls >= 6 end end end },
    })
    -- a single ball just past the trainee (who steps aside once it is thrown, so it misses):
    -- fading, no bigger
    local function pastBy(dz) return function(S)
      for _, b in ipairs(S.balls) do if b.game and b.z < S.player.z - dz then return true end end
    end end
    course("lv1_hp", {
      { name = "1_arriving", when = function(S)
        for _, b in ipairs(S.balls) do
          if b.game then S.player.x = b.x > 0 and -0.7 or 0.7 end
          if b.game and b.z < S.player.z + 0.05 then return true end
        end
      end },
      { name = "2_just_past", when = pastBy(0.02) },
      { name = "3_further_past", when = pastBy(0.05) },
    })
    course("lv1_spe", {
      { name = "1_strays", when = function(S) return #S.balls >= 4 end, after = 0.5 },
    })
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
