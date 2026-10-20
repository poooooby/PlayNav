-- One still frame of a Pokemon's pic (src/stillpic.lua): a clock-driven sprite mod answers with
-- its first frame, the game's own single-frame pics pass through untouched, and the clock is
-- always put back.
-- Run from the engine root: luajit mods/play_nav/tests/stillpic_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

-- a love with a clock and no graphics (the headless loader's)
local clock = 12.34
local realLove = love
love = { timer = { getTime = function() return clock end } }
local realGetTime = love.timer.getTime

local SP = loadFile("mods/play_nav/src/stillpic.lua")({})

-- a provider that animates as g9-battle-sprites-gen3 does: the frame from the clock, one cached
-- image per frame
local frames = {}
local function animated(mon)
  local f = math.floor(love.timer.getTime() * 15) % 6
  frames[f] = frames[f] or { image = { frame = f }, w = 64, h = 64 }
  return frames[f]
end

local a = SP.get(animated, {})
T.eq(a and a.image.frame, 0, "a clock-driven provider gives its first frame")
clock = 99.9
local b = SP.get(animated, {})
T.eq(b, a, "...the same one whenever it is asked")
T.eq(love.timer.getTime, realGetTime, "the clock is put back")
T.eq(love.timer.getTime(), 99.9, "...and tells the time again")

-- the resting pose: frames grouped by opaque box, the box held longest wins (frame 0 a dip)
do
  local realBox = SP.boxKey
  local boxes = { [0] = "dip", "up", "rest", "rest", "rest", "up" }
  SP.boxKey = function(img) return boxes[img.frame] end
  local seen = {}
  local function bouncy()
    local f = math.floor(love.timer.getTime() * 8) % 6
    seen[f] = seen[f] or { image = { frame = f }, w = 64, h = 64 }
    return seen[f]
  end
  local r = SP.get(bouncy)
  T.eq(r and r.image.frame, 2, "the pose held longest, not frame 0's dip")
  T.eq(SP.get(bouncy), r, "...the same one next time")
  T.eq(love.timer.getTime, realGetTime, "...the clock put back")
  -- a provider making a new image at every call: frame 0
  local fresh = function() return { image = { frame = 0 }, w = 64, h = 64 } end
  T.eq(SP.get(fresh).image.frame, 0, "a new image at every call: frame 0")
  SP.boxKey = realBox
end

-- the game's own pic: one 64x64 frame, handed back as it is
local rom = { image = { name = "rom" }, w = 64, h = 64 }
T.eq(SP.get(function() return rom end), rom, "the game's own pic passes through untouched")

-- no pic, and a provider that fails: nil, the clock still put back
T.eq(SP.get(function() return nil end), nil, "no pic: nil")
T.eq(SP.get(function() error("boom") end), nil, "a failing provider: nil")
T.eq(love.timer.getTime, realGetTime, "...the clock put back after an error too")

-- a sheet without graphics to cut it: handed back as it is rather than failing
local sheet = { image = { getDimensions = function() return 256, 64 end }, w = 64, h = 64, frames = 4 }
T.eq(SP.get(function() return sheet end), sheet, "a sheet with no graphics to cut it comes back as it is")

-- no love.timer at all
love = {}
T.eq(SP.get(function() return rom end), rom, "no clock: the provider is still asked")

love = realLove
T.finish("play_nav stillpic")
