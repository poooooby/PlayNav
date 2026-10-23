-- Super Training's and Pokemon-Amie's sound effects (its room, PLAY, DECORATE and minigames),
-- PlayNav's own: each made on the
-- chip synth (src/chipsynth.lua M.effect; the layer fields are described there), under the ids
-- data/training_sounds.lua and data/amie_sounds.lua map the events to. The ones the game loops
-- while something lasts (the charge, the wind-up, a ball in the air; the berry rain, a score
-- counting up) are four seconds of steady sound, stopped
-- when it ends, as the extracted ones were.

local function hz(name)
  local NOTE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
  local l, acc, oct = name:match("^([A-G])([#b]?)(%d)$")
  local midi = (tonumber(oct) + 1) * 12 + NOTE[l] + (acc == "#" and 1 or acc == "b" and -1 or 0)
  return 440 * 2 ^ ((midi - 69) / 12)
end
local function notes(list)
  local out = {}
  for i, n in ipairs(list) do out[i] = hz(n) end
  return out
end
local function alternate(a, b, count)
  local out = {}
  for i = 1, count do out[i] = (i % 2 == 1) and a or b end
  return out
end

local S = {}

-- a screen change: the shutters whoosh shut, clank, and whoosh open
S["se/sys_057"] = { peak = 0.7, layers = {
  { at = 0, dur = 0.35, wave = "noise", lp = 700, lp1 = 4000, vol = 0.5, attack = 0.2, release = 0.12 },
  { at = 0.33, dur = 0.12, wave = "noise", lp = 3000, decay = 30, vol = 0.8 },
  { at = 0.33, dur = 0.2, wave = "pulse50", f0 = 140, f1 = 90, decay = 18, vol = 0.45 },
  { at = 0.33, dur = 0.35, wave = "tri", f0 = 880, decay = 14, vol = 0.22 },
  { at = 0.95, dur = 0.35, wave = "noise", lp = 4000, lp1 = 900, vol = 0.4, attack = 0.05, release = 0.2 },
} }
-- picking a course; starting one
S["se/sp_decide"] = { peak = 0.6, layers = {
  { dur = 0.1, wave = "pulse25", steps = notes({ "C6", "G6" }), step = 0.045, decay = 8, vol = 0.5, release = 0.02 },
} }
S["se/sp_031"] = { peak = 0.65, layers = {
  { dur = 0.32, wave = "pulse25", steps = notes({ "C5", "E5", "G5", "C6" }), step = 0.05, vol = 0.45, release = 0.1 },
  { at = 0.05, dur = 0.3, wave = "tri", steps = notes({ "E5", "G5", "C6", "E6" }), step = 0.05, vol = 0.3, release = 0.1 },
} }
-- the balloon: a pump of air, its name sliding in
S["se/sp_036"] = { peak = 0.65, layers = {
  { dur = 0.22, wave = "noise", lp = 400, lp1 = 2500, vol = 0.7, attack = 0.03, release = 0.08 },
  { dur = 0.22, wave = "sine", f0 = 180, f1 = 260, vol = 0.25, decay = 4 },
} }
S["se/sp_033"] = { peak = 0.55, layers = {
  { dur = 0.3, wave = "noise", lp = 1500, lp1 = 6000, vol = 0.5, attack = 0.1, release = 0.15 },
  { dur = 0.3, wave = "sine", f0 = 400, f1 = 900, vol = 0.15, release = 0.1 },
} }
-- Start!: the whistle
S["se/sp_037"] = { peak = 0.6, layers = {
  { dur = 0.42, wave = "pulse50", f0 = 2000, vib = { 0.6, 14 }, vol = 0.45, attack = 0.01, release = 0.08 },
  { dur = 0.42, wave = "tri", f0 = 2000, vib = { 0.6, 14 }, vol = 0.25, attack = 0.01, release = 0.08 },
} }
-- a finger down; the charge's hum (steady, stopped when it ends)
S["se/sp_019"] = { peak = 0.4, layers = {
  { dur = 0.04, wave = "tri", f0 = 1400, decay = 60, vol = 0.5 },
} }
S["se/sp_024"] = { peak = 0.45, layers = {
  { dur = 4, wave = "saw", f0 = 110, vol = 0.35, attack = 0.08, trem = { 0.3, 9 } },
  { dur = 4, wave = "tri", f0 = 220, vol = 0.3, attack = 0.08, vib = { 0.15, 6 } },
} }
-- shots: a plain one, a charged one
S["se/sp_017"] = { peak = 0.55, layers = {
  { dur = 0.12, wave = "pulse25", f0 = 1400, f1 = 350, decay = 10, vol = 0.55 },
} }
S["se/sp_016"] = { peak = 0.7, layers = {
  { dur = 0.3, wave = "saw", f0 = 900, f1 = 120, decay = 6, vol = 0.5 },
  { dur = 0.2, wave = "noise", lp = 3000, lp1 = 800, decay = 12, vol = 0.4 },
} }
-- goals: hit, hit with a charged shot, a new group appearing
S["se/sp_021"] = { peak = 0.6, layers = {
  { dur = 0.3, wave = "tri", f0 = hz("G6"), decay = 12, vol = 0.5 },
  { at = 0.03, dur = 0.3, wave = "tri", f0 = hz("C7"), decay = 12, vol = 0.35 },
} }
S["se/sp_015"] = { peak = 0.75, layers = {
  { dur = 0.5, wave = "tri", f0 = hz("G6"), decay = 7, vol = 0.45 },
  { dur = 0.5, wave = "tri", f0 = hz("C7"), decay = 7, vol = 0.35 },
  { dur = 0.5, wave = "tri", f0 = hz("E7"), decay = 7, vol = 0.3 },
  { dur = 0.08, wave = "noise", lp = 6000, decay = 40, vol = 0.5 },
} }
S["se/sp_032"] = { peak = 0.5, layers = {
  { dur = 0.22, wave = "tri", steps = notes({ "E6", "G6", "B6", "E7" }), step = 0.045, decay = 6, vol = 0.4, release = 0.05 },
} }
-- the balloon's attack: the wind-up alarm (steady), the throw
S["se/sp_034"] = { peak = 0.45, layers = {
  { dur = 4, wave = "pulse50", steps = alternate(660, 880, 34), step = 0.12, vol = 0.35 },
} }
S["se/sp_035"] = { peak = 0.7, layers = {
  { dur = 0.25, wave = "sine", f0 = 220, f1 = 60, decay = 8, vol = 0.7 },
  { dur = 0.15, wave = "noise", lp = 2000, lp1 = 500, decay = 15, vol = 0.4 },
} }
-- a ball on its way (steady)
S["se/sp_041"] = { peak = 0.4, layers = {
  { dur = 4, wave = "noise", lp = 1200, vol = 0.5, attack = 0.05, trem = { 0.5, 7 } },
  { dur = 4, wave = "sine", f0 = 300, vol = 0.12, attack = 0.05, trem = { 0.5, 7 } },
} }
-- the balloon beaten: the pop, the long leak, the burst as it zips off, the twinkle
S["se/sp_044"] = { peak = 0.85, layers = {
  { dur = 0.6, wave = "noise", lp = 5000, lp1 = 400, decay = 6, vol = 0.8 },
  { dur = 0.4, wave = "sine", f0 = 120, f1 = 40, decay = 8, vol = 0.6 },
} }
S["se/sp_049"] = { peak = 0.5, layers = {
  { dur = 3.5, wave = "noise", lp = 3000, lp1 = 1500, vol = 0.45, attack = 0.1, release = 1.0, trem = { 0.15, 5 } },
} }
S["se/sp_005"] = { peak = 0.7, layers = {
  { dur = 0.35, wave = "noise", lp = 2500, lp1 = 600, decay = 9, vol = 0.7 },
  { dur = 0.3, wave = "sine", f0 = 300, f1 = 150, decay = 10, vol = 0.3 },
} }
S["se/sp_007"] = { peak = 0.5, layers = {
  { dur = 0.5, wave = "tri", steps = notes({ "E7", "G7", "B7", "E8" }), step = 0.06, decay = 5, vol = 0.35 },
  { at = 0.25, dur = 0.4, wave = "sine", f0 = hz("E8"), decay = 8, vol = 0.2, vib = { 0.3, 12 } },
} }
-- the results: a tap to the next line, and the jingle for an Award or a bag received
S["se/message"] = { peak = 0.35, layers = {
  { dur = 0.035, wave = "pulse25", f0 = 1200, decay = 50, vol = 0.4 },
} }
S["se/sp_046"] = { peak = 0.65, layers = {
  { dur = 0.95, wave = "pulse25", steps = notes({ "C5", "E5", "G5", "C6" }), step = 0.1, vol = 0.4, release = 0.35, vib = { 0.1, 6 } },
  { dur = 0.95, wave = "tri", steps = notes({ "G4", "C5", "E5", "G5" }), step = 0.1, vol = 0.3, release = 0.35 },
} }

