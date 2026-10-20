-- Driver: Pokemon-Amie's PLAY screen as the game plays it: asleep with its back turned, the tap that wakes it
-- ("!", the flash, facing you with notes, the buttons in), stroking (the hand, the view easing
-- in), taps on each zone (reactions), the puff strip, a puff dragged onto it (the flash, the
-- close-up, a bite, back out), the games picker (badge 1 -> 2 -> 3 with the arrows, back to 1,
-- the difficulty ribbons, Easy starts Berry Picker), and the top screen's sky. Shots each step.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/amie_play_probe.lua love .

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
  local s0 = Runtime.getSession()
  if s0 then s0.x, s0.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s0 and #(s0.party or {}) == 0 then
    Party.giveMon(s0, C:require("species", os.getenv("PROBE_SPECIES") and ("SPECIES_" .. os.getenv("PROBE_SPECIES")) or "SPECIES_TORCHIC"), 12)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 6)
    Party.giveMon(s0, C:require("species", "SPECIES_WURMPLE"), 5)
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
  log("touch screen:", tostring(X.W) .. "x" .. tostring(X.H))
  local R, Apps = X.amie, X.apps
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function press(id, ax, ay) local x, y = win(ax, ay); love.touchpressed(id, x, y, 0, 0, 1) end
  local function move(id, ax, ay) local x, y = win(ax, ay); love.touchmoved(id, x, y, 0, 0, 1) end
  local function release(id, ax, ay) local x, y = win(ax, ay); love.touchreleased(id, x, y, 0, 0, 1) end
  local function tapAt(id, ax, ay)
    if not ax then log("no point for", id); return end
    press(id, ax, ay); U.wait(2); release(id, ax, ay); U.wait(3)
  end

  local ok, err = pcall(function()
    log("open play:", R.openPlay())
    U.wait(10)
    local app = Apps:get("play")
    local st = function() return app.state() end
    local settle = function(limit) waitFor(function() return not app.busy() end, limit or 1200); U.wait(4) end
    local function waitSecs(sec) local t = love.timer.getTime(); while love.timer.getTime() - t < sec do U.wait(1) end end
    log("wake:", st().wake)
    shot("p01_asleep")
    -- the wake
    tapAt("wake", app.tapPoint("pet"))
    waitFor(function() return st().wake == "exclaim" end, 200)
    U.wait(6)
    shot("p02_exclaim")
    waitFor(function() return st().wake == "flash" end, 1200)
    U.wait(2)
    shot("p03_flash")
    waitFor(function() return st().wake == "awake" end, 1200)
    U.wait(20)
    shot("p04_awake")
    log("awake:", st().wake)
    -- its liveliness by mood: happy (hops), hungry (droops), and still while petted
    local m = R.state().meters
    local saved = { m.affection, m.enjoyment, m.fullness }
    m.affection, m.enjoyment, m.fullness = 255, 255, 200
    local hops = 0
    for k = 1, 4 do
      local seen = waitFor(function() return st().hopping end, 900)
      if seen then hops = hops + 1 end
      U.wait(3)
      shot(("p04b_happy_%d"):format(k))
      waitFor(function() return not st().hopping end, 300)
    end
    log("happy: hops seen", hops)
    m.affection, m.enjoyment, m.fullness = 0, 0, 0
    U.wait(30)
    local lowHops = 0
    for _ = 1, 600 do if st().hopping then lowHops = lowHops + 1 end; U.wait(1) end
    shot("p04c_hungry")
    log("hungry: frames hopping", lowHops)
    m.affection, m.enjoyment, m.fullness = saved[1], saved[2], saved[3]
    -- stroking: the hand, the view easing in; on until the game's reward (60 moving ticks on
    -- one spot class: about 2 s), then petting locks while it bounces with music notes
    local px, py = app.tapPoint("zone", "chest")
    local aff0 = R.state().meters.affection
    R.state().meters.enjoyment = 120
    press("pet", px, py); U.wait(2)
    local t0, k, rewarded = love.timer.getTime(), 0, false
    local shotNotes = false
    while love.timer.getTime() - t0 < 5 do
      k = k + 1
      move("pet", px + math.sin(k / 3) * 22, py + math.cos(k / 4) * 10)
      U.wait(1)
      if k == 30 then
        log("stroking: zoom", ("%.2f"):format(st().zoom), "hand", st().hand, "calm", ("%.2f"):format(st().calm))
        shot("p05_stroke")
      end
      if not shotNotes and love.timer.getTime() - t0 > 1.3 then
        shotNotes = true
        shot("p05c_stroke_feedback")
      end
      if st().locked then rewarded = true; break end
    end
    log(("petting reward after %.2f s: %s; affection %d -> %d; hopping %s"):format(love.timer.getTime() - t0,
      tostring(rewarded), aff0, R.state().meters.affection, tostring(st().hopping)))
    U.wait(3)
    shot("p05b_reward")
    release("pet", px, py)
    settle()
    -- a tap on each zone: the reaction
    for _, zone in ipairs({ "head", "face", "cheeks", "chest", "side", "bottom" }) do
      U.wait(40)
      local zx, zy = app.tapPoint("zone", zone)
      tapAt("z" .. zone, zx, zy)
      U.wait(4)
      log("zone", zone, "hand", st().hand, "emote", st().emote)
      shot("p06_zone_" .. zone)
      settle()
    end
    -- a hit: a second press on the body within 4 ticks of the first
    do
      local hx, hy = app.tapPoint("zone", "chest")
      local e0 = R.state().meters.enjoyment
      press("h1", hx, hy); U.wait(1); release("h1", hx, hy)
      press("h2", hx, hy); U.wait(1); release("h2", hx, hy)
      U.wait(3)
      log("hit: enjoyment", e0, "->", R.state().meters.enjoyment, "emote", st().emote)
      shot("p06b_hit")
      waitSecs(0.5)
      press("h3", hx, hy); U.wait(2); release("h3", hx, hy)
      waitSecs(0.3)
      press("h4", hx, hy); U.wait(2); release("h4", hx, hy)
      log("two slow taps: enjoyment", R.state().meters.enjoyment)
      settle()
    end
    -- a high five: a finger held off the Pokemon until the countdown runs out (high affection: soon)
    do
      R.state().meters.affection = 255
      local e0 = R.state().meters.enjoyment
      local t0 = love.timer.getTime()
      press("five", 248, 112)
      U.wait(3)
      log("five held:", tostring(st().fiveHeld), "left", ("%.2f"):format(st().fiveLeft or -1), "wake", st().wake, "hand", st().hand)
      -- (the countdown was rolled at the visit's start, at that affection: up to ~7 s)
      while R.state().meters.enjoyment <= e0 and love.timer.getTime() - t0 < 12 do U.wait(1) end
      log(("high five after %.2f s: enjoyment %d -> %d; jumping %s"):format(love.timer.getTime() - t0, e0,
        R.state().meters.enjoyment, tostring(st().jumping)))
      -- the leap at the hand: on its way, at the top, landing
      waitSecs(0.12); shot("p07b_five_rising")
      waitSecs(0.16); shot("p07b_five_peak")
      waitSecs(0.3); shot("p07b_five_landing")
      release("five", 248, 112)
      waitFor(function() return not st().jumping end, 600)
      settle()
    end
    -- the strip and a meal
    local Rules = R.rules
    local jar = R.puffs()
    for _, p in ipairs(Rules.PUFFS) do Rules.jarAdd(jar, p.id) end
    R.state().meters.fullness = 0
    -- a few kinds stacked several deep, so the counts show
    for _ = 1, 3 do Rules.jarAdd(jar, Rules.PUFFS[1].id); Rules.jarAdd(jar, Rules.PUFFS[2].id) end
    tapAt("puffbtn", app.tapPoint("puff_btn"))
    waitSecs(0.08)
    shot("p07a_strip_opening")
    waitFor(function() return st().strip > 0.98 end, 600)
    U.wait(4)
    shot("p07_strip")
    log("drawer:", st().kinds, "kinds; scroll", ("%.1f"):format(st().scroll))
    -- a sideways drag scrolls it; the pad's left scrolls back a puff at a time
    do
      local rx, ry = app.tapPoint("strip")
      press("scr", rx, ry); U.wait(1)
      for k = 1, 12 do move("scr", rx - k * 14, ry); U.wait(1) end
      release("scr", rx - 12 * 14, ry)
      waitSecs(0.6)
      log("after a drag left: scroll", ("%.1f"):format(st().scroll))
      shot("p07c_scrolled")
      local s1 = st().scroll
      U.tap(game, "left"); waitSecs(0.4)
      log("pad left: scroll", ("%.1f"):format(s1), "->", ("%.1f"):format(st().scroll))
      for _ = 1, 12 do U.tap(game, "left"); U.wait(2) end
      waitSecs(0.5)
      log("pad left x12: scroll", ("%.1f"):format(st().scroll))
    end
    local mx, my = app.tapPoint("pet")
    local function pull(id, i)
      local sx, sy = app.tapPoint("slot", i)
      press(id, sx, sy); U.wait(1)
      for k = 1, 4 do move(id, sx, sy + k * 6); U.wait(1) end   -- down out of the drawer
      return sx, sy + 24
    end
    local function carry(id, fx, fy, tx, ty, n)
      for k = 1, n or 10 do move(id, fx + (tx - fx) * k / (n or 10), fy + (ty - fy) * k / (n or 10)); U.wait(1) end
    end
    -- 1. offered, then taken back to the puff button before the first bite: back in the jar
    do
      local n0 = #R.puffs()
      local px, py = pull("back", 1)
      carry("back", px, py, mx, my)
      waitFor(function() return st().feed ~= nil end, 200)
      log("offered: feed", st().feed, "jar", n0, "->", #R.puffs())
      local bx, by = app.tapPoint("puff_btn")
      carry("back", mx, my, bx, by, 4)
      release("back", bx, by)
      U.wait(4)
      log("put back before a bite: jar", #R.puffs(), "(was", n0 .. "); feed", tostring(st().feed))
      settle(1200)
    end
    -- 2. let go of on the grass, never offered: it falls away and is lost
    do
      local n0 = #R.puffs()
      local px, py = pull("lost", 2)
      carry("lost", px, py, 40, 200, 6)
      release("lost", 40, 200)
      U.wait(3)
      log("let go off the Pokemon: jar", n0, "->", #R.puffs(), "falling", st().falling)
      shot("p08a_puff_falls")
      settle(600)
    end
    -- 3. the meal: held to it, it eats while the puff stays at its mouth
    local px, py = pull("puff", 2)
    carry("puff", px, py, mx, my)
    shot("p08_drag")
    waitFor(function() return st().feed == "flash" end, 200)
    U.wait(3)
    shot("p09_meal_flash")
    waitFor(function() return st().feed == "eat" end, 1200)
    log("eating: at mouth", tostring(st().atMouth))
    waitFor(function() local f = R.state().feeding; return f and f.taken >= 1 end, 2400)
    U.wait(2)
    shot("p10_meal_bite")
    -- pulled away mid-meal: it waits; brought back, it carries on
    do
      local f = R.state().feeding
      local taken = f and f.taken or -1
      carry("puff", mx, my, mx + 90, my - 40, 4)
      waitSecs(1.2)
      local f2 = R.state().feeding
      log("pulled away: at mouth", tostring(st().atMouth), "bites", taken, "->", f2 and f2.taken or "done")
      carry("puff", mx + 90, my - 40, mx, my, 4)
    end
    waitFor(function() return st().feed == "after" end, 4800)
    U.wait(6)
    shot("p11_meal_done")
    release("puff", mx, my)
    settle(2400)
    shot("p12_back_out")
    -- 4. let go of mid-meal: the rest falls away
    do
      local n0 = #R.puffs()
      R.state().meters.fullness = 0
      local qx, qy = pull("mid", 1)
      carry("mid", qx, qy, mx, my)
      waitFor(function() local f = R.state().feeding; return f and f.taken >= 1 end, 2400)
      release("mid", mx, my)
      U.wait(3)
      log("let go mid-meal: jar", n0, "->", #R.puffs(), "feeding", tostring(R.state().feeding ~= nil),
        "falling", st().falling, "feed", tostring(st().feed))
      settle(1200)
    end
    -- the drawer stays open after a meal: the puff button folds it, then the picker
    tapAt("puffclose", app.tapPoint("puff_btn"))
    waitFor(function() return st().strip < 0.02 end, 600)
    log("drawer folded:", ("%.2f"):format(st().strip))
    tapAt("playbtn", app.tapPoint("play_btn"))
    U.wait(30)
    log("picker:", st().picker and st().picker.stage, st().picker and st().picker.game)
    shot("p13_picker_berry")
    tapAt("right", app.tapPoint("arrow_r")); U.wait(30)
    shot("p14_picker_head")
    tapAt("right2", app.tapPoint("arrow_r")); U.wait(30)
    shot("p15_picker_tile")
    tapAt("left", app.tapPoint("arrow_l")); U.wait(10)
    tapAt("left2", app.tapPoint("arrow_l")); U.wait(30)
    log("picker back to:", st().picker and st().picker.game)
    -- the pad: right / left between the games, A for its difficulties, left / right there, B back
    do
      local function pk() local p = st().picker; return p and (p.stage .. " game " .. p.game .. " diff " .. p.diff) or "none" end
      U.tap(game, "right"); U.wait(20)
      log("pad right:", pk())
      U.tap(game, "right"); U.wait(20)
      U.tap(game, "right"); U.wait(20)
      log("pad right x2 more (stops at the last):", pk())
      U.tap(game, "a"); U.wait(30)
      log("pad A:", pk())
      shot("p15b_pad_diff")
      U.tap(game, "left"); U.wait(20)
      log("pad left on the difficulties:", pk())
      U.tap(game, "b"); U.wait(30)
      log("pad B:", pk())
      U.tap(game, "left"); U.wait(15)
      U.tap(game, "left"); U.wait(30)
      log("pad left x2:", pk())
    end
    tapAt("badge", app.tapPoint("badge", 1)); U.wait(30)
    log("picker:", st().picker and st().picker.stage, "diff", st().picker and st().picker.diff)
    shot("p16_picker_diff")
    tapAt("diff", app.tapPoint("diff", 1)); U.wait(30)
    log("after Easy: mode", R.state().mode, "app", Apps:active().id)
    shot("p17_berry_started")
    R.session.finish()
    U.wait(5)
    -- left alone: it dozes off after the game's 900 ticks (30 s), sleeps, and goes back to the room
    log("open play again:", R.openPlay())
    U.wait(10)
    tapAt("wake2", app.tapPoint("pet"))
    waitFor(function() return st().wake == "awake" end, 2400)
    local tIdle = love.timer.getTime()
    waitFor(function() return st().wake == "dozing" or R.state().mode ~= "play" end, 60 * 60 * 3)
    log(("dozing after %.1f s idle"):format(love.timer.getTime() - tIdle))
    U.wait(30)
    shot("p18_dozing")
    waitFor(function() return R.state() == nil or R.state().mode ~= "play" end, 60 * 60 * 3)
    log(("idle end: mode %s after %.1f s; app %s"):format(tostring(R.state() and R.state().mode),
      love.timer.getTime() - tIdle, Apps:active() and Apps:active().id))
    U.wait(20)
    shot("p19_back_in_room")
    R.session.finish()
    U.wait(5)
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
