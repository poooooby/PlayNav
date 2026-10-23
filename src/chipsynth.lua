-- PlayNav's own music: songs written as note lists (data/chip_songs.lua) played on a small
-- chip synth - pulse waves (12.5 / 25 / 50% duty), a triangle, noise and three drums - into
-- stereo samples and a 16-bit WAV. Pure Lua (no love.*), so it runs inside a mod.job.
--
-- A voice: { wave, vol, pan (-1..1), env = { attack, decay, sustain, release } (seconds, the
-- sustain a level), gate (of the note's length), vib (depth in semitones), octave (shift),
-- notes }. Notes: whitespace-separated tokens, "|" (a bar line) ignored: a pitch C4, F#5, Bb3
-- or a rest r, then /n for its length (1 whole, 2 half, 4 quarter, 8 eighth, 16) and . for
-- dotted; the length carries on until a token gives another. A drum voice (wave "drums") takes
-- k (kick), s (snare), h (hat) and r.
-- A song: { bpm, loop, loopBar (the bar the loop goes back to), transpose, voices } or
-- { from = <another song's id>, bpm, transpose } (the same notes at another tempo / key).

local M = {}

M.RATE = 32000
M.TARGET_RMS = 0.21   -- about -13.6 dBFS, the level the game's own music is extracted at
M.PEAK = 0.95

local NOTE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

-- "F#5/8." -> midi, beats; "r/4" -> nil, beats; a drum letter -> the letter, beats
function M.parse(text, drums)
  local out, len = {}, 1
  for tok in text:gmatch("%S+") do
    if tok ~= "|" then
      local head, div, dot = tok:match("^([^/]+)/?(%d*)(%.?)$")
      if not head then error("bad note token: " .. tok, 0) end
      if div ~= "" then
        len = 4 / tonumber(div)
        if dot == "." then len = len * 1.5 end
      end
      local pitch = nil
      if head ~= "r" then
        if drums then
          pitch = head
        else
          local name, acc, oct = head:match("^([A-G])([#b]?)(%-?%d)$")
          if not name then error("bad pitch: " .. head, 0) end
          pitch = (tonumber(oct) + 1) * 12 + NOTE[name] + (acc == "#" and 1 or acc == "b" and -1 or 0)
        end
      end
      out[#out + 1] = { pitch, len }
    end
  end
  return out
end

-- a little deterministic noise (no math.random: the same song renders the same everywhere)
local function lcg(seed)
  local s = seed or 22222
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 1073741824 - 1
  end
end

-- the pulses band-limited (polyBLEP at both edges), so high notes do not fold back as hiss
local function blep(t, dt)
  if t < dt then
    t = t / dt
    return t + t - t * t - 1
  elseif t > 1 - dt then
    t = (t - 1) / dt
    return t * t + t + t + 1
  end
  return 0
end
local function pulse(duty)
  return function(p, dt)
    local v = p < duty and 1 or -1
    return v + blep(p, dt) - blep((p - duty) % 1, dt)
  end
end
local WAVE = {
  pulse12 = pulse(0.125),
  pulse25 = pulse(0.25),
  pulse50 = pulse(0.5),
  tri = function(p) return 4 * math.abs(p - 0.5) - 1 end,
  saw = function(p, dt) return 2 * p - 1 - blep(p, dt) end,
}

local function envAt(env, t, gate)
  local a, d, s, r = env[1], env[2], env[3], env[4]
  local level
  if t < a then level = t / a
  elseif t < a + d then level = 1 - (1 - s) * (t - a) / d
  else level = s end
  if t > gate then
    local k = 1 - (t - gate) / r
    if k <= 0 then return 0 end
    -- the release starts from where the note was at the gate
    local atGate = gate < a and gate / a or (gate < a + d and 1 - (1 - s) * (gate - a) / d or s)
    level = atGate * k
  end
  return level
end

-- one drum hit into the buffers from sample i0
local function drum(L, R, n, i0, kind, vol, panL, panR, noise)
  local rate = M.RATE
  local len = math.floor(rate * (kind == "k" and 0.18 or kind == "s" and 0.16 or 0.05))
  local ph, prev = 0, 0
  for j = 0, len - 1 do
    local i = i0 + j
    if i > n then break end
    local t = j / rate
    local v
    if kind == "k" then
      local f = 45 + 120 * math.exp(-t * 22)
      ph = (ph + f / rate) % 1
      v = math.sin(ph * 2 * math.pi) * math.exp(-t * 13)
    elseif kind == "s" then
      ph = (ph + 190 / rate) % 1
      v = noise() * 0.75 * math.exp(-t * 20) + math.sin(ph * 2 * math.pi) * 0.35 * math.exp(-t * 30)
    else
      local w = noise()
      v = (w - prev) * 0.5 * math.exp(-t * 70)
      prev = w
    end
    L[i] = L[i] + v * vol * panL
    R[i] = R[i] + v * vol * panR
  end
end

-- the song's samples: L, R (1-based float tables), n, loopStart (0-based sample, or nil)
function M.render(song, songs)
  local base = song
  local transpose, bpm = song.transpose or 0, song.bpm
  if song.from then
    base = songs and songs[song.from]
    if not base then error("song from " .. tostring(song.from) .. " is missing", 0) end
    transpose = (base.transpose or 0) + (song.transpose or 0)
    bpm = song.bpm or base.bpm
  end
  local rate = M.RATE
  local spb = 60 / bpm
  -- the length: the longest voice
  local parsed, beats = {}, 0
  for v, voice in ipairs(base.voices) do
    local list = M.parse(voice.notes, voice.wave == "drums")
    parsed[v] = list
    local b = 0
    for _, e in ipairs(list) do b = b + e[2] end
    beats = math.max(beats, b)
  end
  local n = math.floor(beats * spb * rate + 0.5)
  local loopStart = base.loop and math.floor((base.loopBar or 0) * 4 * spb * rate + 0.5) or nil
  local L, R = {}, {}
  for i = 1, n do L[i], R[i] = 0, 0 end
  local noise = lcg(9001)
  for v, voice in ipairs(base.voices) do
    local pan = voice.pan or 0
    local panL, panR = math.min(1, 1 - pan), math.min(1, 1 + pan)
    local vol = voice.vol or 0.5
    local at = 0
    for _, e in ipairs(parsed[v]) do
      local pitch, len = e[1], e[2]
      local i0 = math.floor(at * spb * rate) + 1
      if pitch and voice.wave == "drums" then
        drum(L, R, n, i0, pitch, vol, panL, panR, noise)
      elseif pitch then
        local midi = pitch + transpose + 12 * (voice.octave or 0)
        local freq = 440 * 2 ^ ((midi - 69) / 12)
        local env = voice.env or { 0.005, 0.1, 0.7, 0.06 }
        local gate = len * spb * (voice.gate or 0.88)
        local total = math.floor((gate + env[4]) * rate)
        local wave = WAVE[voice.wave] or WAVE.pulse50
        local vib, ph = voice.vib or 0, 0
        for j = 0, total - 1 do
          local i = i0 + j
          if i > n then
            -- a tail past the end comes round to the loop's start
            if not loopStart then break end
            i = i - n + loopStart
            if i > n then break end
          end
          local t = j / rate
          local f = freq
          if vib > 0 and t > 0.15 then f = freq * 2 ^ (vib * math.sin(t * 2 * math.pi * 5.5) / 12) end
          local dt = f / rate
          ph = (ph + dt) % 1
          local s = wave(ph, dt) * envAt(env, t, gate) * vol
          L[i] = L[i] + s * panL
          R[i] = R[i] + s * panR
        end
      end
      at = at + len
    end
  end
  -- a gentle low-pass takes the edge off the pulses, then the level: the game's music's rms,
  -- the peaks rounded off under PEAK
  local yl, yr, sum = 0, 0, 0
  for i = 1, n do
    yl = yl + (L[i] - yl) * 0.55
    yr = yr + (R[i] - yr) * 0.55
    L[i], R[i] = yl, yr
    sum = sum + yl * yl + yr * yr
  end
  local rms = math.sqrt(sum / math.max(1, 2 * n))
  local g = rms > 0 and M.TARGET_RMS / rms or 1
  local knee = M.PEAK * 0.8
  local function shape(x)
    x = x * g
    local a = math.abs(x)
    if a <= knee then return x end
    local over = (a - knee) / (M.PEAK - knee)
    local y = knee + (M.PEAK - knee) * (over / (1 + over))
    return x < 0 and -y or y
  end
  for i = 1, n do L[i], R[i] = shape(L[i]), shape(R[i]) end
  return L, R, n, loopStart
end

-- ------- sound effects (data/chip_sounds.lua): layers summed into one mono buffer.
-- A layer: { at, dur (seconds), wave (pulse12/25/50, tri, saw, sine, noise), f0 [, f1] (Hz, an
-- exponential sweep) or steps = { Hz, ... } with step (seconds each), vol, attack, decay (an
-- exponential fall, per second), release (a fade over the last seconds), lp [, lp1] (noise's
-- low-pass, Hz), vib = { semitones, Hz }, trem = { depth, Hz } }.
-- An effect: { layers, peak (its loudest sample, default 0.75) }.
function M.effect(def)
  local rate = M.RATE
  local len = 0
  for _, l in ipairs(def.layers) do len = math.max(len, (l.at or 0) + l.dur) end
  local n = math.max(1, math.floor(len * rate + 0.5))
  local buf = {}
  for i = 1, n do buf[i] = 0 end
  local noise = lcg(4242)
  for _, l in ipairs(def.layers) do
    local i0 = math.floor((l.at or 0) * rate)
    local count = math.floor(l.dur * rate)
    local wave = WAVE[l.wave]
    local ph, y = 0, 0
    local attack, decay, release = l.attack or 0.002, l.decay, l.release or 0.01
    for j = 0, count - 1 do
      local i = i0 + j + 1
      if i > n then break end
      local t = j / rate
      local k = t / l.dur
      local v
      if l.wave == "noise" then
        local fc = l.lp and (l.lp1 and l.lp * (l.lp1 / l.lp) ^ k or l.lp) or rate / 2
        local a = 1 - math.exp(-2 * math.pi * fc / rate)
        y = y + a * (noise() - y)
        v = y
      else
        local f
        if l.steps then
          f = l.steps[math.min(#l.steps, math.floor(t / l.step) + 1)]
        else
          f = l.f1 and l.f0 * (l.f1 / l.f0) ^ k or l.f0
        end
        if l.vib then f = f * 2 ^ (l.vib[1] * math.sin(2 * math.pi * l.vib[2] * t) / 12) end
        local dt = f / rate
        ph = (ph + dt) % 1
        if l.wave == "sine" then v = math.sin(ph * 2 * math.pi) else v = wave(ph, dt) end
      end
      local amp = (l.vol or 0.5) * math.min(1, t / attack)
      if decay then amp = amp * math.exp(-decay * t) end
      local left = l.dur - t
      if left < release then amp = amp * left / release end
      if l.trem then amp = amp * (1 - l.trem[1] * (0.5 + 0.5 * math.sin(2 * math.pi * l.trem[2] * t))) end
      buf[i] = buf[i] + v * amp
    end
  end
  local peak = 0
  for i = 1, n do peak = math.max(peak, math.abs(buf[i])) end
  local g = peak > 0 and (def.peak or 0.75) / peak or 1
  for i = 1, n do buf[i] = buf[i] * g end
  return buf, n
end

-- 16-bit mono WAV bytes
function M.wavMono(buf, n, rate)
  rate = rate or M.RATE
  local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local data, chunk, char = {}, {}, string.char
  for i = 1, n do
    local s = math.floor(math.max(-1, math.min(1, buf[i])) * 32767 + 0.5)
    if s < 0 then s = s + 65536 end
    chunk[#chunk + 1] = char(s % 256, math.floor(s / 256))
    if #chunk >= 8192 then data[#data + 1] = table.concat(chunk); chunk = {} end
  end
  data[#data + 1] = table.concat(chunk)
  local pcm = table.concat(data)
  return "RIFF" .. u32(36 + #pcm) .. "WAVE" .. "fmt " .. u32(16) .. u16(1) .. u16(1) .. u32(rate)
    .. u32(rate * 2) .. u16(2) .. u16(16) .. "data" .. u32(#pcm) .. pcm
end

-- 16-bit stereo WAV bytes
function M.wav(L, R, n, rate)
  rate = rate or M.RATE
  local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local data = {}
  local chunk = {}
  local char = string.char
  for i = 1, n do
    local l = math.floor(math.max(-1, math.min(1, L[i])) * 32767 + 0.5)
    local r = math.floor(math.max(-1, math.min(1, R[i])) * 32767 + 0.5)
    if l < 0 then l = l + 65536 end
    if r < 0 then r = r + 65536 end
    chunk[#chunk + 1] = char(l % 256, math.floor(l / 256), r % 256, math.floor(r / 256))
    if #chunk >= 4096 then
      data[#data + 1] = table.concat(chunk)
      chunk = {}
    end
  end
  data[#data + 1] = table.concat(chunk)
  local pcm = table.concat(data)
  return "RIFF" .. u32(36 + #pcm) .. "WAVE" .. "fmt " .. u32(16) .. u16(1) .. u16(2) .. u32(rate)
    .. u32(rate * 4) .. u16(4) .. u16(16) .. "data" .. u32(#pcm) .. pcm
end

return M