-- ------- Pokemon-Amie's minigames and their picker (data/amie_sounds.lua maps the events here)

local function blip(f, dur, vol) return { dur = dur or 0.05, wave = "pulse25", f0 = f, decay = 30, vol = vol or 0.5 } end
local function chime(f, at, dur, vol) return { at = at or 0, dur = dur or 0.35, wave = "tri", f0 = f, decay = 9, vol = vol or 0.45 } end

-- buttons and choices
S["se/kw_select"] = { peak = 0.45, layers = { blip(hz("A6"), 0.04) } }
S["se/kw_select2"] = { peak = 0.45, layers = { blip(hz("E6"), 0.04), { at = 0.06, dur = 0.04, wave = "pulse25", f0 = hz("A6"), decay = 30, vol = 0.45 } } }
S["se/kw_decide"] = { peak = 0.55, layers = {
  { dur = 0.12, wave = "pulse25", steps = notes({ "E6", "B6" }), step = 0.05, decay = 8, vol = 0.5, release = 0.02 } } }
S["se/kw_selgame"] = S["se/kw_decide"]
S["se/kw_decide2"] = { peak = 0.6, layers = {
  { dur = 0.26, wave = "pulse25", steps = notes({ "C6", "E6", "G6", "C7" }), step = 0.05, decay = 5, vol = 0.45, release = 0.05 },
  chime(hz("C7"), 0.15, 0.3, 0.3) } }
