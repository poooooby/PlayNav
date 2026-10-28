-- Which of the game's own Super Training sound effects (recipe kind "sfx", rendered from the
-- player's card image) plays when. The game names its 52 effects by number only
-- (SEQ_SE_SP_001..051, SEQ_SE_SP_DECIDE); these were found by rendering all of them
-- (tools/bcsar.py) and cross-correlating each against a capture of Hone Sp. Atk with Magnemite
-- (Lv. 1, 49 s), with the music subtracted, then reading the video at each onset. r is the
-- match; times are seconds into the capture (the title appears at 5.20 s).
--
-- Events the capture does not show (a plain tap's shot and its hit, a miss, being hit,
-- blocking, the attacks, time running out) keep their stand-ins in src/training/regimen.lua.

return {
  -- the home screen: punching the bag has no sound in the game; the Regimens button and the shutters into the picker are one system sound
  -- (1.74 s: the close, the black and the fade); every shutter change plays it (T.goTo, the NaviPlay menu's card, the import screen's play button)
  transition = "se/sys_057",
  -- the Konami code's alley (ours, NaviPlay's own effects whatever the asset option)
  rocket_sting = "se/rk_sting",    -- the R appears (the code, the way into the alley)
  rocket_glint = "se/rk_glint",    -- its glint; the dealer showing up
  rocket_rain = "se/rk_rain",      -- the rain, looped while in the alley
  rocket_step = "se/rk_step",      -- a footstep down the alley
  rocket_buy = "se/rk_buy",        -- a sale
  rocket_open = "se/rk_open",      -- the shop slides open
  -- the picker
  select_course = "se/sp_decide",  -- the first tap on a course
  start_course = { "se/sp_decide", "se/sp_031" },   -- the second tap: two layered
  -- the intro
  pump = "se/sp_036",              -- each of the balloon's five pumps
  bot_name = "se/sp_033",          -- the balloon's name slides in
  play = "se/sp_037",              -- Start!: the clock starts
  -- shooting
  press = "se/sp_019",             -- a finger on the touch screen
  charging = "se/sp_024",          -- the charge, while the finger is held (a looping hum)
  shot = "se/sp_017",              -- a plain shot (a tap)
  charged_shot = "se/sp_016",      -- a charged shot (or the Energy Shot) let go
  goal_hit = "se/sp_021",          -- a plain shot on a goal
  charged_hit = "se/sp_015",       -- a charged shot on a goal
  goals_spawned = "se/sp_032",     -- a new group of goals
  -- the balloon's attacks
  attack_warn = "se/sp_034",       -- it winds up (looping, until it throws)
  attack_launch = "se/sp_035",     -- it throws (a random pitch each time)
  ball_flight = "se/sp_041",       -- a ball on its way (looping, while balls are in the air)
  -- the end
  clear = "se/sp_044",             -- the last goal: the balloon is beaten
  deflate_hiss = "se/sp_049",      -- the air leaking as it zigzags off
  deflate_burst = "se/sp_005",     -- the burst of puffs as it zips away
  star = "se/sp_007",              -- the twinkle as it vanishes into the sky
  -- the results
  result_next = "se/message",      -- a tap to the coach's next line (the game's message sound)
  result_jingle = "se/sp_046",     -- an Award / new best time, and a training bag received
  -- the bag drawer: one system sound for the button, a bag, every choice; another to close
  bags_open = "se/decide1",        -- the bag button (the drawer slides out)
  bag_select = "se/decide1",       -- a bag tapped, Use / Throw away / Back, Yes / No
  bags_close = "se/cancel1",       -- the drawer closed (its return, or a tap outside it)
  -- a regimen's exit: the first tap arms it (a second within the ring's time leaves)
  exit_arm = "se/sp_020",

  -- when the intro's sounds come, s after the title (the pumps' onsets 8.25 / 8.89 / 9.72 /
  -- 10.56 / 11.39 s, the name's 12.70 s, less the title's 5.20 s)
  INTRO = { PUMPS = { 3.05, 3.69, 4.52, 5.36, 6.19 }, BOT_NAME = 7.50 },

  -- capture 1: Hone Sp. Atk with Magnemite, 2026-10-12 (times in it, the title at 5.20 s);
  -- capture 2: an Azahar capture 2026-10-14, the home screen near the League (Victory Road's
  -- music subtracted) through a regimen with attacks to the results, with notes of what
  -- happens when
  EVIDENCE = {
    transition = "capture 2, 11.35 s, r 0.90-0.95: the Regimens button and the shutters (a system sound); INFERRED for the way back (the picker's shutters close, the home screen's open) and NaviPlay's own shutters: no capture shows them",
    select_course = "capture 2, 17.80 s, r 0.96: the first tap on a course",
    start_course = "capture 1, 1.26 / 1.30 s, r 0.70 / 0.67; capture 2, 23.85 / 23.88 s, r 0.69 / 0.62: DECIDE with SP_031 40 ms after",
    pump = "capture 1, 8.25-11.39 s, r 0.92-0.99; capture 2, 30.75-33.91 s, r 0.80-0.99",
    bot_name = "capture 1, 12.70 s, r 0.93; capture 2, 35.19 s, r 0.93",
    play = "capture 1, 17.02 s, r 0.80; capture 2, 39.51 s, r 0.72",
    press = "capture 1, 17.69 s, r 0.82: the first touch of a charged shot",
    charging = "capture 1, 17.69-19.11 / 20.99-21.34 s, r 0.69-0.95 every 0.355 s (its wave's loop)",
    shot = "capture 2, 43.43 / 45.03 / 50.82 / 51.99 / 54.73 / 56.90 / 57.97 / 58.77 s, r 0.75-0.94: Wooble's 'player shoot'",
    charged_shot = "capture 1, 19.69 s, r 0.98: the shot let go, a yellow burst over the screen",
    goal_hit = "capture 2, 55.10 s, r 0.89: Wooble's 'target hit'",
    charged_hit = "capture 1, 20.63 s, r 0.92: the charged shot lands on the balloon",
    goals_spawned = "capture 2, 52.86 s, r 0.87: Wooble's 'new targets appear'",
    attack_warn = "capture 2, 45.17-46.37 / 53.56-54.76 s, r 0.64-0.98 every 0.40 s: Wooble's 'balloon prepares to attack'",
    attack_launch = "capture 2, 48.06 s, r 0.45 (its random pitch keeps the match low): Wooble's 'balloon shoots back'",
    ball_flight = "capture 2, 48.50-50.18 s, r 0.78-0.91 every 0.42 s: Wooble's 'ball headed towards player'",
    clear = "capture 1, 21.76 s, r 0.97; capture 2, 59.24 s, r 0.87",
    deflate_hiss = "UNSETTLED: the game's hiss is a steady loop in both captures (capture 1 23.10-26.05 s, capture 2 60.5-63.55 s) that no rendered effect (SP, system, battle, field: 1,428) matches by waveform; SP_049 matched by average spectrum before the renderer applied changes made after a note began, and now fades over 1.7 s; kept as the nearest",
    deflate_burst = "capture 1, 26.10 s (spectrogram 0.84); capture 2, 63.57 s, r 0.52-0.59: Wooble's 'balloon pops and flies away'; its fade (to 0.19 by 0.9 s, 0.05 by 1.5 s) now matches both captures' (0.21 / 0.05)",
    star = "capture 1, 28.51 s, r 0.43; capture 2, 65.98 s, r 0.48: Wooble's 'star sound' (the quietest effect, volume 20)",
    result_next = "capture 2, 73.56 s, r 0.70: Wooble's 'normal dialogue continue' (SEQ_SE_MESSAGE; SELECT3, a 17 ms click, matched 0.44 before the renderer read MESSAGE's empty key ranges and its tempo)",
    result_jingle = "capture 2, 76.45 / 79.89 s, r 0.87 / 0.72: Wooble's 'Award / new best time' and 'training bag received'; capture 1 34.86 / 37.94 / 41.82 s",
    bags_open = "capture 3 (Wooble's, 2026-10-23), 5.22 s: SEQ_SE_DECIDE1, waveform r 0.74 (every other effect under 0.28)",
    bag_select = "capture 3, 7.89 / 9.60 / 11.37 s (bags tapped, a choice): SEQ_SE_DECIDE1, r 0.60-0.74",
    bags_close = "capture 3, 22.37 s: SEQ_SE_CANCEL1 (= SYS_070), r 0.83",
    exit_arm = "capture 3, 51.66 s (the exit's first tap, its ring closing in): SEQ_SE_SP_020, r 0.72 (every other effect under 0.13)",
  },
}
