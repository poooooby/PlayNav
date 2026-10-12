-- Petting zones and the per-species table.
-- Run from the engine root: luajit mods/play_nav/tests/petting_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local DATA = loadFile("mods/play_nav/data/petting_gen3.lua")
local P = loadFile("mods/play_nav/src/amie/petting.lua")(DATA)

-- the table covers every Gen 3 species
local n = 0
for k in pairs(DATA) do n = n + 1 end
T.eq(n, 386, "386 species in the petting table")
local known = {}
for _, z in ipairs(P.ZONES) do known[z] = true end
known.all = true
local bad = 0
for k, r in pairs(DATA) do
  if (r[1] and not known[r[1]]) or (r[2] and not known[r[2]]) or (r[4] and not known[r[4]]) then bad = bad + 1 end
end
T.eq(bad, 0, "every zone in the table is a known zone")

-- zones over the body
T.eq(P.zoneAt(0, -0.9), "head", "the top of the ellipse is the head")
T.eq(P.zoneAt(0, -0.3), "face", "the upper middle is the face")
T.eq(P.zoneAt(0.5, -0.3), "cheeks", "beside the face are the cheeks")
T.eq(P.zoneAt(0, 0), "chest", "the centre is the chest")
T.eq(P.zoneAt(0, 0.45), "belly", "below it the belly")
T.eq(P.zoneAt(0.6, 0.05), "side", "the flanks are the side")
T.eq(P.zoneAt(0.7, 0.45), "limbs", "low and wide are the limbs")
T.eq(P.zoneAt(0, 0.9), "bottom", "the bottom is the tail")
for z, pt in pairs(P.ZONE_POINT) do
  T.eq(P.zoneAt(pt[1], pt[2]), z, "the representative point of " .. z .. " is inside it")
end

-- species
T.eq(P.spot(25, "chest"), "favored", "Pikachu likes under the chin")
T.eq(P.spot(25, "belly"), "disfavored", "...and not its stomach")
local kind, eff = P.spot(25, "cheeks")
T.eq(kind, "effect", "...and its cheeks shock")
T.eq(eff, "paralyzing", "...paralyzing")
T.eq(P.spot(4, "bottom"), "effect", "Charmander's tail burns")
T.eq(P.spot(4, "head"), "favored", "...but it likes its head")
T.eq(P.spot(4, "face"), "disfavored", "...not its nostrils")
T.eq(P.spot(218, "face"), "effect", "Slugma burns everywhere")
T.eq(P.spot(218, "bottom"), "effect", "...everywhere")
T.eq(P.spot(378, "head"), "effect", "Regice freezes everywhere")
T.eq(P.spot(44, "head"), "favored", "Gloom likes its front petal")
local k2, e2 = P.spot(44, P.row(44)[4])
T.eq(e2 == "slimy" and k2 == "normal", true, "...and its drool is slimy but still pettable")
T.eq(P.spot(9999, "head"), "normal", "an unknown species is neutral everywhere")
T.eq(P.spotAt(25, 0, 0.05), "favored", "spotAt maps the point to the zone")
local d = P.describe(255)
T.eq(d.favored, "Neck feathers", "Torchic's favored text is kept")
T.eq(d.disfavored, "Head feathers", "...and the disfavored one")

T.finish("play_nav petting")
