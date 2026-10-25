-- Driver: Head It's yarn never doubles up on one Pokemon. Hard, all three Pokemon, FEVER held
-- (the shortest interval), every ball headed when it can be; each frame every pair of balls
-- falling on one column is checked for reaching the head within HEAD 8 frames of each other
-- (the second could not be headed). Logs the launches, those pairs, misses and frames held back.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/head_gap_probe.lua love .
-- PROBE_DIFF (hard), PROBE_FRAMES game frames to play (3600).

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
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if X and os.getenv("PROBE_FALLBACK") == "1" then X._test.forceRom(false) end
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
  if not X then log("FAIL no exports"); return end
  local opts = game.mods.modOptions.play_nav or {}
  game.mods.modOptions.play_nav = opts
  local savedDisplay = opts.display_mode
  opts.display_mode = "combined"
  local R, Apps, S = X.amie, X.apps, X.amie.session
  local rec = R.games and R.games.record and R.games.record("head")
  local diff = os.getenv("PROBE_DIFF") or "hard"
  local savedUnlocked = rec and rec.unlocked
  local savedHigh = rec and rec.high and rec.high[diff]
  local ok, err = pcall(function()
    if rec then rec.unlocked = 4 end
    log("open play:", R.openPlay()); U.wait(10)
    log("show games:", S.showGames()); U.wait(10)
    log("start head:", diff, S.startGame("head", diff))
    local app = Apps:get("game_head")
    local st = function() return app.debugState() end
    if not waitFor(function() return st() and st().phase == "play" end, 60 * 60) then
      log("FAIL no play phase:", st() and st().phase); return
    end
    -- all three Pokemon (the stages hurried along)
    for stage = 1, 2 do
      st().stageF = 1e6
      waitFor(function() return st().stage == stage end, 60 * 10)
      U.wait(30)
    end
    log("stage", st().stage, "interval", st().interval)
    -- the game's arrival: frames until the test point is in the just window's middle
    local HR = R.headRules or {}
    local W = HR.WINDOW or { just = { 130, 180 } }
    local mid = (W.just[1] + W.just[2]) / 2
    local function due(b)
      local y, v = b.y, b.v
      for n = 0, 900 do
        if 120 - y + (HR.BALL_H or 90) * (HR.TEST_DROP or 0.25) >= mid then return n end
        v = v + b.g
        y = y - v
      end
      return math.huge
    end
    local seen, launches, pairs_, flagged = {}, 0, 0, {}
    local frames = tonumber(os.getenv("PROBE_FRAMES")) or 3600
    local lastFrame, held, lastCounter = st().frame or 0, 0, nil
    local t0 = st().frame or 0
    while (st().frame or 0) - t0 < frames and st().phase == "play" do
      local x = st()
      x.timer = 1800
      x.fever = true
      x.interval = math.min(x.interval, 15)
      -- (a launch held back: the counter past the interval and still counting)
      if x.counter and x.counter > x.interval and x.frame ~= lastFrame then held = held + 1 end
      lastFrame = x.frame
      local fall = {}
      for _, b in ipairs(x.balls) do
        if not seen[b] then seen[b] = true; launches = launches + 1 end
        if b.state == "fall" and not b.missed and not b.gone and not b.giant then fall[#fall + 1] = b end
      end
      for i = 1, #fall do
        for j = i + 1, #fall do
          local a, b = fall[i], fall[j]
          if a.slot == b.slot and math.abs(due(a) - due(b)) < 8 then
            local key = tostring(a) .. tostring(b)
            if not flagged[key] then
              flagged[key] = true
              pairs_ = pairs_ + 1
              log(("  pair on %d: due %d / %d frames (kinds %d / %d)"):format(a.slot, due(a), due(b), a.kind, b.kind))
            end
          end
        end
      end
      local slot = app.nextTap("just") or app.nextTap("good")
      if slot then
        local px, py = app.tapPoint("slot", slot)
        local r = X.state().rect
        local tab = X.state().tabHeight or 0
        local wx, wy = r.x + px * r.scale, r.y + (py + tab) * r.scale
        love.touchpressed("h", wx, wy, 0, 0, 1); U.wait(1); love.touchreleased("h", wx, wy, 0, 0, 1)
      end
      U.wait(1)
    end
    local x = st()
    log(("played %d frames: %d launches, %d pairs due on one head within 8 frames, %d misses, %d hits, %d frames held back")
      :format((x.frame or 0) - t0, launches, pairs_, x.misses or 0, x.hits or 0, held))
    log("RESULT", pairs_ == 0 and "ok" or "FAIL")
    S.finish()
    U.wait(5)
  end)
  if not ok then log("probe body failed:", tostring(err)) end
  opts.display_mode = savedDisplay
  if rec then
    rec.unlocked = savedUnlocked
    if rec.high then rec.high[diff] = savedHigh end
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
