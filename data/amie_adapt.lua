-- Pokemon-Amie's minigame pictures the sprite pages do not carry, made from ones PlayNav's
-- atlases do (src/amie/adapt_art.lua): `from` another picture as it is, or `crop` a part of it,
-- `tint` it (each channel multiplied), `grey` it (its light alone, then the tint), or `fill` a
-- plain colour. The reward icons are the Poke
-- Puffs themselves (get00..get25: basic, frosted, fancy, deluxe in sweet, mint, citrus, mocha,
-- spice order, then the six supremes); Head It's and Tile Puzzle's stamps are Berry Picker's; its gold points star
-- and the joining Pokemon's pink stars are Berry Picker's star tinted (the sparkles are drawn:
-- src/amie/ui_art.lua); its thin clouds are Berry Picker's cloud and its grass a
-- slice of Berry Picker's.

local A = {}

local FLAVORS = { "sweet", "mint", "citrus", "mocha", "spice" }
local TIERS = { "basic", "frosted", "fancy", "deluxe" }
local SUPREME = { "wish", "honor", "spring", "summer", "fall", "winter" }
for _, game in ipairs({ "berry", "head", "tile" }) do
  for t, tier in ipairs(TIERS) do
    for f, flavor in ipairs(FLAVORS) do
      A[("lyt/%s/get%02d"):format(game == "tile" and "tile_down" or game .. "_reward", (t - 1) * 5 + f - 1)] = { from = "puff/" .. flavor .. "_" .. tier }
    end
  end
  for i, s in ipairs(SUPREME) do
    A[("lyt/%s/get%02d"):format(game == "tile" and "tile_down" or game .. "_reward", 19 + i)] = { from = "puff/supreme_" .. s }
  end
end

A["lyt/head_front/stamp"] = { from = "lyt/berry_score/stamp" }
A["lyt/tile_up/stamp"] = { from = "lyt/berry_score/stamp" }
-- DECORATE's return is the room's (drawn: src/amie/ui_art.lua)
A["lyt/amie_deco/button_back"] = { from = "lyt/amie_room/button_back" }
-- the points star is gold, the joining Pokemon's stars pink
A["lyt/head_down/star"] = { from = "lyt/berry_balloon/balloon_star", tint = { 0.96, 0.81, 0.34 } }
A["lyt/head_effect/star"] = { from = "lyt/berry_balloon/balloon_star", tint = { 0.96, 0.81, 0.34 } }
A["lyt/head_down/star_appear"] = { from = "lyt/berry_balloon/balloon_star", tint = { 0.9, 0.43, 0.95 } }
-- the thin clouds drifting over Head It's sky
for _, id in ipairs({ "lyt/head_bg/cloud_02", "lyt/head_bg/cloud_04", "lyt/head_rear/cloud_02", "lyt/head_rear/cloud_04" }) do
  A[id] = { from = "lyt/berry_rear/01_cloud" }
end
-- a tuft of grass: the left 80 units of Berry Picker's
A["lyt/head_prior/grass01"] = { from = "lyt/berry_rear/grass", crop = { 0, 33, 80, 36 } }
-- Head It's grey yarn stand-ins: a yarn ball greyed
A["lyt/head_ball/dummy00"] = { from = "lyt/head_ball/ball00_00", grey = true, tint = { 1.15, 1.15, 1.15 } }
A["lyt/head_front/ball"] = { from = "lyt/head_ball/ball00_00", grey = true, tint = { 1.15, 1.15, 1.15 } }
-- PLAY's floating hearts and notes and the top screen's affection and enjoyment icons are the
-- room's drawn heart and notes
A["fx/heart"] = { from = "lyt/amie_room/heart_00" }
A["fx/note"] = { from = "lyt/amie_room/ic_asobu" }
A["ui/icon_heart"] = { from = "lyt/amie_room/particle_01" }
A["ui/icon_note"] = { from = "lyt/amie_room/talk_onpu" }
-- Berry Picker's sky is plain white
A["lyt/berry_rear/sky"] = { fill = { 1, 1, 1, 1 }, w = 2, h = 2 }

return A
