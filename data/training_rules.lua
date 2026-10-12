-- Every number Super Training uses, in one place, with its provenance. The code reads only
-- these tables (src/training/rules.lua, sim.lua); nothing numeric hides in the apps.
--
-- EVIDENCE classifies each group (dotted key path):
--   verified     stated by a reliable source (Bulbapedia, Serebii, ORAS Wiki, the Japanese
--                wikis pente.koro-pokemon.com / atwiki pkmnomegaralphas / gamepedia.jp /
--                blog.game-de.com, or the game's own files)
--   measured     taken from recorded original gameplay (none yet)
--   inferred     deduced from several sources that agree indirectly
--   placeholder  no public source; a provisional value chosen to keep the original loop
--                playable, meant to be corrected without touching the engine of the game
-- `confidence` is low / medium / high for the value itself.

local N = {}

N.LIMITS = {
  EV_CAP = 252,        -- per stat for every Super Training source
  EV_TOTAL = 510,
  BAG_MAX = 12,        -- training bags carried at once
  EV_BY_LEVEL = { 4, 8, 12 },
  DOUBLE_UP_MULT = 2,
}

-- Stat bags are expanded per stat by rules.lua (hp_s, hp_m, hp_l, atk_s ...). `effect`
-- bags set the one pending regimen effect; reset and soothing act at once.
N.BAGS = {
  STAT = { s = { hits = 10, ev = 1 }, m = { hits = 25, ev = 4 }, l = { hits = 50, ev = 12 } },
  big_shot = { hits = 10, effect = "big_shot" },
  double_up = { hits = 10, effect = "double_up" },
  strength = { hits = 10, effect = "strength" },
  swiftness = { hits = 10, effect = "swiftness" },
  toughen_up = { hits = 10, effect = "toughen_up" },
  team_flare = { hits = 10, effect = "refreshed" },
  reset = { hits = 100, effect = "reset" },
  soothing = { hits = 250, effect = "friendship", amount = 20 },
}

N.CORE = {
  AUTO_HIT_S = 60,          -- the Pokemon hits its bag once a minute while the screen is open
  REFRESHED_HITS_DIV = 2,   -- a refreshed Pokemon needs half the hits
  REFRESHED_S = 600,        -- how long the refreshed state lasts (wall clock seconds)
  REST_ODDS = 0.12,         -- chance to lie down at each automatic hit
  BLACK_BAG_DROP = 0.03,    -- chance per tap of the empty bag to drop a bag
  BLACK_BAG_MIN_TAPS = 8,   -- taps before a drop can happen
}

-- weights for the random bags. `stat_s` means the S bag of a random stat.
N.BAG_ODDS = {
  black = { stat_s = 24, big_shot = 5, double_up = 4, strength = 5, swiftness = 5, toughen_up = 5,
            team_flare = 3, reset = 2, soothing = 2 },
  support = { big_shot = 3, double_up = 2, strength = 3, swiftness = 3, toughen_up = 3 },
  DOUBLE_UP_POKERUS_MULT = 2,
  -- clearing a course: the stat bag's size by the fraction of the clock left, else Double-Up
  clear = { l_at = 0.75, m_at = 0.45, double_up = 0.15 },
}

N.CLOCK = {
  TIME = 180,            -- every course
  EXTRA_BOT_S = 30,      -- added when a bot pops in a circuit course
  COUNTDOWN_S = 3,
  TARGET = { [1] = 150, [2] = 120, [3] = 120, secret = 90, secret_long = 120 },
}

N.GOALS = {
  YELLOW_AT = 8,      -- a white goal turns yellow
  GONE_AT = 12,       -- and vanishes
  CHANCE_S = 10,      -- a red Chance Goal stays this long without a score
  CHANCE_ODDS = 0.5,  -- chance it appears once a group is cleared
  GROUP_GAP_S = 0.6,
  R = 0.12,           -- goal radius in bot-local units
  CHANCE_R = 0.16,
  MARKER_R = 0.12,
  -- goals travel over the balloon's own shape (the Pokemon's sprite): bot-local units per
  -- second, by course level; goals on a moving part (an anchor with `motion`) and the
  -- fleeing / roaming courses go faster and further. RADIUS: how far from its spot a goal
  -- wanders (bot-local units); the fleeing and roaming courses use the whole sprite.
  WANDER = {
    SPEED = { [1] = 0.15, [2] = 0.25, [3] = 0.33, secret = 0.36 },
    MOTION_SPEED = 0.6, ROAM_SPEED = 0.55, FLEE_SPEED = 1.1,
    RADIUS = 0.45, MOTION_RADIUS = 0.8, PAUSE_S = 0.6,
  },
}