S["se/kw_cancel"] = { peak = 0.5, layers = {
  { dur = 0.12, wave = "pulse25", steps = notes({ "B5", "E5" }), step = 0.05, decay = 10, vol = 0.45, release = 0.02 } } }
S["se/kw_selplay"] = { peak = 0.6, layers = {
  { dur = 0.32, wave = "tri", steps = notes({ "G5", "C6", "E6", "G6", "C7" }), step = 0.04, vol = 0.45, release = 0.12 },
  { dur = 0.3, wave = "noise", lp = 6000, vol = 0.12, attack = 0.02, release = 0.2 } } }
S["se/kw_onceagain"] = { peak = 0.55, layers = {
  { dur = 0.22, wave = "pulse25", steps = notes({ "G5", "D6", "G6" }), step = 0.06, decay = 5, vol = 0.45, release = 0.05 } } }

-- the start and the end of a round
S["se/kw_countdown1"] = { peak = 0.5, layers = { { dur = 0.14, wave = "pulse50", f0 = hz("A5"), vol = 0.45, release = 0.04 } } }
S["se/kw_start"] = { peak = 0.65, layers = {
  { dur = 0.45, wave = "pulse50", f0 = hz("A6"), vol = 0.4, attack = 0.01, release = 0.15 },
  { dur = 0.45, wave = "pulse25", f0 = hz("E6"), vol = 0.3, attack = 0.01, release = 0.15 },
  { dur = 0.45, wave = "tri", f0 = hz("A5"), vol = 0.35, release = 0.15 } } }
