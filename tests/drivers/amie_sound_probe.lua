-- Driver: Pokemon-Amie's own sound effects. Every effect data/amie_sounds.lua names is in the
-- cache (the import rendered it), and G.se plays the game's effect (a handle), not the Emerald
-- stand-in, for a sample of events.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/amie_sound_probe.lua love .

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
    log("FAIL boot phase not reached")
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local G = X.amie.session
  local map = G.sounds or {}
  local have, missing, total = 0, {}, 0
  for event, id in pairs(map) do
    if id == false or event == "EVIDENCE" then id = {} end
    for _, one in ipairs(type(id) == "table" and id or { id }) do
      total = total + 1
      local ok, sd = pcall(X.assets.sound, one)
      if ok and sd then have = have + 1 else missing[#missing + 1] = event .. "=" .. one end
    end
  end
  log(("effects named in the map: %d, in the cache: %d"):format(total, have))
  if #missing > 0 then log("missing:", table.concat(missing, " ")) end
  local stand = 0
  local host = G.host or nil
  for _, ev in ipairs({ "select", "stroke", "bite", "wake", "head_just", "tile_swap", "berry_give", "visitor_enter" }) do
    local h = G.se(ev, "SE_SELECT")
    log(("G.se(%s): %s"):format(ev, h and "the game's effect" or "the stand-in"))
    if not h then stand = stand + 1 end
    U.wait(20)
  end
  log("stand-ins played:", stand)
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
