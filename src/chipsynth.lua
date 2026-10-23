-- PlayNav's own sound effects (data/chip_sounds.lua) made on a small chip synth: pulse waves
-- (12.5 / 25 / 50% duty), a triangle, a saw, a sine and noise, layered with envelopes into a
-- mono 16-bit WAV. Pure Lua (no love.*), so it runs inside a mod.job. (Its music is the game's
-- own songs: src/training/music.lua.)

local M = {}

M.RATE = 32000

-- a little deterministic noise (no math.random: the same effect renders the same everywhere)
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

return M
