-- Driver: Tentacruel's bitbots as purple party balloons; one popped, shot as it deflates, darts
-- about and falls off the screen (sim time; driver runs step faster).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/bit_pop_probe.lua love .

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
    local started, why = TR.session.startCourse("lv2_spd")
    log("start lv2_spd", started, why)
    waitFor(function() return TR.state().mode == "regimen" end, 900)
    waitFor(function() return TR.session.sim and TR.session.sim.phase == "play" end, 60 * 60)
    local S = TR.session.sim
    S.player.safe = 1e9
    waitFor(function() return #S.bits >= 2 end, 60 * 60)
    log("bits", #S.bits)
    shot("b01_bits")
    local bit = S.bits[1]
    bit.hp, bit.dead, bit.regenT, bit.poppedAt = 0, true, 1e9, S.t
    local t0 = S.t
    for i, at in ipairs({ 0.08, 0.18, 0.3, 0.5, 0.8, 1.1, 1.5 }) do
      waitFor(function() return S.t - t0 >= at end, 2000)
      shot(("b%02d_pop_%.2f"):format(i + 1, S.t - t0))
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
