-- Driver: Berry Picker as the game plays it (Wooble's capture "Berry Game.mp4"): the demo
-- (the hand mid-drag, READY, START!), play (a bubble, a quick and a slow delivery, a wrong
-- berry), the last seconds, TIME'S UP, the rain, the heap, the smoke and medallions, the
-- buttons, the top screen's RESULTS card, then Quit back to petting. Shots at each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/berry_probe.lua love .
-- PROBE_SHAPE=gear|3ds picks the touch screen's shape (the option event only).

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
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
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
    Party.giveMon(s, C:require("species", "SPECIES_WURMPLE"), 5)
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display = "split"
  if os.getenv("PROBE_SHAPE") then
    loader.events:emit("mod.options_changed", { mod = "play_nav", key = "screen_shape", value = os.getenv("PROBE_SHAPE") })
    log("shape:", os.getenv("PROBE_SHAPE"), "W x H", tostring(X.W) .. "x" .. tostring(X.H))
  end
  local R, Apps, S = X.amie, X.apps, X.amie.session
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function press(id, ax, ay) local x, y = win(ax, ay); love.touchpressed(id, x, y, 0, 0, 1) end
  local function move(id, ax, ay) local x, y = win(ax, ay); love.touchmoved(id, x, y, 0, 0, 1) end
  local function release(id, ax, ay) local x, y = win(ax, ay); love.touchreleased(id, x, y, 0, 0, 1) end
  local function tapAt(id, ax, ay)
    if not ax then log("no point for", id); return end
    press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(3)
  end
  local function drag(id, x0, y0, x1, y1, steps)
    if not (x0 and x1) then log("no point for drag", id); return end
    press(id, x0, y0); U.wait(2)
    steps = steps or 10
    for i = 1, steps do move(id, x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps); U.wait(1) end
    release(id, x1, y1); U.wait(2)
  end

  log("open play:", R.openPlay())
  U.wait(10)
  log("show games:", S.showGames())
  U.wait(10)
  log("start berry:", S.startGame("berry", "easy"))
  local app = Apps:get("game_berry")
  local st = app.debugState()
  log("art:", tostring(st and st.art))
  local Dm = app.screen("demo")
  local function demoAt(f)
    waitFor(function() local x = Dm and Dm:frameOf(st.demoClip); return (x or 0) >= f or app.debugState().phase ~= "countdown" end, 60 * 120)
  end
  -- the demo: the window, the hand mid-drag, READY, START!
  demoAt(60);  shot("b01_demo_window")
  demoAt(170); shot("b02_demo_hand")
  demoAt(250); shot("b03_demo_note")
  demoAt(500); shot("b04_ready")
  demoAt(575); shot("b05_start")
  waitFor(function() return app.debugState().phase == "play" end, 60 * 120)
  -- play: wait for a bubble, deliver right quickly, then a wrong one, then a slow one
  local askers = {}
  local function visibleSlot()
    for i = 1, 3 do if app.wanted(i) then return i end end
  end
  -- the first Pokemon rising from below (it asks once it is up)
  waitFor(function()
    for i2 = 1, 3 do
      local sl = app.debugState().slots[i2]
      if sl.visible and (sl.lift or 0) > 0.35 and (sl.lift or 0) < 0.8 then return true end
    end
  end, 60 * 30)
  shot("b05b_rising")
  waitFor(function() return visibleSlot() ~= nil end, 60 * 60)
  -- the bubble open and settled (its wait clip shows the berry)
  waitFor(function()
    for i2 = 1, 3 do
      local sl = app.debugState().slots[i2]
      if sl.visible and sl.bal and sl.bal.clip:find("wait") then return true end
    end
  end, 60 * 30)
  U.wait(3)
  shot("b06_bubble")
  do
    local B = app.screen("balloon")
    for _, a in ipairs(B.active) do log("balloon clip", a.name, ("%.1f"):format(a.frame), "loop", tostring(a.loop)) end
    for i2, sl in ipairs(app.debugState().slots) do
      log("slot", i2, "visible", tostring(sl.visible), "want", tostring(sl.want), "bal", sl.bal and sl.bal.clip, sl.bal and tostring(sl.bal.after))
    end
  end
  local i = visibleSlot()
  if i then
    local bx, by = app.tapPoint("berry", app.wanted(i))
    local sx, sy = app.tapPoint("slot", i)
    press("d1", bx, by); U.wait(2)
    for k = 1, 6 do move("d1", bx + (sx - bx) * k / 10, by + (sy - by) * k / 10); U.wait(1) end
    shot("b07_dragging")
    for k = 7, 10 do move("d1", bx + (sx - bx) * k / 10, by + (sy - by) * k / 10); U.wait(1) end
    release("d1", sx, sy)
    U.wait(8)
    shot("b08_right_quick")
    log("score after the first:", app.debugState().score)
  end
  waitFor(function() return visibleSlot() ~= nil end, 60 * 60)
  i = visibleSlot()
  if not i then
    local x = app.debugState()
    log("no asker: t", ("%.2f"):format(x.t), "phase", x.phase, "rot n", x.rot and x.rot.n)
    for i2, sl in ipairs(x.slots) do
      log("  slot", i2, "vis", tostring(sl.visible), "ask", tostring(sl.asking), "lift", ("%.2f"):format(sl.lift or -1),
        "bal", sl.bal and sl.bal.clip or "-", sl.bal and tostring(sl.bal.after) or "-", "hide", ("%.2f"):format(sl.hideTimer or -1),
        "active", tostring(sl.active), "stay", tostring(sl.stay))
    end
  end
  if i then
    local wrong = app.wanted(i) % 3 + 1
    local bx, by = app.tapPoint("berry", wrong)
    local sx, sy = app.tapPoint("slot", i)
    drag("d2", bx, by, sx, sy)
    U.wait(8)
    shot("b09_mistake")
    log("misses after the wrong one:", app.debugState().misses)
  end
  -- a berry let go in the open: it falls and is lost, its kind gone from the tree until it
  -- is off the bottom
  do
    local bx, by = app.tapPoint("berry", 1)
    local mx, my = app.tapPoint("slot", 2)
    press("lost", bx, by); U.wait(2)
    for k = 1, 6 do move("lost", bx + (mx - bx) * k / 12, by + (my - 60 - by) * k / 12); U.wait(1) end
    release("lost", bx + (mx - bx) / 2, by + (my - 60 - by) / 2)
    U.wait(4)
    local f = app.debugState().falling[1]
    log("lost berry falling:", tostring(f ~= nil), f and ("%.0f"):format(f.y) or "-")
    shot("b09b_lost_falling")
    press("again", bx, by); U.wait(2); release("again", bx, by); U.wait(2)
    log("picked again while falling:", tostring(app.debugState().falling[1] ~= nil and "refused" or "n/a"))
    waitFor(function() return app.debugState().falling[1] == nil end, 60 * 10)
    log("back on the tree:", tostring(app.debugState().falling[1] == nil))
  end
  -- ten deliveries for the +10 count; which Pokemon asks is random (logged)
  for n = 1, 12 do
    if not waitFor(function() return visibleSlot() ~= nil end, 60 * 30) then break end
    i = visibleSlot()
    askers[#askers + 1] = tostring(i)
    local bx, by = app.tapPoint("berry", app.wanted(i))
    local sx, sy = app.tapPoint("slot", i)
    drag("d" .. (n + 2), bx, by, sx, sy, 4)
    if app.debugState().score == 10 then U.wait(6); shot("b10_count10") end
  end
  log("score:", app.debugState().score, "misses:", app.debugState().misses)
  log("askers (in order):", table.concat(askers, " "))
  -- PROBE_BERRY_SCORE=<n>: end on that many berries (the heap's size; the kinds past those
  -- delivered are filled in)
  if os.getenv("PROBE_BERRY_SCORE") then app.debugState().score = tonumber(os.getenv("PROBE_BERRY_SCORE")) end
  -- the last seconds: red, and a beat as each second turns over
  app.debugState().timer = 4.02
  waitFor(function() return app.debugState().timer < 3.97 end, 600)
  shot("b11_hurry_beat")
  waitFor(function() return app.debugState().timer < 3.6 end, 600)
  shot("b11_hurry")
  waitFor(function() return app.debugState().phase == "timeUp" end, 60 * 60)
  U.wait(20)
  shot("b12_timeup")
  waitFor(function() local x = app.debugState(); return x.phase == "rain" and (x.pt or 0) > 1.0 end, 60 * 60)
  shot("b13_rain")
  waitFor(function() local x = app.debugState(); return x.phase == "rain" and x.downAt and x.pt - x.downAt > 0.7 end, 60 * 60)
  shot("b14_heap")
  log("heap berries:", #(app.debugState().pile or {}), "score", app.debugState().score)
  waitFor(function() local x = app.debugState(); return x.phase == "smoke" and (x.pt or 0) > 0.12 end, 60 * 60)
  shot("b15_smoke")
  waitFor(function() local x = app.debugState(); return x.phase == "smoke" and (x.pt or 0) > 1.4 end, 60 * 60)
  shot("b16_medals")
  waitFor(function() return app.debugState().phase == "buttons" end, 60 * 60)
  U.wait(20)
  shot("b17_buttons")
  local res = R.state() and R.state().lastResult
  log("result:", res and res.stars, res and res.title, res and #(res.puffs or {}), "unlocked", res and tostring(res.unlockedNew))
  tapAt("quit", app.tapPoint("quit"))
  U.wait(20)
  log("after Quit: mode", R.state() and R.state().mode, "tool", tostring(R.state() and R.state().tool), "app", Apps:active().id)
  shot("b18_petting")
  S.finish()
  U.wait(5)
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
