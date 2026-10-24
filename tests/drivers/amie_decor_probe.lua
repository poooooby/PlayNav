-- Driver: Pokemon-Amie's room and DECORATE as the game plays them (kawaii_lower /
-- customize layouts): the room, the menu with its bubbles,
-- DECORATE's entry, both drawers and a page turn, a cushion picked, dragged and settled on
-- a seat, picked up again and put back, a puff set on its spot, the wallpaper's slide,
-- the check, and the puff falling in back in the room. Shots at each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/amie_decor_probe.lua love .

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
  local function waitSecs(secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do U.wait(1) end
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
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = "combined"
  local Extract = X._test.extract and X._test.extract()
  if Extract then
    waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 300)
    log("art complete:", tostring(Extract.cacheComplete()))
  end
  local R = X.amie
  local Apps = X.apps
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
    press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(4)
  end
  local function drag(id, x0, y0, x1, y1, steps)
    if not (x0 and x1) then log("no point for drag", id); return end
    press(id, x0, y0); U.wait(2)
    steps = steps or 12
    for i = 1, steps do move(id, x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps); U.wait(1) end
    release(id, x1, y1); U.wait(4)
  end

  -- something to decorate with: every cushion and a few puffs
  local decor = R.decor.ensure(R.store.decor())
  local n = 0
  for _, r in ipairs(R.decor.ITEMS) do if r.kind == "cushion" and n < 20 then R.decor.own(decor, r.id); n = n + 1 end end
  R.decor.own(decor, "wall/blue"); R.decor.own(decor, "wall/orange")
  for _, id in ipairs({ "puff/mocha_basic", "puff/sweet_basic", "puff/mint_frosted" }) do R.rules.jarAdd(R.puffs(), id) end
  R.store.saveDecor(); R.store.savePuffs()

  local ok, why = R.open()
  log("amie open:", tostring(ok), tostring(why))
  if not ok then return end
  local home, deco = Apps:get("home"), Apps:get("decorate")
  -- the screens' own clock runs on the surface's ticks, slower than the wall clock in a
  -- driver run: wait for them to settle, not for seconds
  local function idle(app, extra)
    U.wait(3)
    waitFor(function() return not app.busy() end, 60 * 60)
    U.wait(extra or 3)
  end
  -- a few ticks into something moving
  local function into(app, ticks)
    for _ = 1, ticks do U.wait(1) end
  end
  idle(home, 20)
  shot("a01_room")
  for attempt = 1, 3 do
    local px, py = home.petPos()
    tapAt("pet" .. attempt, px, py)
    U.wait(6)
    if home.menuOpen() then break end
  end
  log("menu open:", tostring(home.menuOpen()))
  idle(home, 30)
  shot("a02_menu")
  U.wait(40)
  shot("a03_menu_later")
  tapAt("deco", home.buttonPos("decorate"))
  waitFor(function() return Apps:active().id == "decorate" end, 60 * 60)
  into(deco, 2)
  shot("a04_to_decorate")
  idle(deco)
  log("mode:", R.state() and R.state().mode, "app:", Apps:active().id)
  shot("a05_decorate")
  tapAt("interior", deco.tapPoint("interior"))
  idle(deco)
  log("drawer:", deco.state().mode, deco.state().tab, "category", tostring(deco.state().category))
  shot("a06_drawer_interior")
  tapAt("pageR", deco.tapPoint("pageRight"))
  into(deco, 3)
  shot("a07_page_turning")
  idle(deco)
  log("page:", deco.state().page, "category", tostring(deco.state().category))
  shot("a08_page2")
  tapAt("pageL", deco.tapPoint("pageLeft"))
  idle(deco)
  -- a cushion: picked, then dragged near the right-hand seat
  tapAt("cell1", deco.tapPoint("cell", 1))
  idle(deco)
  log("held:", tostring(deco.state().held), deco.state().mode)
  shot("a09_cushion_held")
  local hx, hy = deco.tapPoint("held")
  local sx, sy = deco.tapPoint("seatHold", 2)
  drag("dragC", hx, hy, sx - 6, sy + 4)
  idle(deco)
  local room = R.store.room()
  local it = room.items[#room.items]
  log("placed:", it and it.id, it and it.x, it and it.y, "mode", deco.state().mode)
  shot("a10_cushion_seated")
  -- tapped again it is held where it is; the tray puts it back
  local ix, iy = deco.tapPoint("seat", 2)
  tapAt("pickC", ix, iy - 6)
  idle(deco)
  log("re-held:", tostring(deco.state().held), deco.state().mode)
  shot("a11_cushion_reheld")
  tapAt("tray", deco.tapPoint("corner"))
  idle(deco)
  log("after put back: items", #room.items, "mode", deco.state().mode)
  -- and down again, left free on the floor
  tapAt("interior2", deco.tapPoint("interior"))
  idle(deco)
  tapAt("cell1b", deco.tapPoint("cell", 1))
  idle(deco)
  hx, hy = deco.tapPoint("held")
  drag("dragC2", hx, hy, hx - 70, hy - 10)
  idle(deco)
  it = room.items[#room.items]
  log("free:", it and it.id, it and it.x, it and it.y)
  shot("a12_cushion_free")
  -- a puff on its spot
  tapAt("puffs", deco.tapPoint("puffs"))
  idle(deco)
  shot("a13_drawer_puffs")
  tapAt("puff1", deco.tapPoint("cell", 1))
  idle(deco)
  shot("a14_puff_held")
  hx, hy = deco.tapPoint("held")
  local px2, py2 = deco.tapPoint("puffSpot")
  drag("dragP", hx, hy, px2 + 4, py2 + 3)
  into(deco, 2)
  shot("a15_puff_settling")
  idle(deco)
  log("puff out:", tostring(room.puffOut), "mode", deco.state().mode)
  shot("a16_puff_set")
  -- the wallpaper slides
  tapAt("wallR", deco.tapPoint("wallRight"))
  into(deco, 3)
  shot("a17_wall_sliding")
  idle(deco)
  log("wallpaper:", room.wallpaper)
  shot("a18_wall_next")
  -- the check: back to the room, the puff falling in
  tapAt("check", deco.tapPoint("corner"))
  waitFor(function() return Apps:active().id == "home" end, 60 * 60)
  waitFor(function() return home.falling() end, 600)
  into(home, 4)
  log("mode:", R.state() and R.state().mode, "app:", Apps:active().id)
  shot("a19_room_puff_falling")
  idle(home, 20)
  shot("a20_room_decorated")
  R.session.finish()
  U.wait(10)
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
