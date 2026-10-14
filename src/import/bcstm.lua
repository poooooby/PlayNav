-- A 3DS BCSTM stream (the game's music, DSP-ADPCM): its header facts and a decode to a
-- 16-bit PCM WAV. Pure Lua with arithmetic only (the extract job has no bit library); the
-- extract job compiles it from source. Twin of tools/bcstm.py.
--
-- M.parse(bytes) -> { channels, rate, loop, loopStart, samples, ... } or nil, why
-- M.wav(bytes, maxChannels) -> wav bytes, info   (the first maxChannels channels, default 2)

local M = {}

local floor = math.floor
local unpack = unpack or table.unpack

local function u8(s, p) return s:byte(p + 1) end
local function u16(s, p)
  local a, b = s:byte(p + 1, p + 2)
  return a + b * 256
end
local function u32(s, p)
  local a, b, c, d = s:byte(p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function s16(s, p)
  local v = u16(s, p)
  return v >= 32768 and v - 65536 or v
end
local function s32(s, p)
  local v = u32(s, p)
  return v >= 2147483648 and v - 4294967296 or v
end

function M.parse(b)
  if type(b) ~= "string" or #b < 0x40 or b:sub(1, 4) ~= "CSTM" then return nil, "not a CSTM file" end
  if b:byte(5) ~= 0xFF or b:byte(6) ~= 0xFE then return nil, "big-endian CSTM" end
  local secs = {}
  for i = 0, u16(b, 0x10) - 1 do
    local at = 0x14 + i * 12
    secs[u16(b, at)] = s32(b, at + 4)
  end
  local info, data = secs[0x4000], secs[0x4002]
  if not (info and data) or b:sub(info + 1, info + 4) ~= "INFO" then return nil, "INFO block missing" end
  local base = info + 8
  local s = base + s32(b, base + 4)
  local ct = base + s32(b, base + 20)
  local h = {
    encoding = u8(b, s), loop = u8(b, s + 1) ~= 0, channels = u8(b, s + 2),
    rate = u32(b, s + 4), loopStart = u32(b, s + 8), samples = u32(b, s + 12),
    blocks = u32(b, s + 16), blockSize = u32(b, s + 20), blockSamples = u32(b, s + 24),
    lastSize = u32(b, s + 28), lastSamples = u32(b, s + 32), lastPadded = u32(b, s + 36),
  }
  h.data = data + 8 + s32(b, s + 0x38 + 4)
  h.chans = {}
  for i = 0, u32(b, ct) - 1 do
    local ci = ct + s32(b, ct + 4 + i * 8 + 4)
    local a = ci + s32(b, ci + 4)
    local coefs = {}
    for k = 0, 15 do coefs[k] = s16(b, a + k * 2) end
    h.chans[i + 1] = { coefs = coefs, hist1 = s16(b, a + 34), hist2 = s16(b, a + 36) }
  end
  if h.encoding ~= 2 then return nil, ("encoding %d is not DSP-ADPCM"):format(h.encoding) end
  if h.channels < 1 or #h.chans < h.channels then return nil, "channel table" end
  return h
end

-- one channel's block of DSP-ADPCM into out[1..n] (14 samples per 8-byte frame)
local function decodeBlock(b, p, size, n, ch, out)
  local coefs = ch.coefs
  local h1, h2 = ch.hist1, ch.hist2
  local i, q, stop = 0, p, p + size
  while i < n and q < stop do
    local head = b:byte(q + 1)
    local pred = floor(head / 16)
    local scale = 2 ^ (head % 16)
    local c1, c2 = coefs[pred * 2], coefs[pred * 2 + 1]
    for k = 0, 13 do
      if i >= n then break end
      local byte = b:byte(q + 2 + floor(k / 2))
      local nib = (k % 2 == 0) and floor(byte / 16) or byte % 16
      if nib >= 8 then nib = nib - 16 end
      local v = floor((nib * scale * 2048 + 1024 + c1 * h1 + c2 * h2) / 2048)
      if v < -32768 then v = -32768 elseif v > 32767 then v = 32767 end
      i = i + 1
      out[i] = v
      h2, h1 = h1, v
    end
    q = q + 8
  end
  ch.hist1, ch.hist2 = h1, h2
  return i
end

-- shared with the sound-effect renderer (src/import/seqsynth.lua): one channel's DSP-ADPCM
-- frames at byte p (0-based) into out[1..n]; ch = { coefs[0..15], hist1, hist2 } is advanced
M.dspBlock = decodeBlock

local function le16(v) if v < 0 then v = v + 65536 end return v % 256, floor(v / 256) end
local function le32(v) return string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256) end

function M.wav(b, maxChannels)
  local h, why = M.parse(b)
  if not h then return nil, why end
  local nch = math.min(h.channels, maxChannels or 2)
  local chans = {}
  for c = 1, nch do
    local src = h.chans[c]
    chans[c] = { coefs = src.coefs, hist1 = src.hist1, hist2 = src.hist2 }
  end
  local parts, bufs, bytes = {}, {}, {}
  for c = 1, nch do bufs[c] = {} end
  local pos, total = h.data, 0
  for blk = 1, h.blocks do
    local last = blk == h.blocks
    local size = last and h.lastSize or h.blockSize
    local stride = last and h.lastPadded or h.blockSize
    local n = last and h.lastSamples or h.blockSamples
    local got = n
    for c = 1, nch do
      got = math.min(got, decodeBlock(b, pos + (c - 1) * stride, size, n, chans[c], bufs[c]))
    end
    -- interleave into little-endian bytes, flushed in pieces string.char can take
    local j = 0
    for i = 1, got do
      for c = 1, nch do
        local lo, hi = le16(bufs[c][i])
        bytes[j + 1], bytes[j + 2] = lo, hi
        j = j + 2
        if j >= 4096 then
          parts[#parts + 1] = string.char(unpack(bytes, 1, j))
          j = 0
        end
      end
    end
    if j > 0 then parts[#parts + 1] = string.char(unpack(bytes, 1, j)) end
    total = total + got
    pos = pos + stride * h.channels
  end
  local pcm = table.concat(parts)
  local header = "RIFF" .. le32(36 + #pcm) .. "WAVEfmt " .. le32(16)
    .. string.char(1, 0, nch, 0) .. le32(h.rate) .. le32(h.rate * nch * 2)
    .. string.char(nch * 2, 0, 16, 0) .. "data" .. le32(#pcm)
  return header .. pcm, { rate = h.rate, channels = nch, samples = total,
    loop = h.loop, loopStart = h.loopStart }
end

return M
