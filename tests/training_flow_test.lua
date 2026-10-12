-- Super Training end to end against a fake Gen 3 host: open from the menu, the layer and
-- the core app, bag hits raising EVs with the HP delta, the black bag, resting and the
-- second wind, Reset and Soothing bags, the inventory cap, the Fully Trained flag, the
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
local fake = {
  name = "fake", available = function() return true end,
  now = function() return os.clock() end, wallClock = function() return os.time() end,
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
S.rng = rngOf(0.99)   -- no rests, no black-bag luck unless asked

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
T.eq(#stack, 1, "the layer is pushed")
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

-- ------- the black bag

do
  local tapsBefore = S.state().blackTaps
  T.check(S.hitBag("tap"), "a tap with no bag hits the black bag")
  T.eq(S.state().blackTaps, tapsBefore + 1, "...counted")
  S.rng = rngOf(0)
  for _ = 1, 10 do S.hitBag("tap") end
  T.eq(S.state().bags, 1, "a lucky run of taps dropped a bag")
  T.check(S.state().blackTaps < 8, "...and reset the count (" .. S.state().blackTaps .. " taps since)")
  S.rng = rngOf(0.99)
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

-- ------- auto hits, rest, second wind

do
  local bags = Store.bags()
  bags[1] = "atk_m"
  S.attachBag(1)
  S.hitBag("auto")
  T.eq(S.state().bag.hits, 1, "an automatic hit counts")
  -- force a rest at the next automatic hit
  S.session.autoAt = 0
  S.rng = rngOf(0)
  S.tick(0.016)
  S.rng = rngOf(0.99)
  T.check(S.state().resting, "the Pokemon lies down")
  local ok, why = S.hitBag("auto")
  T.check(not ok and why == "resting", "no automatic hits while resting")
  T.check(S.wake(), "a tap wakes it")
  T.check(S.state().refreshed, "...refreshed")
  T.eq(S.state().bag.needed, 13, "the M bag now needs 13 hits (25 halved, rounded up)")
  for i = 1, 12 do S.hitBag("tap") end
  T.eq(party[1].evs.atk, 4, "+4 Attack")
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
  S.session.rec.refreshedUntil = nil
  S.attachBag(1)
  for i = 1, 10 do S.hitBag("tap") end
  T.check(S.state().refreshed, "Team Flare: raring to go")
end

-- ------- Soothing and Reset

do
  local bags = Store.bags()
  bags[1] = "soothing"
  S.attachBag(1)
  T.eq(S.state().bag.needed, 125, "Soothing while refreshed: 125 hits")
  for i = 1, 125 do S.hitBag("tap") end
  T.eq(party[1].friendship, 90, "+20 friendship")
  bags[1] = "reset"
  S.attachBag(1)
  for i = 1, 50 do S.hitBag("tap") end
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
  S.tapBlackBag()
  T.eq(S.state().bags, 12, "a drop with a full rack is lost")
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
  for i = 1, 5 do S.hitBag("tap") end
  T.eq(party[1].evs.def, 1, "+1 Def")
  T.eq(S.state().total, 510, "510 total")
  T.check(S.state().fully, "Fully Trained")
  T.check(S.session.rec.fully, "...recorded")
  bags[1] = "reset"
  S.attachBag(1)
  for i = 1, 50 do S.hitBag("tap") end
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

-- ------- the save

do
  local saved = run.loader.modSave.play_nav.training
  T.check(type(saved) == "table" and saved.schema == 1, "mod.save.training at schema 1")
  T.check(saved.mons["1234:77"] and saved.mons["1234:77"].fully == true, "the Fully Trained flag persists")
  T.eq(#saved.bags, 12, "twelve bags in the rack (three from the regimens)")
  T.check(type(saved.cleared) == "table", "the cleared table exists")
end

T.finish()
