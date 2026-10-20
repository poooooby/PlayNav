-- Haptics (src/haptics.lua): pulse lengths by kind and the HAPTICS option's level, off is
-- silent, a fast stream merges, patterns play out from update, sounds map to pulses, and an
-- event's own pulse skips its stand-in sound's.
-- Run from the engine root: luajit mods/play_nav/tests/haptics_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local option = "medium"
local mod = { options = { get = function(_, key) if key == "haptics" then return option end end } }
local H = loadFile("mods/play_nav/src/haptics.lua")(mod)
local felt = {}
H.vibrate = function(secs) felt[#felt + 1] = secs end
local function reset() for i = #felt, 1, -1 do felt[i] = nil end end
local function near(a, b) return a and math.abs(a - b) < 1e-9 end

-- the kinds, at medium
T.check(H.pulse("medium"), "a pulse is felt")
T.check(near(felt[1], H.SECONDS.medium), "...as long as its kind")
H.update(1)
-- the level scales it
option = "high"; reset(); H.pulse("medium")
T.check(near(felt[1], H.SECONDS.medium * H.LEVELS.high), "HIGH is longer")
H.update(1)
option = "low"; reset(); H.pulse("medium")
T.check(near(felt[1], H.SECONDS.medium * H.LEVELS.low), "LOW is shorter")
H.update(1)
option = "off"; reset()
T.eq(H.pulse("strong"), false, "OFF: no pulse")
T.eq(H.pattern("success"), false, "...no pattern")
H.update(1)
T.eq(#felt, 0, "...nothing felt at all")
option = nil; reset(); H.pulse("light")
T.check(near(felt[1], H.SECONDS.light), "no option set: medium")
H.update(1)

-- a fast stream merges; a stronger pulse still comes through
option = "medium"; reset()
H.pulse("tick"); H.update(0.01); H.pulse("tick"); H.update(0.01); H.pulse("tick")
T.eq(#felt, 1, "ticks closer than MIN_GAP merge into one")
H.pulse("strong")
T.eq(#felt, 2, "...a stronger pulse is not merged away")
H.update(H.MIN_GAP + 0.01); H.pulse("tick")
T.eq(#felt, 3, "...after the gap a tick is felt again")
H.update(1)

-- a pattern: its first pulse now, the rest as update reaches them
reset()
H.pattern("bad")
T.eq(#felt, 1, "a pattern's first pulse is at once")
H.update(0.05)
T.eq(#felt, 1, "...its second waits for its gap")
H.update(0.05)
T.eq(#felt, 2, "...then comes, even though it is no stronger")
H.update(1)
reset(); H.pattern("success")
for _ = 1, 30 do H.update(0.02) end
T.eq(#felt, 3, "success is three pulses")
T.check(near(felt[3], H.SECONDS.strong), "...ending strong")

-- sounds
reset(); H.update(1)
H.onSound("SE_SELECT")
T.check(near(felt[1], H.SECONDS.tick), "a menu's select sound ticks")
H.update(1); H.onSound("SE_PIN")
T.check(near(felt[2], H.SECONDS.medium), "a good hit's sound pulses medium")
H.update(1); H.onSound("SE_NOT_EFFECTIVE"); H.update(0.2)
T.eq(#felt, 4, "a miss's sound knocks twice")
H.update(1); reset()
T.eq(H.onSound("SE_SOMETHING_ELSE"), false, "an unmapped sound: nothing")
-- an event that played its own pulse skips its stand-in sound's, in that frame only
H.pulse("strong"); H.skipNextSound()
T.eq(H.onSound("SE_PIN"), false, "the stand-in sound's haptic is skipped")
H.update(1)
H.skipNextSound(); H.update(0.016)
T.check(H.onSound("SE_PIN"), "...a skip left unused does not swallow a later sound")

T.finish("play_nav haptics")
