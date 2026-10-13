-- Super Training end to end against a fake Gen 3 host: open from the menu, the layer and
-- the core app, bag hits raising EVs with the HP delta, the black bag, the wall clock's
-- automatic punches (open and in the background), the idle and routine rests and what
-- waking gives, Reset and Soothing bags, the inventory cap, the Fully Trained flag, the
-- Wing items through the item.use hook, the mutual lock with Amie, and the save record.
-- Run from the engine root: luajit mods/play_nav/tests/training_flow_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local run = T.sdk.loadMod("mods/play_nav", { generation = 3, data = T.sdk.gen3Data and T.sdk.gen3Data() or nil })
T.eq(#run.errors, 0, "the mod loads clean on gen 3 (" .. tostring(run.errors[1]) .. ")")

local X = run.loader.exports.play_nav
local TR = X.training
T.check(type(TR) == "table" and type(TR.open) == "function", "training is exported")
local S, Rules, Store, Items = TR.session, TR.rules, TR.store, TR.items
local Apps = X.apps

-- ------- a fake host

local party = {
  { personality = 1234, otId = 77, species = 25, hp = 20, maxHp = 35, level = 12, friendship = 70,
    evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }, pokerus = 0 },
  { personality = 5, otId = 77, species = 7, hp = 0, maxHp = 30, level = 9, friendship = 70,
    evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }, pokerus = 0 },
  { personality = 9, otId = 77, species = 4, hp = 15, maxHp = 22, level = 8, friendship = 70,
    evs = { hp = 100, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }, pokerus = 0 },
}
local stack, sounds, cries, bag = {}, {}, {}, {}
local setEvsCalls = {}
-- the wall clock is the test's to move
local clock = { wall = 1000000 }
local fake = {
  name = "fake", available = function() return true end,
  now = function() return os.clock() end, wallClock = function() return clock.wall end,
  party = function() return party end,
  monKey = function(m) return m.personality .. ":" .. m.otId end,
  resolve = function(m) for _, p in ipairs(party) do if p.personality == m.personality then return p end end return m end,
  isEgg = function() return false end,
  isFainted = function(m) return (m.hp or 0) <= 0 end,
  speciesOf = function(m) return m.species end,
  national = function(m) return m.species end,
  displayName = function(m) return "SPECIES" .. m.species end,
  level = function(m) return m.level end,
  frontPic = function() return nil end,
  icon = function() return nil end,
  typesOf = function() return { 13 } end,
  evsOf = function(m) local o = {}; for k, v in pairs(m.evs) do o[k] = v end; return o end,
  setEvs = function(m, evs)
    for k, v in pairs(evs) do m.evs[k] = v end
    -- a stand-in for applyStats: 1 max HP per 4 HP EVs, current HP follows
    local oldMax = m.maxHp
    m.maxHp = 35 + math.floor(m.evs.hp / 4)
    m.hp = math.max(1, math.min(m.maxHp, m.hp + (m.maxHp - oldMax)))
    setEvsCalls[#setEvsCalls + 1] = { key = m.personality, hp = m.evs.hp }
    return true
  end,
  baseStats = function() return { hp = 35, atk = 55, def = 40, spe = 90, spa = 50, spd = 50 } end,
  friendshipOf = function(m) return m.friendship end,
  addFriendship = function(m, n) m.friendship = math.min(255, m.friendship + n); return m.friendship end,
  vitaminFriendship = function(m) m.friendship = m.friendship + 5 end,
  hasPokerus = function(m) return m.pokerus ~= 0 end,
  playCry = function(m) cries[#cries + 1] = m.species end,
  playSe = function(name) sounds[#sounds + 1] = name end,
  pushLayer = function(module) stack[#stack + 1] = module; return true end,
  popLayer = function() stack[#stack] = nil; return true end,
  layerOpen = function() return #stack > 0 end,
  session = function() return { party = party, bag = bag } end,
  canGiveItem = function() return #bag < 3 end,
  giveItem = function(id, qty) bag[#bag + 1] = { id, qty }; return true end,
  removeItem = function(id, qty) for i, e in ipairs(bag) do if e[1] == id then table.remove(bag, i); return true end end return false end,
}
X._test.setTrainingHost(fake)
X._test.setRefreshHost({ party = fake.party, monKey = fake.monKey, resolve = fake.resolve, isEgg = fake.isEgg,
  speciesOf = fake.speciesOf, displayName = fake.displayName, frontPic = fake.frontPic, icon = fake.icon,
  statusOf = function() return nil end, pushLayer = fake.pushLayer, popLayer = fake.popLayer,
  playSe = fake.playSe, playCry = fake.playCry, available = fake.available, now = fake.now,
  leadMon = function() return party[1] end, national = fake.national, typesOf = fake.typesOf })

local function rngOf(v) return function() return v end end
S.rng = rngOf(0.99)   -- no black-bag luck unless asked
-- routine rests only where a section asks for one (it sets bagsToRest itself)
local N = Rules.N
local restBags = N.CORE.ROUTINE_REST_BAGS
N.CORE.ROUTINE_REST_BAGS = { 100000, 100000 }

-- ------- the items registered with the engine

do
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  local okI, info = false, nil
  if ok and ItemsData and ItemsData.info then okI, info = pcall(ItemsData.info, 400) end
  if okI and type(info) == "table" then
    T.eq(info and info.name, "Health Wing", "item 400 is the Health Wing")
    T.eq(info and info.price, 3000, "...priced 3000")
    T.eq(info and info.fieldUse, "vitamin", "...used like a vitamin")
    T.eq(ItemsData.info(409) and ItemsData.info(409).name, "Dawn Stone", "item 409 is the Dawn Stone")
    T.eq(ItemsData.toNumericId and ItemsData.toNumericId("HEALTH_WING"), 400, "the name resolves after the registry write")
  else
    T.check(true, "the item pack is not in the headless cache; the engine checks run in the driver")
  end
  T.eq(Items.index("swift-wing"), 405, "slug -> index")
  T.check(Items.isTrainingItem(406) and not Items.isTrainingItem(63), "training items are known by id")
end

-- ------- open

T.eq(S.session, nil, "no session at the start")
T.check(TR.open(), "opens on the first healthy party member")
T.eq(#stack, 0, "no top-screen layer: the overworld stays live, as in the game")
T.check(Apps:get("training_core").fieldPlay, "...and the engine's pad stays for walking")
T.check(S.enterCourses(), "the regimen picker")
T.eq(#stack, 1, "...brings up the top-screen layer (its course card)")
T.check(S.enterCore(), "back to the room")
T.eq(#stack, 0, "...takes it down again")

-- ------- the screen change to the picker and back, on the game's frames
do
  local X = S.TRANS
  local function frames(n) for _ = 1, n do S.tick(1 / 30) end end
  T.check(S.goTo("courses"), "REGIMENS starts the change")
  T.check(not S.goTo("courses"), "...one at a time")
  T.eq(S.transView("bottom"), nil, "the button's bounce first")
  frames(X.WAIT + 5)
  local v = S.transView("bottom")
  T.check(v and v.shutter == "close", "then the shutters close over the home screen")
  T.eq(S.state().mode, "core", "...still the home screen")
  T.eq(#stack, 0, "...the overworld still on top")
  frames(X.SWITCH - X.WAIT - 5)
  T.eq(S.state().mode, "courses", "at SWITCH the picker takes over")
  T.eq(#stack, 1, "...with its top-screen layer")
  T.eq(S.transView("top").black, 1, "both screens black")
  T.eq(S.transView("bottom").black, 1, "...the touch screen too")
  frames(X.HOLD - X.SWITCH + 3)
  local b = S.transView("top").black
  T.check(b > 0 and b < 1, "fading in (" .. tostring(b) .. ")")
  frames(X.FADE)
  T.check(not S.transitioning(), "the change is over")
  T.check(S.goTo("core"), "back from the picker")
  frames(5)
  T.eq(S.transView("bottom").shutter, "close", "its shutters close")
  frames(X.CLOSE)
  T.eq(S.state().mode, "core", "the home screen is back")
  T.eq(#stack, 0, "...the overworld on top again")
  T.eq(S.transView("bottom").shutter, "open", "...and its shutters open")
  frames(X.OPEN + 1)
  T.check(not S.transitioning(), "done")
end
do
  -- with no layer up, the mod's frame tick drives the session
  local t0 = S.session.anim.t
  S.frame(0.5)
  T.eq(S.session.anim.t, t0 + 0.5, "the frame tick runs the session")
end
T.eq(Apps:active().id, "training_core", "the core app owns the surface")
T.check(X._test.surfaceWanted(), "the surface is wanted")
T.eq(S.state().mode, "core", "mode core")
T.eq(S.state().name, "SPECIES25", "the lead trains")
T.eq(S.state().shot, "yellow", "Pikachu's Energy Shot is yellow")
T.eq(S.state().total, 0, "no EVs yet")
local okA, whyA = X.amie.open()
T.check(not okA and whyA == "busy", "Amie refuses while training is open (" .. tostring(whyA) .. ")")
T.eq(S.state().bag, nil, "no bag on the stand")
do
  local ok, why = TR.open()
  T.check(not ok and why == "open", "a second open is refused")
end

-- ------- one punch at a time: the hit animation finishes before the next is taken

do
  local tapsBefore = S.state().blackTaps
  T.check(S.hitBag("tap"), "a punch lands")
  local ok, why = S.hitBag("tap")
  T.check(not ok and why == "busy", "a second tap during the animation is refused (" .. tostring(why) .. ")")
  T.eq(S.state().blackTaps, tapsBefore + 1, "...and not counted")
  S.tick(S.HIT_LOCK * 0.5)
  T.check(not S.hitBag("tap"), "still refused halfway through")
  S.tick(S.HIT_LOCK * 0.5 + 0.01)
  T.check(S.hitBag("tap"), "taken once the animation has finished")
  S.tick(S.HIT_LOCK + 0.01)
end

-- the rest of the suite punches in tight loops: no wait between punches, and no finishing
-- move after a cleared bag (its own test below turns it back on)
S.HIT_LOCK = 0
S.FINISH_MOVE = false
S.REGIMEN_SHOW = false

-- ------- the black bag

do
  local meta = Store.meta()
  local tapsBefore = S.state().blackTaps
  T.check(S.hitBag("tap"), "a tap with no bag hits the black bag")
  T.eq(S.state().blackTaps, tapsBefore + 1, "...counted")
  -- the game's roll: a find at 5% a tap, then one of its 26 bags
  S.rng = rngOf(0.5)
  for _ = 1, 20 do S.hitBag("tap") end
  T.eq(S.state().bags, 0, "unlucky taps: nothing")
  T.eq(S.state().blackTaps, tapsBefore + 21, "...each counted")
  S.rng = rngOf(0.01)
  S.hitBag("tap")
  T.eq(S.state().bags, 1, "a tap under 5% digs up a bag")
  T.eq(Store.bags()[1], "hp_s", "...the first of the 26 at that roll")
  T.eq(S.state().blackTaps, 0, "...and the count starts over")
  S.rng = rngOf(0.99)
  S.session.rec.secondWind = nil
end

-- ------- a stat bag: ten hits, +1 HP EV, HP moved with max HP

do
  local bags = Store.bags()
  bags[1] = "hp_s"
  T.check(S.attachBag(1), "HP Bag S goes on the stand")
  T.eq(S.state().bags, 0, "...out of the inventory")
  T.eq(S.state().bag.needed, 10, "ten hits needed")
  for i = 1, 9 do S.hitBag("tap") end
  T.eq(S.state().bag.hits, 9, "nine hits in")
  T.eq(party[1].evs.hp, 0, "no EV yet")
  S.hitBag("tap")
  T.eq(S.state().bag, nil, "the bag burst")
  T.eq(party[1].evs.hp, 1, "+1 HP EV")
  T.eq(S.state().total, 1, "the session's EVs follow")
  T.eq(#setEvsCalls, 1, "the host wrote the stats once")
  -- an L bag: +12
  bags[1] = "hp_l"
  T.check(S.attachBag(1), "HP Bag L")
  T.eq(S.state().bag.needed, 50, "fifty hits")
  for i = 1, 50 do S.hitBag("tap") end
  T.eq(party[1].evs.hp, 13, "+12 more")
  T.eq(party[1].maxHp, 38, "max HP rose by 3")
  T.eq(party[1].hp, 23, "...and current HP with it")
end

-- ------- the party rebuilt while Core Training is open (a battle's write-back): the bag's EVs
-- go to the party's own record, not the copy the session opened on

do
  local old = party[1]
  local copy = {}
  for k, v in pairs(old) do copy[k] = v end
  copy.evs = {}
  for k, v in pairs(old.evs) do copy.evs[k] = v end
  party[1] = copy
  local before = copy.evs.def
  local bags = Store.bags()
  bags[1] = "def_s"
  T.check(S.attachBag(1), "Defense Bag S on the stand")
  for _ = 1, S.state().bag.needed do S.hitBag("tap") end
  T.eq(copy.evs.def, before + 1, "the party's current record got the Defense EV")
  T.eq(old.evs.def, before, "...not the stale copy")
  T.check(S.session.mon == copy, "the session follows the party's record")
end

-- ------- a cleared bag's finishing move: the clip with its line, the glow, the bag's words
-- at frame 170, the home screen at 200 with the stat's +N for 120 more

do
  S.FINISH_MOVE = true
  local rec = S.session.rec
  local toRest = rec.bagsToRest
  rec.bagsToRest = 99
  local bags = Store.bags()
  bags[1] = "def_s"
  T.check(S.attachBag(1), "Defense Bag S on the stand")
  S.session.rec.bag.hits = S.session.rec.bag.needed - 1
  local def0 = party[1].evs.def
  T.check(S.hitBag("tap"), "the last punch lands")
  local st = S.state()
  T.check(st.finishing, "the finishing move starts")
  T.eq(party[1].evs.def, def0 + 1, "the EV is in at once")
  T.check(S.session.anim.finish.clip == "a" or S.session.anim.finish.clip == "b" or S.session.anim.finish.clip == "c",
    "one of the game's three clips")
  T.check(st.message ~= nil, "its line is up (" .. tostring(st.message) .. ")")
  local first = st.message
  local ok, why = S.hitBag("tap")
  T.check(not ok and why == "busy", "taps wait for it (" .. tostring(why) .. ")")
  local function frames(n) for _ = 1, n do S.tick(1 / 30) end end
  frames(100)
  T.eq(S.state().message, first, "...still its line during the glow")
  frames(72)
  T.check(S.state().message ~= first and S.state().message ~= nil, "the bag's words at frame 170 (" .. tostring(S.state().message) .. ")")
  T.check(S.state().finishing, "...still finishing")
  frames(30)
  st = S.state()
  T.check(not st.finishing, "home again at frame 200")
  T.eq(st.message, nil, "...the words cleared")
  T.check(st.statUp and st.statUp.stat == "def" and st.statUp.added == 1, "Defense's +1 on the meter")
  frames(121)
  T.check(S.state().statUp ~= nil, "the +1 stays until the next hit")
  T.check(S.hitBag("tap"), "taps are taken again")
  T.eq(S.state().statUp, nil, "...and the next tap clears the +1")
  rec.bagsToRest = toRest
  S.FINISH_MOVE = false
end

-- ------- the coach's cheer: a line from the bag's group at once, 300 frames shown, 300
-- hidden, a new one; the countdown stands still while a punch plays

do
  local rec = S.session.rec
  local bags = Store.bags()
  local function frames(n) for _ = 1, n do S.tick(1 / 30) end end
  frames(15)   -- the last test's punch has played out
  bags[1] = "def_m"
  T.check(S.attachBag(1), "Defense Bag M on the stand")
  frames(1)
  local line = S.state().cheerLine
  T.check(line ~= nil and line >= 51 and line <= 53, "a Defense cheer at once (line " .. tostring(line) .. ", 51-53)")
  T.check(S.state().cheer ~= nil, "...in the message window")
  frames(298)
  T.check(S.state().cheer ~= nil, "still up at frame 299")
  frames(2)
  T.eq(S.state().cheer, nil, "hidden after 300 frames")
  frames(150)
  -- a punch: the countdown waits while it plays (0.25 s = 7.5 frames)
  S.hitBag("tap")
  frames(150)
  T.eq(S.state().cheer, nil, "...the punch held the countdown back")
  frames(10)
  local nxt = S.state().cheerLine
  T.check(nxt ~= nil and nxt >= 51 and nxt <= 53, "the next Defense cheer (line " .. tostring(nxt) .. ")")
  -- the bag comes off: no cheer
  rec.bag = nil
  frames(1)
  T.eq(S.state().cheer, nil, "no bag, no cheer")
  T.eq(N.CORE.CHEER.GROUP.spa, 1, "Sp. Atk bags cheer with Attack's lines (the game's table)")
  T.eq(Rules.cheerGroup("soothing"), 7, "Soothing: lines 66-68")
end

-- ------- the wall clock: a punch a minute, the rest after a rolled 30 to 60 minutes awake

local function hits() return S.state().bag and S.state().bag.hits end

do
  local bags = Store.bags()
  bags[1] = "atk_m"
  S.attachBag(1)
  S.hitBag("auto")
  T.eq(hits(), 1, "an automatic hit counts")
  local t0 = clock.wall
  local rec = S.session.rec
  rec.awakeAt, rec.restAfter = t0, nil
  rec.nextAutoAt = t0 + N.CORE.AUTO_HIT_S
  S.rng = rngOf(0)
  clock.wall = t0 + 59; S.tick(0.016)
  T.eq(hits(), 1, "no punch before a minute")
  T.eq(rec.restAfter, N.CORE.REST_AFTER_S[1], "the awake stretch was rolled: 30 minutes here")
  S.rng = rngOf(0.99)
  clock.wall = t0 + 60; S.tick(0.016)
  T.eq(hits(), 2, "a punch once a minute on its own")
  clock.wall = t0 + 150; S.tick(0.016)
  T.eq(hits(), 3, "one more at two minutes")
  S.touch()
  clock.wall = t0 + 20 * 60 + 5; S.tick(0.016)
  T.check(not S.state().resting, "twenty minutes in: still up")
  T.eq(hits(), 21, "...a punch every minute (twenty by now, after the first by hand)")
  clock.wall = t0 + 30 * 60 + 1; S.tick(0.016)
  T.eq(S.state().resting, "idle", "thirty minutes awake: it lies down, touched or not")
  local before = hits()
  local ok, why = S.hitBag("auto")
  T.check(not ok and why == "resting", "no automatic hits while resting")
  clock.wall = clock.wall + 3600; S.tick(0.016)
  T.eq(hits(), before, "it stays down, however long")
  T.check(S.wake(), "a tap wakes it")
  T.check(S.state().secondWind and S.state().refreshed, "waking gives a second wind (the smile)")
  T.check(S.state().restAfter ~= nil and S.state().awakeAt == clock.wall, "...and a new awake stretch")
  -- double strength: each punch counts two until this bag is done (the M bag on the stand
  -- was cleared by the automatic punches before the rest)
  T.eq(S.state().bag, nil, "the automatic punches cleared the M bag along the way")
  bags[1] = "atk_m"
  S.attachBag(1)
  for _ = 1, 12 do S.hitBag("tap") end
  T.eq(hits(), 24, "twelve double-strength taps: 24 of 25")
  S.hitBag("tap")
  T.eq(S.state().bag, nil, "the 25-hit bag in 13 taps")
  T.check(not S.state().secondWind, "the second wind is spent with that bag")
end

-- ------- the second wind lasts one regimen too, and comes from rare finds and Team Flare

do
  S.session.rec.secondWind = true
  local course = S.courseList and S.courseList()[1]
  if course and S.startCourse then
    local ok = S.startCourse(course.id)
    T.check(ok, "a regimen starts")
    T.check(S.sim and S.sim.mods and S.sim.mods.secondWind, "...with the second wind's double points")
    T.check(not S.session.rec.secondWind, "...which it spends")
    S.quitRegimen()
  else
    T.check(true, "no regimen in this build")
  end
  -- a rare find from the blank bag
  local meta = Store.meta()
  local saved = S.session.rec.bag
  S.session.rec.bag = nil
  S.rng = rngOf(0.045)   -- under 5%, and slot 2 of 26: HP Bag M, a rare find
  S.hitBag("tap")
  S.rng = rngOf(0.99)
  local found = Store.bags()[#Store.bags()]
  T.check(Rules.isRareBag(found), "a rare bag turned up (" .. tostring(found) .. ")")
  T.check(S.state().secondWind, "...and a rare find brings a second wind")
  S.session.rec.secondWind = nil
  S.session.rec.bag = saved
end

-- ------- the routine rest: after a rolled 3 to 5 bags, whichever comes first

do
  S.session.rec.bag = nil
  S.session.rec.bagsToRest = 1
  local bags = Store.bags()
  bags[1] = "hp_s"
  S.attachBag(1)
  T.eq(S.state().bag.needed, 10, "a bag needs its full hits; the second wind is in the punch")
  for _ = 1, 10 do S.hitBag("tap") end
  T.eq(S.state().resting, "routine", "a cleared bag on the count: a routine rest")
  bags[1] = "atk_m"
  local ok, why = S.attachBag(1)
  T.check(not ok and why == "resting", "no bag can be set while it rests")
  T.check(S.wake(), "a tap wakes it")
  T.check(S.state().secondWind, "a second wind after this rest too")
  local atk = party[1].evs.atk
  S.attachBag(1)
  for _ = 1, 13 do S.hitBag("tap") end
  T.eq(party[1].evs.atk, atk + 4, "the M bag in 13 double-strength taps: +4 Attack")
  T.check(not S.state().secondWind, "spent")
  -- a cleared bag can bring the next second wind
  S.rng = rngOf(0)
  bags[1] = "hp_s"
  S.attachBag(1)
  for _ = 1, 10 do S.hitBag("tap") end
  T.check(S.state().secondWind, "a cleared bag brought a second wind (the odds rolled low)")
  S.session.rec.secondWind = nil
  -- the count is rolled from the rule: 3 to 5 bags
  N.CORE.ROUTINE_REST_BAGS = restBags
  S.session.rec.bagsToRest = nil
  bags[1] = "hp_s"
  S.attachBag(1)
  for _ = 1, 10 do S.hitBag("tap") end
  T.eq(S.session.rec.bagsToRest, 2, "the next rest rolled 3 bags out (one cleared)")
  S.rng = rngOf(0.99)
  S.session.rec.secondWind = nil
  N.CORE.ROUTINE_REST_BAGS = { 100000, 100000 }
  S.session.rec.bagsToRest = nil
end

-- ------- a fainted Pokemon stays down

do
  local hp = party[1].hp
  S.lieDown("routine")
  party[1].hp = 0
  local ok, why = S.wake()
  T.check(not ok and why == "fainted", "a fainted Pokemon cannot be woken (" .. tostring(why) .. ")")
  T.check(S.state().fainted, "...and shows as fainted")
  party[1].hp = hp
  T.check(S.wake(), "revived, it wakes")
end

-- ------- the bag box: names, descriptions, the questions (fallback text headless)

do
  -- the game's words when this machine's cache holds the extracted text, else ours
  local name = S.bagName("hp_s")
  T.check(name == "HP Bag S" or name == "HP BAG S", "the bag's name (" .. name .. ")")
  T.check(S.bagDescription("atk_l"):lower():find("attack") ~= nil, "its description names the stat")
  T.check(not S.bagDescription("atk_l"):find("{BAG}", 1, true), "...without the game's header line")
  T.eq(S.uiText("use"), "Use", "button words")
  T.check(S.uiText("askDiscard", "def_m"):lower():find("defense bag m", 1, true) ~= nil, "the question names the bag")
  T.check(not S.uiText("askUse", "def_m"):find("\n", 1, true), "questions wrap to the box, no hard breaks")
  local saved = S.session.rec.bag
  S.session.rec.bag = { id = "hp_s", hits = 3, needed = 10 }
  T.eq(S.useQuestion("spe_s"), "replaceBag", "a bag on the stand: the replace question")
  S.session.rec.bag = nil
  S.session.rec.pending = "strength"
  T.eq(S.useQuestion("big_shot"), "replaceEffect", "a pending effect: the effect question")
  T.eq(S.useQuestion("spe_s"), "askUse", "a stat bag: the plain question")
  S.session.rec.pending = nil
  S.session.rec.bag = saved
  -- the game discards the bag on the stand when a new one is set
  local bags = Store.bags()
  local before = #bags
  bags[#bags + 1] = "spd_s"
  bags[#bags + 1] = "spd_m"
  S.attachBag(#bags - 1)
  S.attachBag(#bags)
  T.eq(#Store.bags(), before, "both left the rack; the first one set was discarded, not returned")
  T.eq(S.state().bag.id, "spd_m", "the second is on the stand")
  S.session.rec.bag = saved
end

-- ------- effect bags, the pending slot, Team Flare

do
  local bags = Store.bags()
  bags[1], bags[2] = "big_shot", "strength"
  S.attachBag(1)
  for i = 1, 10 do S.hitBag("tap") end
  T.eq(S.state().pending, "big_shot", "Big-Shot waits for the next regimen")
  S.attachBag(1)
  for i = 1, 10 do S.hitBag("tap") end
  T.eq(S.state().pending, "strength", "Strength replaces it (no stacking)")
  bags[1] = "team_flare"
  S.session.rec.secondWind = nil
  S.attachBag(1)
  for i = 1, 10 do S.hitBag("tap") end
  T.check(S.state().secondWind, "Team Flare: raring to go (a second wind)")
end

-- ------- Soothing and Reset

do
  local bags = Store.bags()
  bags[1] = "soothing"
  S.attachBag(1)
  T.eq(S.state().bag.needed, 250, "Soothing: 250 hits")
  for i = 1, 125 do S.hitBag("tap") end
  T.eq(party[1].friendship, 90, "...in 125 taps with Team Flare's second wind: +20 friendship")
  T.check(not S.state().secondWind, "the wind went with that bag")
  bags[1] = "reset"
  S.attachBag(1)
  for i = 1, 100 do S.hitBag("tap") end
  T.eq(party[1].evs.hp, 0, "Reset: HP EVs gone")
  T.eq(party[1].evs.atk, 0, "...Attack too")
  T.eq(S.state().total, 0, "total 0")
end

-- ------- caps and the inventory

do
  local bags = Store.bags()
  for i = #bags, 1, -1 do table.remove(bags, i) end
  party[1].evs.spe = 252
  S.session.evs = fake.evsOf(party[1])
  bags[1] = "spe_s"
  local ok, why = S.attachBag(1)
  T.check(not ok and why == "capped", "a bag for a capped stat is refused")
  T.eq(S.state().bags, 1, "...and stays in the inventory")
  for i = 2, 12 do bags[i] = "hp_s" end
  T.eq(S.state().bags, 12, "twelve bags")
  S.rng = rngOf(0)
  Store.meta().blackTaps = 100
  local msgBefore = S.state().message
  local rolls = 0
  S.rng = function() rolls = rolls + 1; return 0 end
  S.tapBlackBag()
  T.eq(S.state().bags, 12, "a full rack finds nothing")
  T.eq(rolls, 0, "...the game makes no roll at all")
  T.eq(S.state().message, msgBefore, "...and says nothing")
  S.rng = rngOf(0.99)
  T.eq(S.discardBag(1), "spe_s", "discard returns the id")
  T.eq(S.state().bags, 11, "eleven left")
end

-- ------- Fully Trained

do
  party[1].evs = { hp = 252, atk = 252, def = 0, spa = 0, spd = 0, spe = 5 }
  S.session.evs = fake.evsOf(party[1])
  local bags = Store.bags()
  bags[1] = "def_s"
  S.attachBag(1)
  for i = 1, 10 do S.hitBag("tap") end
  T.eq(party[1].evs.def, 1, "+1 Def")
  T.eq(S.state().total, 510, "510 total")
  T.check(S.state().fully, "Fully Trained")
  T.check(S.session.rec.fully, "...recorded")
  bags[1] = "reset"
  S.attachBag(1)
  for i = 1, 100 do S.hitBag("tap") end
  T.eq(S.state().total, 0, "reset again")
  T.check(S.state().fully, "...and still Fully Trained")
end

-- ------- switching

do
  local ok, why = S.switchTo(party[2])
  T.check(not ok and why == "fainted", "a fainted Pokemon can't train")
  T.check(S.switchTo(party[3]), "another healthy one can")
  T.eq(S.state().name, "SPECIES4", "...and takes the screen")
  T.eq(S.state().evs.hp, 100, "with its own EVs")
  T.eq(#S.party(), 3, "the party strip lists three")
  T.check(S.party()[3].active and not S.party()[2].eligible, "active and eligible flags")
end

-- ------- the Wings through item.use

do
  local Hooks = run.loader.hooks or (run.loader.runtime and run.loader.runtime.hooks)
  local ok, kind, text = Items.useWing(Items.def(400), 1)
  T.check(ok and kind == "vitamin", "a Health Wing on slot 1 works (" .. tostring(text) .. ")")
  T.eq(party[1].evs.hp, 1, "+1 HP EV")
  T.eq(party[1].friendship, 95, "vitamin friendship")
  party[1].evs.hp = 252
  ok, kind = Items.useWing(Items.def(400), 1)
  T.check(not ok and kind == "noeffect", "at 252 it has no effect")
  party[1].evs.hp = 0
  T.check(Items.give(406, 1), "a Pretty Wing into the bag")
  T.eq(bag[1][1], 406, "...is item 406")
  for _ = 1, 3 do Items.give(406, 1) end
  T.check(not Items.give(406, 1), "a full bag refuses")
end

-- ------- regimens: the ladder, a forced clear, the awards

do
  S.switchTo(party[1])
  for i = #bag, 1, -1 do table.remove(bag, i) end   -- room for prizes
  party[1].evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  S.session.evs = fake.evsOf(party[1])
  S.session.rec.fully = nil
  T.eq(#S.courseList(), 30, "thirty courses on offer")
  local ok, why = S.startCourse("lv2_hp")
  T.check(not ok and why == "locked", "Lv2 is locked at the start")
  ok, why = S.startCourse("secret_01")
  T.check(not ok and why == "not_fully_trained", "secret courses need 510 EVs")
  -- a pending bag effect feeds the regimen and is spent by it
  S.session.rec.pending = "double_up"
  T.check(S.startCourse("lv1_hp"), "Lv1 HP starts")
  T.eq(S.state().mode, "regimen", "mode regimen")
  T.eq(Apps:active().id, "training_aim", "the aim pad owns the surface")
  T.check(S.sim ~= nil and S.sim.phase == "countdown", "the simulation is counting down")
  T.check(S.sim.mods.evMult == 2, "...with the Double-Up effect")
  for _ = 1, 40 do S.tick(0.1) end
  T.eq(S.sim.phase, "play", "...and playing after the countdown")
  local st = S.state()
  T.check(st.regimen and st.regimen.target == 500, "state carries the regimen (target 500)")
  -- the layer forwards the pad
  S.layer.handleInput({ wasPressed = function(_, k) return k == "l" end, isDown = function(_, k) return k == "right" end })
  T.check(S.sim.player.mx == 1, "right is held")
  T.check(S.sim.player.shield > 0, "L raised the shield")
  T.check(S.forceEnd({ clear = true, remaining = 160 }), "a forced clear")
  T.eq(S.state().mode, "result", "the result shows")
  local r = S.session.result
  T.check(r and r.clear, "cleared")
  T.eq(r.ev, 8, "+4 HP doubled by the Double-Up")
  T.eq(party[1].evs.hp, 8, "...on the party record")
  T.check(r.medal, "160 s left on a 150 s target: medal")
  T.check(r.newBest and r.firstClear, "first clear, new best")
  T.check(Rules.BAGS[r.bag] ~= nil and r.bagKept, "a bag was earned and kept (" .. tostring(r.bag) .. ")")
  T.eq(S.state().pending, nil, "the Double-Up is spent")
  T.check(Store.cleared().lv1_hp, "the course counts as cleared for everyone")
  T.eq(S.courseRecord("lv1_hp").best, 160, "best time recorded")
  T.check(r.praise ~= nil and #r.praise > 0, "the coach has a word (" .. tostring(r.praise) .. ")")
  T.check(type(r.target) == "number", "the result carries the target")
  T.eq(#r.unlocked, 0, "one Lv1 clear unlocks nothing yet")
  local nm = S.courseName("lv1_hp")
  T.check(nm == "Raise Your HP with Wailmer!", "the course's official name (" .. nm .. ")")
  T.check(S.levelHeading(2):lower():find("lv. 2", 1, true) ~= nil, "a level heading (" .. S.levelHeading(2) .. ")")
  T.check(S.leaveResult(), "leave the result")
  T.eq(S.state().mode, "courses", "...to the picker")
  -- unlock Lv2 by clearing the other five Lv1 courses; the sixth clear announces it
  for _, stat in ipairs({ "atk", "def", "spa", "spd" }) do Store.cleared()["lv1_" .. stat] = true end
  T.check(S.startCourse("lv1_spe"), "the last Lv1 course")
  S.forceEnd({ clear = true, remaining = 100 })
  r = S.session.result
  T.eq(#r.unlocked, 6, "clearing the sixth Lv1 course opens the six Lv2 courses")
  T.check(r.unlockText and r.unlockText:find("unlocked", 1, true) ~= nil, "...announced (" .. tostring(r.unlockText) .. ")")
  S.leaveResult()
  T.check(S.startCourse("lv2_hp"), "Lv2 opens once all six Lv1 are cleared")
  S.forceEnd({ timeout = true })
  r = S.session.result
  T.check(r and not r.clear, "a time out")
  T.eq(r.ev, nil, "...gives no EVs")
  T.check(Rules.N.BAG_ODDS.support[r.bag] ~= nil, "...but a support bag (" .. tostring(r.bag) .. ")")
  S.leaveResult()
  -- a secret circuit with a prize
  S.session.rec.fully = true
  for _, c in ipairs(S.courseList()) do if not c.secret then Store.cleared()[c.id] = true end end
  T.check(S.startCourse("secret_01"), "the first secret course opens for a Fully Trained Pokemon")
  T.eq(#S.sim.course.bots, 2, "two Balloon Bots")
  S.rng = rngOf(0.5)
  S.forceEnd({ clear = true, remaining = 100 })
  r = S.session.result
  T.check(r.clear and r.medal, "cleared with a medal (100 >= 90)")
  T.check(r.item ~= nil, "a prize item (" .. tostring(r.item and r.item.name) .. ")")
  T.check(r.item and r.item.given, "...went into the bag")
  S.rng = rngOf(0.99)
  S.leaveResult()
  ok, why = S.startCourse("secret_03")
  T.check(not ok and why == "locked", "secret 3 waits for 2")
  T.check(S.startCourse("secret_02"), "secret 2 is next")
  S.quitRegimen()
  T.eq(S.state().mode, "courses", "quitting returns to the picker")
  T.eq(S.sim, nil, "...and drops the simulation")
  S.enterCore()
end

-- ------- modes and closing

T.check(S.enterBags(), "BAGS mode")
T.eq(S.state().mode, "bags", "...recorded")
T.check(S.enterCore(), "back to core")
S.layer.handleInput({ wasPressed = function(_, k) return k == "b" end, isDown = function() return false end })
T.eq(S.session, nil, "B closes the session")
T.eq(#stack, 0, "the layer is popped")
T.check(not X._test.surfaceWanted(), "the surface goes dormant")
T.check(X.amie.open(), "Amie opens again")
X.amie.session.finish()

-- ------- the strip's arrows switch to Pokemon-Amie

do
  T.check(TR.open(party[1]), "open again")
  T.check(type(S.onSwitch) == "function", "the arrows have somewhere to go")
  S.onSwitch()
  T.eq(S.session, nil, "an arrow leaves Super Training")
  T.check(X.amie.session.session ~= nil, "...and opens Pokemon-Amie")
  X.amie.session.finish()
end

-- ------- the save

do
  local saved = run.loader.modSave.play_nav.training
  T.check(type(saved) == "table" and saved.schema == 1, "mod.save.training at schema 1")
  T.check(saved.mons["1234:77"] and saved.mons["1234:77"].fully == true, "the Fully Trained flag persists")
  T.eq(#saved.bags, 12, "twelve bags in the rack (three from the regimens)")
  T.check(type(saved.cleared) == "table", "the cleared table exists")
end

-- ------- training goes on with the screen closed (counts and rests only, nothing drawn)

do
  T.check(TR.open(party[1]), "open on the lead again")
  local key = S.session.key
  local bags = Store.bags()
  bags[#bags + 1] = "big_shot"
  S.attachBag(#bags)
  local rec = Store.mon(key)
  local h0 = rec.bag.hits
  rec.awakeAt, rec.restAfter = clock.wall, 1800
  rec.nextAutoAt = clock.wall + N.CORE.AUTO_HIT_S
  S.finish()
  T.eq(Store.meta().activeKey, key, "the last Pokemon to train keeps training")
  local t0 = rec.awakeAt
  clock.wall = t0 + N.CORE.AUTO_HIT_S
  S.background(true)
  T.eq(rec.bag.hits, h0 + 1, "a punch a minute with the screen closed")
  clock.wall = t0 + 150
  S.background(false)
  T.eq(rec.bag.hits, h0 + 1, "...not outside the field (a battle, a menu)")
  S.background(true)
  T.eq(rec.bag.hits, h0 + 2, "...caught up once back in the field")
  -- the blank bag: idle punches dig up a bag after a rolled 10 to 15 of them
  rec.bag = nil
  local meta = Store.meta()
  while #Store.bags() >= N.LIMITS.BAG_MAX do table.remove(Store.bags()) end
  local n0 = #Store.bags()
  S.rng = rngOf(0.5)
  clock.wall = t0 + 150 + 9 * 60
  S.background(true)
  T.eq(#Store.bags(), n0, "nine unlucky idle punches on the blank bag: nothing")
  S.rng = rngOf(0.01)
  clock.wall = t0 + 150 + 10 * 60
  S.background(true)
  T.eq(#Store.bags(), n0 + 1, "a lucky one digs up a bag, screen closed")
  S.rng = rngOf(0.99)
  clock.wall = t0 + 3600
  S.background(true)
  T.eq(rec.resting, "idle", "left alone, it lies down when its awake stretch ends")
  T.check(TR.open(party[1]), "reopened")
  T.eq(S.state().resting, "idle", "...still resting when the screen comes back")
  S.finish()
end

T.finish()
