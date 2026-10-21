-- The sound-effect renderer (src/import/bcsar.lua + seqsynth.lua) against tools/bcsar.py's
-- WAVs of the same effects. Needs the game's sound archive and the reference renders in the
-- work tree (oras-extract/romfs/sound, made with tools/romfs_extract.py, and
-- oras-extract/se_sp from `python tools/bcsar.py renderall ... SE_SP ...`); skips without them.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local home = os.getenv("USERPROFILE") or os.getenv("HOME") or "."
local work = os.getenv("ORAS_WORK") or (home .. "/Documents/oras-extract")
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local bcsarPath = work .. "/romfs/sound/sango_sound.bcsar"
local f = io.open(bcsarPath, "rb")
if not (f and slurp(work .. "/se_sp/SEQ_SE_SP_001.wav")) then
  print("bcsar_test: SKIP (no work tree sound archive / reference renders)")
  if f then f:close() end
  return
end
local size = f:seek("end")
local function read(off, len) f:seek("set", off); return f:read(len) end
local function load(path) return dofile("mods/play_nav/" .. path) end
local Bcsar = load("src/import/bcsar.lua")
local Bcstm = load("src/import/bcstm.lua")
local Seq = load("src/import/seqsynth.lua")

local ar = Bcsar.open(read, 0, size)
T.check(ar ~= nil, "the archive opens through ranged reads")
T.check(ar.ids["SEQ_SE_SP_001"] ~= nil, "names resolve")
T.eq(Bcsar.open(function() return "nope" end, 0, 4), nil, "not an archive: nil")

