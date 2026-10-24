-- Driver: the regimen's shield against Wooble's capture 2026-10-23_17-28-44: up at once, a
-- ball bouncing off it, the shield flaring and shattering a moment later; held with nothing
-- coming, shattering at its length. Shots at each step (sim time; driver runs step faster).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/shield_probe.lua love .

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
    TR.open()
    U.wait(20)
    TR.session.enterCourses()
    U.wait(10)
    TR.session.startCourse("lv1_hp")
    waitFor(function() return TR.state().mode == "regimen" end, 900)
    waitFor(function() return TR.session.sim and TR.session.sim.phase == "play" end, 60 * 60)
    local S = TR.session.sim
    S.gameAttacks = nil
    S.script = nil
    S.balls = {}
    local p = S.player
    -- a ball coming in, the shield up as it nears
    S.balls[#S.balls + 1] = { x = p.x, y = (p.y or 0) + 0.15, z = 0.6, vx = 0, vy = 0, vz = -0.8, r = 0.06, kind = "small" }
    waitFor(function() return S.balls[1] and S.balls[1].z < 0.3 end, 900)
    S:block()
    U.wait(2); shot("s01_shield_up")
    waitFor(function() return S.balls[1] and S.balls[1].bounced end, 900)
    U.wait(3); shot("s02_bounced")
    waitFor(function() return p.breakT and p.breakT < 0.15 end, 900); shot("s03_flare")
    waitFor(function() return (p.shatter or 0) > 0 end, 900); U.wait(2); shot("s04_shatter")
    waitFor(function() return (p.shatter or 0) < 0.3 end, 900); shot("s05_pieces")
    log("blocked: score", S.score, "cooldown", p.shieldCd)
    -- held with nothing coming
    waitFor(function() return p.shieldCd <= 0 end, 900)
    S.balls = {}
    S:block()
    local t0 = S.t
    U.wait(10); shot("s06_held")
    waitFor(function() return p.shield <= 0 end, 2000)
    log(("held shield shattered after %.2f s"):format(S.t - t0))
    U.wait(2); shot("s07_held_shatter")
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
