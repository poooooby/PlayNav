-- Driver: the Konami code's alley (src/training/rocket.lua). Opens Super Training's home screen,
-- enters the code on the pad (up up down down left right B A START, through the engine's input
-- queue), shoots the R's unlock and the home screen with its new button, taps it, shoots the way
-- in (the R flashing), the walk, the dealer, his greeting and the shop; buys an R+ and an R with
-- the touch screen's buttons, is refused short of money and with a full drawer, leaves with the
-- red button and shoots the home screen again; then hangs the R+ and punches it clear (+64).
-- Logs the canvases switched to by the 3D code inside love.draw (there must be none).
-- PROBE_FALLBACK=1: PlayNav's own art; PROBE_FLAT=1: no 3D (the flat alley); SHOT_W / SHOT_H.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/rocket_probe.lua love .

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
  local function waitSecs(sec) local t = love.timer.getTime(); while love.timer.getTime() - t < sec do U.wait(1) end end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
    if os.getenv("PROBE_FALLBACK") == "1" and Xk and Xk._test and Xk._test.forceRom then Xk._test.forceRom(false) end
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 10)
  end
  U.wait(30)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = "combined"
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local TR = X.training
  local T = TR.session
  local Rk = T.rocket
  local Scene = T.rocketScene
  if not Rk then log("FAIL no rocket module"); return end
  if os.getenv("PROBE_FLAT") == "1" and Scene then Scene.failed, Scene.why = true, "PROBE_FLAT" end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function tapAt(id, ax, ay)
    local x, y = win(ax, ay)
    love.touchpressed(id, x, y, 0, 0, 1); U.wait(2); love.touchreleased(id, x, y, 0, 0, 1); U.wait(3)
  end
  local function tapRect(id, r) tapAt(id, r.x + r.w / 2, r.y + r.h / 2) end

  -- canvases switched to inside love.draw by the alley's code (render3d / rocket_scene: the
  -- Thor breaks on those); ui_art's lazily drawn pictures counted apart
  local switches, artSwitches, inDraw = 0, 0, false
  -- every canvas switched to inside love.draw, by the innermost of PlayNav's files that asked
  local byFile = {}
  do
    local origDraw, origSet = love.draw, love.graphics.setCanvas
    love.draw = function(...) inDraw = true; local r = { pcall(origDraw, ...) }; inDraw = false
      if not r[1] then error(r[2], 0) end end
    love.graphics.setCanvas = function(...)
      if inDraw and select("#", ...) > 0 and (...) ~= nil then
        local tb = debug.traceback("", 2)
        if tb:find("render3d", 1, true) or tb:find("rocket_scene", 1, true) then switches = switches + 1
        elseif tb:find("ui_art", 1, true) then artSwitches = artSwitches + 1 end
        local file = tb:match("play_nav[/\\]([%w_/\\]+%.lua)") or "(not PlayNav)"
        byFile[file] = (byFile[file] or 0) + 1
      end
      return origSet(...)
    end
  end
  local function canvasLog()
    local parts = {}
    for f, n in pairs(byFile) do parts[#parts + 1] = f .. " " .. n end
    table.sort(parts)
    log("canvases switched to inside love.draw, by file: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
  end

  local ok, err = pcall(function()
    log("open:", TR.open())
    U.wait(20)
    shot("r00_home")
    -- the code, a button a few frames apart
    for _, b in ipairs(Rk.KONAMI) do U.tap(game, b); U.wait(4) end
    U.wait(4)
    log("unlocked:", T.rocketUnlocked(), "busy:", T.rocketBusy())
    local SM = require("src.ui.game3.start_menu")
    waitSecs(0.3)
    log("start menu open after the code:", SM.isOpen and SM.isOpen())
    shot("r01_unlock_black")
    waitSecs(0.6)
    shot("r02_unlock_r")
    waitFor(function() return not T.rocketBusy() end, 2000)
    U.wait(10)
    shot("r03_home_button")
    -- the R button
    local core = X.apps:get("training_core")
    tapRect(1, core.geometry().ROCKET)
    log("going:", T.session.trans and T.session.trans.to)
    local M = T.music
    local function musicLog(when)
      log(("music %s: playing %s, fading %d, field held %s"):format(when, tostring(M and M.current),
        M and #M.fading or 0, tostring(M and M.holding)))
    end
    waitFor(function() local v = T.transView("top"); return v and v.logo and v.logo >= 0.2 end, 3000)
    shot("r04a_logo_in")
    musicLog("as the R comes in")
    waitFor(function() local v = T.transView("top"); return v and v.logo and v.logo >= 0.62 end, 3000)
    shot("r04b_logo_glint")
    waitFor(function() local v = T.transView("top"); return v and v.logoA and v.logoA <= 0.5 end, 3000)
    shot("r04c_logo_out")
    waitFor(function() return T.session.mode == "rocket" and not T.session.trans end, 3000)
    shot("r05_walk_start")
    waitSecs(1.6)
    shot("r06_walk")
    waitFor(function() local st = Rk.state(); return st and st.phase == "greet" and st.typed end, 3000)
    U.wait(10)
    shot("r07_greet")
    local st = Rk.state()
    log("greet:", st.line)
    local app = X.apps:get("training_rocket")
    local Gm = app.geometry()
    tapRect(2, Gm.BOX)
    waitFor(function() return Rk.state().shopT >= 1 end, 600)
    U.wait(10)
    shot("r08_shop")
    -- money for the run; an R+ (the seventh: HP R+) then an R
    Runtime.getSession().money = 40000
    for _ = 1, 6 do tapRect(3, Gm.DOWN) end
    U.wait(5)
    shot("r09_scrolled")
    tapRect(4, Gm.PICK)
    U.wait(5)
    shot("r10_confirm")
    log("asked:", Rk.state().line)
    tapRect(5, Gm.YES)
    U.wait(10)
    st = Rk.state()
    log("bought:", st.id, "money", st.money, "drawer", st.bags, "said:", st.line)
    shot("r11_sold")
    tapRect(6, Gm.UP)
    tapRect(7, Gm.PICK); tapRect(8, Gm.YES)
    U.wait(5)
    st = Rk.state()
    log("bought an R:", "money", st.money, "drawer", st.bags)
    -- short now (5,000)
    tapRect(9, Gm.PICK); tapRect(10, Gm.YES)
    U.wait(5)
    st = Rk.state()
    log("short:", "money", st.money, "drawer", st.bags, "said:", st.line)
    shot("r12_broke")
    -- a full drawer
    local bags = TR.store.bags()
    local before = #bags
    while #bags < 12 do bags[#bags + 1] = "hp_s" end
    Runtime.getSession().money = 999999
    tapRect(11, Gm.PICK); tapRect(12, Gm.YES)
    U.wait(5)
    st = Rk.state()
    log("full:", "money", st.money, "drawer", st.bags, "said:", st.line)
    shot("r13_full")
    while #bags > before do table.remove(bags) end
    -- leave
    tapRect(13, Gm.BACK)
    waitFor(function() local s2 = Rk.state(); return s2 and s2.typed end, 600)
    U.wait(5)
    shot("r14_bye")
    log("bye:", Rk.state().line)
    musicLog("in the alley")
    waitFor(function() return T.session.trans ~= nil end, 3000)
    U.wait(3)
    musicLog("leaving")
    waitFor(function() return T.session.mode == "core" and not T.session.trans end, 3000)
    U.wait(10)
    musicLog("back home")
    shot("r15_home_again")
    log("back home: mode", T.session.mode, "button still:", T.rocketUnlocked(), "music held:", T.music and T.music.holding)
    log(("canvases switched to by the alley's 3D inside love.draw: %d (ui_art's pictures: %d)"):format(switches, artSwitches))
    local stats = Scene and Scene.stats()
    if stats then log(("alley renders: prepared %d placed %d waiting %d"):format(stats.prepared, stats.placed, stats.waiting)) end
    log("alley 3D:", Scene and Scene.available())
    -- hang the R+ and punch it clear
    local idx
    for i, id in ipairs(TR.store.bags()) do if id == "hp_rp" then idx = i end end
    if idx then
      T.HIT_LOCK, T.FINISH_MOVE = 0, false
      local hp0 = TR.host.evsOf(T.session.mon).hp
      log("hang hp_rp:", T.attachBag(idx))
      for _ = 1, 60 do T.hitBag("tap") end
      log(("HP EVs %d -> %d"):format(hp0, TR.host.evsOf(T.session.mon).hp))
      U.wait(5)
    end
    -- the drawer shows the R bag with its glow
    T.enterBags()
    U.wait(15)
    shot("r16_drawer")
  end)
  if not ok then log("FAIL", tostring(err)) end
  canvasLog()
  log("DONE")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
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
