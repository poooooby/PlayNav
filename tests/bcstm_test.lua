-- The BCSTM decoder (src/import/bcstm.lua) against tools/bcstm.py's WAV of the same stream.
-- Needs the game's files in the work tree (oras-extract/romfs/sound and snd/, made with
-- tools/romfs_extract.py and tools/bcstm.py); skips without them.
package.path = "mods/play_nav/?.lua;" .. package.path
local home = os.getenv("USERPROFILE") or os.getenv("HOME") or "."
local work = os.getenv("ORAS_WORK") or (home .. "/Documents/oras-extract")
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local src = slurp(work .. "/romfs/sound/bgm_xy_sp_menu.dspadpcm.bcstm")
local ref = slurp(work .. "/snd/sp_menu.wav")
if not (src and ref) then
  print("bcstm_test: SKIP (no work tree streams)")
  return
end
local B = dofile("mods/play_nav/src/import/bcstm.lua")
local fails, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then fails = fails + 1; print("FAIL " .. what) end
end
local h = assert(B.parse(src))
check(h.channels == 2 and h.rate == 28000, "header: 2 channels at 28000 Hz")
check(h.loop and h.loopStart == 172032 and h.samples == 488267, "loop point and length")
local t0 = os.clock()
local wav, info = B.wav(src)
print(("decoded %d samples in %.2f s"):format(info.samples, os.clock() - t0))
check(info.samples == 488267, "every sample decoded")
check(#wav == #ref, ("wav size %d vs reference %d"):format(#wav, #ref))
-- python's wave module writes the same 44-byte header; compare the PCM
check(wav:sub(45) == ref:sub(45), "PCM matches tools/bcstm.py")
check(B.parse("nope") == nil, "rejects other files")
print(("bcstm_test: %d checks, %d failed"):format(checks, fails))
if fails > 0 then os.exit(1) end
