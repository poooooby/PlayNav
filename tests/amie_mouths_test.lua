-- data/amie_mouths.lua (tools/amie_mouths.py): where each species' mouth is on its front picture,
-- for PLAY's feeding - every National Dex number to 1025, inside the picture's box, with the side
-- its head leans to.
-- Run from the engine root: luajit mods/play_nav/tests/amie_mouths_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local M = assert(loadfile("mods/play_nav/data/amie_mouths.lua"))()

local n, bad = 0, {}
for dex = 1, 1025 do
  local m = M[dex]
  if m then
    n = n + 1
    if not (#m == 3 and m[1] >= 0 and m[1] <= 1 and m[2] >= 0 and m[2] <= 1 and m[3] >= 0 and m[3] <= 1) then
      bad[#bad + 1] = dex
    end
  end
end
T.eq(n, 1025, "every species 1..1025 has a mouth")
T.eq(#bad, 0, "each inside its picture's box, with a head side (" .. table.concat(bad, ",") .. ")")
-- a few read by eye: Pidgey's beak on its left, Squirtle's smile in the upper middle
T.check(M[16][1] < 0.25, "Pidgey's beak is at its left")
T.check(M[7][2] < 0.5, "Squirtle's mouth is in its upper half")

T.finish("play_nav amie mouths")
