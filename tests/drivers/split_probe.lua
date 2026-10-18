-- Driver: boots Emerald, opens the Amie room in split mode at several window sizes
-- (landscape and portrait), logging where the picture and the touch screen land and
-- taking a shot of each. A quick check of the split layout (Layout.dual).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/split_probe.lua love .

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
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  -- CLEAR EXTRACTED ART may be on in the player's options: a driver run never acts on it
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
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local R = X.amie
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  opts.display = "split"
  if X.import then waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120) end
  log("open room:", R.open())
  U.wait(10)
  local Display = require("src.core.game3.display")
  local function picture()
    local w, h = love.graphics.getDimensions()
    local scale, ox, oy, pw, ph = Display.fit(w, h)
    return ("%d,%d %dx%d @%s"):format(ox, oy, pw, ph, tostring(scale))
  end
  local function surface()
    local r = X.state().rect
    return r and ("%d,%d %dx%d @%s"):format(r.x, r.y, r.w, r.h, tostring(r.scale)) or "nil"
  end
  -- one layout (src/layout.lua Layout.dual): each window size once
  for _, size in ipairs({ { 1280, 720 }, { 1920, 1080 }, { 432, 768 }, { 720, 1280 }, { 540, 1200 } }) do
    love.window.setMode(size[1], size[2], { resizable = true, highdpi = true })
    U.wait(10)
    log(("%dx%d picture %-22s surface %s"):format(size[1], size[2], picture(), surface()))
    U.shot(game, ("%s/split_%dx%d.png"):format(dir, size[1], size[2]))
  end
  R.session.finish()
  U.wait(5)
  log("closed: picture back to", picture(), "mode", X.state().mode)
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
