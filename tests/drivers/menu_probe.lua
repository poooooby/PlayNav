-- Driver: the NaviPlay menu. START -> NAVIPLAY (one entry; the old AMIE / TRAINING entries
-- gone), the menu up with its two cards; a real touch on Super Training's card (the sink,
-- the shutters, its home behind them), its return back to the menu; Pokemon-Amie's card (the
-- fade, the room, no arrows on the strip), its CLOSE back to the menu; the x leaves.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/menu_probe.lua love .

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
  local function waitSecs(s) local t = love.timer.getTime(); while love.timer.getTime() - t < s do U.wait(1) end end
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
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) < 2 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 12)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local Apps = X.apps
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function active() return Apps:active() and Apps:active().id or "?" end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function tapAt(id, ax, ay)
    local x, y = win(ax, ay)
    love.touchpressed(id, x, y, 0, 0, 1); U.wait(2)
    love.touchreleased(id, x, y, 0, 0, 1); U.wait(4)
  end

  -- ------- START: one NAVIPLAY entry
  local StartMenu = require("src.ui.game3.start_menu")
  waitFor(function() return game.phase == "field" end, 1200)
  U.wait(60)
  for _ = 1, 5 do
    U.tap(game, "start")
    U.wait(30)
    if #(StartMenu.ENTRIES or {}) > 0 then break end
  end
  local idx, ids = nil, {}
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    ids[#ids + 1] = tostring(e.id)
    if e.id == "play_nav" then idx = i end
  end
  log("start menu entries:", table.concat(ids, ","))
  if not idx then log("FAIL no NAVIPLAY entry"); return end
  local moves = idx - (StartMenu.cursor or 1)
  for _ = 1, math.abs(moves) do U.tap(game, moves > 0 and "down" or "up"); U.wait(6) end
  shot("m00_start_menu")
  U.tap(game, "a")
  U.wait(30)
  log("after NAVIPLAY: active", active(), "shown", tostring(X.menu.shown()), "surface", X.state().mode)
  shot("m01_menu")

  local M = X.menu.app
  -- ------- Super Training's card
  local tx, ty = M.tapPoint("card", "training")
  local x, y = win(tx, ty)
  love.touchpressed("t1", x, y, 0, 0, 1); U.wait(3)
  shot("m02_training_held")
  love.touchreleased("t1", x, y, 0, 0, 1)
  waitSecs(0.3)
  shot("m03_shutters")
  waitFor(function() return X.training.session.session ~= nil end, 600)
  waitSecs(1.0)
  log("training card: active", active(), "session", tostring(X.training.session.session ~= nil))
  shot("m04_training_home")
  local core = Apps:get("training_core")
  local cl = core and core.geometry().CLOSE
  if cl then tapAt("t2", cl.x + cl.w / 2, cl.y + cl.h / 2) end
  U.wait(20)
  log("after its return: active", active(), "shown", tostring(X.menu.shown()))
  shot("m05_back_to_menu")

  -- ------- Pokemon-Amie's card
  tx, ty = M.tapPoint("card", "amie")
  tapAt("t3", tx, ty)
  waitSecs(0.2)
  shot("m06_amie_fade")
  waitFor(function() return X.amie.session.session ~= nil end, 600)
  waitSecs(1.5)
  log("amie card: active", active(), "session", tostring(X.amie.session.session ~= nil))
  shot("m07_amie_room")
  local home = Apps:get("home")
  local cx, cy = home.closePos()
  tapAt("t4", cx, cy)
  waitFor(function() return X.amie.session.session == nil end, 600)
  U.wait(20)
  log("after its CLOSE: active", active(), "shown", tostring(X.menu.shown()))
  shot("m08_back_again")

  -- ------- the x
  tx, ty = M.tapPoint("close")
  tapAt("t5", tx, ty)
  U.wait(20)
  log("after the x: active", active(), "shown", tostring(X.menu.shown()), "surface", X.state().mode)
  shot("m09_closed")
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
