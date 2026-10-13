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
  local function waitSecs(secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do U.wait(1) end
  end
  -- wait on the wall clock (the session runs on it) for pred, at most secs
  local function waitUntil(pred, secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do
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
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
  end
  U.wait(60)
  local loader = game.mods
  local MOD_ID = "play_nav"
  local X = loader and loader.exports and loader.exports[MOD_ID]
  if not X then log("FAIL no exports"); return end
  local TR = X.training
  if not TR then log("FAIL training not exported"); return end
  local Apps = X.apps
  loader.modOptions[MOD_ID] = loader.modOptions[MOD_ID] or {}
  loader.modOptions[MOD_ID].display = "split"
  loader.modOptions[MOD_ID].prompt_always = false
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  -- the music at each shot: our track, whether it sounds, and the field's music held or not
  local okAu, Audio = pcall(require, "src.core.game3.audio")
  local function musicState()
    local M = TR.session and TR.session.music
    local v = M and M.voice
    local playing = v and v.src and v.src:isPlaying()
    return ("music %s playing %s pos %s held %s | field paused %s stopped %s song %s"):format(
      tostring(M and M.current), tostring(playing), tostring(v and v.pos), tostring(M and M.holding),
      tostring(okAu and Audio._bgmPaused), tostring(okAu and Audio.isBgmStopped and Audio.isBgmStopped()),
      tostring(okAu and Audio._currentSong and Audio._currentSong.id))
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
  local function tapAt(id, ax, ay)
    local x, y = win(ax, ay)
    love.touchpressed(id, x, y, 0, 0, 1); U.wait(2)
    love.touchreleased(id, x, y, 0, 0, 1); U.wait(4)
  end
  local lead = s.party[1]
  local evs0 = Pokemon.evsOf(lead)
  log(("lead %s hp %d/%d evs hp %d atk %d"):format(Pokemon.displayName(lead), lead.hp, lead.maxHp, evs0.hp, evs0.atk))

  -- ------- START -> TRAINING
  U.tap(game, "start")
  U.wait(20)
  local StartMenu = require("src.ui.game3.start_menu")
  local idx, amieIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "play_nav_training" then idx = i end
    if e.id == "play_nav_amie" then amieIdx = i end
  end
  log("start menu:", topId(), "TRAINING entry at", tostring(idx), "AMIE at", tostring(amieIdx), "cursor", StartMenu.cursor)
  if idx then
    local moves = idx - (StartMenu.cursor or 1)
    for _ = 1, math.abs(moves) do U.tap(game, moves > 0 and "down" or "up"); U.wait(6) end
    U.tap(game, "a")
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
  -- the rest of the probe punches in bulk: no finishing moves in between
  TR.session.FINISH_MOVE = false
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
  tapAt("party1", geo.partySlot(1).x + 9, geo.partySlot(1).y + 12)
  U.wait(5)
  tapAt("regimens", geo.REGIMENS.x + geo.REGIMENS.w / 2, geo.REGIMENS.y + geo.REGIMENS.h / 2)
  -- the change on the game's frames: the shutters, the black, the fade
  waitFor(function() local t = TR.session.session.trans; return t and t.t >= 7 + 12 end, 2000)
  shot("t05a_shutters")
  waitFor(function() return TR.state().mode == "courses" end, 2000)
  shot("t05a_black")
  waitFor(function() return TR.session.session.trans == nil end, 4000)
  U.wait(5)
  log("courses mode:", TR.state().mode, "app", Apps:active().id)
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
  for _, at in ipairs({ { 0.4, "t06a_intro_title" }, { 3.1, "t06b_intro_pump" }, { 4.2, "t06c_intro_pump2" }, { 5.3, "t06c2_intro_rise" },
    { 7.6, "t06d_intro_balloon" }, { 9.2, "t06e_intro_trainee" }, { 11.0, "t06f_intro_start" } }) do
    waitUntil(function() return sim.t >= at[1] or sim.phase ~= "countdown" end, 15)
    shot(at[2])
  end
  waitUntil(function() return sim and sim.phase == "play" end, 15)
  log("play: phase", sim and sim.phase, "goals", sim and #sim.goals, "remaining", sim and sim.remaining)
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
      local x, y = win(px, py)
      love.touchpressed("aim", x, y, 0, 0, 1)
      waitSecs(0.15)
      love.touchreleased("aim", x, y, 0, 0, 1)
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
  for _, at in ipairs({ { 1.0, "t07b_outro_wobble" }, { 3.0, "t07c_outro_fly" }, { 5.3, "t07c2_outro_away" }, { 6.4, "t07d_outro_twinkle" },
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
  waitSecs(1.4)
  log("result page at shot:", TR.session.results and TR.session.results.page, "t", TR.session.results and TR.session.results.t)
  shot("t08_result")
  log("result words:", tostring(r and r.praise), "|", tostring(r and r.statText), "| unlocked", r and #r.unlocked)
  -- the coach's lines, a tap each (the first goes on its own)
  local Rs = TR.session.results
  log("result pages:", Rs and Rs.list and #Rs.list or 0)
  waitSecs(1.6)
  for i = 1, 8 do
    if TR.state().mode ~= "result" or (Rs and Rs.done) then break end
    shot(("t08p%d_result_page"):format(i))
    tapAt("next", 128, 90)
    waitSecs(0.9)
  end
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
  local okBC, BagChrome = pcall(require, "src.ui.game3.rse.bag_chrome")
  log("rse icon hook:", okBC and type(BagChrome.modIcon(400)) or "no chrome")
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
    -- the Wings are the last items of the ITEMS pocket: move the cursor down a few
    for _ = 1, 4 do U.tap(game, "down"); U.wait(6) end
    shot("t09_bag_wings")
    U.tap(game, "b"); U.wait(15); U.tap(game, "b"); U.wait(10)
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
