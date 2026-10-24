-- Driver: Speed EVs and the trainee's shot speed: a regimen started at 0 Speed EVs, then
-- (Super Training still open, as a vitamin would) 252, each logging the regimen's ballSpeedMult
-- and a fired shot's speed.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/shot_speed_probe.lua love .

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
    local mon = s.party[1]
    local Pokemon = require("src.core.game3.pokemon")
    local function setSpe(v)
      local evs = Pokemon.evsOf(mon)
      evs.spe = v
      pcall(Pokemon.applyStats, mon)
    end
    setSpe(0)
    TR.open()
    U.wait(20)
    for _, c in ipairs(TR.session.courseList()) do TR.store.cleared()[c.id] = true end
    for _, v in ipairs({ 0, 252 }) do
      setSpe(v)
      TR.session.enterCourses()
      U.wait(10)
      local started, why = TR.session.startCourse("lv1_spe")
      log("spe", v, "start", started, why)
      waitFor(function() return TR.state().mode == "regimen" end, 900)
      waitFor(function() return TR.session.sim and TR.session.sim.phase == "play" end, 60 * 60)
      local S = TR.session.sim
      S.guts = 1
      local sh = S:fire(0)
      log(("spe %d: session evs.spe %s, ballSpeedMult %.3f, shot vz %.3f"):format(v,
        tostring(TR.session.session and TR.session.session.evs.spe), S.mods.ballSpeedMult or -1, sh.vz))
      TR.session.forceEnd("timeout")
      waitFor(function() return TR.state().mode ~= "regimen" end, 60 * 60)
      pcall(TR.session.leaveResult)
      U.wait(30)
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
