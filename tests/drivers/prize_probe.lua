-- Driver: a regimen prize that is one of the engine's own items (Soda Pop, Stardust, Hard Stone)
-- and one of NaviPlay's (a Wing), given through T.giveItemSpec as a cleared secret course does:
-- the id it resolves to, its name, whether it reached the bag, and the icon the results screen
-- would draw for it.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/prize_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(30)
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  TR.open()
  U.wait(20)
  local T = TR.session
  local Bag = require("src.core.game3.bag")
  local function count(id)
    local ok, n = pcall(function()
      if Bag.count then return Bag.count(s.bag, id) end
      if Bag.quantity then return Bag.quantity(s.bag, id) end
      return nil
    end)
    return ok and n or "?"
  end
  for _, spec in ipairs({ { item = "ITEM_SODA_POP" }, { item = "ITEM_STARDUST" }, { item = "ITEM_HARD_STONE" },
      { training = "pretty-wing" } }) do
    local id = spec.item and T.host and T.host.itemId and T.host.itemId(spec.item) or nil
    local before = id and count(id) or "-"
    local res = T.giveItemSpec(spec)
    local after = res.index and count(res.index) or "-"
    local icon = res.index and T.itemIcon and T.itemIcon(res.index)
    log(("%-16s -> index %s name %q given %s bag %s -> %s icon %s"):format(spec.item or spec.training,
      tostring(res.index), tostring(res.name), tostring(res.given), tostring(before), tostring(after),
      icon and "yes" or "none"))
  end
  -- the icons, side by side at 4x, saved for a look
  do
    local G = love.graphics
    local c = G.newCanvas(4 * 24 * 4 + 12, 4 * 24, { dpiscale = 1 })
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.clear(0.15, 0.2, 0.3, 1)
    for i, idx in ipairs({ 27, 108, 204, 406 }) do
      local icon = T.itemIcon and T.itemIcon(idx)
      if icon then
        G.setColor(1, 1, 1, 1)
        local w = icon:getWidth()
        G.draw(icon, (i - 1) * (96 + 4), 0, 0, 96 / w, 96 / w)
      end
    end
    G.pop()
    local data = c:newImageData()
    local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
    local fd = data:encode("png")
    local f = io.open(dir .. "/icons.png", "wb")
    if f then f:write(fd:getString()); f:close() end
    log("icons saved")
  end
  local meta = TR.store and TR.store.meta and TR.store.meta()
  log("pending items:", meta and #(meta.pendingItems or {}) or "?")
  pcall(TR.finish)
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
