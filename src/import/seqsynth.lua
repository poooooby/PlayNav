-- Renders one of the game's sound effects: its sequence (CSEQ: notes, waits, pan, volume, pitch
-- bend, vibrato, envelope, tracks, random values, sweeps, loops) played on its bank's
-- instruments (CBNK: key / velocity regions -> a wave, original key, volume, pan, pitch, ADSR),
-- the waves being DSP-ADPCM CWAVs. Pure Lua, arithmetic only; the extract job compiles it from
-- source. Twin of tools/bcsar.py's render(), sample for sample.
--
-- M.render(sound, archive, deps) -> left, right (float arrays, 1-based), n
--   sound = archive:sound(name); deps = { Bcsar = <bcsar module>, dsp = Bcstm.dspBlock }
-- M.wav(left, right, n) -> 16-bit WAV bytes (mono when both channels are the same)

local M = {}

local floor, sin, cos, log10, pi = math.floor, math.sin, math.cos, math.log10, math.pi
local unpack = unpack or table.unpack

M.OUT_RATE = 32728
M.TEMPO, M.TIMEBASE = 120, 48
M.ENV_STEP = 0.003
M.MAX_SECONDS = 4.0   -- a looping wave left held is cut here (a charge breaks at 2.6 s)
M.LFO_HZ_PER_SPEED = 0.390625
local ENV_FLOOR = -92544

