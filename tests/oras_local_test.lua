-- The full in-game chain against the real Alpha Sapphire dump, when it is on
-- this machine: card image -> NCSD/NCCH/RomFS (ctr.lua) -> GARC (garc.lua)
-- -> LZ11 (lz.lua) -> BCLIM (bclim.lua) -> RGBA, checked against the MD5s
-- the Python pipeline wrote (tools/discover.py -> results.lua). Skips
-- cleanly when the dump or the results are absent, so CI never needs ROM
-- bytes. Run from the engine root:
--   ORAS_CCI="<path to .cci>" ORAS_RESULTS="<sheets dir>/results.lua" \
--   luajit mods/play_nav/tests/oras_local_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local StreamMD5 = require("src.mods.StreamMD5")

local cci = os.getenv("ORAS_CCI")
  or "C:/Users/Collin/Downloads/Pokemon Alpha Sapphire (USA) (En,Ja,Fr,De,Es,It,Ko) (Rev 2)/Pokemon Alpha Sapphire (USA) (En,Ja,Fr,De,Es,It,Ko) (Rev 2).cci"
local resultsPath = os.getenv("ORAS_RESULTS")
  or "C:/Users/Collin/Documents/oras-extract/sheets_amie/results.lua"

local function loadFile(path)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end

local rom = io.open(cci, "rb")
local resultsChunk = io.open(resultsPath, "rb")
if not rom or not resultsChunk then
  print("SKIP oras_local_test: dump or results.lua not present")
  T.finish("play_nav oras local (skipped)")
  return
end
resultsChunk:close()
local results = loadFile(resultsPath)

local Ctr = loadFile("mods/play_nav/src/import/ctr.lua")
local Garc = loadFile("mods/play_nav/src/import/garc.lua")
local Lz = loadFile("mods/play_nav/src/import/lz.lua")
local Bclim = loadFile("mods/play_nav/src/import/bclim.lua")

local reads = 0
local function read(offset, length)
  reads = reads + 1
  rom:seek("set", offset)
  local data = rom:read(length)
  assert(data and #data == length, ("short read at 0x%x"):format(offset))
  return data
end

local fs, err = Ctr.open(read)
T.check(fs ~= nil, "the card image opens (" .. tostring(err) .. ")")
if not fs then T.finish("play_nav oras local") return end

-- the RomFS walk finds the archives and the empty file ctrtool tripped on
local off, len = fs:file("a/0/4/3")
T.check(off ~= nil and len == 44140, "a/0/4/3 (Amie hand UI) is found with the size the dump shows")
local _, zero = fs:file("a/0/8/7")
T.eq(zero, 0, "a/0/8/7 is the zero-length file")
local listing = fs:list("a/0/4")
T.check(listing and #listing >= 10, "a/0/4 lists its archives")

-- pick a spread of textures: every format at least a few times, cap the total
local perFormat, picked = {}, {}
for _, r in ipairs(results) do
  perFormat[r.format] = (perFormat[r.format] or 0) + 1
  if perFormat[r.format] <= 6 then picked[#picked + 1] = r end
end
T.check(#picked >= 20, ("%d textures picked across formats"):format(#picked))

local garcs = {}
local okCount, total = 0, 0
local function md5(s)
  local h = StreamMD5.new()
  for i = 1, #s, 1024 * 1024 do h:update(s:sub(i, i + 1024 * 1024 - 1)) end
  return h:final()
end

for _, r in ipairs(picked) do
  total = total + 1
  local g = garcs[r.archive]
  if not g then
    local aOff, aLen = fs:file(r.archive)
    g = assert(Garc.open(read, aOff, aLen))
    garcs[r.archive] = g
  end
  local bytes, berr = g:bytes(r.entry, r.sub)
  if not bytes then
    T.check(false, ("%s entry %d/%d readable: %s"):format(r.archive, r.entry, r.sub, tostring(berr)))
  else
    local blob, compressed = Lz.decode(bytes)
    T.eq(compressed, r.compressed, ("%s %d/%d: LZ state matches the dump"):format(r.archive, r.entry, r.sub))
    local clim = blob and blob:sub(r.clim_start + 1, r.clim_end)
    local img, derr = clim and Bclim.decode(clim)
    if not img then
      T.check(false, ("%s %d/%d decodes: %s"):format(r.archive, r.entry, r.sub, tostring(derr)))
    else
      local same = img.w == r.w and img.h == r.h and img.format == r.format and md5(img.rgba) == r.md5
      if same then okCount = okCount + 1 end
      T.check(same, ("%s %d/%d %s %dx%d matches the Python pipeline"):format(
        r.archive, r.entry, r.sub, r.format, r.w, r.h))
    end
  end
end
print(("decoded %d/%d textures identically; %d image reads"):format(okCount, total, reads))
rom:close()
T.finish("play_nav oras local")
