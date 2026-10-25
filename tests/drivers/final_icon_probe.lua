-- Driver: the regimen picker's last secret page with every course open, so the final course's
-- picture shows: the Aron line's (the card's stage_poke_38) on Emerald / Ruby / FireRed, the
-- Larvitar line's (31) on Sapphire / LeafGreen. PROBE_FALLBACK=1 for PlayNav's drawn pictures;
-- PROBE_COURSE picks another course (its blurb logged).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/final_icon_probe.lua love .

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
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if os.getenv("PROBE_FALLBACK") == "1" and X and X._test and X._test.forceRom then X._test.forceRom(false) end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TREECKO"), 12) end
  U.wait(30)
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  log("open:", TR.open())
  U.wait(20)
  local T = TR.session
  T.enterCourses()
  U.wait(10)
  T.session.rec.fully = true
  for _, c in ipairs(T.courseList()) do TR.store.cleared()[c.id] = true end
  local Apps = X.apps
  local cs = Apps and Apps:get("training_courses")
  -- PROBE_COURSE: another course to pick (secret_09's blurb, the card's line 103, is ours)
  local pick = os.getenv("PROBE_COURSE") or "secret_12"
  cs.select(pick)
  U.wait(10)
  log("blurb:", T.courseBlurb(pick))
  local c = T.course("secret_12")
  log("version:", T.host and T.host.gameVersion and T.host.gameVersion(), "final course:", c.bots[1].species, c.bots[1].art)
  U.wait(10)
  log("shot", U.shot(game, dir .. "/final_icon.png") and "ok" or "MISSING")
  for _, x in ipairs(T.courseList()) do TR.store.cleared()[x.id] = nil end
  T.session.rec.fully = nil
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
