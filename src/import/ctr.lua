-- Decrypted 3DS card image reader: NCSD -> partition 0 NCCH -> RomFS (IVFC
-- level 3) -> path lookup. Pure Lua; reads only headers and the metadata
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

-- Returns a RomFS handle or nil, reason.
function M.open(read)
  local h = read(0x100, 4)
  if h ~= "NCSD" then return nil, "not an NCSD image" end
  local part = read(0x120, 8)
  local p0off = u32(part, 1) * MEDIA_UNIT
  local ncch = p0off
  if read(ncch + 0x100, 4) ~= "NCCH" then return nil, "partition 0 is not an NCCH" end
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
    ncch = ncch, romfs = romfs, l3 = l3,
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
