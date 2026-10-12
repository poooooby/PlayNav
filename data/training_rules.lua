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

-- the Effort-o-Meter: each axis's length in pixels is the base stat's step plus the EV's step
-- (the game's own tables: { at least, pixels }, first match wins; 20 + 32 reaches the hexagon)
N.METER = {
  BASE_STEPS = { { 140, 20 }, { 120, 16 }, { 100, 14 }, { 80, 12 }, { 60, 10 }, { 40, 8 }, { 20, 6 }, { 1, 4 }, { 0, 1 } },
  EV_STEPS = { { 252, 32 }, { 216, 28 }, { 180, 24 }, { 144, 20 }, { 108, 16 }, { 72, 12 }, { 36, 8 }, { 1, 4 }, { 0, 1 } },
}

N.CORE = {
  AUTO_HIT_S = 60,          -- the Pokemon hits its bag once a minute on its own (screen open or not)
  -- it lies down after a rolled 30 to 60 minutes awake, or after a rolled 3 to 5 bags cleared,
  -- whichever comes first
  REST_AFTER_S = { 1800, 3600 },
  ROUTINE_REST_BAGS = { 3, 5 },
  -- the second wind: punches count double (a bag in half the hits; a regimen scores double).
  -- It lasts one bag or one regimen, never a time.
  REFRESHED_HITS_DIV = 2,
  SECOND_WIND_AFTER_BAG = 0.5,  -- chance of a second wind right after clearing a bag
  -- the blank bag (no training bag set): each punch finds a bag at this chance (percent), the
  -- bag then one of the game's 26 with equal odds (Team Flare's slot finds nothing)
  BLANK_BAG_DROP = 5,
  BLANK_BAG_DROP_FULLY = 10,    -- with all 510 EVs
  -- the coach's cheer while a training bag hangs: line FIRST + PER_GROUP * group + rand(3) of
  -- file 27, the group by bag; shown SHOW frames (30 a second), hidden HIDE, then a new line.
  -- The countdown stands still while a punch plays, so fast tapping spaces the lines out.
  CHEER = {
    FIRST = 45, PER_GROUP = 3, SHOW = 300, HIDE = 300,
    GROUP = { hp = 0, atk = 1, def = 2, spa = 1, spd = 2, spe = 3, big_shot = 0, strength = 1,
      toughen_up = 2, swiftness = 3, double_up = 4, team_flare = 5, reset = 6, soothing = 7 },
  },
}

-- weights for the random bags. `stat_s` means the S bag of a random stat.
N.BAG_ODDS = {
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
  -- the game's shot table (DllSparring.cro .rodata 0x18234, one 20-byte record per colour in
  -- this order: points, speed, size, cost, ?): its ratios on our scale, black anchoring it
  -- (black: speed 3.6, size 1.0, cost 180 in the game's units)
  black  = { speed = 2.2, r = 0.07, mult = 1.0, cost = 0.25 },
  yellow = { speed = 2.2, r = 0.049, mult = 0.3, cost = 0.0139, rapid = 0.12 },
  orange = { speed = 2.2, r = 0.14, mult = 0.8, cost = 0.25 },
  green  = { speed = 1.589, r = 0.105, mult = 2.0, cost = 0.4167 },
  blue   = { speed = 3.178, r = 0.0595, mult = 1.0, cost = 0.4167 },
  weak   = { speed = 2.2, r = 0.049, mult = 0.15, cost = 0.0 },
  RAPID = "yellow",      -- the colour that sprays while held
  BIG_SHOT_SIZE = 1.5,
  HP_SIZE_BONUS = 0.4,   -- +40% radius at 252 HP EVs
  SPE_SPEED_BONUS = 0.4,
}

N.POINTS = {
  BASE = { [1] = 20, [2] = 60, [3] = 90, secret = 100 },  -- a plain goal per course level
  CHANCE_MULT = 1.0,     -- a Chance Goal scores like a plain goal, repeatedly
  ATK_BONUS = 0.5,       -- +50% at 252 Atk+SpA EVs
  STRENGTH_MULT = 1.5,   -- the game's bag table: the four support bags carry 1.5
}

