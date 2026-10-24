-- Driver: Pokemon-Amie's SWITCH screen as the game plays it: the room's menu, SWITCH pressed,
-- the party list sliding in (the heart on the Pokemon in the room, its meters), another
-- medallion chosen (its meters, the green Switch Pokemon! button), the button pressed (the
-- heart moves), the list sliding out and the new Pokemon coming into the room; then SWITCH
-- again and the return button. Shots at each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/amie_switch_probe.lua love .

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
  -- PROBE_SLOTS (engine species slots, comma-separated) sets the party instead
  local slots = {}
  for v in (os.getenv("PROBE_SLOTS") or ""):gmatch("%d+") do slots[#slots + 1] = tonumber(v) end
  if s and #slots > 0 then
    while #(s.party or {}) > 0 do table.remove(s.party) end
    for _, sp in ipairs(slots) do Party.giveMon(s, sp, 50) end
  end
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
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display_mode
  opts.display_mode = "combined"
  local R, Apps = X.amie, X.apps
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function press(id, ax, ay) local x, y = win(ax, ay); love.touchpressed(id, x, y, 0, 0, 1) end
  local function release(id, ax, ay) local x, y = win(ax, ay); love.touchreleased(id, x, y, 0, 0, 1) end
  local function tapAt(id, ax, ay)
    if not ax then log("no point for", id); return end
    press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(4)
  end

  local ok, err = pcall(function()
    -- different meters per Pokemon, so the panel changes as each is chosen
    local party = Runtime.getSession().party
    local levels = { { 120, 60, 200 }, { 255, 255, 40 }, { 20, 150, 255 } }
    for i = 1, 3 do
      local key = R.monKey and R.monKey(party[i])
      local m = key and R.store.meters(key)
      if m then m.affection, m.fullness, m.enjoyment = levels[i][1], levels[i][2], levels[i][3] end
    end
    log("amie open:", R.open())
    local home = Apps:get("home")
    local function idle(extra)
      U.wait(3)
      waitFor(function() return not home.busy() end, 60 * 60)
      U.wait(extra or 3)
    end
    local function swIdle()
      waitFor(function() local x = home.switchState(); return not x or (x.phase == "open" and not x.pressing and not x.waiting) end, 60 * 30)
      U.wait(4)
    end
    idle(20)
    for attempt = 1, 3 do
      local px, py = home.petPos()
      tapAt("pet" .. attempt, px, py)
      U.wait(6)
      if home.menuOpen() then break end
    end
    idle(20)
    shot("w01_menu")
    tapAt("switch", home.buttonPos("switch"))
    waitFor(function() local x = home.switchState(); return x and x.phase == "in" end, 120)
    U.wait(1)
    shot("w02_sliding_in")
    swIdle()
    shot("w03_list")
    log("list:", home.switchState() and home.switchState().sel, "heart", home.switchState() and home.switchState().heart)
    tapAt("slot2", home.switchPos("slot", 2))
    swIdle()
    shot("w04_slot2")
    tapAt("slot3", home.switchPos("slot", 3))
    swIdle()
    shot("w05_slot3")
    tapAt("button", home.switchPos("button"))
    waitFor(function() local x = home.switchState(); return x and x.waiting end, 120)
    U.wait(2)
    shot("w06_heart_moved")
    waitFor(function() return home.switchState() == nil end, 60 * 30)
    U.wait(2)
    shot("w07_room_new")
    log("in the room:", R.state() and R.state().name)
    waitFor(function() return not home.busy() end, 60 * 10)
    U.wait(30)
    shot("w08_room_entered")
    -- again, then the return button
    for attempt = 1, 3 do
      local px, py = home.petPos()
      tapAt("pet" .. attempt, px, py)
      U.wait(6)
      if home.menuOpen() then break end
    end
    idle(10)
    tapAt("switch2", home.buttonPos("switch"))
    waitFor(function() return home.switchState() ~= nil end, 120)
    swIdle()
    shot("w09_list_again")
    log("heart now:", home.switchState() and home.switchState().heart)
    tapAt("return", home.switchPos("return"))
    waitFor(function() return home.switchState() == nil end, 60 * 30)
    U.wait(4)
    shot("w10_returned")
    R.session.finish()
    U.wait(5)
  end)
  if not ok then log("probe body failed:", tostring(err)) end
  opts.display_mode = savedDisplay
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
