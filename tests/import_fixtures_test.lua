-- The pure-Lua reader chain over a synthetic card image (tests/fixtures/mini.cci,
-- made by tools/make_fixtures.py from hand-made pixels): NCSD/NCCH/RomFS walk,
-- GARC tables, LZ11, CLIM discovery in a pack, and every pixel of several
-- texture formats. Run from the engine root:
--   luajit mods/play_nav/tests/import_fixtures_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end

local Ctr = loadFile("mods/play_nav/src/import/ctr.lua")
local Garc = loadFile("mods/play_nav/src/import/garc.lua")
local Lz = loadFile("mods/play_nav/src/import/lz.lua")
local Bclim = loadFile("mods/play_nav/src/import/bclim.lua")
local expected = loadFile("mods/play_nav/tests/fixtures/expected.lua")

local f = assert(io.open("mods/play_nav/tests/fixtures/mini.cci", "rb"))
local image = f:read("*a")
f:close()
T.eq(#image, expected.imageSize, "the fixture image has the recorded size")

local reads = 0
local function read(offset, length)
  reads = reads + 1
  local s = image:sub(offset + 1, offset + length)
  assert(#s == length, "short read")
  return s
end

local function hex(s)
  return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

-- ------- containers

local fs, err = Ctr.open(read)
T.check(fs ~= nil, "the synthetic NCSD opens (" .. tostring(err) .. ")")
local listing = fs:list("a/0/4")
T.eq(#listing, 3, "a/0/4 lists three files")
local _, zeroLen = fs:file("a/0/4/2")
T.eq(zeroLen, 0, "the zero-length file is reported as such")
local off3, len3 = fs:file("a/0/4/3")
T.eq(read(off3, len3), "second file", "a plain file reads back")
T.eq(select(2, fs:file("a/0/4/9")), "no file a/0/4/9", "a missing file is named")

local aOff, aLen = fs:file(expected.archive)
T.check(aOff ~= nil, "the archive is found")
local g, gerr = Garc.open(read, aOff, aLen)
T.check(g ~= nil, "the GARC opens (" .. tostring(gerr) .. ")")
T.eq(g.count, #expected.entries, "every entry is listed")

-- ------- LZ11 round trip and bad input

T.eq(select(2, Lz.decode("plain")), false, "non-LZ input passes through")
T.eq(Lz.decode("plain"), "plain", "...unchanged")
T.eq(select(2, Lz.decode("\17\0\0\0junk")), false, "a zero-size header is treated as raw")

-- ------- textures

for _, e in ipairs(expected.entries) do
  local bytes, berr = g:bytes(e.entry, 0)
  T.check(bytes ~= nil, ("entry %d readable (%s)"):format(e.entry, tostring(berr)))
  local blob, compressed = Lz.decode(bytes)
  T.eq(compressed, e.compressed, ("entry %d: compression detected as recorded"):format(e.entry))
  local clims = Bclim.find(blob)
  T.check(#clims >= 1, ("entry %d: a CLIM is found"):format(e.entry))
  local img, derr = Bclim.decode(blob:sub(clims[1].start, clims[1].stop))
  T.check(img ~= nil, ("entry %d decodes (%s)"):format(e.entry, tostring(derr)))
  if img then
    T.eq(img.format, e.fmt, ("entry %d: format %s"):format(e.entry, e.fmt))
    T.eq(img.w .. "x" .. img.h, e.w .. "x" .. e.h, ("entry %d: size"):format(e.entry))
    T.eq(hex(img.rgba), e.rgba, ("entry %d: every pixel matches the reference (%s)"):format(e.entry, e.fmt))
  end
  if e.second then
    T.eq(#clims, 2, ("entry %d: the pack holds two CLIMs"):format(e.entry))
    local img2 = Bclim.decode(blob:sub(clims[2].start, clims[2].stop))
    T.check(img2 ~= nil, "the second CLIM decodes")
    if img2 then T.eq(hex(img2.rgba), e.second.rgba, "...pixel for pixel") end
  end
end

-- ------- header rejection

T.eq(select(2, Bclim.decode("short")), "too small for a CLIM trailer", "a short blob is refused")
T.eq(select(2, Bclim.decode(("x"):rep(0x28))), "CLIM/imag magic missing", "a wrong trailer is refused")
T.check(reads > 0, ("the walk used %d bounded reads"):format(reads))

T.finish("play_nav import fixtures")
