-- BCLIM texture decoder, pure Lua (no bit library, no FFI): the in-game twin of
-- tools/bclim.py. decode(bytes) -> { w, h, format, rgba } where rgba is a
-- string of w*h*4 bytes, or nil, reason.
--
-- Layout: [texture data][CLIM 0x14][imag 0x14] at the end of the file; 8x8
-- tiles row-major, Morton order inside a tile; ETC1 tiles are four 4x4
-- blocks (row-major 2x2), ETC1A4 with an 8-byte alpha block before each
-- colour block. Channel conventions match bclimtool (verified by
-- tools/discover.py on the Alpha Sapphire archives).

local M = {}

M.FORMATS = {
  [0] = "L8", [1] = "A8", [2] = "LA4", [3] = "LA8", [4] = "HILO8", [5] = "RGB565",
  [6] = "RGB8", [7] = "RGBA5551", [8] = "RGBA4", [9] = "RGBA8", [10] = "ETC1",
  [11] = "ETC1A4", [12] = "L4", [13] = "A4",
}
local BPP = { L8 = 1, A8 = 1, LA4 = 1, LA8 = 2, HILO8 = 2, RGB565 = 2, RGB8 = 3,
  RGBA5551 = 2, RGBA4 = 2, RGBA8 = 4 }

local MOD = { { 2, 8 }, { 5, 17 }, { 9, 29 }, { 13, 42 }, { 18, 60 }, { 24, 80 }, { 33, 106 }, { 47, 183 } }

-- Morton index -> x, y inside an 8x8 tile
local MX, MY = {}, {}
for i = 0, 63 do
  local x = (i % 2) + math.floor(i / 4) % 2 * 2 + math.floor(i / 16) % 2 * 4
  local y = math.floor(i / 2) % 2 + math.floor(i / 8) % 2 * 2 + math.floor(i / 32) % 2 * 4
  MX[i], MY[i] = x, y
end

-- channel scaling follows bclimtool (round(v * 255 / max)) so the dev
-- pipeline and the in-game decoder agree to the byte
local X5, X6, X4 = {}, {}, {}
for v = 0, 31 do X5[v] = math.floor((v * 255 + 15) / 31) end
for v = 0, 63 do X6[v] = math.floor((v * 255 + 31) / 63) end
for v = 0, 15 do X4[v] = v * 17 end
-- ETC1 base colours expand by bit replication per the ETC1 specification
local E5 = {}
for v = 0, 31 do E5[v] = v * 8 + math.floor(v / 4) end

local function pow2(v)
  local p = 8
  while p < v do p = p * 2 end
  return p
end

local char = string.char
local floor = math.floor

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p) local a, b, c, d = s:byte(p, p + 3); return a + b * 256 + c * 65536 + d * 16777216 end

