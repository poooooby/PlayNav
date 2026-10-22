-- CRC-32 (IEEE, the zlib / PNG one), pure Lua over the `bit` library, so it
-- runs inside a mod.job worker where require and love.data are absent. Twin
-- of Python's zlib.crc32. Used to check that the bytes a recipe row reads
-- from the player's card image are the ones the recipe was made from.

local bit = bit
local band, bxor, rshift, bnot = bit.band, bit.bxor, bit.rshift, bit.bnot
local byte = string.byte

local M = {}

local TABLE = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if band(c, 1) ~= 0 then c = bxor(rshift(c, 1), 0xEDB88320) else c = rshift(c, 1) end
  end
  TABLE[i] = c
end

-- Running state: start with M.start(), feed with M.update(state, s), finish
-- with M.hex(state). M.of(s) does all three.
function M.start() return 0xFFFFFFFF end

function M.update(c, s)
  local n = #s
  local i = 1
  while i + 7 <= n do
    local a1, a2, a3, a4, a5, a6, a7, a8 = byte(s, i, i + 7)
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a1), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a2), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a3), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a4), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a5), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a6), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a7), 0xFF)])
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, a8), 0xFF)])
    i = i + 8
  end
  while i <= n do
    c = bxor(rshift(c, 8), TABLE[band(bxor(c, byte(s, i)), 0xFF)])
    i = i + 1
  end
  return c
end

function M.hex(c)
  local v = bnot(c)
  if v < 0 then v = v + 4294967296 end
  return ("%08x"):format(v)
end

function M.of(s) return M.hex(M.update(M.start(), s)) end

-- A range of the image read in pieces no larger than the import read cap.
function M.ofRange(read, offset, length, chunk)
  chunk = chunk or 8 * 1024 * 1024
  local c = M.start()
  local pos, left = offset, length
  while left > 0 do
    local n = math.min(left, chunk)
    c = M.update(c, read(pos, n))
    pos, left = pos + n, left - n
  end
  return M.hex(c)
end

return M
