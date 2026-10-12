-- Pokemon-Amie stat rules against the Bulbapedia table.
-- Run from the engine root: luajit mods/play_nav/tests/amie_rules_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/amie_rules.lua")
local R = loadFile("mods/play_nav/src/amie/rules.lua")(N)

-- ------- levels

T.eq(R.level(0), 0, "0 points is level 0")
T.eq(R.level(1), 1, "1 point is level 1")
T.eq(R.level(49), 1, "49 is still level 1")
T.eq(R.level(50), 2, "50 is level 2")
T.eq(R.level(100), 3, "100 is level 3")
T.eq(R.level(150), 4, "150 is level 4")
T.eq(R.level(254), 4, "254 is level 4")
T.eq(R.level(255), 5, "255 is level 5")

-- ------- petting

do
  local m = R.newMeters()
  m.enjoyment = 100
  local a, e = R.pet(m, "favored")
  T.eq(a, 3, "with no affection yet a favored spot counts as normal: +3 at enjoyment 100")
  T.eq(e, -50, "...spending 50 enjoyment")
  T.eq(m.affection, 3, "affection is 3")
  T.eq(m.enjoyment, 50, "...and -50 enjoyment")
  a, e = R.pet(m, "favored")
  T.eq(a, 3, "favored at enjoyment 50 gives +3")
  T.eq(e, -42, "...for -42 enjoyment")
  T.eq(m.enjoyment, 8, "enjoyment is now 8")
  a, e = R.pet(m, "favored")
  T.eq(a, 0, "below 16 enjoyment a favored pet gives nothing")
  T.eq(e, 0, "...and costs nothing")
  m.enjoyment = 30
  a, e = R.pet(m, "normal")
  T.eq(a, 1, "normal at 30 enjoyment gives +1")
  T.eq(e, -20, "...for -20")
  m.enjoyment = 40
  a = R.pet(m, "normal")
  T.eq(a, 2, "normal at 40 gives +2")
  m.enjoyment = 10
  a, e = R.pet(m, "disfavored")
  T.eq(a, 0, "a disfavored spot never adds affection")
  T.eq(e, -10, "...and takes 20 enjoyment, clamped at 0")
  T.eq(m.enjoyment, 0, "enjoyment floor is 0")
  m.enjoyment = 20
  a = R.pet(m, "favored")
  T.eq(a, 1, "favored at 20 gives +1 (16..41 band)")
end

-- ------- other play events

do
  local m = R.newMeters()
  m.enjoyment = 100
  T.eq(R.hit(m), -5, "a hit costs 5 enjoyment")
  T.eq(R.highFive(m), 10, "a high-five gives 10")
  T.eq(R.canHighFive(m), false, "...but needs 5 affection to be offered")
  m.affection = 5
  T.eq(R.canHighFive(m), true, "5 affection unlocks it")
  T.eq(R.openPlay(m), 10, "opening play gives 10 enjoyment")
  m.fullness = 200
  R.battleEntered(m)
  T.eq(m.fullness, 190, "a battle takes 10 fullness")
  T.eq(m.enjoyment, 120, "...and gives 5 enjoyment")
  m.enjoyment = 69
  R.steps(m, 1)
  T.eq(m.fullness, 189, "50 steps take 1 fullness")
  T.eq(m.enjoyment, 70, "...and give 1 enjoyment below 70")
  R.steps(m, 1)
  T.eq(m.enjoyment, 70, "...but not at 70")
  local a = R.newMeters()
  a.fullness = 150
  R.gameWin(a, "berry", "easy")
  T.eq(a.fullness, 40, "a won game takes 110 fullness")
  T.eq(a.enjoyment, 80, "...and gives 80 enjoyment")
  local b = R.newMeters()
  R.gameWin(b, "tile", "normal")
  T.eq(b.enjoyment, 30, "an easy or normal Tile Puzzle gives 30")
  R.gameWin(b, "tile", "hard")
  T.eq(b.enjoyment, 110, "a hard one gives 80")
