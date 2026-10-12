-- GARC archive reader (Game Freak 3DS container), pure Lua.
--
-- garc.open(read, base, size) where read(offset, length) returns bytes from
-- the enclosing image and `base` is the archive's absolute offset. Only the
-- header and tables are read; entries are located, not loaded, so a job can
-- fetch just the ones its recipe names.
--
-- Layout (little endian):
--   "CRAG" u32 headerSize u16 BOM(0xFEFF) u16 version u32 chunkCount u32 dataOffset u32 fileSize
--     version 0x0400: u32 largestUnpadded;  0x0600: u32 largestPadded u32 largestUnpadded u32 padToNearest
--   "OTAF" u32 size u16 count u16 pad  u32[count] offsets into the FATB entry area
--   "BTAF" u32 size u32 fileCount  entries: u32 flags, then for each set bit: u32 start u32 end u32 length
--   "BMIF" u32 size u32 dataSize   (data follows at header dataOffset)

local M = {}

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

function M.open(read, base, size)
  local head = read(base, math.min(size or 0x40, 0x40))
  if head:sub(1, 4) ~= "CRAG" then return nil, "not a GARC" end
  local headerSize = u32(head, 5)
  local bom = u16(head, 9)
  if bom ~= 0xFEFF then return nil, "big-endian GARC unsupported" end
  local version = u16(head, 11)
  local dataOffset = u32(head, 17)
  local fileSize = u32(head, 21)
  -- FATO sits right after the header; read FATO + FATB in one go
  local fatoHead = read(base + headerSize, 12)
  if fatoHead:sub(1, 4) ~= "OTAF" then return nil, "FATO missing" end
  local fatoSize = u32(fatoHead, 5)
  local count = u16(fatoHead, 9)
  local fatbHead = read(base + headerSize + fatoSize, 12)
  if fatbHead:sub(1, 4) ~= "BTAF" then return nil, "FATB missing" end
  local fatbSize = u32(fatbHead, 5)
  local tables = read(base + headerSize, fatoSize + fatbSize)
  local fato = {}
  for i = 1, count do fato[i] = u32(tables, 13 + (i - 1) * 4) end
  local fatbEntries = fatoSize + 12 + 1   -- 1-based position of the FATB entry area inside `tables`
  local entries = {}
  for i = 1, count do
    local p = fatbEntries + fato[i]
    local flags = u32(tables, p)
    p = p + 4
    local subs = {}
    local bit = 1
    for j = 0, 31 do
      if flags % (bit * 2) >= bit then
        local start, stop, length = u32(tables, p), u32(tables, p + 4), u32(tables, p + 8)
        p = p + 12
        subs[#subs + 1] = { sub = j, start = start, stop = stop, length = length }
      end
      bit = bit * 2
    end
    entries[i] = subs
  end
  local G = {
    base = base, version = version, dataOffset = dataOffset, fileSize = fileSize,
    count = count, entries = entries, read = read,
  }
  -- absolute location of entry `index` (0-based like the dump tool), sub-entry `sub`
  function G:locate(index, sub)
    local subs = self.entries[index + 1]
    if not subs then return nil, "no entry " .. tostring(index) end
    for _, s in ipairs(subs) do
      if s.sub == (sub or 0) then
        if s.length == 0 then return nil, "empty entry" end
        return self.base + self.dataOffset + s.start, s.length
      end
    end
    return nil, ("entry %d has no sub %d"):format(index, sub or 0)
  end
  function G:bytes(index, sub)
    local off, len = self:locate(index, sub)
    if not off then return nil, len end
    return self.read(off, len)
  end
  return G
end

return M
