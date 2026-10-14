-- A 3DS sound archive (BCSAR): names, sounds, banks and wave archives, read through ranged
-- reads (the archive is 22 MB; only its tables and the files an effect needs are read). Pure
-- Lua, arithmetic only; the extract job compiles it from source. Twin of tools/bcsar.py.
--
-- local ar = M.open(read, offset, length)      read(offset, length) -> bytes (the card image)
-- ar:sound(name) -> { name, volume, seq = CSEQ bytes, banks = { CBNK bytes | false } } | nil, why
-- ar:wave(warcId, index) -> CWAV bytes

local M = {}

local function u16(s, p)
  local a, b = s:byte(p + 1, p + 2)
  return a + b * 256
end
local function u32(s, p)
  local a, b, c, d = s:byte(p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function s32(s, p)
  local v = u32(s, p)
  return v >= 2147483648 and v - 4294967296 or v
end
M.u16, M.u32, M.s32 = u16, u32, s32

-- (type, offset) of an 8-byte reference
local function ref(s, p) return u16(s, p), s32(s, p + 4) end
M.ref = ref

-- a block's section by its tag: absolute offset (0-based) and size
local function section(s, off, tag)
  for i = 0, u16(s, off + 0x10) - 1 do
    local so = s32(s, off + 0x14 + i * 12 + 4)
    if s:sub(off + so + 1, off + so + 4) == tag then return off + so, u32(s, off + 0x14 + i * 12 + 8) end
  end
  return nil
end
M.section = section

local Archive = {}
Archive.__index = Archive

function M.open(read, base, length)
  local head = read(base, 0x40)
  if not head or head:sub(1, 4) ~= "CSAR" then return nil, "not a CSAR file" end
  local self = setmetatable({ read = read, base = base, length = length }, Archive)
  -- the header's section table by id (the sections themselves lie past the header)
  local secs = {}
  for i = 0, u16(head, 0x10) - 1 do
    local p = 0x14 + i * 12
    secs[u16(head, p)] = { s32(head, p + 4), u32(head, p + 8) }
  end
  local strg, strgSize = secs[0x2000] and secs[0x2000][1], secs[0x2000] and secs[0x2000][2]
  local info, infoSize = secs[0x2001] and secs[0x2001][1], secs[0x2001] and secs[0x2001][2]
  local file = secs[0x2002] and secs[0x2002][1]
  if not (strg and info and file) then return nil, "sections missing" end
  self.strg = read(base + strg, strgSize)
  self.info = read(base + info, infoSize)
  self.fileBase = base + file + 8
  -- the INFO tables: sounds 0x2100, banks 0x2101, wave archives 0x2103, files 0x2106
  local s, b = self.info, 8
  self.tables = {}
  for i = 0, 7 do
    local t, o = ref(s, b + i * 8)
    if t >= 0x2100 and t <= 0x2106 then
      local at = b + o
      local list = {}
      for k = 0, u32(s, at) - 1 do
        local _, eo = ref(s, at + 4 + k * 8)
        list[k] = at + eo
      end
      self.tables[t] = list
    end
  end
  -- names -> item ids (the patricia tree's leaves)
  local g = self.strg
  local sb = 8
  local _, sto = ref(g, sb)
  local _, lto = ref(g, sb + 8)
  local st, lt = sb + sto, sb + lto
  local strings = {}
  local n = u32(g, st)
  for i = 0, n - 1 do
    local o, size = s32(g, st + 4 + i * 12 + 4), u32(g, st + 4 + i * 12 + 8)
    strings[i] = g:sub(st + o + 1, st + o + size - 1)
  end
  self.ids = {}
  for i = 0, u32(g, lt + 4) - 1 do
    local p = lt + 8 + i * 20
    if u16(g, p) == 1 then
      local sid, iid = u32(g, p + 12), u32(g, p + 16)
      if strings[sid] then self.ids[strings[sid]] = iid end
    end
  end
  return self
end

function Archive:fileBytes(fid)
  local s = self.info
  local e = self.tables[0x2106][fid]
  if not e then return nil, "no file " .. tostring(fid) end
  local t, o = ref(s, e)
  if t ~= 0x220c then return nil, "file " .. fid .. " is outside the archive" end
  local loc = e + o
  return self.read(self.fileBase + s32(s, loc + 4), u32(s, loc + 8))
end

function Archive:sound(name)
  local s = self.info
  local iid = self.ids[name]
  if not iid or math.floor(iid / 16777216) ~= 1 then return nil, "no sound " .. tostring(name) end
  local e = self.tables[0x2100][iid % 16777216]
  local fid, volume = u32(s, e), s:byte(e + 9)
  local seqinfo = e + 0x44
  local _, bo = ref(s, seqinfo)
  local bt = seqinfo + bo
  local banks = {}
  for i = 0, u32(s, bt) - 1 do
    local bid = u32(s, bt + 4 + i * 4)
    if bid == 0xffffffff then
      banks[i + 1] = false
    else
      local be = self.tables[0x2101][bid % 16777216]
      banks[i + 1] = be and self:fileBytes(u32(s, be)) or false
    end
  end
  local seq, why = self:fileBytes(fid)
  if not seq then return nil, why end
  return { name = name, volume = volume, seq = seq, banks = banks }
end

function Archive:wave(warcId, index)
  local we = self.tables[0x2103][warcId % 16777216]
  if not we then return nil, "no wave archive" end
  local warc, why = self:fileBytes(u32(self.info, we))
  if not warc then return nil, why end
  local info = section(warc, 0, "INFO")
  local data = section(warc, 0, "FILE")
  local o, size = s32(warc, info + 12 + index * 12 + 4), u32(warc, info + 12 + index * 12 + 8)
  return warc:sub(data + 8 + o + 1, data + 8 + o + size)
end

return M