end

-- ------- milestones and hints

T.eq(R.danceCrossed(49, 50), 2, "crossing 50 dances with two cries")
T.eq(R.danceCrossed(249, 250), false, "250 is skipped")
T.eq(R.danceCrossed(254, 255), 3, "255 cries three times")
T.eq(R.danceCrossed(50, 51), false, "no milestone, no dance")
T.eq(#R.giftsCrossed(0, 30), 1, "25 crossed gives one gift")
T.eq(#R.giftsCrossed(20, 255), 6, "0 to 255 crosses six gift thresholds")
T.eq(R.hint({ fullness = 10, enjoyment = 40 }), "puff", "low fullness shows the puff")
T.eq(R.hint({ fullness = 40, enjoyment = 10 }), "note", "lower enjoyment shows the note")
T.eq(R.hint({ fullness = 30, enjoyment = 30 }), "puff", "a tie shows the puff")
T.eq(R.hint({ fullness = 200, enjoyment = 210 }), "orange_note", "both high shows the orange note")
T.eq(R.hint({ fullness = 100, enjoyment = 100 }), nil, "middling shows nothing")

-- ------- puffs and the jar

do
  T.eq(#R.PUFFS, 26, "26 varieties")
  T.eq(R.puffName("puff/mint_frosted"), "Frosted Mint Poke Puff", "names")
  T.eq(R.puffName("puff/supreme_fall"), "Supreme Autumn Poke Puff", "the game calls the fall puff Autumn")
  R.textPuffName = function(id) if id == "puff/mint_frosted" then return "Frosted Mint Poké Puff" end end
  T.eq(R.puffName("puff/mint_frosted"), "Frosted Mint Poké Puff", "the text hook wins")
  T.eq(R.puffName("puff/sweet_basic"), "Sweet Poke Puff", "...and falls back")
  R.textPuffName = nil
  T.eq(R.PUFF_BY_ID["puff/supreme_wish"].affection, 10, "Wish gives +10")
  T.eq(R.PUFF_BY_ID["puff/supreme_summer"].affection, 6, "a seasonal supreme gives +6")
  T.eq(R.PUFF_BY_ID["puff/sweet_deluxe"].affection, 5, "deluxe +5")
  local jar = {}
  R.jarAdd(jar, "puff/sweet_basic"); R.jarAdd(jar, "puff/mint_basic"); R.jarAdd(jar, "puff/sweet_basic")
  T.eq(R.jarTotal(jar), 3, "three in the jar")
  T.eq(R.jarCount(jar, "puff/sweet_basic"), 2, "two sweet")
  local owned = R.ownedPuffs(jar)
  T.eq(#owned, 2, "two varieties owned")
  T.eq(owned[1].id, "puff/sweet_basic", "...catalogue order")
  T.eq(owned[1].count, 2, "...with counts")
  T.eq(R.jarTake(jar, "puff/mint_basic"), true, "a puff comes out")
  T.eq(R.jarTake(jar, "puff/mint_basic"), false, "...only while there is one")
  for _ = 1, 120 do R.jarAdd(jar, "puff/spice_basic") end
  T.eq(#jar, 100, "the jar caps at 100")
  T.eq(jar[1], "puff/spice_basic", "...dropping the oldest first")
  local mig = R.migrateJar({ plain = 7 })
  T.eq(#mig, 7, "a v1 pile becomes seven puffs")
  T.eq(mig[1], "puff/sweet_basic", "...spread over the basics")
  local mig2 = R.migrateJar({ ["puff/mocha_fancy"] = 2, ["puff/sweet_basic"] = 1 })
  T.eq(#mig2, 3, "v1 counts become a list")
  T.eq(R.migrateJar(nil)[1], nil, "no old jar gives an empty one")
  local seq = { 0.0, 0.999, 0.5 }
  local n = 0
  local rng = function() n = n + 1; return seq[n] end
  T.eq(R.randomPuff(rng), "puff/sweet_basic", "rng 0 is the first basic")
  T.eq(R.randomPuff(rng), "puff/supreme_winter", "rng ~1 is the last seasonal supreme")
  local g = R.grantPuffs({}, 5, function() return 0 end)
  T.eq(#g, 5, "five granted")
end

-- ------- feeding

do
  local m = R.newMeters()
  local jar = { "puff/sweet_basic", "puff/mocha_deluxe" }
  local ok, hearts = R.feed(m, jar, "puff/sweet_basic", 25)
  T.eq(ok, true, "a basic puff is eaten")
  T.eq(hearts, 2, "...for +2 affection")
  T.eq(m.fullness, 50, "...and +50 fullness")
  T.eq(#jar, 1, "...out of the jar")
  ok, hearts = R.feed(m, jar, "puff/mocha_deluxe", 25)
  T.eq(hearts, 5, "a deluxe puff is +5")
  T.eq(m.puffsEaten, 2, "two eaten")
  local why
  ok, why = R.feed(m, jar, "puff/mocha_deluxe", 25)
  T.eq(why, "none", "none left")
  m.fullness = 255
  ok, why = R.canFeed(m, 25)
  T.eq(why, "full", "a full Pokemon turns away")
  ok, why = R.canFeed(R.newMeters(), 11)
  T.eq(why, "cannot", "Metapod cannot eat")
  T.eq(R.canPet(218), false, "Slugma cannot be petted")
  T.eq(R.canPet(25), true, "Pikachu can")
  T.eq(R.bitesFor("large"), 2, "big Pokemon take two bites")
  T.eq(R.bitesFor("small"), 5, "small ones five")
  local b = R.newMeters()
  T.eq(R.bite(b, 5), 10, "a bite of a five-biter is +10 fullness")
  T.eq(R.bite(b, 2), 24, "...of a two-biter +24")
  local c = R.newMeters()
  R.bite(c, 3); R.bite(c, 3)
  local a = R.finishPuff(c, "puff/sweet_frosted", 2, 3)
  T.eq(c.fullness, 50, "finishing after two credited bites lands on +50 total")
  T.eq(a, 3, "...and the frosted +3")
  T.eq(R.bitePace({ fullness = 100 }, 3), "quick", "quick bites below 198")
  T.eq(R.bitePace({ fullness = 200 }, 3), "slow_late", "198..213 slows late bites")
  T.eq(R.bitePace({ fullness = 200 }, 2), "quick", "...not for two-biters")
  T.eq(R.bitePace({ fullness = 220 }, 2), "slow", "above 213 every bite is slow")
end

-- ------- evidence: every number has a row saying where it comes from

do
  local missing = {}
  for _, p in ipairs(R.leafPaths()) do
    if not R.evidenceFor(p) then missing[#missing + 1] = p end
  end
  T.eq(#missing, 0, "every value in data/amie_rules.lua has an evidence row (" .. table.concat(missing, ", ") .. ")")
  local classes = { verified = true, measured = true, inferred = true, placeholder = true }
  local bad = {}
  for path, row in pairs(N.EVIDENCE) do
    if not classes[row.class] or type(row.source) ~= "string" or row.source == "" then bad[#bad + 1] = path end
  end
  T.eq(#bad, 0, "rows carry a class and a source (" .. table.concat(bad, ", ") .. ")")
  T.eq(R.evidenceFor("GAME.PARTICIPANTS").class, "verified", "three participants: the game's text")
  T.eq(R.evidenceFor("PET.STEP_PX").class, "placeholder", "stroke length on this screen is ours")
  T.eq(R.evidenceFor("PET.normal").class, "verified", "a nested path inherits its group's row")
end

T.finish("play_nav amie rules")
