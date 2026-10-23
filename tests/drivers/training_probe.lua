-- Driver: boots Emerald, opens Super Training from the START menu, hits a training bag to
-- completion on the touch surface, checks the EVs and HP on the real party record, gives
-- and uses a Health Wing through the engine's item use, and shots the screens.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/training_probe.lua love .

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
  -- one frame; a frame over STALL_S is logged with the sounds started just before it
  local STALL_S, lastFrame, recent = 0.1, nil, {}
  local function step()
    U.wait(1)
    local now = love.timer.getTime()
    if lastFrame and now - lastFrame > STALL_S then
      log(("  STALL %.0f ms after: %s"):format((now - lastFrame) * 1000, table.concat(recent, ", ")))
    end
    lastFrame = now
    for i = #recent, 1, -1 do recent[i] = nil end
  end
  local function noteSound(what) recent[#recent + 1] = what end
  local function waitSecs(secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do step() end
  end
  -- wait on the wall clock (the session runs on it) for pred, at most secs
  local function waitUntil(pred, secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do
      if pred() then return true end
      step()
    end
    return pred() and true or false
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
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
  local Stack3 = require("src.ui.game3.stack")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local function topId() local t = Stack3.top(); return t and t.id end
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s and #(s.party or {}) == 0 then
    -- PROBE_SPECIES (e.g. RAPIDASH): the lead, for a larger sprite; Torchic by default
    Party.giveMon(s, C:require("species", "SPECIES_" .. (os.getenv("PROBE_SPECIES") or "TORCHIC")), 12)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
  end
  U.wait(60)
  local loader = game.mods
  local MOD_ID = "play_nav"
  local X = loader and loader.exports and loader.exports[MOD_ID]
  if X and X.haptics then X.haptics.log = {} end
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  if not TR then log("FAIL training not exported"); return end
  local Apps = X.apps
  loader.modOptions[MOD_ID] = loader.modOptions[MOD_ID] or {}
  -- PLAYNAV_DISPLAY=second_screen runs it on the second display (the desktop companion
  -- window): touches go in through feedSecond in the pushed frame's pixels
  local SECOND = os.getenv("PLAYNAV_DISPLAY") == "second_screen"
  loader.modOptions[MOD_ID].display_mode = SECOND and "separate" or "combined"
  log("display:", loader.modOptions[MOD_ID].display_mode)
  loader.modOptions[MOD_ID].prompt_always = false
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  -- the music at each shot: our track, whether it sounds, and the field's music held or not
  local okAu, Audio = pcall(require, "src.core.game3.audio")
  -- PROBE_MUSIC_VOL=<0-7> sets the engine's music volume for this run (options.lua untouched)
  if okAu and os.getenv("PROBE_MUSIC_VOL") then
    Audio._bgmVolume = (tonumber(os.getenv("PROBE_MUSIC_VOL")) or 7) / 7
    log("music volume set to", Audio._bgmVolume)
  end
  -- PROBE_OWN_MENU=1: as without the card image's picker track (PlayNav's own stands in)
  if os.getenv("PROBE_OWN_MENU") == "1" then
    local A = X._test.assets()
    if A and A.manifest and A.manifest.assets then A.manifest.assets["bgm/sp_menu"] = nil end
    if A then A.tracks["bgm/sp_menu"] = nil end
  end
  local function musicState()
    local M = TR.session and TR.session.music
    local v = M and M.voice
    local playing = v and v.src and v.src:isPlaying()
    return ("music %s game song %s playing %s pos %s held %s | field paused %s stopped %s song %s"):format(
      tostring(M and M.current), tostring(M and M.gameCurrent), tostring(playing), tostring(v and v.pos), tostring(M and M.holding),
      tostring(okAu and Audio._bgmPaused), tostring(okAu and Audio.isBgmStopped and Audio.isBgmStopped()),
      tostring(okAu and Audio._currentSong and Audio._currentSong.id))
  end
  -- every game effect played (src/sfx.lua), with the regimen clock when there is one
  local Sfx = TR.session and TR.session.sfx
  if Sfx then
    local play0 = Sfx.play
    Sfx.play = function(id, opts)
      local h = play0(id, opts)
      noteSound(id)
      local sim = TR.session.sim
      log(("  sfx %s %s%s"):format(id, h and "played" or "MISSING", sim and (" at sim t %.2f %s"):format(sim.t or 0, sim.phase or "") or ""))
      return h
    end
  end
  -- the game's own effects played as stand-ins
  local th = X._test and X._test.trainingHost and X._test.trainingHost()
  if th and th.playSe then
    local se0 = th.playSe
    th.playSe = function(name, ...) noteSound(tostring(name)); return se0(name, ...) end
  end
  local function shot(name)
    log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING")
    log("  " .. musicState())
  end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  -- a finger down / up at app coordinates (ax, ay), on whichever screen PlayNav is showing
  local function touch(action, id, ax, ay)
    if SECOND then
      local k = X.state().pushK or 3
      local tab = X.state().tabHeight or 0
      return X._test.feedSecond(action, ax * k, (ay + tab) * k)
    end
    local x, y = win(ax, ay)
    if action == "down" then love.touchpressed(id, x, y, 0, 0, 1) else love.touchreleased(id, x, y, 0, 0, 1) end
  end
  local function tapAt(id, ax, ay)
    touch("down", id, ax, ay); U.wait(2)
    touch("up", id, ax, ay); U.wait(4)
  end
  local lead = s.party[1]
  local evs0 = Pokemon.evsOf(lead)
  log(("lead %s hp %d/%d evs hp %d atk %d"):format(Pokemon.displayName(lead), lead.hp, lead.maxHp, evs0.hp, evs0.atk))

  -- ------- START -> TRAINING
  U.tap(game, "start")
  U.wait(20)
  local StartMenu = require("src.ui.game3.start_menu")
  local idx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "play_nav" then idx = i end
  end
  log("start menu:", topId(), "PLAYNAV entry at", tostring(idx), "cursor", StartMenu.cursor)
  if idx then
    local moves = idx - (StartMenu.cursor or 1)
    for _ = 1, math.abs(moves) do U.tap(game, moves > 0 and "down" or "up"); U.wait(6) end
    U.tap(game, "a")
    U.wait(30)
    -- the PlayNav menu: its Super Training card
    for _, c in ipairs(X.menu and X.menu.app.cards() or {}) do
      if c.id == "training" then log("menu card training:", tostring(c.open())) end
    end
    U.wait(30)
  else
    U.tap(game, "b"); U.wait(10)
    log("open directly:", TR.open())
    U.wait(10)
  end
  local st = TR.state()
  log("after open: top", topId(), "mode", tostring(st.mode), "name", tostring(st.name), "shot", tostring(st.shot),
    "total", tostring(st.total), "surface", X.state().mode)
  shot("t01_core")
  -- the dock: the second party member lying down (resting), the others hopping
  do
    local other = Runtime.getSession().party[2]
    if other then
      TR.store.mon(TR.host.monKey(other)).resting = "idle"
      U.wait(20)
      shot("t01b_dock_resting")
      U.wait(15)
      shot("t01c_dock_hop")
      TR.store.mon(TR.host.monKey(other)).resting = false
    end
  end
  local okA, whyA = X.amie.open()
  log("amie while training:", tostring(okA), tostring(whyA))

  -- ------- a bag: HP Bag S, ten taps on the stand
  local core = Apps:get("training_core")
  local geo = core.geometry()
  TR.store.bags()[1] = "hp_s"
  log("attach:", TR.session.attachBag(1))
  -- a punch is taken only after the last one's animation: tap as a player would, and check
  -- that a tap in between is refused
  for i = 1, 10 do
    tapAt("bag" .. i, geo.BAG.x + geo.BAG.w / 2, geo.BAG.y + geo.BAG.h / 2)
    if i == 1 then
      local hitsBefore = TR.session.session.rec.bag and TR.session.session.rec.bag.hits
      tapAt("spam", geo.BAG.x + geo.BAG.w / 2, geo.BAG.y + geo.BAG.h / 2)
      local hitsAfter = TR.session.session.rec.bag and TR.session.session.rec.bag.hits
      log("spam tap during the animation: hits", tostring(hitsBefore), "->", tostring(hitsAfter))
    end
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < TR.session.HIT_LOCK + 0.05 do U.wait(1) end
  end
  U.wait(10)
  st = TR.state()
  local evs1 = Pokemon.evsOf(lead)
  log(("after 10 taps: bag %s hits %s evs hp %d (was %d) hp %d/%d total %d msg %s"):format(
    tostring(st.bag and st.bag.id), tostring(st.bag and st.bag.hits), evs1.hp, evs0.hp, lead.hp, lead.maxHp, st.total,
    tostring(st.message)))
  shot("t02_bag_done")
  -- the finishing move: each clip at a few frames, the glow, the bag's words, then the home
  -- screen with the stat's +N and the gauge arrow
  local fin = TR.session.session.anim.finish
  log("finish:", tostring(fin and fin.clip), "msg", tostring(TR.state().message))
  if fin then
    local function at(clip, f, name)
      fin.clip, fin.t = clip, f / 30
      U.wait(1)
      shot(name)
    end
    for _, c in ipairs({ "a", "b", "c" }) do
      for _, f in ipairs({ 4, 16, 24, 36, 56 }) do at(c, f, ("t02f_%s_%02d"):format(c, f)) end
    end
    at("a", 110, "t02g_glow")
    at("a", 175, "t02h_words")
    log("words:", tostring(TR.state().message))
    fin.t = 200 / 30
    U.wait(3)
    log("after the finish:", tostring(TR.state().finishing), "statUp", tostring(TR.state().statUp and TR.state().statUp.stat))
    shot("t02i_statup")
    TR.session.session.anim.statUp = nil   -- the next hit would clear it
  end
  -- the found bag's presentation (sand_bag_get): a forced find, shot at its key frames
  do
    TR.session.takeDownBag()
    local oldRng = TR.session.rng
    TR.session.rng = function() return 0.01 end
    TR.session.hitBag("tap")
    TR.session.rng = oldRng
    local gift = TR.session.session.anim.gift
    local _, why = TR.session.hitBag("tap")
    log("gift after the find:", gift and "on" or "OFF", "tap meanwhile:", tostring(why))
    if gift then
      local function at(f, name) gift.t = f / 30; U.wait(1); shot(name) end
      at(8, "t02j_gift_drop")
      at(30, "t02k_gift_hung")
      at(74, "t02l_gift_rise")
      gift.t = 104 / 30
      U.wait(3)   -- past WORDS_AT: the words and the dim come up
      shot("t02m_gift_words")
      log("gift words:", tostring(TR.state().message))
      gift.t = 200 / 30
      U.wait(3)
      log("after the gift:", tostring(TR.state().gift), "bags", TR.state().bags)
      TR.session.session.message, TR.session.session.messageUntil = nil, nil
    end
  end
  -- the rest of the probe punches in bulk: no finishing moves in between
  TR.session.FINISH_MOVE = false
  TR.session.GIFT_SHOW = false
  -- an L bag through the session for the radar
  TR.store.bags()[1] = "atk_l"
  TR.session.attachBag(1)
  -- one punch per animation in play; the probe punches in bulk
  local lock = TR.session.HIT_LOCK
  TR.session.HIT_LOCK = 0
  for _ = 1, 50 do TR.session.hitBag("tap") end
  TR.session.HIT_LOCK = lock
  U.wait(5)
  local evs2 = Pokemon.evsOf(lead)
  log(("after Attack L: atk %d hp %d/%d"):format(evs2.atk, lead.hp, lead.maxHp))
  shot("t03_radar")
  tapAt("bagsbtn", geo.BAGS.x + geo.BAGS.w / 2, geo.BAGS.y + geo.BAGS.h / 2)
  U.wait(5)
  TR.store.bags()[1] = "spe_m"
  TR.store.bags()[2] = "reset"
  TR.store.bags()[3] = "double_up"
  U.wait(3)
  log("bags mode:", TR.state().mode, "app", Apps:active().id, "bags", TR.state().bags)
  shot("t03b_bags")
  local bagsApp = Apps:get("training_bags")
  local bg = bagsApp.geometry()
  local s1 = bg.slotRect(1)
  tapAt("slot1", s1.x + s1.w / 2, s1.y + s1.h / 2)
  U.wait(5)
  log("box:", tostring(bagsApp.view() and bagsApp.view().index), "name", TR.session.bagName("spe_m"),
    "| desc", (TR.session.bagDescription("spe_m"):gsub("\n", " / ")), "| use", TR.session.uiText("use"))
  shot("t03c_bag_box")
  local b1 = bg.button(1, 3)
  tapAt("use", b1.x + b1.w / 2, b1.y + b1.h / 2)
  U.wait(5)
  log("question:", tostring(bagsApp.view() and bagsApp.view().question), "|", (TR.session.uiText("askUse", "spe_m"):gsub("\n", " / ")))
  shot("t03d_bag_ask")
  local yes = bg.button(1, 2)
  tapAt("yes", yes.x + yes.w / 2, yes.y + yes.h / 2)
  -- the drawer slides out, then the room
  waitFor(function() return TR.state().mode == "core" end, 600)
  log("after yes: mode", TR.state().mode, "stand", tostring(TR.state().bag and TR.state().bag.id), "bags", TR.state().bags)
  TR.session.enterBags()
  U.wait(3)
  local back = bagsApp.geometry().BACK
  tapAt("bagsback", back.x + back.w / 2, back.y + back.h / 2)
  waitFor(function() return TR.state().mode == "core" end, 600)
  -- black bag taps and the party strip
  local before = TR.state().bags
  for i = 1, 30 do tapAt("black" .. i, geo.BAG.x + geo.BAG.w / 2, geo.BAG.y + geo.BAG.h / 2) end
  log("black bag: bags", before, "->", TR.state().bags, "taps", TR.state().blackTaps)
  local slot = geo.partySlot(2)
  tapAt("party2", slot.x + slot.w / 2, slot.y + slot.h / 2)
  U.wait(5)
  log("switched to:", TR.state().name)
  shot("t04_switch")

  -- ------- a regimen: REGIMENS, pick Lv1 HP, play with the pad and the touch screen
  -- gen3-hd-sprites, when it is there: is it installed and on for battle pics (its tagged
  -- stand-ins are what PlayNav draws the full frame from)
  do
    local ex = loader and loader.exports and loader.exports["gen3-hd-sprites"]
    log("gen3-hd-sprites:", ex and "loaded" or "absent", ex and ("active " .. tostring(ex.isActive()) ..
      " battle " .. tostring(ex.enabled("battle")) .. " tagOf " .. tostring(ex.tagOf ~= nil)) or "")
    -- PROBE_FAKE_TAG=1: tag the lead's back pic with a 2x copy at scale 0.5 (draws the same, but
    -- through the tag path), to check that path when the sprite mod gave an untagged pic
    if os.getenv("PROBE_FAKE_TAG") == "1" and ex and ex.tag then
      local entry = TR.host.backPic(lead)
      if entry and entry.image then
        local iw, ih = entry.image:getDimensions()
        local big = love.graphics.newCanvas(iw * 2, ih * 2, { dpiscale = 1 })
        love.graphics.push("all")
        love.graphics.setCanvas(big)
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(entry.image, 0, 0, 0, 2, 2)
        love.graphics.pop()
        ex.tag(entry.image, { texture = big, quad = love.graphics.newQuad(0, 0, iw * 2, ih * 2, iw * 2, ih * 2), scale = 0.5 })
        log("fake tag: on the back pic, 2x copy at scale 0.5")
      end
    end
  end
  -- PROBE_NO_BOARD=1: no hover board under the trainee (the sprite on its own)
  if os.getenv("PROBE_NO_BOARD") == "1" and TR.session.arenaDraw then
    TR.session.arenaDraw.board = false
    log("board: off for this run")
  end
  tapAt("party1", geo.partySlot(1).x + 9, geo.partySlot(1).y + 12)
  U.wait(5)
  -- a record on Lv1 HP held by another party member: the picker shows it cleared, with the
  -- best time and its holder's icon, for the trainee too
  do
    local party = Runtime.getSession().party
    local other = party[2]
    if other and TR.store.records then
      TR.store.cleared().lv1_hp = true
      TR.store.records().lv1_hp = { best = 141.5, key = TR.host.monKey(other),
        species = TR.host.speciesOf and TR.host.speciesOf(other) or nil, name = "ZIGZAGOON" }
      log("seeded a record on lv1_hp held by", TR.host.monKey(other))
    end
  end
  tapAt("regimens", geo.REGIMENS.x + geo.REGIMENS.w / 2, geo.REGIMENS.y + geo.REGIMENS.h / 2)
  -- the change on the game's frames: the shutters, the black, the fade
  waitFor(function() local t = TR.session.session.trans; return t and t.t >= 7 + 12 end, 2000)
  shot("t05a_shutters")
  waitFor(function() return TR.state().mode == "courses" end, 2000)
  shot("t05a_black")
  waitFor(function() return TR.session.session.trans == nil end, 4000)
  U.wait(5)
  log("courses mode:", TR.state().mode, "app", Apps:active().id)
  do
    local A = X._test.assets()
    local tk = A and A.music("bgm/sp_menu")
    log(("picker track: %s Hz, %s channels, %.1f s"):format(tostring(tk and tk.rate), tostring(tk and tk.channels),
      tk and tk.samples / tk.rate or 0))
  end
  shot("t05_courses")
  local coursesApp = Apps:get("training_courses")
  local tile = coursesApp.geometry().slots[2]
  tapAt("tile", tile.x + tile.w / 2, tile.y + tile.h / 2)
  U.wait(5)
  shot("t05b_course_card")
  do
    local Stack = package.loaded["src.ui.game3.stack"]
    local top = Stack and Stack.top and Stack.top()
    log("top layer:", tostring(top and top.id), "drawScene", tostring(top and type(top.mod) == "table" and top.mod.drawScene ~= nil),
      "hdLive", tostring(top and type(top.mod) == "table" and top.mod.hdLive), "stackTop", tostring(Stack3.top and Stack3.top() and Stack3.top().id))
    log("hdTop why:", tostring(X.hdTop and X.hdTop.why), "last", tostring(X.hdTop and X.hdTop.last ~= nil))
  end
  U.wait(5)
  log("selected:", tostring(coursesApp.selected()))
  tapAt("tile2", tile.x + tile.w / 2, tile.y + tile.h / 2)
  -- the fade to black, then the regimen and its intro on the top screen
  waitUntil(function() local t = TR.session.session.trans; return t and t.to == "regimen" and t.t >= 12 end, 3)
  shot("t05c_fade_in")
  waitUntil(function() return TR.session.sim ~= nil end, 5)
  log("regimen mode:", TR.state().mode, "app", Apps:active().id, "phase", tostring(TR.session.sim and TR.session.sim.phase),
    "hud", tostring(TR.session.hud and TR.session.hud.P ~= nil), "countdown", tostring(TR.session.sim and TR.session.sim.countdown))
  local aim = Apps:get("training_aim")
  local sim = TR.session.sim
  -- the pumps: each one's peak (sound + 0.08 s) and its sag before the next (as the capture)
  for _, at in ipairs({ { 0.4, "t06a_intro_title" }, { 2.0, "t06a2_cam_close" }, { 3.13, "t06b_pump1_peak" }, { 3.6, "t06b_pump1_sag" },
    { 4.6, "t06b_pump3_peak" }, { 5.25, "t06b_pump3_sag" }, { 5.44, "t06b_pump4_peak" }, { 6.1, "t06b_pump4_sag" },
    { 6.27, "t06b_pump5_peak" }, { 7.0, "t06c2_intro_risen" },
    { 7.6, "t06d_intro_balloon" }, { 8.0, "t06d2_trainee_riding_in" }, { 8.6, "t06d3_sway" }, { 9.2, "t06e_intro_trainee" },
    { 10.0, "t06e2_sway_ending" }, { 11.0, "t06f_intro_start" } }) do
    waitUntil(function() return sim.t >= at[1] or sim.phase ~= "countdown" end, 15)
    shot(at[2])
  end
  waitUntil(function() return sim and sim.phase == "play" end, 15)
  -- PROBE_EXIT=1: the exit asks twice - one tap rings the button and stays, the ring runs out,
  -- then two taps leave
  if os.getenv("PROBE_EXIT") == "1" then
    local E = aim.geometry().EXIT
    local ex, ey = E.x + E.w / 2, E.y + E.h / 2
    tapAt("exit1", ex, ey)
    for _, at in ipairs({ { 0.1, "x01_ring_closing" }, { 0.5, "x02_ring_held" }, { 1.12, "x03_ring_spreading" } }) do
      waitUntil(function() local t = aim.exitRingT(); return t == nil or t >= at[1] end, 3)
      shot(at[2])
    end
    log("one tap: mode", TR.state().mode, "sim", tostring(TR.session.sim ~= nil))
    waitSecs(0.5)
    log("ring gone:", tostring(aim.exitRingT() == nil), "mode", TR.state().mode)
    tapAt("exit2", ex, ey)
    waitSecs(0.3)
    tapAt("exit3", ex, ey)
    waitSecs(1.0)
    log("two taps: mode", TR.state().mode, "sim", tostring(TR.session.sim ~= nil))
    shot("x04_left")
    return
  end
  log("play: phase", sim and sim.phase, "goals", sim and #sim.goals, "remaining", sim and sim.remaining)
  -- the player sprite as the arena has it, saved for a look (player_sprite.png)
  do
    local AD = TR.session.arenaDraw
    local img, px0, py0, pw, ph, pk
    if AD and AD.debugPlayerPic then img, px0, py0, pw, ph, pk = AD.debugPlayerPic(TR.session.session) end
    if img then
      -- the part drawn (an atlas page is far larger than its frame)
      local iw, ih = img:getDimensions()
      local cw, ch = math.ceil(pw or iw), math.ceil(ph or ih)
      local cv = love.graphics.newCanvas(cw, ch, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(cv)
      love.graphics.origin()
      love.graphics.clear(0.24, 0.24, 0.24, 1)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, love.graphics.newQuad(px0 or 0, py0 or 0, cw, ch, iw, ih), 0, 0)
      love.graphics.pop()
      local ok = pcall(function() cv:newImageData():encode("png", "probe_player_sprite.png") end)
      log(("player sprite image: %dx%d, drawn %sx%s from %s,%s at x%.3f; %s"):format(iw, ih, tostring(pw), tostring(ph),
        tostring(px0), tostring(py0), pk or 1, ok and "saved" or "not saved"))
    end
  end
  log("player sprite:", TR.session.arenaDraw and TR.session.arenaDraw.debugPlayer(TR.session.session),
    "backPic", tostring(TR.host.backPic(lead)), "frontPic", tostring(TR.host.frontPic(lead)),
    "player", sim.player.x, sim.player.z)
  do
    local e = TR.host.backPic(lead)
    local keys = {}
    for k, v in pairs(e or {}) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    log("backPic entry:", table.concat(keys, " "))
    local f = TR.host.frontPic(lead)
    keys = {}
    for k, v in pairs(f or {}) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    log("frontPic entry:", table.concat(keys, " "))
  end
  shot("t06_regimen_start")
  do
    local x0, z0 = sim.player.x, sim.player.z
    U.hold(game, "right", 40)
    local x1 = sim.player.x
    U.hold(game, "up", 40)
    local z1 = sim.player.z
    U.hold(game, "left", 80)
    log(("d-pad: x %.2f -> right %.2f -> left %.2f; z %.2f -> up %.2f"):format(x0, x1, sim.player.x, z0, z1))
  end
  -- aim at live goals through the pad for ~12 s of wall time; dodge and block meanwhile
  local t0 = love.timer.getTime()
  local shotsTaken = 0
  while love.timer.getTime() - t0 < 12 and sim.phase == "play" do
    local st = sim:state()
    local g = st.goals[1]
    if g then
      local px, py = aim.padPointFor(g.x, g.y)
      touch("down", "aim", px, py)
      waitSecs(0.15)
      touch("up", "aim", px, py)
      shotsTaken = shotsTaken + 1
    end
    if shotsTaken % 4 == 0 then U.hold(game, "left", 12) elseif shotsTaken % 4 == 2 then U.hold(game, "right", 12) end
    if shotsTaken % 5 == 0 then U.tap(game, "l") end
    waitSecs(0.5)
  end
  local st = sim:state()
  log(("after %d shots: score %d/%d hits %d misses %d playerHits %d blocked %d remaining %.1f phase %s energyShots %s"):format(
    shotsTaken, st.score, st.target, st.stats.hits, st.stats.misses, st.stats.playerHits, st.stats.blocked, st.remaining, st.phase,
    tostring(st.stats.energyShots)))
  shot("t07_regimen_play")
  -- the attacks: a lobbed ball (up, off screen with its red mark, coming down) and a big ball
  if sim.phase == "play" then
    sim.player.x, sim.player.y = 0.3, 0.2
    sim:launch({ kind = "lob" })
    local t0 = sim.t
    for _, at in ipairs({ { 0.5, "t07f_lob_up" }, { 1.2, "t07g_lob_off" }, { 1.95, "t07h_lob_down" } }) do
      waitUntil(function() return sim.t >= t0 + at[1] end, 5)
      shot(at[2])
    end
    sim:launch({ kind = "big" })
    local t1 = sim.t
    waitUntil(function() return sim.t >= t1 + 0.4 end, 5)
    shot("t07i_big_ball")
    waitUntil(function() return sim.t >= t1 + 0.75 end, 5)
    shot("t07j_big_ball_near")
  end
  if sim.phase == "play" then
    log("forceEnd:", TR.session.forceEnd({ clear = true, remaining = sim.remaining }))
  end
  -- the end: the balloon goes, Success!, the fade
  for _, at in ipairs({ { 1.0, "t07b_outro_wobble" }, { 2.0, "t07c0_outro_gusts" }, { 3.0, "t07c_outro_fly" },
    { 4.9, "t07c1_outro_burst" }, { 5.1, "t07c15_outro_burst2" }, { 5.3, "t07c2_outro_away" }, { 6.4, "t07d_outro_twinkle" },
    { 7.9, "t07e_outro_success" } }) do
    waitUntil(function() local o = TR.session.session.outro; return not o or o.t >= at[1] end, 12)
    shot(at[2])
  end
  waitUntil(function() return TR.state().mode == "result" end, 12)
  U.wait(5)
  local r = TR.session.session.result
  local evs2b = Pokemon.evsOf(lead)
  log(("result: clear %s ev +%s (%s) medal %s bag %s kept %s; hp ev now %d; cleared lv1_hp %s"):format(
    tostring(r and r.clear), tostring(r and r.ev), tostring(r and r.stat), tostring(r and r.medal), tostring(r and r.bag),
    tostring(r and r.bagKept), evs2b.hp, tostring(TR.store.cleared().lv1_hp)))
  -- the results' top screen as it plays: the rows slide in, the stat goes up, the gauge fills
  for _, at in ipairs({ { 0.1, "t08a0_result_start" }, { 0.45, "t08a1_rows_in" }, { 0.9, "t08a2_rows_done" },
    { 1.35, "t08a3_stat_up" }, { 1.9, "t08a4_gauge" }, { 2.8, "t08a5_gauge_more" } }) do
    waitUntil(function() local R0 = TR.session.results; return not R0 or (R0.t or 0) >= at[1] end, 6)
    shot(at[2])
  end
  log("result page at shot:", TR.session.results and TR.session.results.page, "t", TR.session.results and TR.session.results.t)
  shot("t08_result")
  log("result words:", tostring(r and r.praise), "|", tostring(r and r.statText), "| unlocked", r and #r.unlocked)
  -- the coach's lines, a tap each (the first goes on its own)
  local Rs = TR.session.results
  log("result pages:", Rs and Rs.list and #Rs.list or 0)
  waitSecs(1.6)
  local aimApp = Apps:get("training_aim")
  local seen = {}
  local pointer0 = aimApp.pointer
  aimApp.pointer = function(self, ev, rec)
    seen[#seen + 1] = ("%s@%.0f,%.0f"):format(tostring(ev.phase), ev.x or -1, ev.y or -1)
    return pointer0(self, ev, rec)
  end
  for i = 1, 8 do
    if TR.state().mode ~= "result" or (Rs and Rs.done) then break end
    shot(("t08p%d_result_page"):format(i))
    tapAt("next", 128, 90)
    waitSecs(0.3)
    shot(("t08p%d_result_page_turn"):format(i))
    waitSecs(0.6)
    log(("  tap %d: page %s/%s active %s events %s"):format(i, tostring(Rs and Rs.page), tostring(Rs and Rs.list and #Rs.list),
      tostring(Apps:active() and Apps:active().id), table.concat(seen, " ")))
    seen = {}
  end
  aimApp.pointer = pointer0
  waitUntil(function() return TR.state().mode == "courses" and TR.session.session.trans == nil end, 6)
  log("after result:", TR.state().mode)
  -- the picker with the secret column: force Fully Trained and all regular courses cleared
  TR.session.session.rec.fully = true
  for _, c in ipairs(TR.session.courseList()) do if not c.secret then TR.store.cleared()[c.id] = true end end
  Apps:get("training_courses").select("secret_02")
  U.wait(5)
  log("course names:", TR.session.courseName("lv1_hp"), "|", TR.session.courseName("secret_02"), "| blurb:", TR.session.courseBlurb("secret_02"))
  shot("t08b_courses_secret")
  TR.session.session.rec.fully = nil
  for _, c in ipairs(TR.session.courseList()) do if not c.secret and c.id ~= "lv1_hp" then TR.store.cleared()[c.id] = nil end end
  local ret = coursesApp.geometry().RETURN
  tapAt("back", ret.x + ret.w / 2, ret.y + ret.h / 2)
  waitFor(function() local t = TR.session.session.trans; return t and t.t >= 12 end, 2000)
  shot("t08c_back_shutters")
  waitFor(function() return TR.session.session.trans == nil end, 4000)
  log("back to:", TR.state().mode)

  -- ------- the Wings through the engine
  local ItemsData = require("src.core.game3.items_data")
  local Bag = require("src.core.game3.bag")
  local info = ItemsData.info(400)
  log("item 400:", tostring(info and info.name), "price", tostring(info and info.price), "fieldUse", tostring(info and info.fieldUse),
    "pocket", tostring(info and info.pocket), "byName", tostring(ItemsData.toNumericId("HEALTH_WING")))
  log("give wings:", TR.items.give(400, 2), "pretty:", TR.items.give(406, 1), "has 400:", Bag.has(s.bag, 400, 1))
  log("dusk stone resolves to", tostring(TR.items.index("dusk-stone")), "(own 407; national_dex_gen3 902 when present)",
    "ST_DUSK_STONE", tostring(ItemsData.toNumericId("ST_DUSK_STONE")), "DUSK_STONE", tostring(ItemsData.toNumericId("DUSK_STONE")))
  log("bag icon draws wrapped (FRLG + RSE skins):", TR.items.wrapBagIcons())
  local ItemUse = require("src.core.game3.item_use")
  local okU, kind, text = ItemUse.useField(s, s.bag, 400, 1)
  local evs3 = Pokemon.evsOf(lead)
  log(("use wing on slot 1: %s %s %s; hp ev %d -> %d; has 400 x1: %s"):format(tostring(okU), tostring(kind), tostring(text),
    evs2.hp, evs3.hp, tostring(Bag.has(s.bag, 400, 1))))
  -- close training, open the bag from the START menu for a look at the icon
  TR.session.finish()
  U.wait(10)
  log("closed: top", tostring(topId()), "surface", X.state().mode)
  U.tap(game, "start")
  U.wait(20)
  local bagIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "bag" then bagIdx = i end end
  log("bag entry at", tostring(bagIdx))
  if bagIdx then
    local moves = bagIdx - (StartMenu.cursor or 1)
    for _ = 1, math.abs(moves) do U.tap(game, moves > 0 and "down" or "up"); U.wait(6) end
    U.tap(game, "a")
    U.wait(40)
    log("bag open: top", tostring(topId()))
    -- the cursor on the first Wing in the ITEMS pocket (its icon beside the bag)
    U.wait(6)
    shot("t09_bag_wings")
    U.tap(game, "b"); U.wait(15); U.tap(game, "b"); U.wait(10)
  end
  if X and X.haptics and X.haptics.log then
    local n = {}
    for _, k in ipairs(X.haptics.log) do n[k] = (n[k] or 0) + 1 end
    log(("haptics felt: tick %d light %d medium %d strong %d (%d pulses)"):format(n.tick or 0, n.light or 0,
      n.medium or 0, n.strong or 0, #X.haptics.log))
  end
  log("done: top", tostring(topId()))
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