N.CHARGE = {
  STAGE_S = { 0.5, 1.0, 1.6 },  -- time held for stage 1 / 2 / 3
  OVER_S = 2.6,                 -- held past this: the charge breaks
  STUN_S = 1.0,                 -- and the Pokemon stops for about a second
  MULT = { 1, 2, 3 },           -- points multiplier per stage (stage 3 = 3x)
  SIZE = { 1, 1.2, 1.4 },
  YELLOW_BURST = 7,             -- a max-charge yellow shot fires this many balls
}

N.GUTS = {
  RATE = 0.5,           -- fraction of the circle refilled per second
  DEF_BONUS = 0.5,      -- +50% at 252 Def+SpD EVs (linear)
  FULL_AT = 1.0,        -- a full meter turns the shot into the species' Energy Shot
  WEAK_BELOW = 0.2,     -- less than this left: a weak black ball
  START = 1.0,
}

-- per Energy Shot colour: relative size, speed, points and guts cost
N.SHOT = {
  black  = { speed = 2.2, r = 0.07, mult = 1.0, cost = 0.25 },
  yellow = { speed = 2.6, r = 0.05, mult = 0.4, cost = 0.08, rapid = 0.12 },
  orange = { speed = 2.0, r = 0.10, mult = 0.8, cost = 0.25 },
  green  = { speed = 1.4, r = 0.09, mult = 1.6, cost = 0.4 },
  blue   = { speed = 3.2, r = 0.05, mult = 1.3, cost = 0.4 },
  weak   = { speed = 1.8, r = 0.05, mult = 0.3, cost = 0 },
  RAPID = "yellow",      -- the colour that sprays while held
  BIG_SHOT_SIZE = 1.5,
  HP_SIZE_BONUS = 0.4,   -- +40% radius at 252 HP EVs
  SPE_SPEED_BONUS = 0.4,
}

N.POINTS = {
  BASE = { [1] = 20, [2] = 60, [3] = 90, secret = 100 },  -- a plain goal per course level
  CHANCE_MULT = 1.0,     -- a Chance Goal scores like a plain goal, repeatedly
  ATK_BONUS = 0.5,       -- +50% at 252 Atk+SpA EVs
  STRENGTH_MULT = 2,
}

N.DAMAGE = {
  small = 50, big = 150, ring = 100, homing = 100, cross = 120, wave = 200, bit = 40,
  HP_REDUCE = 0.5,       -- -50% at 252 HP EVs
  TOUGHEN_MULT = 0.5,
  SUDDEN_DEATH = 9999,   -- the Hydreigon course
  LEVEL_MULT = { 1, 1.25, 1.5, secret = 1.5 },   -- higher levels take more per hit
}

N.ATTACK = {
  TELEGRAPH_S = 1.0,
  small = { speed = 1.4, r = 0.06, gap = 0.35 },
  big = { speed = 0.9, r = 0.16 },
  ring = { speed = 1.1, n = 8, r = 0.06, spin = 1.2, ring_r = 0.45 },
  homing = { speed = 0.9, r = 0.07, turn = 1.4 },
  cross = { speed = 1.2, r = 0.06, arms = 4, arm_len = 0.35 },
  wave_tall = { speed = 1.0, cols = 4, gap_w = 0.3 },
  wave_wide = { speed = 1.0, w = 1.4 },
  bit = { z = 0.7, r = 0.1, hp = 3, fire_every = 2.5, y = 0.5, regen_s = 12 },
  barrier = { max_s = 25 },
}

