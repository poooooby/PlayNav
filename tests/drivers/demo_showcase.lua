-- Driver: a showcase of PlayNav at the game's own speed, for recording. Run it paced
-- (POKEPORT_DRIVER_PACED=1) so a second on screen is a second of play:
--   1. the art extraction (a real run over the cache), its play button, the PlayNav menu
--   2. Super Training: punches on the blank bag, a bag found, the bag drawer, the Effort-o-Meter
--      growing with each cleared bag, a short regimen and its results
--   3. Pokemon-Amie: the room, DECORATE, visitors and their gift, SWITCH with each Pokemon's
--      meters, PLAY (waking, petting, a meal, a high five), each minigame in brief
--   4. Kanto Gear's store tiles for both apps, each opened from its tile
-- A finger marker shows every touch and a caption names each part. Home in the game window
-- starts it; Home during a run stops it (every shortcut put back, PlayNav's screens closed)
-- and it waits for Home again, as it does after a run through.
--   POKEPORT_DRIVER_PACED=1 SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/demo_showcase.lua love .
-- Env: SHOT_W / SHOT_H the window (720 x 1040: the picture on top, the touch screen as tall
-- under it), DEMO_CAPTIONS=0 hides the captions,
-- DEMO_EXTRACT=0 skips the real extraction (the gate's states are shown pinned instead),
-- DEMO_WAIT=0 starts at once (else Home in the game window starts it), DEMO_MUSIC_VOL=<0-7>
-- the music's volume for the run (7), DEMO_ONLY=<extract,training,amie,play,games,gear> runs only those parts, DEMO_PAD=1 keeps
-- the engine's on-screen pad, DEMO_SHOTS=0 takes no screenshots (one after each caption).
-- Demo-only shortcuts, restored afterwards: a stat bag gives DEMO_EV (64) EVs so the meter's
-- growth shows; the visitors chat CHAT_S (7) seconds, not the game's thirty.

local DEMO_EV = 64
local CHAT_S = 7

local function body(game, log)
  local U0 = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  -- Home: a fresh press starts the demo, and during a run stops it and goes back to ready
  local RESTART = setmetatable({}, { __tostring = function() return "demo restart" end })
  local running, homeWas = false, false
  local function homePressed()
    local down = love.keyboard.isDown("home")
    local pressed = down and not homeWas
    homeWas = down
    return pressed
  end
  local U = setmetatable({
    wait = function(n)
      for _ = 1, n or 1 do
        U0.wait(1)
        if homePressed() and running then error(RESTART, 0) end
      end
    end,
  }, { __index = U0 })
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function secs(s) local t = love.timer.getTime(); while love.timer.getTime() - t < s do U.wait(1) end end
  -- wait on the wall clock for pred, at most s seconds
  local function within(s, pred)
    local t = love.timer.getTime()
    while love.timer.getTime() - t < s do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 720, tonumber(os.getenv("SHOT_H")) or 1040, { resizable = true, highdpi = true })
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
  local StartMenu = require("src.ui.game3.start_menu")
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  local s0 = Runtime.getSession()
  if s0 then s0.x, s0.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s0 and #(s0.party or {}) == 0 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 16)
    Party.giveMon(s0, C:require("species", "SPECIES_MARILL"), 14)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 12)
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display
  opts.display = "split"
  local Apps = X.apps
  local Extract = X._test.extract and X._test.extract()
  if Extract then
    waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 300)
  end
  waitFor(function() return game.phase == "field" end, 1200)

  -- the music on for the run (the engine's options file untouched): DEMO_MUSIC_VOL 0-7, 7 default
  local okAu, Audio = pcall(require, "src.core.game3.audio")
  if okAu and type(Audio) == "table" then
    Audio._bgmVolume = (tonumber(os.getenv("DEMO_MUSIC_VOL")) or 7) / 7
    if Audio._audioMode == "external_only" then Audio._audioMode = nil end
  end
  -- ready: the window's title says so, and Home starts the demo (DEMO_WAIT=0 runs it once)
  local WAIT = os.getenv("DEMO_WAIT") ~= "0"
  local title0 = love.window.getTitle()
  local function ready()
    love.window.setTitle("PlayNav demo ready: press Home to start (Home again restarts)")
    log("ready: press Home in the game window to start")
    local pressed = false
    repeat
      U0.wait(1)
      pressed = homePressed()
    until pressed
    love.window.setTitle(title0)
    secs(0.5)
  end

  -- every demo shortcut goes through tweak(), so a restart (or the part's end) puts it back
  local undo, saved = {}, {}
  local function tweak(t, k, v)
    saved[t] = saved[t] or {}
    if saved[t][k] == nil then
      local old = t[k]
      saved[t][k] = true
      undo[#undo + 1] = function() t[k] = old end
    end
    t[k] = v
  end
  local function later(fn) undo[#undo + 1] = fn end
  local function undoAll()
    for i = #undo, 1, -1 do pcall(undo[i]) end
    undo, saved = {}, {}
  end

  local only = {}
  for part in (os.getenv("DEMO_ONLY") or ""):gmatch("[%w_]+") do only[part] = true end
  local function wanted(part) return next(only) == nil or only[part] end

  -- ------- what the recording shows over the game: the fingers and a caption

  local CAPTIONS = os.getenv("DEMO_CAPTIONS") ~= "0"
  -- where the top screen ends in the window: above PlayNav's touch screen (the split keeps one
  -- layout, so the last one seen holds while the surface is down), or the Gear's stacked half
  local gearSplit = nil
  local gearSession
  do
    local hook = loader.exports.kanto_gear and loader.exports.kanto_gear.modules
    for i = 1, 60 do
      local name, v = debug.getupvalue(hook and hook.register or print, i)
      if not name then break end
      if name == "session" then gearSession = v end
    end
  end
  local function topFoot()
    if gearSplit then return gearSplit end
    local r = X.state().rect
    if r and X.state().mode ~= "off" then return r.y - 6 end
    -- PlayNav's surface down: the Gear's own screen under the game, when it shows
    local gr = gearSession and gearSession.primaryBottomRect
    if gr and gr.y > 0 then return gr.y - 6 end
    return love.graphics.getHeight() - 6
  end
  local fingers, ripples = {}, {}
  local caption, captionAt = nil, 0
  local SHOTS = os.getenv("DEMO_SHOTS") ~= "0"
  local shotN, shotDone = 0, true
  local font
  -- the engine's own on-screen pad stays off for the recording (DEMO_PAD=1 keeps it); touches
  -- still go through it to PlayNav and the Gear
  local okTC, TC = pcall(require, "src.core.TouchControls")
  local hidePad = okTC and type(TC) == "table" and os.getenv("DEMO_PAD") ~= "1"
  do
    local draw0 = love.draw
    love.draw = function(...)
      if hidePad and TC.enabled ~= false then TC.enabled = false end
      local a, b = draw0(...)
      local G = love.graphics
      G.push("all")
      G.origin()
      G.setCanvas()
      local now = love.timer.getTime()
      for i = #ripples, 1, -1 do
        local r = ripples[i]
        local k = (now - r.t) / 0.35
        if k >= 1 then table.remove(ripples, i)
        else
          G.setColor(1, 1, 1, 0.7 * (1 - k))
          G.setLineWidth(3)
          G.circle("line", r.x, r.y, 16 + 22 * k)
        end
      end
      for _, f in pairs(fingers) do
        G.setColor(1, 1, 1, 0.38)
        G.circle("fill", f.x, f.y, 17)
        G.setColor(0.15, 0.15, 0.2, 0.75)
        G.setLineWidth(2.5)
        G.circle("line", f.x, f.y, 17)
      end
      if SHOTS and caption and not shotDone and now - captionAt > 1.2 and not game.capturePath then
        shotDone = true
        shotN = shotN + 1
        game.capturePath = ("%s/demo_%02d_%s.png"):format(dir, shotN, (caption:gsub("[^%w]+", "_"):sub(1, 40)))
      end
      if CAPTIONS and caption then
        font = font or G.newFont(22)
        G.setFont(font)
        local a2 = math.min(1, (now - captionAt) / 0.3)
        local w = font:getWidth(caption) + 36
        local x, y = 16, topFoot() - 40 - 14
        G.setColor(0.08, 0.06, 0.16, 0.78 * a2)
        G.rectangle("fill", x, y, w, 40, 10, 10)
        G.setColor(0.55, 0.4, 1, 0.9 * a2)
        G.setLineWidth(2)
        G.rectangle("line", x, y, w, 40, 10, 10)
        G.setColor(1, 1, 1, a2)
        G.print(caption, x + 18, y + 8)
      end
      G.pop()
      return a, b
    end
  end
  local function say(text)
    caption, captionAt = text, love.timer.getTime()
    shotDone = false
    if text then log("--", text) end
  end

  -- ------- touches in app units (the touch screen's 256-wide space), with the marker

  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local nextId = 0
  local function newId() nextId = nextId + 1; return "demo" .. nextId end
  local function down(id, ax, ay)
    local x, y = win(ax, ay)
    fingers[id] = { x = x, y = y }
    love.touchpressed(id, x, y, 0, 0, 1)
  end
  local function moveTo(id, ax, ay)
    local x, y = win(ax, ay)
    local f = fingers[id]
    local dx, dy = f and x - f.x or 0, f and y - f.y or 0
    fingers[id] = { x = x, y = y }
    love.touchmoved(id, x, y, dx, dy, 1)
  end
  local function up(id, ax, ay)
    local x, y = win(ax, ay)
    fingers[id] = nil
    ripples[#ripples + 1] = { x = x, y = y, t = love.timer.getTime() }
    love.touchreleased(id, x, y, 0, 0, 1)
  end
  local function tap(ax, ay, hold)
    if not ax then log("  no point to tap"); return end
    local id = newId()
    down(id, ax, ay)
    secs(hold or 0.09)
    up(id, ax, ay)
    U.wait(2)
  end
  -- a finger moved from (x0, y0) to (x1, y1) over t seconds (eased), already down or put down
  local function glide(id, x0, y0, x1, y1, t)
    local t0 = love.timer.getTime()
    while true do
      local k = math.min(1, (love.timer.getTime() - t0) / t)
      local e = k * k * (3 - 2 * k)
      moveTo(id, x0 + (x1 - x0) * e, y0 + (y1 - y0) * e)
      U.wait(1)
      if k >= 1 then break end
    end
  end
  local function drag(x0, y0, x1, y1, t)
    if not (x0 and x1) then log("  no point to drag"); return end
    local id = newId()
    down(id, x0, y0)
    secs(0.12)
    glide(id, x0, y0, x1, y1, t or 0.6)
    secs(0.08)
    up(id, x1, y1)
    U.wait(2)
  end
  local function rectMid(r) return r.x + r.w / 2, r.y + r.h / 2 end
  local function pad(btn, after) U.tap(game, btn); secs(after or 0.25) end

  -- START -> PLAYNAV, the cursor walked there as a player would
  local function startPlayNav()
    for _ = 1, 5 do
      U.tap(game, "start")
      secs(0.5)
      if #(StartMenu.ENTRIES or {}) > 0 then break end
    end
    local idx
    for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "play_nav" then idx = i end end
    if not idx then log("FAIL no PLAYNAV entry"); return false end
    local moves = idx - (StartMenu.cursor or 1)
    for _ = 1, math.abs(moves) do pad(moves > 0 and "down" or "up", 0.22) end
    secs(0.4)
    pad("a", 0.2)
    return true
  end

  local function segment(name, fn)
    if not wanted(name) then return end
    log("== " .. name)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok and err == RESTART then error(RESTART, 0) end
    if not ok then log("SEGMENT FAILED", name, tostring(err)) end
    for id, f in pairs(fingers) do love.touchreleased(id, f.x, f.y, 0, 0, 1) end
    fingers = {}
    undoAll()
  end

  local function runAll()

  -- ======================================================================== the extraction

  segment("extract", function()
    local M = X.menu
    if not Extract then log("  no extraction in this build"); return end
    local complete0 = Extract.cacheComplete
    later(function()
      Extract.cacheComplete = complete0
      if Extract.state ~= "running" and Extract.state ~= "finishing" and complete0() then Extract.state = "complete" end
    end)
    local real = os.getenv("DEMO_EXTRACT") ~= "0" and Extract.importPresent()
    say("PlayNav: built from your own Alpha Sapphire")
    secs(1.5)
    -- the screen a first run meets: BEGIN EXTRACTION
    Extract.cacheComplete = function() return false end
    Extract.state = "idle"
    startPlayNav()
    secs(0.6)
    log("  gate up:", Apps:active().id, Extract.state)
    say("One extraction from your card image")
    secs(2.2)
    local imp = Apps:get("import")
    local h = (X.H or 230) - (X.state().tabHeight or 0)
    local dh = math.max(0, h - 178) / 2
    local bx, by = rectMid(imp.BEGIN)
    if real then
      Extract.cacheComplete = complete0
      tap(bx, by + dh, 0.14)
      log("  extraction:", Extract.state)
      within(300, function() return Extract.state ~= "running" and Extract.state ~= "finishing" end)
      log("  extraction done:", Extract.state, "complete", tostring(Extract.cacheComplete()))
    else
      -- the bar shown pinned (the real update would write an empty manifest meanwhile)
      local update0, progress0 = Extract.update, Extract.progress
      tweak(Extract, "update", function() end)
      Extract.state = "running"
      local t0 = love.timer.getTime()
      tweak(Extract, "progress", function() return math.min(1407, math.floor((love.timer.getTime() - t0) / 4 * 1407)), 1407 end)
      tap(bx, by + dh, 0.14)
      secs(4.2)
      Extract.update, Extract.progress = update0, progress0
      Extract.cacheComplete = complete0
      Extract.state = "done"
    end
    secs(1.6)
    say("The PlayNav menu")
    tap(imp.PLAY.x, imp.PLAY.y + dh, 0.14)
    within(5, function() return M and M.shown() end)
    secs(2.0)
    log("  menu shown:", tostring(M and M.shown()))
  end)

  if X.menu and not X.menu.shown() then
    X.menu.open()
    secs(1.0)
  end
  local Menu = X.menu.app

  -- ======================================================================== Super Training

  segment("training", function()
    local TR = X.training
    local T = TR.session
    local TRules = TR.rules
    -- the rack: a few bags to choose from; the trainee awake on the blank bag
    local bags = TR.store.bags()
    for i = #bags, 1, -1 do bags[i] = nil end
    for _, id in ipairs({ "hp_l", "atk_l", "spe_l", "def_l", "spa_m", "double_up" }) do TRules.inventoryAdd(bags, id) end
    say("Super Training")
    secs(0.8)
    tap(Menu.tapPoint("card", "training"))
    within(6, function() return T.session ~= nil and T.session.trans == nil and Apps:active().id == "training_core" end)
    local rec = T.session.rec
    rec.resting, rec.bag, rec.secondWind, rec.bagsToRest, rec.fully = false, nil, nil, 99, nil
    -- the meter starts low each take
    do
      local mon = T.session.mon
      local evs = TR.host.evsOf(mon)
      for k in pairs(evs) do evs[k] = 0 end
      TR.host.setEvs(mon, evs)
      T.session.evs = evs
    end
    secs(1.5)
    local core = Apps:get("training_core")
    local geo = core.geometry()
    local bagX, bagY = rectMid(geo.BAG)
    -- punches on the blank bag (no find yet)
    say("Punch the bag")
    local rng0 = T.rng
    tweak(T, "rng", function() return 0.99 end)
    for _ = 1, 5 do
      tap(bagX, bagY)
      secs(0.55)
    end
    -- the next one digs up a bag: the game's presentation
    say("A new bag drops down!")
    tweak(T, "rng", function() return 0.01 end)
    tap(bagX, bagY)
    T.rng = rng0
    within(8, function() return not T.gifting() end)
    secs(1.0)
    log("  found:", tostring(bags[#bags]), "rack", #bags)
    -- the bag drawer: choose the HP bag, USE, Yes
    say("The bag drawer")
    tap(rectMid(geo.BAGS))
    within(3, function() return TR.state().mode == "bags" end)
    secs(1.0)
    local bagsApp = Apps:get("training_bags")
    local bg = bagsApp.geometry()
    tap(rectMid(bg.slotRect(1)))
    secs(1.8)
    tap(rectMid(bg.button(1, 3)))
    secs(1.3)
    tap(rectMid(bg.button(1, 2)))
    within(4, function() return TR.state().mode == "core" end)
    secs(0.8)
    log("  on the stand:", tostring(rec.bag and rec.bag.id))
    -- the Effort-o-Meter: each cleared bag grows it (DEMO_EV a bag, to see it)
    local evs0 = {}
    for _, id in ipairs({ "hp_l", "atk_l", "spe_l", "def_l", "spa_m" }) do
      local d = TRules.bag(id)
      if d then evs0[id] = d.ev; tweak(d, "ev", DEMO_EV) end
    end
    local lock0, finish0 = T.HIT_LOCK, T.FINISH_MOVE
    tweak(T, "HIT_LOCK", 0.06)
    local function punchOut()
      -- quick punches; a second wind makes each count double
      rec.secondWind = true
      local t0 = love.timer.getTime()
      while rec.bag and love.timer.getTime() - t0 < 12 do
        tap(bagX, bagY, 0.04)
        secs(0.05)
      end
    end
    say("Clear the bag: the Effort-o-Meter grows")
    punchOut()
    within(10, function() return not T.finishing() end)
    secs(1.6)
    tweak(T, "FINISH_MOVE", false)
    for _, id in ipairs({ "atk_l", "spe_l", "def_l" }) do
      local at
      for i, b in ipairs(bags) do if b == id then at = i end end
      if at then
        T.attachBag(at)
        secs(0.6)
        punchOut()
        -- the +N over the stat's label and the gauge's arrow, as the finishing move leaves them
        local d = TRules.bag(id)
        if d and T.session and T.session.anim then
          T.session.anim.statUp = { stat = d.stat, added = DEMO_EV, t = 0 }
        end
        secs(1.8)
      end
    end
    T.HIT_LOCK, T.FINISH_MOVE = lock0, finish0
    for id, ev in pairs(evs0) do TRules.bag(id).ev = ev end
    local e = TR.host.evsOf(T.session.mon)
    log(("  evs now hp %d atk %d def %d spe %d"):format(e.hp or 0, e.atk or 0, e.def or 0, e.spe or 0))
    secs(1.0)

    -- a regimen, quickly
    say("Training regimens")
    tap(rectMid(geo.REGIMENS))
    within(6, function() return TR.state().mode == "courses" and T.session.trans == nil end)
    secs(1.2)
    local coursesApp = Apps:get("training_courses")
    local tile = coursesApp.geometry().slots[2]
    tap(rectMid(tile))
    secs(2.0)
    tap(rectMid(tile))
    within(6, function() return T.sim ~= nil end)
    local sim = T.sim
    within(16, function() return sim.phase == "play" end)
    say("Shoot the balloon's targets")
    local aim = Apps:get("training_aim")
    local t0 = love.timer.getTime()
    local n = 0
    while love.timer.getTime() - t0 < 11 and sim.phase == "play" do
      local st = sim:state()
      local g = st.goals[1]
      if g then
        local px, py = aim.padPointFor(g.x, g.y)
        local id = newId()
        down(id, px, py); secs(0.14); up(id, px, py)
        n = n + 1
      end
      if n % 4 == 1 then U.hold(game, "left", 10) elseif n % 4 == 3 then U.hold(game, "right", 10) end
      secs(0.35)
    end
    log("  shots", n, "score", sim:state().score, "/", sim:state().target)
    if sim.phase == "play" then T.forceEnd({ clear = true, remaining = sim.remaining }) end
    say("Cleared!")
    within(14, function() return TR.state().mode == "result" end)
    secs(3.0)
    for _ = 1, 10 do
      if TR.state().mode ~= "result" then break end
      tap(128, 90)
      secs(1.1)
    end
    within(6, function() return TR.state().mode == "courses" and T.session.trans == nil end)
    secs(0.8)
    tap(rectMid(coursesApp.geometry().RETURN))
    within(6, function() return TR.state().mode == "core" and T.session.trans == nil end)
    secs(1.2)
    tap(rectMid(core.geometry().CLOSE))
    within(4, function() return X.menu.shown() end)
    secs(1.2)
  end)

  -- ======================================================================== Pokemon-Amie

  local A = X.amie
  local G = A.session
  local Rules = A.rules
  local home, deco, play = Apps:get("home"), Apps:get("decorate"), Apps:get("play")
  local function homeIdle(extra)
    U.wait(2)
    within(6, function() return not home.busy() end)
    secs(extra or 0.3)
  end
  local function decoIdle(extra)
    U.wait(2)
    within(6, function() return not deco.busy() end)
    secs(extra or 0.3)
  end
  local function playIdle(extra)
    U.wait(2)
    within(8, function() return not play.busy() end)
    secs(extra or 0.3)
  end
  local function openRoomMenu()
    for _ = 1, 4 do
      tap(home.petPos())
      secs(0.4)
      if home.menuOpen() then return true end
      secs(0.6)
    end
    return home.menuOpen()
  end
  local function pressRoomButton(which)
    if not home.menuOpen() then openRoomMenu() end
    secs(0.9)
    tap(home.buttonPos(which))
  end
  -- every party member's meters, different so SWITCH shows them change
  local function seedAmie()
    local party = Runtime.getSession().party
    local levels = { { 150, 90, 200 }, { 255, 255, 60 }, { 40, 170, 255 } }
    for i = 1, math.min(3, #party) do
      local key = A.monKey(party[i])
      local m = key and A.store.meters(key)
      if m then m.affection, m.fullness, m.enjoyment = levels[i][1], levels[i][2], levels[i][3] end
    end
    local decor = A.decor.ensure(A.store.decor())
    local n = 0
    for _, r in ipairs(A.decor.ITEMS) do if r.kind == "cushion" and n < 8 then A.decor.own(decor, r.id); n = n + 1 end end
    A.decor.own(decor, "wall/blue"); A.decor.own(decor, "wall/orange"); A.decor.own(decor, "wall/green")
    local jar = A.puffs()
    local deluxe
    for _, p in ipairs(Rules.PUFFS) do if p.tier == "deluxe" and not deluxe then deluxe = p.id end end
    for _, p in ipairs(Rules.PUFFS) do
      if p.tier == "basic" or p.tier == "frosted" then Rules.jarAdd(jar, p.id) end
    end
    if deluxe then for _ = 1, 3 do Rules.jarAdd(jar, deluxe) end end
    local room = A.store.room()
    room.items, room.puffOut = {}, nil
    local vis = A.store.visitors()
    vis.gifts = {}
    A.store.saveDecor(); A.store.savePuffs(); A.store.saveRoom(); A.store.saveVisitors()
    return deluxe
  end

  segment("amie", function()
    local deluxe = seedAmie()
    local V = G.Visitors
    local chat0 = V.CHAT_SECS
    say("Pokemon-Amie")
    secs(0.8)
    tap(Menu.tapPoint("card", "amie"))
    within(6, function() return G.session ~= nil and Apps:active().id == "home" end)
    V.reset()
    V.nextArrival = 1e9   -- the visitors wait until a puff is out
    homeIdle(2.0)
    say("The Amie room")
    secs(1.5)
    openRoomMenu()
    homeIdle(2.2)

    -- DECORATE
    say("Decorate")
    tap(home.buttonPos("decorate"))
    within(6, function() return Apps:active().id == "decorate" end)
    decoIdle(1.0)
    tap(deco.tapPoint("wallRight"))
    decoIdle(1.0)
    -- two cushions, each pressed out of the drawer and dragged onto a guest seat
    for k, seat in ipairs({ 1, 3 }) do
      tap(deco.tapPoint("interior"))
      decoIdle(0.8)
      local cx, cy = deco.tapPoint("cell", k)
      local id = newId()
      down(id, cx, cy)
      U.wait(3)
      local hx, hy = deco.tapPoint("held")
      local sx, sy = deco.tapPoint("seatHold", seat)
      if hx and sx then
        local fx, fy = sx - (hx - cx), sy - (hy - cy)
        secs(0.25)
        glide(id, cx, cy, fx, fy, 0.8)
        secs(0.1)
        up(id, fx, fy)
      else
        up(id, cx, cy)
        log("  no held item from cell", k)
      end
      decoIdle(0.8)
    end
    log("  room items:", #A.store.room().items)
    -- a puff out: pulled from its drawer and let go in the room
    tap(deco.tapPoint("puffs"))
    decoIdle(0.8)
    local px, py = deco.tapPoint("cell", 1)
    local rx, ry = deco.tapPoint("room", { 150, 175 })
    drag(px, py, rx, ry, 0.8)
    decoIdle(1.0)
    log("  puff out:", tostring(A.store.room().puffOut))
    tap(deco.tapPoint("corner"))
    within(6, function() return Apps:active().id == "home" end)
    homeIdle(1.5)

    -- visitors drop by, chat and leave a gift
    say("Visitors drop by")
    tweak(V, "CHAT_SECS", CHAT_S)
    V.nextArrival = 0.5
    local pending = V.pending()
    within(45, function() return V.group ~= nil end)
    say("...and chat")
    within(CHAT_S + 6, function() return #pending > 0 end)
    say("They left a gift!")
    secs(2.5)
    if #pending > 0 then
      tap(home.giftPos(#pending))
      secs(3.5)
    end
    V.CHAT_SECS = chat0
    V.nextArrival = 1e9

    -- SWITCH: the party and each one's meters
    say("Switch: each Pokemon's affection, fullness, enjoyment")
    pressRoomButton("switch")
    within(4, function() local x = home.switchState(); return x and x.phase == "open" end)
    secs(1.8)
    tap(home.switchPos("slot", 2))
    secs(2.2)
    tap(home.switchPos("slot", 3))
    secs(2.2)
    tap(home.switchPos("slot", 2))
    secs(1.6)
    tap(home.switchPos("button"))
    within(6, function() return home.switchState() == nil end)
    homeIdle(2.0)
    log("  in the room:", tostring(G.session and G.session.name))
  end)

  segment("play", function()
    if not (G.session and G.session.mode == "home") then
      seedAmie()
      tap(Menu.tapPoint("card", "amie"))
      within(6, function() return G.session ~= nil and Apps:active().id == "home" end)
      homeIdle(1.0)
    end
    -- fond of you: it reaches for a held-out hand within a second or two
    local m = A.state().meters
    m.affection, m.fullness, m.enjoyment = 255, 0, 120
    say("Play")
    pressRoomButton("play")
    within(6, function() return Apps:active().id == "play" end)
    secs(1.8)
    local st = function() return play.state() end
    tap(play.tapPoint("pet"))
    within(6, function() return st().wake == "awake" end)
    secs(1.2)
    -- petting: stroked on the chest until it is pleased
    say("Petting")
    local cx, cy = play.tapPoint("zone", "chest")
    local id = newId()
    down(id, cx, cy)
    local t0, k = love.timer.getTime(), 0
    while love.timer.getTime() - t0 < 6 do
      k = k + 1
      moveTo(id, cx + math.sin(k / 5) * 20, cy + math.cos(k / 7) * 8)
      U.wait(1)
      if st().locked then break end
    end
    secs(0.8)
    up(id, cx, cy)
    playIdle(1.0)
    local hx, hy = play.tapPoint("zone", "head")
    id = newId()
    down(id, hx, hy)
    t0, k = love.timer.getTime(), 0
    while love.timer.getTime() - t0 < 3 do
      k = k + 1
      moveTo(id, hx + math.sin(k / 4) * 16, hy)
      U.wait(1)
      if st().locked then break end
    end
    up(id, hx, hy)
    playIdle(1.0)
    -- a meal: the drawer, a puff pulled out and held to its mouth
    say("Feeding a Poke Puff")
    tap(play.tapPoint("puff_btn"))
    within(3, function() return st().strip > 0.98 end)
    secs(1.0)
    local mx, my = play.tapPoint("pet")
    local sx, sy = play.tapPoint("slot", 1)
    id = newId()
    down(id, sx, sy)
    secs(0.15)
    glide(id, sx, sy, sx, sy + 24, 0.2)
    glide(id, sx, sy + 24, mx, my, 0.7)
    within(16, function() return st().feed == "after" end)
    secs(1.2)
    up(id, mx, my)
    playIdle(1.0)
    tap(play.tapPoint("puff_btn"))
    within(3, function() return st().strip < 0.02 end)
    secs(0.6)
    -- a high five: a hand held out off the Pokemon
    say("High five!")
    id = newId()
    down(id, 248, 112)
    within(6, function() return st().jumping end)
    within(3, function() return not st().jumping end)
    secs(0.4)
    up(id, 248, 112)
    playIdle(1.2)
  end)

  segment("games", function()
    if not (G.session and G.session.mode == "play") then
      local m0 = A.open()
      within(6, function() return Apps:active().id == "home" end)
      homeIdle(0.5)
      pressRoomButton("play")
      within(6, function() return Apps:active().id == "play" end)
      tap(play.tapPoint("pet"))
      within(6, function() return play.state().wake == "awake" end)
      log("  (play opened for the games:", tostring(m0), ")")
    end
    local Games = A.games
    for _, g in ipairs({ "berry", "head", "tile" }) do
      local r = Games.record and Games.record(g)
      if r then r.unlocked = math.max(r.unlocked or 1, 1) end
    end
    local function pick(i)
      tap(play.tapPoint("play_btn"))
      secs(1.4)
      for _ = 2, i do tap(play.tapPoint("arrow_r")); secs(1.0) end
      tap(play.tapPoint("badge", i))
      secs(1.4)
      tap(play.tapPoint("diff", 1))
    end
    local function quitGame(app)
      within(20, function() return app.debugState().phase == "buttons" end)
      secs(1.6)
      tap(app.tapPoint("quit"))
      within(6, function() return Apps:active().id == "play" end)
      playIdle(1.0)
    end

    -- Berry Picker
    say("Minigame: Berry Picker")
    pick(1)
    local berry = Apps:get("game_berry")
    within(8, function() return Apps:active().id == "game_berry" end)
    within(30, function() return berry.debugState().phase == "play" end)
    local function asker() for i = 1, 3 do if berry.wanted(i) then return i end end end
    local delivered, t0 = 0, love.timer.getTime()
    while love.timer.getTime() - t0 < 14 and delivered < 9 do
      if within(4, function() return asker() ~= nil end) then
        local i = asker()
        local bx, by = berry.tapPoint("berry", berry.wanted(i))
        local sx, sy = berry.tapPoint("slot", i)
        drag(bx, by, sx, sy, 0.38)
        delivered = delivered + 1
        secs(0.25)
      end
    end
    berry.debugState().timer = 2.5
    within(30, function() return berry.debugState().phase == "buttons" end)
    quitGame(berry)

    -- Head It
    say("Minigame: Head It")
    pick(2)
    local head = Apps:get("game_head")
    within(8, function() return Apps:active().id == "game_head" end)
    within(30, function() return head.debugState().phase == "play" end)
    local function headFor(s, untilFn)
      local tEnd = love.timer.getTime() + s
      while love.timer.getTime() < tEnd do
        local slot = head.nextTap("just")
        if slot then
          local hx, hy = head.tapPoint("slot", slot)
          tap(hx, hy, 0.05)
        else
          U.wait(1)
        end
        if untilFn and untilFn() then return end
      end
    end
    headFor(12)
    head.debugState().timer = 45
    headFor(20, function() return head.debugState().phase ~= "play" end)
    -- the giant ball: headed at the star
    within(12, function() local x = head.debugState(); return x.phase == "giant" and x.giant end)
    for _ = 1, 1200 do
      local gb = head.debugState().giant
      if not gb or gb.state ~= "fall" or gb.missed then break end
      local ty = 120 - gb.y + 350 * 0.4
      if ty >= 130 and ty < 180 then
        local hx, hy = head.tapPoint("slot", 1)
        tap(hx, hy, 0.05)
        break
      end
      U.wait(1)
    end
    quitGame(head)

    -- Tile Puzzle
    say("Minigame: Tile Puzzle")
    pick(3)
    local tile = Apps:get("game_tile")
    within(8, function() return Apps:active().id == "game_tile" end)
    secs(1.6)
    tap(tile.tapPoint("begin"))
    within(20, function() return tile.debugState().phase == "play" end)
    secs(0.6)
    for _ = 1, 40 do
      if tile.debugState().phase ~= "play" then break end
      local p, q = tile.nextMove()
      if not p then break end
      within(3, function() return not tile.busy() end)
      tap(tile.tapPoint("tile", q))
      secs(0.3)
      tap(tile.tapPoint("tile", p))
      secs(0.35)
    end
    quitGame(tile)

    -- back to the room, and out to the menu
    say("Back to the room")
    tap(play.tapPoint("back"))
    within(6, function() return Apps:active().id == "home" end)
    homeIdle(1.5)
    tap(home.closePos())
    within(4, function() return X.menu.shown() end)
    secs(1.2)
  end)

  -- ======================================================================== Kanto Gear

  segment("gear", function()
    local ex = loader.exports
    local hook = ex.kanto_gear and ex.kanto_gear.modules
    if not hook then log("  Kanto Gear is not loaded: part skipped"); return end
    if X.menu.shown() then
      tap(Menu.tapPoint("close"))
      secs(1.0)
    end
    -- the Gear's runtime is reached through its hook's upvalues (as gear_store_probe does)
    local function upvalue(fn, want)
      for i = 1, 60 do
        local name, v = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == want then return v end
      end
    end
    local DR = upvalue(hook.register, "displayRuntime")
    local gs = upvalue(hook.register, "session")
    local THEME = upvalue(hook.register, "THEME")
    if not (DR and gs and THEME) then log("  could not reach the Gear's runtime: part skipped"); return end
    -- the Gear's own screen beside the game for this part (options in memory only)
    loader.modOptions.kanto_gear = loader.modOptions.kanto_gear or {}
    local gopts = loader.modOptions.kanto_gear
    local saved = { display_mode = gopts.display_mode, combined_layout = gopts.combined_layout,
      secondary_size = gopts.secondary_size }
    -- stacked, the Gear's screen as tall as the game's
    gopts.display_mode, gopts.combined_layout, gopts.secondary_size = "combined", "stacked", 50
    local function changed(key, value)
      loader.events:emit("mod.options_changed", { mod = "kanto_gear", key = key, value = value })
    end
    changed("display_mode", "combined"); changed("combined_layout", "stacked"); changed("secondary_size", 50)
    do
      local ww, wh = love.graphics.getDimensions()
      local gap = math.max(2, math.floor(math.min(ww, wh) * 0.01))
      gearSplit = wh - math.floor((wh - gap) * 0.5) - gap
    end
    -- installed and placed for the demo; the Gear's home is never written to its save
    local saveHome0 = DR.saveHome
    DR.saveHome = function() end
    local IDS = { "super_training", "pokemon_amie" }
    local installed0 = {}
    for _, id in ipairs(IDS) do
      local pkg = DR.homeCatalog and DR.homeCatalog.packages[id]
      installed0[id] = pkg and pkg.installed
      if pkg then pkg.installed = true end
      if not (DR.storeOnHome and DR.storeOnHome(id)) and DR.storeHomeSpot then
        local s, p, c, r = DR.storeHomeSpot(id)
        if s then DR.Home.place(DR.home.layout, DR.homeCatalog, s, p, c, r) end
      end
    end
    local function homePage(id)
      for _, t in ipairs(DR.home.layout.tiles or {}) do if t.id == id .. "_app" then return t.page end end
    end
    local function showHome(page)
      gs.page = "HOME"
      DR.home.activeApp, DR.home.editing, DR.home.library = nil, false, false
      DR.home.help, DR.home.helpSeen = false, true
      if page then DR.home.page = page end
      gs.dirty = true
    end
    -- a tap at (hx, hy) on the Gear's 240 x 216 screen
    local function gearTap(hx, hy)
      local r = gs.primaryBottomRect
      if not r then log("  the Gear's screen is not up"); return end
      local x = r.x + (hx + 0.75) * r.w / 240
      local y = r.y + (hy + 0.75) * r.h / 216
      local id = newId()
      fingers[id] = { x = x, y = y }
      love.touchpressed(id, x, y, 0, 0, 1)
      secs(0.1)
      fingers[id] = nil
      ripples[#ripples + 1] = { x = x, y = y, t = love.timer.getTime() }
      love.touchreleased(id, x, y, 0, 0, 1)
      U.wait(2)
    end
    local function tileMid(id)
      for _, t in ipairs(DR.homePageElements() or {}) do
        if t.id == id .. "_app" then
          local x, y, w, h = THEME.hgss:homeRect(t)
          return x + w / 2, y + h / 2
        end
      end
    end
    local ok, err = pcall(function()
      secs(1.0)
      log("  the Gear's screen:", gs.primaryBottomRect and "up" or "not up")
      say("Kanto Gear: Silph Store")
      DR.openHomeApp("store")
      gs.dirty = true
      secs(1.0)
      for _, id in ipairs(IDS) do
        if DR.storeShow then DR.storeShow(id); gs.dirty = true end
        secs(2.6)
      end
      say("Kanto Gear: both apps on its home screen")
      showHome(homePage(IDS[1]))
      secs(3.0)
      for _, id in ipairs({ "pokemon_amie", "super_training" }) do
        showHome(homePage(id))
        secs(1.2)
        local hx, hy = tileMid(id)
        say(id == "pokemon_amie" and "Opened from its Kanto Gear tile: Pokemon-Amie" or "Opened from its Kanto Gear tile: Super Training")
        if hx then gearTap(hx, hy) else log("  no tile on screen for", id) end
        local opened = within(5, function()
          if id == "pokemon_amie" then return G.session ~= nil end
          return X.training.session.session ~= nil
        end)
        log("  " .. id .. " from its tile:", tostring(opened))
        secs(3.5)
        if id == "pokemon_amie" then G.finish() else X.training.finish() end
        within(4, function() return G.session == nil and X.training.session.session == nil end)
        secs(1.0)
      end
      showHome(homePage(IDS[1]))
      secs(2.0)
    end)
    if not ok and err ~= RESTART then log("  gear part failed:", tostring(err)) end
    for _, id in ipairs(IDS) do
      local pkg = DR.homeCatalog and DR.homeCatalog.packages[id]
      if pkg then pkg.installed = installed0[id] end
    end
    DR.saveHome = saveHome0
    gopts.display_mode, gopts.combined_layout, gopts.secondary_size = saved.display_mode, saved.combined_layout, saved.secondary_size
    changed("display_mode", saved.display_mode); changed("combined_layout", saved.combined_layout)
    changed("secondary_size", saved.secondary_size)
    gearSplit = nil
    if not ok and err == RESTART then error(RESTART, 0) end
  end)

  say(nil)
  caption = nil
  secs(1.0)
  end   -- runAll

  -- a restart: fingers up, shortcuts back, every PlayNav screen closed, the field again
  local function resetScene()
    for id, f in pairs(fingers) do love.touchreleased(id, f.x, f.y, 0, 0, 1) end
    fingers, ripples = {}, {}
    undoAll()
    say(nil)
    gearSplit = nil
    if Extract then within(300, function() return Extract.state ~= "running" and Extract.state ~= "finishing" end) end
    if X.amie.session.session then pcall(X.amie.session.finish) end
    if X.training.session.session then pcall(X.training.finish) end
    U0.wait(2)
    if X.menu.shown() then pcall(X.menu.close) end
    pcall(StartMenu.close, true)
    pcall(Apps.setActive, Apps, "play", game)
    secs(0.8)
  end

  repeat
    if WAIT then ready() end
    running = true
    local ok, err = xpcall(runAll, debug.traceback)
    running = false
    if not ok and err ~= RESTART then log("DEMO ERROR:", tostring(err)) end
    resetScene()
    log(ok and "the demo ran through" or (err == RESTART and "restarted: back to ready" or "the demo stopped"))
  until not WAIT

  if hidePad then
    hidePad = false
    if TC.applyOptions and type(game.options) == "table" then pcall(TC.applyOptions, TC, game.options) end
  end
  opts.display = savedDisplay
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