local function samples(wav)
  local ch = wav:byte(23)
  local out = {}
  for i = 45, #wav - 1, 2 do
    local v = wav:byte(i) + wav:byte(i + 1) * 256
    out[#out + 1] = v >= 32768 and v - 65536 or v
  end
  return out, ch
end

-- one note, waits, multi-track with sweeps and vibrato, three tracks, random, envelope decay
-- (and the two system sounds Super Training uses, whose references are in se_wide; MESSAGE has
-- empty key ranges and its own timebase / tempo)
-- SP_005 / SP_049: changes and sweeps after the note began (the burst's fall and fade)
for _, name in ipairs({ "SEQ_SE_SP_001", "SEQ_SE_SP_003", "SEQ_SE_SP_004", "SEQ_SE_SP_044", "SEQ_SE_SP_035", "SEQ_SE_SP_032",
  "SEQ_SE_SP_005", "SEQ_SE_SP_049",
  "SEQ_SE_SYS_057", "SEQ_SE_MESSAGE" }) do
  local snd = assert(ar:sound(name))
  local t0 = os.clock()
  local L, R, n = Seq.render(snd, ar, { dsp = Bcstm.dspBlock })
  local wav = Seq.wav(L, R, n)
  local mine, chm = samples(wav)
  local ref, chr = samples(slurp(work .. "/se_sp/" .. name .. ".wav") or slurp(work .. "/se_wide/" .. name .. ".wav"))
  T.eq(chm, chr, name .. ": the same channel count")
  T.eq(#mine, #ref, name .. ": the same length")
  local worst = 0
  for i = 1, math.min(#mine, #ref) do
    local dlt = math.abs(mine[i] - ref[i])
    if dlt > worst then worst = dlt end
  end
  T.check(worst <= 1, ("%s: sample for sample with tools/bcsar.py (worst %d LSB, %.2f s to render)"):format(name, worst, os.clock() - t0))
end

-- a song (music mode: calls, returns, the loop jump, the expression volume, the tail folded onto
-- the loop) at the game's tempo and sped up, against `python tools/bcsar.py music ... [tempo]`
-- (oras-extract/bgm_kw); Berry Picker's theme loops from 2.0 s to 34.0 s
for _, case in ipairs({ { 1, "x1", 65456, 1112752 }, { 1.25, "x1.25", 52365, 890202 } }) do
  local ref = slurp(work .. "/bgm_kw/SEQ_BGM_KW_GAME01_" .. case[2] .. ".wav")
  if ref then
    local t0 = os.clock()
    local L, R, n, loop = Seq.render(assert(ar:sound("SEQ_BGM_KW_GAME01")), ar,
      { dsp = Bcstm.dspBlock, music = true, tempoScale = case[1] })
    local secs = os.clock() - t0
    T.check(loop ~= nil and loop[1] == case[3] and loop[2] == case[4],
      ("GAME01 x%s: loop %s..%s (%s)"):format(case[1], tostring(loop and loop[1]), tostring(loop and loop[2]), case[2]))
    local mine = samples(Seq.wav(L, R, n))
    local theirs = samples(ref)
    T.eq(#mine, #theirs, "GAME01 x" .. case[1] .. ": the same length")
    local worst = 0
    for i = 1, math.min(#mine, #theirs) do
      local dlt = math.abs(mine[i] - theirs[i])
      if dlt > worst then worst = dlt end
    end
    T.check(worst <= 1, ("GAME01 x%s: sample for sample with tools/bcsar.py (worst %d LSB, %.1f s to render)"):format(case[1], worst, secs))
    -- raised to the recipe's level (Seq.level), against `bcsar.py music ... 1 12.3`
    local refG = case[1] == 1 and slurp(work .. "/bgm_kw/SEQ_BGM_KW_GAME01_x1_gain12.3.wav")
    if refG then
      Seq.level(L, R, n, 12.3)
      local mineG, theirsG = samples(Seq.wav(L, R, n)), samples(refG)
      local worstG, peak = 0, 0
      for i = 1, math.min(#mineG, #theirsG) do
        local dlt = math.abs(mineG[i] - theirsG[i])
        if dlt > worstG then worstG = dlt end
        if math.abs(mineG[i]) > peak then peak = math.abs(mineG[i]) end
      end
      T.eq(#mineG, #theirsG, "GAME01 x1 +12.3 dB: the same length")
      T.check(worstG <= 1, ("GAME01 x1 +12.3 dB: sample for sample with tools/bcsar.py (worst %d LSB)"):format(worstG))
      T.check(peak <= math.floor(Seq.LEVEL_CEIL * 32767 + 1), ("GAME01 x1 +12.3 dB: the limiter holds it at the ceiling (peak %d)"):format(peak))
    end
  end
end

-- the level: a song under the ceiling is only raised; a peak over it is turned down to the
-- ceiling, the gain easing in ahead of it and back out after it
do
  local n = 400
  local L, R = {}, {}
  for i = 0, n - 1 do L[i], R[i] = 0.1, -0.1 end
  Seq.level(L, R, n, 6)
  local k = 10 ^ (6 / 20)
  T.check(math.abs(L[0] - 0.1 * k) < 1e-12 and math.abs(R[n - 1] + 0.1 * k) < 1e-12, "level: under the ceiling, the gain alone")
  for i = 0, n - 1 do L[i], R[i] = 0.1, 0.1 end
  L[200] = 0.5   -- x2 = 1.0, over the ceiling
  Seq.level(L, R, n, 20 * math.log10(2))
  T.check(math.abs(L[200] - Seq.LEVEL_CEIL) < 1e-9, ("level: the peak held at the ceiling (%.4f)"):format(L[200]))
  T.check(L[198] < 0.2 and L[198] > 0.19 and R[198] == L[198], ("level: eased in ahead of the peak, both channels (%.5f)"):format(L[198]))
  T.check(R[260] < 0.2 and R[260] > R[201], ("level: easing back out after it (%.5f)"):format(R[260]))
  T.check(math.abs(L[0] - 0.2) < 1e-12 and math.abs(L[n - 1] - 0.2) < 1e-12, "level: far from it, the gain alone")
  -- a stream's cut: every sample of the WAV scaled, the header kept
  local L2, R2 = { [0] = 0.5, [1] = -0.5, [2] = 0.25 }, { [0] = 0.5, [1] = -0.5, [2] = 0.25 }
  local wav = Seq.wav(L2, R2, 3)
  local cut = Seq.scaleWav(wav, 20 * math.log10(0.5))
  local a, b = samples(wav), samples(cut)
  T.eq(cut:sub(1, 44), wav:sub(1, 44), "scaleWav: the header kept")
  T.check(math.abs(b[1] - a[1] / 2) <= 1 and math.abs(b[2] - a[2] / 2) <= 1 and math.abs(b[3] - a[3] / 2) <= 1,
    ("scaleWav: -6 dB halves each sample (%d %d %d -> %d %d %d)"):format(a[1], a[2], a[3], b[1], b[2], b[3]))
end
f:close()
T.finish()
