-- Background job: render PlayNav's own songs (data/chip_songs.lua) and sound effects
-- (data/chip_sounds.lua) on the chip synth (src/chipsynth.lua) into WAV bytes, off the main
-- thread. require is refused in a job, so all three arrive as source strings.
-- arg = { synth = <src>, songs = <src>, sounds = <src> }
-- returns { tracks = { [id] = { wav, samples, loop, loopStart } }, sounds = { [id] = wav },
--   errors = { [id] = why }, rate }

local arg = ...
local Synth = assert(load(arg.synth, "=chipsynth"))()
local songs = arg.songs and assert(load(arg.songs, "=chip_songs"))() or {}
local effects = arg.sounds and assert(load(arg.sounds, "=chip_sounds"))() or {}

local tracks, sounds, errors = {}, {}, {}
for id, song in pairs(songs) do
  local ok, L, R, n, loopStart = pcall(Synth.render, song, songs)
  if ok then
    tracks[id] = { wav = Synth.wav(L, R, n), samples = n, loop = loopStart ~= nil, loopStart = loopStart or 0 }
  else
    errors[id] = tostring(L)
  end
end
for id, def in pairs(effects) do
  local ok, buf, n = pcall(Synth.effect, def)
  if ok then sounds[id] = Synth.wavMono(buf, n) else errors[id] = tostring(buf) end
end
return { tracks = tracks, sounds = sounds, errors = errors, rate = Synth.RATE }