N.BLOCK = { LEN = 0.6, COOLDOWN = 1.5, DEF_BONUS = 0.5 }

N.PLAYER = { X_MAX = 0.8, Z_MAX = 0.3, SPEED = 1.1, R = 0.12, H = 0.3, SPE_BONUS = 0.4, SWIFT_MULT = 1.3,
             HIT_STUN_S = 0.6 }

N.BOT = { GROWTH = 0.02, SCALE_MAX = 1.5, R = 0.32, FLINCH_S = 0.35, CY = 0.45,
          -- a sprite balloon is taller than the round one: it hovers higher, sized so that even
          -- fully grown it stays inside the sky the aim pad reaches (AIM_X across, 0..AIM_Y up)
          SHAPE_CY = 1.04, AIM_X = 1.6, AIM_Y = 2.05,
          RAGE_AT = 2400, CALM_AT = 2400,
          RAGE_CADENCE = 0.6, RAGE_SPEED = 1.3, RAGE_DAMAGE = 1.5,   -- Aegislash past 2400
          CALM_CADENCE = 1.8, CALM_SPEED = 0.8 }                      -- Roserade past 2400

-- fallback colour by primary GBA type id when a species is not in the Bulbapedia table
N.SHOT_TYPE_BY_TYPE = { [13] = "yellow", [10] = "orange", [12] = "green", [6] = "green", [11] = "blue", [15] = "blue" }

N.ITEMS = { WING_EV = 1 }

