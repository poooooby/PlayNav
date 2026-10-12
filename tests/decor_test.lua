-- The decor catalogue and rules: ownership, placement, wallpaper, puff out, gifts.
-- Run from the engine root: luajit mods/play_nav/tests/decor_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/amie_rules.lua")
local Rules = loadFile("mods/play_nav/src/amie/rules.lua")(N)
local CATALOG = loadFile("mods/play_nav/data/decor_catalog.lua")
local D = loadFile("mods/play_nav/src/amie/decor.lua")(CATALOG, Rules)

-- the catalogue
T.eq(#D.WALLS, 34, "34 wallpapers")
T.eq(#D.ITEMS, 172, "172 cushions and objects")
local cushions, objects = 0, 0
for _, r in ipairs(D.ITEMS) do if r.kind == "cushion" then cushions = cushions + 1 else objects = objects + 1 end end
T.eq(cushions, 104, "104 cushions")
T.eq(objects, 68, "68 objects")
T.eq(#D.defaults(), 11, "eleven starting items")
T.eq(D.name("cushion/leaf_cushion"), "Leaf Cushion", "names resolve")
-- the game's own list (a/0/7/3 file 110) fixed three pairs: entry 82 is the blue cushion
T.eq(D.get("cushion/blue_circle_cushion").entry, 82, "Blue Circle Cushion is entry 82")
T.eq(D.get("cushion/red_circle_cushion").entry, 83, "Red Circle Cushion 83")
T.eq(D.get("cushion/iron_cushion").entry, 132, "Iron Cushion 132")
T.eq(D.get("cushion/cast_iron_cushion").entry, 133, "Cast-Iron Cushion 133")
T.eq(D.name("object/lightbulb_object"), "Lightbulb Object", "the game's spelling")
T.eq(D.get("object/light_bulb_object"), nil, "...the old id is gone")
do
  -- a 0.3.1 save owned the old ids: they follow the rename once
  local old = { seeded = true, owned = { ["object/light_bulb_object"] = true, ["cushion/red_circle_cushion"] = true, ["cushion/leaf_cushion"] = true } }
  D.ensure(old)
  T.check(old.owned["object/lightbulb_object"] and not old.owned["object/light_bulb_object"], "owned Lightbulb renamed")
  T.check(old.owned["cushion/blue_circle_cushion"] and not old.owned["cushion/red_circle_cushion"], "the cushion the player saw (entry 82) keeps its art under its right name")
  T.check(old.owned["cushion/leaf_cushion"], "others untouched")
  T.eq(old.names, D.NAMES_VERSION, "...marked done")
  D.ensure(old)
  T.check(old.owned["cushion/blue_circle_cushion"] and not old.owned["cushion/red_circle_cushion"], "a second pass does not swap back")
  local room = { items = { { id = "cushion/iron_cushion", x = 1, y = 2 }, { id = "object/light_bulb_object", x = 3, y = 4 } }, wallpaper = "wall/pink" }
  D.ensureRoom(room, { owned = { ["wall/pink"] = true } })
  T.eq(room.items[1].id, "cushion/cast_iron_cushion", "placed items follow the rename")
  T.eq(room.items[2].id, "object/lightbulb_object", "...and the spelling")
  -- the text hook names items the game's way
  D.textName = function(id) if id == "cushion/leaf_cushion" then return "Leaf Cushion (text)" end end
  T.eq(D.name("cushion/leaf_cushion"), "Leaf Cushion (text)", "D.name prefers the game's text")
  T.eq(D.name("cushion/stump_cushion"), "Stump Cushion", "...and falls back")
  D.textName = nil
end
T.eq(D.thumbOf("wall/pink_cloud"), "thumb/pink_cloud", "a wallpaper has a thumbnail id")
T.eq(D.get("wall/chic").set, "F", "Chic is the classy set")
T.eq(D.get("object/wooden_bed").entry, 240, "the Wooden Bed is the last texture")
T.eq(#D.BY_CATEGORY.Fire, 7, "a type set has seven items: wallpaper, four cushions, two objects")
T.eq(#D.BY_SET.A, 9 * 5, "set A is nine colours x five")
T.eq(#D.BY_SET.D, 13 * 7, "set D is thirteen types x seven")

-- ownership
local decor = D.ensure({})
T.eq(D.ownedCount(decor), 11, "a fresh record owns the eleven defaults")
T.eq(D.owns(decor, "wall/pink"), true, "...the pink wallpaper among them")
T.eq(D.owns(decor, "wall/fire"), false, "...not the fire one")
T.eq(D.own(decor, "wall/fire"), true, "owning adds it")
T.eq(D.own(decor, "wall/fire"), false, "...once")
T.eq(D.own(decor, "wall/nope"), false, "unknown ids are refused")
T.eq(#D.owned(decor, "wall"), 4, "four wallpapers owned")
T.eq(#D.owned(decor, "cushion"), 6, "six cushions owned")

-- the room
local room = D.ensureRoom({}, decor)
T.eq(room.wallpaper, "wall/pink", "the room starts with pink")
T.eq(D.setWallpaper(room, decor, "wall/fire"), true, "an owned wallpaper applies")
local okW, whyW = D.setWallpaper(room, decor, "wall/water")
T.eq(whyW, "not owned", "an unowned one does not")
T.eq(D.place(room, decor, "cushion/leaf_cushion", 100, 120), true, "an owned cushion is placed")
local okP, whyP = D.place(room, decor, "object/campfire_object", 50, 100)
T.eq(whyP, "not owned", "an unowned object is refused")
for i = 1, 40 do D.place(room, decor, "cushion/pink_egg_cushion", 20 + i, 100) end
T.eq(#room.items, 30, "the room holds thirty items at most")
local full, whyF = D.place(room, decor, "cushion/leaf_cushion", 1, 1)
T.eq(whyF, "full", "...and says so")
T.eq(D.remove(room, 30), true, "an item can be removed")
T.eq(#room.items, 29, "...leaving 29")
local idx = D.itemAt(room, 100, 118)
T.eq(idx, 1, "the leaf cushion is found under its point")
T.eq(D.move(room, 1, 60, 130), true, "...and moved")
T.eq(room.items[1].x, 60, "...to the new spot")
T.eq(D.nearestCushion(room, 60, 130).id, "cushion/leaf_cushion", "the nearest cushion is the leaf one")

-- the puff set out
local jar = { "puff/sweet_deluxe", "puff/mint_basic" }
T.eq(D.puffOutEffect(room).stay, 0.5, "no puff: visitors stay half the time")
T.eq(D.setPuffOut(room, jar, "puff/sweet_deluxe"), true, "a deluxe puff is set out")
T.eq(#jar, 1, "...out of the jar")
T.eq(room.puffOutGroups, 4, "...for four groups")
T.eq(D.puffOutEffect(room).stay, 0.95, "...and visitors stay 95%")
T.eq(D.puffOutEffect(room).minSet, "B", "...with gifts from set B at least")
for _ = 1, 4 do D.puffGroupUsed(room) end
T.eq(room.puffOut, nil, "after four groups it is gone")
local okO, whyO = D.setPuffOut(room, jar, "puff/sweet_deluxe")
T.eq(whyO, "none", "no second deluxe in the jar")
D.setPuffOut(room, jar, "puff/mint_basic")
T.eq(room.puffOutGroups, 1, "a basic puff lasts one group")

-- gifts
local rng0 = function() return 0 end
local g = D.roll({ set = "F" }, decor, rng0)
T.eq(g.kind, "item", "a set F gift is an item")
T.eq(D.get(g.id).set, "F", "...from set F")
local text = D.grant(g, decor, jar)
T.check(text:find("You received the"), "granting says what arrived")
T.eq(D.owns(decor, g.id), true, "...and it is owned")
for _, r in ipairs(D.BY_SET.F) do D.own(decor, r.id) end
local g2 = D.roll({ set = "F" }, decor, rng0)
T.eq(g2.kind, "puff", "with set F complete the gift is a puff")
T.eq(Rules.puffTier(g2.id), "deluxe", "...a deluxe one")
local g3 = D.roll({ category = "Fire" }, decor, rng0)
T.eq(D.get(g3.id).category, "Fire", "a type gift comes from that type")
T.eq(D.requestOf({ kind = "milestone", affection = 150 }).set, "E", "150 affection asks for set E")
T.eq(D.requestOf({ kind = "unlock", set = "D" }).set, "D", "an unlock carries its set")
T.eq(D.requestOf({ kind = "visitor", category = "Water" }).category, "Water", "a same-type group carries the type")

T.finish("play_nav decor")
