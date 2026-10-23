-- Super Training's sound effects, PlayNav's own: each made on the chip synth
-- (src/chipsynth.lua M.effect; the layer fields are described there), under the ids
-- data/training_sounds.lua maps the events to. The three that the game loops while something
-- lasts (the charge, the wind-up, a ball in the air) are four seconds of steady sound, stopped
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

return S
