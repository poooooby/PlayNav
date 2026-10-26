-- Super Training on the Game Boy games: EVs over Stat Exp (src/training/host_gb.lua) and the
-- five-stat rules (src/training/rules.lua with a Gen 1 / 2 profile). Run from the engine root:
--   luajit mods/play_nav/tests/statexp_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local pass, fail = 0, 0
local function check(ok, what)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end
end
local function eq(got, want, what) check(got == want, ("%s (got %s, want %s)"):format(what, tostring(got), tostring(want))) end

local ROOT = "mods/play_nav/"
local function load(name) return dofile(ROOT .. name) end
local Gen = load("src/gen.lua")
local N = load("data/training_rules.lua")
local makeRules = load("src/training/rules.lua")

-- ------- the profile
local p1, p2, p3 = Gen.profile(1, "red"), Gen.profile(2, "crystal"), Gen.profile(3, "emerald")
eq(p1.frameW .. "x" .. p1.frameH, "160x144", "Gen 1's frame")
eq(p1.frame.h, 216, "the frame is 216 units tall at 240 across")
eq(p1.frame.y, -28, "about the 240x160 band")
eq(p2.family, "gen2", "Crystal's songs are Gen 2's")
eq(p3.evTotal, 510, "Gen 3 keeps 510")
eq(p1.evTotal, nil, "Gen 1 has no total")

