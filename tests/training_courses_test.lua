-- The course table: 18 regular rows with the Bulbapedia scores and EVs, 12 secret rows in
-- order, the medal targets, prizes that resolve, and every reference the simulation needs.
-- Run from the engine root: luajit mods/play_nav/tests/training_courses_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/training_rules.lua")
local C = loadFile("mods/play_nav/data/training_courses.lua")
local Items = loadFile("mods/play_nav/data/training_items.lua")
local Sim = loadFile("mods/play_nav/src/training/sim.lua")(N)

T.eq(#C.courses, 30, "thirty courses")

-- Bulbapedia "Super Training": bot (National number) and score per level and stat
local EXPECT = {
  [1] = { hp = { 320, 500 }, atk = { 610, 300 }, def = { 74, 400 }, spa = { 81, 300 }, spd = { 72, 200 }, spe = { 714, 200 } },
  [2] = { hp = { 369, 2500 }, atk = { 611, 1500 }, def = { 75, 1500 }, spa = { 82, 1500 }, spd = { 73, 1000 }, spe = { 142, 1000 } },
  [3] = { hp = { 321, 4000 }, atk = { 612, 2500 }, def = { 76, 2500 }, spa = { 462, 2500 }, spd = { 691, 2000 }, spe = { 715, 2000 } },
}
local SECRET = {
  { 4, { 699, 697 }, { 1800, 1800 } }, { 5, { 3 }, { 4000 } }, { 5, { 6 }, { 4000 } }, { 5, { 9 }, { 4000 } },
  { 5, { 618 }, { 4800 } }, { 6, { 681 }, { 4800 } }, { 6, { 407 }, { 4800 } }, { 6, { 475 }, { 5600 } },
  { 7, { 664, 665, 666 }, { 1200, 2400, 3600 } }, { 7, { 476 }, { 7200 } }, { 7, { 633, 634, 635 }, { 1600, 2400, 4800 } },
  { 8, { 304, 305, 306, 306 }, { 1600, 2400, 3200, 5600 } },
}

local ids = {}
local regular, secret = 0, 0
for _, c in ipairs(C.courses) do
  T.check(not ids[c.id], "unique id " .. c.id)
  ids[c.id] = true
  T.check(type(c.name) == "string" and #c.name > 0, c.id .. " has a name")
  local ok, err = Sim.validate(c, C)
  T.check(ok, c.id .. " validates (" .. tostring(err) .. ")")
  if c.secret then
    secret = secret + 1
    T.eq(c.secret, secret, c.id .. " is secret number " .. secret)
    local row = SECRET[secret]
    T.eq(c.level, row[1], c.id .. " level " .. row[1])
    T.eq(#c.bots, #row[2], c.id .. " has " .. #row[2] .. " bot(s)")
    for i, nat in ipairs(row[2]) do
      T.eq(c.bots[i] and c.bots[i].national, nat, c.id .. " bot " .. i .. " is #" .. nat)
      T.eq(c.bots[i] and c.bots[i].score, row[3][i], c.id .. " bot " .. i .. " pops at " .. row[3][i])
    end
    T.eq(c.stat, nil, c.id .. " gives no EVs")
    T.check(type(c.items) == "table" and #c.items > 0, c.id .. " has prizes")
    T.eq(c.medal, (secret == 9 or secret == 11) and 120 or 90, c.id .. " medal target")
    if #c.bots > 1 then T.eq(c.extraBotSecs, 30, c.id .. " adds 30 s per bot") end
  else
    regular = regular + 1
    local row = EXPECT[c.level] and EXPECT[c.level][c.stat]
    T.check(row ~= nil, c.id .. " is a known level/stat")
    T.eq(#c.bots, 1, c.id .. " has one bot")
    T.eq(c.bots[1].national, row and row[1], c.id .. " bot is #" .. tostring(row and row[1]))
    T.eq(c.bots[1].score, row and row[2], c.id .. " pops at " .. tostring(row and row[2]))
    T.eq(c.ev, c.level * 4, c.id .. " gives " .. c.level * 4 .. " EVs")
    T.eq(c.medal, c.level == 1 and 150 or 120, c.id .. " medal target")
    if c.bots[1].national <= 386 then
      T.check(type(c.bots[1].species) == "string", c.id .. " names its Gen 3 species")
    else
      T.eq(c.bots[1].species, nil, c.id .. " has no Gen 3 species")
    end
  end
end
T.eq(regular, 18, "18 regular courses")
T.eq(secret, 12, "12 secret courses")

-- the game's course order (a/0/7/3 file 44) and the official English names
do
  local seen = {}
  for _, c in ipairs(C.courses) do
    T.check(type(c.order) == "number" and c.order >= 2 and c.order <= 31 and not seen[c.order], c.id .. " has a unique game order " .. tostring(c.order))
    seen[c.order] = true
    T.eq(c.bots[1].art, ("training/stage_poke_%02d"):format(c.order), c.id .. " icon follows the order")
  end
  T.eq(C.byId.lv1_hp.order, 3, "Wailmer is the fourth entry (after the two tutorials and Magnemite)")
  T.eq(C.byId.lv1_hp.name, "Raise Your HP with Wailmer!", "the official name")
  T.eq(C.byId.lv3_def.name, "Break It! Golem's Defensive Line!", "...for Golem too")
  T.eq(C.byId.secret_01.order, 20, "the first secret course is entry 20")
  T.eq(C.byId.secret_12.order, 31, "...the last 31")
  T.check(C.byId.lv2_spe.motion and C.byId.lv2_spe.motion.bob, "Aerodactyl soars")
  T.check(C.byId.secret_10.roaming, "Probopass's goals roam")
end

-- prizes resolve to engine item names or training item slugs
do
  local slugs = {}
  for _, d in ipairs(Items) do slugs[d.slug] = true end
  for _, c in ipairs(C.courses) do
    for _, p in ipairs(c.items or {}) do
      if p.training then
        T.check(slugs[p.training], c.id .. " prize " .. p.training .. " is a training item")
      else
        T.check(type(p.item) == "string" and p.item:match("^ITEM_[A-Z_]+$"), c.id .. " prize " .. tostring(p.item) .. " is an engine item name")
      end
      T.check((p.w or 1) > 0, "a positive weight")
    end
  end
end

-- the stone cups give their stone only on a new best
do
  local leaf = C.byId.secret_02
  local stone
  for _, p in ipairs(leaf.items) do if p.item == "ITEM_LEAF_STONE" then stone = p end end
  T.check(stone and stone.bestOnly, "the Leaf Stone Cup's stone needs a new best")
  T.check(C.byId.secret_11.suddenDeath, "Hydreigon's course is sudden death")
  T.eq(C.byId.secret_06.rageAt, 2400, "Aegislash rages at 2400")
  T.eq(C.byId.secret_07.calmAt, 2400, "Roserade calms at 2400")
  T.eq(C.byId.lv2_hp.goals.chance.odds, 1.0, "Relicanth always offers the Chance Goal")
end

T.finish()
