-- Driver: what Super Training's home screen costs per frame while the bag is punched back to
-- back. Times the touch screen's draw at each density, the second display's readback (the
-- canvas into an ImageData, as main.lua pushes it at up to 30 a second) and the garbage each
-- push leaves, then frame times over a punch chain.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/perf_probe.lua love .
-- PLAYNAV_DISPLAY=second_screen times the second display instead (the desktop companion
-- window; the micro-timings are skipped), and
-- PERF_NO_KG=1 removes Kanto Gear's hooks for the run (its install and options untouched).

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
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 30)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  game.mods.modOptions.play_nav = game.mods.modOptions.play_nav or {}
  local SECOND = os.getenv("PLAYNAV_DISPLAY") == "second_screen"
  game.mods.modOptions.play_nav.display = SECOND and "second_screen" or "split"
  if os.getenv("PERF_NO_KG") == "1" then
    game.mods.hooks:removeOwner("kanto_gear")
    if game.mods.events then game.mods.events:removeOwner("kanto_gear") end
    log("kanto_gear hooks removed for this run")
  end
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  do
    local ids = {}
    for _, m in ipairs(game.mods.loaded or {}) do
      ids[#ids + 1] = m.manifest.id .. " " .. tostring(m.manifest.version)
    end
    log("mods loaded:", table.concat(ids, ", "))
  end
  local TR = X.training
  log("open:", TR.open())
  TR.session.session.rec.bag = { id = "atk_l", hits = 0, needed = 100000 }
  U.wait(30)
  local Sf, drawAll = X._test.surface, X._test.drawAll
  local clock = love.timer.getTime
  local function punch() TR.session.hitBag("tap") end
  -- frame times over a 4 s punch chain (a tap every 0.45 s), in the chosen display mode
  local function chain(label)
    local times = {}
    local last, nextPunch, t0 = clock(), 0, clock()
    local sim0 = TR.session.session.anim.t
    while clock() - t0 < 4 do
      if clock() >= nextPunch then punch(); nextPunch = clock() + 0.45 end
      U.wait(1)
      local t = clock()
      times[#times + 1] = (t - last) * 1000
      last = t
    end
    local gameS = TR.session.session.anim.t - sim0
    table.sort(times)
    local function pct(p) return times[math.max(1, math.floor(#times * p))] end
    log(("frames over a punch chain (%s, surface %s, k %s): %d in 4 s, median %.2f ms, p95 %.2f, max %.2f; game clock ran %.2f s"):format(
      label, tostring(X.state().mode), tostring(X.state().pushK), #times, pct(0.5), pct(0.95), times[#times], gameS))
  end
  -- a regimen: the top layer, the HUD and the aim screen, timed against the sim's clock
  local function regimen(label)
    TR.session.REGIMEN_SHOW = true
    log("start course:", TR.session.startCourse("lv1_hp"))
    waitFor(function() return TR.session.sim ~= nil end, 3000)
    local sim = TR.session.sim
    local times, last, t0, sim0 = {}, clock(), clock(), sim and sim.t or 0
    while clock() - t0 < 6 do
      U.wait(1)
      local t = clock()
      times[#times + 1] = (t - last) * 1000
      last = t
    end
    table.sort(times)
    local function pct(p) return times[math.max(1, math.floor(#times * p))] end
    log(("frames in a regimen (%s, surface %s, k %s): %d in 6 s, median %.2f ms, p95 %.2f, max %.2f; sim clock ran %.2f s"):format(
      label, tostring(X.state().mode), tostring(X.state().pushK), #times, pct(0.5), pct(0.95), times[#times],
      (sim and sim.t or 0) - sim0))
  end
  if SECOND then
    U.wait(120)   -- the companion window connects
    chain("second screen")
    regimen("second screen")
    return
  end
  local function ms(f, n)
    local t0 = clock()
    for _ = 1, n do f() end
    return (clock() - t0) * 1000 / n
  end
  -- punch now and then so the animation is live while timing
  for _, k in ipairs({ 1, 2, 3, 4 }) do
    log(("draw at k=%d: %.2f ms"):format(k, ms(function() punch(); Sf:render(drawAll, k) end, 60)))
  end
  for _, k in ipairs({ 2, 3 }) do
    collectgarbage("collect")
    local kb0 = collectgarbage("count")
    local n = 30
    local per = ms(function() punch(); local d = Sf:imageData(k, drawAll) end, n)
    local kb1 = collectgarbage("count")
    log(("second-display push at k=%d (draw + readback): %.2f ms, Lua heap +%.0f KB over %d pushes"):format(k, per, kb1 - kb0, n))
    local per2 = ms(function() punch(); local d = Sf:imageData(k, drawAll); if d then d:release() end end, n)
    log(("  ...released at once: %.2f ms"):format(per2))
  end
  chain("split")
  regimen("split")
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
