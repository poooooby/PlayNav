-- Pokemon-Amie numbers, one place for the rules, the tests and the docs.
-- Sources: Bulbapedia "Pokemon-Amie" (Stats, Affecting stats, Affection
-- benefits), "Poke Puff", "Petting", "Berry Picker", "Head It", "Tile Puzzle";
-- the game's own English text (Alpha Sapphire a/0/7/3, read offline) confirms
-- the rules it states in words. EVIDENCE at the bottom classes every value:
-- verified (a public datamine or the game's text), inferred (a stated rule,
-- our number), placeholder (ours; nothing public states it).
-- Stats are 0..255. Species numbers below are National Dex numbers.

return {
  version = 2,
  MAX = 255,

  -- minimum points for affection / fullness / enjoyment level 0..5
  LEVELS = { [0] = 0, [1] = 1, [2] = 50, [3] = 100, [4] = 150, [5] = 255 },

  -- petting, as Amie's script runs it (a/0/8/9 entry 0, func_0cca0): progress is the time the
  -- stylus moves on the body (a tick counts when it moved more than MOVE_PX touch px in x or y),
  -- on the current spot class and anywhere; a reward once either is long enough, paid by spot
  -- and by how much enjoyment is left to spend; petting then ends until the finger lifts.
  -- Counts are the script's ticks (TICK_HZ a second).
  PET = {
    TICK_HZ = 30,
    MOVE_PX = 4,
    SPOT_TICKS = 60,        -- on one spot class
    REPEAT_TICKS = 60,      -- more for each reward in a row already given on that class
    BODY_TICKS = 150,       -- anywhere on the body but a disliked spot (paid as normal)
    DISLIKED_TICKS = 30,
    SWITCH_TICKS = 4,       -- another spot class takes over once it lasts this long
    OFF_BODY_TICKS = 30,    -- this long off the body ends the petting
    normal = { { min = 50, aff = 3, enj = -50 }, { min = 35, aff = 2, enj = -35 }, { min = 20, aff = 1, enj = -20 } },
    favored = { { min = 42, aff = 3, enj = -42 }, { min = 16, aff = 1, enj = -16 } },
    disfavored = { aff = 0, enj = -20 },
    -- the interrupting spots (burning, paralyzing, cutting, freezing) react on contact: a jolt
    -- every JOLT_TICKS of it; the EFFECT_JOLTS-th jolt (counted over the visit) makes it
    -- recoil and ends the petting
    EFFECT_JOLTS = 5,
    JOLT_TICKS = { burning = 30, paralyzing = 30, cutting = 16, freezing = 16 },
    LOCK_S = 1.2,           -- the happy motion after a reward, petting locked meanwhile
  },

  -- PLAY left alone (the script's main loop, func_0f284): IDLE_TICKS without a touch, it falls
  -- asleep (CYCLES motions of about CYCLE_TICKS), then goes back into its ball and to the room;
  -- at once on entering when enjoyment and fullness are both at least SATED
  IDLE = { TICKS = 900, CYCLES = 3, CYCLE_TICKS = 60, SATED = 150, BALL_S = 0.35 },

  -- feeding, as Amie's script runs it: a puff is FULLNESS in BITES[national] bites (50 div bites
  -- each, the last the remainder), then its tier's affection; no flavour or nature enters it;
  -- from SLOW_AT fullness a Pokemon taking two or more bites pauses after each; at 255 it turns
  -- away from the puff. Eating changes no enjoyment.
  PUFF = {
    FULLNESS = 50,                       -- a whole puff
    AFFECTION = { basic = 2, frosted = 3, fancy = 4, deluxe = 5, supreme = 6, supreme_special = 10 },
    SLOW_AT = 230,
    CAP = 100,                           -- jar size; the oldest puff is lost past it
    START = 10,
    BITES_DEFAULT = 3,
    -- the species that take other than three bites (a/0/8/9 entries 1-721, s16 at +306)
    BITES = {
      [23] = 1, [24] = 1, [316] = 1, [317] = 1, [321] = 1, [336] = 1, [443] = 1, [455] = 1,
      [3] = 2, [95] = 2, [103] = 2, [115] = 2, [130] = 2, [131] = 2, [143] = 2, [146] = 2,
      [148] = 2, [149] = 2, [150] = 2, [160] = 2, [199] = 2, [208] = 2, [226] = 2, [244] = 2,
      [245] = 2, [248] = 2, [249] = 2, [250] = 2, [289] = 2, [297] = 2, [306] = 2, [320] = 2,
      [330] = 2, [350] = 2, [357] = 2, [381] = 2, [382] = 2, [383] = 2, [384] = 2, [389] = 2,
      [450] = 2, [460] = 2, [464] = 2, [465] = 2, [472] = 2, [473] = 2, [477] = 2, [483] = 2,
      [484] = 2, [486] = 2, [487] = 2, [493] = 2, [497] = 2, [545] = 2, [593] = 2, [604] = 2,
      [614] = 2, [623] = 2, [638] = 2, [640] = 2, [643] = 2, [644] = 2, [646] = 2, [675] = 2,
      [697] = 2, [699] = 2, [706] = 2, [713] = 2, [716] = 2, [717] = 2, [718] = 2,
      [50] = 5, [177] = 5, [298] = 5, [406] = 5, [412] = 5, [433] = 5, [492] = 5, [590] = 5,
      [595] = 5, [602] = 5, [682] = 5,
    },
  },

  -- a played minigame, every participant: fullness and enjoyment by game and rank; Unlimited
  -- by the result's star step (0..6: +80 .. +140)
  GAME = {
    FULLNESS = -110,
    ENJOYMENT = { berry = 80, head = 80, tile = { easy = 30, normal = 50, hard = 80 } },
    UNLIMITED_ENJOYMENT = 80, UNLIMITED_STEP = 10,
    PARTICIPANTS = 3,
  },

  -- the Pokemon chosen for Amie only, when it took part in a battle / every 50 steps:
  -- enjoyment only below ENJOYMENT_BELOW (a battle's never past it)
  BATTLE = { FULLNESS = -10, ENJOYMENT = 5, ENJOYMENT_BELOW = 50 },
  STEPS = { EVERY = 50, FULLNESS = -1, ENJOYMENT = 1, ENJOYMENT_BELOW = 50 },
  -- a hit: a second press on the body within TICKS of the first
  HIT = { ENJOYMENT = -5, TICKS = 4 },
  -- a high five: a finger held still off the Pokemon (after POSE_TICKS the hand is held out)
  -- counts down ((255 - affection) div STEP + 1) x PER_STEP + rand(RAND) ticks (only while
  -- held; rolled again after an attempt), then it reaches for the hand, TRIES times at most;
  -- needs MIN_AFFECTION
  HIGH_FIVE = { ENJOYMENT = 10, MIN_AFFECTION = 5, POSE_TICKS = 10, STEP = 50, PER_STEP = 30, RAND = 30, TRIES = 2 },
  -- opening PLAY, and coming back to it from a minigame
  OPEN_PLAY = { ENJOYMENT = 10 },
  -- the camera and microphone games (no camera or microphone here; unused)
  MAKING_FACES = { AFFECTION = 4, FULLNESS = -50, ENJOYMENT = 40 },
  MIC = { ENJOYMENT = 5, TIMES = 4 }, SMILE = { ENJOYMENT = 5, TIMES = 4 },

  DANCE_EVERY = 50,                      -- hearts, twice at 50, 100, 150, 200; three times at 255
  -- affection milestones that give a Decor gift (the highest crossed only), and their sets
  GIFT_AFFECTION = { 25, 50, 75, 100, 150, 255 },
  GIFT_SET = { [25] = "B", [50] = "C", [75] = "D", [100] = "D", [150] = "E", [255] = "F" },
  HINT = { LOW = 50, HIGH = 200 },       -- icons over a wandering Pokemon

  -- benefits in battle
  BENEFITS = {
    EXP_LEVEL = 2, EXP_MULT = 1.2,
    ENDURE_LEVEL = 3, ENDURE_PCT = { [3] = 10, [4] = 15, [5] = 25 }, ENDURE_PCT_200 = 20,
    CURE_LEVEL = 4, CURE_PCT = 20,
    DODGE_AFFECTION = 200, DODGE_POINTS = 10,
    CRIT_LEVEL = 5,
  },

  -- species that never eat Poke Puffs (no visible mouth)
  NON_EATERS = { [11] = true, [14] = true, [204] = true, [266] = true, [268] = true, [292] = true, [665] = true },
  -- species that cannot be petted at all (burning / freezing whole body)
  NO_PET = { [218] = true, [378] = true },

  -- where each value comes from; a row covers the path and everything under it
  EVIDENCE = {
    MAX = { class = "verified", source = "Bulbapedia Pokemon-Amie: stats run 0..255", confidence = "high" },
    LEVELS = { class = "verified", source = "DllField.cro 0xd790c / 0xd4120 (levels 1-49, 50-99, 100-149, 150-254, 255); Bulbapedia Pokemon-Amie agrees; the words Affection / Fullness / Enjoyment are a/0/7/3 file 111 lines 14-16", confidence = "high" },
    PET = { class = "verified", source = "Amie's script a/0/8/9 entry 0 (func_0cca0, rewards 0xd890..0xdb68); Bulbapedia Pokemon-Amie, Petting agrees", confidence = "high" },
    ["PET.TICK_HZ"] = { class = "verified", source = "the game runs at 30 fps (Wooble, 2026-10-19); the script yields once a frame, so the idle sleep's 900 ticks are 30 s", confidence = "high" },
    ["PET.MOVE_PX"] = { class = "verified", source = "a/0/8/9 func_05534(4) at 0xd67c / 0xd714: abs delta > 4 touch px", confidence = "high" },
    ["PET.SPOT_TICKS"] = { class = "verified", source = "a/0/8/9 0xd7a4..0xd980: L11 >= 60 + 60 x repeats (G1372 / G1376)", confidence = "high" },
    ["PET.REPEAT_TICKS"] = { class = "verified", source = "a/0/8/9 0xd7a4..0xd980, 0xec9c..0xecf4", confidence = "high" },
    ["PET.BODY_TICKS"] = { class = "verified", source = "a/0/8/9 0xd7a4..0xd980: L12 >= 150", confidence = "high" },
    ["PET.DISLIKED_TICKS"] = { class = "verified", source = "a/0/8/9: a disliked spot's flat 30", confidence = "high" },
    ["PET.SWITCH_TICKS"] = { class = "verified", source = "a/0/8/9 0xd69c..0xd78c", confidence = "high" },
    ["PET.OFF_BODY_TICKS"] = { class = "verified", source = "a/0/8/9 0xd280", confidence = "high" },
    ["PET.EFFECT_JOLTS"] = { class = "verified", source = "a/0/8/9 0xe8f8: INC G1368; 5 <= G1368 -> motion 10, petting ends", confidence = "high" },
    ["PET.JOLT_TICKS"] = { class = "verified", source = "a/0/8/9 0xe398..0xea1c: 30 ticks of shake (burn, shock), 1 + 15 of jolt (cut, freeze)", confidence = "medium" },
    ["PET.LOCK_S"] = { class = "inferred", source = "the script locks touch until the happy motion (func_04f2c) ends; the motion's length is ours", confidence = "low" },
    IDLE = { class = "verified", source = "a/0/8/9 func_0f284: L5 > 900 (0xfc24..0xfc44), 3 sleep cycles (0xfc94..0x10234), 60 ticks with no motion, at once when enjoyment and fullness >= 150 (0xf364..0xf3b0)", confidence = "high" },
    ["IDLE.BALL_S"] = { class = "inferred", source = "func_10ec4: it shrinks into its ball over 10 ticks before the room", confidence = "medium" },
    PUFF = { class = "verified", source = "Amie's script a/0/8/9 e0: fullness 50 div bites, the last the remainder (func_0b144 0xb248-0xb34c); affection = the puff table a/2/2/3's b1 (_GetCakePara(1), 0xb844 / 0xb860; read by main 0x468e14); a pause after each bite from 230 with 2+ bites (0xb470-0xb640); refused at 255 (0xc5b4); no flavour read anywhere", confidence = "high" },
    ["PUFF.BITES"] = { class = "verified", source = "a/0/8/9 entries 1-721 (National Dex), s16 at +306 (the script's G448): 639 species 3 bites; that this is G448 is inferred from the record layout and the spread", confidence = "medium" },
    ["PUFF.CAP"] = { class = "verified", source = "Bulbapedia Poke Puff: up to 100 kept; a/0/7/3 files 105-107 'You can't carry any more Poke Puffs!' confirms a cap", confidence = "high" },
    ["PUFF.START"] = { class = "placeholder", source = "ours: the starting jar", confidence = "low" },
    GAME = { class = "verified", source = "DllPuzzle.cro 0x55d0-0x5634 (ro 0xe0f4: easy 30, normal 50, hard 80, Unlimited 80..140 by result), DllNuts.cro 0x4434-0x44a8 (ro 0xd594: 80; Unlimited 80..140), DllHeading.cro 0x44c4 (80; Unlimited 80..140); fullness -110 each; row = difficulty, index = result is inferred", confidence = "high" },
    ["GAME.PARTICIPANTS"] = { class = "verified", source = "a/0/7/3 file 124 line 9 'You need three Pokemon in good condition.'", confidence = "high" },
    BATTLE = { class = "verified", source = "main 0x3e8a64 -> 0x3b5548: the Amie Pokemon only, when it took part (flag +0x155); enjoyment +5 only below 50, capped at 50 (0x3b5594-0x3b55ac); fullness -10 (0x3b55c0)", confidence = "high" },
    STEPS = { class = "verified", source = "DllField.cro 0x23818-0x2384c (every 50 steps) -> main 0x478828: enjoyment +1 only below 50 (0x478880), fullness -1 (0x4788a0); the Amie Pokemon only (party +0x19)", confidence = "high" },
    HIT = { class = "verified", source = "Amie's script func_0a234 (0xaf28-0xb048): a new press on the body while the first press's counter is 1..4; func_09fc0: enjoyment -5 (0xa054)", confidence = "high" },
    HIGH_FIVE = { class = "verified", source = "Amie's script: pose at 10 ticks (0xa4d8-0xa53c), countdown ((255 - aff) div 50 + 1) * 30 + rand(30) (0xa3b8), runs only while held off the body (0xa778), affection >= 5 (0xa7cc), 2 tries (0xa878), success on body part 10 during the reach (0xa92c), +10 enjoyment (0xaaa8), rolled again (0xab54); the reach needs the species' motion 25", confidence = "high" },
    OPEN_PLAY = { class = "verified", source = "Amie's script func_104c8 0x10cf0-0x10d1c (+10 on opening PLAY, once a run) and func_10d88 0x10e60 (+10 back from a minigame); the room changes no stats (DllField imports no setter)", confidence = "high" },
    MAKING_FACES = { class = "verified", source = "Amie's script 0x1296c / 0x12994 / 0x129b0 (per success); microphone +5 x4 (0x2d0c), smile +5 x4 (0x6698); no camera or microphone here, unused", confidence = "high" },
    DANCE_EVERY = { class = "verified", source = "Amie's script func_095f0: thresholds 50 / 100 / 150 / 200 / 255 (data 0x51c), played 2 / 2 / 2 / 2 / 3 times, once each a visit, after feeding, a petting reward or a face game", confidence = "high" },
    GIFT_AFFECTION = { class = "verified", source = "main 0x408fc8 (thresholds 25 / 50 / 75 / 100 / 150 / 255 at 0x581c24; the highest crossed since the last stored value only), sets DllField 0xfb404 (B C D D E F); lines 11 / 19 of file 111", confidence = "high" },
    HINT = { class = "placeholder", source = "ours: the game shows no hint over the room's Pokemon (DllField has only the menu's bubbles)", confidence = "low" },
    BENEFITS = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affection benefits", confidence = "high" },
    GIFT_SET = { class = "verified", source = "DllField.cro table 0xfb404: the affection milestones' sets B C D D E F", confidence = "high" },
    MIC = { class = "verified", source = "Amie's script: microphone +5 enjoyment for the first 4 times (G1264, 0x2d0c); no microphone here, unused", confidence = "high" },
    SMILE = { class = "verified", source = "Amie's script: a camera smile >= 50 gives +5 enjoyment, 4 times at most (G1268, 0x6698); no camera here, unused", confidence = "high" },
    NON_EATERS = { class = "verified", source = "DllField.cro 0xd40f0-0xd411c (no fullness bubble for 11, 14, 204, 266, 268, 292, 665); Bulbapedia Poke Puff agrees", confidence = "high" },
    NO_PET = { class = "verified", source = "Bulbapedia Petting: Slugma and Regice cannot be petted", confidence = "high" },
  },
}