-- ------- provenance (see the header)
N.EVIDENCE = {
  ["LIMITS.EV_CAP"] = { class = "verified", source = "atwiki pkmnomegaralphas Super Training page; Bulbapedia Effort values", confidence = "high" },
  ["LIMITS.EV_TOTAL"] = { class = "verified", source = "Bulbapedia Effort values", confidence = "high" },
  ["LIMITS.BAG_MAX"] = { class = "verified", source = "Serebii X/Y Super Training; gamepedia.jp; game-de", confidence = "high" },
  ["LIMITS.EV_BY_LEVEL"] = { class = "verified", source = "Bulbapedia Super Training", confidence = "high" },
  ["LIMITS.DOUBLE_UP_MULT"] = { class = "verified", source = "Bulbapedia Double-Up Bag", confidence = "high" },
  ["BAGS"] = { class = "verified", source = "Bulbapedia Super Training, Training Bags table (Team Flare 10 hits; gamepedia.jp says 5)", confidence = "high" },
  ["CORE.AUTO_HIT_S"] = { class = "verified", source = "Bulbapedia; pente.koro-pokemon.com", confidence = "high" },
  ["CORE.REFRESHED_HITS_DIV"] = { class = "verified", source = "atwiki; game-de (hits halved); Bulbapedia (double speed)", confidence = "high" },
  ["CORE.REFRESHED_S"] = { class = "placeholder", source = "no source states how long the second wind lasts", confidence = "low" },
  ["CORE.REST_ODDS"] = { class = "placeholder", source = "Bulbapedia: rests occasionally", confidence = "low" },
  ["CORE.BLACK_BAG_DROP"] = { class = "placeholder", source = "game-de: the drop rate is low", confidence = "low" },
  ["CORE.BLACK_BAG_MIN_TAPS"] = { class = "placeholder", source = "", confidence = "low" },
  ["BAG_ODDS.black"] = { class = "placeholder", source = "which bags drop is verified (JP bag page); the weights are not", confidence = "low" },
  ["BAG_ODDS.support"] = { class = "placeholder", source = "atwiki comment: a time out gives a support bag", confidence = "low" },
  ["BAG_ODDS.DOUBLE_UP_POKERUS_MULT"] = { class = "placeholder", source = "Bulbapedia Pokerus: raises the Double-Up rate, amount unknown", confidence = "low" },
  ["BAG_ODDS.clear"] = { class = "inferred", source = "atwiki: size random, maybe tied to clear time; game-de: faster clears give bigger bags", confidence = "low" },
  ["CLOCK.TIME"] = { class = "inferred", source = "Gamer Guides time-to-beat 0:30 / 1:00 / 1:30-3:00 equals 3:00 minus the JP target records; GameFAQs: remaining time", confidence = "medium" },
  ["CLOCK.EXTRA_BOT_S"] = { class = "verified", source = "Bulbapedia; atwiki", confidence = "high" },
  ["CLOCK.COUNTDOWN_S"] = { class = "placeholder", source = "", confidence = "low" },
  ["CLOCK.TARGET"] = { class = "verified", source = "pente.koro-pokemon.com/xy/supatore-list (target records); ORAS Wiki", confidence = "high" },
  ["GOALS.YELLOW_AT"] = { class = "verified", source = "ORAS Wiki (oraswiki.com)", confidence = "medium" },
  ["GOALS.GONE_AT"] = { class = "verified", source = "ORAS Wiki", confidence = "medium" },
  ["GOALS.CHANCE_S"] = { class = "verified", source = "AS text 44:62: red goals disappear after a set amount of time; ORAS Wiki: over 10 seconds", confidence = "medium" },
  ["GOALS.CHANCE_ODDS"] = { class = "placeholder", source = "AS text 45:84: a red bonus goal needs every white goal blasted first (necessary, not always sufficient); gamepedia.jp", confidence = "low" },
  ["GOALS.GROUP_GAP_S"] = { class = "placeholder", source = "", confidence = "low" },
  ["GOALS.R"] = { class = "placeholder", source = "", confidence = "low" },
  ["GOALS.CHANCE_R"] = { class = "placeholder", source = "", confidence = "low" },
  ["GOALS.MARKER_R"] = { class = "placeholder", source = "", confidence = "low" },
  ["GOALS.WANDER"] = { class = "inferred", source = "AS text 44:64 (goals on arms, wings and other moving bits make aiming harder), 45:87 / 45:99 / 45:104 (fleeing, constantly moving goals); the speeds and ranges are ours", confidence = "low" },
  ["CHARGE.STAGE_S"] = { class = "placeholder", source = "atwiki: three stages", confidence = "low" },
  ["CHARGE.OVER_S"] = { class = "placeholder", source = "AS text 44:68: if you wait too long, your aura will fizzle out; atwiki / pente", confidence = "low" },
  ["CHARGE.STUN_S"] = { class = "inferred", source = "atwiki: about one second unable to act", confidence = "medium" },
  ["CHARGE.MULT"] = { class = "inferred", source = "AS text 44:68: a Charged Shot nets triple points; stage 2 unknown", confidence = "medium" },
  ["CHARGE.SIZE"] = { class = "placeholder", source = "", confidence = "low" },
  ["CHARGE.YELLOW_BURST"] = { class = "verified", source = "atwiki: 7 shots at max charge", confidence = "medium" },
  ["GUTS.RATE"] = { class = "placeholder", source = "game-de: a careful rhythm gets Energy Shots almost by itself, so the refill is quick", confidence = "low" },
  ["GUTS.FULL_AT"] = { class = "inferred", source = "AS text a/0/7/3 44:60: when you are full of that energy, the shots you let loose transform into Energy Shots; atwiki: a small meter gives a low-scoring black ball", confidence = "medium" },
  ["GUTS.DEF_BONUS"] = { class = "placeholder", source = "direction verified (Def/SpD fill guts faster)", confidence = "low" },
  ["GUTS.WEAK_BELOW"] = { class = "placeholder", source = "atwiki: a small meter gives a weak black ball; AS text 44:60 (Energy Shots need a full meter)", confidence = "low" },
  ["GUTS.START"] = { class = "placeholder", source = "", confidence = "low" },
  ["SHOT"] = { class = "placeholder", source = "the ordering per colour is verified (Bulbapedia, atwiki, gamepedia); the magnitudes are not", confidence = "low" },
  ["POINTS.BASE"] = { class = "placeholder", source = "", confidence = "low" },
  ["POINTS.CHANCE_MULT"] = { class = "placeholder", source = "JP guides call it a chance to rack up points; no multiplier is stated", confidence = "low" },
  ["POINTS.ATK_BONUS"] = { class = "placeholder", source = "direction verified", confidence = "low" },
  ["POINTS.STRENGTH_MULT"] = { class = "verified", source = "Bulbapedia Strength Bag: doubles points per shot", confidence = "high" },
  ["DAMAGE"] = { class = "placeholder", source = "Gamer Guides: typically 50-400; AS text 44:61: a hit costs some of the points you earned", confidence = "low" },
  ["DAMAGE.SUDDEN_DEATH"] = { class = "verified", source = "AS text 44:89: hit even once and your score drops back down to zero; atwiki", confidence = "high" },
  ["DAMAGE.LEVEL_MULT"] = { class = "placeholder", source = "atwiki: higher levels take more points per hit and attack more often; amounts unknown", confidence = "low" },
  ["ATTACK"] = { class = "placeholder", source = "the kinds are verified (atwiki enemy patterns); speeds and counts are not", confidence = "low" },
  ["ATTACK.bit.regen_s"] = { class = "placeholder", source = "AS text 44:70: bits regenerate given enough time; the time is not stated", confidence = "low" },
  ["BLOCK"] = { class = "placeholder", source = "AS text 44:67: L throws up a barrier for a short period, not usable nonstop; longer with Def/SpD (gamepedia); lengths unknown", confidence = "low" },
  ["PLAYER"] = { class = "placeholder", source = "bounded box and faster with Spe verified; sizes are not", confidence = "low" },
  ["BOT.GROWTH"] = { class = "placeholder", source = "atwiki: the balloon grows with every goal", confidence = "low" },
  ["BOT.SCALE_MAX"] = { class = "placeholder", source = "", confidence = "low" },
  ["BOT.R"] = { class = "placeholder", source = "", confidence = "low" },
  ["BOT.SHAPE_CY"] = { class = "placeholder", source = "ours: the sprite balloon's centre, so it fits the visible sky (y 0..2.09 at the bot's depth)", confidence = "low" },
  ["BOT.AIM_X"] = { class = "placeholder", source = "ours: the aim reach across with a sprite balloon (the sky at the bot's depth is +-1.71)", confidence = "low" },
  ["BOT.AIM_Y"] = { class = "placeholder", source = "ours: the aim reach up with a sprite balloon", confidence = "low" },
  ["BOT.FLINCH_S"] = { class = "placeholder", source = "atwiki: the balloon flinches on a goal", confidence = "low" },
  ["BOT.CY"] = { class = "placeholder", source = "", confidence = "low" },
  ["BOT.RAGE_AT"] = { class = "verified", source = "atwiki: Aegislash rages past 2400; AS text 44:84: gets faster as you get more points, shots more powerful", confidence = "medium" },
  ["BOT.CALM_AT"] = { class = "verified", source = "atwiki: Roserade calms past 2400; AS text 44:85: quick ferocious shots at first, sluggish as you score", confidence = "medium" },
  ["BOT.RAGE_CADENCE"] = { class = "placeholder", source = "AS text 44:84 says faster, not how much", confidence = "low" },
  ["BOT.RAGE_SPEED"] = { class = "placeholder", source = "AS text 44:84", confidence = "low" },
  ["BOT.RAGE_DAMAGE"] = { class = "placeholder", source = "AS text 44:84: its shots get more powerful too", confidence = "low" },
  ["BOT.CALM_CADENCE"] = { class = "placeholder", source = "AS text 44:85", confidence = "low" },
  ["BOT.CALM_SPEED"] = { class = "placeholder", source = "AS text 44:85", confidence = "low" },
  ["SHOT_TYPE_BY_TYPE"] = { class = "placeholder", source = "only used for species missing from the Bulbapedia table (none in Gen 3)", confidence = "low" },
  ["ITEMS.WING_EV"] = { class = "verified", source = "Bulbapedia Wing items: +1 EV", confidence = "high" },
}

return N
