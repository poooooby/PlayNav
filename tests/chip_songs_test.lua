-- PlayNav's own songs (data/chip_songs.lua) on the chip synth (src/chipsynth.lua): every voice
-- of a song runs whole bars and as many as the others, the notation parses, each song renders
-- at the game's music level with its peaks under the ceiling and its loop inside it. Set
-- CHIP_OUT=<dir> to also write the WAVs for a listen. Run from the engine root:
--   luajit mods/play_nav/tests/chip_songs_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function module(path)
  local f = assert(io.open("mods/play_nav/" .. path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end
local Synth = module("src/chipsynth.lua")
local songs = module("data/chip_songs.lua")

-- the notation
local p = Synth.parse("C4/4 D#4/8. r Bb3/16 |")
T.eq(p[1][1], 60, "C4 is MIDI 60")
T.eq(p[1][2], 1, "a quarter is a beat")
T.eq(p[2][1], 63, "a sharp raises a semitone")
T.eq(p[2][2], 0.75, "a dotted eighth is three quarters of a beat")
T.eq(p[3][1], nil, "r is a rest")
T.eq(p[3][2], 0.75, "a length carries on")
T.eq(p[4][1], 58, "a flat lowers a semitone")
T.check(not pcall(Synth.parse, "H4/4"), "a bad pitch is refused")

local ids = {}
for id in pairs(songs) do ids[#ids + 1] = id end
table.sort(ids)
T.check(#ids >= 6, "Super Training's six tracks are written")
for _, want in ipairs({ "bgm/sp_menu", "bgm/sp_gamestart", "bgm/sp_stage", "bgm/sp_stage_02", "bgm/sp_clear", "bgm/sp_gameover" }) do
  T.check(songs[want] ~= nil, want .. " is written")
end

local out = os.getenv("CHIP_OUT")
for _, id in ipairs(ids) do
  local song = songs[id]
  local base = song.from and songs[song.from] or song
  -- the voices' lengths in beats
  local lengths = {}
  for v, voice in ipairs(base.voices) do
    local b = 0
    for _, e in ipairs(Synth.parse(voice.notes, voice.wave == "drums")) do b = b + e[2] end
    lengths[v] = b
  end
  local same = true
  for v = 2, #lengths do if math.abs(lengths[v] - lengths[1]) > 1e-9 then same = false end end
  T.check(same, ("%s: every voice runs the same length (%s)"):format(id, table.concat(lengths, ", ")))
  T.check(lengths[1] % 4 == 0, ("%s: whole bars (%g beats)"):format(id, lengths[1]))
  local t0 = os.clock()
  local L, R, n, loopStart = Synth.render(song, songs)
  local secs = os.clock() - t0
  local sum, peak = 0, 0
  for i = 1, n do
    sum = sum + L[i] * L[i] + R[i] * R[i]
    peak = math.max(peak, math.abs(L[i]), math.abs(R[i]))
  end
  local rms = math.sqrt(sum / (2 * n))
  local db = 20 * math.log10(rms)
  T.check(math.abs(db - 20 * math.log10(Synth.TARGET_RMS)) < 1.5, ("%s: at the music level (%.1f dB)"):format(id, db))
  T.check(peak <= Synth.PEAK + 1e-6, ("%s: peaks under the ceiling (%.3f)"):format(id, peak))
  if base.loop then T.check(loopStart and loopStart < n, ("%s: its loop starts inside it"):format(id)) end
  print(("  %s: %.1f s, rendered in %.2f s, %.1f dB rms, peak %.2f"):format(id, n / Synth.RATE, secs, db, peak))
  if out then
    local f = io.open(out .. "/" .. id:gsub("^bgm/", "") .. ".wav", "wb")
    if f then f:write(Synth.wav(L, R, n)); f:close() end
  end
end

-- the sound effects: every one Super Training's map names is made, each at its peak, the steady
-- ones four seconds long
local effects = module("data/chip_sounds.lua")
local map = module("data/training_sounds.lua")
local wanted = {}
local function want(v)
  if type(v) == "string" and v:match("^se/") then wanted[v] = true
  elseif type(v) == "table" then for _, x in pairs(v) do want(x) end end
end
for _, v in pairs(map) do want(v) end
for id in pairs(wanted) do T.check(effects[id] ~= nil, id .. " has a sound of PlayNav's own") end
local STEADY = { ["se/sp_024"] = true, ["se/sp_034"] = true, ["se/sp_041"] = true }
for id, def in pairs(effects) do
  local buf, n = Synth.effect(def)
  local peak = 0
  for i = 1, n do peak = math.max(peak, math.abs(buf[i])) end
  T.check(math.abs(peak - (def.peak or 0.75)) < 1e-6, ("%s: at its peak (%.2f)"):format(id, peak))
  local secs = n / Synth.RATE
  if STEADY[id] then T.check(secs >= 3.99, ("%s: four steady seconds (%.2f)"):format(id, secs))
  else T.check(secs > 0.02 and secs < 4, ("%s: a short effect (%.2f s)"):format(id, secs)) end
  if out then
    local f = io.open(out .. "/" .. id:gsub("^se/", "se_") .. ".wav", "wb")
    if f then f:write(Synth.wavMono(buf, n)); f:close() end
  end
end

T.finish("play_nav chip songs")
