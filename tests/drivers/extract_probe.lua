-- Driver: bring the player's extracted art up to the recipe's version (after a recipe bump),
-- then log what the cache holds. Never clears anything; needs the card image imported.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/extract_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
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
  -- CLEAR EXTRACTED ART may be on in the player's options: a driver run never acts on it
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  end
  log("art kept from CLEAR:", tostring(game.mods and game.mods.exports and game.mods.exports.play_nav ~= nil))
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Map = require("src.core.game3.map")
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  U.wait(60)
  local X = game.mods and game.mods.exports and game.mods.exports["play_nav"]
  local Extract = X and X._test.extract and X._test.extract()
  if not Extract then log("FAIL no Extract"); return end
  waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 300)
  U.wait(10)
  log("state after boot:", Extract.state, "complete:", tostring(Extract.cacheComplete()),
    "import present:", tostring(Extract.importPresent()))
  -- PROBE_DIFFER=<key,key,...> | all: alter those fingerprints first, as a dump whose bytes
  -- differ there would (src/import/fingerprint.lua's keys); a plain PROBE_FORCE run restores
  local differ = os.getenv("PROBE_DIFFER")
  if differ and differ ~= "" then
    local rows = Extract.fingerprints and Extract.fingerprints()
    if not rows then log("FAIL fingerprints are off"); return end
    local n = 0
    for key, fp in pairs(rows) do
      if differ == "all" or ("," .. differ .. ","):find("," .. key .. ",", 1, true) then
        rows[key] = { size = fp.size, crc = fp.crc == "00000000" and "00000001" or "00000000" }
        n = n + 1
      end
    end
    log("fingerprints altered:", n)
  end
  -- PROBE_FORCE=1: extract again even though the cache reads complete
  if not Extract.cacheComplete() or os.getenv("PROBE_FORCE") == "1" then
    if not Extract.importPresent() then log("FAIL the card image is not imported"); return end
    log("extract started:", tostring(Extract.start()))
    waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 300)
    U.wait(10)
  end
  log("state:", Extract.state, "complete:", tostring(Extract.cacheComplete()),
    "differ:", tostring(Extract.differs), "failed:", tostring(Extract.failed))
  log("message:", tostring(Extract.message))
  local m = Extract.cacheManifest and Extract.cacheManifest()
  local n = 0
  for id, why in pairs(m and m.missing or {}) do n = n + 1; if n <= 5 then log("missing", id, why) end end
  log("missing total", n)
  local A = X._test.assets and X._test.assets()
  for _, id in ipairs({ "lyt/amie_deco/bar_title", "lyt/amie_room/gift", "lyt/amie_room/frame" }) do
    local ok, img = pcall(function() return A and A.image(id) end)
    log("image", id, ok and img and "ok" or "MISSING")
  end
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
