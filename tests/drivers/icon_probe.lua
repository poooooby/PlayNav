-- Driver: what each sprite source hands NaviPlay for a few species (a form from the National
-- Dex mods, a newer species, a Gen 3 one): the party icon entry (frame size, sheet size,
-- pixel density) and the front pic, and the opaque box PLAY / Head It measure on each.
-- Env PROBE_SLOTS = comma-separated engine species slots (default Zygarde Complete 1144,
-- Victini, Bulbasaur).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/icon_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
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
  local s = Runtime.getSession()
  local slots = {}
  for v in (os.getenv("PROBE_SLOTS") or ""):gmatch("%d+") do slots[#slots + 1] = tonumber(v) end
  if #slots == 0 then
    slots = { 1144, 558, C:require("species", "SPECIES_BULBASAUR") }
  end
  if s then
    while #(s.party or {}) > 0 do table.remove(s.party) end
    for _, sp in ipairs(slots) do if sp and sp > 0 then Party.giveMon(s, sp, 50) end end
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  local host = X and X._test and X._test.refreshHost and X._test.refreshHost()
  if not host then log("FAIL no host"); return end
  local function dims(img)
    if not img then return "nil" end
    local w, h = img:getDimensions()
    local pw, ph = w, h
    if img.getPixelDimensions then pw, ph = img:getPixelDimensions() end
    return ("%dx%d (px %dx%d)"):format(w, h, pw, ph)
  end
  log("dpi scale:", love.graphics.getDPIScale and love.graphics.getDPIScale())
  log("sharp shader compiled:", X.hd and X.hd.sharpShader and X.hd.sharpShader() ~= nil)
  -- the readback PLAY / Head It measure a sprite with, at the density a high-DPI device's
  -- canvases default to (2) and pinned to 1: the boxes must agree once pinned
  local function boxAt(img, dpi)
    local w, h = img:getDimensions()
    local c = love.graphics.newCanvas(w, h, { dpiscale = dpi })
    love.graphics.push("all")
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
    love.graphics.pop()
    local d = c:newImageData()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = d:getPixel(x, y)
        if a > 0.1 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    return ("%d,%d-%d,%d"):format(x0, y0, x1 + 1, y1 + 1)
  end
  for _, mon in ipairs(s.party) do
    local pic = host.frontPic and host.frontPic(mon)
    if pic and pic.image then
      log(("%s box: scan at density 2 (the old Thor read) %s; pinned to 1 %s"):format(
        host.displayName(mon), boxAt(pic.image, 2), boxAt(pic.image, 1)))
    end
  end
  for _, mon in ipairs(s.party) do
    local name = host.displayName and host.displayName(mon) or "?"
    local ic = host.icon and host.icon(mon)
    local q = ic and ic.quads and (ic.quads[0] or ic.quads[1])
    local qv = q and table.concat({ q:getViewport() }, ",") or "-"
    log(("%s: icon w %s h %s frames %s; image %s; quad0 %s"):format(name, tostring(ic and ic.w),
      tostring(ic and ic.h), tostring(ic and ic.frames), dims(ic and ic.image), qv))
    local pic = host.frontPic and host.frontPic(mon)
    log(("%s: front w %s h %s; image %s"):format(name, tostring(pic and pic.w), tostring(pic and pic.h),
      dims(pic and pic.image)))
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
