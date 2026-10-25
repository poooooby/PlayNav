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
  T.check(C.byId.lv2_spe.sway and C.byId.lv2_spe.sway.ay >= 9, "Aerodactyl soars (its sway, +-9.5 px every 5.4 s)")
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

-- the Balloon Bots' own sprites (tools/balloon_atlas.py): a cell for every bot of every course,
-- Mega Aggron its own, each palette parsable and in the atlas's rows
do
  local BB = loadFile("mods/play_nav/data/balloon_bots.lua")
  T.eq(BB.size, 96, "the bots' cells are 96 square")
  local missing, maxRow = {}, -1
  for _, c in ipairs(C.courses) do
    for _, list in ipairs({ c.bots, c.alphaBots or {} }) do
      for _, b in ipairs(list) do
        local key = tostring(b.national) .. (b.mega and "-mega" or "")
        local cell = BB.cells[key]
        if not cell then missing[#missing + 1] = key
        elseif cell.row > maxRow then maxRow = cell.row end
      end
    end
  end
  T.eq(#missing, 0, "every Balloon Bot has a sprite (missing: " .. table.concat(missing, ", ") .. ")")
  T.check(BB.cells["306-mega"] and BB.cells["306"] and BB.cells["306-mega"].row ~= BB.cells["306"].row,
    "Mega Aggron is its own sprite, not Aggron's")
  local okPal, n = true, 0
  for _, cell in pairs(BB.cells) do
    n = n + 1
    if #cell.pal < 1 or #cell.pal > 255 then okPal = false end
    for _, hex in ipairs(cell.pal) do if not hex:match("^%x%x%x%x%x%x%x%x$") then okPal = false end end
  end
  T.check(okPal, "every palette is 1..255 rrggbbaa colours")
  T.eq(maxRow, n - 1, "the cells fill the atlas's rows one each")
  local f = io.open("mods/play_nav/assets/balloon_bots.png", "rb")
  local png = f and f:read("*a")
  if f then f:close() end
  T.check(png ~= nil, "the atlas image is there")
  if png then
    -- the PNG header's size: 96 wide, a cell per bot tall
    local function u32(p) local a, b2, c2, d = png:byte(p, p + 3); return ((a * 256 + b2) * 256 + c2) * 256 + d end
    T.eq(u32(17), 96, "...96 wide")
    T.eq(u32(21), 96 * n, "...a cell per bot tall")
  end
end

-- every balloon carries the game's damage per hit (its course data, a/1/1/8 +0xc)
do
  local missing = {}
  for _, c in ipairs(C.courses) do
    for i, b in ipairs(c.bots) do
      if not (type(b.damage) == "number" and b.damage > 0) then missing[#missing + 1] = c.id .. "#" .. i end
    end
  end
  T.eq(#missing, 0, "every balloon has the game's damage (" .. table.concat(missing, ", ") .. ")")
  T.eq(C.byId.lv1_atk.bots[1].damage, 50, "Axew's 50")
  T.eq(C.byId.secret_06.bots[1].damage2, 2500, "Aegislash's second form 2500")
  -- the finale's line by version (GARC a/1/1/7 row 31: Omega Ruby Aron, Alpha Sapphire Larvitar)
  local fin = C.byId.secret_12
  T.eq(C.botsFor(fin, "ruby")[1].national, 304, "Ruby: Omega Ruby's Aron line")
  T.eq(C.botsFor(fin, "emerald")[1].national, 304, "Emerald: the Aron line")
  T.eq(C.botsFor(fin, "sapphire")[1].national, 246, "Sapphire: Alpha Sapphire's Larvitar line")
  T.eq(C.botsFor(fin, "leafgreen")[4].national, 248, "LeafGreen: ...to Mega Tyranitar")
  T.check(C.botsFor(fin, "leafgreen")[4].mega and C.botsFor(fin, "sapphire")[4].damage == 2500, "...its Mega, 2500 a hit")
  T.eq(C.botsFor(C.byId.lv1_hp, "sapphire")[1].national, 320, "every other course is the same in both")
  -- the attack data holds both finales, each line's species the bots'
  local GD = loadFile("mods/play_nav/data/training_attacks.lua")
  for _, v in ipairs({ { "secret_12", "sapphire" }, { "secret_12_omega", "ruby" } }) do
    local ids, bots, same = GD.courses[v[1]], C.botsFor(fin, v[2]), true
    for i, b in ipairs(bots) do same = same and GD.phases[ids[i]] and GD.phases[ids[i]].species == b.national end
    T.check(same and #ids == #bots, v[1] .. ": the attack data's phases are " .. v[2] .. "'s balloons")
  end
  -- every secret balloon's timing from its model
  local untimed = {}
  for id, ids in pairs(GD.courses) do
    if id:match("^secret") then
      for _, pid in ipairs(ids) do if not N.ATTACK.GAME.PHASE[pid] then untimed[#untimed + 1] = pid end end
    end
  end
  T.check(#untimed == 0, "every secret phase timed (" .. table.concat(untimed, " ") .. ")")
end

T.finish()
