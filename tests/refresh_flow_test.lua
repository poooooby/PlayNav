-- Pokemon-Amie end to end against a fake Gen 3 host: battle.ended drops a
-- puff; play -> pet by spot, hit, high-five, feed -> DONE,
-- with the top-screen layer pushed and popped, the meters persisted in
-- mod.save (schema 2), steps and battles moving the stats outside a session.
-- Run from the engine root: luajit mods/play_nav/tests/refresh_flow_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local run = T.sdk.loadMod("mods/play_nav", { generation = 3, data = T.sdk.gen3Data and T.sdk.gen3Data() or nil })
T.eq(#run.errors, 0, "the mod loads clean on gen 3 (" .. tostring(run.errors[1]) .. ")")

local X = run.loader.exports.play_nav
-- fake hosts, not the player's cache: the import gate stands aside
if X and X._test and X._test.setImportGate then X._test.setImportGate(false) end
local A = X.amie
T.check(type(A) == "table" and type(A.onBattleEnded) == "function", "amie is exported")
T.eq(X.refresh, A, "...and under the old refresh name too")
local S = A.session
local Rules = A.rules

-- ------- a fake host: a party, a stack, sounds, pics

local party = {
  { personality = 1234, otId = 77, species = 25, hp = 20, maxHp = 35, status = "PSN", nickname = "SPARKY" },
  { personality = 5, otId = 77, species = 7, hp = 0, maxHp = 30 },
}
local stack = {}
local sounds, cries = {}, {}
local fake = {
  name = "fake", available = function() return true end,
  now = function() return os.clock() end, wallClock = function() return os.time() end,
  party = function() return party end,
  monKey = function(m) return m.personality .. ":" .. m.otId end,
  resolve = function(m) for _, p in ipairs(party) do if p.personality == m.personality then return p end end return m end,
  isEgg = function() return false end,
  speciesOf = function(m) return m.species end,
  national = function(m) return m.species end,
  displayName = function(m) return m.nickname or ("SPECIES" .. m.species) end,
  frontPic = function() return nil end,
  icon = function() return nil end,
  typesOf = function(sp) if sp == 4 or sp == 5 or sp == 6 then return { 10 } end return { 11 } end,
  statusOf = function(m) return m.status end,
  cureStatus = function(m) m.status = nil; return true end,
  playCry = function(m) cries[#cries + 1] = m.species end,
  playSe = function(name) sounds[#sounds + 1] = name end,
  pushLayer = function(module) stack[#stack + 1] = module; return true end,
  popLayer = function() stack[#stack] = nil; return true end,
  layerOpen = function() return #stack > 0 end,
  battleFacts = function(ev) return { damaged = true, wild = true, grass = true, foeTypes = { "WATER" }, result = ev.result } end,
  activeMon = function(ev) return ev.battle.player.mon end,
  leadMon = function() return party[1] end,
  playerName = function() return "WOOBLE" end,
  dexSeen = function() return { 1, 4, 7, 25, 252, 255 } end,
  speciesName = function(sp) return "SPECIES" .. tostring(sp) end,
  iconSpecies = function() return nil end,
  typeName = function(id) return ({ [10] = "Fire", [11] = "Water", [12] = "Grass", [13] = "Electric" })[id] end,
  evoRoot = function(sp) if sp == 5 or sp == 6 then return 4 end return sp end,
}
X._test.setRefreshHost(fake)

local ev = { result = "win", battle = { wild = true, player = { mon = party[1] }, enemy = { mon = { species = 7 } } } }

-- ------- the save migrated to schema 2

T.eq(run.loader.modSave.play_nav.schema, 2, "the save is at schema 2")
T.eq(#A.puffs(), 10, "ten starting puffs")
T.eq(run.loader.modSave.play_nav.beans, nil, "no v1 bean counts remain")

-- ------- a battle: nothing drops, nothing opens (Poke Puffs come from the minigames only)

do
  local ok, why = A.onBattleEnded({ result = "lose", battle = { player = { mon = party[1] } } })
  T.eq(ok, false, "a lost battle drops nothing")
  T.eq(why, "no puffs from battles", "...for that reason")
end
S.rng = function() return 0.05 end
local granted, whyGrant = A.onBattleEnded(ev)
T.eq(granted, false, "a won battle drops no Poke Puff either")
T.eq(whyGrant, "no puffs from battles", "...and says why")
T.eq(A.state(), nil, "...without opening a session")
T.eq(#stack, 0, "...or pushing the layer")
T.eq(X._test.surfaceWanted(), false, "...and the surface stays dormant")
T.eq(#A.puffs(), 10, "the jar keeps the starting ten")
A.puffs()[#A.puffs() + 1] = "puff/sweet_basic"   -- the eleventh the later checks expect

-- ------- play, straight in

T.eq(A.openPlay(), true, "openPlay() opens the close-up")
local st = A.state()
T.eq(st.mode, "play", "the session opens in the play mode")
T.eq(st.name, "SPARKY", "the nickname is shown")
T.eq(#stack, 1, "the top-screen layer is pushed")
T.eq(X.apps:active().id, "play", "the surface switched to the PLAY app")
T.eq(X._test.surfaceWanted(), true, "a session wakes the dormant surface")
T.check(#cries >= 1, "the Pokemon cries when play starts")
T.eq(st.meters.enjoyment, 10, "opening play gives 10 enjoyment")
T.eq(#X.apps:get("play").geometry.tools(S.session), 2, "the tray holds the puffs and the games")

-- petting by spot: Pikachu (25) likes under the chin (chest), not its stomach. With no
-- affection at all every spot pets as a normal one, so start it off with a little.
st.meters.affection = 5
st.meters.enjoyment = 100
local aff = st.meters.affection
local hearts, kind, event = S.petStroke(30, 100, "favored")
T.eq(event, false, "30 px is not a petting event yet")
hearts, kind, event = S.petStroke(40, 100, "favored")
T.eq(event, true, "70 px makes one")
T.eq(hearts, 3, "...a favored spot at 100 enjoyment is three hearts")
T.eq(st.meters.affection, aff + 3, "...and three affection")
T.eq(st.meters.enjoyment, 58, "...for 42 enjoyment")
hearts = S.petEvent("disfavored")
T.eq(hearts, 0, "a disfavored spot gives nothing")
T.eq(st.meters.enjoyment, 38, "...and costs 20 enjoyment")
hearts, kind = S.petStroke(100, 2000, "normal")
T.eq(kind, "fast", "scrubbing fast is not petting")
T.eq(A.petting.spotAt(25, 0, 0.05), "favored", "the zone under Pikachu's chin is favored")
T.eq(A.petting.spotAt(25, 0, 0.45), "disfavored", "its stomach is not")

-- hit and high-five
local enj = st.meters.enjoyment
T.eq(S.hit(), true, "a hit lands")
T.eq(st.meters.enjoyment, enj - 5, "...for -5 enjoyment")
T.eq(S.canHighFive(), true, "with 5+ affection a high-five is on offer")
T.eq(S.highFive(), true, "...and it works")
T.eq(st.meters.enjoyment, enj - 5 + 10, "...for +10 enjoyment")

-- puffs: the simple path and the bite path
local full = st.meters.fullness
local jar = #A.puffs()
local okFeed, fed = S.feedPuff()
T.eq(okFeed, true, "a puff is eaten")
T.eq(fed, 2, "...a basic puff is two hearts")
T.check(A.state().message and A.state().message:find("Puff"), "the message names a Poke Puff (ours or the game text)")
T.eq(st.meters.fullness, full + 50, "fullness rose by 50")
T.eq(#A.puffs(), jar - 1, "the puff came out of the jar")
local owned = Rules.ownedPuffs(A.puffs())
T.eq(S.feedStart(owned[1].id), true, "a held puff starts the bites")
local f = A.state().feeding
T.check(f and f.bites >= 2, "...with a bite count")
local bites, done = 0, nil
for _ = 1, 400 do
  local what, h = S.feedHold(0.1)
  if what == "bite" then bites = bites + 1 end
  if what == "done" then done = h; break end
end
T.eq(bites, f.bites - 1, "every bite but the last is partial")
T.eq(done, 2, "the last bite finishes the puff for two hearts")
T.eq(st.meters.fullness, full + 100, "...and 50 fullness in total")
T.eq(S.feedStart(owned[1].id) and S.feedDrop(), true, "a puff pulled away is dropped")
T.eq(A.state().feeding, nil, "...and the bites stop")
st.meters.fullness = 255
local okFull, why = S.feedStart(owned[1].id)
T.eq(why, "full", "a full Pokemon turns away")

-- milestones: push affection over 50 and the dance + gift events fire
st.meters.affection = 49
st.meters.enjoyment = 100
S.petEvent("favored")
local events = S.takeEvents()
local sawDance, sawGift = false, false
for _, e in ipairs(events) do
  if e.kind == "dance" then sawDance = true end
  if e.kind == "gift" and e.affection == 50 then sawGift = true end
end
T.eq(sawDance, true, "crossing 50 affection dances")
T.eq(sawGift, true, "...and earns a gift")
T.eq(#A.store.visitors().gifts >= 1, true, "the gift waits in the visitors record")

-- done: persisted and released
S.finish()
T.eq(A.state(), nil, "DONE ends the session")
T.eq(#stack, 0, "...and pops the layer")
local saved = run.loader.modSave.play_nav
T.check(type(saved) == "table" and type(saved.mons) == "table", "meters are in mod.save")
local rec = saved.mons["1234:77"]
T.check(rec ~= nil, "...keyed by personality:otId")
T.eq(rec.affection, st.meters.affection, "...with the affection reached")
T.check(rec.lastCareAt ~= nil, "...and a last-played timestamp")

-- ------- outside a session: steps and battles move the active Pokemon's stats

local m = A.meters("1234:77")
m.fullness, m.enjoyment = 100, 50
for _ = 1, 50 do S.onStep() end
T.eq(m.fullness, 99, "50 steps take one fullness")
T.eq(m.enjoyment, 51, "...and give one enjoyment")
-- the Hall of Fame: one Supreme Honor puff waits with the visitors, once
local gifts = A.store.visitors().gifts
local giftsBefore = #gifts
local liveHost = X._test.refreshHost()
liveHost.gameCleared = function() return true end
for _ = 1, 100 do S.onStep() end
liveHost.gameCleared = function() return false end
T.eq(#gifts, giftsBefore + 1, "after the Hall of Fame one gift waits, however far you walk")
T.eq(gifts[#gifts].puff, "puff/supreme_honor", "...a Supreme Honor puff")
local honorJar = #A.puffs()
A.visitors.claim(#gifts)
T.eq(A.puffs()[#A.puffs()], "puff/supreme_honor", "...claimed into the jar")
T.eq(#A.puffs(), honorJar + 1, "...one puff")
m.fullness, m.enjoyment = 99, 51
S.onBattleStarted()
T.eq(m.fullness, 89, "entering a battle takes 10 fullness")
T.eq(m.enjoyment, 56, "...and gives 5 enjoyment")

-- ------- opening from the menu: the room, then play and back, then a switch

T.eq(A.open(), true, "open() from the menu opens the room")
T.eq(A.state().mode, "home", "...mode home")
T.eq(X.apps:active().id, "home", "...on the HOME app")
S.enterPlay()
T.eq(A.state().mode, "play", "PLAY switches to play")
T.eq(X.apps:active().id, "play", "...on the PLAY app")
T.eq(A.state().fromHome, true, "...remembering the room")
S.back()
T.eq(A.state().mode, "home", "BACK returns to the room")
-- the room is the bottom screen alone (as Super Training's home): the game keeps the top
T.eq(#stack, 0, "...and the top-screen layer comes down for it")
S.enterPlay()
T.eq(#stack, 1, "PLAY brings the top-screen layer back")
S.back()
T.eq(#stack, 0, "...and the room takes it down again")
party[3] = { personality = 99, otId = 77, species = 4, hp = 10, maxHp = 20, nickname = "EMBER" }
T.eq(S.switchTo(party[3]), true, "SWITCH takes another party member")
T.eq(A.state().name, "EMBER", "...and the room shows it")
T.eq(A.state().national, 4, "...with its species")
T.eq(A.store.meta().activeKey, "99:77", "...remembered as the active Pokemon")
S.finish()
T.eq(A.state(), nil, "CLOSE ends the session")
T.eq(A.open(), true, "the next open...")
T.eq(A.state().name, "EMBER", "...shows the remembered Pokemon")
S.finish()
party[3] = nil
T.eq(A.openPlay(), true, "openPlay() goes straight to play")
T.eq(A.state().mode, "play", "...mode play")
T.eq(A.state().fromHome, false, "...with no room to go back to")
S.back()
T.eq(A.state(), nil, "...so BACK closes")

-- ------- minigames: the picker (on the play screen) needs three healthy Pokemon, a game records a result

T.eq(A.openPlay(), true, "play again for the games")
local okG, whyG = S.showGames()
T.eq(okG, false, "with one healthy Pokemon the games refuse")
T.eq(whyG, "need three healthy Pokemon", "...saying why")
party[2].hp = 15
party[3] = { personality = 99, otId = 77, species = 4, hp = 10, maxHp = 20, nickname = "EMBER" }
T.eq(S.showGames(), false, "a poisoned Pokemon is out too (SPARKY is still poisoned)")
party[1].status = nil
T.eq(S.showGames(), true, "with three healthy they open")
T.eq(A.state().mode, "play", "...still the play mode")
T.eq(A.state().tool, "games", "...with the picker up")
T.eq(X.apps:active().id, "play", "...on the PLAY app")
T.eq(A.meters("1234:77").enjoyment > 0, true, "opening the games cheers the active Pokemon")
local okStart, whyStart = S.startGame("berry", "normal")
T.eq(okStart, false, "normal is locked at first")
T.eq(whyStart, "locked", "...and says so")
T.eq(S.startGame("berry", "easy"), true, "easy Berry Picker starts")
T.eq(A.state().mode, "game", "...mode game")
T.eq(X.apps:active().id, "game_berry", "...on the Berry Picker app")
T.eq(A.state().game.id, "berry", "...with the game recorded")
T.eq(#A.state().game.participants, 3, "...and three participants")
local gapp = X.apps:get("game_berry")
-- the opening demo (10 s with the game's art, a 3 s count without) then play
for _ = 1, 200 do gapp:update(0.1); if gapp.debugState().phase == "play" then break end end
T.eq(gapp.debugState().phase, "play", "the opening ran and the game is on")
T.eq(A.state().mode, "game", "...in mode game")
local jarBefore = #A.puffs()
gapp.forceEnd(20)
T.eq(A.state().mode, "game", "the result shows on the game app first")
local res = A.state().lastResult
T.check(res ~= nil, "a result was recorded")
T.eq(res.stars, 4, "...20 berries is four stars")
T.eq(#A.puffs(), jarBefore + 5, "...five puffs in the jar")
T.eq(res.unlockedNew, "normal", "...normal unlocked")
S.leaveGame()
T.eq(A.state().mode, "play", "leaving the result returns to play")
T.eq(A.state().tool, "games", "...with the picker still up")
T.check(A.state().message and A.state().message:find("puffs"), "...and the result as a line")
T.eq(S.startGame("head", "easy"), true, "Head It starts")
local happ = X.apps:get("game_head")
for _ = 1, 40 do happ:update(0.1) end
happ.forceEnd(45)
T.eq(A.state().lastResult.stars, 3, "45 points on easy Head It is three stars")
S.leaveGame()
T.eq(S.startGame("tile", "easy"), true, "Tile Puzzle starts")
local tapp = X.apps:get("game_tile")
for _ = 1, 40 do tapp:update(0.1) end
tapp.forceEnd(25)
T.eq(A.state().lastResult.stars, 4, "25 seconds on easy Tile Puzzle is four stars")
S.leaveGame()
S.back()
T.eq(A.state().tool, nil, "BACK folds the picker")
T.eq(A.state().mode, "play", "...and stays on play")
S.finish()
party[3] = nil
party[2].hp = 0

-- ------- decorate: the room's wallpaper and items; visitors and their gifts

T.eq(A.open(), true, "the room again")
local Dc = A.decor
local decorRec = A.store.decor()
T.eq(Dc.ownedCount(decorRec), 11, "the room comes with the eleven default decor items")
T.eq(A.store.room().wallpaper, "wall/pink", "...and the pink wallpaper")
T.eq(S.enterDecorate(), true, "DECORATE opens the drawer")
T.eq(A.state().mode, "decorate", "...mode decorate")
T.eq(X.apps:active().id, "decorate", "...on the decorate app")
T.eq(Dc.place(A.store.room(), decorRec, "cushion/leaf_cushion", 100, 110), true, "a cushion is placed")
T.eq(Dc.setWallpaper(A.store.room(), decorRec, "wall/blue"), true, "the blue wallpaper applies")
S.enterHome(false)
T.eq(A.state().mode, "home", "DONE returns to the room")
T.eq(Dc.nearestCushion(A.store.room(), 100, 100).id, "cushion/leaf_cushion", "...where the cushion waits")
local Vs = A.visitors
T.check(#Vs.poolOf() >= 4, "the visitor pool has species to draw from")
local before = #Vs.pending()
local req = Vs.force({ 4, 5, 6 }, { 255, 255, 255 })
T.eq(req.any, true, "three of one evolutionary line give any item")
req = Vs.force({ 4, 25, 7 }, { 255, 255, 255 })
T.eq(req.set, "F", "three at max affection give set F")
req = Vs.force({ 4, 25, 7 }, { 0, 0, 0 })
T.eq(req.set, "A", "three at zero give set A")
T.eq(#Vs.pending(), math.min(before + 3, 6), "three more gifts wait on the floor (six at most)")
Dc.setPuffOut(A.store.room(), A.puffs(), Rules.ownedPuffs(A.puffs())[1].id)
local text, gift = Vs.claim(1)
T.check(text and text:find("You received"), "claiming a gift says what arrived")
T.check(gift.kind == "item" or gift.kind == "puff", "...an item or a puff")
T.eq(#Vs.pending(), math.min(before + 3, 6) - 1, "...and it leaves the floor")
S.finish()

-- ------- benefits: the endure odds and affection lookup

if A.benefits then
  T.eq(A.benefits.endurePct(0), 0, "no affection, no endure")
  T.eq(A.benefits.endurePct(100), 10, "level 3 endures 10%")
  T.eq(A.benefits.endurePct(150), 15, "level 4 endures 15%")
  T.eq(A.benefits.endurePct(200), 20, "200 points endure 20%")
  T.eq(A.benefits.endurePct(255), 25, "level 5 endures 25%")
  T.eq(A.benefits.affectionOf(party[1]), m.affection, "affection is read from the save by key")

  -- each benefit through the engine's own hook chain, as a Gen 3 battle calls it (Bulbapedia
  -- "Affection", Generation VI: the numbers Alpha Sapphire uses)
  A.benefits.install()
  local H = run.loader.hooks
  local saved = m.affection
  local me = { side = "player", partyIndex = 1, mon = party[1] }
  local foe = { side = "opponent", partyIndex = 1, mon = {} }
  local st = { playerHalf = 6, playerName = "WOOBLE" }
  local function exp(aff)
    m.affection = aff
    return H:call("exp.gain", function() return 100 end, { mon = party[1], battle = st })
  end
  T.eq(exp(49), 100, "experience: level 1, no boost")
  T.eq(exp(50), 120, "experience: level 2 and up, 1.2x")
  -- critical hits: a second chance of 1/(d-1) on a miss doubles 1/d
  local drew
  local function crit(aff, stage, roll)
    m.affection = aff
    drew = nil
    return H:call("battle.crit", function() return false end, { battle = st, attacker = me, stage = stage,
      rng = function(lo, hi) drew = hi; return roll end })
  end
  T.eq(crit(254, 0, 0), false, "crit: under level 5, nothing extra")
  T.eq(crit(255, 0, 0), true, "crit: level 5, the extra chance can land")
  T.eq(drew, 14, "...a second draw of 1 in 15 at stage 0 (1/16 doubled to 1/8)")
  T.eq(crit(255, 1, 1), false, "...and miss")
  T.eq(drew, 6, "...1 in 7 at stage 1 (1/8 doubled to 1/4)")
  -- dodging: the foe's accuracy drops 10 points at 200+, never for moves that cannot miss
  local seen
  local function acc(aff, effect)
    m.affection = aff
    seen = nil
    H:call("battle.accuracy", function(c) seen = c.accuracy; return true end,
      { battle = st, user = foe, target = me, accuracy = 100, move = { effect = effect or 0 } })
    return seen
  end
  T.eq(acc(199), 100, "dodge: under 200, the foe's accuracy stands")
  T.eq(acc(200), 90, "dodge: 200+, the foe's accuracy drops 10 points")
  T.eq(acc(255, 17), 100, "...not for a move that cannot miss (Swift)")
  -- enduring: a knockout left at 1 HP, 10 / 15 / 20 / 25 %
  party[1].hp = 50
  local function hit(aff, roll)
    m.affection = aff
    return (H:call("battle.damage", function() return 80, {} end,
      { battle = st, user = foe, target = me, rng = function() return roll end }))
  end
  T.eq(hit(99, 0), 80, "endure: under level 3, the knockout lands")
  T.eq(hit(100, 9), 49, "endure: level 3, a roll under 10 leaves 1 HP")
  T.eq(hit(100, 10), 80, "...and 10 or more does not")
  T.eq(hit(255, 24), 49, "endure: level 5, under 25 holds on")

  -- the game's level-4 lines (Bulbapedia "Affection", X / Y / ORAS wording)
  local said = {}
  A.benefits.sayHook = function(t) said[#said + 1] = t end
  local E = run.loader.events
  local function last() return said[#said] end
  -- a fresh battle: nothing left over from the checks above (their queued crit line, the
  -- stand-in battler's endure flag)
  me._amieEndure = nil
  E:emit("battle.started", { battle = st })
  -- a super-effective hit, said once the next move starts (after "It's super effective!")
  m.affection = 150
  local n0 = #said
  E:emit("battle.damage_dealt", { battle = st, user = me, target = foe, damage = 20, effectiveness = 20 })
  T.eq(#said, n0, "super effective: held until the next move")
  E:emit("battle.move_used", { battle = st })
  T.eq(last(), "That's it! I knew you could do it!", "...then the game's line")
  m.affection = 149
  n0 = #said
  E:emit("battle.damage_dealt", { battle = st, user = me, target = foe, damage = 20, effectiveness = 20 })
  E:emit("battle.move_used", { battle = st })
  T.eq(#said, n0, "under level 4: no line")
  -- the HP bar turning red (under 10 of 48 pixels), once on the way in
  m.affection = 150
  party[1].maxHp, party[1].hp = 100, 15
  n0 = #said
  E:emit("battle.damage_dealt", { battle = st, user = foe, target = me, damage = 30 })
  E:emit("battle.turn_ended", { battle = st })
  T.check(said[n0 + 1] and said[n0 + 1]:find("is in a bit of a pinch. It looks like it might cry...", 1, true) ~= nil,
    "into the red: the pinch line")
  n0 = #said
  party[1].hp = 10
  E:emit("battle.damage_dealt", { battle = st, user = foe, target = me, damage = 5 })
  E:emit("battle.turn_ended", { battle = st })
  T.eq(#said, n0, "already red: not again")
  T.check(A.benefits.inRed(20, 100) and not A.benefits.inRed(21, 100), "red is under 10 of 48 pixels (20 of 100)")
  -- asleep: once each time it falls asleep
  local sleeper = { side = "player", partyIndex = 1, mon = party[1], status = "SLEEP" }
  local stS = { playerHalf = 6, battlers = { [0] = sleeper } }
  n0 = #said
  E:emit("battle.turn_started", { battle = stS })
  T.check(last() and last():find("is fast asleep... Zzz... Zzz...", 1, true) ~= nil, "asleep (spelled SLEEP): the game's line")
  E:emit("battle.turn_started", { battle = stS })
  T.eq(#said, n0 + 1, "...once while it sleeps")
  sleeper.status = nil
  E:emit("battle.turn_started", { battle = stS })
  sleeper.status = "SLP"
  E:emit("battle.turn_started", { battle = stS })
  T.eq(#said, n0 + 2, "...and again when it falls asleep again")
  T.eq(A.benefits.statusCode("PARALYSIS"), "PAR", "status spellings map to the game's codes")
  A.benefits.sayHook = nil
  m.affection = saved
end

run.release()
T.finish("play_nav amie flow")
