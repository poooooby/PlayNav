-- Driver: Super Training's energy meter and charged shots against the game's (capture
-- 2026-10-23_16-43-37): the meter filling from the middle, the two rings once it covers a shot,
-- a charge's stage 1 (yellow ring, the second crosshair closing in, the fire) and stage 2
-- (red, the bigger fire), a Charged Shot's points, and a charge held too long (smoke, the
-- stop). Times are the sim's own (driver runs step faster than real time).
-- PROBE_FALLBACK=1 draws NaviPlay's own HUD (USE ROM ASSETS off for the run).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/charge_probe.lua love .

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
  if os.getenv("PROBE_FALLBACK") == "1" then X._test.forceRom(false) end
  local TR = X.training
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end

  local ok, err = pcall(function()
    log("training open:", tostring(TR.open()))
    U.wait(20)
    TR.session.enterCourses()
    U.wait(10)
    log("start course:", tostring(TR.session.startCourse("lv1_hp")))
    waitFor(function() return TR.state().mode == "regimen" end, 900)
    local function sim() return TR.session.sim end
    waitFor(function() return sim() and sim().phase == "play" end, 60 * 60)
    local S = sim()
    local m = S.mods
    log(("shot power %s, meter refill %.2f a second, colour %s"):format(tostring(m.power), m.gutsPerS or -1, S.shotType))
    -- the meter from empty
    S.guts = 0
    waitFor(function() return S.guts >= 0.25 end, 600); shot("c01_meter_quarter")
    waitFor(function() return S:shotReady() end, 600); U.wait(6); shot("c02_meter_ready_rings")
    waitFor(function() return S.guts >= 1 end, 600); shot("c03_meter_full")
    -- a charge: stage 1, closing in, stage 2
    local g = S:state().goals[1]
    if g then S:aim(g.x, g.y) end
    S:pressFire()
    local function heldF() return S.player.chargeT * 30 end
    waitFor(function() return heldF() >= 52 end, 900); shot("c04_stage1_yellow")
    waitFor(function() return heldF() >= 59 end, 900); shot("c05_closing_in")
    waitFor(function() return heldF() >= 70 end, 900); shot("c06_stage2_red")
    local before = S.score
    S:releaseFire()
    local scored
    waitFor(function() scored = S.score - before; return scored > 0 end, 600)
    log(("charged shot scored %d (power %s x 3 = %s); meter after %.2f"):format(scored, tostring(m.power),
      tostring(m.power and math.floor(m.power) * 3), S.guts))
    -- held too long
    waitFor(function() return S.player.lock == 0 end, 300)
    S:pressFire()
    waitFor(function() return (S.player.smoke or 0) > 0 end, 900)
    local stunAt = S.t
    U.wait(4); shot("c07_fizzle_smoke")
    log(("fizzled at %.2f s held; stopped for %.2f s"):format(96 / 30, S.player.stun))
    S:setMove(1, 0)
    local x0 = S.player.x
    waitFor(function() return S.player.stun <= 0 end, 900)
    log(("moved while stopped: %s"):format(tostring(math.abs(S.player.x - x0) > 1e-4 and S.t - stunAt < 0.99)))
    S:setMove(0, 0)
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