N.DAMAGE = {
  small = 50, big = 150, ring = 100, homing = 100, cross = 120, wave = 200, bit = 40,
  HP_REDUCE = 0.5,       -- -50% at 252 HP EVs
  TOUGHEN_MULT = 1 / 1.5,  -- the bag table's 1.5, as damage taken divided by it
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

N.PLAYER = { X_MAX = 0.8, Z_MAX = 0.3, SPEED = 1.1, R = 0.12, H = 0.3, SPE_BONUS = 0.4, SWIFT_MULT = 1.5,
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
  ["LIMITS.DOUBLE_UP_MULT"] = { class = "verified", source = "Bulbapedia Double-Up Bag; the game's training-bag table (main program 0x007ED098, DllSparring.cro 0x18030, DllSparringMenu.cro 0x6084): per bag { kind, value, hits / 5 }: 2.0" , confidence = "high" },
  ["BAGS"] = { class = "verified", source = "the game's training-bag table (main program 0x007ED098, DllSparring.cro 0x18030, DllSparringMenu.cro 0x6084): per bag { kind, value, hits / 5 }: stat S/M/L +1/+4/+12 in 10/25/50 hits, support bags 10, Team Flare 10, Reset 100, Soothing +20 in 250 (settles gamepedia.jp's 5 for Team Flare); Bulbapedia agrees", confidence = "high" },
  ["METER"] = { class = "verified", source = "the game's Effort-o-Meter step tables, main program 0x007EC5E8 (base) / 0x007EC604 (EVs), read by the code at 0x00761228 (u16 threshold, u16 pixels pairs); also DllSparringMenu.cro .rodata 0x6034", confidence = "high" },
  ["CORE.AUTO_HIT_S"] = { class = "verified", source = "Bulbapedia; pente.koro-pokemon.com; measured on Alpha Sapphire (Azahar, 2026-10-12): one punch a minute", confidence = "high" },
  ["CORE.REFRESHED_HITS_DIV"] = { class = "verified", source = "atwiki; game-de (hits halved); Bulbapedia (double speed); lasts one bag or one regimen (player guides)", confidence = "high" },
  ["CORE.REST_AFTER_S"] = { class = "measured", source = "Alpha Sapphire in Azahar, 2026-10-12: no rest after 45 minutes left alone; a rolled 30 to 60 minutes stands in", confidence = "low" },
  ["CORE.ROUTINE_REST_BAGS"] = { class = "inferred", source = "player data: a rest roughly every 3 to 5 bags cleared; the game's odds are not documented", confidence = "medium" },
  ["CORE.SECOND_WIND_AFTER_BAG"] = { class = "placeholder", source = "player guides: the happy bubble often follows a cleared bag; how often is not stated", confidence = "low" },
  ["CORE.CHEER"] = { class = "verified", source = "the game's code: main program 0x007BB504 (the home screen's cheer): with a bag on the stand and hits left, line = 45 + 3 * (first u16 of the bag's 12-byte record at 0x007ED088) + rand(3), shown through 0x761340, a 300-frame countdown at +0x26c shows / hides it in turn (0x007BB628 / 0x007BB6C8); traced live with breakpoints: shown at once on a new bag, hidden 10.2 s later, the next 10.5 s on, 12.8 s while tapping; the finish (0x007BBF4C) stops it", confidence = "high" },
  ["CORE.BLANK_BAG_DROP"] = { class = "verified", source = "the game's code: main program 0x007B9A0C (a tap on the blank bag): rand(100) < 5, or < 10 under a flag read from the Pokemon (0x006F6BF8), then rand(26) + 1 into the bag table at 0x007ED088; entry 24 (kind 5, Team Flare) gives nothing; caught live with a write watchpoint on the bag rack", confidence = "high" },
  ["CORE.BLANK_BAG_DROP_FULLY"] = { class = "inferred", source = "the 10 is the game's (see BLANK_BAG_DROP); that its flag is 'fully trained' is read from player reports", confidence = "medium" },
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
  ["SHOT"] = { class = "inferred", source = "the game's shot table, DllSparring.cro .rodata 0x18234 (6 x { points, speed, size, cost, ? } in the order black, yellow, orange, green, blue, weak; a slower variant at 0x1833C): the ratios between colours are the game's, the absolute scale is ours (black anchors it); the cost field read as energy (the weak shot costs 0)", confidence = "medium" },
  ["POINTS.BASE"] = { class = "placeholder", source = "", confidence = "low" },
  ["POINTS.CHANCE_MULT"] = { class = "placeholder", source = "JP guides call it a chance to rack up points; no multiplier is stated", confidence = "low" },
  ["POINTS.ATK_BONUS"] = { class = "placeholder", source = "direction verified", confidence = "low" },
  ["POINTS.STRENGTH_MULT"] = { class = "verified", source = "the game's training-bag table (main program 0x007ED098, DllSparring.cro 0x18030, DllSparringMenu.cro 0x6084): per bag { kind, value, hits / 5 }: 1.5 (Bulbapedia's 'doubles' is not what the game holds)", confidence = "high" },
  ["SHOT.BIG_SHOT_SIZE"] = { class = "verified", source = "the game's training-bag table (main program 0x007ED098, DllSparring.cro 0x18030, DllSparringMenu.cro 0x6084): per bag { kind, value, hits / 5 }: 1.5", confidence = "high" },
  ["PLAYER.SWIFT_MULT"] = { class = "verified", source = "the game's training-bag table (main program 0x007ED098, DllSparring.cro 0x18030, DllSparringMenu.cro 0x6084): per bag { kind, value, hits / 5 }: 1.5", confidence = "high" },
  ["DAMAGE.TOUGHEN_MULT"] = { class = "inferred", source = "the game's training-bag table (main program 0x007ED098, DllSparring.cro 0x18030, DllSparringMenu.cro 0x6084): per bag { kind, value, hits / 5 }: 1.5; read here as damage taken divided by 1.5", confidence = "medium" },
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
