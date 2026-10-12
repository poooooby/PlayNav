-- Gen 6 (X/Y, ORAS) text file reader, pure Lua (no bit library: runs inside a job).
-- Mirrors tools/gen6_text.py.
--
-- Layout (little endian): u16 sections (1), u16 lineCount, u32 totalLength,
-- u32 initialKey, u32 sectionOffset; at sectionOffset: u32 sectionLength, then lineCount
-- entries of (u32 offset from sectionOffset, u16 length in chars, u16 pad). Each line is
-- UTF-16LE, xor-encrypted with a key that starts at 0x7C89 + i * 0x2983 and rotates left
-- three bits after every char.
--
-- decode(blob) -> { [0] = line0, line1, ... } as UTF-8 with "\n" line breaks. Variables
-- become {BAG} (item / bag name, 0x010A), {MON} (Pokemon nickname, 0x0102), {PLAYER}
-- (0x0100), {STAT} (0x010D), {ITEM} (0x0109), {COURSE} (0x0197), {DECOR} (an Amie Décor item,
-- 0x018C), {PUFF} (a Poké Puff, 0x01A0), {N} (numbers 0x0200..0x0204) or nothing (colours,
-- plural markers, waits and anything else).

local M = {}

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- 16-bit xor by nibbles
local XOR4 = {}
for a = 0, 15 do
  XOR4[a] = {}
  for b = 0, 15 do
    local r, bitv = 0, 1
    local x, y = a, b
    for _ = 1, 4 do
      if (x % 2) ~= (y % 2) then r = r + bitv end
      x, y, bitv = math.floor(x / 2), math.floor(y / 2), bitv * 2
    end
    XOR4[a][b] = r
  end
end
local function xor16(a, b)
  local r, m = 0, 1
  for _ = 1, 4 do
    r = r + XOR4[a % 16][b % 16] * m
    a, b, m = math.floor(a / 16), math.floor(b / 16), m * 16
  end
  return r
end
M.xor16 = xor16

local function rotl3(k) return ((k * 8) % 65536) + math.floor(k / 8192) end

local function utf8(c)
  if c < 0x80 then return string.char(c) end
  if c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64) end
  return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
end

local SPECIAL = { [0xE07F] = " ", [0xE08D] = "…", [0xE08E] = "♂", [0xE08F] = "♀", [0x000A] = "\n", [0xE07E] = "\n" }
local VARS = { [0x010A] = "{BAG}", [0x0102] = "{MON}", [0x0100] = "{PLAYER}", [0x010D] = "{STAT}",
  [0x0109] = "{ITEM}", [0x0197] = "{COURSE}", [0x018C] = "{DECOR}", [0x01A0] = "{PUFF}",
  [0x0200] = "{N}", [0x0201] = "{N}", [0x0202] = "{N}", [0x0203] = "{N}", [0x0204] = "{N}" }

function M.decode(blob)
  if type(blob) ~= "string" or #blob < 0x10 then return nil, "too short" end
  local sections, lines = u16(blob, 1), u16(blob, 3)
  local secOff = u32(blob, 13)
  if sections ~= 1 or lines == 0 or lines > 5000 or secOff + 4 > #blob then return nil, "not a text file" end
  local out = {}
  local key = 0x7C89
  for i = 0, lines - 1 do
    local ent = secOff + 4 + i * 8
    if ent + 8 > #blob then return nil, "line table cut short" end
    local off, len = u32(blob, ent + 1), u16(blob, ent + 5)
    local start = secOff + off
    if start + len * 2 > #blob then return nil, "line " .. i .. " out of range" end
    local k = key
    local chars = {}
    for j = 0, len - 1 do
      chars[#chars + 1] = xor16(u16(blob, start + j * 2 + 1), k)
      k = rotl3(k)
    end
    key = (key + 0x2983) % 65536
    local s, j = {}, 1
    while j <= #chars do
      local c = chars[j]
      if c == 0 then break end
      if c == 0x10 then
        local n = chars[j + 1] or 0
        local code = chars[j + 2]
        s[#s + 1] = (code and VARS[code]) or ""
        j = j + 2 + n
      else
        s[#s + 1] = SPECIAL[c] or utf8(c)
        j = j + 1
      end
    end
    out[i] = table.concat(s)
  end
  return out, lines
end

-- a Lua source string that returns the lines (what the job writes to the cache)
function M.serialize(lines, count)
  local parts = { "return {" }
  for i = 0, (count or 0) - 1 do parts[#parts + 1] = ("  [%d] = %q,"):format(i, lines[i] or "") end
  parts[#parts + 1] = "}"
  return table.concat(parts, "\n") .. "\n"
end

return M
