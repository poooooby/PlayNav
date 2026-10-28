-- Background job: render NaviPlay's own sound effects (data/chip_sounds.lua) on the chip synth
-- (src/chipsynth.lua) into WAV bytes, off the main thread. require is refused in a job, so both
-- arrive as source strings. (Its music is the game's own songs: src/training/music.lua.)
-- arg = { synth = <src>, sounds = <src> }
-- returns { sounds = { [id] = wav }, errors = { [id] = why }, rate }

local arg = ...
local Synth = assert(load(arg.synth, "=chipsynth"))()
local effects = arg.sounds and assert(load(arg.sounds, "=chip_sounds"))() or {}

local sounds, errors = {}, {}
for id, def in pairs(effects) do
  local ok, buf, n = pcall(Synth.effect, def)
  if ok then sounds[id] = Synth.wavMono(buf, n) else errors[id] = tostring(buf) end
end
return { sounds = sounds, errors = errors, rate = Synth.RATE }
