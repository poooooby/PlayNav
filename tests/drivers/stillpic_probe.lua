-- Driver: Pokemon pics from whatever sprite mod is on (g9-battle-sprites-gen3 animates by the
-- clock). The engine's pic asked at several moments (different frames when a mod animates),
-- then NaviPlay's host (mod.stillPic): one first frame every time. Saves each as a PNG.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/stillpic_probe.lua love .

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
  local Pokemon = require("src.core.game3.pokemon")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then
    local slot = tonumber(os.getenv("PROBE_SLOT"))
    if slot then Party.giveMon(s, slot, 20) end
    Party.giveMon(s, C:require("species", "SPECIES_SWAMPERT"), 40)
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local host = X._test and X._test.refreshHost and X._test.refreshHost()
  if not host then log("FAIL no host"); return end
  local function save(img, name)
    local ok = pcall(function()
      local lw = img:getDimensions()
      local w, h = img:getPixelDimensions()
      local k = w / lw
      local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.origin()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0, 0, k, k)
      love.graphics.setCanvas()
      love.graphics.pop()
      local data = c:newImageData()
      local fd = data:encode("png")
      local f = io.open(dir .. "/" .. name .. ".png", "wb")
      if f then f:write(fd:getString()); f:close() end
    end)
    return ok
  end
  if os.getenv("PROBE_ALLFRAMES") and s.party[1] then
    -- every frame of the first Pokemon's sheet, in order (the clock stepped at the mod's 8 fps)
    local real, seen, n = love.timer.getTime, {}, 0
    for f = 0, 63 do
      love.timer.getTime = function() return f / 8 + 0.01 end
      local ok, e = pcall(Pokemon.monFrontPic, s.party[1], nil, "summary")
      love.timer.getTime = real
      local img = ok and e and e.image
      if img and seen[img] then break end
      if img then seen[img] = true; n = n + 1; save(img, ("all_%02d"):format(f)) end
    end
    log("frames in the sheet:", n)
  end
  for _, mon in ipairs(s.party) do
    local name = host.displayName and host.displayName(mon) or "?"
    local raw, ours = {}, {}
    for i = 1, 4 do
      local e = Pokemon.monFrontPic(mon, nil, "summary")
      raw[i] = e and e.image
      local p = host.frontPic(mon)
      ours[i] = p and p.image
      if raw[i] then save(raw[i], name .. "_engine_" .. i) end
      if i == 1 and ours[1] then save(ours[1], name .. "_still") end
      waitSecs(0.23)
    end
    local rawDiff, oursDiff = 0, 0
    for i = 2, 4 do
      if raw[i] ~= raw[1] then rawDiff = rawDiff + 1 end
      if ours[i] ~= ours[1] then oursDiff = oursDiff + 1 end
    end
    local b1 = host.backPic(mon)
    waitSecs(0.31)
    local b2 = host.backPic(mon)
    log(("%s: engine frames differing %d/3 (animated: %s); ours differing %d/3; back same %s; size %s"):format(
      name, rawDiff, tostring(rawDiff > 0), oursDiff, tostring(b1 and b2 and b1.image == b2.image),
      ours[1] and table.concat({ ours[1]:getDimensions() }, "x") or "nil"))
  end
  log("getTime runs:", love.timer.getTime() > 0)
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
