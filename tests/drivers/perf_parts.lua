-- Driver: where a PlayNav frame's Lua time and garbage go, part by part, on the home screen
-- and in a regimen (split mode on the desktop; the ratios carry to a low-power device, the
-- absolute times do not). For each part: the time per call and the Lua heap it allocates per
-- call with the collector stopped (what the device's GC has to sweep every frame).
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/perf_parts.lua love .

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
  -- CLEAR EXTRACTED ART may be on in the player's options: a driver run never acts on it
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
  game.mods.modOptions.play_nav.display_mode = "combined"
  game.mods.hooks:removeOwner("kanto_gear")
  if game.mods.events then game.mods.events:removeOwner("kanto_gear") end
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local TR = X.training
  log("open:", TR.open())
  TR.session.session.rec.bag = { id = "atk_l", hits = 0, needed = 100000 }
  U.wait(30)
  local Sf, drawAll = X._test.surface, X._test.drawAll
  local clock = love.timer.getTime
  local function punch() TR.session.hitBag("tap") end

  -- time and garbage per call, the collector held meanwhile
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

  log("---- home screen (punch chain live)")
  punch()
  measure("touch screen render k=1", function() Sf:render(drawAll, 1) end)
  measure("touch screen render k=4", function() Sf:render(drawAll, 4) end)
  measure("T.frame (session tick + music)", function() TR.session.frame(1 / 60) end)
  measure("T.party()", function() TR.session.party() end)
  measure("T.state()", function() TR.session.state() end)

  -- the regimen in 2D, then in 3D SUPER TRAINING (set for the run only, never saved)
  local Draw = TR.session.arenaDraw
  -- every course open (Tentacruel's is Lv2: balls, bitbots and goals together)
  for _, c in ipairs(TR.session.courseList()) do TR.store.cleared()[c.id] = true end
  for _, three in ipairs({ false, true }) do
    if Draw then Draw.mode3d = three end
    log(three and "---- regimen, 3D" or "---- regimen, 2D")
    if three and Draw and Draw.arena3d then log("3D available:", Draw.arena3d.available()) end
    TR.session.REGIMEN_SHOW = true
    log("start course:", TR.session.startCourse("lv2_spd"))
    waitFor(function() return TR.session.sim ~= nil end, 3000)
    -- past the intro so the HUD, goals, balls and bitbots are all up
    waitFor(function() local sim = TR.session.sim; return sim and sim.phase == "play" end, 3000)
    -- until attacks and bitbots are up (or a while)
    waitFor(function() local sim = TR.session.sim; return sim and #sim.balls > 0 and #(sim.bits or {}) > 0 end, 60 * 60)
    local sim = TR.session.sim
    log(("game space %s, balls %d, bits %d, goals %d"):format(tostring(sim and sim.game3d), sim and #sim.balls or 0,
      sim and #(sim.bits or {}) or 0, sim and #sim.goals or 0))
    measure("aim screen render k=1", function() Sf:render(drawAll, 1) end)
    local layer = topScene()
    if layer then
      measure("top scene (arena + HUD) at 240x160", function() Sf:render(function(G) layer.drawScene(G) end, 1) end)
      measure("top scene at 4x (window resolution)", function() Sf:render(function(G) G.scale(0.25, 0.25); layer.drawScene(G) end, 4) end)
    else
      log("no top layer of ours on the stack")
    end
    if Draw and sim then
      measure("arena alone (D.draw)", function() Sf:render(function(G) Draw.draw(G, sim, TR.session.session, TR.session) end, 1) end)
    end
    if three and Draw and Draw.arena3d then
      local A3 = Draw.arena3d
      measure("stadium alone (A3.drawStadium)", function() Sf:render(function(G) A3.drawStadium(G, 0, 0, 240, 160) end, 1) end)
    end
    measure("T.frame (sim + hud + music)", function() TR.session.frame(1 / 60) end)
    if sim then measure("sim:update(1/60) alone", function() sim:update(1 / 60) end) end
    if three and Draw and Draw.arena3d and sim then
      local A3 = Draw.arena3d
      measure("A3.update (camera)", function() A3.update(sim) end)
      measure("A3.project x100", function() for i = 1, 100 do A3.project(i, 20, -i) end end)
    end
    if TR.session.hud and TR.session.hud.P then
      local P = TR.session.hud.P
      measure("HUD layout draw alone", function() Sf:render(function(G) P:draw(G) end, 1) end)
    end
    TR.session.forceEnd("timeout")
    waitFor(function() return TR.session.sim == nil or TR.session.state().mode ~= "regimen" end, 3000)
    U.wait(60)
    if TR.session.state().mode == "result" then TR.session.leaveResult(); U.wait(60) end
  end
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
