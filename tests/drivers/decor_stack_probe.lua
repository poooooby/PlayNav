-- Driver: two gifts of the same cushion stack in Pokemon-Amie (a player report: the second gift of
-- a cushion already owned was lost). Two pending gifts that both turn out as one cushion are
-- tapped in the room, one box then the other: two copies owned. In DECORATE both copies are
-- placed, one after the other, then both put back with the tray, one after the other: two copies
-- still owned, the drawer counting 2 / 1 / 0 / 1 / 2. Each check logs "ok" or "FAIL"; shots at
-- each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/decor_stack_probe.lua love .
--   (POKEPORT_GAME=crystal POKEPORT_VERSION=crystal for Gen 2, red for Gen 1;
--   PROBE_CUSHION=<id> the cushion, else the first one not owned)

local GB = { red = 1, blue = 1, yellow = 1, green = 1, gold = 2, silver = 2, crystal = 2 }

local function body(game, log, dir, cleanup)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local fails = 0
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log((ok and "ok   " or "FAIL ") .. what)
    return ok
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
  U.wait(2)

  -- ------- into the field with a party
  local gen = GB[(os.getenv("POKEPORT_GAME") or "emerald"):lower()] or 3
  local function exports() return game.mods and game.mods.exports and game.mods.exports.play_nav end
  if gen == 3 then
    if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
      log("FAIL boot phase not reached; phase:", game.phase)
      return
    end
    local Xk = exports()
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
    game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
    U.wait(30)
    local Runtime = require("src.core.game3.runtime")
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local C = require("src.core.game3.constants").of(os.getenv("POKEPORT_VERSION") or "emerald")
    local Party = require("src.core.game3.party")
    pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
    local s = Runtime.getSession()
    if s then s.x, s.y = 14, 12 end
    Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
    Player.targetX, Player.targetY = 14, 12
    if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  else
    local Xk = exports()
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
    if gen == 2 then
      waitFor(function() return game.world and game.world.map end, 900)
    elseif not U.newGame(game) then
      log("FAIL no overworld")
      return
    end
    U.wait(30)
    local data = game.data
    local function newMon(species, level)
      if gen == 1 then return require("src.pokemon.Pokemon").new(data, species, level) end
      return require("src.battle.gen2.Mon").new(data, species, level)
    end
    if #(game.save.party or {}) == 0 then
      game.save.party = { newMon(gen == 1 and "PIKACHU" or "CYNDAQUIL", 20) }
    end
  end
  U.wait(60)
  local X = exports()
  if not X then log("FAIL no exports"); return end
  local loader = game.mods
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = "combined"
  local Extract = X._test.extract and X._test.extract()
  if Extract then
    waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 300)
    log("gen", gen, "art complete:", tostring(Extract.cacheComplete()))
  end

  local R, Apps = X.amie, X.apps
  local D, Store, V = R and R.decor, R and R.store, R and R.visitors
  if not (D and Store and V) then log("FAIL no Decor / Store / Visitors in exports.amie"); return end

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
  local function drag(id, x0, y0, x1, y1)
    if not (x0 and x1) then log("no point for drag", id); return end
    press(id, x0, y0); U.wait(2)
    for i = 1, 12 do move(id, x0 + (x1 - x0) * i / 12, y0 + (y1 - y0) * i / 12); U.wait(1) end
    release(id, x1, y1); U.wait(4)
  end

  -- ------- the cushion, owned by none to start with
  local decor = D.ensure(Store.decor())
  local id = os.getenv("PROBE_CUSHION")
  if not id then
    for _, r in ipairs(D.ITEMS) do
      if r.kind == "cushion" and D.count(decor, r.id) == 0 then id = r.id; break end
    end
  end
  if not (id and D.get(id) and D.get(id).kind == "cushion") then log("FAIL no cushion to test:", tostring(id)); return end
  decor.owned[id] = nil
  local room = Store.room()
  for i = #(room.items or {}), 1, -1 do if room.items[i].id == id then table.remove(room.items, i) end end
  Store.saveDecor(); Store.saveRoom()
  log("cushion:", id, D.name(id))

  -- copies owned, as the save holds them
  local function owned() return D.count(Store.decor(), id) end
  local function rawOwned() return tostring(Store.decor().owned[id]) end
  local function placed()
    local n = 0
    for _, it in ipairs(Store.room().items or {}) do if it.id == id then n = n + 1 end end
    return n
  end

  -- both gifts turn out as this cushion: the request and the roll for a probe record, nothing else
  local realRequest, realRoll = D.requestOf, D.roll
  cleanup.restore = function() D.requestOf, D.roll = realRequest, realRoll end
  D.requestOf = function(rec)
    if rec.probeItem then return { probeItem = rec.probeItem } end
    return realRequest(rec)
  end
  D.roll = function(req, dec, rng)
    if req.probeItem then return { kind = "item", id = req.probeItem, name = D.name(req.probeItem) } end
    return realRoll(req, dec, rng)
  end

  -- ------- the room: two gift boxes, tapped one after the other
  local ok, why = R.open()
  log("amie open:", tostring(ok), tostring(why))
  if not ok then return end
  local home, deco = Apps:get("home"), Apps:get("decorate")
  local function idle(app, extra)
    U.wait(3)
    waitFor(function() return not app.busy() end, 60 * 60)
    U.wait(extra or 3)
  end
  idle(home, 20)
  local vis = Store.visitors()
  vis.gifts = { { kind = "probe", probeItem = id }, { kind = "probe", probeItem = id } }
  Store.saveVisitors()
  U.wait(10)
  if home.menuOpen() then tapAt("closeMenu", home.giftPos(3)); idle(home) end
  shot("s01_two_gifts")
  check(#V.pending() == 2 and owned() == 0, ("two gifts waiting, none owned (pending %d, owned %d)"):format(#V.pending(), owned()))

  tapAt("gift2", home.giftPos(2))
  U.wait(30)
  shot("s02_first_claimed")
  check(#V.pending() == 1 and owned() == 1,
    ("first gift claimed: pending %d, owned %d (raw %s)"):format(#V.pending(), owned(), rawOwned()))

  tapAt("gift1", home.giftPos(1))
  U.wait(30)
  shot("s03_second_claimed")
  check(#V.pending() == 0 and owned() == 2,
    ("second gift claimed: pending %d, owned %d (raw %s)"):format(#V.pending(), owned(), rawOwned()))

  -- ------- DECORATE: place both, then put both back
  for attempt = 1, 3 do
    tapAt("pet" .. attempt, home.petPos())
    U.wait(6)
    if home.menuOpen() then break end
  end
  idle(home, 10)
  tapAt("deco", home.buttonPos("decorate"))
  waitFor(function() return Apps:active().id == "decorate" end, 60 * 60)
  idle(deco)

  local function drawerCount()
    for p, pg in ipairs(deco.pageList()) do
      for k, e in ipairs(pg.items) do if e.id == id then return e.count, p, k end end
    end
    return nil
  end
  -- the drawer open on the cushion's page; its cell
  local function openDrawer()
    tapAt("interior", deco.tapPoint("interior"))
    idle(deco)
    local _, p, k = drawerCount()
    for _ = 1, 40 do
      if not p or deco.state().page == p then break end
      tapAt("pageR", deco.tapPoint("pageRight"))
      idle(deco)
    end
    return k
  end
  local function state(step, wantPlaced, wantDrawer)
    local inDrawer = drawerCount()
    check(owned() == 2 and placed() == wantPlaced and inDrawer == wantDrawer,
      ("%s: owned %d (raw %s), placed %d, drawer %s"):format(step, owned(), rawOwned(), placed(), tostring(inDrawer)))
  end
  state("in DECORATE", 0, 2)

  local SPOTS = { { 60, 180 }, { 260, 180 } }
  for n, spot in ipairs(SPOTS) do
    local k = openDrawer()
    if not k then check(false, "the cushion is in the drawer"); break end
    shot(("s%02d_drawer_%d"):format(3 + n * 2 - 1, n))
    tapAt("cell" .. n, deco.tapPoint("cell", k))
    idle(deco)
    if not check(deco.state().held == id, ("copy %d held from the drawer (held %s)"):format(n, tostring(deco.state().held))) then break end
    local hx, hy = deco.tapPoint("held")
    local tx, ty = deco.tapPoint("room", { spot[1], spot[2] - 8 })
    drag("place" .. n, hx, hy, tx, ty)
    idle(deco)
    shot(("s%02d_placed_%d"):format(3 + n * 2, n))
    state(("copy %d placed"):format(n), n, 2 - n)
  end

  for n = 1, 2 do
    local it, at
    for i, x in ipairs(Store.room().items or {}) do if x.id == id then it, at = x, i; break end end
    if not check(it ~= nil, ("a placed copy to put back (%d)"):format(n)) then break end
    tapAt("pick" .. n, deco.tapPoint("room", { it.x, it.y }))
    idle(deco)
    check(deco.state().held == id and deco.state().mode == "hold",
      ("copy %d picked up from the room (held %s, mode %s, item %d)"):format(n, tostring(deco.state().held), deco.state().mode, at))
    tapAt("tray" .. n, deco.tapPoint("corner"))
    idle(deco)
    shot(("s%02d_put_back_%d"):format(7 + n, n))
    state(("copy %d put back"):format(n), 2 - n, n)
  end

  -- ------- out of DECORATE and Pokemon-Amie closed: the save keeps both
  tapAt("check", deco.tapPoint("corner"))
  waitFor(function() return Apps:active().id == "home" end, 60 * 60)
  idle(home, 10)
  shot("s10_room")
  R.session.finish()
  U.wait(10)
  check(owned() == 2 and placed() == 0, ("after closing: owned %d (raw %s), placed %d"):format(owned(), rawOwned(), placed()))
  log(fails == 0 and "ALL OK" or ("FAILURES " .. fails))
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
  local cleanup = {}
  local ok, err = xpcall(function() body(game, log, dir, cleanup) end, debug.traceback)
  if cleanup.restore then cleanup.restore() end
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