S["se/kw_start3"] = { peak = 0.65, layers = {
  { dur = 0.5, wave = "pulse25", steps = notes({ "D6", "F#6", "A6", "D7" }), step = 0.07, vol = 0.42, release = 0.18 },
  { dur = 0.5, wave = "tri", steps = notes({ "A5", "D6", "F#6", "A6" }), step = 0.07, vol = 0.3, release = 0.18 } } }
S["se/kw_timeover"] = { peak = 0.6, layers = {
  { dur = 0.6, wave = "pulse50", steps = notes({ "E5", "C5", "A4" }), step = 0.18, vol = 0.4, release = 0.15 },
  { dur = 0.6, wave = "saw", f0 = 220, f1 = 150, vol = 0.15, release = 0.2 } } }
S["se/kw_end"] = { peak = 0.65, layers = {
  { dur = 1.0, wave = "tri", f0 = hz("C5"), decay = 3, vol = 0.5, vib = { 0.08, 5 } },
  { dur = 1.0, wave = "sine", f0 = hz("G5"), decay = 4, vol = 0.3 },
  { dur = 0.06, wave = "noise", lp = 4000, decay = 40, vol = 0.3 } } }
S["se/kw_stamp"] = { peak = 0.75, layers = {
  { dur = 0.18, wave = "sine", f0 = 160, f1 = 60, decay = 14, vol = 0.8 },
  { dur = 0.1, wave = "noise", lp = 2500, decay = 30, vol = 0.6 } } }
S["se/kw_sweet"] = { peak = 0.6, layers = {
  { dur = 0.7, wave = "tri", steps = notes({ "C6", "E6", "G6", "C7", "E7", "G7" }), step = 0.06, vol = 0.4, release = 0.3 },
  { at = 0.3, dur = 0.5, wave = "sine", f0 = hz("C8"), decay = 6, vol = 0.15, vib = { 0.3, 12 } } } }
S["se/kw_star"] = { peak = 0.6, layers = {
  { dur = 0.6, wave = "tri", steps = notes({ "E6", "G#6", "B6", "E7" }), step = 0.07, vol = 0.4, release = 0.25 },
  { at = 0.25, dur = 0.45, wave = "sine", f0 = hz("E8"), decay = 7, vol = 0.18, vib = { 0.3, 12 } } } }
S["se/kw_draw"] = { peak = 0.55, layers = {
  { dur = 0.4, wave = "noise", lp = 3000, lp1 = 9000, vol = 0.35, attack = 0.05, release = 0.2 },
  { dur = 0.4, wave = "sine", f0 = 800, f1 = 2400, vol = 0.25, release = 0.15 } } }

-- Berry Picker
S["se/kw_pick"] = { peak = 0.55, layers = { { dur = 0.08, wave = "sine", f0 = 900, f1 = 1500, decay = 25, vol = 0.6 } } }
S["se/kw_give"] = { peak = 0.55, layers = { chime(hz("E6"), 0, 0.25, 0.45), chime(hz("A6"), 0.06, 0.3, 0.4) } }
S["se/kw_givefast"] = { peak = 0.6, layers = { chime(hz("E6"), 0, 0.2), chime(hz("A6"), 0.05, 0.2), chime(hz("C#7"), 0.1, 0.3) } }
S["se/kw_enter"] = { peak = 0.5, layers = { { dur = 0.22, wave = "sine", f0 = 300, f1 = 900, vol = 0.45, release = 0.08 } } }
S["se/kw_enter2"] = { peak = 0.5, layers = { { dur = 0.22, wave = "sine", f0 = 400, f1 = 1200, vol = 0.45, release = 0.08 } } }
S["se/kw_leave2"] = { peak = 0.5, layers = { { dur = 0.25, wave = "sine", f0 = 900, f1 = 250, vol = 0.45, release = 0.1 } } }
S["se/kw_fail"] = { peak = 0.55, layers = {
  { dur = 0.3, wave = "pulse50", steps = { 196, 165 }, step = 0.12, vol = 0.4, release = 0.08 },
  { dur = 0.3, wave = "saw", f0 = 98, vol = 0.18, release = 0.1 } } }
