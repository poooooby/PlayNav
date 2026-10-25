-- Driver: the front picture PLAY draws for every species (the installed sprite mods' still pose,
-- as host.frontPic hands it out), saved as <SHOT_DIR>/pics/<dex>.png for tools/amie_mouths.py.
-- Species by g9-battle-sprites-gen3's data/atlas_index.lua (dex -> the engine's slot);
-- PROBE_FROM / PROBE_TO limit the dex range.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/front_dump_probe.lua love .

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
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
  if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local s0 = Runtime.getSession()
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local R = X.amie
  -- dex -> slot, the base form (the shortest name for a dex)
  local f = io.open("mods/g9-battle-sprites-gen3/data/atlas_index.lua", "r")
  if not f then log("FAIL no atlas_index"); return end
  local src = f:read("*a"); f:close()
  local slots, names = {}, {}
  for name, dex, slot in src:gmatch('%["([A-Z0-9_]+)"%] = { dex = (%d+), slot = (%d+)') do
    dex, slot = tonumber(dex), tonumber(slot)
    if not names[dex] or #name < #names[dex] then names[dex], slots[dex] = name, slot end
  end
  love.filesystem.createDirectory("front_dump")
  local from, to = tonumber(os.getenv("PROBE_FROM")) or 1, tonumber(os.getenv("PROBE_TO")) or 1025
  local saved, failed = 0, {}
  for dex = from, to do
    local slot = slots[dex]
    local ok = slot and pcall(function()
      s0.party = {}
      Party.giveMon(s0, slot, 30)
    end)
    local pic = nil
    if ok and #(s0.party or {}) > 0 then
      local okO = pcall(R.openPlay)
      U.wait(2)
      local sess = R.session and R.session.session
      pic = okO and sess and sess.pic and sess.pic.image or nil
    end
    if pic then
      local okW = pcall(function()
        local w, h = pic:getDimensions()
        local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
        love.graphics.push("all")
        love.graphics.setCanvas(c)
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(pic, 0, 0)
        love.graphics.setCanvas()
        love.graphics.pop()
        local data = c:newImageData():encode("png")
        local out = io.open(dir .. "/pics/" .. dex .. ".png", "wb")
        out:write(data:getString()); out:close()
        c:release()
      end)
      if okW then saved = saved + 1 else failed[#failed + 1] = dex end
    else
      failed[#failed + 1] = dex
    end
    pcall(R.session.finish)
    U.wait(1)
  end
  log("saved", saved, "failed", #failed, table.concat(failed, ",", 1, math.min(#failed, 40)))
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
