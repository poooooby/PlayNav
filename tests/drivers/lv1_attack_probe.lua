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
