-- PlayNav's own music for Super Training and Pokemon-Amie's minigames, written for
-- src/chipsynth.lua (the notation is described there). Original tunes; every voice of a song runs the same number of bars
-- (tests/chip_songs_test.lua checks it). Ids are the tracks the music player asks for.

local LEAD = { 0.004, 0.10, 0.65, 0.07 }
local ARP = { 0.002, 0.06, 0.35, 0.04 }
local BASS = { 0.003, 0.08, 0.8, 0.05 }
local BRASS = { 0.01, 0.12, 0.75, 0.12 }

-- a voice of chord tones in eighths, per bar (root, third, fifth, third, twice)
local function arp(chords)
  local out = {}
  for _, c in ipairs(chords) do
    out[#out + 1] = ("%s/8 %s %s %s %s %s %s %s |"):format(c[1], c[2], c[3], c[2], c[1], c[2], c[3], c[2])
  end
  return table.concat(out, " ")
end
-- the bass bouncing between a root and its octave in eighths
local function bounce(roots)
  local out = {}
  for _, r in ipairs(roots) do
    out[#out + 1] = ("%s2/8 %s3 %s2 %s3 %s2 %s3 %s2 %s3 |"):format(r, r, r, r, r, r, r, r)
  end
  return table.concat(out, " ")
end
local function rep(s, n) return (s .. " "):rep(n) end

local AM, F, C, G = { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "C4", "E4", "G4" }, { "G3", "B3", "D4" }
local E, EM, DM = { "E3", "G#3", "B3" }, { "E3", "G3", "B3" }, { "D4", "F4", "A4" }
local BEAT = "k/8 h s h k k s h |"
local FILL = "s/8 s s s k s s s |"

local songs = {}

-- the regimen picker: easy-going, C major
songs["bgm/sp_menu"] = { bpm = 116, loop = true, loopBar = 0, voices = {
  { wave = "pulse25", vol = 0.42, pan = -0.15, env = LEAD, vib = 0.15, notes = [[
    E5/4 G5/8 E5/8 D5/4 C5/4 | A4/4 C5/8 E5/8 A5/4 G5/4 | F5/4 E5/8 D5/8 C5/4 A4/4 | B4/4 D5/8 G5/8 F5/4 D5/4 |
    E5/8 G5/8 C6/4 B5/8 A5/8 G5/4 | A5/8 G5/8 E5/4 C5/8 D5/8 E5/4 | F5/4 A5/4 G5/8 F5/8 E5/8 D5/8 | D5/2 G4/4 B4/4 | ]] },
  { wave = "pulse12", vol = 0.16, pan = 0.35, env = ARP, notes = arp({ C, AM, F, G, C, AM, F, G }) },
  { wave = "tri", vol = 0.5, env = BASS, gate = 0.95, notes = [[
    C3/4 C3/8 C3/8 G2/4 C3/4 | A2/4 A2/8 A2/8 E2/4 A2/4 | F2/4 F2/8 F2/8 C3/4 F2/4 | G2/4 G2/8 G2/8 D3/4 G2/4 |
    C3/4 C3/8 C3/8 G2/4 C3/4 | A2/4 A2/8 A2/8 E2/4 A2/4 | F2/4 F2/8 F2/8 C3/4 F2/4 | G2/4 G2/8 G2/8 D3/4 G2/4 | ]] },
  { wave = "drums", vol = 0.3, notes = rep("h/8 h s h h h s h |", 8) },
} }

-- a regimen's title: a short fanfare, played once
songs["bgm/sp_gamestart"] = { bpm = 150, loop = false, voices = {
  { wave = "pulse50", vol = 0.4, pan = -0.1, env = BRASS, notes = "G4/8 C5 E5 G5 r E5 G5/4 | C6/2. r/4 |" },
  { wave = "pulse25", vol = 0.3, pan = 0.25, env = BRASS, notes = "E4/8 G4 C5 E5 r C5 E5/4 | G5/2. r/4 |" },
  { wave = "tri", vol = 0.5, env = BASS, notes = "C3/4 C3 G2 C3 | C3/2. r/4 |" },
  { wave = "drums", vol = 0.4, notes = "k/8 h k h s h s s | k/2. r/4 |" },
} }

-- a regimen: driving, A minor, sixteen bars
local STAGE = { bpm = 152, loop = true, loopBar = 0, voices = {
  { wave = "pulse25", vol = 0.4, pan = -0.15, env = LEAD, vib = 0.12, notes = [[
    A4/8 A4 C5 E5 A5/4 G5/8 E5 | F5/4 E5/8 C5 A4/4 C5 | G4/8 C5 E5 G5 E5/4 D5 | D5/8 B4 G4/4 B4/8 D5 G5/4 |
    A5/8 G5 E5 C5 A4/4 E5 | F5/8 E5 F5 A5 C6/4 A5 | B5/8 A5 G5 D5 B4/4 D5 | E5/2 G#5/4 B5 |
    A5/4 F5/8 A5 C6/4 A5 | B5/4 G5/8 B5 D6/4 B5 | G5/8 E5 B4 E5 G5/4 B5 | A5/4. E5/8 C5/4 A4 |
    D5/8 F5 A5 F5 D6/4 A5 | B5/8 G5 D5 G5 B5/4 D6 | E6/4 D6/8 C6 B5/4 G#5 | E5/2 B4/4 G#4 | ]] },
  { wave = "pulse12", vol = 0.14, pan = 0.35, env = ARP,
    notes = arp({ AM, F, C, G, AM, F, G, E, F, G, EM, AM, DM, G, E, E }) },
  { wave = "tri", vol = 0.5, env = BASS, gate = 0.8,
    notes = bounce({ "A", "F", "C", "G", "A", "F", "G", "E", "F", "G", "E", "A", "D", "G", "E", "E" }) },
  { wave = "drums", vol = 0.32, notes = rep(BEAT, 7) .. FILL .. rep(BEAT, 7) .. FILL },
} }
songs["bgm/sp_stage"] = STAGE
-- a secret regimen: the same tune up a fourth, a little faster
songs["bgm/sp_stage_02"] = { from = "bgm/sp_stage", transpose = 5, bpm = 160 }

-- cleared, through the results: a fanfare, then a bright four-bar loop
songs["bgm/sp_clear"] = { bpm = 132, loop = true, loopBar = 2, voices = {
  { wave = "pulse50", vol = 0.38, pan = -0.1, env = BRASS, vib = 0.1, notes = [[
    C5/8 E5 G5 C6 r G5 C6/4 | D6/8 C6 B5 C6 E6/2 |
    E5/4 G5 C6 G5 | A5/4 F5/8 A5 C6/4 A5 | B5/4 D6/8 B5 G5/4 F5 | E5/4 C5 G4/2 | ]] },
  { wave = "pulse12", vol = 0.15, pan = 0.35, env = ARP, notes = arp({ C, G, C, F, G, C }) },
  { wave = "tri", vol = 0.5, env = BASS, notes = [[
    C3/4 G2 C3 G2 | C3/4 G2 C3/2 |
    C3/4 G2 C3 G2 | F2/4 C3 F2 C3 | G2/4 D3 G2 D3 | C3/4 G2 C3 G2 | ]] },
  { wave = "drums", vol = 0.3, notes = "k/8 h s h k h s h | k/8 h s h k/4 s | " .. rep(BEAT, 4) },
} }

-- time ran out, through the results: a falling phrase, then a quiet loop
songs["bgm/sp_gameover"] = { bpm = 96, loop = true, loopBar = 2, voices = {
  { wave = "pulse25", vol = 0.36, pan = -0.1, env = LEAD, vib = 0.18, notes = [[
    A4/4 G4 F4 E4 | D4/2 E4/2 |
    C5/4 B4/8 A4 E4/2 | F4/4 A4 D5/2 | B4/4 G#4/8 E4 B4/2 | A4/2. r/4 | ]] },
  { wave = "pulse12", vol = 0.12, pan = 0.3, env = ARP, notes = arp({ F, E, AM, DM, E, AM }) },
  { wave = "tri", vol = 0.45, env = BASS, notes = [[
    F2/2 E2 | D2/2 E2 |
    A2/2 E2 | D2/2 A2 | E2/2 B2 | A2/1 | ]] },
} }

-- ------- Pokemon-Amie's minigames (src/training/music.lua's second player, main's amieMusic)

local BB, D, BM, A = { "Bb3", "D4", "F4" }, { "D4", "F#4", "A4" }, { "B3", "D4", "F#4" }, { "A3", "C#4", "E4" }
local SOFT = { 0.02, 0.2, 0.6, 0.2 }

-- Berry Picker: a sunny, bouncing tune in F, eight bars round
songs["bgm/kw_game01"] = { bpm = 128, loop = true, loopBar = 0, voices = {
  { wave = "pulse25", vol = 0.4, pan = -0.15, env = LEAD, vib = 0.12, notes = [[
    F5/8 A5 C6/4 A5/8 F5 G5/4 | E5/8 G5 C6/4 G5/8 E5 C5/4 | D5/8 F5 A5/4 F5/8 D5 E5/4 | Bb4/8 D5 F5/4 D5/8 F5 Bb5/4 |
    A5/8 G5 F5/4 C5/8 F5 A5/4 | G5/8 E5 C5/4 E5/8 G5 C6/4 | Bb5/8 A5 G5/4 F5/8 D5 Bb4/4 | C5/4 E5 G5 C6 | ]] },
  { wave = "pulse12", vol = 0.15, pan = 0.35, env = ARP, notes = arp({ F, C, DM, BB, F, C, BB, C }) },
  { wave = "tri", vol = 0.5, env = BASS, gate = 0.8, notes = bounce({ "F", "C", "D", "Bb", "F", "C", "Bb", "C" }) },
  { wave = "drums", vol = 0.3, notes = rep(BEAT, 7) .. FILL },
} }
-- the same, quicker as the time runs short (30 s, then 10 s left)
songs["bgm/kw_game01_fast"] = { from = "bgm/kw_game01", bpm = 144 }
songs["bgm/kw_game01_faster"] = { from = "bgm/kw_game01", bpm = 160 }

-- Head It: a hopping tune in G (FEVER plays it a tone up and quicker, on the same voice)
songs["bgm/kw_game02"] = { bpm = 144, loop = true, loopBar = 0, voices = {
  { wave = "pulse25", vol = 0.4, pan = -0.15, env = LEAD, vib = 0.1, notes = [[
    G5/8 G5 B5 D6 B5/4 G5 | E5/8 G5 B5 G5 E5/4 B4 | C5/8 E5 G5 C6 B5/4 A5 | D5/8 F#5 A5 F#5 D5/2 |
    B5/8 A5 G5 A5 B5/4 D6 | E6/8 D6 B5 G5 E5/4 G5 | A5/8 C6 E6 C6 A5/4 F#5 | G5/4 D5/8 F#5 A5/2 | ]] },
  { wave = "pulse12", vol = 0.15, pan = 0.35, env = ARP, notes = arp({ G, EM, C, D, G, EM, AM, D }) },
  { wave = "tri", vol = 0.5, env = BASS, gate = 0.75, notes = bounce({ "G", "E", "C", "D", "G", "E", "A", "D" }) },
  { wave = "drums", vol = 0.32, notes = rep("k/8 h s h k h s s |", 7) .. FILL },
} }

-- Tile Puzzle: an easy, thoughtful tune in D
songs["bgm/kw_game03"] = { bpm = 104, loop = true, loopBar = 0, voices = {
  { wave = "pulse50", vol = 0.32, pan = -0.1, env = SOFT, vib = 0.15, notes = [[
    F#5/4. E5/8 D5/4 A4 | B4/4 D5 F#5/2 | G5/4. F#5/8 E5/4 D5 | C#5/4 E5 A5/2 |
    A5/4. G5/8 F#5/4 D5 | B5/4 A5/8 F#5 D5/2 | E5/4 G5 B5 G5 | A5/2. r/4 | ]] },
  { wave = "pulse12", vol = 0.13, pan = 0.3, env = ARP, notes = arp({ D, BM, G, A, D, BM, EM, A }) },
  { wave = "tri", vol = 0.45, env = BASS, notes = [[
    D3/2 A2 | B2/2 F#2 | G2/2 D3 | A2/2 E2 | D3/2 A2 | B2/2 F#2 | E2/2 B2 | A2/2 A2 | ]] },
  { wave = "drums", vol = 0.22, notes = rep("k/8 h h h s h h h |", 8) },
} }

return songs
