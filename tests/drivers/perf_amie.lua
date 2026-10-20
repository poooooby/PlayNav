-- Driver: where an Amie frame's Lua time and garbage go, screen by screen (the room, PLAY,
-- and each minigame mid-play), as perf_parts does for Super Training. For each: the time per
-- call and the Lua heap it allocates per call with the collector stopped (what the device's
-- GC has to sweep every frame).
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/perf_amie.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
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
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  if s and #(s.party or {}) < 3 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 12)
    Party.giveMon(s, C:require("species", "SPECIES_WURMPLE"), 8)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  game.mods.modOptions.play_nav = game.mods.modOptions.play_nav or {}
  game.mods.modOptions.play_nav.display = "split"
  game.mods.hooks:removeOwner("kanto_gear")
  if game.mods.events then game.mods.events:removeOwner("kanto_gear") end
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local Sf, drawAll = X._test.surface, X._test.drawAll
  local clock = love.timer.getTime

  local function measure(label, f, n)
    n = n or 120
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    local t0 = clock()
    for _ = 1, n do f() end
    local dt = (clock() - t0) * 1000 / n
    local kb = (collectgarbage("count") - kb0) / n
    collectgarbage("restart")
    log(("%-44s %6.3f ms  %7.2f KB garbage per call"):format(label, dt, kb))
  end

  local Stack = require("src.ui.game3.stack")
  local function topScene()
    local top = Stack.top()
    return top and top.mod and top.mod.drawScene and top.mod or nil
  end

  local A = X.amie
  local S = A.session
  log("amie open:", A.open())
  U.wait(30)

  log("---- the room")
  local nothing = function() end
  measure("render wrapper alone (empty draw)", function() Sf:render(nothing, 1) end)
  measure("touch screen render k=1", function() Sf:render(drawAll, 1) end)
  measure("G.frame (room tick + visitors)", function() S.frame(1 / 60) end)

  log("---- PLAY")
  S.finish()
  U.wait(10)
  log("openPlay:", A.openPlay())
  U.wait(60)
  measure("touch screen render k=1", function() Sf:render(drawAll, 1) end)
  measure("G.frame", function() S.frame(1 / 60) end)
  local layer = topScene()
  if layer then measure("top scene (sky) at 240x160", function() Sf:render(function(G) layer.drawScene(G) end, 1) end) end

  for _, id in ipairs({ "berry", "head", "tile" }) do
    log("---- " .. id .. " (play phase)")
    local ok, why = S.startGame(id, "easy")
    log("start:", ok, why)
    if ok then
      local app = X.apps and X.apps:get("game_" .. id)
      local inPlay = function()
        local d = app and app.debugState and app.debugState()
        return d and (d.phase == "play" or d.phase == nil and not (app.busy and app.busy()))
      end
      waitFor(inPlay, 60 * 40)
      U.wait(30)
      local d = app and app.debugState and app.debugState()
      log("phase:", d and d.phase or "?")
      measure("touch screen render k=1", function() Sf:render(drawAll, 1) end)
      measure("G.frame (sim tick)", function() S.frame(1 / 60) end)
      layer = topScene()
      if layer then measure("top scene at 240x160", function() Sf:render(function(G) layer.drawScene(G) end, 1) end) end
      -- (measured 2026-10-19: a layout draw's remaining garbage is ~85 bytes per drawn quad
      -- inside LOVE's own mesh bindings - the same draw against a no-op G makes a tenth of
      -- it - so the lytplayer side is as clean as it gets without batching the quads)
      if id == "berry" and app and app.screen then
        for _, which in ipairs({ "rear", "front", "nuts", "balloon" }) do
          local P = app.screen(which)
          if P then measure("  " .. which .. " layout draw alone", function() Sf:render(function(G) P:draw(G) end, 1) end) end
        end
      end
      if app and app.forceEnd then app.forceEnd(0) end
      U.wait(30)
      S.leaveGame({ toPetting = true })
      U.wait(30)
    end
  end
  S.finish()
end

return function(game)
  local log = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[driver]", table.concat(parts, " "))
  end
  local ok, err = pcall(body, game, log)
  if not ok then log("FAIL", err) end
  love.event.quit()
end
