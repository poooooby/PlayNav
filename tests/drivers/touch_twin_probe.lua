-- Driver: a finger on a phone is also reported as a mouse (love.mouse.isDown / getPosition
-- follow it); NaviPlay's mouse poll used to turn that into a second tap at the same spot, so the
-- bag drawer opened and shut at once (and stayed shut after) and Amie's Pokemon took no tap
-- (its menu opened and closed). Each tap here comes with that twin, as iOS (and a touchscreen
-- PC) delivers it; the drawer must open and stay open on every visit, the room's menu must open.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/touch_twin_probe.lua love .

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
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
  end
  waitFor(function() return game.phase == "field" end, 1200)
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display_mode
  opts.display_mode = "combined"
  local Apps = X.apps

  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end

  -- every press the apps receive, by pointer id: a twin shows up as a "mouse" press
  local presses, twins = {}, 0
  local realPointer = Apps.pointer
  Apps.pointer = function(self, ev, rec, g)
    if ev.phase == "pressed" then presses[#presses + 1] = tostring(ev.id) end
    return realPointer(self, ev, rec, g)
  end
  local function pressesSince(n)
    local out = {}
    for i = n + 1, #presses do out[#out + 1] = presses[i] end
    return table.concat(out, ",")
  end

  -- a tap with its mouse twin: while the finger is down the mouse reads down at the same spot
  local real = { getOS = love.system.getOS, isDown = love.mouse.isDown, getPosition = love.mouse.getPosition,
    getTouches = love.touch and love.touch.getTouches }
  local finger = nil
  love.mouse.isDown = function(b) if finger then return b == 1 end return real.isDown(b) end
  love.mouse.getPosition = function() if finger then return finger.x, finger.y end return real.getPosition() end
  if love.touch then
    love.touch.getTouches = function() if finger then return { finger.id } end return {} end
  end
  local function twinTap(id, ax, ay)
    local x, y = win(ax, ay)
    local before = #presses
    finger = { id = id, x = x, y = y }
    love.touchpressed(id, x, y, 0, 0, 1)
    U.wait(3)
    love.touchreleased(id, x, y, 0, 0, 1)
    finger = nil
    U.wait(6)
    local got = pressesSince(before)
    log("   tap", id, "mode", X.state().mode, "presses", got)
    twins = twins + ((got:find("mouse", 1, true) ~= nil) and 1 or 0)
  end
  local function mid(r) return r.x + r.w / 2, r.y + r.h / 2 end

  local failures = 0
  local function expect(ok, what)
    if not ok then failures = failures + 1 end
    log(ok and "ok  " or "FAIL", what)
  end

  local function scenario(osName)
    love.system.getOS = function() return osName end
    -- ------- Super Training's home: the drawer, three visits
    log("--", osName, "training open:", tostring(X.training.open()))
    local core = Apps:get("training_core")
    local bags = Apps:get("training_bags")
    local T = X.training.session
    waitFor(function() return T.session and T.session.mode == "core" and not (T.session.trans) end, 600)
    U.wait(20)
    for visit = 1, 3 do
      twinTap("bags" .. visit, mid(core.geometry().BAGS))
      U.wait(20)
      expect(T.session and T.session.mode == "bags", ("%s: the drawer opens and stays open (visit %d)"):format(osName, visit))
      twinTap("back" .. visit, mid(bags.geometry().BACK))
      -- the slide-out runs on screen time, slower than frames in a driver run
      local t0 = love.timer.getTime()
      while not (T.session and T.session.mode == "core") and love.timer.getTime() - t0 < 3 do U.wait(1) end
      U.wait(10)
      expect(T.session and T.session.mode == "core", ("%s: its return button closes it (visit %d, mode %s)"):format(
        osName, visit, tostring(T.session and T.session.mode)))
    end
    X.training.finish()
    U.wait(30)
    -- ------- Amie's room: a tap on the Pokemon opens the menu
    log("--", osName, "amie open:", tostring(X.amie.open()))
    local home = Apps:get("home")
    U.wait(3)
    waitFor(function() return not home.busy() end, 60 * 60)
    U.wait(20)
    twinTap("pet", home.petPos())
    U.wait(10)
    expect(home.menuOpen(), osName .. ": a tap on the Pokemon opens the room's menu")
    X.amie.session.finish()
    U.wait(30)
  end

  local ok, err = pcall(function()
    scenario("iOS")
    scenario("Windows")
  end)
  expect(twins == 0, ("no tap reached the apps twice (%d did)"):format(twins))
  Apps.pointer = realPointer
  love.system.getOS, love.mouse.isDown, love.mouse.getPosition = real.getOS, real.isDown, real.getPosition
  if love.touch then love.touch.getTouches = real.getTouches end
  opts.display_mode = savedDisplay
  if not ok then log("probe body failed:", tostring(err)); failures = failures + 1 end
  log(failures == 0 and "PASS" or ("FAILURES " .. failures))
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
