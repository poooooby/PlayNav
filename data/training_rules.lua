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
  CHANCE_S = 15,      -- a red Chance Goal stays this long without a score
  CHANCE_ODDS = 0.5,  -- chance it appears once a group is cleared (when CHANCE_EVERY is off)
  CHANCE_EVERY = 2,   -- the red goal comes after every second cleared group
  GROUP_GAP_S = 1.5,
  -- goal radius in world units at the balloon's depth: the game's goal panes are 32x32 of its
  -- 400x240 top screen, 16 px of radius = 9.6 px here = 0.08 units (N.VIEW.FAR.hw 120)
  R = 0.08,
  CHANCE_R = 0.08,
  MARKER_R = 0.08,
  -- goals travel over the balloon's own shape (the Pokemon's sprite): bot-local units per
  -- second, by course level; goals on a moving part (an anchor with `motion`) and the
  -- fleeing / roaming courses go faster and further. RADIUS: how far from its spot a goal
  -- wanders (bot-local units); the fleeing and roaming courses use the whole sprite.
  WANDER = {
    -- the regular goals stay where they appear (they move with the balloon: N.BOT.SWAY);
    -- only the fleeing and roaming courses' goals travel
    SPEED = { [1] = 0, [2] = 0, [3] = 0, secret = 0 },
    MOTION_SPEED = 0, ROAM_SPEED = 0.55, FLEE_SPEED = 1.1,
    RADIUS = 0.45, MOTION_RADIUS = 0.8, PAUSE_S = 0.6,
  },
}

-- a held touch charges from the press, whatever the meter holds (the game counts frames at 30
-- a second): Charged at STAGE_F[1], full at STAGE_F[2]; held FIZZLE_F, the charge breaks and the
-- Pokemon can neither move, shoot nor charge for STUN_F; after a Charged Shot, AFTER_F with no
-- shot or charge. A Charged Shot's points rise from x1 at stage 1 to x(1 + MULT_RISE) at stage 2.
N.CHARGE = {
  FPS = 30,
  STAGE_F = { 50, 66 },
  FIZZLE_F = 96,
  STUN_F = 30,
  AFTER_F = 15,
  MULT_RISE = 2,
  YELLOW_BURST = 7,             -- a max-charge yellow shot fires this many balls
}

-- the energy meter: CAP units (the sim keeps it as a fraction), refilled every frame by
-- int(PER_FRAME * (1 + (DEFv + EV total) * DEF_K)), DEFv = base Def + Sp. Def + 2 x their EVs;
-- a shot whose cost is more than the meter holds is the weak shot (costs nothing). The meter
-- starts empty. RATE is the refill a second with no stats known (a fake host).
N.GUTS = {
  CAP = 500,
  PER_FRAME = 4,
  DEF_K = 0.0025,
  START = 0,
  RATE = 0.5,
}