local function u32(s, p)
  local a, b, c, d = s:byte(p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function u16(s, p)
  local a, b = s:byte(p + 1, p + 2)
  return a + b * 256
end
local function s32(s, p)
  local v = u32(s, p)
  return v >= 2147483648 and v - 4294967296 or v
end
local function s16be(s, p)
  local v = s:byte(p + 1) * 256 + s:byte(p + 2)
  return v >= 32768 and v - 65536 or v
end
local function ref(s, p) return u16(s, p), s32(s, p + 4) end
local function f32(s, p)
  local b = u32(s, p)
  local sign = b >= 2147483648 and -1 or 1
  local e = floor(b / 8388608) % 256
  local m = b % 8388608
  if e == 0 then return sign * m * 2 ^ -149 end
  return sign * (1 + m / 8388608) * 2 ^ (e - 127)
end
local function section(s, off, tag)
  for i = 0, u16(s, off + 0x10) - 1 do
    local so = s32(s, off + 0x14 + i * 12 + 4)
    if s:sub(off + so + 1, off + so + 4) == tag then return off + so, u32(s, off + 0x14 + i * 12 + 8) end
  end
  return nil
end

-- ------- waves

local function cwav(b, dsp)
  if b:sub(1, 4) ~= "CWAV" then return nil, "not a CWAV" end
  local info = section(b, 0, "INFO")
  local data = section(b, 0, "DATA")
  local body = info + 8
  local enc, loop = b:byte(body + 1), b:byte(body + 2)
  local rate, ls, le = u32(b, body + 4), u32(b, body + 8), u32(b, body + 12)
  local ct = body + 0x14
  local _, co = ref(b, ct + 4)
  local ch = ct + co
  local _, so = ref(b, ch)
  local sampleOff = data + 8 + so
  local pcm = {}
  if enc == 2 then
    local _, ao = ref(b, ch + 8)
    local a = ch + ao
    local coefs = {}
    for k = 0, 15 do
      local v = u16(b, a + k * 2)
      coefs[k] = v >= 32768 and v - 65536 or v
    end
    local h1, h2 = u16(b, a + 34), u16(b, a + 36)
    local c = { coefs = coefs, hist1 = h1 >= 32768 and h1 - 65536 or h1, hist2 = h2 >= 32768 and h2 - 65536 or h2 }
    dsp(b, sampleOff, math.ceil(le / 14) * 8, le, c, pcm)
  elseif enc == 1 then
    for i = 0, le - 1 do
      local v = u16(b, sampleOff + i * 2)
      pcm[i + 1] = v >= 32768 and v - 65536 or v
    end
  elseif enc == 0 then
    for i = 0, le - 1 do
      local v = b:byte(sampleOff + i + 1)
      pcm[i + 1] = (v > 127 and v - 256 or v) * 256
    end
  else
    return nil, "wave encoding " .. enc
  end
  local out = {}
  for i = 1, le do out[i - 1] = (pcm[i] or 0) / 32768 end
  return { rate = rate, loop = loop ~= 0, loopStart = ls, n = le, samples = out }
end

-- ------- banks: instrument -> { { lo, hi, region } }

local function bankRegions(bnk)
  local info = section(bnk, 0, "INFO")
  local body = info + 8
  local _, wo = ref(bnk, body)
  local wt = body + wo
  local waves = {}
  for i = 0, u32(bnk, wt) - 1 do waves[i] = { u32(bnk, wt + 4 + i * 8), u32(bnk, wt + 8 + i * 8) } end
  local _, io = ref(bnk, body + 8)
  local it = body + io

  local function velregion(p)
    local idx, flags = u32(bnk, p), u32(bnk, p + 4)
    local r = { wave = waves[idx], key = 60, volume = 127, pan = 64, pitch = 1.0, adsr = { 127, 127, 127, 0, 127 } }
    local q = p + 8
    local function bit(n) return floor(flags / 2 ^ n) % 2 == 1 end
    if bit(0) then r.key = bnk:byte(q + 1); q = q + 4 end
    if bit(1) then r.volume = bnk:byte(q + 1); q = q + 4 end
    if bit(2) then r.pan = bnk:byte(q + 1); q = q + 4 end
    if bit(3) then r.pitch = f32(bnk, q); q = q + 4 end
    if bit(4) then q = q + 4 end
    for n = 5, 8 do if bit(n) then q = q + 4 end end
    if bit(9) then
      local env = p + u32(bnk, q)
      local curve = env + s32(bnk, env + 4)
      r.adsr = { bnk:byte(curve + 1, curve + 5) }
    end
    return r
  end

  local function container(p)
    local t, o = ref(bnk, p)
    local c = p + o
    if t == 0x6000 then
      local rt, ro = ref(bnk, c)
      if rt ~= 0x5901 and rt ~= 0x5902 then return {} end
      return { { 0, 127, c + ro, rt } }
    elseif t == 0x6001 then
      local n = u32(bnk, c)
      local rt0 = c + 4 + floor((n + 3) / 4) * 4
      local out, lo = {}, 0
      for i = 0, n - 1 do
        local hi = bnk:byte(c + 4 + i + 1)
        local rtyp, ro = ref(bnk, rt0 + i * 8)
        if rtyp == 0x5901 or rtyp == 0x5902 then out[#out + 1] = { lo, hi, c + ro, rtyp } end   -- 0x5903: empty
        lo = hi + 1
      end
      return out
    elseif t == 0x6002 then
      local lo, hi = bnk:byte(c + 1), bnk:byte(c + 2)
      local out = {}
      for i = 0, hi - lo do
        local rtyp, ro = ref(bnk, c + 4 + i * 8)
        if rtyp == 0x5901 or rtyp == 0x5902 then out[#out + 1] = { lo + i, lo + i, c + ro, rtyp } end
      end
      return out
    end
    error(("region table type %x"):format(t), 0)
  end

  local insts = {}
  for i = 0, u32(bnk, it) - 1 do
    local t, o = ref(bnk, it + 4 + i * 8)
    if t == 0x5900 then
      local regions = {}
      for _, k in ipairs(container(it + o)) do
        for _, v in ipairs(container(k[3])) do
          if v[4] == 0x5902 then regions[#regions + 1] = { k[1], k[2], velregion(v[3]) } end
        end
      end
      insts[i] = regions
    end
  end
  return insts
end

-- ------- the sequencer

local function newRng(seed)
  local r = { s = seed or 12345 }
  function r.range(lo, hi)
    -- fmod is exact on doubles; % (a - floor(a / b) * b) can round off at this size
    r.s = math.fmod(r.s * 16807, 2147483647)
    return lo + r.s % (hi - lo + 1)
  end
  return r
end

local function varlen(d, i)
  local v = 0
  while true do
    local c = d:byte(i + 1)
    i = i + 1
    v = v * 128 + c % 128
    if c < 128 then return v, i end
  end
end

local KEYS = { [0xc0] = "pan", [0xc1] = "vol", [0xc2] = "mvol", [0xc3] = "transpose", [0xc4] = "bend",
  [0xc5] = "range", [0xca] = "mdepth", [0xcb] = "mspeed", [0xcd] = "mrange", [0xe0] = "mdelay",
  [0xd0] = "attack", [0xd1] = "decay", [0xd2] = "sustain", [0xd3] = "release", [0xb1] = "hold" }
local ARG2 = { [0xe0] = true, [0xe1] = true, [0xe3] = true, [0xe4] = true }

local function parseTrack(d, start, rng)
  local ev, opens, loops = {}, {}, {}
  local i, t, waitNotes, steps = start, 0, true, 0
  local capTicks = M.MAX_SECONDS * M.TEMPO * M.TIMEBASE / 60
  while i < #d and steps < 4000 do
    steps = steps + 1
    local op = d:byte(i + 1)
    i = i + 1
    local prefix = nil
    if op == 0xa0 or op == 0xa3 then
      prefix = op
      op = d:byte(i + 1)
      i = i + 1
    end
    if op < 0x80 then
      local vel = d:byte(i + 1)
      i = i + 1
      local length
      length, i = varlen(d, i)
      ev[#ev + 1] = { t, "note", op, vel, length }
      if waitNotes then t = t + length end
    elseif op == 0x80 then
      local w
      w, i = varlen(d, i)
      t = t + w
    elseif op == 0x81 then
      local p
      p, i = varlen(d, i)
      ev[#ev + 1] = { t, "prg", p }
    elseif op == 0x88 then
      opens[#opens + 1] = { d:byte(i + 1), d:byte(i + 2) * 65536 + d:byte(i + 3) * 256 + d:byte(i + 4) }
      i = i + 4
    elseif op == 0x89 or op == 0x8a then
      i = i + 3
    elseif op >= 0xb0 and op < 0xe0 then
      local v
      if prefix == 0xa0 then
        local lo, hi = s16be(d, i), s16be(d, i + 2)
        i = i + 4
        v = rng.range(lo, hi)
      else
        v = d:byte(i + 1)
        i = i + 1
      end
      local dur = 0
      if prefix == 0xa3 then
        dur = s16be(d, i)
        i = i + 2
      end
      if op == 0xc7 then
        waitNotes = v ~= 0
      elseif op == 0xd4 then
        loops[#loops + 1] = { i, v }
      else
        if (op == 0xc3 or op == 0xc4) and v > 127 and prefix ~= 0xa0 then v = v - 256 end
        ev[#ev + 1] = { t, "set", op, v, dur }
      end
    elseif ARG2[op] then
      local v = s16be(d, i)
      i = i + 2
      ev[#ev + 1] = { t, "set", op, v, 0 }
    elseif op == 0xfc then
      local top = loops[#loops]
      if top then
        local at, n = top[1], top[2]
        if n == 0 or n > 1 then
          loops[#loops] = { at, n ~= 0 and n - 1 or 0 }
          i = at
          if n == 0 and t > capTicks then loops[#loops] = nil end
        else
          loops[#loops] = nil
        end
      end
    elseif op == 0xfe then
      i = i + 2
    elseif op == 0xff then
      break
    else
      error(("sequence command %02x at %d"):format(op, i - 1), 0)
    end
  end
  ev[#ev + 1] = { t, "end" }
  return ev, opens
end

M._parseTrack, M._newRng = parseTrack, newRng   -- for the tests

local ATTACK_TABLE = { [0] = 0x00, 0x01, 0x05, 0x0e, 0x1a, 0x26, 0x33, 0x3f, 0x49, 0x54, 0x5c, 0x64, 0x6d,
  0x74, 0x7b, 0x7f, 0x84, 0x89, 0x8f }
local function attackRate(a) if a < 109 then return 255 - a end return ATTACK_TABLE[127 - a] end
local function releaseRate(v)
  if v == 127 then return 0xffff end
  if v == 126 then return 0x3c00 end
  if v < 50 then return v * 2 + 1 end
  return floor(0x1e00 / (126 - v))
end
local function sustainDb(s)
  if s >= 127 then return 0 end
  if s == 0 then return ENV_FLOOR end
  local v = 40 * log10(s / 127) * 128
  return v < 0 and math.ceil(v) or floor(v)
end

-- the track parameters a sounding voice follows live (set or swept after its note began)
local LIVE = { [0xc0] = "pan", [0xc1] = "vol", [0xc2] = "mvol", [0xc4] = "bend", [0xc5] = "range",
  [0xca] = "mdepth", [0xcb] = "mspeed", [0xcd] = "mrange", [0xe0] = "mdelay" }
local LIVE_DEFAULT = { pan = 64, vol = 127, mvol = 127, bend = 0, range = 2, mdepth = 0, mspeed = 16,
  mrange = 1, mdelay = 0 }
-- set at a note's start (the envelope and the instrument)
local AT_NOTE = { [0xd0] = "attack", [0xd1] = "decay", [0xd2] = "sustain", [0xd3] = "release", [0xb1] = "hold",
  [0xc3] = "transpose" }

-- a track's live parameters over ticks: each change { tick, value, sweep ticks, from }
local function newTimeline()
  local tl = { ch = {}, cur = {} }
  for k, v in pairs(LIVE_DEFAULT) do tl.ch[k], tl.cur[k] = {}, v end
  function tl.set(key, t, v, dur)
    local list = tl.ch[key]
    list[#list + 1] = { t, v, dur, tl.cur[key] }
    tl.cur[key] = v
  end
  function tl.at(key, tick)
    local val = LIVE_DEFAULT[key]
    for _, c in ipairs(tl.ch[key]) do
      if c[1] > tick then break end
      if c[3] ~= 0 and tick < c[1] + c[3] then
        val = c[4] + (c[2] - c[4]) * (tick - c[1]) / c[3]
      else
        val = c[2]
      end
    end
    return val
  end
  return tl
end

local function mixVoice(L, R, size, wav, reg, st, tl, t0, key, vel, length, tickS, soundGain)
  local OUT = M.OUT_RATE
  local a = st.attack or reg.adsr[1]
  local dcy = st.decay or reg.adsr[2]
  local sus = st.sustain or reg.adsr[3]
  local hold = st.hold or reg.adsr[4]
  local rel = st.release or reg.adsr[5]
  local src, nsrc = wav.samples, wav.n
  local velGain = soundGain * (vel / 127) ^ 2 * (reg.volume / 127) ^ 2
  local start = floor(t0 * tickS * OUT + 0.5)
  local offAt = length > 0 and (t0 + length) * tickS or nil
  local pos = 0.0
  local env = a < 127 and ENV_FLOOR or 0
  local phase = a < 127 and "attack" or (hold ~= 0 and "hold" or "decay")
  local holdLeft = hold * M.ENV_STEP * 8
  local susDb = sustainDb(sus)
  local stepN = math.max(1, floor(M.ENV_STEP * OUT))
  local i, last = start, start
  local baseRatio = wav.rate / OUT * reg.pitch
  local ratio, amp, lg, rg = 0, 0, 0, 0
  local lfoPhase, lfoT = 0.0, nil
  while i < size do
    local t = i / OUT
    if i % stepN == 0 or i == start then
      local tick = t / tickS
      -- the track's live parameters, swept where a sweep is running
      local bend, brange = tl.at("bend", tick), tl.at("range", tick)
      local vol, mvol, pan = tl.at("vol", tick), tl.at("mvol", tick), tl.at("pan", tick)
      local mdepth, mspeed, mrange = tl.at("mdepth", tick), tl.at("mspeed", tick), tl.at("mrange", tick)
      local semis = key - reg.key + bend / 128 * brange
      -- vibrato: its phase runs on from when it may start (the delay after the note)
      local since = t - t0 * tickS - tl.at("mdelay", tick) * tickS
      if since > 0 then
        if lfoT then lfoPhase = lfoPhase + 2 * pi * mspeed * M.LFO_HZ_PER_SPEED * (t - lfoT) end
        lfoT = t
        if mdepth ~= 0 then semis = semis + sin(lfoPhase) * mdepth / 128 * mrange end
      end
      ratio = baseRatio * 2 ^ (semis / 12)
      local p = pan + reg.pan - 64
      if p < 0 then p = 0 elseif p > 127 then p = 127 end
      -- 64 is the exact centre: 0..64 and 64..127 each span half the field
      local x = p <= 64 and (p - 64) / 64 or (p - 64) / 63
      lg, rg = cos((x + 1) * pi / 4), sin((x + 1) * pi / 4)
      if offAt and t >= offAt and phase ~= "release" then phase = "release" end
      if phase == "attack" then
        env = floor(env * attackRate(a) / 255)
        if env > -16 then
          env = 0
          phase = hold ~= 0 and "hold" or "decay"
        end
      elseif phase == "hold" then
        holdLeft = holdLeft - M.ENV_STEP
        if holdLeft <= 0 then phase = "decay" end
      elseif phase == "decay" then
        env = env - releaseRate(dcy)
        if env <= susDb then
          env = susDb
          phase = "sustain"
        end
      elseif phase == "release" then
        env = env - releaseRate(rel)
      end
      if env <= ENV_FLOOR then break end
      amp = velGain * (vol / 127) ^ 2 * (mvol / 127) ^ 2 * 10 ^ (env / 128 / 20)
    end
    local ip = floor(pos)
    if ip >= nsrc - 1 then
      if wav.loop and wav.loopStart < nsrc - 1 then
        pos = pos - (nsrc - wav.loopStart)
        ip = floor(pos)
      else
        break
      end
    end
    local fr = pos - ip
    local v = src[ip] + (src[ip + 1] - src[ip]) * fr
    L[i] = L[i] + v * amp * lg
    R[i] = R[i] + v * amp * rg
    last = i
    pos = pos + ratio
    i = i + 1
  end
  return last
end

function M.render(sound, archive, deps)
  local seq = sound.seq
  local data = section(seq, 0, "DATA")
  if not data then return nil, "no DATA section" end
  local d = seq:sub(data + 8 + 1)
  local rng = newRng(12345)
  local tracks, order, seen = {}, {}, {}
  local pending = { { 0, 0 } }
  while #pending > 0 do
    local item = table.remove(pending, 1)
    if not seen[item[1]] then
      seen[item[1]] = true
      local ev, opens = parseTrack(d, item[2], rng)
      tracks[item[1]] = ev
      order[#order + 1] = item[1]
      for _, o in ipairs(opens) do pending[#pending + 1] = o end
    end
  end
  table.sort(order)
  local bank = sound.banks[1]
  local insts = bank and bankRegions(bank) or {}
  local wavecache = {}
  -- the sequence's own timebase (b0) and tempo (e1), set once at the start
  local timebase, tempo = M.TIMEBASE, M.TEMPO
  for _, idx in ipairs(order) do
    for _, e in ipairs(tracks[idx]) do
      if e[2] == "set" and e[3] == 0xb0 and e[4] > 0 then timebase = e[4] end
      if e[2] == "set" and e[3] == 0xe1 and e[4] > 0 then tempo = e[4] end
    end
  end
  local tickS = 60 / (tempo * timebase)
  local soundGain = sound.volume / 127
  local size = floor(M.MAX_SECONDS * M.OUT_RATE)
  local L, R = {}, {}
  for i = 0, size - 1 do L[i], R[i] = 0, 0 end
  local last = 0
  for _, idx in ipairs(order) do
    -- the whole track's live parameters first, then its notes play against them
    local tl = newTimeline()
    for _, e in ipairs(tracks[idx]) do
      if e[2] == "set" and LIVE[e[3]] then tl.set(LIVE[e[3]], e[1], e[4], e[5]) end
    end
    local st = { prg = 0, transpose = 0 }
    for _, e in ipairs(tracks[idx]) do
      local t, kind = e[1], e[2]
      if kind == "prg" then
        st.prg = e[3]
      elseif kind == "set" and AT_NOTE[e[3]] then
        st[AT_NOTE[e[3]]] = e[4]
      elseif kind == "note" then
        local k = e[3] + st.transpose
        local reg
        for _, r in ipairs(insts[st.prg] or {}) do
          if r[1] <= k and k <= r[2] then reg = r[3]; break end
        end
        if reg then
          local w = reg.wave
          local wkey = w[1] .. ":" .. w[2]
          if wavecache[wkey] == nil then
            local bytes = archive:wave(w[1], w[2])
            wavecache[wkey] = bytes and cwav(bytes, deps.dsp) or false
          end
          if wavecache[wkey] then
            local stc = {}
            for kk, vv in pairs(st) do stc[kk] = vv end
            local endAt = mixVoice(L, R, size, wavecache[wkey], reg, stc, tl, t, k, e[4], e[5], tickS, soundGain)
            if endAt > last then last = endAt end
          end
        end
      end
    end
  end
  return L, R, math.min(size, last + 1)
end

-- 16-bit WAV; mono when the channels are the same
function M.wav(L, R, n)
  local mono = true
  for i = 0, n - 1 do
    if math.abs(L[i] - R[i]) > 1e-6 then mono = false; break end
  end
  local nch = mono and 1 or 2
  local parts, bytes, j = {}, {}, 0
  local function put(v)
    local x = floor(v * 32767 + 0.5)
    if x < -32768 then x = -32768 elseif x > 32767 then x = 32767 end
    if x < 0 then x = x + 65536 end
    bytes[j + 1], bytes[j + 2] = x % 256, floor(x / 256)
    j = j + 2
    if j >= 4096 then
      parts[#parts + 1] = string.char(unpack(bytes, 1, j))
      j = 0
    end
  end
  for i = 0, n - 1 do
    put(L[i])
    if not mono then put(R[i]) end
  end
  if j > 0 then parts[#parts + 1] = string.char(unpack(bytes, 1, j)) end
  local pcm = table.concat(parts)
  local function le32(v) return string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256) end
  return "RIFF" .. le32(36 + #pcm) .. "WAVEfmt " .. le32(16) .. string.char(1, 0, nch, 0)
    .. le32(M.OUT_RATE) .. le32(M.OUT_RATE * nch * 2) .. string.char(nch * 2, 0, 16, 0)
    .. "data" .. le32(#pcm) .. pcm, mono
end

return M
