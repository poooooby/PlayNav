-- Driver: a held mouse on the aim pad charges a shot without firing first. The click reaches
-- the surface twice (the engine's input.pointer event and the split screen's poll); the second
-- press must not restart the pointer (a restart reads as a release and fires).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/mouse_hold_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do if pred() then return true end; U.wait(1) end
    return pred() and true or false
  end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then log("FAIL boot"); return end
  game.mods.exports.play_nav._test.keepArt()
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  waitFor(function() return game.phase == "field" end, 1200)
  U.wait(60)
  local X = game.mods.exports.play_nav
  game.mods.modOptions.play_nav = game.mods.modOptions.play_nav or {}
  local opts = game.mods.modOptions.play_nav
  local saved = opts.display_mode
  opts.display_mode = "combined"
  local T = X.training.session
  local ok, err = pcall(function()
    X.training.open()
    waitFor(function() return T.session and T.session.mode == "core" end, 600)
    U.wait(20)
    T.enterCourses(); U.wait(20)
    T.startCourse("lv1_hp")
    waitFor(function() return T.sim and T.sim.phase == "play" end, 60 * 40)
    U.wait(30)
    local sim = T.sim
    local fired = 0
    local release0 = sim.releaseFire
    sim.releaseFire = function(self, ...)
      if self.player.charging then fired = fired + 1 end
      return release0(self, ...)
    end
    -- the middle of the touch screen, in window pixels
    local r = X._test.state.rect
    local mx, my = r.x + r.w * 0.5, r.y + r.h * 0.5
    -- the real button and cursor stood in for (the poll reads them every frame)
    local held = true
    local isDown0, getPos0 = love.mouse.isDown, love.mouse.getPosition
    love.mouse.isDown = function() return held end
    love.mouse.getPosition = function() return mx, my end
    -- the engine's event, then the poll's own press the next frame (both paths, one click)
    X._test.feedWindow("pressed", "mouse", mx, my, nil, "mouse")
    U.wait(1)
    X._test.feedWindow("pressed", "mouse", mx, my, nil, "mouse")
    U.wait(20)
    local whileHeld = fired
    log(("held: charging %s, shots fired while held %d"):format(tostring(sim.player.charging), whileHeld))
    held = false
    X._test.feedWindow("released", "mouse", mx, my, nil, "mouse")
    U.wait(2)
    love.mouse.isDown, love.mouse.getPosition = isDown0, getPos0
    log(("released: shots fired %d"):format(fired))
    log((whileHeld == 0 and fired == 1) and "PASS no shot while held, one on release" or "FAIL")
    sim.releaseFire = release0
    T.quitRegimen()
    U.wait(30)
    X.training.finish()
  end)
  opts.display_mode = saved
  if not ok then log("failed:", tostring(err)) end
  log("DONE")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local lf = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[#p + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(p, " "))
    if lf then lf:write(table.concat(p, " "), "\n"); lf:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if lf then lf:close() end
  love.event.quit()
end
