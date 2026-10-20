-- Driver: the Amie room's visitors. Three seated and chatting (the talk bubbles over whoever
-- speaks, a shot per bubble with who spoke and where it was drawn), and the room's Pokemon
-- wandering with cushions on the guest seats and elsewhere (it never sits on a guest seat).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/visitors_probe.lua love .

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
    log("FAIL boot phase not reached")
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s0 = Runtime.getSession()
  if #(s0.party or {}) == 0 then Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(30)
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local A = X.amie
  log("open:", tostring(A.open()))
  waitSecs(1.5)
  local G = A.session
  local V = G.Visitors
  local home = X.apps:get("home")

  -- three visitors seated; the chat starts on the next update
  V.force()
  for _, v in ipairs(V.present) do v.state, v.x = "stay", v.tx end
  V.group = nil
  local seen = {}
  for _ = 1, 3000 do
    U.wait(1)
    local b = V.group and V.group.bubble
    if b and not seen[b.who] and home.talkAt then
      local v = V.present[b.who]
      local bx, by = home.talkAt(v)
      seen[b.who] = true
      waitSecs(0.25)
      log(("bubble %s over visitor %d at seat (%d, %d): drawn at (%.0f, %.0f)"):format(b.word, b.who, v.x, v.y, bx, by))
      shot("v_bubble_" .. b.who)
    end
    if seen[1] and seen[2] and seen[3] then break end
  end

  -- the Pokemon's favourite spots: a cushion on each guest seat and one in the open
  V.sendOff()
  for _ = 1, 600 do if #V.present == 0 then break end; U.wait(1) end
  local Decor, Store = G.Decor, X.amie.store
  local room = Store and Store.room and Store.room()
  if Decor and room then
    room.items = {}
    local cushion = "cushion/leaf_cushion"
    for _, sp in ipairs(Decor.SEATS) do room.items[#room.items + 1] = { id = cushion, x = sp.x, y = sp.y } end
    room.items[#room.items + 1] = { id = cushion, x = 60, y = 180 }
    local onSeat, elsewhere = 0, 0
    for _ = 1, 40 do
      local c = Decor.nearestCushion(room, math.random(20, 300), math.random(90, 200))
      if c and Decor.seatOf(c) then onSeat = onSeat + 1 elseif c then elsewhere = elsewhere + 1 end
    end
    log(("favourite cushions picked: on a guest seat %d, elsewhere %d"):format(onSeat, elsewhere))
  end
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
