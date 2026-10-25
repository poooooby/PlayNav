-- Any decrypted dump of Alpha Sapphire: the containers ctr.lua opens (card image, CIA, bare
-- NCCH; a CIA and an NCCH are built here from tests/fixtures/mini.cci, nothing ROM-derived),
-- CRC-32 against zlib's, the extract job skipping a row whose bytes differ from the recipe's
-- fingerprint, every recipe row having one, and - when the real dump is on this machine -
-- every fingerprint recomputed from it. Run from the engine root:
--   luajit mods/play_nav/tests/fingerprint_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local ROOT = "mods/play_nav/"
local function slurp(path)
  local f = assert(io.open(ROOT .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local function module(path) return assert(load(slurp(path), "@" .. path))() end

local Ctr = module("src/import/ctr.lua")
local Zstd = module("src/import/zstd.lua")
local Crc = module("src/import/crc32.lua")
local F = module("src/import/fingerprint.lua")
local Recipe = module("data/oras_recipe.lua")
local Prints = module("data/oras_fingerprints.lua")
local expected = module("tests/fixtures/expected.lua")

-- ------- CRC-32 (zlib.crc32's values)

T.eq(Crc.of("123456789"), "cbf43926", "the CRC-32 check value")
T.eq(Crc.of(""), "00000000", "the empty string")
T.eq(Crc.of("a"), "e8b7be43", "one byte")
local long = ("abcdefghij"):rep(1000) .. "xyz"
T.eq(Crc.ofRange(function(o, n) return long:sub(o + 1, o + n) end, 0, #long, 777), Crc.of(long),
  "a range read in pieces hashes as the whole")

-- ------- containers

local cci = slurp("tests/fixtures/mini.cci")
local function u32(s, p) local a, b, c, d = s:byte(p, p + 3); return a + b * 256 + c * 65536 + d * 16777216 end
local function le32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
local function be32(v) return string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256) end
local function pad(s, n) return s .. ("\0"):rep(n - #s) end

local p0 = u32(cci, 0x121) * 0x200
local p0len = u32(cci, 0x125) * 0x200
local ncch = cci:sub(p0 + 1, p0 + p0len)

-- a CIA: header, cert chain, ticket, TMD (RSA-2048 signature, one content chunk), content 0
local function cia(encrypted)
  local certSize, ticketSize = 0x40, 0x40
  local tmdSize = 0x140 + 0xC4 + 0x900 + 0x30
  local header = pad(le32(0x2020) .. "\0\0\0\0" .. le32(certSize) .. le32(ticketSize) .. le32(tmdSize)
    .. le32(0) .. le32(#ncch) .. le32(0), 0x2040)
  local chunk = pad(be32(0) .. "\0\0" .. (encrypted and "\0\1" or "\0\0") .. be32(0) .. be32(#ncch), 0x30)
  local tmd = pad(pad(be32(0x10004), 0x140) .. ("\0"):rep(0xC4 + 0x900) .. chunk, 0xB40)
  return header .. ("C"):rep(certSize) .. ("T"):rep(ticketSize) .. tmd .. ncch
end

local function opener(image)
  return function(offset, length)
    local s = image:sub(offset + 1, offset + length)
    assert(#s == length, "short read")
    return s
  end
end

local function archiveBytes(image)
  local read = opener(image)
  local fs, err = Ctr.open(read)
  if not fs then return nil, err end
  local off, len = fs:file(expected.archive)
  return read(off, len), fs.kind
end

local fromCci, kind = archiveBytes(cci)
T.eq(kind, "cci", "a card image opens as one")
local fromCia, ciaKind = archiveBytes(cia(false))
T.eq(ciaKind, "cia", "a decrypted CIA opens")
T.eq(fromCia, fromCci, "a CIA's first content reads the same archive")
local fromNcch, ncchKind = archiveBytes(ncch)
T.eq(ncchKind, "ncch", "a bare NCCH opens")
T.eq(fromNcch, fromCci, "a bare NCCH reads the same archive")
local _, encErr = Ctr.open(opener(cia(true)))
T.check(tostring(encErr):find("encrypted CIA", 1, true) ~= nil, "a title-key encrypted CIA is refused by name")
local _, junkErr = Ctr.open(opener(("\0"):rep(0x4000)))
T.check(tostring(junkErr):find("not a 3DS", 1, true) ~= nil, "a file of another kind is refused by name")

-- ------- the extract job over the fixture: matching rows extract, differing rows are skipped

local sources = {}
for _, name in ipairs({ "lz", "garc", "ctr", "bclim", "crc32" }) do sources[name] = slurp("src/import/" .. name .. ".lua") end
local jobSrc = slurp("src/import/job_extract.lua")

local function runJob(image, items, verify)
  local read = opener(image)
  local written = {}
  local env = setmetatable({
    job = {
      imports = { read = function(_, _, o, n) return read(o, n) end },
      cache = { write = function(_, path, bytes) written[path] = bytes; return true end },
    },
  }, { __index = _G })
  local chunk = assert(load(jobSrc, "=job_extract", "t", env))
  local out = chunk({ importId = "oras_cci", archive = expected.archive, items = items, modules = sources,
    outPrefix = "raw/", verify = verify, differs = F.DIFFERS, missingFp = F.MISSING })
  local byId = {}
  for _, r in ipairs(out.results) do byId[r.id] = r end
  return byId, written
end

-- the fixture's blobs as the job reads them, before LZ
local Garc = module("src/import/garc.lua")
local readCci = opener(cci)
local fsCci = Ctr.open(readCci)
local aOff, aLen = fsCci:file(expected.archive)
local g = Garc.open(readCci, aOff, aLen)
local function fpOf(entry)
  local b = g:bytes(entry, 0)
  return { size = #b, crc = Crc.of(b) }
end

local e0, e1 = expected.entries[1], expected.entries[2]
local function items(fp0, fp1)
  return {
    { entry = e0.entry, sub = 0, clim = 0, id = "t/e0", w = e0.w, h = e0.h, fmt = e0.fmt, fp = fp0 },
    { entry = e1.entry, sub = 0, clim = 0, id = "t/e1", w = e1.w, h = e1.h, fmt = e1.fmt, fp = fp1 },
  }
end

for _, case in ipairs({ { "card image", cci }, { "CIA", cia(false) }, { "bare NCCH", ncch } }) do
  local res = runJob(case[2], items(fpOf(e0.entry), fpOf(e1.entry)), true)
  T.check(res["t/e0"].ok and res["t/e1"].ok, "matching rows extract from a " .. case[1])
end

local wrong = fpOf(e1.entry)
wrong = { size = wrong.size, crc = wrong.crc == "00000000" and "00000001" or "00000000" }
local res, written = runJob(cci, items(fpOf(e0.entry), wrong), true)
T.check(res["t/e0"].ok, "a matching row still extracts beside a differing one")
T.eq(res["t/e1"].ok, false, "a row whose bytes differ is skipped")
T.eq(res["t/e1"].err, F.DIFFERS, "and says why")
T.eq(written["raw/t/e1.rgba"], nil, "nothing is written for it")
T.check(written["raw/t/e0.rgba"] ~= nil, "the matching row is written")

local short = fpOf(e0.entry)
res = runJob(cci, items({ size = short.size + 1, crc = short.crc }, fpOf(e1.entry)), true)
T.eq(res["t/e0"].err, F.DIFFERS, "a size that differs is caught before the hash")

res = runJob(cci, items(nil, fpOf(e1.entry)), true)
T.eq(res["t/e0"].err, F.MISSING, "a row with no fingerprint is not trusted")

res = runJob(cci, items(nil, wrong), false)
T.check(res["t/e0"].ok and res["t/e1"].ok, "with verify off every row extracts as before")

-- ------- the table covers the recipe

T.eq(Prints.recipe, Recipe.version, "the fingerprints are for this recipe version")
local missing = 0
for _, item in ipairs(Recipe.assets) do
  if not Prints.rows[F.key(item)] then
    missing = missing + 1
    if missing <= 5 then print("no fingerprint for " .. item.id .. " (" .. F.key(item) .. ")") end
  end
end
T.eq(missing, 0, "every recipe row has a fingerprint")

-- ------- the real dump, when present: every fingerprint recomputed

local rom = io.open(os.getenv("ORAS_CCI") or (ROOT .. "baseroms/alpha_sapphire_rev2.cci"), "rb")
if not rom then
  print("SKIP fingerprint_test real dump: not present")
else
  local function read(offset, length)
    rom:seek("set", offset)
    local s = rom:read(length)
    assert(s and #s == length, "short read")
    return s
  end
  -- (Azahar's compressed image: the card image inside it, as the job reads it)
  if Zstd.isZ3ds(read) then read = assert(Zstd.wrap(read)) end
  local fs = assert(Ctr.open(read))
  local garcs, bad, n = {}, 0, 0
  for key, want in pairs(Prints.rows) do
    n = n + 1
    local archive, entry, sub = key:match("^(.-):(%d+):(%d+)$")
    local size, crc
    if archive then
      local off, len = assert(fs:file(archive))
      garcs[archive] = garcs[archive] or assert(Garc.open(read, off, len))
      local b = assert(garcs[archive]:bytes(tonumber(entry), tonumber(sub)))
      size, crc = #b, Crc.of(b)
    else
      local off, len = assert(fs:file(key))
      size, crc = len, Crc.ofRange(read, off, len)
    end
    if size ~= want.size or crc ~= want.crc then
      bad = bad + 1
      print(("differs: %s %d %s, table %d %s"):format(key, size, crc, want.size, want.crc))
    end
  end
  rom:close()
  T.eq(bad, 0, ("all %d fingerprints match the Rev 2 dump"):format(n))
end

T.finish("play_nav fingerprints")
