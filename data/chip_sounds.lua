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

-- a screen change: the shutters slam - a broad crash of noise at once, a low thud under it,
-- darkening as it dies away over half a second
S["se/sys_057"] = { peak = 0.8, layers = {
  { dur = 1.15, wave = "noise", poles = 2, lp = 3600, lp1 = 500, attack = 0.04, decay = 2.5, vol = 0.8 },
  { at = 0.18, dur = 0.5, wave = "noise", poles = 2, lp = 2000, lp1 = 600, attack = 0.03, decay = 7, vol = 0.35 },
  { dur = 1.15, wave = "noise", poles = 2, lp = 200, attack = 0.04, decay = 2.5, vol = 0.6 },
  { dur = 0.35, wave = "sine", f0 = 85, f1 = 45, attack = 0.005, decay = 7, vol = 0.5 },
} }
-- picking a course: a double tap of noise, then a low rising tone as it settles; starting
-- one: a bright arpeggio rippling up three times as it fades
S["se/sp_decide"] = { peak = 0.6, layers = {
  { dur = 0.05, wave = "noise", poles = 2, lp = 2800, decay = 30, vol = 0.7 },
  { at = 0.055, dur = 0.06, wave = "noise", poles = 2, lp = 2400, decay = 28, vol = 0.6 },
  { dur = 0.38, wave = "pulse50", f0 = 230, f1 = 310, attack = 0.03, decay = 6, vol = 0.35 },
} }
local RIPPLE_LO = { 587, 880, 1319, 1976, 1109, 1109 }
local RIPPLE_HI = { 740, 1109, 1661, 2637, 1661, 1976 }
local function ripple(list)
  local out = {}
  for _ = 1, 3 do for _, f in ipairs(list) do out[#out + 1] = f end end
  return out
end
S["se/sp_031"] = { peak = 0.6, layers = {
  { dur = 0.81, wave = "pulse25", steps = ripple(RIPPLE_LO), step = 0.05, attack = 0.005, decay = 3.5, vol = 0.4 },
  { dur = 0.81, wave = "tri", steps = ripple(RIPPLE_HI), step = 0.05, attack = 0.005, decay = 3.5, vol = 0.35 },
} }
-- the balloon: a pump of air (a held rush with a low tone in it); its name: a swell of air
-- fading slowly
S["se/sp_036"] = { peak = 0.65, layers = {
  { dur = 0.37, wave = "noise", poles = 2, lp = 1400, attack = 0.03, release = 0.12, vol = 0.6 },
  { dur = 0.37, wave = "sine", f0 = 140, attack = 0.03, release = 0.12, vol = 0.35 },
} }
S["se/sp_033"] = { peak = 0.55, layers = {
  { dur = 0.87, wave = "noise", poles = 2, lp = 1000, lp1 = 2400, attack = 0.1, decay = 4, vol = 0.6 },
  { dur = 0.87, wave = "noise", poles = 2, lp = 150, attack = 0.08, decay = 3, vol = 0.3 },
} }
-- Start!: a short, high trilled whistle, cut off
S["se/sp_037"] = { peak = 0.6, layers = {
  { dur = 0.17, wave = "sine", f0 = 3400, vib = { 0.9, 28 }, attack = 0.01, release = 0.01, vol = 0.7 },
  { dur = 0.17, wave = "noise", poles = 2, lp = 150, attack = 0.01, release = 0.01, vol = 0.12 },
} }
-- a finger down: a soft tap of noise; the charge: a crackling, flickering rush (steady,
-- stopped when it ends)
S["se/sp_019"] = { peak = 0.45, layers = {
  { dur = 0.2, wave = "noise", poles = 2, lp = 1000, decay = 14, vol = 0.6 },
  { dur = 0.12, wave = "sine", f0 = 200, f1 = 110, decay = 18, vol = 0.4 },
} }
S["se/sp_024"] = { peak = 0.45, layers = {
  { dur = 4, wave = "noise", poles = 2, lp = 1200, attack = 0.05, trem = { 0.8, 14 }, vol = 0.6 },
  { dur = 4, wave = "noise", poles = 2, lp = 150, attack = 0.05, trem = { 0.5, 9 }, vol = 0.4 },
  { dur = 4, wave = "tri", f0 = 133, attack = 0.05, trem = { 0.6, 14 }, vol = 0.2 },
} }
-- shots: a plain one, a whoosh of air in two puffs; a charged one, a long fizzing rush
S["se/sp_017"] = { peak = 0.55, layers = {
  { dur = 0.14, wave = "noise", poles = 2, lp = 900, attack = 0.04, release = 0.05, vol = 0.6 },
  { at = 0.11, dur = 0.21, wave = "noise", poles = 2, lp = 600, attack = 0.02, decay = 9, vol = 0.5 },
  { dur = 0.3, wave = "sine", f0 = 100, f1 = 66, decay = 7, vol = 0.35 },
} }
S["se/sp_016"] = { peak = 0.7, layers = {
  { dur = 1.1, wave = "noise", poles = 2, lp = 2000, lp1 = 1000, attack = 0.04, decay = 0.6, release = 0.5, trem = { 0.7, 9 }, vol = 0.6 },
  { dur = 1.1, wave = "noise", poles = 2, lp = 200, attack = 0.04, decay = 0.6, release = 0.5, vol = 0.45 },
} }
-- goals: hit (a burst of air and a tone bending up), hit charged (a fluttering burst), a new
-- group (a quick puff fading long)
S["se/sp_021"] = { peak = 0.6, layers = {
  { dur = 0.44, wave = "noise", poles = 2, lp = 1600, attack = 0.02, decay = 6, vol = 0.55 },
  { dur = 0.4, wave = "sine", f0 = 250, f1 = 470, attack = 0.03, decay = 4, vol = 0.45 },
} }
S["se/sp_015"] = { peak = 0.75, layers = {
  { dur = 0.48, wave = "noise", poles = 2, lp = 1050, attack = 0.02, decay = 5, trem = { 0.5, 7 }, vol = 0.65 },
  { dur = 0.48, wave = "noise", poles = 2, lp = 150, attack = 0.02, decay = 4, vol = 0.4 },
} }
S["se/sp_032"] = { peak = 0.5, layers = {
  { dur = 0.81, wave = "noise", poles = 2, lp = 2800, lp1 = 800, attack = 0.02, decay = 6, vol = 0.7 },
  { dur = 0.4, wave = "sine", f0 = 120, f1 = 70, attack = 0.01, decay = 9, vol = 0.4 },
} }
-- the balloon's attack: the wind-up, a rush pulsing five times a second (steady), and the
-- throw, a short falling rush
-- a steady rush with sharp pulses on it, every `every` seconds over four seconds
local function pulses(every, bed, spike, tone)
  local layers = {
    { dur = 4, wave = "noise", poles = 2, lp = bed, attack = 0.05, vol = 0.3 },
    { dur = 4, wave = "tri", f0 = tone, attack = 0.05, vol = 0.12 },
  }
  for t = 0.02, 3.9, every do
    layers[#layers + 1] = { at = t, dur = 0.09, wave = "noise", poles = 2, lp = spike, attack = 0.004, decay = 35, vol = 0.8 }
  end
  return layers
end
S["se/sp_034"] = { peak = 0.45, layers = pulses(0.27, 1000, 2000, 133) }
S["se/sp_035"] = { peak = 0.7, layers = {
  { dur = 0.16, wave = "noise", poles = 2, lp = 1200, lp1 = 500, attack = 0.005, decay = 10, vol = 0.7 },
  { dur = 0.16, wave = "sine", f0 = 160, f1 = 90, decay = 12, vol = 0.35 },
} }
-- a ball on its way: a rush thrumming six times a second (steady)
S["se/sp_041"] = { peak = 0.4, layers = pulses(0.22, 800, 2400, 300) }
-- the balloon beaten: the pop (a burst, then a long ringing, wobbling tail), the long leak
-- (a hiss with a wobbling low tone dying away), the burst as it zips off (a crack and a long
-- shimmering tail), the twinkle (a bright bell flickering out)
S["se/sp_044"] = { peak = 0.85, layers = {
  { dur = 1.75, wave = "noise", poles = 2, lp = 3200, lp1 = 600, attack = 0.005, decay = 4, vol = 0.8 },
  { dur = 1.6, wave = "tri", f0 = 700, vib = { 3, 7 }, attack = 0.02, decay = 2.6, vol = 0.3 },
  { dur = 0.3, wave = "sine", f0 = 110, f1 = 50, decay = 10, vol = 0.5 },
} }
S["se/sp_049"] = { peak = 0.5, layers = {
  { dur = 1.6, wave = "noise", poles = 2, lp = 2000, lp1 = 600, attack = 0.01, decay = 2.4, vol = 0.6 },
  { dur = 1.6, wave = "saw", f0 = 120, f1 = 80, vib = { 3, 7 }, attack = 0.01, decay = 2.2, vol = 0.25 },
} }
S["se/sp_005"] = { peak = 0.7, layers = {
  { dur = 2.3, wave = "noise", poles = 2, lp = 3600, lp1 = 600, attack = 0.004, decay = 2.2, trem = { 0.25, 11 }, vol = 0.8 },
  { dur = 0.4, wave = "sine", f0 = 90, f1 = 40, decay = 8, vol = 0.6 },
} }
S["se/sp_007"] = { peak = 0.5, layers = {
  { dur = 0.84, wave = "sine", f0 = 3950, attack = 0.005, decay = 3, trem = { 0.5, 7 }, vol = 0.5 },
  { dur = 0.84, wave = "sine", f0 = 5260, attack = 0.005, decay = 3.4, trem = { 0.5, 7 }, vol = 0.35 },
  { dur = 0.84, wave = "sine", f0 = 7900, attack = 0.005, decay = 4, trem = { 0.5, 7 }, vol = 0.2 },
} }
-- the results: a tap to the next line (a two-note ting), and the jingle for an Award or a bag
-- received (five soft chord swells in C#, the last smaller)
S["se/message"] = { peak = 0.35, layers = {
  { dur = 0.16, wave = "sine", steps = { 2060, 2820 }, step = 0.05, attack = 0.01, decay = 10, vol = 0.6 },
  { dur = 0.16, wave = "sine", f0 = 8360, attack = 0.01, decay = 16, vol = 0.1 },
} }
local STABS = { { 554, 1109 }, { 831, 1397 }, { 988, 1976 }, { 1109, 2217 }, { 831, 1661 } }
local jingle = {}
for i, st in ipairs(STABS) do
  local last = i == #STABS
  local at, k = last and 0.5 or (i - 1) * 0.11, last and 0.5 or 1
  jingle[#jingle + 1] = { at = at, dur = 0.14, wave = "pulse25", f0 = st[1], attack = 0.05, release = 0.08, vol = 0.4 * k }
  jingle[#jingle + 1] = { at = at, dur = 0.14, wave = "tri", f0 = st[2], attack = 0.05, release = 0.08, vol = 0.35 * k }
end
S["se/sp_046"] = { peak = 0.65, layers = jingle }

-- a regimen's exit armed: a tone sweeping up, then warbling as it fades
S["se/sp_020"] = { peak = 0.5, layers = {
  { dur = 0.2, wave = "tri", f0 = 170, f1 = 620, attack = 0.08, vol = 0.5 },
  { at = 0.2, dur = 0.26, wave = "pulse25", steps = { 500, 420, 500, 420, 500 }, step = 0.05, decay = 7, vol = 0.4 },
  { at = 0.2, dur = 0.26, wave = "tri", steps = { 1000, 860, 1000, 860, 1000 }, step = 0.05, decay = 8, vol = 0.25 },
} }
-- the bag drawer closed (the system's cancel): two quick notes stepping down
S["se/cancel1"] = { peak = 0.5, layers = {
  { dur = 0.15, wave = "pulse25", steps = { 680, 330 }, step = 0.055, attack = 0.005, release = 0.03, vol = 0.45 },
  { dur = 0.15, wave = "tri", steps = { 1280, 520 }, step = 0.055, attack = 0.005, release = 0.03, vol = 0.25 },
} }

-- ------- Pokemon-Amie's minigames and their picker (data/amie_sounds.lua maps the events here)

local function blip(f, dur, vol) return { dur = dur or 0.05, wave = "pulse25", f0 = f, decay = 30, vol = vol or 0.5 } end
local function chime(f, at, dur, vol) return { at = at or 0, dur = dur or 0.35, wave = "tri", f0 = f, decay = 9, vol = vol or 0.45 } end

-- a tap on a button or an item: a click, a faint high ring after it
S["se/kw_select"] = { peak = 0.45, layers = {
  { dur = 0.03, wave = "noise", poles = 2, lp = 4000, decay = 60, vol = 0.8 },
  { dur = 0.15, wave = "sine", f0 = 2800, decay = 15, vol = 0.2 },
  { dur = 0.15, wave = "sine", f0 = 3500, decay = 18, vol = 0.15 },
} }
-- a page, a wallpaper, a game turned: a click with a mid ring
S["se/kw_select2"] = { peak = 0.45, layers = {
  { dur = 0.025, wave = "noise", poles = 2, lp = 3500, decay = 70, vol = 0.8 },
  { dur = 0.09, wave = "sine", f0 = 1500, decay = 25, vol = 0.3 },
  { dur = 0.09, wave = "sine", f0 = 2800, decay = 30, vol = 0.2 },
} }
-- a choice confirmed: four notes stepping up, swelling to the last and fading
local DECIDE_STEPS = { 349, 349, 440, 523, 523, 587, 587, 587, 587, 587 }
local DECIDE = {
  { dur = 0.47, wave = "pulse25", steps = DECIDE_STEPS, step = 0.05, attack = 0.01, release = 0.17, vol = 0.18 },
  { dur = 0.47, wave = "pulse25", steps = DECIDE_STEPS, step = 0.05, attack = 0.28, release = 0.17, vol = 0.32 },
  { at = 0.25, dur = 0.22, wave = "tri", f0 = 784, attack = 0.03, release = 0.17, vol = 0.35 },
  { at = 0.2, dur = 0.27, wave = "sine", f0 = 8500, attack = 0.05, release = 0.15, vol = 0.04 },
}
S["se/kw_decide"] = { peak = 0.55, layers = DECIDE }
S["se/kw_selgame"] = S["se/kw_decide"]
S["se/kw_decide2"] = { peak = 0.6, layers = DECIDE }
-- back: a short tone sliding down, swelling then fading
S["se/kw_cancel"] = { peak = 0.5, layers = {
  { dur = 0.31, wave = "pulse25", f0 = 580, f1 = 470, attack = 0.1, decay = 6, vol = 0.45 },
  { dur = 0.31, wave = "noise", poles = 2, lp = 1500, attack = 0.1, decay = 8, vol = 0.15 },
} }
-- the play button opens the picker: the choice's swell
S["se/kw_selplay"] = { peak = 0.6, layers = DECIDE }
-- Play Again: a quick bright chirp
S["se/kw_onceagain"] = { peak = 0.55, layers = {
  { dur = 0.1, wave = "noise", poles = 2, lp = 2000, decay = 30, vol = 0.5 },
  { dur = 0.1, wave = "tri", f0 = 720, f1 = 900, decay = 25, vol = 0.5 },
} }

-- 3, 2, 1: an E struck four times in quick succession, ringing out
local count = {}
for i = 0, 3 do
  count[#count + 1] = { at = i * 0.053, dur = i == 3 and 0.2 or 0.06, wave = "pulse25", f0 = 660, decay = i == 3 and 9 or 14, vol = 0.45 }
end
S["se/kw_countdown1"] = { peak = 0.5, layers = count }
-- START!: a quick trilled whistle
S["se/kw_start"] = { peak = 0.65, layers = {
  { dur = 0.15, wave = "sine", f0 = 2600, vib = { 0.6, 25 }, trem = { 0.4, 25 }, attack = 0.01, release = 0.03, vol = 0.6 },
  { dur = 0.15, wave = "noise", poles = 2, lp = 2500, attack = 0.01, release = 0.03, vol = 0.08 },
} }
-- Tile Puzzle's START!: a wobbling whistle, held, then cut
S["se/kw_start3"] = { peak = 0.65, layers = {
  { dur = 0.27, wave = "sine", f0 = 2900, vib = { 0.6, 20 }, attack = 0.02, release = 0.05, vol = 0.6 },
  { dur = 0.27, wave = "noise", poles = 2, lp = 2500, attack = 0.02, release = 0.05, vol = 0.08 },
} }
-- time over: a whistle, held, then a short second blast
S["se/kw_timeover"] = { peak = 0.6, layers = {
  { dur = 0.42, wave = "sine", f0 = 2950, vib = { 0.4, 22 }, trem = { 0.3, 18 }, attack = 0.01, release = 0.04, vol = 0.6 },
  { at = 0.47, dur = 0.12, wave = "sine", f0 = 2950, vib = { 0.4, 22 }, attack = 0.01, release = 0.05, vol = 0.6 },
  { dur = 0.59, wave = "noise", poles = 2, lp = 3000, attack = 0.01, release = 0.05, vol = 0.08 },
} }
-- Berry Picker's TIME'S UP: a referee's whistle, a short pip then a long trill
S["se/kw_end"] = { peak = 0.65, layers = {
  { dur = 0.1, wave = "sine", f0 = 2620, attack = 0.01, release = 0.02, vol = 0.6 },
  { at = 0.2, dur = 0.75, wave = "sine", f0 = 2620, vib = { 0.5, 25 }, trem = { 0.5, 22 }, attack = 0.02, release = 0.05, vol = 0.6 },
  { dur = 0.1, wave = "noise", poles = 2, lp = 3000, attack = 0.01, release = 0.02, vol = 0.12 },
  { at = 0.2, dur = 0.75, wave = "noise", poles = 2, lp = 3000, attack = 0.02, release = 0.05, vol = 0.12 },
} }
S["se/kw_stamp"] = { peak = 0.75, layers = {
  { dur = 0.18, wave = "sine", f0 = 160, f1 = 60, decay = 14, vol = 0.8 },
  { dur = 0.1, wave = "noise", lp = 2500, decay = 30, vol = 0.6 } } }
-- the smoke clears on the puffs won: a burst of glittering air settling low
S["se/kw_sweet"] = { peak = 0.6, layers = {
  { dur = 0.95, wave = "noise", poles = 2, lp = 3000, lp1 = 1500, attack = 0.005, decay = 4, vol = 0.55 },
  { dur = 0.95, wave = "noise", poles = 2, lp = 250, attack = 0.005, decay = 3.5, vol = 0.5 },
} }
-- the picture whole: a bell struck once, ringing out
S["se/kw_star"] = { peak = 0.6, layers = {
  { dur = 0.81, wave = "sine", f0 = 700, attack = 0.005, decay = 3, vol = 0.5 },
  { dur = 0.81, wave = "sine", f0 = 1400, attack = 0.005, decay = 3.5, vol = 0.4 },
  { dur = 0.81, wave = "sine", f0 = 2100, attack = 0.005, decay = 4, vol = 0.3 },
  { dur = 0.81, wave = "sine", f0 = 3520, attack = 0.005, decay = 4.5, vol = 0.2 },
  { dur = 0.81, wave = "sine", f0 = 5280, attack = 0.005, decay = 5, vol = 0.12 },
} }
-- a puff held to it: a rush swelling to a burst, then fading long
S["se/kw_draw"] = { peak = 0.55, layers = {
  { dur = 0.19, wave = "noise", poles = 2, lp = 3000, attack = 0.17, release = 0.02, vol = 0.4 },
  { at = 0.17, dur = 0.54, wave = "noise", poles = 2, lp = 2500, attack = 0.005, decay = 6, vol = 0.7 },
  { dur = 0.12, wave = "sine", f0 = 1300, f1 = 1450, attack = 0.02, decay = 15, vol = 0.2 },
} }

-- a berry taken, a puff pulled out: a tone swelling in
S["se/kw_pick"] = { peak = 0.55, layers = {
  { dur = 0.12, wave = "tri", f0 = 820, f1 = 940, attack = 0.06, release = 0.05, vol = 0.5 },
  { dur = 0.12, wave = "noise", poles = 2, lp = 1500, attack = 0.06, release = 0.05, vol = 0.3 },
} }
-- the right berry handed over: a bright chord struck twice
local given = {}
for i = 0, 1 do
  for _, f in ipairs({ 660, 990, 1320 }) do
    given[#given + 1] = { at = i * 0.12, dur = 0.4 - i * 0.12, wave = "tri", f0 = f, decay = 7, vol = 0.3 }
  end
end
given[#given + 1] = { dur = 0.08, wave = "tri", f0 = 480, decay = 20, vol = 0.25 }
S["se/kw_give"] = { peak = 0.55, layers = given }
-- the right berry, quick: a bright chord struck three times, ringing
local struck = {}
for i = 0, 2 do
  for _, f in ipairs({ 660, 990, 1320 }) do
    struck[#struck + 1] = { at = i * 0.09, dur = 0.71 - i * 0.09, wave = "tri", f0 = f, decay = 4.5, vol = 0.3 }
  end
end
struck[#struck + 1] = { dur = 0.71, wave = "sine", f0 = 6340, decay = 5, vol = 0.06 }
S["se/kw_givefast"] = { peak = 0.6, layers = struck }
-- an asking Pokemon rises: a rush of air and a tone sweeping up into a held, wavering note
S["se/kw_enter"] = { peak = 0.5, layers = {
  { dur = 0.4, wave = "noise", poles = 2, lp = 2500, attack = 0.01, decay = 6, vol = 0.45 },
  { dur = 0.15, wave = "sine", f0 = 150, f1 = 1260, attack = 0.01, vol = 0.5 },
  { at = 0.15, dur = 0.25, wave = "sine", f0 = 1260, vib = { 0.3, 6 }, decay = 7, vol = 0.5 },
} }
S["se/kw_enter2"] = { peak = 0.5, layers = {
  { dur = 0.4, wave = "noise", poles = 2, lp = 2500, attack = 0.01, decay = 6, vol = 0.45 },
  { dur = 0.15, wave = "sine", f0 = 200, f1 = 1500, attack = 0.01, vol = 0.5 },
  { at = 0.15, dur = 0.25, wave = "sine", f0 = 1500, vib = { 0.3, 6 }, decay = 7, vol = 0.5 },
} }
-- dropping out of view: a tone arcing up and back down
S["se/kw_leave2"] = { peak = 0.5, layers = {
  { dur = 0.12, wave = "sine", f0 = 250, f1 = 950, attack = 0.01, vol = 0.5 },
  { at = 0.12, dur = 0.24, wave = "sine", f0 = 950, f1 = 250, decay = 5, vol = 0.5 },
  { dur = 0.12, wave = "tri", f0 = 500, f1 = 1900, attack = 0.01, vol = 0.15 },
  { at = 0.12, dur = 0.24, wave = "tri", f0 = 1900, f1 = 500, decay = 5, vol = 0.15 },
} }
-- the wrong berry, or it gave up: a harsh buzz cut short, a low tail
S["se/kw_fail"] = { peak = 0.55, layers = {
  { dur = 0.06, wave = "pulse50", f0 = 1700, attack = 0.005, release = 0.01, vol = 0.45 },
  { dur = 0.06, wave = "noise", poles = 2, lp = 3000, attack = 0.005, release = 0.01, vol = 0.5 },
  { at = 0.05, dur = 0.14, wave = "noise", poles = 2, lp = 900, decay = 18, vol = 0.25 },
} }
-- a puff let go falls: a soft low thump
S["se/kw_fallsweet"] = { peak = 0.5, layers = {
  { dur = 0.2, wave = "noise", poles = 2, lp = 700, decay = 40, vol = 0.6 },
  { dur = 0.12, wave = "sine", f0 = 160, f1 = 80, decay = 30, vol = 0.5 },
} }
-- the berries raining down (steady, stopped when the rain ends)
local patter = {}
for i = 0, 31 do
  patter[#patter + 1] = { at = i * 0.12 + (i % 3) * 0.02, dur = 0.07, wave = "sine", f0 = 600 + (i * 137) % 700, f1 = 300, decay = 30, vol = 0.35 }
end
-- the berries raining down: falling whistles, one after another, in three waves
local rain = {}
for wave = 0, 2 do
  for k = 0, 3 do
    local at = wave * 0.55 + k * 0.11
    rain[#rain + 1] = { at = at, dur = 0.33, wave = "sine", f0 = 4000 - k * 300, f1 = 900, attack = 0.02, release = 0.08, vol = 0.4 }
  end
end
-- the berries raining down: falling whistles, one after another, in four waves
local rain = {}
for wave = 0, 3 do
  for k = 0, 3 do
    local at = wave * 0.45 + k * 0.11
    rain[#rain + 1] = { at = at, dur = 0.33, wave = "sine", f0 = 4000 - k * 300, f1 = 900, attack = 0.02, release = 0.08, vol = 0.4 }
  end
end
S["se/kw_falling"] = { peak = 0.45, layers = rain }
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
-- a good heading: two thumps of air, a tone sliding up after them (in FEVER a high ring too)
local function goodHead(ring)
  local out = {
    { dur = 0.12, wave = "noise", poles = 2, lp = 2500, attack = 0.005, decay = 14, vol = 0.6 },
    { at = 0.07, dur = 0.15, wave = "noise", poles = 2, lp = 2500, attack = 0.005, decay = 12, vol = 0.6 },
    { dur = 0.33, wave = "noise", poles = 2, lp = 250, attack = 0.005, decay = 6, vol = 0.45 },
    { at = 0.08, dur = 0.25, wave = "tri", f0 = 280, f1 = 480, attack = 0.08, release = 0.08, vol = 0.3 },
  }
  if ring then out[#out + 1] = { dur = 0.41, wave = "sine", f0 = ring, attack = 0.05, decay = 4, vol = 0.08 } end
  return out
end
S["se/kw_headok"] = { peak = 0.6, layers = goodHead() }
-- a just heading: three thumps of air with a high ring over them (in FEVER the ring higher)
local function heading(ring)
  local out = {}
  for _, at in ipairs({ 0, 0.09, 0.2 }) do
    out[#out + 1] = { at = at, dur = 0.3, wave = "noise", poles = 2, lp = 2500, attack = 0.005, decay = 9, vol = 0.55 }
  end
  out[#out + 1] = { dur = 0.63, wave = "noise", poles = 2, lp = 250, attack = 0.005, decay = 4, vol = 0.45 }
  out[#out + 1] = { dur = 0.63, wave = "sine", f0 = ring, attack = 0.01, decay = 3, vol = 0.12 }
  return out
end
S["se/kw_headgood"] = { peak = 0.65, layers = heading(3180) }
S["se/kw_fheadok"] = { peak = 0.6, layers = goodHead(4860) }
S["se/kw_fheadgood"] = { peak = 0.65, layers = heading(7280) }
-- the giant headed well: a short block of noise
S["se/kw_lheadok"] = { peak = 0.7, layers = {
  { dur = 0.11, wave = "noise", poles = 2, lp = 3000, attack = 0.005, release = 0.05, vol = 0.6 },
  { dur = 0.11, wave = "noise", poles = 2, lp = 250, attack = 0.005, release = 0.05, vol = 0.5 },
} }
-- the giant headed: a big burst of air fizzing on a long while
S["se/kw_lheadgood"] = { peak = 0.75, layers = {
  { dur = 1.28, wave = "noise", poles = 2, lp = 3000, attack = 0.005, decay = 2.5, trem = { 0.2, 13 }, vol = 0.6 },
  { dur = 1.28, wave = "noise", poles = 2, lp = 250, attack = 0.005, decay = 3, vol = 0.45 },
  { at = 0.12, dur = 0.3, wave = "noise", poles = 2, lp = 2500, decay = 9, vol = 0.4 },
  { dur = 1.28, wave = "sine", f0 = 3580, attack = 0.01, decay = 2, vol = 0.08 },
} }
S["se/kw_headfail"] = { peak = 0.6, layers = {
  { dur = 0.25, wave = "sine", f0 = 160, f1 = 80, decay = 10, vol = 0.6 },
  { dur = 0.25, wave = "pulse50", f0 = 130, f1 = 90, decay = 10, vol = 0.2 } } }
-- the giant missed: a bright burst of noise, held, then fading
S["se/kw_lheadfail"] = { peak = 0.7, layers = {
  { dur = 0.46, wave = "noise", poles = 2, lp = 4000, attack = 0.005, decay = 3, vol = 0.6 },
  { dur = 0.46, wave = "noise", poles = 2, lp = 300, attack = 0.005, decay = 4, vol = 0.4 },
  { dur = 0.05, wave = "sine", f0 = 2700, decay = 30, vol = 0.25 },
} }
-- the giant ball drops: a heavy rumble swelling and dying away
S["se/kw_lballfall"] = { peak = 0.6, layers = {
  { dur = 0.87, wave = "noise", poles = 2, lp = 1500, attack = 0.08, decay = 2.6, vol = 0.6 },
  { dur = 0.87, wave = "noise", poles = 2, lp = 200, attack = 0.08, decay = 2.2, vol = 0.6 },
} }
-- "!!" for the giant: two high whistles bending up
S["se/kw_alert"] = { peak = 0.55, layers = {
  { dur = 0.17, wave = "sine", f0 = 2800, f1 = 3100, attack = 0.005, decay = 15, vol = 0.5 },
  { dur = 0.17, wave = "sine", f0 = 5000, f1 = 7200, attack = 0.005, decay = 15, vol = 0.35 },
} }
-- a combo begins: an E held a moment, then let go
S["se/kw_combo"] = { peak = 0.55, layers = {
  { dur = 0.33, wave = "pulse25", f0 = 660, attack = 0.01, release = 0.2, vol = 0.45 },
  { dur = 0.33, wave = "tri", f0 = 1320, attack = 0.01, release = 0.2, vol = 0.3 },
} }
-- a 10-hit combo: a bright chord held, then let go
S["se/kw_combo2"] = { peak = 0.6, layers = {
  { dur = 0.43, wave = "pulse25", f0 = 660, attack = 0.01, release = 0.13, vol = 0.3 },
  { dur = 0.43, wave = "tri", f0 = 831, attack = 0.01, release = 0.13, vol = 0.3 },
  { dur = 0.43, wave = "tri", f0 = 988, attack = 0.01, release = 0.13, vol = 0.3 },
  { dur = 0.43, wave = "noise", poles = 2, lp = 3000, attack = 0.01, release = 0.13, trem = { 0.5, 14 }, vol = 0.25 },
} }
-- a 50-hit combo: tones stacking up, pulsing, to a sudden stop
S["se/kw_combo3"] = { peak = 0.6, layers = {
  { dur = 0.5, wave = "pulse25", steps = { 330, 660, 740, 820, 980, 1000, 1320 }, step = 0.075, attack = 0.4, release = 0.08, trem = { 0.5, 14 }, vol = 0.4 },
  { dur = 0.5, wave = "tri", steps = { 660, 740, 980, 1320, 1660, 1660, 1660 }, step = 0.075, attack = 0.4, release = 0.08, vol = 0.3 },
  { at = 0.5, dur = 0.15, wave = "tri", f0 = 1320, decay = 18, vol = 0.2 },
} }
-- a 100-hit combo: a long pulsing build of stacked tones to a sudden stop, a shimmer after
S["se/kw_combo4"] = { peak = 0.65, layers = { chime(hz("G6"), 0, 0.2), chime(hz("B6"), 0.05, 0.2), chime(hz("D7"), 0.1, 0.2), chime(hz("G7"), 0.15, 0.5),
  { at = 0.2, dur = 0.4, wave = "noise", lp = 8000, vol = 0.1, release = 0.3 } } }

-- the RESULTS card comes in: a noisy burst settling low
S["se/kw_number"] = { peak = 0.5, layers = {
  { dur = 0.6, wave = "noise", poles = 2, lp = 2000, attack = 0.01, decay = 6, vol = 0.5 },
  { dur = 0.6, wave = "noise", poles = 2, lp = 250, attack = 0.01, decay = 4, vol = 0.5 },
} }
local ticks = {}
for i = 0, 79 do ticks[#ticks + 1] = { at = i * 0.05, dur = 0.02, wave = "pulse25", f0 = 1600, decay = 60, vol = 0.35 } end
-- a score counting up: a scatter of low ticks (steady, stopped when it ends)
local tally = { { dur = 4, wave = "noise", poles = 2, lp = 600, attack = 0.05, vol = 0.25 } }
for i = 0, 47 do
  tally[#tally + 1] = { at = i * 0.083 + (i % 3) * 0.012, dur = 0.05, wave = "noise", poles = 2, lp = 1800, decay = 50, vol = 0.7 }
end
S["se/kw_addscore"] = { peak = 0.4, layers = tally }
-- a bonus row settles: a low, noisy thud
S["se/kw_score"] = { peak = 0.55, layers = {
  { dur = 0.47, wave = "noise", poles = 2, lp = 1200, attack = 0.005, decay = 6, vol = 0.5 },
  { dur = 0.47, wave = "noise", poles = 2, lp = 250, attack = 0.005, decay = 4, vol = 0.6 },
} }
-- one star: a chime falling slowly, wobbling as it goes
S["se/kw_value1"] = { peak = 0.55, layers = {
  { dur = 0.95, wave = "tri", f0 = 900, f1 = 440, attack = 0.01, decay = 2.4, trem = { 0.5, 12 }, vol = 0.55 },
  { dur = 0.95, wave = "sine", f0 = 3300, f1 = 1900, attack = 0.01, decay = 3.5, trem = { 0.5, 12 }, vol = 0.2 },
} }
-- two stars: a fluttering chord, then its ring fading
S["se/kw_value2"] = { peak = 0.55, layers = {
  { dur = 0.84, wave = "pulse25", f0 = 330, attack = 0.02, decay = 4, trem = { 0.6, 25 }, vol = 0.3 },
  { dur = 0.84, wave = "tri", f0 = 500, attack = 0.02, decay = 4, trem = { 0.6, 25 }, vol = 0.4 },
  { dur = 0.84, wave = "tri", f0 = 660, attack = 0.02, decay = 4.5, vol = 0.3 },
  { dur = 0.6, wave = "sine", f0 = 8900, attack = 0.02, decay = 6, vol = 0.05 },
} }
-- three stars: a fluttering low chord with a high shimmer over it, ringing long
S["se/kw_value3"] = { peak = 0.6, layers = {
  { dur = 0.96, wave = "tri", f0 = 370, attack = 0.01, decay = 3, trem = { 0.6, 22 }, vol = 0.45 },
  { dur = 0.96, wave = "tri", f0 = 460, attack = 0.01, decay = 3, trem = { 0.6, 22 }, vol = 0.35 },
  { dur = 0.96, wave = "noise", poles = 2, lp = 5000, attack = 0.01, decay = 4, trem = { 0.6, 22 }, vol = 0.2 },
  { dur = 0.96, wave = "sine", f0 = 9500, attack = 0.01, decay = 4, vol = 0.05 },
} }

-- a tile lifts: a soft puff
S["se/kw_float"] = { peak = 0.5, layers = {
  { dur = 0.08, wave = "noise", poles = 2, lp = 1500, attack = 0.01, decay = 30, vol = 0.5 },
  { dur = 0.08, wave = "tri", f0 = 460, attack = 0.01, decay = 30, vol = 0.4 },
} }
-- two tiles swap: a rush with a tone chirping up through it
S["se/kw_swap"] = { peak = 0.55, layers = {
  { dur = 0.23, wave = "noise", poles = 2, lp = 2500, attack = 0.02, decay = 12, vol = 0.5 },
  { dur = 0.15, wave = "sine", f0 = 700, f1 = 2800, attack = 0.02, decay = 8, vol = 0.4 },
} }
S["se/kw_setpanel"] = { peak = 0.55, layers = {
  { dur = 0.08, wave = "pulse25", f0 = 700, f1 = 400, decay = 30, vol = 0.5 },
  { dur = 0.04, wave = "noise", lp = 3500, decay = 60, vol = 0.35 } } }

-- ------- Pokemon-Amie's room, PLAY and DECORATE (each shaped as the game's: its length, its
-- pitch rising or falling, noise or tone)

-- the room's menu, DECORATE's pills: a warbling blip
S["se/decide1"] = { peak = 0.55, layers = {
  { dur = 0.29, wave = "tri", f0 = 380, vib = { 3, 11 }, attack = 0.01, decay = 9, vol = 0.55 },
  { dur = 0.29, wave = "sine", f0 = 1950, vib = { 3, 11 }, attack = 0.01, decay = 10, vol = 0.25 },
  { dur = 0.03, wave = "noise", poles = 2, lp = 2500, decay = 60, vol = 0.4 },
} }
-- DECORATE: an item taken into the finger (a quick wavering pip), and let go (a dip and a rise)
S["se/catch"] = { peak = 0.5, layers = {
  { dur = 0.09, wave = "tri", f0 = 520, vib = { 4, 15 }, decay = 18, vol = 0.5 },
  { dur = 0.09, wave = "noise", poles = 2, lp = 1500, decay = 25, vol = 0.25 },
} }
S["se/release"] = { peak = 0.5, layers = {
  { dur = 0.06, wave = "sine", f0 = 950, f1 = 550, vol = 0.5 },
  { at = 0.06, dur = 0.06, wave = "sine", f0 = 550, f1 = 900, release = 0.03, vol = 0.5 },
  { dur = 0.12, wave = "noise", poles = 2, lp = 1500, decay = 20, vol = 0.25 },
} }

-- PLAY: a finger lands on the Pokemon (a soft, airy pat)
S["se/kw_touch"] = { peak = 0.45, layers = {
  { dur = 0.05, wave = "noise", poles = 2, lp = 2500, decay = 50, vol = 0.5 },
  { dur = 0.05, wave = "sine", f0 = 900, f1 = 1300, decay = 40, vol = 0.4 },
} }
S["se/kw_stroke"] = { peak = 0.5, layers = {
  { dur = 0.08, wave = "sine", f0 = 220, f1 = 260, vol = 0.5, attack = 0.03, release = 0.03 },
  { at = 0.08, dur = 0.1, wave = "tri", f0 = 850, f1 = 1300, vol = 0.25, release = 0.05 } } }
-- happy: bouncing "boing"s, each a tone arcing up and back; the reward's run of eight fading,
-- a dance step's four
local function boings(n, every, fade)
  local out = {}
  for i = 0, n - 1 do
    local k, at, up = fade ^ i, i * every, every * 0.45
    out[#out + 1] = { at = at, dur = up, wave = "tri", f0 = 300, f1 = 1150, attack = 0.005, vol = 0.45 * k }
    out[#out + 1] = { at = at + up, dur = every - up, wave = "tri", f0 = 1150, f1 = 650, release = 0.01, vol = 0.45 * k }
    out[#out + 1] = { at = at, dur = up, wave = "sine", f0 = 600, f1 = 2300, attack = 0.005, vol = 0.15 * k }
    out[#out + 1] = { at = at + up, dur = every - up, wave = "sine", f0 = 2300, f1 = 1300, release = 0.01, vol = 0.15 * k }
  end
  return out
end
S["se/kw_heart1"] = { peak = 0.55, layers = boings(4, 0.09, 0.95) }
S["se/kw_heart2"] = { peak = 0.6, layers = boings(9, 0.09, 0.82) }
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
-- the high five: three quick claps, a ring after them
local claps = {}
for i, at in ipairs({ 0, 0.11, 0.2, 0.3 }) do
  claps[#claps + 1] = { at = at, dur = 0.1, wave = "noise", poles = 2, lp = 3500, decay = 25, vol = ({ 1, 0.7, 0.8, 0.5 })[i] }
end
claps[#claps + 1] = { dur = 0.4, wave = "sine", f0 = 1300, decay = 6, vol = 0.15 }
S["se/kw_snap"] = { peak = 0.65, layers = claps }
-- the Poke Puff drawer opening (a rising swish into a held note) and closing (a short swish down)
S["se/kw_selsweet"] = { peak = 0.55, layers = {
  { dur = 0.16, wave = "noise", lp = 900, lp1 = 2500, vol = 0.35, attack = 0.05, release = 0.04 },
  { at = 0.04, dur = 0.37, wave = "tri", steps = { 450, 525, 600, 775 }, step = 0.06, vol = 0.45, release = 0.2 } } }
S["se/kw_closesweet"] = { peak = 0.5, layers = {
  { dur = 0.1, wave = "noise", lp = 2500, lp1 = 900, vol = 0.35, release = 0.03 },
  { at = 0.06, dur = 0.24, wave = "tri", f0 = 600, f1 = 450, vol = 0.45, release = 0.12 } } }
-- a bite: two quick crunches
S["se/kw_eat"] = { peak = 0.55, layers = {
  { dur = 0.035, wave = "noise", poles = 2, lp = 1500, decay = 60, vol = 0.8 },
  { at = 0.055, dur = 0.05, wave = "noise", poles = 2, lp = 1200, attack = 0.015, release = 0.02, vol = 0.8 },
  { at = 0.05, dur = 0.06, wave = "tri", f0 = 460, attack = 0.015, release = 0.02, vol = 0.3 },
} }
-- the last bite: a fluttering munch, cut off
S["se/kw_eatswallow"] = { peak = 0.55, layers = {
  { dur = 0.22, wave = "noise", poles = 2, lp = 1500, attack = 0.02, release = 0.03, trem = { 0.6, 20 }, vol = 0.6 },
  { dur = 0.22, wave = "tri", f0 = 320, f1 = 600, attack = 0.02, release = 0.03, trem = { 0.6, 20 }, vol = 0.35 },
} }
-- it will not eat: a low warbling groan
S["se/kw_fault"] = { peak = 0.6, layers = {
  { dur = 0.26, wave = "tri", f0 = 620, vib = { 4, 8 }, attack = 0.005, decay = 8, vol = 0.45 },
  { dur = 0.26, wave = "noise", poles = 2, lp = 1000, attack = 0.005, decay = 15, vol = 0.4 },
  { dur = 0.26, wave = "sine", f0 = 100, attack = 0.005, decay = 10, vol = 0.3 },
} }
-- a visitor speaks: a soft blip rising
S["se/kw_face1"] = { peak = 0.45, layers = {
  { dur = 0.07, wave = "noise", poles = 2, lp = 1200, decay = 30, vol = 0.5 },
  { dur = 0.07, wave = "tri", f0 = 500, f1 = 800, decay = 20, vol = 0.45 },
} }
-- tapped awake, a visitor chatting: a high chirp, then a lower blip
S["se/kw_face2"] = { peak = 0.5, layers = {
  { dur = 0.04, wave = "sine", f0 = 1140, f1 = 1380, decay = 20, vol = 0.4 },
  { at = 0.055, dur = 0.075, wave = "noise", poles = 2, lp = 1200, attack = 0.02, release = 0.05, vol = 0.5 },
  { at = 0.055, dur = 0.075, wave = "tri", f0 = 280, f1 = 700, attack = 0.02, release = 0.05, vol = 0.4 },
} }
-- the "..." bubble: two tones drifting up
S["se/kw_think"] = { peak = 0.5, layers = {
  { dur = 0.25, wave = "tri", f0 = 340, f1 = 460, attack = 0.005, decay = 6, vol = 0.5 },
  { dur = 0.25, wave = "sine", f0 = 980, f1 = 1400, attack = 0.005, decay = 7, vol = 0.3 },
} }
-- dozing off: a long airy sigh, swelling and fading
S["se/kw_sleep"] = { peak = 0.35, layers = {
  { dur = 0.55, wave = "noise", poles = 2, lp = 3500, attack = 0.3, release = 0.25, vol = 0.5 },
  { dur = 0.55, wave = "noise", poles = 2, lp = 600, attack = 0.3, release = 0.25, vol = 0.35 },
} }
-- a gift: a fanfare of fifths, a chime held over it
S["se/kw_bonus"] = { peak = 0.6, layers = {
  { dur = 0.24, wave = "pulse25", steps = { hz("C5"), hz("G5") }, step = 0.08, vol = 0.45, release = 0.03 },
  { at = 0.16, dur = 0.08, wave = "pulse25", f0 = hz("C5"), vol = 0.4 },
  chime(hz("C6"), 0.24, 0.45, 0.45),
  { at = 0.22, dur = 0.2, wave = "noise", lp = 6000, vol = 0.08, release = 0.15 } } }

return S
