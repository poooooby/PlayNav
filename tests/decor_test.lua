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

-- the drawer's categories (Bulbapedia's 22, the game's order)
T.eq(#D.CATEGORY_ORDER, 22, "22 Décor categories")
T.eq(D.drawerCategory(D.get("cushion/pink_egg_cushion")), "Color", "set A is Color")
T.eq(D.drawerCategory(D.get("cushion/polka_dot_candy_cushion")), "Pattern", "set B is Pattern")
T.eq(D.drawerCategory(D.get("cushion/orange_cloud_cushion")), "Cloud", "set C is Cloud")
T.eq(D.drawerCategory(D.get("object/wooden_bed")), "Classy", "set F is Classy")
T.eq(D.drawerCategory(D.get("cushion/leaf_cushion")), "Grass", "a type set goes by its type")
do
  local seen = {}
  for _, r in ipairs(D.ITEMS) do seen[D.drawerCategory(r)] = true end
  local n, unknown = 0, nil
  for c in pairs(seen) do n = n + 1; if not D.CATEGORY_RANK[c] then unknown = c end end
  T.eq(n, 22, "every item falls in one of the 22")
  T.eq(unknown, nil, "...and nothing outside them")
  local groups = D.ownedByCategory(D.ensure({}))
  local names = {}
  for _, g in ipairs(groups) do names[#names + 1] = g.category .. #g.rows end
  T.eq(table.concat(names, " "), "Grass1 Color4 Cloud3", "the starting items: Leaf (Grass), four Egg cushions (Color), three Cloud items")
end

-- the room
local room = D.ensureRoom({}, decor)
T.eq(room.wallpaper, "wall/pink", "the room starts with pink")
T.eq(D.setWallpaper(room, decor, "wall/fire"), true, "an owned wallpaper applies")
local okW, whyW = D.setWallpaper(room, decor, "wall/water")
T.eq(whyW, "not owned", "an unowned one does not")
T.eq(D.place(room, decor, "cushion/leaf_cushion", 100, 120), true, "an owned cushion is placed")
local okP, whyP = D.place(room, decor, "object/campfire_object", 50, 100)
T.eq(whyP, "not owned", "an unowned object is refused")
-- one of each: placing takes it out of the drawer (the capture's 0, faded)
T.eq(D.inDrawer(room, decor, "cushion/leaf_cushion"), 0, "a placed cushion leaves the drawer")
T.eq(D.inDrawer(room, decor, "cushion/pink_egg_cushion"), 1, "...another is still there")
T.eq(D.inDrawer(room, decor, "object/campfire_object"), 0, "...and an unowned one never was")
local again, whyA = D.place(room, decor, "cushion/leaf_cushion", 140, 120)
T.eq(whyA, "placed", "the same cushion cannot go down twice")
local big = { owned = {} }
for _, r in ipairs(D.ITEMS) do big.owned[r.id] = true end
for i = 2, 41 do D.place(room, big, D.ITEMS[i].id, 20 + i, 100) end
T.eq(#room.items, 30, "the room holds thirty items at most")
local full, whyF = D.place(room, big, D.ITEMS[50].id, 1, 1)
T.eq(whyF, "full", "...and says so")
T.eq(D.remove(room, 30), true, "an item can be removed")
T.eq(#room.items, 29, "...leaving 29")
local idx = D.itemAt(room, 100, 118)
T.eq(idx, 1, "the leaf cushion is found under its point")
T.eq(D.move(room, 1, 60, 130), true, "...and moved")
T.eq(room.items[1].x, 60, "...to the new spot")
T.eq(D.nearestCushion(room, 60, 130).id, "cushion/leaf_cushion", "the nearest cushion is the leaf one")
do
  -- the guest seats are the visitors': a cushion there is never the Pokemon's spot
  local seated = { items = { { id = "cushion/leaf_cushion", x = D.SEATS[1].x, y = D.SEATS[1].y } } }
  T.eq(D.nearestCushion(seated, D.SEATS[1].x, D.SEATS[1].y), nil, "a cushion on a guest seat is not the Pokemon's")
  seated.items[2] = { id = "cushion/leaf_cushion", x = 60, y = 180 }
  T.eq(D.nearestCushion(seated, D.SEATS[1].x, D.SEATS[1].y).x, 60, "...one elsewhere is, however far")
end

-- the game's units and spots (customize.bclyt: seats 6t / 6v / 6x, the puff's ad)
do
  local old = { items = { { id = "cushion/leaf_cushion", x = 128, y = 106 } } }
  D.ensureRoom(old, decor)
  T.eq(old.units, "lyt", "an old room moves to the game's units")
  T.eq(old.items[1].x, 160, "...x / 0.8")
  T.eq(old.items[1].y, 150, "...(y + 14) / 0.8")
  D.ensureRoom(old, decor)
  T.eq(old.items[1].y, 150, "...once")
  local r2 = D.ensureRoom({}, decor)
  T.eq(#D.freeSeats(r2), 3, "three seats around the puff")
  local sx, sy, seat = D.snap(r2, 190, 125)
  T.eq(seat, 2, "let go near the right-hand seat, it settles there")
  T.eq(sx, 195, "...exactly on it")
  T.eq(sy, 119, "...")
  D.place(r2, decor, "cushion/leaf_cushion", sx, sy)
  T.eq(#D.freeSeats(r2), 2, "a seat with a cushion on it is taken")
  T.eq(#D.freeSeats(r2, 1), 3, "...unless that cushion is the one being moved")
  local fx, fy, none = D.snap(r2, 190, 125)
  T.eq(none, nil, "a taken seat does not pull another item")
  T.eq(fx, 190, "...it stays where it was let go")
  local ox, oy = D.snap(r2, 60, 200)
  T.eq(ox + oy, 260, "far from any seat: where it was let go")
  -- the game's DECORATE code (DllKawaigariArrange): a cushion inside a seat's 28 x 18 box takes
  -- it; on a taken seat it is pushed half a seat aside, so a seat holds one; objects ignore the
  -- seats; elsewhere the 10-unit grid inside the room; items may overlap
  local C = "cushion/leaf_cushion"     -- (on seat 2 already)
  local cushion2
  for _, r in ipairs(CATALOG) do if r.kind == "cushion" and r.id ~= C then cushion2 = r.id; break end end
  local object
  for _, r in ipairs(CATALOG) do if r.kind == "object" then object = r.id; break end end
  T.check(cushion2 and object, "the catalogue has another cushion and an object")
  local qx, qy, qseat = D.settle(r2, 158, 97, nil, cushion2)
  T.eq(qseat, 1, "a cushion inside a free seat's box takes it")
  T.eq(qx + qy, 160 + 94, "...exactly on it")
  local px, py, pseat = D.settle(r2, 197, 121, nil, cushion2)
  T.eq(pseat, nil, "a cushion on the taken right-hand seat does not take it (one per seat)")
  T.eq(px, 195 + 14, "...it is pushed half a seat to the right")
  T.eq(py, 121, "...keeping its own height")
  local lx2 = D.settle(r2, 120, 118, nil, cushion2)
  T.eq(lx2, 125, "the left-hand seat is free: it takes that one")
  local ox2, oy2, oseat = D.settle(r2, 197, 121, nil, object)
  T.eq(oseat, nil, "an object ignores the seats")
  T.eq(ox2 + oy2, 200 + 120, "...settling on the 10-unit grid, even on a seat")
  local gx, gy, gseat = D.settle(r2, 63, 197, nil, cushion2)
  T.eq(gseat, nil, "the open floor: no seat")
  T.eq(gx + gy, 60 + 200, "...on the 10-unit grid")
  local bx, by = D.settle(r2, 330, 10, nil, object)
  T.eq(bx + by, 320 + 40, "held inside the room (x 0..320, y 40..220)")
  T.check(D.isCushion(C) and not D.isCushion(object), "cushions and objects told apart by the catalogue")
  -- the wallpaper under the spots: its Poke Ball's middle (the picture's 160, 116) on the
  -- puff's spot, covering the screen
  local sc, ox, oy = D.wallPlace(240, 0)
  T.check(sc == 1 and ox == 0 and oy == 0, "3DS shape: the wallpaper 1:1, as the game draws it")
  local LHg = 230 / 0.8
  sc, ox, oy = D.wallPlace(LHg, (LHg - 240) / 2)
  T.check(math.abs(oy + 116 * sc - (116 + (LHg - 240) / 2)) < 1e-9, "Kanto Gear shape: the ring's middle on the spot")
  T.check(math.abs(ox + 160 * sc - 160) < 1e-9, "...centred across")
  T.check(oy <= 0 and oy + 240 * sc >= LHg and ox <= 0, ("...and the screen covered (scale %.3f)"):format(sc))
  T.eq(D.onPuffSpot(165, 112), true, "a puff let go near its spot lands there")
  T.eq(D.onPuffSpot(60, 200), false, "...not far away")
end

-- the puff set out
local jar = { "puff/sweet_deluxe", "puff/mint_basic" }
T.eq(D.puffOutEffect(room).stay, 0.5, "no puff: visitors stay half the time")
T.eq(D.setPuffOut(room, jar, "puff/sweet_deluxe"), true, "a deluxe puff is set out")
T.eq(#jar, 1, "...out of the jar")
T.eq(room.puffOutGroups, 4, "...for four groups")
T.eq(D.puffOutEffect(room).stay, 0.9, "...and visitors stay 90%")
T.eq(D.puffOutEffect(room).giftBonus, 150, "...with 150 added to the group's affection for the gift")
room.items = room.items or {}
local savedItems = room.items
room.items = { { id = "cushion/leaf_cushion", x = D.SEATS[1].x, y = D.SEATS[1].y } }
T.eq(D.puffOutEffect(room).stay, 1.0, "an item on a guest seat adds 10 (100 at most)")
room.items = savedItems
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
T.eq(g2.kind, "item", "with set F all owned a set F gift is still an item (it may repeat)")
local g4 = D.roll({ puffTier = "deluxe" }, decor, rng0)
T.eq(Rules.puffTier(g4.id), "deluxe", "a puff request gives a puff of its tier")
local few = { owned = {} }
local locked = false
for i = 1, 40 do
  local r = D.roll({ set = "D" }, few, function() return (i % 37) / 37 end)
  local row = D.get(r.id)
  if row and D.LOCKED[row.category] then locked = true end
end
T.eq(locked, false, "under 20 Decor owned, no Poison, Ghost or Dark Decor is given")
local g3 = D.roll({ category = "Fire" }, decor, rng0)
T.eq(D.get(g3.id).category, "Fire", "a type gift comes from that type")
T.eq(D.requestOf({ kind = "milestone", affection = 150 }).set, "E", "150 affection asks for set E")
T.eq(D.requestOf({ kind = "unlock", set = "D" }).set, "D", "an unlock carries its set")
T.eq(D.requestOf({ kind = "visitor", category = "Water" }).category, "Water", "a same-type group carries the type")

T.finish("play_nav decor")