-- per Energy Shot colour: relative size, speed, points and guts cost
N.SHOT = {
  -- the game's shot table (DllSparring.cro .rodata 0x18234, one 20-byte record per colour in
  -- this order: points, speed, size, cost, ?): its ratios on our scale, black anchoring it
  -- (black: speed 3.6, size 1.0, cost 180 in the game's units); the speeds halved 2026-10-23
  -- (Wooble) against the game's Speed factor, which makes a trained Pokemon's shots up to ~2x;
  -- `cost` / `chargedCost` are the meter's CAP 500 shares (table A / table B at 0x1833C, a
  -- Charged Shot's), `chargedSpeed` table B's speed against A's
  black  = { speed = 1.1, r = 0.07, mult = 1.0, cost = 0.36, chargedCost = 0.36, chargedSpeed = 3.0 / 3.6 },
  yellow = { speed = 1.1, r = 0.049, mult = 0.3, cost = 0.02, chargedCost = 0.1, chargedSpeed = 3.0 / 3.6, rapid = 0.12 },
  orange = { speed = 1.1, r = 0.14, mult = 0.8, cost = 0.36, chargedCost = 0.36, chargedSpeed = 3.0 / 3.6 },
  green  = { speed = 0.7945, r = 0.105, mult = 2.0, cost = 0.6, chargedCost = 0.6, chargedSpeed = 2.1 / 2.6 },
  blue   = { speed = 1.589, r = 0.0595, mult = 1.0, cost = 0.6, chargedCost = 0.6, chargedSpeed = 1 },
  weak   = { speed = 1.1, r = 0.049, mult = 0.15, cost = 0.0, chargedCost = 0.0, chargedSpeed = 3.0 / 3.6 },
  RAPID = "yellow",      -- the colour whose max charge bursts (YELLOW_BURST balls); holding never fires
  BIG_SHOT_SIZE = 1.5,
  HP_SIZE_BONUS = 0.4,   -- +40% radius at 252 HP EVs (only without the Pokemon's stats)
  SPE_SPEED_BONUS = 0.4,
  -- the game's: speed x (1 + SPEv x SPE_K), SPEv = base Speed + 2 x its EVs; size x (1 + HPv x
  -- HP_K), HPv = base HP + 2 x its EVs. Our shot table's speeds and sizes are those at
  -- SPEv / HPv = STAT_REF (the game's scale is not ours), so the factors are taken against it.
  SPE_K = 0.005,
  HP_K = 0.00125,
  STAT_REF = 100,
}

-- a hit scores the shot's power: P x the colour's power, at least 1 (a Charged Shot by its
-- charge, N.CHARGE.MULT_RISE). P = (base Atk + Sp. Atk) div 5 + (their EVs) div 4 + 0.5 x min(EV
-- total, 50) + 0.2 x the EV total's next 50 + 0.1 x its next 410, x STRENGTH_MULT with Strength.
-- BASE / ATK_BONUS only when the Pokemon's stats are not known (a fake host).
N.POINTS = {
  EV_STEPS = { { 50, 0.5 }, { 100, 0.2 }, { 510, 0.1 } },
  BASE = { [1] = 20, [2] = 60, [3] = 90, secret = 100 },  -- a plain goal per course level
  CHANCE_MULT = 1.0,     -- a Chance Goal scores like a plain goal, repeatedly
  ATK_BONUS = 0.5,       -- +50% at 252 Atk+SpA EVs
  STRENGTH_MULT = 1.5,   -- the game's bag table: the four support bags carry 1.5
}

N.DAMAGE = {
  small = 50, big = 150, ring = 100, homing = 100, cross = 120, wave = 200, bit = 40,
  HP_REDUCE = 0.5,       -- -50% at 252 HP EVs (only without the Pokemon's stats)
  -- the game's: a hit's loss x 1 / (1 + (HPv + EV total) x LOSS_K)
  LOSS_K = 0.005,
  -- each balloon's own damage (data/training_courses.lua, the game's course data) for its balls;
  -- a bitbot's shot that share of it. The per-kind numbers above only for a course without it.
  BIT_SHARE = 0.8,
  TOUGHEN_MULT = 1 / 1.5,  -- the bag table's 1.5, as damage taken divided by it
  SUDDEN_DEATH = 9999,   -- the Hydreigon course
  LEVEL_MULT = { 1, 1.25, 1.5, secret = 1.5 },   -- higher levels take more per hit
}

N.ATTACK = {
  TELEGRAPH_S = 1.0,
  small = { speed = 1.19, r = 0.06, gap = 0.35 },
  big = { speed = 0.77, r = 0.16 },
  ring = { speed = 0.94, n = 8, r = 0.06, spin = 1.2, ring_r = 0.45 },
  homing = { speed = 0.77, r = 0.07, turn = 1.2 },
  cross = { speed = 1.02, r = 0.06, arms = 4, arm_len = 0.35 },
  wave_tall = { speed = 0.85, cols = 4, gap_w = 0.3 },
  wave_wide = { speed = 0.85, w = 1.4 },
  bit = { z = 0.7, r = 0.1, hp = 3, fire_every = 2.5, y = 0.5, regen_s = 12 },
  barrier = { max_s = 25 },
  -- a ball lobbed up off the top of the screen that comes down where the trainee stood when it
  -- was thrown: `flight` seconds, `peak` world units over its straight path at the top
  lob = { flight = 2.6, peak = 3.2, r = 0.12 },
  -- the balls are the game's soccer ball (target_ball00, 48 px of its 400 px top screen: 0.122
  -- world units of radius at the trainee's depth). A ball's radius there is its kind's r times
  -- SIZE for the level, never more than CAP sprite radii (Lv1 / Lv2 the sprite's own size, Lv3
  -- twice it, so there is still room to get out of the way); drawn, it grows from FAR of that
  -- as it leaves the balloon, on past the trainee to the cap
  BALL = { SPRITE_R = 0.122, SIZE = { [1] = 1, [2] = 1.25, [3] = 1.6, secret = 1.6 },
           CAP = { [1] = 1, [2] = 1, [3] = 2, secret = 2 }, FAR = 0.35 },
}

-- the guard (L / R held): up while held, at most int(MAX_F x (1 + DEFv x DEF_K)) frames,
-- DEFv = base Def + Sp. Def + 2 x their EVs; dropped (released, or run out) it cannot rise again
-- for COOLDOWN_F; while up the Pokemon moves at MOVE_MULT and cannot shoot; a ball it stops
-- leaves it untouchable for SAFE_F. LEN / COOLDOWN / DEF_BONUS only without the Pokemon's stats.
N.BLOCK = { MAX_F = 20, DEF_K = 0.005, COOLDOWN_F = 30, SAFE_F = 25, MOVE_MULT = 0.5,
  LEN = 0.6, COOLDOWN = 1.5, DEF_BONUS = 0.5 }

-- the trainee stands on a floating stand and moves across and up / down on a plane facing the
-- balloon (the d-pad); Z is its fixed depth, Y_MAX how high it can rise
-- (SPEED was 25% under 1.1 for a steadier stand, the balls' speeds and the lob's flight eased to
-- match; halved 2026-10-23 (Wooble) toward the game's: its stand crosses side to side in ~3.8 s
-- at SPEv 100, the game's speed then x(1 + SPEv x SPE_K) against that)
-- Y_MAX: as high as the sprite stays on screen (its feet 51 px, the drawn 64 px frame at 0.8,
-- below the top: (140 - 51) / 70.5 at the stand's depth)
N.PLAYER = { X_MAX = 0.8, Z = 0.1, Y_MAX = 1.25, SPEED = 0.41, R = 0.12, H = 0.3, SPE_BONUS = 0.4, SPE_K = 0.001, SWIFT_MULT = 1.5,
             HIT_STUN_S = 14 / 30, HIT_SAFE_F = 30 }

-- the top screen's view of the arena (240x160 px): at the trainee's depth (NEAR, z = 0) and the
-- balloon's (FAR, z = 1) a world unit is hw px across and hu px up, and the floor is at y = fy.
-- The balloon is drawn large (a sprite about 140 px wide hovering over the stadium's
-- grass); the trainee's stand floats in front of it.
N.VIEW = { NEAR = { hw = 118, fy = 140, hu = 70 }, FAR = { hw = 120, fy = 140, hu = 75 } }

N.BOT = { GROWTH = 0.02, SCALE_MAX = 1.2, R = 0.32, FLINCH_S = 0.35, CY = 0.45,
          -- a sprite balloon is taller than the round one: it hovers higher, sized so that even
          -- fully grown it stays inside the sky the aim pad reaches (AIM_X across, 0..AIM_Y up)
          SHAPE_CY = 1.04, AIM_X = 1.6, AIM_Y = 2.05,
          RAGE_AT = 2400, CALM_AT = 2400,
          -- the balloon's sway in the game's top-screen pixels (400x240), by level: a loop ax
          -- across and ay up and down every period seconds (measured live, see EVIDENCE); a
          -- goal hit makes it shake for SHAKE_S, SHAKE_PX at the start, fading
          SWAY = { [1] = { ax = 12, ay = 28, period = 4.6 }, [2] = { ax = 9, ay = 14, period = 9 },
                   [3] = { ax = 25, ay = 45, period = 9 }, secret = { ax = 25, ay = 45, period = 9 } },
          SHAKE_S = 3, SHAKE_PX = 12,
          RAGE_CADENCE = 0.6, RAGE_SPEED = 1.3, RAGE_DAMAGE = 1.5,   -- Aegislash past 2400
          CALM_CADENCE = 1.8, CALM_SPEED = 0.8 }                      -- Roserade past 2400

-- fallback colour by primary GBA type id when a species is not in the Bulbapedia table
N.SHOT_TYPE_BY_TYPE = { [13] = "yellow", [10] = "orange", [12] = "green", [6] = "green", [11] = "blue", [15] = "blue" }

N.ITEMS = { WING_EV = 1 }

-- ------- provenance (see the header)
N.EVIDENCE = {
  ["LIMITS.EV_CAP"] = { class = "verified", source = "atwiki pkmnomegaralphas Super Training page; Bulbapedia Effort values", confidence = "high" },
  ["LIMITS.EV_TOTAL"] = { class = "verified", source = "Bulbapedia Effort values", confidence = "high" },
  ["LIMITS.BAG_MAX"] = { class = "verified", source = "the game's code: the rack is 12 one-byte slots (0x30C.. in the training save block, 0x0045EBF0 walks them); the blank bag's drop roll is skipped when it is full (main program 0x007B99FC); Serebii X/Y Super Training", confidence = "high" },
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
  ["GOALS.CHANCE_S"] = { class = "measured", source = "AS text 44:62: red goals disappear after a set amount of time; ORAS Wiki: over 10 seconds; live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: one stood 10.4 s before its first hit and stayed after hits", confidence = "medium" },
  ["GOALS.CHANCE_ODDS"] = { class = "placeholder", source = "AS text 45:84: a red bonus goal needs every white goal blasted first (necessary, not always sufficient); gamepedia.jp", confidence = "low" },
  ["GOALS.CHANCE_EVERY"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: a single goal that takes several hits came after the second group of three each time", confidence = "medium" },
  ["GOALS.GROUP_GAP_S"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: the next group 1.5 s after the last goal of one bursts (2 s once at Lv3)", confidence = "medium" },
  ["GOALS.R"] = { class = "measured", source = "upper.bclyt in a/1/1/4: the goal panes 0..e are 32x32 (target01, big_target); scaled to this view", confidence = "medium" },
  ["GOALS.CHANCE_R"] = { class = "measured", source = "upper.bclyt: the big goal uses the same 32x32 panes", confidence = "medium" },
  ["GOALS.MARKER_R"] = { class = "placeholder", source = "", confidence = "low" },
  ["GOALS.WANDER.SPEED"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: goals stay where they appear and move only with the balloon", confidence = "medium" },
  ["GOALS.WANDER"] = { class = "inferred", source = "AS text 44:64 (goals on arms, wings and other moving bits make aiming harder), 45:87 / 45:99 / 45:104 (fleeing, constantly moving goals); the speeds and ranges are ours", confidence = "low" },
  ["CHARGE.FPS"] = { class = "verified", source = "the game runs Super Training at 30 fps (5400.0 = the 180 s clock)", confidence = "high" },
  ["CHARGE.STAGE_F"] = { class = "verified", source = "DllSparring.cro charge state [r4+0x26c] at 0x2598-0x29ac, frames held [r4+0x274]: cmp #0x32 (stage 1, 0x27a8), cmp #0x42 (stage 2, 0x2844); capture 2026-10-23_16-43-37 yellow 6.5 s, red 7.0 s", confidence = "high" },
  ["CHARGE.FIZZLE_F"] = { class = "verified", source = "DllSparring.cro cmp #0x60 at 0x28e0 (effect 0x41 the smoke, SE 0x1000f2); capture 8-9 s", confidence = "high" },
  ["CHARGE.STUN_F"] = { class = "verified", source = "DllSparring.cro [r4+0x290] = 30 at 0x2934, blocks moving (0x1f94), firing (0x2eec), charging (0x2608)", confidence = "high" },
  ["CHARGE.AFTER_F"] = { class = "verified", source = "DllSparring.cro [r4+0x28c] = 15 after a Charged Shot (0x29a0)", confidence = "high" },
  ["CHARGE.MULT_RISE"] = { class = "verified", source = "DllSparring.cro 0x3140-0x3180: power x (1 + 2 x min((t - 50) / 16, 1)), 2.0 at 0x2a1c; capture +531 = 177 x 3", confidence = "high" },
  ["CHARGE.YELLOW_BURST"] = { class = "verified", source = "atwiki: 7 shots at max charge", confidence = "medium" },
  ["GUTS.CAP"] = { class = "verified", source = "DllSparring.cro 0x1f18-0x1f38: filled only below 0x1f4, clamped to it; the circle's clip frame = the meter (0x1f3c)", confidence = "high" },
  ["GUTS.PER_FRAME"] = { class = "verified", source = "DllSparring.cro 0x5cec-0x5d0c: int(4 x (1 + (DEFv + EV total) x 0.0025)); capture: empty to full in ~1.6 s", confidence = "high" },
  ["GUTS.DEF_K"] = { class = "verified", source = "DllSparring.cro 0x5cec-0x5d0c (DEFv = stat+0x54)", confidence = "high" },
  ["GUTS.START"] = { class = "verified", source = "DllSparring.cro 0x5cd4: the meter starts at 0", confidence = "high" },
  ["GUTS.RATE"] = { class = "placeholder", source = "only without the Pokemon's stats", confidence = "low" },
  ["BLOCK.MAX_F"] = { class = "verified", source = "DllSparring.cro guard state [r4+0x280] 0x23d0-0x2594: up while button 0x100 is held, down at counter [0x298] = stat+0x44 = int(20 x (1 + 0.005 x DEFv)) (0x5e50-0x5e60)", confidence = "high" },
  ["BLOCK.DEF_K"] = { class = "verified", source = "DllSparring.cro 0x5e50-0x5e60 (DEFv = stat+0x54; no bag, no EV total)", confidence = "high" },
  ["BLOCK.COOLDOWN_F"] = { class = "verified", source = "DllSparring.cro state 2: [0x29c] cmp #0x1e at 0x256c, then the button must be let go (0x2578-0x2594)", confidence = "high" },
  ["BLOCK.SAFE_F"] = { class = "verified", source = "DllSparring.cro 0x2a64-0x2b44: a blocked hit gives 25 frames untouchable (and a push back)", confidence = "high" },
  ["BLOCK.MOVE_MULT"] = { class = "verified", source = "DllSparring.cro 0x1fa8-0x1fcc: move speed x0.5 while [0x284] / [0x288] (the guard) are set; firing blocked at 0x25b4", confidence = "high" },
  ["PLAYER.SPE_K"] = { class = "verified", source = "DllSparring.cro stat+0xc = 2 x (1 + SPEv x 0.001) at 0x5c8c-0x5cb4 (no EV total), x1.5 Swiftness at 0x5cb8-0x5ccc; an arc a frame on the stand's sphere, no inertia", confidence = "high" },
  ["SHOT.SPE_K"] = { class = "verified", source = "DllSparring.cro 0x2f84-0x2fcc: shot speed = rec.speed x (1 + SPEv x 0.005), SPEv = stat+0x58 (base Spe + 2 EV_Spe)", confidence = "high" },
  ["SHOT.HP_K"] = { class = "verified", source = "DllSparring.cro 0x2f84-0x2fcc: shot size = rec.size x (1 + HPv x 0.00125), HPv = stat+0x4c (base HP + 2 EV_HP); x1.5 Big-Shot", confidence = "high" },
  ["SHOT.STAT_REF"] = { class = "inferred", source = "ours: the stat value at which our shot table's absolute speeds and sizes hold", confidence = "low" },
  ["DAMAGE.BIT_SHARE"] = { class = "placeholder", source = "ours: a bitbot's shot against a ball (the game's other attack classes not traced; one adds a flat 4 unblockable at 0x143c4)", confidence = "low" },
  ["PLAYER.HIT_SAFE_F"] = { class = "verified", source = "DllSparring.cro 0x2c14-0x2c2c: after an unblocked hit [0x1d4] = 30 frames untouchable, a knockback of 2 units back over 14 frames ([0x1ec], no moving or charging)", confidence = "high" },
  ["DAMAGE.LOSS_K"] = { class = "verified", source = "DllSparring.cro 0x5c54-0x5c80: stat+0 = 1 / (1 + (HPv + EV total) x 0.005), / 1.5 Toughen Up; applied to a hit's loss at 0x2b48-0x2b8c", confidence = "high" },
  ["SHOT.cost"] = { class = "verified", source = "DllSparring.cro table A 0x18234 / B 0x1833C cost ints (180, 10/50, 180, 300, 300, 0) over the meter's 500; a cost above the meter fires the weak shot free (0x2f34, 0x2f48)", confidence = "high" },
  ["POINTS.EV_STEPS"] = { class = "verified", source = "DllSparring.cro stat+0x5c at 0x5ed4-0x5ff8: (Atk + SpA bases) div 5 + (EVs) div 4 + 0.5 min(X, 50) + 0.2 clamp(X-50, 0, 50) + 0.1 clamp(X-100, 0, 410), x1.5 Strength; a hit's score is the shot's power (0xa5a4, 0xf694)", confidence = "high" },
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
  ["BOT.SCALE_MAX"] = { class = "placeholder", source = "Wooble (2026-10-12): 1.2, so the large balloon of this view stays on the top screen; the game's own cap is not measured", confidence = "low" },
  ["BOT.R"] = { class = "placeholder", source = "", confidence = "low" },
  ["BOT.SHAPE_CY"] = { class = "placeholder", source = "ours: the sprite balloon's centre, so it fits the visible sky (y 0..2.09 at the bot's depth)", confidence = "low" },
  ["BOT.AIM_X"] = { class = "placeholder", source = "ours: the aim reach across with a sprite balloon (the sky at the bot's depth is +-1.71)", confidence = "low" },
  ["BOT.AIM_Y"] = { class = "placeholder", source = "ours: the aim reach up with a sprite balloon", confidence = "low" },
  ["BOT.FLINCH_S"] = { class = "placeholder", source = "atwiki: the balloon flinches on a goal", confidence = "low" },
  ["VIEW"] = { class = "placeholder", source = "ours: the layout of Wooble's concept for the top screen (2026-10-12)", confidence = "low" },
  ["ATTACK.BALL"] = { class = "inferred", source = "Wooble (2026-10-12): the attacks are the game's soccer ball, bigger at higher levels (up to the sprite's size at Lv1 / Lv2, about twice at Lv3), growing as they come at the trainee; the multipliers are ours", confidence = "low" },
  ["ATTACK.lob"] = { class = "inferred", source = "Wooble (2026-10-12): balls lobbed up off screen come down on the trainee, a red shadow marking where; flight and height are ours", confidence = "low" },
  ["BOT.SWAY"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: Lv1 a loop of +-12 x +-28 px every 4.6 s, Lv2 +-9 x +-14 px slowly, Lv3 swings of up to 120 px (the secret courses take Lv3's until measured)", confidence = "medium" },
  ["BOT.SHAKE_S"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: after a goal the others jitter +-10-20 px for 3-5 s", confidence = "medium" },
  ["BOT.SHAKE_PX"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st", confidence = "medium" },
  ["PLAYER.Y_MAX"] = { class = "inferred", source = "the game: the trainee's stand moves up and down as well as across (Wooble)", confidence = "medium" },
  ["PLAYER.Z"] = { class = "placeholder", source = "ours: the stand's depth", confidence = "low" },
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
