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

-- the changeover between a course's balloons (Wooble's capture s4/1, The Troubles Keep on
-- Coming?!; seconds from the last hit): the beaten one collapses onto the grass over DEFLATE
-- and lies there as a puddle, the screen fades to black over FADE_OUT and back over FADE_IN with
-- the next lying flat at SWAP_S, 30 s go onto the clock at BONUS_S, it inflates where it lies
-- over INFLATE, its name shows over NAME, and play (goals, its first warning) at PLAY_S; the
-- clock stands still throughout
N.BETWEEN = { DEFLATE = { 0.2, 1.3 }, FADE_OUT = { 3.7, 3.9 }, SWAP_S = 4.5, FADE_IN = { 4.6, 4.8 },
  BONUS_S = 5.8, INFLATE = { 6.1, 8.2 }, NAME = { 8.8, 10.1 }, PLAY_S = 10.2 }

N.GOALS = {
  YELLOW_AT = 7.7,    -- a white goal turns orange
  GONE_AT = 12.2,     -- and vanishes, fading over its last FADE_S
  FADE_S = 1.5,
  CHANCE_S = 15,      -- a red Chance Goal stays this long without a score
  CHANCE_ODDS = 0.5,  -- chance it appears once a group is cleared (when CHANCE_EVERY is off)
  CHANCE_EVERY = 2,   -- the red goal comes after every second cleared group
  GROUP_GAP_S = 0.9,
  CHANCE_DELAY_S = 0.5,  -- a cleared group's red goal comes this long after (the balloon frozen)
  EXPIRE_GAP_S = 0.95,  -- after a group that ran out unscored
  MIN_GAP_S = 0.4,
  -- a group's timer by course (Wooble's Lv1 / Lv2 captures): white for `white` s, then orange,
  -- gone at `gone`, and a group that ran out is followed on `cycle` from when it came
  TIMER = {
    default = { white = 7.7, gone = 12.2, cycle = 13.2 },
    lv2_hp = { white = 9.55, gone = 13.4, cycle = 16.0 },
    lv2_atk = { white = 9.6, gone = 14.0, cycle = 16.05 },
    lv2_def = { white = 7.8, gone = 12.3, cycle = 13.2 },
    lv2_spa = { white = 9.5, gone = 15.3, cycle = 15.9 },
    lv2_spd = { white = 5.1, gone = 8.1, cycle = 9.0 },
    lv2_spe = { white = 5.05, gone = 8.1, cycle = 9.1 },
    lv3_hp = { white = 9.6, gone = 15.3, cycle = 16.1 },
    lv3_atk = { white = 9.5, gone = 15.2, cycle = 16.1 },
    lv3_def = { white = 7.8, gone = 12.3, cycle = 13.2 },
    lv3_spa = { white = 9.4, gone = 15.2, cycle = 16.0 },
    lv3_spd = { white = 3.3, gone = 5.3, cycle = 6.13 },
    lv3_spe = { white = 3.3, gone = 4.5, cycle = 6.05 },
  },
  -- goal radius in world units at the balloon's depth: the game's goals show 26.5 px across of
  -- its 400x240 top screen (Wooble's Lv1 captures; the panes are 32x32 with their glow), 13.25
  -- px of radius = 7.95 px here = 0.066 units (N.VIEW.FAR.hw 120)
  R = 0.066,
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
    MOTION_SPEED = 0, ROAM_SPEED = 0.55, FLEE_SPEED = 1.1, MARKER_SPEED = 0.6,
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
  SPE_SPEED_BONUS = 3.0,  -- x4 at 252 Speed EVs (only without the Pokemon's stats)
  -- the game's: speed x (1 + SPEv x SPE_K), SPEv = base Speed + 2 x its EVs; size x (1 + HPv x
  -- HP_K), HPv = base HP + 2 x its EVs. Our shot table's speeds and sizes are those at
  -- SPEv / HPv = STAT_REF (the game's scale is not ours), so the factors are taken against it.
  -- Every shot's speed is scaled by SPEED_SCALE so a fully Speed-trained shot crosses in ~0.25 s
  -- as the game's does (Wooble 2026-10-23), the game's factor kept (SPE_EXP 1, x3 from none to
  -- full Speed): an untrained Torchic's ~0.76 s, a fully trained one's ~0.25 s
  SPE_EXP = 1,
  SPEED_SCALE = 1.31,
  -- the least time between two shots (a tap in it fires nothing): no machine-gunning taps
  REFIRE_S = 0.25,
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
  -- the game's attack scripts (data/training_attacks.lua, run by src/training/sim.lua): its units
  -- to ours - the trainee moves on a sphere 240 out from the balloon, 30 degrees either side
  -- (+-120 units across) and up to 45 degrees (170 units) up; our stand +-0.8 across, 1.25 up and
  -- 0.9 deep - so UNIT for x / y (and sizes), DEPTH_UNIT along the flight; FIRE_KEY_U the units
  -- a pose takes to its fire key (the step's -1; the game reads it from the pose's animation,
  -- at most 90); a bitbot fires every BIT_EVERY_F frames at SPEED units a frame, radius R
  -- SIZE_UNIT: a projectile's size (the game draws them in 3D, near the camera, so they look far
  -- bigger than the field's scale): its normal ball (4.8) at our ball's 0.06, a giant (27) 0.34
  -- (calibrated on Wooble's six Lv1 captures, 2026-10-23: a ball takes ~1.45 s from launch to
  -- the trainee, so the flight is DEPTH units; a wait step lasts its recovery plus the idle pose's
  -- WAIT_POSE_U; a throw leaves FIRE_KEY_U after its wind-up starts (FIRE_KEY_COURSE: a pose that
  -- runs longer); yaw / pitch are ANGLE_DEG degrees a unit (the spread balls fly well clear))
  GAME = { UNIT = 0.8 / 120, SIZE_UNIT = 0.06 / 4.8,
    -- a game ball as drawn (the camera's perspective): PX_PER_UNIT screen units of radius per
    -- unit of its size at launch, GROW times that at the trainee - where that size is also its
    -- hitbox (SIZE_UNIT is the bitbots' shots only)
    DRAWN = { PX_PER_UNIT = 1.06, GROW = 4.5 },
    -- a wide or tall ball's long side this much longer than the game's (drawn and hit alike)
    STRETCH = 1.5,
    DEPTH = 196, DEPTH_UNIT = 0.9 / 196, FIRE_KEY_U = 22,
    FIRE_KEY_COURSE = { lv1_hp = 42 }, WAIT_POSE_U = { [0] = 50, [1] = 70, [2] = 55 }, ANGLE_DEG = 6,
    -- each balloon's own animation lengths (Wooble's Lv1 / Lv2 captures; the poses are its
    -- model's): `pose` the idle a wait plays out (units past its recovery), `key` the wind-up to
    -- the throw, `shieldKey` the wind-up to a shield
    COURSE = {
      lv1_hp = { pose = { [0] = 61 }, key = 42 },
      lv1_atk = { pose = { [0] = 55 }, key = 20 },
      lv1_def = { pose = { [0] = 52, [1] = 65 }, key = 24 },
      lv1_spa = { pose = { [0] = 39 }, key = 21 },
      lv1_spd = { pose = { [1] = 91 }, key = 22 },
      lv1_spe = { pose = { [0] = 49 }, key = 20 },
      lv2_hp = { pose = { [0] = 81 }, key = 21 },
      lv2_atk = { pose = { [0] = 42 }, key = 21 },
      lv2_def = { pose = { [2] = 53 }, key = 35, shieldKey = 18 },
      lv2_spa = { pose = { [0] = 62 }, key = 22 },
      lv2_spd = { key = 20 },
      lv2_spe = { pose = { [0] = 41, [1] = 49 }, key = 20 },
      -- Lv3 (the s3 captures)
      lv3_hp = { pose = { [2] = 100 }, key = 20 },
      lv3_atk = { pose = { [0] = 60 }, key = 20 },
      lv3_def = { pose = { [0] = 45, [2] = 110 }, key = 42, shieldKey = 22 },
      lv3_spa = { pose = { [0] = 82 }, key = 22 },
      lv3_spd = { pose = { [2] = 64 }, key = 25 },
      lv3_spe = { pose = { [0] = 63, [2] = 57 }, key = 21 },
    },
    -- bitbots by course: spots across (world units at their depth) and each one's fire interval
    -- in frames (the s2 / s3 captures, re-read 2026-10-24: the same layout on all three courses,
    -- left / middle / right at x 96 / 200 / 304 of 400; the first volley together, then the
    -- middle one, nearer the camera, every ~94 and the sides every ~105 - Tentacruel's too)
    BITS = {
      lv2_spd = { x = { -0.53, 0, 0.53 }, every = { 105, 94, 105 } },
      lv3_hp = { x = { -0.53, 0, 0.53 }, every = { 105, 94, 105 } },
      lv3_spd = { x = { -0.52, 0.04, 0.52 }, every = { 105, 94, 105 } },
    },
    -- bitbots (Wooble's Tentacruel capture): each fires every BIT_EVERY_F frames, all three
    -- together, the first BIT_FIRST_S after they appear; each circles a loop BIT_LOOP_R across
    -- every BIT_LOOP_S, about its spot in BIT_X
    BIT_EVERY_F = 103, BIT_FIRST_S = 1.2, BIT_LOOP_S = 6, BIT_LOOP_R = 0.18, BIT_X = { -0.55, -0.2, 0.35 },
    BIT_SPEED = 3.5, BIT_R = 2.4, MAX_BITS = 3 },
  small = { speed = 1.19, r = 0.06, gap = 0.35 },
  big = { speed = 0.77, r = 0.16 },
  ring = { speed = 0.94, n = 8, r = 0.06, spin = 1.2, ring_r = 0.45 },
  homing = { speed = 0.77, r = 0.07, turn = 1.2 },
  cross = { speed = 1.02, r = 0.06, arms = 4, arm_len = 0.35 },
  wave_tall = { speed = 0.85, cols = 4, gap_w = 0.3 },
  wave_wide = { speed = 0.85, w = 1.4 },
  bit = { z = 0.7, r = 0.1, hp = 3, fire_every = 2.5, y = 0.5, regen_s = 12 },
  barrier = { max_s = 25 },
  -- homing (Wooble 2026-10-23): a round homing ball is dodged by moving at all in its last
  -- LOCK_S; a wide one follows across to the end (dodge by moving up or down), a tall one up and
  -- down (dodge left or right). An axis pulling with k <= STRONG_K follows to the end; a locked
  -- axis hits only if the trainee is within DODGE of where it was when it locked
  HOMING = { STRONG_K = 4, SPEED = 0.25, HOLD_S = 0.5 },
  -- the balls' own motion (flight, wave, homing, bitbot shots) this much faster than the game's;
  -- HOMING's SPEED / HOLD_S are at 1 and scale with it
  TEMPO = 1.5,
  -- a balloon's shield (Wooble's Graveler capture): its target fades in over FADE_IN_S (not
  -- hittable until then) and circles the balloon ORBIT_R world units out about a point ORBIT_UP
  -- above its middle, from START_DEG on screen (0 right, 90 down) anticlockwise at DEG_S
  SHIELD = { FADE_IN_S = 1.2, TAIL_S = 1.0, ORBIT_R = 0.21, ORBIT_UP = 0.04, START_DEG = 123, DEG_S = 29.3,
    -- a course's own orbit (Golem: r 44 px, 31.1 deg/s from the top)
    COURSE = { lv3_def = { ORBIT_R = 0.22, START_DEG = -97, DEG_S = 31.1 } } },
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
-- A stopped ball bounces off the shield, which shatters BREAK_F frames later (Wooble's capture
-- 2026-10-23_17-28-44: blocked at 3.4 s, shattered at 4.0); held to its length it shatters too
-- (12.1 -> 13.6 s); the pieces fly for SHATTER_S.
N.BLOCK = { MAX_F = 20, DEF_K = 0.005, COOLDOWN_F = 30, SAFE_F = 25, MOVE_MULT = 0.5, BREAK_F = 18, SHATTER_S = 0.6,
  LEN = 0.6, COOLDOWN = 1.5, DEF_BONUS = 0.5 }

-- the trainee stands on a floating stand and moves across and up / down on a plane facing the
-- balloon (the d-pad); Z is its fixed depth, Y_MAX how high it can rise
-- (SPEED was 25% under 1.1 for a steadier stand, the balls' speeds and the lob's flight eased to
-- match; halved 2026-10-23 (Wooble) toward the game's: its stand crosses side to side in ~3.8 s
-- at SPEv 100, the game's speed then x(1 + SPEv x SPE_K) against that)
-- Y_MAX: as high as the sprite stays on screen (its feet 51 px, the drawn 64 px frame at 0.8,
-- below the top: (140 - 51) / 70.5 at the stand's depth)
N.PLAYER = { X_MAX = 0.8, Z = 0.1, Y_MAX = 1.25, SPEED = 0.72, R = 0.12, H = 0.3, SPE_BONUS = 0.4, SPE_K = 0.001, SWIFT_MULT = 1.5,
             HIT_STUN_S = 14 / 30, HIT_SAFE_F = 30,
             -- 3D SUPER TRAINING's forward / back (the game's): the trainee's distance from the
             -- balloon in steps (game units; it starts on STEP0), closing at DIST_SPEED units a
             -- frame (30 fps; half while guarding); the 2D view's depth (1 - Z) is DIST[STEP0]
             DIST = { 180, 240, 300 }, DIST_STEP0 = 2, DIST_SPEED = 2 }

-- the top screen's view of the arena (240x160 px): at the trainee's depth (NEAR, z = 0) and the
-- balloon's (FAR, z = 1) a world unit is hw px across and hu px up, and the floor is at y = fy.
-- The balloon is drawn large (a sprite about 140 px wide hovering over the stadium's
-- grass); the trainee's stand floats in front of it.
-- 3D SUPER TRAINING plays in the game's own space, 1:1 (DllSparring.cro; units the game's, the
-- balloon at the origin, y up, 30 frames a second), only with the option on (the 2D view keeps
-- its tuning above):
--   the trainee on a sphere about the balloon: elevation EL, azimuth AZ (90 in front), the
--   radius a distance step (PLAYER.DIST), moving SPEED x (1 + Speed x SPE_K) units of arc a frame
--   (x1.5 Swiftness, x0.5 guarding); its body ACTOR_IN inside that point, ACTOR_SIDE units of arc
--   to the side and ACTOR_UP above the sphere's level; its hit shape a sphere of HIT_R; the
--   camera EYE_UP over the sphere point (the code aims it at (0, EYE_UP, 0); the capture fits LOOK_Y)
--   an enemy ball: its record's speed a frame, its semi-axes its hitbox (an ellipsoid touching
--   the trainee's sphere hits); gone DESPAWN from where it left; homing (trainee - ball) x t / (t
--   + k) on x and y, t its frames
--   a goal: a box of half GOAL_HALF (GOAL_HALF_BIG for the red); a shot: the table SHOT (speed a
--   frame, size) x (1 + Speed x 0.005), x (1 + HP x 0.00125), flying as a lob LOB over its line
--   the balloon: its phase's scale (attack data `scale`), growing to GROW x as it fills, swaying
--   SWAY (x amplitude, degrees a frame, y amplitude, degrees a frame) when its phase says
--   ours (the sprites standing in for the 3D models): BAL_SIZE the balloon sprite's mean side
--   at scale 1, its feet on the grass (GROUND) or, with a midY, its middle midY x scale above it; TRAINEE_SIZE every trainee sprite's sqrt(w x h) and BOARD_W its board's width; BIT_R a
--   bitbot's size; PLAY_FOVY / LOOK_Y the play camera's field and the height it looks at (fitted to
--   a capture: e77's intro camera has the same 37.85)
N.GAME3D = { EL = { 0, 45 }, AZ = { 60, 120 }, SPEED = 2, SPE_K = 0.001, ACTOR_IN = 11.5, ACTOR_SIDE = 2.5,
  ACTOR_UP = 3.5, HIT_R = 3, EYE_UP = 4.5, DESPAWN = 300, GOAL_HALF = 10, GOAL_HALF_BIG = 15, LOB = 6,
  SHOT = { black = { 3.6, 1.0 }, yellow = { 3.6, 0.7 }, orange = { 3.6, 2.0 }, green = { 2.6, 1.5 },
    blue = { 5.2, 0.85 }, weak = { 3.6, 0.7 } },
  SHOT_CHARGED = { black = { 3.0, 1.0 }, yellow = { 3.0, 0.7 }, orange = { 3.0, 2.0 }, green = { 2.1, 1.5 },
    blue = { 5.2, 0.85 }, weak = { 3.0, 0.7 } },
  SHOT_SPE_K = 0.005, SHOT_HP_K = 0.00125, GROW = 1.5, SWAY = { 12, 2, 6, 1 },
  BAL_SIZE = 105, GROUND = -6.7, TRAINEE_SIZE = 1.8, BOARD_W = 3.6, RIDE_UP = 0.75, BIT_R = 8.3, BIT_SPEED = 3.5, BIT_SHOT_R = 2.8,
  -- the bitbots where the game has them: left / middle / right spots (x, y, z), each circling a
  -- loop BIT_LOOP_R round it facing the camera
  BIT_SPOTS = { { -44.4, 28, 90 }, { 0, 28, 120 }, { 44.4, 28, 90 } }, BIT_LOOP_R = 16, PLAY_FOVY = 37.81,
  LOOK_Y = 35, EDGE_OFF = 2.5, EDGE_TURN = 9, EDGE_TILT = 15,
  -- each balloon as the captures show it at the start (the middle distance, score 0), by National
  -- Dex number: { width, height, middle y } in the 3DS's 400x240 px
  SIZE_PX = {
    [610] = { 71, 105, 119.5 },    -- Axew (lv1_atk)
    [74] = { 111, 53, 122.5 },     -- Geodude (lv1_def)
    [81] = { 106, 63, 90.5 },      -- Magnemite (lv1_spa)
    [714] = { 63.5, 94.5, 94 },    -- Noibat (lv1_spe)
    [72] = { 52.5, 93, 110.5 },    -- Tentacool (lv1_spd)
    [320] = { 137, 79, 117.5 },    -- Wailmer (lv1_hp)
    [142] = { 113, 88, 101 },      -- Aerodactyl (lv2_spe)
    [611] = { 134, 100, 121 },     -- Fraxure (lv2_atk)
    [75] = { 146.5, 80, 131 },     -- Graveler (lv2_def)
    [82] = { 128, 67, 90.5 },      -- Magneton (lv2_spa)
    [369] = { 44, 95, 108 },       -- Relicanth (lv2_hp)
    [73] = { 88, 106, 106 },       -- Tentacruel (lv2_spd)
    [691] = { 74, 83, 90.5 },      -- Dragalge (lv3_spd)
    [76] = { 136, 106, 119 },      -- Golem (lv3_def)
    [612] = { 83, 109, 117.5 },    -- Haxorus (lv3_atk)
    [462] = { 134, 94, 116 },      -- Magnezone (lv3_spa)
    [715] = { 145, 103, 111.5 },   -- Noivern (lv3_spe)
    [321] = { 84, 82, 122 },       -- Wailord (lv3_hp)
    [699] = { 54, 132, 106 },      -- Aurorus (secret_01)
    [3] = { 148, 103, 120 },       -- Venusaur (secret_02)
  } }

N.VIEW = { NEAR = { hw = 118, fy = 140, hu = 70 }, FAR = { hw = 120, fy = 140, hu = 75 } }

N.BOT = { GROWTH = 0.02, SCALE_MAX = 1.2, GROW_K = 0.56, GROW_EASE = 10, SHAKE_HZ = 2, R = 0.32, FLINCH_S = 0.35, CY = 0.45,
          -- a sprite balloon is taller than the round one: it hovers higher, sized so that even
          -- fully grown it stays inside the sky the aim pad reaches (AIM_X across, 0..AIM_Y up)
          SHAPE_CY = 1.04, AIM_X = 1.6, AIM_Y = 2.05,
          -- grown, a balloon's top stays under SKY_TOP and its feet above FEET_MIN (world units at
          -- its depth; the top screen's top is 1.87 there): a tall one sinks and grows less
          SKY_TOP = 1.76, FEET_MIN = 0.1,
          RAGE_AT = 2400, CALM_AT = 2400,
          -- the balloon's sway in the game's top-screen pixels (400x240), by level: a loop ax
          -- across and ay up and down every period seconds; a goal hit makes it shake for
          -- SHAKE_S, SHAKE_PX x the level's SHAKE_SCALE at the start, fading. Lv3 / secret as
          -- measured live; Lv1 / Lv2 ramp up to it (see EVIDENCE)
          SWAY = { [1] = { ax = 0.5, ay = 5, period = 3.5 }, [2] = { ax = 1.5, ay = 2.5, period = 4 },
                   [3] = { ax = 25, ay = 45, period = 9 }, secret = { ax = 25, ay = 45, period = 9 } },
          SHAKE_S = 0.7, SHAKE_PX = 9,
          SHAKE_SCALE = { [1] = 1, [2] = 1, [3] = 1, secret = 1 },
          -- a throw (Wooble's Lv1 captures): a dip of DIP_PX through the first DIP_AT of the
          -- wind-up, up to RISE_PX above its place as the ball leaves, held HOLD_S, then back
          WINDUP = { DIP_PX = 10, RISE_PX = 8, DIP_AT = 0.65, HOLD_S = 1.4 },
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
  ["CLOCK.EXTRA_BOT_S"] = { class = "verified", source = "Bulbapedia; atwiki; Wooble's capture s4/1: a +30 rises into the clock (2:18 -> 2:48) during the changeover, not a reset", confidence = "high" },
  ["BETWEEN"] = { class = "measured", source = "Wooble's capture s4/1 (secret_01, 10 fps) 2026-10-23: last hit 42.2 s, Aurorus collapses 42.4-43.5 (puffs), a flat puddle to 45.9, fade 45.9-46.1, black to 46.7, fade in 46.8-47.0 with Tyrantrum lying flat, +30 at 48.0, inflating where it lies 48.3-50.4, its name 51.0-52.3, aura and goals 52.4; the clock frozen 42.2-52.4; the score 0 / the same target", confidence = "high" },
  ["CLOCK.COUNTDOWN_S"] = { class = "placeholder", source = "", confidence = "low" },
  ["CLOCK.TARGET"] = { class = "verified", source = "pente.koro-pokemon.com/xy/supatore-list (target records); ORAS Wiki", confidence = "high" },
  ["GOALS.YELLOW_AT"] = { class = "measured", source = "Wooble's Lv1 captures 2026-10-23 (all six, unscored groups): white 7.6-7.9 s, then orange; the ORAS Wiki's 8 s", confidence = "high" },
  ["GOALS.GONE_AT"] = { class = "measured", source = "Wooble's Lv1 captures 2026-10-23: orange 3.0 s, a see-through fade 1.5 s, spun out at ~12.2-12.4 s; the ORAS Wiki's 12 s", confidence = "high" },
  ["GOALS.FADE_S"] = { class = "measured", source = "Wooble's Lv1 captures 2026-10-23: the faint orange before a goal goes, ~1.5 s (Wailmer, Geodude, Magnemite; Noibat ~1.1)", confidence = "medium" },
  ["GOALS.TIMER"] = { class = "measured", source = "Wooble's Lv1 / Lv2 captures 2026-10-23 (agents' frame reads, 10 fps): Lv1 all six white 7.6-7.9 / gone ~12.2 / every 13.2 s; Lv3 (s3): Wailord 9.6 / 15.3 / 16.1, Haxorus 9.5 / 15.2 / 16.1, Golem 7.8 / 12.3 / 13.2 (held under its shield), Magnezone 9.4 / 15.2 / ~16, Dragalge 3.3 / 5.3 / 6.13, Noivern 3.3 / 4.5 / 6.05 (one goal at a time); Relicanth 9.55 / 13.4 / 16.0, Fraxure 9.6 / ~14 / 16.05, Graveler 7.8 / ~12.3 / 13.2 (its goals hidden and their timer held under its shield), Magneton 9.5 / 15.3 / 15.9, Tentacruel 5.1 / 8.1 / 9.0, Aerodactyl 5.05 / 8.1 / 9.1", confidence = "high" },
  ["GOALS.MIN_GAP_S"] = { class = "placeholder", source = "ours: the least gap after a group runs out", confidence = "low" },
  ["GOALS.EXPIRE_GAP_S"] = { class = "measured", source = "Wooble's Lv1 captures 2026-10-23: a group that ran out is followed 0.7-1.0 s later (new groups every 13.0-13.2 s; Noibat 1.4)", confidence = "medium" },
  ["GOALS.CHANCE_S"] = { class = "measured", source = "AS text 44:62: red goals disappear after a set amount of time; ORAS Wiki: over 10 seconds; live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: one stood 10.4 s before its first hit and stayed after hits", confidence = "medium" },
  ["GOALS.CHANCE_ODDS"] = { class = "placeholder", source = "AS text 45:84: a red bonus goal needs every white goal blasted first (necessary, not always sufficient); gamepedia.jp", confidence = "low" },
  ["GOALS.CHANCE_EVERY"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: a single goal that takes several hits came after the second group of three each time", confidence = "medium" },
  ["GOALS.CHANCE_DELAY_S"] = { class = "measured", source = "Wooble's magneton-2 capture: the red goal fades in 0.5 s after the clearing hit (settled at 0.7), the balloon holding its pose and puffing air from both sides ~1.4 s; it took two hits of +177 each (a plain goal's)", confidence = "medium" },
  ["GOALS.GROUP_GAP_S"] = { class = "measured", source = "Wooble's magneton-2 capture: the next group 0.9 s after a cleared one's last hit; earlier live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: the next group 1.5 s after the last goal of one bursts (2 s once at Lv3)", confidence = "medium" },
  ["GOALS.R"] = { class = "measured", source = "Wooble's Lv1 captures 2026-10-23: goals 25.5-27 px across on the 400x240 top screen in all six (upper.bclyt's panes are 32x32 with their glow); scaled to this view", confidence = "high" },
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
  ["BLOCK.BREAK_F"] = { class = "measured", source = "capture 2026-10-23_17-28-44 (10 fps): the ball bounces off at 3.4 s, the shield shatters at 4.0 s", confidence = "medium" },
  ["BLOCK.SHATTER_S"] = { class = "measured", source = "capture 2026-10-23_17-28-44: the flash and pieces fade over ~0.6 s (4.0 -> 4.6, 13.6 -> 14.2)", confidence = "medium" },
  ["BLOCK.MAX_F"] = { class = "verified", source = "DllSparring.cro guard state [r4+0x280] 0x23d0-0x2594: up while button 0x100 is held, down at counter [0x298] = stat+0x44 = int(20 x (1 + 0.005 x DEFv)) (0x5e50-0x5e60)", confidence = "high" },
  ["BLOCK.DEF_K"] = { class = "verified", source = "DllSparring.cro 0x5e50-0x5e60 (DEFv = stat+0x54; no bag, no EV total)", confidence = "high" },
  ["BLOCK.COOLDOWN_F"] = { class = "verified", source = "DllSparring.cro state 2: [0x29c] cmp #0x1e at 0x256c, then the button must be let go (0x2578-0x2594)", confidence = "high" },
  ["BLOCK.SAFE_F"] = { class = "verified", source = "DllSparring.cro 0x2a64-0x2b44: a blocked hit gives 25 frames untouchable (and a push back)", confidence = "high" },
  ["BLOCK.MOVE_MULT"] = { class = "verified", source = "DllSparring.cro 0x1fa8-0x1fcc: move speed x0.5 while [0x284] / [0x288] (the guard) are set; firing blocked at 0x25b4", confidence = "high" },
  ["PLAYER.SPE_K"] = { class = "verified", source = "DllSparring.cro stat+0xc = 2 x (1 + SPEv x 0.001) at 0x5c8c-0x5cb4 (no EV total), x1.5 Swiftness at 0x5cb8-0x5ccc; an arc a frame on the stand's sphere, no inertia", confidence = "high" },
  ["SHOT.SPE_EXP"] = { class = "verified", source = "1: the game's Speed factor as it is (DllSparring.cro 0x2f84-0x2fcc); the exponent stays to sharpen it if wanted", confidence = "high" },
  ["SHOT.REFIRE_S"] = { class = "inferred", source = "Wooble 2026-10-24: a delay so rapid taps cannot fire like a machine gun (the weak shot is free when the meter is short); the game's own gap between plain shots is not known (ours)", confidence = "medium" },
  ["SHOT.SPEED_SCALE"] = { class = "measured", source = "Wooble 2026-10-23, the game: a fully Speed-trained shot takes ~0.25 s to reach the target from the farthest point; x1.31 makes Torchic's at 252 Speed EVs 0.25 s (ours crosses the 0.9 depth at vz, whatever the angle)", confidence = "medium" },
  ["SHOT.SPE_K"] = { class = "verified", source = "DllSparring.cro 0x2f84-0x2fcc: shot speed = rec.speed x (1 + SPEv x 0.005), SPEv = stat+0x58 (base Spe + 2 EV_Spe)", confidence = "high" },
  ["SHOT.HP_K"] = { class = "verified", source = "DllSparring.cro 0x2f84-0x2fcc: shot size = rec.size x (1 + HPv x 0.00125), HPv = stat+0x4c (base HP + 2 EV_HP); x1.5 Big-Shot", confidence = "high" },
  ["SHOT.STAT_REF"] = { class = "inferred", source = "ours: the stat value at which our shot table's absolute speeds and sizes hold", confidence = "low" },
  ["ATTACK.GAME"] = { class = "inferred", source = "DllSparring.cro: the trainee on a sphere of radius 240 (0x6fbc), azimuth 60..120, elevation 0..45 (0x2004-0x2098); the scale to our stand is ours; the pose's own fire key is at most 90 units (0xa96c). Calibrated on Wooble's Lv1 captures 2026-10-23 (Wailmer, Axew, Geodude, Magnemite, Tentacool, Noibat; agents' frame reads at 10 fps): launch -> trainee 1.4-1.5 s (DEPTH 196 at speed 4.5), Magnemite's homing 2.0 s; wind-up start -> ball ~1.3-1.6 s at rate 0.5, 2.7-2.9 s at 0.25 (FIRE_KEY_U 22), Wailmer's 2.8 s (42); the first wind-up / aura 5.6-7.1 s in and the loops (Wailmer 20 s, Geodude 11.2 + 19.4 s, Axew 5.9 / 5.5 s apart, Magnemite 8.4 s steps, Noibat 13.1 s) fit wait = recover + 45 (pose 0) / + 80 (pose 1) within ~1 s; the spread volleys (Axew's rings of 8, Geodude's diamond, Noibat's 4 strays) fly off screen past the trainee, ~6 degrees a yaw / pitch unit; bits at 3.5 a frame, radius 2.4 (a/2/1/2/4 #0, 0x9fcc), at most 3 (0xbb4c); Tentacruel's capture (s2): the three appear together, first fire 1.2 s later, then all together every ~3.45 s (103 frames; the code's 32 was not their rate), each on its own clockwise loop every 6.0 s (~40 px across), at about -128 / -56 / +75 px across from the balloon; their shots 80 against its 120 (the bit record), -19 against -29 seen", confidence = "medium" },
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
  ["GAME3D"] = { class = "verified", source = "DllSparring.cro (research 2026-10-24): the sphere (0xadcc), limits el 0..45 / az 60..120 (0x21f0-0x2200), speed stat+0xc = 2 x (1 + SPEv x 0.001) a frame, x0.5 guarding (0x21e0); the trainee actor at sphere(el, az + 2.5 units of arc, r - 11.5) + (0, 3.5, 0) (0xcaf0); its hit sphere radius 3 at every distance (table 0x18228); the camera at sphere(el, az, r) + (0, 4.5, 0) looking at (0, 4.5, 0) (0x6ed4); the enemy ball's hit: the trainee sphere's nearest point inside the ball's ellipsoid of its record's semi-axes (0x15900-0x15ac0), base += normalize(target - start) x speed a frame (0x163f4 / 0x15624), gone at 300 from its start (0x15ad4), homing (trainee - base) x t / (t + k) (0x155ec); goals boxes of half 10 / 15 (0xdf68 / 0xdf6c); shots: tables 0x18234 / 0x1833c (speed, size), x (1 + SPEv x 0.005), x (1 + HPv x 0.00125), a lob 6 over its line (0x16488); the balloon's phase scale a/1/1/8 +4, growing to 1.5x (0x122e4), sway (12 sin 2t, 6 sin t) degrees a frame (0x11b58)", confidence = "high" },
  ["GAME3D.BAL_SIZE"] = { class = "measured", source = "ours (the balloon's 3D model stands in as its sprite): the sprite's mean side sqrt(w x h) at phase scale 1, fitted to the capture magneton-2 (Magneton, scale 0.7: the model 93 x 57 of the 240x160 frame at 240 out with the play camera, sqrt 73 frame = 73.5 game units); a floating balloon's middle is its phase's midY x scale above the grass (Magneton: 75 x 0.7 = 52.5, measured 53.1)", confidence = "low" },
    ["GAME3D.TRAINEE_SIZE"] = { class = "measured", source = "ours (the trainee's sprite for its model, every Pokemon the same size, Wooble 2026-10-24): the captures' Latias at the middle, 68 x 46 of 400x240 px (sqrt 55.9 = 37.3 frame units at ~11.5 out: 1.8 game units); the game scales most trainee models 0.015 (a/1/3/0)", confidence = "medium" },
  ["GAME3D.BOARD_W"] = { class = "measured", source = "the board under it as wide as the game's stand in the captures (horn tip to horn tip 111 of 400 px: 3.6 game units)", confidence = "medium" },
  ["GAME3D.RIDE_UP"] = { class = "measured", source = "the trainee rides a ball on the stand: its feet over the actor point (the stand's top) by the ball - the captures' Latias bottom at y 169 of 240 against the actor point's ~193 (24 px = 0.75 game units at 11.5 out)", confidence = "medium" },
  ["GAME3D.BIT_SPOTS"] = { class = "verified", source = "read live (Azahar GDB stub, 2026-10-24, Tentacruel): the three bitbots' world matrices at z 90 / 119.7 / 90, sampled twice - middle (2, 12.7) and (-10.9, 38.8): a loop round (0, 28.0) of 15.4; sides (-34.7, 42.3) / (-42.4, 14.5) and (45, 45) / (59.6, 21.2): round x ~-37 / ~44 at y 28, radii 14.5 / 17 (two points each, their roots off their middles); across from the captures, where the side loops are exactly symmetric (centres x 96 / 200 / 304 of 400, radii 37 / 47 / 37 px, clockwise every ~6 s, facing the camera): (+-44.4, 28, 90) and (0, 28, 120), a loop of 16; bodies 38x41 / 45x51 px (~16.5 across), their balls 17 / 12.5 px at launch (radius ~2.8)", confidence = "high" },
  ["GAME3D.BIT_LOOP_R"] = { class = "measured", source = "see GAME3D.BIT_SPOTS", confidence = "medium" },
  ["GAME3D.PLAY_FOVY"] = { class = "verified", source = "read live (Azahar GDB stub, 2026-10-24, Tentacruel's regimen at the middle): the top screen's projection uploaded with each draw holds 2.920762 / 1.752457 (5:3): cot(fovy / 2) = 2.920762, fovy 37.81 degrees (the intro camera e77's 37.85; the capture fit had 37.85)", confidence = "high" },
  ["GAME3D.LOOK_Y"] = { class = "verified", source = "read live (Azahar GDB stub, 2026-10-24, Tentacruel's regimen): the stadium's modelview is the view itself; at the middle rows (1, 0, 0, 0), (0, 0.992021, 0.126070, -34.720844), (0, -0.126070, 0.992021, -237.517853): the eye (0, 4.5, 240) looking 7.24 degrees up at (0, 35.0, 0); at the top (elevation 45) the eye (0, 174.21, 169.71) looking 39.36 degrees down, again at (0, 35.0, 0): a fixed target (the capture fit had 31)", confidence = "high" },
  ["GAME3D.EDGE_OFF"] = { class = "verified", source = "DllSparring.cro 0x1450c-0x14988: at a limit effect #3 is spawned beside the trainee at (0, 2.5, 0) for the top, (+-2.5, 0, 0) for the sides; the 3d-ref captures (Axew / Aerodactyl / Graveler, 2026-10-24) show a ripple disc there: the left one edge-on ~100 px left of Latias, the right a crescent by the stand, the top a ~2:1 ellipse above-left of it", confidence = "high" },
  ["GAME3D.EDGE_TURN"] = { class = "measured", source = "the ripple discs' facing, fitted to the 3d-ref captures (2026-10-24): a side disc nearly edge-on (Axew / Graveler left edge: a streak 10-12 px wide, 90+ tall, leaning 10-15 degrees), the top one a ~0.8 ellipse (Axew top edge 150 x 125 px); EDGE_TURN off the line of sight, EDGE_TILT toward the camera", confidence = "low" },
  ["GAME3D.EDGE_TILT"] = { class = "measured", source = "see GAME3D.EDGE_TURN", confidence = "low" },
  ["GAME3D.SIZE_PX"] = { class = "measured", source = "every regular balloon, Aurorus and Venusaur measured at the start (middle distance, score 0, no aura) in Wooble's captures (st regimens/*.mp4, s2, s3, s4; 2026-10-24, one research agent, medians of 10-20 frames, goal boxes cut out): body box width / height and middle y in 400x240 px; Axew / Aerodactyl cross-checked on the 3d-ref takes; Venusaur (aura on, 0.6 s), Dragalge / Noibat / Noivern / Aerodactyl (thin or flapping) +-5..10 px; Tyrantrum unmeasured (turned view)", confidence = "medium" },
  ["GAME3D.BIT_R"] = { class = "placeholder", source = "ours: a bitbot's hit size against shots (its model e73 is ~47 long)", confidence = "low" },
  ["GAME3D.GROUND"] = { class = "verified", source = "the stadium model's pitch lines (a/1/1/4 e75)", confidence = "high" },
  ["PLAYER.DIST"] = { class = "verified", source = "DllSparring.cro: the trainee's radius targets {180, 240, 300} (table 0x1821c), the step index starting at 1 (0x6fc0), stepped one nearer / farther by button masks 4 / 8 (0x4338 / 0x43f4; blocked while stunned or knocked back), the radius closing at 2.0 units a frame (1.0 guarding; literals 0x45a4 / 0x45a0) - 30 frames a step - with SE 0x100102 (0x42c0-0x4590)", confidence = "high" },
  ["PLAYER"] = { class = "placeholder", source = "bounded box and faster with Spe verified; sizes are not", confidence = "low" },
  ["BOT.GROWTH"] = { class = "placeholder", source = "atwiki: the balloon grows with every goal (no longer used: GROW_K)", confidence = "low" },
  ["BOT.GROW_EASE"] = { class = "measured", source = "Wooble's graveler-2 capture: most of a growth step in the first frame, all of it within 0.2-0.3 s", confidence = "medium" },
  ["BOT.GROW_K"] = { class = "measured", source = "Wooble's graveler-2 capture 2026-10-23: each +177 hit inflates the balloon a step (height 79.5 -> 121.5 px at 94% of 1500), feet fixed; scale ~ 1 + 0.56 x score / target, most of a step in one frame then a small wobble", confidence = "medium" },
  ["BOT.SHAKE_HZ"] = { class = "measured", source = "Wooble's magneton-2 capture: a goal hit twists the balloon side to side ~+-10 px, ~0.5 s a swing, settled in ~0.7 s; Graveler's (graveler-2) a +-1-1.5 px wobble in the same time", confidence = "low" },
  ["BOT.SCALE_MAX"] = { class = "placeholder", source = "Wooble (2026-10-12): 1.2, so the large balloon of this view stays on the top screen; the game's own cap is not measured", confidence = "low" },
  ["BOT.R"] = { class = "placeholder", source = "", confidence = "low" },
  ["BOT.SKY_TOP"] = { class = "inferred", source = "Wooble 2026-10-24 (Thor): a grown balloon must not pass the top of the screen or its goals cannot be reached; the frame's top at the balloon's depth is 140 / 75 = 1.87, less the HUD's top band (ours)", confidence = "medium" },
  ["BOT.FEET_MIN"] = { class = "inferred", source = "ours: how low a grown balloon may sink to stay under SKY_TOP (just above the grass)", confidence = "low" },
  ["BOT.SHAPE_CY"] = { class = "placeholder", source = "ours: the sprite balloon's centre, so it fits the visible sky (y 0..2.09 at the bot's depth)", confidence = "low" },
  ["BOT.AIM_X"] = { class = "placeholder", source = "ours: the aim reach across with a sprite balloon (the sky at the bot's depth is +-1.71)", confidence = "low" },
  ["BOT.AIM_Y"] = { class = "placeholder", source = "ours: the aim reach up with a sprite balloon", confidence = "low" },
  ["BOT.FLINCH_S"] = { class = "placeholder", source = "atwiki: the balloon flinches on a goal", confidence = "low" },
  ["VIEW"] = { class = "placeholder", source = "ours: the layout of Wooble's concept for the top screen (2026-10-12)", confidence = "low" },
  ["ATTACK.BALL"] = { class = "inferred", source = "Wooble (2026-10-12): the attacks are the game's soccer ball, bigger at higher levels (up to the sprite's size at Lv1 / Lv2, about twice at Lv3), growing as they come at the trainee; the multipliers are ours", confidence = "low" },
  ["ATTACK.lob"] = { class = "inferred", source = "Wooble (2026-10-12): balls lobbed up off screen come down on the trainee, a red shadow marking where; flight and height are ours", confidence = "low" },
  ["BOT.SWAY"] = { class = "measured", source = "live read of the HUD target panes in Alpha Sapphire (Azahar, 2026-10-12): Speed Lv1, Sp. Atk Lv2 / Lv3; oras-extract/live_st: Lv1 a loop of +-12 x +-28 px every 4.6 s, Lv2 +-9 x +-14 px slowly, Lv3 swings of up to 120 px (the secret courses take Lv3's until measured). Lv1 from Wooble's six Lv1 captures 2026-10-23 (the old read was Noibat's goal riding its wing): a vertical bob, Wailmer +-6 / 4 s, Geodude +-5 / 3.3 s, Magnemite +-4.75 / 2.35 s, Axew +-1 (still), Tentacool +-11 eased / ~12 s, Noibat +-5 across / 6.6 s - the default +-0.5 x +-5 every 3.5 s, each course's own in data/training_courses.lua `sway`; Lv2 from the s2 captures (Relicanth +-2.8 x +-3.5 / 5.5 s, Fraxure +-2 / 2.8, Graveler +-1.5 / 3.2, Magneton +-2.5 x +-2 / 3.95, Tentacruel a slow sink, Aerodactyl +-9.5 / 5.4): the default +-1.5 x +-2.5 every 4 s", confidence = "low" },
  ["ATTACK.TEMPO"] = { class = "inferred", source = "Wooble 2026-10-23: the trainee moves 50% faster (PLAYER.SPEED 0.41 -> 0.615) and the attacks' motion with it, so play is quicker on our flat field (juking, quick thinking) at the same difficulty; the attack schedule (waits, wind-ups) keeps the captures' timing", confidence = "medium" },
  ["ATTACK.GAME.STRETCH"] = { class = "inferred", source = "Wooble 2026-10-23: the wide ball should be wider and the tall one taller; the game's are ~1.44 : 1 on screen, x1.5 on the long side ~2.2 : 1 (ours)", confidence = "medium" },
  ["ATTACK.GAME.DRAWN"] = { class = "inferred", source = "Wooble 2026-10-23: the ball as drawn is its hitbox (a ball seen to touch the trainee hits it, one seen to pass does not). Wooble's Lv1 captures: ~17 px across of 400 at launch for a size-4.8 ball (PX_PER_UNIT); the game's grows ~13x by the trainee (a stream ball 26 px at launch, ~95 px just before the trainee, ~250 px at the camera, Wailord s3) - too big to dodge as a hitbox, so ours grows GROW 4.5x (~75 px of 400; Wooble 2026-10-23: 3x looked too small)", confidence = "medium" },
  ["ATTACK.HOMING"] = { class = "inferred", source = "Wooble 2026-10-23: homing is to be skill based - not stuck to the trainee, so it can be outrun; a wide or tall ball homes the same with a wider or taller hitbox. A homing ball steers toward the trainee now at most SPEED world units a second on the axes it homes (the trainee moves 0.41) and flies straight over its last HOLD_S; STRONG_K: a pull this strong one way only still homes (the game's k 1 on the wide / tall balls), a weaker one-way pull (Golem's pillars, k 32) is a plain stretched ball", confidence = "medium" },
  ["ATTACK.SHIELD"] = { class = "measured", source = "Wooble's Graveler capture (s2) 2026-10-23: the target fades in ~1.2 s after the shield, circles (199,118) at r 42 px (fit residual 0.5 px over 34 frames) counter-clockwise on screen at 29.3 deg/s (12.3 s a turn), from 123 deg; one hit breaks it; the goals hidden under it, their timer held; unhit it breaks up the same way after ~21.0 s (graveler-2: up 3.15 -> 24.12, the step's 600 frames + TAIL_S); Golem's (s3) the same but r 44, 31.1 deg/s from -97 deg (the top)", confidence = "high" },
  ["BOT.WINDUP"] = { class = "measured", source = "Wooble's Lv1 captures 2026-10-23: every throw a dip (Wailmer ~14 px, Magnemite ~12, Geodude ~10, Noibat ~20), a snap up (Wailmer to -16, Magnemite +2.5 over its top) as the ball leaves, held 1.3-1.5 s while it flies (Magnemite), then back; some also turn (Axew, Magnemite 30-45 degrees), not drawn", confidence = "medium" },
  ["BOT.SHAKE_SCALE"] = { class = "placeholder", source = "ours (Wooble 2026-10-23, the movement ramping by level): the after-goal shake x0.35 Lv1, x0.7 Lv2, x1 Lv3 / secret", confidence = "low" },
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
