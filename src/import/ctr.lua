-- Decrypted 3DS image reader: card image (NCSD partition 0), CIA (first
-- content) or bare NCCH -> RomFS (IVFC level 3) -> path lookup. Pure Lua; reads only headers and the metadata
-- tables through a read(offset, length) closure, so it works over
-- mod.imports:read and inside a mod.job worker. Twin of tools/romfs_extract.py.

local M = {}

local MEDIA_UNIT = 0x200

local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function u64(s, p)
  -- offsets inside a 2 GiB image fit comfortably in a double
  return u32(s, p) + u32(s, p + 4) * 4294967296
end

-- UTF-16LE name -> ASCII-ish Lua string (RomFS names here are plain ASCII)
local function name16(s, p, n)
  local out = {}
  for i = 0, n - 2, 2 do
    local lo, hi = s:byte(p + i, p + i + 1)
    local code = lo + hi * 256
    out[#out + 1] = code < 128 and string.char(code) or "?"
  end
  return table.concat(out)
end

local function be16(s, p) local a, b = s:byte(p, p + 1); return a * 256 + b end
local function be32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function align64(n) return math.ceil(n / 64) * 64 end

-- a TMD's signature block, type word and padding included
local SIG_BLOCK = {
  [0x10000] = 0x240, [0x10003] = 0x240,
  [0x10001] = 0x140, [0x10004] = 0x140,
  [0x10002] = 0x80, [0x10005] = 0x80,
}
local CIA_HEADER = 0x2020

-- Where the game's NCCH starts, and the container's kind: a card image (.cci / .3ds,
-- partition 0), a CIA (its first content, which must not be title-key encrypted), or a
-- bare NCCH (.cxi).
function M.ncchOf(read)
  local magic = read(0x100, 4)
  if magic == "NCSD" then
    return u32(read(0x120, 8), 1) * MEDIA_UNIT, "cci"
  end
  if magic == "NCCH" then return 0, "ncch" end
  local h = read(0, 0x20)
  if u32(h, 1) ~= CIA_HEADER then
    return nil, "not a 3DS card image, CIA or NCCH"
  end
  local ticket = align64(CIA_HEADER) + align64(u32(h, 9))
  local tmd = ticket + align64(u32(h, 13))
  local content = tmd + align64(u32(h, 17))
  local sig = SIG_BLOCK[be32(read(tmd, 4), 1)]
  if not sig then return nil, "CIA: unknown TMD signature type" end
  local chunk = read(tmd + sig + 0xC4 + 0x900, 0x30)
  if be16(chunk, 7) % 2 == 1 then
    return nil, "encrypted CIA content: supply a decrypted CIA"
  end
  return content, "cia"
end

-- Returns a RomFS handle or nil, reason.
function M.open(read)
  local ncch, kind = M.ncchOf(read)
  if not ncch then return nil, kind end
  if read(ncch + 0x100, 4) ~= "NCCH" then
    return nil, kind == "cia" and "the CIA's first content is not an NCCH"
      or "partition 0 is not an NCCH"
  end
  local flags = read(ncch + 0x188, 8)
  local f7 = flags:byte(8)
  if f7 % 8 < 4 then return nil, "encrypted NCCH: supply a decrypted image" end
  local rf = read(ncch + 0x1B0, 8)
  local romfs = ncch + u32(rf, 1) * MEDIA_UNIT
  local ivfc = read(romfs, 0x5C)
  if ivfc:sub(1, 4) ~= "IVFC" then return nil, "RomFS IVFC header missing" end
  local masterHashSize = u32(ivfc, 0x09)
  local l3BlockLog2 = u32(ivfc, 0x4D)
  local block = 2 ^ l3BlockLog2
  local l3 = romfs + math.ceil((0x60 + masterHashSize) / block) * block
  local hdr = read(l3, 0x28)
  if u32(hdr, 1) ~= 0x28 then return nil, "unexpected RomFS level-3 header" end
  local dirMetaOff, dirMetaLen = u32(hdr, 0x0D), u32(hdr, 0x11)
  local fileMetaOff, fileMetaLen = u32(hdr, 0x1D), u32(hdr, 0x21)
  local dataOff = u32(hdr, 0x25)
  local fs = {
    ncch = ncch, kind = kind, romfs = romfs, l3 = l3,
    dirMeta = read(l3 + dirMetaOff, dirMetaLen),
    fileMeta = read(l3 + fileMetaOff, fileMetaLen),
    data = l3 + dataOff,
    read = read,
  }

  local function dirChildren(dirOff)
    local dm = fs.dirMeta
    local firstChild = u32(dm, dirOff + 9)
    local firstFile = u32(dm, dirOff + 13)
    return firstChild, firstFile
  end

  -- find child directory by name under dirOff
  local function childDir(dirOff, name)
    local dm = fs.dirMeta
    local d = select(1, dirChildren(dirOff))
    while d ~= 0xFFFFFFFF do
      local n = u32(dm, d + 0x15)
      if name16(dm, d + 0x19, n) == name then return d end
      d = u32(dm, d + 5)
    end
    return nil
  end

  local function childFile(dirOff, name)
    local fm = fs.fileMeta
    local _, f = dirChildren(dirOff)
    while f ~= 0xFFFFFFFF do
      local n = u32(fm, f + 0x1D)
      if name16(fm, f + 0x21, n) == name then
        return fs.data + u64(fm, f + 9), u64(fm, f + 17)
      end
      f = u32(fm, f + 5)
    end
    return nil
  end

  -- "a/0/4/3" -> absolute offset, length
  function fs:file(path)
    local dir = 0
    local parts = {}
    for seg in path:gmatch("[^/]+") do parts[#parts + 1] = seg end
    for i = 1, #parts - 1 do
      dir = childDir(dir, parts[i])
      if not dir then return nil, "no directory " .. parts[i] .. " in " .. path end
    end
    local off, len = childFile(dir, parts[#parts])
    if not off then return nil, "no file " .. path end
    return off, len
  end

  -- list files under a directory path ("a/0/4") as { name, offset, length }
  function fs:list(path)
    local dir = 0
    for seg in path:gmatch("[^/]+") do
      dir = childDir(dir, seg)
      if not dir then return nil, "no directory " .. seg end
    end
    local fm = self.fileMeta
    local out = {}
    local _, f = dirChildren(dir)
    while f ~= 0xFFFFFFFF do
      local n = u32(fm, f + 0x1D)
      out[#out + 1] = { name = name16(fm, f + 0x21, n), offset = self.data + u64(fm, f + 9), length = u64(fm, f + 17) }
      f = u32(fm, f + 5)
    end
    return out
  end

  return fs
end

return M