-- ------- the rules
local R = makeRules(N, {}, p1)
local R3 = makeRules(N, {}, p3)
eq(#R.STATS, 5, "five stats")
eq(R.STATS[5], "spc", "Special")
eq(#R3.STATS, 6, "Gen 3: six")
eq(R.statOf("spa"), "spc", "Sp. Atk trains Special")
eq(R.statOf("spd"), "spc", "Sp. Def trains Special")
eq(R3.statOf("spa"), "spa", "Gen 3: Sp. Atk is itself")
eq(R.evTotalMax(), 1260, "every stat full: 5 x 252")

local evs = { hp = 0, atk = 0, def = 0, spe = 0, spc = 0 }
eq(R.addEv(evs, "spa", 12), 12, "+12 Sp. Atk")
eq(evs.spc, 12, "...is Special")
eq(evs.spa .. "/" .. evs.spd, "12/12", "...read by Sp. Atk and Sp. Def")
eq(R.addEv(evs, "spd", 300), 240, "Special stops at 252")
eq(R.addEv(evs, "hp", 252) + R.addEv(evs, "atk", 252) + R.addEv(evs, "def", 252), 756, "no 510 total")
check(not R.isFullyTrained(evs), "Speed 0: not Fully Trained")
eq(R.statRoom(evs, "spe"), 252, "Speed has its 252")
R.addEv(evs, "spe", 252)
check(R.isFullyTrained(evs), "every stat at 252: Fully Trained")
eq(R.evShare(evs), 1, "the gauge full")
R.resetEvs(evs)
eq(evs.spc + evs.spa + evs.spd, 0, "the reset clears Special")

-- bags: the Special ones stand in for Sp. Atk / Sp. Def ones
check(R.BAGS.spc_s ~= nil and R.BAGS.spc_l.ev == N.BAGS.STAT.l.ev, "Special bags S / M / L")
eq(R.regularBag("spa_m"), "spc_m", "a Sp. Atk find is a Special bag")
eq(R.regularBag("spd_l"), "spc_l", "a Sp. Def find too")
eq(R3.regularBag("spa_m"), "spa_m", "Gen 3 keeps its own")
eq(R.bagArt("spc_s"), R.bagArt("spa_s"), "Special wears the Sp. Atk bag's picture")
for i = 0, 999 do
  local id = R.pickBlackBag(function() return (i % 26) / 26 end)
  if id then check(R.BAGS[id].stat ~= "spa" and R.BAGS[id].stat ~= "spd", "no Sp. Atk / Sp. Def bag found: " .. id) end
end
local course = { stat = "spa", level = 1, time = 60 }
local bag = R.rollClearBag(course, 60, function() return 0.99 end)
eq(bag, "spc_l", "a cleared Sp. Atk regimen gives a Special bag")
eq(#R.ROCKET_LIST, 10, "the dealer sells ten (five stats, R / R+)")
local hasSpc = false
for _, id in ipairs(R.ROCKET_LIST) do if id == "spc_rp" then hasSpc = true end end
check(hasSpc, "...Special R+ among them")

-- the game's shot formulas read the total on the 510 scale
local base = { hp = 45, atk = 49, def = 49, spe = 45, spa = 65, spd = 65 }
local full = { hp = 252, atk = 252, def = 252, spe = 252, spc = 252, spa = 252, spd = 252 }
local full3 = { hp = 252, atk = 252, def = 6, spe = 0, spa = 0, spd = 0 }
eq(R.shotStats(base, full).evTotal, 510, "Gen 1 fully trained shoots as 510")
eq(R3.shotStats(base, full3).evTotal, 510, "Gen 3's 510")

-- ------- the host over Stat Exp
local gen1Data = { pokemon = { PIKACHU = { dex = 25, name = "PIKACHU",
  baseStats = { hp = 35, attack = 55, defense = 30, speed = 90, special = 50 }, types = { "ELECTRIC", "ELECTRIC" } } } }
local mon = { species = "PIKACHU", level = 50, hp = 100, dvs = { hp = 15, attack = 15, defense = 15, speed = 15, special = 15 },
  statExp = { hp = 0, attack = 63504, defense = 1000, speed = 65535, special = 144 } }
local Stats = require("src.pokemon.Stats")
mon.stats = Stats.calc(gen1Data.pokemon.PIKACHU, 50, mon.dvs, mon.statExp)
mon.hp = mon.stats.hp
local fakeMod = { generation = 1, game = { save = { party = { mon }, money = 5000, options = { musicVol = 7, sfxVol = 3 } }, data = gen1Data },
  log = { warn = function() end, info = function() end } }
local base1 = load("src/refresh/host_gb.lua")(fakeMod, p1)
local H = load("src/training/host_gb.lua")(fakeMod, base1)
local e = H.evsOf(mon)
eq(e.atk, 252, "Stat Exp 63504 is 252 EVs")
eq(e.def, 32, "Stat Exp 1000 is 32 (ceil sqrt)")
eq(e.spe, 255, "65535 reads 255")
eq(e.spc, 12, "Special 144 is 12")
eq(e.spa .. "/" .. e.spd, "12/12", "...as Sp. Atk and Sp. Def")
local atk0, hp0, max0 = mon.stats.attack, mon.hp, mon.stats.hp
e.spc, e.hp = 13, 8
H.setEvs(mon, e)
eq(mon.statExp.special, 169, "13 EVs write Stat Exp 169")
eq(mon.statExp.defense, 1000, "an untouched stat keeps its Stat Exp")
eq(mon.statExp.speed, 65535, "...the full one too")
eq(mon.statExp.hp, 64, "8 HP EVs: Stat Exp 64")
eq(mon.stats.attack, atk0, "Attack unchanged")
eq(mon.stats.hp, max0 + 1, "HP up by its bonus (8 EVs: +2, +1 at Lv50)")
eq(mon.hp, hp0 + 1, "current HP moves with the max")
H.setEvs(mon, { hp = 0, atk = 0, def = 0, spe = 0, spc = 0 })
eq(mon.statExp.attack, 0, "a reset writes 0")
check(mon.stats.attack < atk0, "and the stats fall")
H.setEvs(mon, { spa = 20, spd = 30 })
eq(mon.statExp.special, 900, "spa / spd alone: the larger, 30 -> 900")
eq(H.money(), 5000, "Gen 1's money")
check(H.spendMoney(1200) and H.money() == 3800, "spent")
eq(H.sfxGain(), 3 / 7, "the effects volume from the options")
eq(H.baseStats("PIKACHU").spa, 50, "Gen 1's Special as Sp. Atk")
eq(base1.national(mon), 25, "National number from the species record")
eq(base1.speciesFromNational(25), "PIKACHU", "and back")
eq(base1.typeName("PSYCHIC_TYPE"), "Psychic", "type names as Decor's")
eq(base1.statusOf({ status = "SLP" }), "SLP", "Gen 1 status")
eq(base1.statusOf({ status = "paralyze" }), "PAR", "Gen 2 status")
check(type(base1.monKey(mon)) == "string", "a key for the mon")

print(("%d/%d checks passed%s  (play_nav stat exp)"):format(pass, pass + fail,
  fail > 0 and (", " .. fail .. " FAILURES") or ""))
if fail > 0 then os.exit(1) end