S["se/kw_fallsweet"] = { peak = 0.5, layers = { { dur = 0.35, wave = "tri", f0 = 1400, f1 = 300, vol = 0.4, release = 0.1 } } }
-- the berries raining down (steady, stopped when the rain ends)
local patter = {}
for i = 0, 31 do
  patter[#patter + 1] = { at = i * 0.12 + (i % 3) * 0.02, dur = 0.07, wave = "sine", f0 = 600 + (i * 137) % 700, f1 = 300, decay = 30, vol = 0.35 }
end
S["se/kw_falling"] = { peak = 0.45, layers = patter }
S["se/kw_landheavy"] = { peak = 0.75, layers = {
  { dur = 0.35, wave = "sine", f0 = 110, f1 = 45, decay = 9, vol = 0.8 },
  { dur = 0.2, wave = "noise", lp = 1200, decay = 15, vol = 0.5 } } }

-- Head It: a heading, good or just (a bright chime on top), in FEVER a little higher; the
-- giant's heavier; a miss
local function bonk(f, ring, vol)
  local l = { { dur = 0.12, wave = "sine", f0 = f, f1 = f * 0.6, decay = 20, vol = vol or 0.6 },
    { dur = 0.05, wave = "noise", lp = 2500, decay = 50, vol = 0.35 } }
  if ring then l[#l + 1] = chime(ring, 0.03, 0.3, 0.35) end
  return l
end
S["se/kw_headok"] = { peak = 0.6, layers = bonk(420) }
S["se/kw_headgood"] = { peak = 0.65, layers = bonk(480, hz("E7")) }
S["se/kw_fheadok"] = { peak = 0.6, layers = bonk(520) }
S["se/kw_fheadgood"] = { peak = 0.65, layers = bonk(600, hz("G7")) }
S["se/kw_lheadok"] = { peak = 0.7, layers = bonk(220) }
S["se/kw_lheadgood"] = { peak = 0.75, layers = bonk(260, hz("C7")) }
S["se/kw_headfail"] = { peak = 0.6, layers = {
  { dur = 0.25, wave = "sine", f0 = 160, f1 = 80, decay = 10, vol = 0.6 },
  { dur = 0.25, wave = "pulse50", f0 = 130, f1 = 90, decay = 10, vol = 0.2 } } }
S["se/kw_lheadfail"] = { peak = 0.7, layers = {
  { dur = 0.4, wave = "sine", f0 = 110, f1 = 50, decay = 7, vol = 0.7 },
  { dur = 0.4, wave = "pulse50", f0 = 90, f1 = 60, decay = 7, vol = 0.25 } } }
S["se/kw_lballfall"] = { peak = 0.6, layers = { { dur = 0.8, wave = "tri", f0 = 1800, f1 = 300, vol = 0.45, release = 0.15 } } }
S["se/kw_alert"] = { peak = 0.55, layers = {
  { dur = 0.4, wave = "pulse50", steps = { 988, 740, 988, 740 }, step = 0.1, vol = 0.4, release = 0.05 } } }
S["se/kw_combo"] = { peak = 0.55, layers = { chime(hz("C6"), 0, 0.2), chime(hz("E6"), 0.05, 0.2), chime(hz("G6"), 0.1, 0.3) } }
S["se/kw_combo2"] = { peak = 0.6, layers = { chime(hz("D6"), 0, 0.2), chime(hz("F#6"), 0.05, 0.2), chime(hz("A6"), 0.1, 0.2), chime(hz("D7"), 0.15, 0.35) } }
S["se/kw_combo3"] = { peak = 0.6, layers = { chime(hz("E6"), 0, 0.2), chime(hz("G#6"), 0.05, 0.2), chime(hz("B6"), 0.1, 0.2), chime(hz("E7"), 0.15, 0.4) } }
S["se/kw_combo4"] = { peak = 0.65, layers = { chime(hz("G6"), 0, 0.2), chime(hz("B6"), 0.05, 0.2), chime(hz("D7"), 0.1, 0.2), chime(hz("G7"), 0.15, 0.5),
  { at = 0.2, dur = 0.4, wave = "noise", lp = 8000, vol = 0.1, release = 0.3 } } }

-- the RESULTS card: it comes in, a bonus row counts up (steady ticking, stopped), settles; the stars
S["se/kw_number"] = { peak = 0.5, layers = {
  { dur = 0.25, wave = "noise", lp = 1500, lp1 = 5000, vol = 0.4, attack = 0.05, release = 0.1 },
  chime(hz("G6"), 0.15, 0.2, 0.3) } }
local ticks = {}
for i = 0, 79 do ticks[#ticks + 1] = { at = i * 0.05, dur = 0.02, wave = "pulse25", f0 = 1600, decay = 60, vol = 0.35 } end
S["se/kw_addscore"] = { peak = 0.4, layers = ticks }
S["se/kw_score"] = { peak = 0.55, layers = { chime(hz("C7"), 0, 0.35, 0.5), chime(hz("G7"), 0.03, 0.3, 0.25) } }
S["se/kw_value1"] = { peak = 0.55, layers = { chime(hz("E6"), 0, 0.4) } }
S["se/kw_value2"] = { peak = 0.55, layers = { chime(hz("E6"), 0, 0.3), chime(hz("B6"), 0.1, 0.4) } }
S["se/kw_value3"] = { peak = 0.6, layers = { chime(hz("E6"), 0, 0.3), chime(hz("B6"), 0.1, 0.3), chime(hz("E7"), 0.2, 0.5),
  { at = 0.25, dur = 0.4, wave = "sine", f0 = hz("E8"), decay = 7, vol = 0.15, vib = { 0.3, 12 } } } }

-- Tile Puzzle: a tile lifts, two swap, one settles home
S["se/kw_float"] = { peak = 0.5, layers = { { dur = 0.18, wave = "sine", f0 = 500, f1 = 1000, vol = 0.45, release = 0.06 } } }
S["se/kw_swap"] = { peak = 0.55, layers = {
  { dur = 0.2, wave = "noise", lp = 2000, lp1 = 5000, vol = 0.35, attack = 0.03, release = 0.08 },
  { dur = 0.2, wave = "sine", f0 = 700, f1 = 500, vol = 0.3, release = 0.06 } } }
S["se/kw_setpanel"] = { peak = 0.55, layers = {
  { dur = 0.08, wave = "pulse25", f0 = 700, f1 = 400, decay = 30, vol = 0.5 },
  { dur = 0.04, wave = "noise", lp = 3500, decay = 60, vol = 0.35 } } }

-- ------- Pokemon-Amie's room, PLAY and DECORATE (each shaped as the game's: its length, its
-- pitch rising or falling, noise or tone)

-- the room's menu and DECORATE's pills: a low knock, a bright tick over it
S["se/decide1"] = { peak = 0.55, layers = {
  { dur = 0.08, wave = "sine", f0 = 600, f1 = 180, decay = 25, vol = 0.6 },
  { at = 0.03, dur = 0.12, wave = "pulse25", f0 = hz("A6"), decay = 28, vol = 0.35 } } }
-- DECORATE: an item taken into the finger (a quick rising pip), and let go (a pip up, then down)
S["se/catch"] = { peak = 0.5, layers = { { dur = 0.09, wave = "sine", f0 = 650, f1 = 1250, vol = 0.5, release = 0.03 } } }
S["se/release"] = { peak = 0.5, layers = {
  { dur = 0.05, wave = "sine", f0 = 800, f1 = 950, vol = 0.5 },
  { at = 0.05, dur = 0.07, wave = "sine", f0 = 950, f1 = 560, vol = 0.45, release = 0.03 } } }

-- PLAY: a finger lands on the Pokemon (a soft pat), a stroke (a soft brush and a lifting tone)
S["se/kw_touch"] = { peak = 0.45, layers = { { dur = 0.04, wave = "sine", f0 = 580, decay = 50, vol = 0.5 } } }
S["se/kw_stroke"] = { peak = 0.5, layers = {
  { dur = 0.08, wave = "sine", f0 = 220, f1 = 260, vol = 0.5, attack = 0.03, release = 0.03 },
  { at = 0.08, dur = 0.1, wave = "tri", f0 = 850, f1 = 1300, vol = 0.25, release = 0.05 } } }
-- happy: a skipping run upward (a step of its dance, its reward's hop); the longer one runs
-- up, then lands with a sparkle
S["se/kw_heart1"] = { peak = 0.55, layers = {
  { dur = 0.32, wave = "pulse25", steps = { 250, 350, 775, 1050, 1300, 1825 }, step = 0.045, vol = 0.45, release = 0.08 },
  { at = 0.2, dur = 0.17, wave = "tri", f0 = 1150, f1 = 2050, vol = 0.2, release = 0.1 } } }
S["se/kw_heart2"] = { peak = 0.6, layers = {
  { dur = 0.2, wave = "pulse25", steps = { 250, 350, 775, 1050 }, step = 0.05, vol = 0.5, release = 0.04 },
  { at = 0.18, dur = 0.24, wave = "tri", steps = { 350, 575, 375, 250 }, step = 0.06, vol = 0.4, release = 0.06 },
  { at = 0.4, dur = 0.4, wave = "noise", lp = 4000, lp1 = 9000, vol = 0.1, release = 0.3 },
  { at = 0.42, dur = 0.35, wave = "sine", f0 = 1000, decay = 8, vol = 0.15, vib = { 0.4, 14 } } } }
-- disliked: a buzzing shock; a hurt yelp down; burning: a long crackling hiss
S["se/kw_elshock"] = { peak = 0.6, layers = {
  { dur = 0.38, wave = "saw", f0 = 125, vol = 0.45, trem = { 0.6, 28 }, release = 0.12 },
  { dur = 0.38, wave = "noise", lp = 6000, vol = 0.25, trem = { 0.8, 17 }, release = 0.12 } } }
S["se/kw_injure"] = { peak = 0.6, layers = {
  { dur = 0.17, wave = "pulse25", f0 = 380, f1 = 220, vol = 0.5, release = 0.05 },
  { at = 0.03, dur = 0.12, wave = "noise", lp = 1500, decay = 18, vol = 0.3 } } }
S["se/kw_burn"] = { peak = 0.5, layers = {
  { dur = 0.68, wave = "noise", lp = 6000, lp1 = 9000, vol = 0.4, trem = { 0.5, 23 }, attack = 0.02, release = 0.2 } } }
-- tapped too hard: a slap; the high five: a bright clap with a ringing tail
S["se/kw_smack"] = { peak = 0.6, layers = {
  { dur = 0.05, wave = "sine", f0 = 160, f1 = 90, decay = 40, vol = 0.6 },
  { dur = 0.15, wave = "noise", lp = 7000, lp1 = 3000, decay = 25, vol = 0.5 } } }
S["se/kw_snap"] = { peak = 0.65, layers = {
  { dur = 0.08, wave = "noise", lp = 3000, decay = 40, vol = 0.7 },
  { at = 0.2, dur = 0.08, wave = "noise", lp = 6500, decay = 35, vol = 0.35 },
  { dur = 0.4, wave = "tri", f0 = 1575, f1 = 1100, decay = 7, vol = 0.25 } } }
-- the Poke Puff drawer opening (a rising swish into a held note) and closing (a short swish down)
S["se/kw_selsweet"] = { peak = 0.55, layers = {
  { dur = 0.16, wave = "noise", lp = 900, lp1 = 2500, vol = 0.35, attack = 0.05, release = 0.04 },
  { at = 0.04, dur = 0.37, wave = "tri", steps = { 450, 525, 600, 775 }, step = 0.06, vol = 0.45, release = 0.2 } } }
S["se/kw_closesweet"] = { peak = 0.5, layers = {
  { dur = 0.1, wave = "noise", lp = 2500, lp1 = 900, vol = 0.35, release = 0.03 },
  { at = 0.06, dur = 0.24, wave = "tri", f0 = 600, f1 = 450, vol = 0.45, release = 0.12 } } }
-- eating: a bite (a soft munch), the last one swallowed (a gulp rising)
S["se/kw_eat"] = { peak = 0.55, layers = {
  { dur = 0.1, wave = "pulse50", f0 = 500, f1 = 580, vol = 0.4, decay = 18 },
  { dur = 0.06, wave = "noise", lp = 1800, decay = 40, vol = 0.3 } } }
S["se/kw_eatswallow"] = { peak = 0.55, layers = {
  { dur = 0.1, wave = "sine", f0 = 320, vol = 0.55, release = 0.02 },
  { at = 0.1, dur = 0.14, wave = "sine", f0 = 330, f1 = 900, vol = 0.5, release = 0.06 } } }
-- it will not eat: a low double buzz
S["se/kw_fault"] = { peak = 0.6, layers = {
  { dur = 0.1, wave = "pulse50", f0 = 125, vol = 0.5, release = 0.02 },
  { at = 0.11, dur = 0.12, wave = "pulse50", f0 = 125, f1 = 150, vol = 0.35, release = 0.06 } } }
-- turning round to face you, and a visitor's chat: little blips
S["se/kw_face1"] = { peak = 0.45, layers = { { dur = 0.07, wave = "pulse25", f0 = 425, decay = 25, vol = 0.45 } } }
S["se/kw_face2"] = { peak = 0.5, layers = {
  { dur = 0.05, wave = "pulse25", f0 = 1200, decay = 30, vol = 0.3 },
  { at = 0.04, dur = 0.06, wave = "pulse25", f0 = 250, decay = 25, vol = 0.5 },
  { at = 0.08, dur = 0.05, wave = "pulse25", f0 = 2075, decay = 35, vol = 0.25 } } }
-- the "..." bubble: three notes wandering up
S["se/kw_think"] = { peak = 0.5, layers = {
  { dur = 0.24, wave = "tri", steps = { 325, 400, 550, 475 }, step = 0.05, vol = 0.5, release = 0.08 } } }
-- dozing off: a soft high whistle falling
S["se/kw_sleep"] = { peak = 0.35, layers = {
  { dur = 0.55, wave = "sine", f0 = 3200, f1 = 1300, vol = 0.35, attack = 0.25, release = 0.2, vib = { 0.4, 6 } } } }
-- a gift: a fanfare of fifths, a chime held over it
S["se/kw_bonus"] = { peak = 0.6, layers = {
  { dur = 0.24, wave = "pulse25", steps = { hz("C5"), hz("G5") }, step = 0.08, vol = 0.45, release = 0.03 },
  { at = 0.16, dur = 0.08, wave = "pulse25", f0 = hz("C5"), vol = 0.4 },
  chime(hz("C6"), 0.24, 0.45, 0.45),
  { at = 0.22, dur = 0.2, wave = "noise", lp = 6000, vol = 0.08, release = 0.15 } } }

return S
