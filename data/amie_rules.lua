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

  -- one petting event per STEP_PX of stroke on the body; the gain depends
  -- on the spot and on how much enjoyment is left to spend
  PET = {
    STEP_PX = 60,
    normal = { { min = 50, aff = 3, enj = -50 }, { min = 35, aff = 2, enj = -35 }, { min = 20, aff = 1, enj = -20 } },
    favored = { { min = 42, aff = 3, enj = -42 }, { min = 16, aff = 1, enj = -16 } },
    disfavored = { aff = 0, enj = -20 },
    FAST_PX_PER_S = 900, -- faster than this reads as a scrub, no petting event
  },

  PUFF = {
    FULLNESS = 50,                       -- a whole puff
    AFFECTION = { basic = 2, frosted = 3, fancy = 4, deluxe = 5, supreme = 6, supreme_special = 10 },
    BITE_FULLNESS = { [2] = 24, [3] = 16, [5] = 10 },  -- per bite of a puff not finished
    SLOW_FROM = 198, ALL_SLOW_FROM = 214,  -- fullness bands that slow the bites
    CAP = 100,                           -- jar size; the oldest puff is lost past it
    START = 10,
  },

  GAME = {
    FULLNESS = -110, ENJOYMENT = 80, ENJOYMENT_EASY_TILE = 30,
    OPEN_ENJOYMENT = 10,                 -- once per save load
    PARTICIPANTS = 3,
  },

  BATTLE = { FULLNESS = -10, ENJOYMENT = 5 },
  STEPS = { EVERY = 50, FULLNESS = -1, ENJOYMENT = 1, ENJOYMENT_BELOW = 70 },  -- 0-70 inclusive
  HIT = { ENJOYMENT = -5, WINDOW_S = 0.3, RADIUS_PX = 10 },
  HIGH_FIVE = { ENJOYMENT = 10, HOLD_S = 5, MIN_AFFECTION = 5 },
  OPEN_PLAY = { ENJOYMENT = 10 },
  MAKING_FACES = { AFFECTION = 8, FULLNESS = -50, ENJOYMENT = 80 },  -- needs a camera; unused

  DANCE_EVERY = 50,                      -- hearts and two cries at 50, 100, ...; three at 255
  GIFT_AFFECTION = { 50, 100, 150, 255 },  -- each affection level from 2 up
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
  NON_EATERS = { [11] = true, [14] = true, [204] = true, [266] = true, [268] = true, [292] = true },
  -- species that cannot be petted at all (burning / freezing whole body)
  NO_PET = { [218] = true, [378] = true },

  -- where each value comes from; a row covers the path and everything under it
  EVIDENCE = {
    MAX = { class = "verified", source = "Bulbapedia Pokemon-Amie: stats run 0..255", confidence = "high" },
    LEVELS = { class = "verified", source = "Bulbapedia Pokemon-Amie: level thresholds 1 / 50 / 100 / 150 / 255; the words Affection / Fullness / Enjoyment are a/0/7/3 file 111 lines 14-16", confidence = "high" },
    PET = { class = "verified", source = "Bulbapedia Pokemon-Amie, Petting: gains per spot and enjoyment band", confidence = "high" },
    ["PET.STEP_PX"] = { class = "placeholder", source = "ours: stroke length that counts as one petting event on this screen", confidence = "low" },
    ["PET.FAST_PX_PER_S"] = { class = "placeholder", source = "ours: a stroke faster than this reads as a scrub", confidence = "low" },
    PUFF = { class = "verified", source = "Bulbapedia Poke Puff: +50 fullness, affection by tier, bites, the slow bands", confidence = "high" },
    ["PUFF.CAP"] = { class = "verified", source = "Bulbapedia Poke Puff: up to 100 kept; a/0/7/3 files 105-107 'You can't carry any more Poke Puffs!' confirms a cap", confidence = "high" },
    ["PUFF.START"] = { class = "placeholder", source = "ours: the starting jar", confidence = "low" },
    GAME = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affecting stats: a game -110 fullness, +80 enjoyment (+30 easy Tile Puzzle), +10 on opening", confidence = "high" },
    ["GAME.PARTICIPANTS"] = { class = "verified", source = "a/0/7/3 file 124 line 9 'You need three Pokemon in good condition.'", confidence = "high" },
    BATTLE = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affecting stats", confidence = "high" },
    STEPS = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affecting stats", confidence = "high" },
    HIT = { class = "verified", source = "Bulbapedia Pokemon-Amie: a hit -5 enjoyment", confidence = "medium" },
    ["HIT.WINDOW_S"] = { class = "placeholder", source = "ours: what reads as a hit on this screen", confidence = "low" },
    ["HIT.RADIUS_PX"] = { class = "placeholder", source = "ours", confidence = "low" },
    HIGH_FIVE = { class = "verified", source = "Bulbapedia Pokemon-Amie: a high five +10 enjoyment", confidence = "medium" },
    ["HIGH_FIVE.HOLD_S"] = { class = "placeholder", source = "ours: how long the hand is held out", confidence = "low" },
    ["HIGH_FIVE.MIN_AFFECTION"] = { class = "inferred", source = "Bulbapedia: a Pokemon high-fives once it is fond of you; the threshold is ours", confidence = "low" },
    OPEN_PLAY = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affecting stats", confidence = "high" },
    MAKING_FACES = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affecting stats (needs the camera; unused)", confidence = "high" },
    DANCE_EVERY = { class = "inferred", source = "Bulbapedia: the Pokemon celebrates as affection grows; the cadence is ours", confidence = "low" },
    GIFT_AFFECTION = { class = "verified", source = "oraswiki Pokemon-Amie: decorations are won by raising the affection level (levels 2-5 at 50 / 100 / 150 / 255); a/0/7/3 file 111 lines 11, 19 are the gift lines", confidence = "medium" },
    HINT = { class = "placeholder", source = "ours: when the room shows a hunger or boredom icon", confidence = "low" },
    BENEFITS = { class = "verified", source = "Bulbapedia Pokemon-Amie, Affection benefits", confidence = "high" },
    NON_EATERS = { class = "verified", source = "Bulbapedia Poke Puff: species that cannot eat", confidence = "high" },
    NO_PET = { class = "verified", source = "Bulbapedia Petting: Slugma and Regice cannot be petted", confidence = "high" },
  },
}
