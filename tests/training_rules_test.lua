-- Super Training rules: bags, EV caps, the ladder, medals, rolls, attack scripts and the
-- evidence coverage of the tunables. Run from the engine root:
--   luajit mods/play_nav/tests/training_rules_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/training_rules.lua")
local Shots = loadFile("mods/play_nav/data/training_shot_types.lua")
local R = loadFile("mods/play_nav/src/training/rules.lua")(N, Shots)

local function rngOf(v) return function() return v end end

-- ------- bags

T.eq(#R.BAG_LIST, 26, "18 stat bags + 8 special bags")
T.eq(R.BAGS.hp_s.hits, 10, "HP Bag S takes 10 hits")
T.eq(R.BAGS.hp_s.ev, 1, "...for +1 EV")
T.eq(R.BAGS.spe_m.hits, 25, "Speed Bag M takes 25 hits")
T.eq(R.BAGS.spe_m.ev, 4, "...for +4")
T.eq(R.BAGS.atk_l.hits, 50, "Attack Bag L takes 50 hits")
T.eq(R.BAGS.atk_l.ev, 12, "...for +12")
T.eq(R.BAGS.reset.hits, 100, "Reset Bag 100 hits")
T.eq(R.BAGS.soothing.hits, 250, "Soothing Bag 250 hits")
T.eq(R.BAGS.soothing.amount, 20, "...+20 friendship")
T.eq(R.BAGS.team_flare.effect, "refreshed", "Team Flare refreshes")
T.eq(R.bagHits("hp_l"), 50, "plain hits")
T.eq(R.bagHits("hp_l", true), 25, "refreshed: half the hits")
T.eq(R.bagHits("reset", true), 50, "Reset refreshed: 50")
T.eq(R.bagHits("nope"), 0, "unknown bag: 0")
T.check(R.isStatBag("def_s") and not R.isStatBag("strength"), "isStatBag")
T.check(R.isEffectBag("strength") and not R.isEffectBag("reset"), "isEffectBag excludes reset")
T.eq(R.BAG_ART.black, 0, "the empty bag is icon 0")
T.eq(R.BAG_ART.hp_s, 1, "HP S is icon 1")
T.eq(R.BAG_ART.spe_l, 18, "Speed L is icon 18")
T.eq(R.BAG_ART.soothing, 26, "the Soothing bag is icon 26")
T.eq(R.BAG_ART.reset, 25, "the Reset bag is icon 25")

-- ------- EVs

do
  local evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  T.eq(R.addEv(evs, "hp", 12), 12, "adding 12 HP EVs")
  T.eq(evs.hp, 12, "...lands")
  T.eq(R.addEv(evs, "hp", 250), 240, "the stat stops at 252")
  T.eq(evs.hp, 252, "...252")
  T.eq(R.addEv(evs, "hp", 1), 0, "...and nothing more")
  T.eq(R.addEv(evs, "atk", 252), 252, "a second stat to 252")
  T.eq(R.addEv(evs, "spe", 12), 6, "the total stops at 510")
  T.eq(R.evTotal(evs), 510, "total 510")
  T.check(R.isFullyTrained(evs), "fully trained at 510")
  T.eq(R.statRoom(evs, "def"), 0, "no room left anywhere")
  T.eq(R.resetEvs(evs), 510, "reset returns what was there")
  T.eq(R.evTotal(evs), 0, "...and zeroes everything")
  T.eq(R.addEv(evs, "bogus", 5), 0, "an unknown stat adds nothing")
  T.eq(R.addEv(evs, "hp", -5), 0, "a negative amount adds nothing")
  T.eq(R.statRoom({ hp = 250 }, "hp"), 2, "statRoom near the cap")
end
T.eq(R.courseEv({ ev = 4 }), 4, "course EV")
T.eq(R.courseEv({ ev = 8 }, "double_up"), 16, "...doubled by Double-Up")
T.eq(R.courseEv({ ev = 8 }, "strength"), 8, "...not by other bags")

-- ------- shot types

T.eq(R.shotType(1), "yellow", "Bulbasaur: yellow (Bulbapedia)")
T.eq(R.shotType(4), "orange", "Charmander: orange")
T.eq(R.shotType(10), "black", "Caterpie: black")
T.eq(R.shotType(999, { 11 }), "blue", "unknown species falls back by type (Water)")
T.eq(R.shotType(999, { 0 }), "black", "...or black")
T.eq(R.shotType(nil), "black", "no species: black")
do
  local count = 0
  for n = 1, 386 do if Shots[n] then count = count + 1 end end
  T.eq(count, 386, "every Gen 3 species has a colour")
end

-- ------- modifiers

do
  local zero = R.modifiers({}, nil)
  T.eq(zero.pointMult, 1, "no EVs: points x1")
  T.eq(zero.lossMult, 1, "...loss x1")
  local maxed = R.modifiers({ hp = 252, atk = 252, def = 252, spa = 252, spd = 252, spe = 252 }, nil)
  T.check(maxed.pointMult > zero.pointMult, "Atk/SpA raise points")
  T.check(maxed.shotSize > zero.shotSize, "HP grows the shot")
  T.check(maxed.lossMult < zero.lossMult, "HP cuts the loss")
  local B = { hp = 50, atk = 50, def = 50, spe = 50, spa = 50, spd = 50 }
  local zeroG = R.modifiers({}, nil, { base = B })
  local maxedG = R.modifiers({ hp = 252, atk = 252, def = 252, spa = 252, spd = 252, spe = 252 }, nil, { base = B })
  T.check(maxedG.gutsPerS > zeroG.gutsPerS, "Def/SpD fill guts faster (the game's refill)")
  -- the game's Speed / HP formulas (DllSparring.cro 0x2f84, 0x5c54)
  local st = R.shotStats({ hp = 100, atk = 0, def = 0, spe = 100, spa = 0, spd = 0 }, {}, nil)
  T.check(math.abs(st.speedMult - 1) < 1e-9 and math.abs(st.sizeMult - 1) < 1e-9, "at the reference stat our table's speed and size hold")
  local fast = R.shotStats({ hp = 100, atk = 0, def = 0, spe = 100, spa = 0, spd = 0 }, { spe = 252 }, nil)
  T.check(math.abs(fast.speedMult - (1 + 604 * 0.005) / 1.5) < 1e-9, "252 Speed EVs: (1 + 604 x 0.005) / 1.5")
  T.check(math.abs(st.lossMult - 1 / (1 + 100 * 0.005)) < 1e-9, "a hit's loss x 1 / (1 + (HPv + EV total) x 0.005)")
  local tough = R.modifiers({}, "toughen_up", { base = { hp = 100, atk = 0, def = 0, spe = 100, spa = 0, spd = 0 } })
  T.check(math.abs(tough.lossMult - st.lossMult / 1.5) < 1e-9, "Toughen Up divides it by 1.5")
  -- moving and the guard (DllSparring.cro 0x5c8c, 0x5e50)
  local fastMove = R.shotStats({ hp = 0, atk = 0, def = 50, spe = 100, spa = 0, spd = 50 }, { spe = 252 }, nil)
  T.check(math.abs(fastMove.moveMult - (1 + 604 * 0.001) / 1.1) < 1e-9, "move speed 2 x (1 + SPEv x 0.001), against SPEv 100")
  T.check(math.abs(R.shotStats({ hp = 0, atk = 0, def = 50, spe = 100, spa = 0, spd = 50 }, {}, "swiftness").moveMult - 1.5) < 1e-9, "Swiftness x1.5")
  T.check(math.abs(fastMove.blockS - math.floor(20 * (1 + 100 * 0.005)) / 30) < 1e-9, "the guard lasts int(20 x (1 + DEFv x 0.005)) frames")
  T.check(maxed.blockLen > zero.blockLen, "...and block longer")
  T.check(maxed.moveMult > zero.moveMult, "Spe moves faster")
  T.check(maxed.ballSpeedMult > zero.ballSpeedMult, "...and shoots faster")
  local half = R.modifiers({ atk = 252 }, nil)
  T.check(half.pointMult > zero.pointMult and half.pointMult < maxed.pointMult, "Atk alone is half the bonus")
  T.eq(R.modifiers({}, "big_shot").shotSize, N.SHOT.BIG_SHOT_SIZE, "Big-Shot grows the shot")
  T.eq(R.modifiers({}, "strength").pointMult, 1.5, "Strength: 1.5x points (the game's bag table)")
  T.eq(R.modifiers({}, "swiftness").moveMult, N.PLAYER.SWIFT_MULT, "Swiftness speeds movement")
  T.eq(R.modifiers({}, "toughen_up").lossMult, N.DAMAGE.TOUGHEN_MULT, "Toughen-Up halves the loss")
  T.eq(R.modifiers({}, "double_up").evMult, 2, "Double-Up doubles EVs")
  T.eq(R.modifiers({}, "double_up").pointMult, 1, "...and touches nothing else")
end

-- ------- the ladder

local courses = {}
for lv = 1, 3 do
  for i, stat in ipairs(R.STATS) do
    courses[#courses + 1] = { id = ("lv%d_%s"):format(lv, stat), level = lv, stat = stat, ev = lv * 4 }
  end
end
for s = 1, 12 do courses[#courses + 1] = { id = "secret_" .. s, secret = s, level = 3 + math.ceil(s / 3) } end

do
  local cleared = {}
  T.check(R.levelUnlocked(cleared, 1, courses), "Lv1 always open")
  T.check(not R.levelUnlocked(cleared, 2, courses), "Lv2 locked at the start")
  for i = 1, 5 do cleared["lv1_" .. R.STATS[i]] = true end
  T.check(not R.levelUnlocked(cleared, 2, courses), "five of six is not enough")
  cleared.lv1_spe = true
  T.check(R.levelUnlocked(cleared, 2, courses), "all six Lv1: Lv2 opens")
  T.check(not R.levelUnlocked(cleared, 3, courses), "Lv3 still locked")
  T.eq(R.nextSecret(cleared, courses), 1, "the first secret course is next")
  cleared.secret_1 = true
  T.eq(R.nextSecret(cleared, courses), 2, "then the second")
  local ok, why = R.canEnter(courses[7], cleared, courses)
  T.check(ok, "Lv2 HP enterable")
  ok, why = R.canEnter(courses[13], cleared, courses)
  T.check(not ok and why == "locked", "Lv3 locked")
  ok, why = R.canEnter(courses[19], cleared, courses, false)
  T.check(not ok and why == "not_fully_trained", "secret needs a Fully Trained Pokemon")
  ok = R.canEnter(courses[20], cleared, courses, true)
  T.check(ok, "secret 2 is the next one")
  ok, why = R.canEnter(courses[21], cleared, courses, true)
  T.check(not ok and why == "locked", "secret 3 waits for 2")
  T.check(not R.allMedals({ courses = {} }, courses), "no medals yet")
  local rec = { courses = {} }
  for _, c in ipairs(courses) do rec.courses[c.id] = { medal = true } end
  T.check(R.allMedals(rec, courses), "all 30 medals: Supremely Trained")
end

-- ------- clocks, medals

T.eq(R.courseTime({}), 180, "the clock is 3:00")
T.eq(R.medalTarget({ level = 1 }), 150, "Lv1 medal at 2:30 left")
T.eq(R.medalTarget({ level = 2 }), 120, "Lv2 at 2:00")
T.eq(R.medalTarget({ level = 3 }), 120, "Lv3 at 2:00")
T.eq(R.medalTarget({ secret = 4 }), 90, "secret at 1:30")
T.eq(R.medalTarget({ secret = 9, medal = 120 }), 120, "a row's own target wins")
T.check(R.medal({ level = 1 }, 150), "150 left: medal")
T.check(not R.medal({ level = 1 }, 149.9), "149.9: no medal")

-- ------- rolls

do
  local c = { level = 1, stat = "hp", ev = 4 }
  T.eq(R.rollClearBag(c, 170, rngOf(0)), "double_up", "rng 0: Double-Up")
  T.eq(R.rollClearBag(c, 170, rngOf(0.99)), "hp_l", "a fast clear: the L bag")
  T.eq(R.rollClearBag(c, 100, rngOf(0.99)), "hp_m", "a middling clear: M")
  T.eq(R.rollClearBag(c, 10, rngOf(0.99)), "hp_s", "a slow clear: S")
  T.eq(R.clearBagSize(c, 180 * 0.75), "l", "L exactly at the threshold")
  T.eq(R.rollClearBag({ secret = 1 }, 170, rngOf(0.99)), "toughen_up", "secret courses give a support bag")
  T.eq(R.rollSupportBag(rngOf(0)), "big_shot", "support roll, rng 0: first key")
  T.eq(R.rollSupportBag(rngOf(0.999)), "toughen_up", "...rng 1: last key")
  -- Pokerus only raises Double-Up
  local plain, rus = 0, 0
  for i = 0, 99 do
    if R.rollClearBag(c, 170, rngOf(i / 100)) == "double_up" then plain = plain + 1 end
    if R.rollClearBag(c, 170, rngOf(i / 100), { pokerus = true }) == "double_up" then rus = rus + 1 end
  end
  T.eq(plain, 15, "Double-Up 15% of clears")
  T.eq(rus, 30, "...30% with Pokerus")
  T.eq(R.meterStep(N.METER.BASE_STEPS, 140), 20, "meter: base 140 reaches the top step")
  T.eq(R.meterStep(N.METER.BASE_STEPS, 139), 16, "...139 the next")
  T.eq(R.meterStep(N.METER.EV_STEPS, 252), 32, "...252 EVs: 32 px")
  T.eq(R.meterStep(N.METER.EV_STEPS, 0), 1, "...no EVs: 1 px")
  local mi, mo = R.meterAxes({ hp = 140 }, { hp = 252 }, { "hp", "atk" })
  T.eq(mo[1], 52, "a maxed axis: 20 + 32 = 52 px")
  T.eq(mi[2], 1, "...an empty one: 1 px")
  T.eq(R.rollCount({ 3, 5 }, rngOf(0)), 3, "a rolled count: the low end")
  T.eq(R.rollCount({ 3, 5 }, rngOf(0.999)), 5, "...the high end")
  -- the blank bag, as the game rolls it: 5% a punch (10% fully trained), then one of 26
  T.check(R.rollBlankBag(rngOf(0.049)) ~= nil, "under 5%: a find")
  T.eq(R.rollBlankBag(rngOf(0.05)), nil, "5% or more: nothing")
  T.check(R.rollBlankBag(rngOf(0.09), { fully = true }) ~= nil, "fully trained: 10%")
  local seen, nothing = {}, 0
  for i = 0, 25 do
    local id = R.pickBlackBag(rngOf((i + 0.5) / 26))
    if id then seen[id] = true else nothing = nothing + 1 end
  end
  local kinds = 0
  for _ in pairs(seen) do kinds = kinds + 1 end
  T.eq(kinds, 25, "each of 25 bags once in 26 equal slots")
  T.eq(nothing, 1, "...and Team Flare's slot finds nothing")
  T.check(not seen.team_flare and seen.reset and seen.soothing and seen.atk_l, "M / L, Reset, Soothing drop; Team Flare never")
  T.check(not R.isRareBag("hp_s") and R.isRareBag("hp_m") and R.isRareBag("reset"), "an S stat bag is the common find")
  local items = { { "ITEM_LEAF_STONE", w = 1, bestOnly = true }, { "ITEM_HARD_STONE", w = 3 },
    { "ITEM_PP_UP", w = 2, minRemaining = 60 } }
  T.eq(R.rollSecretPrize({ items = items }, 10, rngOf(0))[1], "ITEM_HARD_STONE", "slow, not a best: only the common item")
  T.eq(R.rollSecretPrize({ items = items }, 100, rngOf(0.99))[1], "ITEM_PP_UP", "time left unlocks the PP Up")
  T.eq(R.rollSecretPrize({ items = items }, 100, rngOf(0), { newBest = true })[1], "ITEM_HARD_STONE", "sorted: HARD before LEAF")
  T.eq(R.rollSecretPrize({ items = items }, 100, rngOf(0.6), { newBest = true })[1], "ITEM_LEAF_STONE", "a new best can give the stone")
  local keyed = { { item = "ITEM_STARDUST", w = 2 }, { training = "pretty-wing", w = 2 } }
  T.eq(R.prizeKey(R.rollSecretPrize({ items = keyed }, 100, rngOf(0))), "ITEM_STARDUST", "item rows roll by name")
  T.eq(R.rollSecretPrize({ items = keyed }, 100, rngOf(0.9)).training, "pretty-wing", "training rows roll by slug")
  T.eq(R.rollSecretPrize({}, 100, rngOf(0)), nil, "no items: nil")
end

-- ------- inventory

do
  local bags = {}
  for i = 1, 12 do T.check(R.inventoryAdd(bags, "hp_s"), "bag " .. i .. " fits") end
  local ok, why = R.inventoryAdd(bags, "hp_s")
  T.check(not ok and why == "full", "the 13th is refused")
  T.check(R.inventoryFull(bags), "full")
  T.eq(R.inventoryRemove(bags, 1), "hp_s", "remove the first")
  T.eq(#bags, 11, "11 left")
  ok, why = R.inventoryAdd(bags, "nope")
  T.check(not ok and why == "unknown", "unknown bags are refused")
end

-- ------- attack scripts

do
  local lib = { gentle = { { at = 8, kind = "small" }, { every = 10, from = 20, ["until"] = 45, kind = "big" } } }
  local s = R.compileAttacks("gentle", lib)
  T.eq(#s, 4, "8, 20, 30, 40")
  T.eq(s[1].t, 8, "first at 8")
  T.eq(s[1].kind, "small", "...small")
  T.eq(s[4].t, 40, "last at 40")
  T.eq(s[4].kind, "big", "...big")
  T.eq(s[2].at, nil, "the at/every keys are stripped")
  T.eq(#R.compileAttacks({ { every = 50, kind = "ring" } }, nil), 3, "every 50 over 180 s: 50, 100, 150")
  T.eq(#R.compileAttacks("missing", lib), 0, "an unknown script compiles to nothing")
end

-- ------- evidence coverage

do
  local missing = {}
  for _, p in ipairs(R.leafPaths()) do
    if not R.evidenceFor(p) then missing[#missing + 1] = p end
  end
  T.eq(#missing, 0, "every tunable has an evidence row (" .. table.concat(missing, ", ") .. ")")
  local classes = { verified = 0, measured = 0, inferred = 0, placeholder = 0 }
  for _, row in pairs(N.EVIDENCE) do
    T.check(classes[row.class] ~= nil, "a known class: " .. tostring(row.class))
    classes[row.class] = (classes[row.class] or 0) + 1
    T.check(row.confidence == "low" or row.confidence == "medium" or row.confidence == "high", "a known confidence")
  end
  T.check(classes.verified > 10, "the verified rows are there")
end

T.finish()
