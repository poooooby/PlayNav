-- Driver: NaviPlay's achievements against the real recomp_achievements. NaviPlay registers its
-- rows, a few moments are noted through mod.exports.achievements, and the framework's own
-- list / isUnlocked / progress answer. Needs recomp_achievements installed.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/ach_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  U.wait(2)
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
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)

  local ex = game.mods and game.mods.exports
  local X = ex and ex.play_nav
  local ach = ex and ex.recomp_achievements
  if not ach then log("FAIL recomp_achievements is not loaded"); return end
  local mine = X and X.achievements
  if not mine then log("FAIL NaviPlay did not connect (no exports.achievements)"); return end
  log("framework", ach.apiVersion, "active", tostring(mine.active()), "ready", tostring(mine.isReady()))

  waitFor(function() return mine.isReady() end, 600)
  local rows = ach.list({ source = "mod:play_nav" })
  log("registered rows:", #rows)
  if #rows ~= #mine.defs and #rows == 0 then log("FAIL no rows registered") end

  local function check(id, want)
    local got = ach.isUnlocked("mod:play_nav:" .. id)
    log((got == want and "ok   " or "FAIL ") .. id, tostring(got))
  end

  mine.note("high_five"); mine.note("dance"); mine.note("wing")
  mine.note("regimen_end", { clear = true, medal = true }, { playerHits = 0, blocked = 1, bitsPopped = 3 }, false, false)
  mine.note("bag_cleared")
  U.wait(90)
  mine.tick()
  for _, id in ipairs({ "high_five", "dance", "wing", "first_award", "flawless", "shield", "bag_cleared" }) do check(id, true) end
  check("fever", false)
  local t = ach.totals("mod:play_nav")
  log("totals", t and (tostring(t.earned) .. "/" .. tostring(t.total)) or "nil")
  U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/play_nav") .. "/ach_toast.png")
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
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
