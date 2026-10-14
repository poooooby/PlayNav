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
f:close()
T.finish()
