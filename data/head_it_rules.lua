-- Head It's rules, read from the game's code (romfs/DllHeading.cro; addresses are file
-- offsets into it). Counts are frames at the game's 30 fps. Positions are the touch screen's
-- layout units with y up about its middle: the touch screen spans y -120..120, the top screen
-- y 240..480 (x -200..200), the gap between them 120..240.
return {
  FPS = 30,
  TIME = 1800,              -- the clock (Process +0x4c)
  LIVES = 3,                -- Unlimited's chances (0x434c)
  CAP = 999,                -- points and combo
  SLOT_X = { 0, -100, 100 },  -- the middle Pokemon, then the left, then the right (0x143c)
  SPAWN_Y = 480, GIANT_Y = 580,
  OUT_TOP = 480, OUT_BOTTOM = -200,
  RISE_FLOOR = 5,           -- a headed ball never rises slower
  DRIFT = 2 * 0.7447,       -- a good hit's sideways drift a frame
  CRUSH_MIN_FALL = 300,     -- a crush ball is kept only if it falls this far within one interval
  -- (ours) a ball goes on a column only if it reaches the Pokemon at least this many frames from
  -- every ball already falling there: else another Pokemon, else a plain ball, else a frame later
  -- - the game's random column let a fast ball catch the one ahead in FEVER, two at once on one
  -- head, which takes 8 frames to head again
  MIN_GAP_F = 12,
  -- the hit windows (ball.bclyt's bounding panes, screen y down from the touch screen's top) and
  -- the test point: the ball's middle, lowered by a quarter of its 90-unit pane (the giant: 0.4
  -- of its 350)
  -- (the game's good windows run 90-130 and 180-240; ours are tighter, 105-130 and 180-205, so a
  -- ball has to be at the Pokemon's head: with our sprites the game's let a ball nearly off the
  -- screen's foot count)
  WINDOW = { goodHigh = { 105, 130 }, just = { 130, 180 }, goodLow = { 180, 205 }, miss = { 240, 280 } },
  BALL_H = 90, TEST_DROP = 0.25, GIANT_H = 350, GIANT_DROP = 0.4,
  -- the touch columns (1f / 1g / 1h): 106 wide about each place, the touch screen's lower half
  TOUCH = { w = 106, top = 120 },
  POINTS = { good = 1, just = 3, fever = 2 },
  MILESTONE = { { every = 100, points = 100 }, { every = 50, points = 50 }, { every = 10, points = 10 } },
  COMBO_SHOW = 3,           -- the N-HIT COMBO words from here
  BIG_BONUS = { good = 10, just = 50 },
  END_WAIT = 30,            -- frames after the last ball before the side Pokemon leave
  -- per difficulty, per stage (1, 2, 3 Pokemon): { start interval, per good hit, per just hit,
  -- minimum, at fever, stage frames, fever combo } (0xb038 + diff * 2520)
  STAGES = {
    easy = { { 90, -8, -15, 30, 30, 600, 5 }, { 90, -8, -15, 30, 30, 600, 5 }, { 90, -8, -15, 30, 30, 299970, 5 } },
    normal = { { 75, -5, -10, 30, 30, 600, 15 }, { 75, -5, -10, 25, 25, 600, 15 }, { 75, -5, -10, 20, 20, 299970, 15 } },
    hard = { { 60, -3, -5, 25, 25, 600, 15 }, { 60, -3, -5, 20, 20, 600, 15 }, { 60, -3, -5, 15, 15, 299970, 15 } },
  },
  UNLIMITED_FEVER = 15,
  -- flight patterns: the odds (percent) of a crush ball and a purple ball, then 8 groups of
  -- { v0, g, vGood, decelGood, vJust, decelJust }: plain for 1 / 2 / 3 Pokemon, crush for 1 / 2 / 3,
  -- purple, the giant (0xd920 + diff * 6000 + pattern * 200)
  PATTERNS = {
    easy = { crush = 5, purple = 0, groups = { { 1.2, 0.52, 30, 0.4, 36, 0.6 }, { 1.4, 0.56, 32, 0.6, 42, 0.8 }, { 1.6, 0.6, 40, 0.8, 48, 1 }, { 1, 0.2, 24, 0.2, 36, 0.4 }, { 1.2, 0.4, 24, 0.4, 36, 0.6 }, { 1.2, 0.4, 30, 0.6, 36, 0.8 }, { 2, 0.8, 30, 0.8, 36, 1 }, { 1.2, 0.6, 40, 0.8, 60, 1 } } },
    normal = { crush = 5, purple = 5, groups = { { 1.6, 0.6, 32, 0.4, 48, 0.6 }, { 2, 0.4, 32, 0.6, 42, 0.8 }, { 2.2, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.2, 24, 0.2, 36, 0.4 }, { 1.2, 0.4, 24, 0.4, 36, 0.6 }, { 1.2, 0.4, 30, 0.6, 36, 0.8 }, { 2.6, 0.8, 36, 0.8, 38, 1 }, { 1.2, 0.6, 40, 0.8, 60, 1 } } },
    hard = { crush = 10, purple = 10, groups = { { 1.8, 0.6, 36, 0.4, 54, 0.6 }, { 2, 0.6, 32, 0.6, 42, 0.8 }, { 2.4, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.2, 24, 0.2, 36, 0.4 }, { 1.2, 0.4, 24, 0.4, 36, 0.6 }, { 1.2, 0.4, 30, 0.6, 36, 0.8 }, { 3, 1.2, 40, 0.8, 46, 1 }, { 1.2, 0.6, 40, 0.8, 60, 1 } } },
    unlimited = {
      { crush = 5, purple = 5, groups = { { 1.4, 0.4, 30, 0.4, 36, 0.6 }, { 1.6, 0.6, 32, 0.6, 42, 0.8 }, { 1.8, 0.6, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 2.6, 0.8, 36, 0.8, 78, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.6, 0.6, 30, 0.4, 36, 0.6 }, { 1.8, 0.6, 32, 0.6, 42, 0.8 }, { 2.2, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3, 0.8, 40, 0.8, 90, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.8, 0.6, 30, 0.4, 36, 0.6 }, { 1.9, 0.8, 32, 0.6, 42, 0.8 }, { 2.2, 1, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.2, 0.8, 40, 0.8, 96, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 0.9, 1, 30, 0.4, 36, 0.6 }, { 1, 1.2, 32, 0.6, 42, 0.8 }, { 1.1, 1.2, 40, 0.6, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.4, 0.8, 40, 0.8, 102, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.6, 0.6, 30, 0.4, 36, 0.6 }, { 1.9, 0.6, 32, 0.6, 42, 0.8 }, { 2, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 0.8, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.7, 0.6, 30, 0.4, 36, 0.6 }, { 1.9, 0.8, 32, 0.6, 42, 0.8 }, { 2, 1, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 0.8, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.4, 0.6, 30, 0.4, 36, 0.6 }, { 1.6, 0.6, 32, 0.6, 42, 0.8 }, { 2, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.7, 0.8, 30, 0.4, 36, 0.6 }, { 1.9, 0.8, 32, 0.6, 42, 0.8 }, { 2.1, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.8, 0.8, 30, 0.4, 36, 0.6 }, { 2, 0.8, 32, 0.6, 42, 0.8 }, { 2.2, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.8, 0.8, 30, 0.4, 36, 0.6 }, { 2.2, 0.8, 32, 0.6, 42, 0.8 }, { 2.4, 1, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.6, 0.6, 30, 0.4, 36, 0.6 }, { 1.8, 0.8, 32, 0.6, 42, 0.8 }, { 2.4, 1, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.7, 0.6, 30, 0.4, 36, 0.6 }, { 2, 0.8, 32, 0.6, 42, 0.8 }, { 2.5, 1, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.7, 0.72, 30, 0.4, 36, 0.6 }, { 2, 0.8, 32, 0.6, 42, 0.8 }, { 2.6, 1, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.6, 0.72, 30, 0.4, 36, 0.6 }, { 2, 0.8, 32, 0.6, 42, 0.8 }, { 2.6, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 5, purple = 5, groups = { { 1.6, 0.8, 30, 0.4, 36, 0.6 }, { 2.1, 0.8, 32, 0.6, 42, 0.8 }, { 2.8, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 0, purple = 5, groups = { { 1.8, 0.6, 30, 0.4, 36, 0.6 }, { 2.2, 0.8, 32, 0.6, 42, 0.8 }, { 2.8, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
      { crush = 0, purple = 0, groups = { { 1.8, 0.6, 30, 0.4, 36, 0.6 }, { 2.2, 0.8, 32, 0.6, 42, 0.8 }, { 2.9, 0.8, 40, 0.8, 48, 1 }, { 1.2, 0.6, 24, 0.6, 36, 0.4 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 1.2, 0.6, 24, 0.6, 36, 0.6 }, { 3.6, 1, 46, 0.8, 108, 1 }, { 3, 0.8, 60, 0.8, 64, 1 } } },
    },
  },
  -- Unlimited's steps (0xcdc0): { Pokemon, interval, per good hit, per just hit, minimum, frames }
  UNLIMITED_STEPS = {
    { 1, 50, -5, -5, 35, 300 }, -- 0
    { 2, 50, -5, -5, 35, 300 }, -- 1
    { 3, 45, -5, -5, 35, 300 }, -- 2
    { 1, 45, -5, -5, 23, 300 }, -- 3
    { 2, 45, -5, -5, 22, 300 }, -- 4
    { 3, 45, -5, -5, 20, 450 }, -- 5
    { 1, 40, -3, -3, 20, 300 }, -- 6
    { 2, 45, -3, -3, 19, 300 }, -- 7
    { 3, 45, -3, -3, 18, 900 }, -- 8
    { 1, 40, -3, -3, 20, 300 }, -- 9
    { 2, 45, -3, -3, 20, 450 }, -- 10
    { 3, 45, -3, -3, 20, 300 }, -- 11
    { 1, 40, -3, -3, 20, 300 }, -- 12
    { 2, 45, -3, -3, 20, 450 }, -- 13
    { 3, 45, -3, -3, 20, 600 }, -- 14
    { 1, 40, -3, -3, 19, 300 }, -- 15
    { 2, 45, -2, -2, 18, 450 }, -- 16
    { 3, 45, -2, -2, 15, 600 }, -- 17
    { 1, 35, -3, -3, 30, 300 }, -- 18
    { 2, 45, -3, -3, 30, 300 }, -- 19
    { 3, 45, -3, -3, 30, 300 }, -- 20
    { 1, 120, -10, -10, 23, 300 }, -- 21
    { 2, 105, -10, -10, 23, 450 }, -- 22
    { 3, 90, -10, -10, 23, 600 }, -- 23
    { 1, 30, -3, -3, 16, 300 }, -- 24
    { 2, 30, -1, -1, 15, 450 }, -- 25
    { 3, 30, -1, -1, 14, 600 }, -- 26
    { 1, 30, -5, -5, 15, 300 }, -- 27
    { 2, 40, -3, -5, 14, 450 }, -- 28
    { 3, 40, -1, -5, 13, 900 }, -- 29
    { 1, 60, -5, -5, 28, 300 }, -- 30
    { 2, 60, -3, -3, 28, 450 }, -- 31
    { 3, 60, -3, -3, 28, 450 }, -- 32
    { 1, 50, -5, -5, 25, 300 }, -- 33
    { 2, 45, -3, -3, 23, 300 }, -- 34
    { 3, 45, -3, -3, 18, 600 }, -- 35
    { 1, 45, -5, -5, 20, 300 }, -- 36
    { 2, 45, -3, -3, 18, 450 }, -- 37
    { 3, 45, -3, -3, 15, 900 }, -- 38
    { 1, 45, -5, -5, 15, 300 }, -- 39
    { 2, 50, -4, -4, 15, 450 }, -- 40
    { 3, 50, -3, -3, 15, 600 }, -- 41
    { 1, 35, -5, -5, 14, 300 }, -- 42
    { 2, 35, -3, -3, 13, 450 }, -- 43
    { 3, 35, -2, -2, 12, 1200 }, -- 44
    { 1, 30, -5, -5, 13, 300 }, -- 45
    { 2, 30, -3, -3, 12, 450 }, -- 46
    { 3, 30, -3, -3, 10, 900 }, -- 47
    { 1, 30, -5, -5, 10, 300 }, -- 48
    { 2, 30, -3, -3, 10, 450 }, -- 49
    { 3, 30, -3, -3, 9, 900 }, -- 50
    { 1, 30, -5, -5, 9, 300 }, -- 51
    { 2, 30, -3, -3, 9, 450 }, -- 52
    { 3, 30, -3, -3, 8, 1200 }, -- 53
  },
  -- the order Unlimited plays its steps in (record numbers from 0; 0xd798), on from position
  -- LOOP_TO when it runs out; a 3-Pokemon step that ends moves to the next pattern
  -- (PATTERN_ORDER, 0x136e0, on from PATTERN_LOOP_TO)
  UNLIMITED_ORDER = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 45, 46, 47,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 48, 49, 50,
    30, 31, 32, 33, 34, 35, 39, 40, 41, 51, 52, 53,
  },
  UNLIMITED_LOOP_TO = 30,
  PATTERN_ORDER = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 10, 11, 12, 13, 15, 10, 11, 12, 13, 16, 10, 11, 13, 15 },
  PATTERN_LOOP_TO = 20,
  -- results: TOTAL = points + the longest combo + the big yarn (0x9718)

  EVIDENCE = {
    TIME = { class = "verified", source = "DllHeading.cro init 0x42e4: the clock at Process +0x4c starts at 1800", confidence = "high" },
    LIVES = { class = "verified", source = "DllHeading.cro 0x434c (3); a missed ball costs one leaving the screen (0x6d14); none left ends at once, no giant (0x77f4)", confidence = "high" },
    SLOT_X = { class = "verified", source = "DllHeading.cro 0x143c: one Pokemon always the middle, two rand(2) left / middle, three rand(3); places -100 / 0 / 100", confidence = "high" },
    POINTS = { class = "verified", source = "DllHeading.cro 0x6868: good +1, just +3, doubled in fever; capped 999", confidence = "high" },
    MILESTONE = { class = "verified", source = "DllHeading.cro 0x6a90-0x6c44: combo % 100 +100, % 50 +50, % 10 +10; combo 3 the combo words", confidence = "high" },
    STAGES = { class = "verified", source = "DllHeading.cro .rodata 0xb038 + diff * 2520, 7 ints a stage; the second Pokemon at 600 frames, the third at 1200 (0x64b4); fever 0x6d50-0x6e50; interval clamp 0x6c94", confidence = "high" },
    PATTERNS = { class = "verified", source = "DllHeading.cro 0xd920 + diff * 6000 + idx * 200 (odds), flight 0x59c0, fall v += g; y -= v (0xd18), ball type roll 0x12a8, crush check 0x57dc", confidence = "high" },
    UNLIMITED_STEPS = { class = "verified", source = "DllHeading.cro 0xcdc0 (records), 0xd798 (order, 1030 jumps to 30, 0x7b68), 0x136e0 (patterns, % 30 of 1010 back to 20)", confidence = "high" },
    MIN_GAP_F = { class = "placeholder", source = "ours (2026-10-24, a player report: in FEVER two balls could reach one Pokemon at once, the second unhittable): a column is taken only when the ball arrives 12 frames or more from any already falling on it - 8 for the heading plus a little to react; the game picks the column at random with no such test", confidence = "medium" },
    WINDOW = { class = "inferred", source = "good windows narrowed by us (the game's counted a ball nearly off the screen past our sprites); the game's: ball.bclyt (a/0/1/7 e0) bounding panes 0/2/4, 1/3/5, 1x/1y/1z, 8 (index tables 0x13d68 / 0x13d80 / 0x13d74); the test point's 0.25 drop is read from 0x58b0 but not run live", confidence = "medium" },
    TOUCH = { class = "verified", source = "ball.bclyt panes 1f / 1g / 1h (106 x 120); a tap counts for the column's lowest ball, not while that Pokemon heads (0xb1c)", confidence = "high" },
    BIG_BONUS = { class = "verified", source = "DllHeading.cro 0x74c0: 10 good, 50 just, 0 missed; the giant drops on the middle Pokemon after the side ones leave (state machine 0x61b4)", confidence = "high" },
  },
}
