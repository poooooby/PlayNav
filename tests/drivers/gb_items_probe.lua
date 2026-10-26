-- Driver: Super Training's items on the Game Boy games, end to end. A prize given into the bag
-- (one of ours, the Health Wing, and a stand-in for an item the game lacks: Stardust), then the
-- Wing used on the lead through the game's own item code - Gen 2's ItemEffects.useOnMon (what the
-- PACK's party menu runs), Gen 1's ItemEffects.use (the bag's) - and its Stat Exp read back.
--   SHOT_DIR=<dir> POKEPORT_GAME=crystal POKEPORT_VERSION=crystal POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/gb_items_probe.lua love .
--   (POKEPORT_GAME=red POKEPORT_VERSION=red for Gen 1)

local function body(game, log)
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
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if X and X._test and X._test.forceRom then X._test.forceRom(false) end
  local gen
  if game.world then
    gen = 2
    waitFor(function() return game.world and game.world.map end, 900)
  else
    gen = 1
    if not U.newGame(game) then log("FAIL no overworld"); return end
  end
  U.wait(30)
  X = game.mods.exports.play_nav
  local th = X.training and X.training.host
  if not check(th ~= nil, "Super Training's host") then return end
  local data = game.data
  local mon = gen == 1 and require("src.pokemon.Pokemon").new(data, "PIKACHU", 30)
    or require("src.battle.gen2.Mon").new(data, "CYNDAQUIL", 30)
  game.save.party = { mon }
  U.wait(10)
  local Bag = require("src.inventory.Bag")
  local function count(id)
    local n = 0
    for _, row in ipairs(Bag.rows(game.save, data) or {}) do
      if type(row) == "table" and (row.id == id or row.item == id) then n = n + (row.qty or row.count or row.n or 1) end
    end
    return n
  end

  -- the items as registered
  local wing = th.itemId("HEALTH_WING") or th.itemId("ITEM_HEALTH_WING")
  local rec = wing and data.items[wing]
  log("Health Wing id:", tostring(wing), "name:", tostring(rec and rec.name), "effect:", tostring(rec and rec.effect))
  check(rec ~= nil and type(rec.name) == "string" and rec.name ~= "", "the Health Wing is registered with its name")
  local stand = th.itemId("ITEM_STARDUST")
  log("Stardust on this game:", tostring(stand), tostring(stand and th.itemName(stand)))
  check(stand ~= nil, "a prize the game lacks has a stand-in")

  -- prizes into the bag, as a regimen's reward gives them
  local w0, s0 = count(wing), count(stand)
  check(th.canGiveItem(wing, 1) and count(wing) == w0, "room for the Wing (the test add put back)")
  check(th.giveItem(wing, 3), "three Wings given")
  check(th.giveItem(stand, 1), "the stand-in given")
  log(("bag: Wings %d -> %d, %s %d -> %d"):format(w0, count(wing), tostring(stand), s0, count(stand)))
  check(count(wing) == w0 + 3 and count(stand) == s0 + 1, "both are in the bag")

  -- a Wing used through the game's own item code
  local hp0 = th.evsOf(mon).hp
  local se0 = mon.statExp and (mon.statExp.hp or mon.statExp.HP) or 0
  local used, text
  if gen == 2 then
    local IE = require("src.core.gen2.ItemEffects")
    log("party action:", tostring(IE.partyAction(wing, data, false)), "needs a target:", tostring(IE.needsTarget(wing, data)))
    -- where the record is (or is not): the merged effects table, by the item's id and its effect's
    local merged = data.gen2ItemEffects
    local byEffect = merged and rec and rec.effect and merged[rec.effect]
    log("gen2ItemEffects:", type(merged), "by id:", tostring(merged and merged[wing]),
      "by effect:", tostring(byEffect), byEffect and ("action " .. tostring(byEffect.action) .. ", use " .. type(byEffect.use)) or "")
    if merged then
      local n, ours = 0, {}
      for k in pairs(merged) do n = n + 1; if tostring(k):find("PLAYNAV") then ours[#ours + 1] = tostring(k) end end
      log("records:", n, "PlayNav's:", table.concat(ours, " "))
    end
    check(IE.partyAction(wing, data, false) ~= nil, "the PACK offers it on the party")
    local r = IE.useOnMon(wing, mon, data, { game = game })
    used, text = r and r.used, r and r.text
  else
    local IE = require("src.inventory.ItemEffects")
    log("needs a target:", tostring(IE.needsTarget(wing, rec, data)))
    check(IE.needsTarget(wing, rec, data) == true, "the bag asks for a Pokemon")
    local result, msgs = IE.use(data, game.save, wing, mon)
    used = result == "consumed"
    text = type(msgs) == "table" and table.concat(msgs, " / ") or tostring(msgs)
  end
  local hp1 = th.evsOf(mon).hp
  local se1 = mon.statExp and (mon.statExp.hp or mon.statExp.HP) or 0
  log(("Wing used: %s, \"%s\"; HP EVs %d -> %d, Stat Exp %s -> %s"):format(tostring(used),
    tostring(text):gsub("\n", " "), hp0, hp1, tostring(se0), tostring(se1)))
  check(used == true and hp1 == hp0 + 1, "the Wing raised HP by one EV")
  check(se1 == hp1 * hp1, "written as Stat Exp = EV^2")
  -- on an egg it does nothing
  if gen == 2 then
    local IE = require("src.core.gen2.ItemEffects")
    local egg = require("src.battle.gen2.Mon").new(data, "TOGEPI", 5)
    egg.isEgg = true
    local r = IE.useOnMon(wing, egg, data, { game = game })
    check(r and r.used == false, "not on an egg")
  end
  log(("%d failures"):format(fails))
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
