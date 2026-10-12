-- Pure cleaning rules: rolls, the tool matrix, rub math, care rewards.
-- Run from the engine root: luajit mods/play_nav/tests/care_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end

local Care = loadFile("mods/play_nav/src/refresh/care.lua")

-- a deterministic rng: cycles through the given values
local function seq(values)
  local i = 0
  return function()
    i = i % #values + 1
    return values[i]
  end
end

-- ------- chances follow the facts

T.check(Care.chanceFor("mud", { damaged = true }) > Care.chanceFor("mud", {}),
  "damage raises the mud chance")
T.check(Care.chanceFor("dust", { wild = true, grass = true }) > Care.chanceFor("dust", { wild = true }),
  "wild grass raises dust")
T.check(Care.chanceFor("wet", { foeTypes = { "water" } }) > Care.chanceFor("wet", {}),
  "a Water-type foe raises wet, case-insensitively")
T.eq(Care.chanceFor("ruffled", { damaged = true }), Care.chanceFor("ruffled", {}),
  "ruffled is a flat chance")

-- ------- rolling

do
  T.eq(#Care.roll({ damaged = true }, "off", seq({ 0 })), 0, "frequency OFF rolls nothing")
  -- rng always 0: every kind hits, so the cap applies
  local marks = Care.roll({ damaged = true, wild = true, grass = true, water = true }, "high", seq({ 0, 0.3, 0.6 }))
  local kinds = {}
  for _, m in ipairs(marks) do kinds[m.kind] = (kinds[m.kind] or 0) + 1 end
  local distinct = 0
  for _ in pairs(kinds) do distinct = distinct + 1 end
  T.check(distinct <= Care.MAX_MARKS, "at most three kinds of mark")
  T.check(distinct >= 1, "...and at least one when everything hits")
  for _, m in ipairs(marks) do
    T.check(m.x >= -1 and m.x <= 1 and m.y >= -1 and m.y <= 1, "marks land inside the body")
    T.eq(m.amount, 1, "a fresh mark is whole")
    T.check(m.r > 0, "marks have a radius")
  end
  -- rng always 0.99: nothing hits
  T.eq(#Care.roll({ damaged = true }, "normal", seq({ 0.99 })), 0, "a high roll leaves the Pokemon clean")
end

-- ------- rubbing

do
  local marks = {
    { kind = "mud", x = 0, y = 0, r = 0.2, amount = 1 },
    { kind = "dust", x = 0.5, y = 0.5, r = 0.2, amount = 1 },
  }
  local removed = Care.rub(marks, "brush", 0, 0, 1, 1)
  T.eq(removed, 0, "the wrong tool removes nothing")
  T.eq(marks[1].amount, 1, "...and the mark is untouched")
  removed = Care.rub(marks, "towel", 0, 0, 0.5, 1)
  T.check(removed > 0.49 and removed < 0.51, "the right tool wears the mark by stroke * rate")
  T.eq(Care.allClean(marks), false, "not clean yet")
  local _, finished = Care.rub(marks, "towel", 0.05, 0.05, 1, 1)
  T.eq(#finished, 1, "finishing a mark reports it")
  T.eq(marks[1].amount, 0, "...at zero")
  T.eq(Care.remaining(marks, "mud"), 0, "no mud left")
  T.eq(Care.remaining(marks), 1, "one mark left in total")
  Care.rub(marks, "brush", 0.5, 0.5, 5, 1)
  T.eq(Care.allClean(marks), true, "brush clears the dust, all clean")
  T.eq(Care.rub(marks, "towel", 0, 0, 1, 1), 0, "rubbing a finished mark removes nothing more")
  T.eq(Care.rub(marks, "towel", 0, 0, 0, 1), 0, "no stroke, no change")
  T.eq(Care.rub(marks, "towel", 2, 2, 1, 1), 0, "rubbing far from a mark does nothing")
end

-- ------- needs

do
  local marks = { { kind = "wet", amount = 1 }, { kind = "wet", amount = 0.5 }, { kind = "mud", amount = 0 } }
  local needs = Care.needs(marks, "PSN")
  T.eq(#needs, 2, "needs lists each live kind once plus status")
  T.eq(needs[1], "wet", "...wet")
  T.eq(needs[2], "status", "...status")
  T.eq(#Care.needs({}, nil), 0, "a clean healthy Pokemon needs nothing")
end

-- ------- rewards

do
  local m = { affection = 0, enjoyment = 0 }
  Care.rewardClean(m)
  Care.rewardCure(m)
  T.eq(m.affection, Care.CLEAN_AFFECTION + Care.CURE_AFFECTION, "clean and cure rewards add up")
  T.check(m.enjoyment > 0, "...and both cheer the Pokemon up")
end

T.finish("play_nav care")
