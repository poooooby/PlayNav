-- Driver: Head It as the game plays it: the middle Pokemon rising with the rule window, the
-- demo's pen, READY / START!, balls headed at the star (the combo words, the rainbow growing,
-- FEVER), a miss, the second and third Pokemon joining (the stages hurried along), time up,
-- the giant ball on the middle Pokemon, RESULTS on the top screen, the smoke and medallions,
-- the buttons, then Quit back to petting. Shots at each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/head_probe.lua love .
-- PROBE_DIFF=easy|normal|hard|unlimited the difficulty (easy).

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
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
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_SWAMPERT"), 40)
    Party.giveMon(s, C:require("species", "SPECIES_KYOGRE"), 45)
    Party.giveMon(s, C:require("species", "SPECIES_LATIAS"), 40)
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if X and X.haptics then X.haptics.log = {} end
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display
  opts.display = "split"
  local R, Apps, S = X.amie, X.apps, X.amie.session
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function press(id, ax, ay) local x, y = win(ax, ay); love.touchpressed(id, x, y, 0, 0, 1) end
  local function release(id, ax, ay) local x, y = win(ax, ay); love.touchreleased(id, x, y, 0, 0, 1) end
  local function tapAt(id, ax, ay)
    if not ax then log("no point for", id); return end
    press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(3)
  end

  local ok, err = pcall(function()
    local diff = os.getenv("PROBE_DIFF") or "easy"
    local rec = R.games and R.games.record and R.games.record("head")
    local savedUnlocked = rec and rec.unlocked
    local savedHigh = rec and rec.high and rec.high[os.getenv("PROBE_DIFF") or "easy"]
    if rec then rec.unlocked = 4 end
    log("open play:", R.openPlay())
    U.wait(10)
    log("show games:", S.showGames())
    U.wait(10)
    log("start head:", diff, S.startGame("head", diff))
    local app = Apps:get("game_head")
    local st = function() return app.debugState() end
    log("art:", tostring(st() and st().art))
    waitFor(function() local x = st(); return x.phase == "intro" and x.pt > 1.2 end, 60 * 30)
    shot("h01_intro")
    waitFor(function() local x = st(); return x.phase == "demo" and x.pt > 1.25 end, 60 * 30)
    shot("h02_demo_fall")
    waitFor(function() local x = st(); return x.phase == "demo" and x.penTap and x.pt - x.penTap > 0.12 end, 60 * 30)
    shot("h03_demo_hit")
    waitFor(function() local x = st(); return x.phase == "ready" and x.pt > 0.6 end, 60 * 30)
    shot("h04_ready")
    waitFor(function() local x = st(); return x.phase == "ready" and x.pt > 1.9 end, 60 * 30)
    shot("h05_start")
    waitFor(function() return st().phase == "play" end, 60 * 30)
    -- a ball on its way (the top screen), then head every ball at the star
    waitFor(function() local x = st(); return #x.balls > 0 and x.balls[1].y < 380 end, 60 * 10)
    shot("h06_ball_top")
    local tapped, missedOne, shots = 0, false, {}
    local function playFor(frames, opts2)
      opts2 = opts2 or {}
      for _ = 1, frames do
        local slot = app.nextTap(opts2.good and "good" or "just")
        if slot and not (opts2.skip and opts2.skip()) then
          tapAt("head" .. slot, app.tapPoint("slot", slot))
          tapped = tapped + 1
        else
          U.wait(1)
        end
        if opts2.until_ and opts2.until_() then return true end
      end
      return false
    end
    playFor(60 * 60, { until_ = function() return st().combo >= 3 and st().comboShow ~= nil end })
    U.wait(3)
    shot("h07_combo3")
    log("combo:", st().combo, "score:", st().score, "interval:", st().interval)
    playFor(60 * 60, { until_ = function() return st().fever end })
    U.wait(8)
    shot("h08_fever")
    log("fever at combo", st().combo, "interval", st().interval)
    -- let one fall: MISS!, the combo and rainbow gone
    waitFor(function() return st().misses > 0 end, 60 * 20)
    waitFor(function() local x = st(); return x.misses > 0 end, 60)
    U.wait(6)
    shot("h09_miss")
    log("after miss: combo", st().combo, "fever", tostring(st().fever), "interval", st().interval)
    if diff ~= "unlimited" then
      -- the second Pokemon joins (hurried: the stage's frames run out)
      st().stageF = 598
      waitFor(function() return st().stage == 1 end, 60 * 5)
      U.wait(10)
      shot("h10_second_joins")
      playFor(60 * 60, { until_ = function()
        for _, b in ipairs(st().balls) do if b.slot == 2 and b.y < 200 then return true end end
        return false
      end })
      shot("h11_left_ball")
      st().stageF = 598
      waitFor(function() return st().stage == 2 end, 60 * 5)
      playFor(60 * 4)
      shot("h12_three")
      -- the clock runs out; the balls still up are played out
      st().timer = 60
      playFor(60 * 30, { until_ = function() return st().phase ~= "play" end })
      shot("h13_timeup")
      waitFor(function() return st().phase == "leave" end, 60 * 30)
      U.wait(8)
      shot("h14_leave")
      waitFor(function() local x = st(); return x.phase == "giant" and x.giant and x.giant.y < 200 end, 60 * 30)
      shot("h15_giant")
      waitFor(function() return app.nextTap("just") == 1 or st().phase ~= "giant" or (st().giant and st().giant.missed) end, 60 * 30)
      -- the giant uses its own test point: tap when it is at the star
      for _ = 1, 600 do
        local gb = st().giant
        if not gb or gb.state ~= "fall" or gb.missed then break end
        local ty = 120 - gb.y + 350 * 0.4
        if ty >= 130 and ty < 180 then tapAt("giant", app.tapPoint("slot", 1)); break end
        U.wait(1)
      end
      U.wait(4)
      shot("h16_giant_hit")
      log("big yarn bonus:", st().bigBonus)
    else
      -- Unlimited: miss until the chances run out
      waitFor(function() return st().phase == "results" end, 60 * 120)
    end
    waitFor(function() local x = st(); return x.phase == "results" and x.pt > 0.9 end, 60 * 30)
    shot("h17_results_rows")
    waitFor(function() local x = st(); return x.phase == "results" and x.pt > 3.0 end, 60 * 30)
    shot("h18_results_card")
    waitFor(function() local x = st(); return x.phase == "smoke" and x.pt > 0.15 end, 60 * 30)
    shot("h19_smoke")
    waitFor(function() local x = st(); return x.phase == "smoke" and x.pt > 1.4 end, 60 * 30)
    shot("h20_medals")
    do
      local Rw = app.screen and app.screen("reward")
      local n = 0
      for _, e in ipairs(Rw and Rw.active or {}) do if e.name == "sweets" then n = n + 1 end end
      log("medallions dancing (sweets on each):", n)
    end
    waitFor(function() return st().phase == "buttons" end, 60 * 60)
    U.wait(20)
    shot("h21_buttons")
    local res = R.state() and R.state().lastResult
    log("taps:", tapped, "score:", st().score, "max combo:", st().maxCombo, "final:", st().final)
    log("result:", res and res.value, res and res.stars, res and res.title, res and #(res.puffs or {}), "new high", res and tostring(res.newHigh))
    tapAt("quit", app.tapPoint("quit"))
    U.wait(20)
    log("after Quit: mode", R.state() and R.state().mode, "app", Apps:active().id)
    shot("h22_petting")
    S.finish()
    U.wait(5)
    if rec then
      rec.unlocked = savedUnlocked
      if rec.high then rec.high[diff] = savedHigh end
    end
  end)
  if not ok then log("probe body failed:", tostring(err)) end
  opts.display = savedDisplay
  if X and X.haptics and X.haptics.log then
    local n = {}
    for _, k in ipairs(X.haptics.log) do n[k] = (n[k] or 0) + 1 end
    log(("haptics felt: tick %d light %d medium %d strong %d (%d pulses)"):format(n.tick or 0, n.light or 0,
      n.medium or 0, n.strong or 0, #X.haptics.log))
  end
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
