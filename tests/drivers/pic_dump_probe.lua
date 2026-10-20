-- Driver: what the sprite mods hand out for a species' front and back pics (the entry's
-- fields, the image's size, a quad's viewport, gen3-hd-sprites' tag), raw and through
-- PlayNav's host (mod.stillPic); each saved as a PNG.
--   PROBE_SPECIES=ZYGARDE_COMPLETE SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_TOUCH=1 POKEPORT_DRIVER=mods/play_nav/tests/drivers/pic_dump_probe.lua love .

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
  local Pokemon = require("src.core.game3.pokemon")
  local s0 = Runtime.getSession()
  local name = os.getenv("PROBE_SPECIES") or "ZYGARDE_COMPLETE"
  -- a dex mod's form has no Emerald constant: its slot number (ZYGARDE_COMPLETE 1144)
  local species = tonumber(name)
  if not species then
    local ok, id = pcall(C.require, C, "species", "SPECIES_" .. name)
    species = ok and id or nil
  end
  if not species then log("FAIL no species", name); return end
  Party.giveMon(s0, species, 30)
  U.wait(30)
  local mon = s0.party[#s0.party]
  local ex = game.mods.exports
  local hd = ex.gen3_hd_sprites or ex["gen3-hd-sprites"]
  local function save(img, file)
    pcall(function()
      local w, h = img:getDimensions()
      local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.origin()
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.pop()
      local d = c:newImageData()
      local fd = d:encode("png")
      local f = io.open(dir .. "/" .. file, "wb")
      f:write(fd:getString())
      f:close()
    end)
  end
  local function dump(label, e)
    if type(e) ~= "table" then log(label, "->", tostring(e)); return end
    local keys = {}
    for k, v in pairs(e) do keys[#keys + 1] = tostring(k) .. "=" .. (type(v) == "userdata" and (v.type and v:type() or "ud") or tostring(v)) end
    table.sort(keys)
    log(label, table.concat(keys, " "))
    if e.image and e.image.getDimensions then
      local w, h = e.image:getDimensions()
      log("  image", w, "x", h, "dpi", e.image.getDPIScale and e.image:getDPIScale() or "?")
      save(e.image, label:gsub("[^%w]", "_") .. ".png")
    end
    if e.quad then log("  quad", e.quad:getViewport()) end
    if hd and hd.tagOf and e.image then
      local tag = hd.tagOf(e.image)
      if tag then dump(label .. " tag", tag) end
    end
  end
  log("mods with tagOf:", tostring(hd ~= nil))
  dump("raw back", Pokemon.monBackPic(mon))
  dump("raw front summary", Pokemon.monFrontPic(mon, nil, "summary"))
  local H = X.training and X.training.host
  log("host:", tostring(H ~= nil))
  if H and H.backPic then dump("host back", H.backPic(mon)) end
  -- Play with that Pokemon, its back turned
  if X.amie and X.amie.openPlay then
    log("play:", tostring(X.amie.openPlay(mon)))
    local t = love.timer.getTime()
    while love.timer.getTime() - t < 1.5 do U.wait(1) end
    log("shot", U.shot(game, dir .. "/play_back.png") and "ok" or "MISSING")
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