-- Every BCLIM inside a blob (a whole file or a pack of several), as
-- { start, stop } 1-based inclusive ranges in blob order: the same scan
-- tools/garc_dump.py performs, so recipe `clim` indices line up.
function M.find(blob)
  local out = {}
  local pos = 1
  while true do
    local p = blob:find("CLIM", pos, true)
    if not p then break end
    pos = p + 4
    if p + 0x28 - 1 <= #blob then
      local bom = u16(blob, p + 4)
      if (bom == 0xFEFF or bom == 0xFFFE) and blob:sub(p + 0x14, p + 0x17) == "imag" then
        local fileSize = u32(blob, p + 0x0C)
        local stop = p + 0x28 - 1
        local start = stop - fileSize + 1
        if start >= 1 and fileSize >= 0x28 then out[#out + 1] = { start = start, stop = stop } end
      end
    end
  end
  return out
end

function M.header(data)
  if type(data) ~= "string" or #data < 0x28 then return nil, "too small for a CLIM trailer" end
  local n = #data
  local clim = n - 0x28 + 1
  local imag = n - 0x14 + 1
  if data:sub(clim, clim + 3) ~= "CLIM" or data:sub(imag, imag + 3) ~= "imag" then
    return nil, "CLIM/imag magic missing"
  end
  local bom = u16(data, clim + 4)
  if bom ~= 0xFEFF then return nil, "big-endian CLIM unsupported" end
  local w, h = u16(data, imag + 8), u16(data, imag + 10)
  local fmt = u32(data, imag + 12)
  local size = u32(data, imag + 16)
  local name = M.FORMATS[fmt]
  if not name then return nil, ("unknown format %d"):format(fmt) end
  return { w = w, h = h, format = name, code = fmt, dataSize = size }
end

local function clamp(v) if v < 0 then return 0 elseif v > 255 then return 255 end return v end

-- fills out[(y*w+x)*4+1 .. +4] with char bytes
local function put(out, w, x, y, r, g, b, a)
  local o = (y * w + x) * 4
  out[o + 1], out[o + 2], out[o + 3], out[o + 4] = char(r), char(g), char(b), char(a)
end

local function etc1Block(tex, pos, hasAlpha, out, w, h, bx, by)
  local alo, ahi
  if hasAlpha then
    alo, ahi = u32(tex, pos), u32(tex, pos + 4)
    pos = pos + 8
  end
  local lo, hi = u32(tex, pos), u32(tex, pos + 4)   -- hi holds bits 32..63
  local flip = hi % 2
  local diff = floor(hi / 2) % 2
  local t2 = MOD[floor(hi / 4) % 8 + 1]
  local t1 = MOD[floor(hi / 32) % 8 + 1]
  local r1, g1, b1, r2, g2, b2
  if diff == 1 then
    local R = floor(hi / 134217728) % 32   -- bits 59..63 -> hi bits 27..31
    local dR = floor(hi / 16777216) % 8    -- bits 56..58 -> hi bits 24..26
    local G = floor(hi / 524288) % 32      -- bits 51..55 -> hi 19..23
    local dG = floor(hi / 65536) % 8       -- bits 48..50 -> hi 16..18
    local B = floor(hi / 2048) % 32        -- bits 43..47 -> hi 11..15
    local dB = floor(hi / 256) % 8         -- bits 40..42 -> hi 8..10
    if dR >= 4 then dR = dR - 8 end
    if dG >= 4 then dG = dG - 8 end
    if dB >= 4 then dB = dB - 8 end
    r1, g1, b1 = E5[R], E5[G], E5[B]
    r2, g2, b2 = E5[(R + dR) % 32], E5[(G + dG) % 32], E5[(B + dB) % 32]
  else
    r1 = X4[floor(hi / 268435456) % 16]    -- bits 60..63 -> hi 28..31
    r2 = X4[floor(hi / 16777216) % 16]     -- bits 56..59 -> hi 24..27
    g1 = X4[floor(hi / 1048576) % 16]      -- bits 52..55 -> hi 20..23
    g2 = X4[floor(hi / 65536) % 16]        -- bits 48..51 -> hi 16..19
    b1 = X4[floor(hi / 4096) % 16]         -- bits 44..47 -> hi 12..15
    b2 = X4[floor(hi / 256) % 16]          -- bits 40..43 -> hi 8..11
  end
  for x = 0, 3 do
    for y = 0, 3 do
      local p = x * 4 + y
      local lsb = floor(lo / 2 ^ p) % 2
      local msb = floor(lo / 2 ^ (16 + p)) % 2
      local first = (flip == 1) and (y < 2) or (flip == 0 and x < 2)
      local tr, tg, tb = r1, g1, b1
      local tab = t1
      if not first then tr, tg, tb, tab = r2, g2, b2, t2 end
      local m = (lsb == 1) and tab[2] or tab[1]
      if msb == 1 then m = -m end
      local px, py = bx + x, by + y
      if px < w and py < h then
        local a = 255
        if hasAlpha then
          local word, shift = alo, p * 4
          if p >= 8 then word, shift = ahi, (p - 8) * 4 end
          a = X4[floor(word / 2 ^ shift) % 16]
        end
        put(out, w, px, py, clamp(tr + m), clamp(tg + m), clamp(tb + m), a)
      end
    end
  end
end

local function pixel(fmt, tex, pos, nibble)
  if fmt == "RGBA4" then
    local v = u16(tex, pos)
    return X4[floor(v / 4096) % 16], X4[floor(v / 256) % 16], X4[floor(v / 16) % 16], X4[v % 16]
  elseif fmt == "RGBA8" then
    local a, b, g, r = tex:byte(pos, pos + 3)
    return r, g, b, a
  elseif fmt == "RGB8" then
    local b, g, r = tex:byte(pos, pos + 2)
    return r, g, b, 255
  elseif fmt == "RGBA5551" then
    local v = u16(tex, pos)
    return X5[floor(v / 2048) % 32], X5[floor(v / 64) % 32], X5[floor(v / 2) % 32], (v % 2 == 1) and 255 or 0
  elseif fmt == "RGB565" then
    local v = u16(tex, pos)
    return X5[floor(v / 2048) % 32], X6[floor(v / 32) % 64], X5[v % 32], 255
  elseif fmt == "LA8" then
    local a, l = tex:byte(pos, pos + 1)
    return l, l, l, a
  elseif fmt == "HILO8" then
    local g, r = tex:byte(pos, pos + 1)
    return r, g, 255, 255
  elseif fmt == "L8" then
    local l = tex:byte(pos)
    return l, l, l, 255
  elseif fmt == "A8" then
    return 255, 255, 255, tex:byte(pos)
  elseif fmt == "LA4" then
    local v = tex:byte(pos)
    local l = X4[floor(v / 16)]
    return l, l, l, X4[v % 16]
  elseif fmt == "L4" then
    local v = tex:byte(pos)
    local n = (nibble == 1) and floor(v / 16) or v % 16
    local l = X4[n]
    return l, l, l, 255
  elseif fmt == "A4" then
    local v = tex:byte(pos)
    local n = (nibble == 1) and floor(v / 16) or v % 16
    return 255, 255, 255, X4[n]
  end
  return 255, 0, 255, 255
end

function M.decode(data)
  local hdr, err = M.header(data)
  if not hdr then return nil, err end
  return M.decodeRaw(hdr.format, hdr.w, hdr.h, data, hdr.dataSize)
end

-- texture data without a CLIM header (a BCH's textures): fmt by name, Morton tiles at
-- power-of-two sizes, `size` bytes available
function M.decodeRaw(fmt, w, h, tex, size)
  local hdr = { dataSize = size or #tex }
  local out = {}
  -- prefill so partially covered tiles leave transparent pixels, not holes
  local zero = char(0)
  for i = 1, w * h * 4 do out[i] = zero end
  -- texture memory is laid out at power-of-two dimensions; the header holds the visible size
  local tilesX, tilesY = pow2(w) / 8, pow2(h) / 8
  if fmt == "ETC1" or fmt == "ETC1A4" then
    local hasAlpha = fmt == "ETC1A4"
    local blockBytes = hasAlpha and 16 or 8
    local pos = 1
    for ty = 0, tilesY - 1 do
      for tx = 0, tilesX - 1 do
        for by = 0, 1 do
          for bx = 0, 1 do
            if pos + blockBytes - 1 > hdr.dataSize then return nil, "texture data truncated" end
            etc1Block(tex, pos, hasAlpha, out, w, h, tx * 8 + bx * 4, ty * 8 + by * 4)
            pos = pos + blockBytes
          end
        end
      end
    end
  else
    local bpp = BPP[fmt]
    local half = (fmt == "L4" or fmt == "A4")
    local pos = 1
    for ty = 0, tilesY - 1 do
      for tx = 0, tilesX - 1 do
        for i = 0, 63 do
          local px, py = tx * 8 + MX[i], ty * 8 + MY[i]
          local bpos, nibble
          if half then bpos, nibble = pos + floor(i / 2), i % 2 else bpos, nibble = pos + i * bpp, 0 end
          if px < w and py < h then
            if bpos > hdr.dataSize then return nil, "texture data truncated" end
            local r, g, b, a = pixel(fmt, tex, bpos, nibble)
            put(out, w, px, py, r, g, b, a)
          end
        end
        pos = pos + (half and 32 or 64 * bpp)
      end
    end
  end
  return { w = w, h = h, format = fmt, rgba = table.concat(out) }
end

return M
