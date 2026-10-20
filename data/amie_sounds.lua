-- Which of the game's own Pokemon-Amie sound effects (recipe kind "sfx": SEQ_SE_KW_*, rendered
-- from the player's card image into se/kw_<name>) plays when. Most are picked by the effect's own
-- name in the game's sound archive (sango_sound.bcsar); those marked [capture] were matched against
-- Wooble's captures 2026-10-20_09-45-09 (PLAY, the game picker, Berry Picker on Easy) and
-- 2026-10-20_09-52-06 (Head It on Easy):
-- each rendered effect cross-correlated with the capture's audio (r, times in the capture), see
-- EVIDENCE. A list plays one of its effects at random (the strokes vary).
-- An event missing here, or an effect not yet extracted, keeps its Emerald stand-in (G.se);
-- false = the game plays nothing there (a capture showed it), silent once the art is extracted.
--
-- The archive's names: ADDSCORE ALERT AWAKE BALL BALLFALL BALLFALLF BALLFALLS BECKON BELCH BONUS
-- BURN CANCEL CANCEL2 CLOSESWEET COMBO COMBO2-4 COMPLETE CORRECT COUNTDOWN1-2 DECIDE DECIDE2
-- DOORCLOSE DOOROPEN DRAW EAT EATSTICKY EATSWALLOW EATWILD ELSHOCK END ENTER ENTER2 FACE1 FACE2
-- FACESTART FAIL FALLING FALLSWEET FAULT FEVER FEVEREND FHEADGOOD FHEADOK FLOAT GIVE GIVEFAST
-- HEADFAIL HEADGOOD HEADOK HEART1-3 HIGHSCORE INJURE KNOCK LANDHEAVY LANDLIGHT LBALLFALL LEAVE2
-- LHEADFAIL LHEADGOOD LHEADOK NUMBER ONCEAGAIN PICK PILE RESULT ROLLUP SCORE SELECT SELECT2
-- SELGAME SELPLAY SELSWEET SETPANEL SLEEP SLIDEIN SMACK SNAP STAMP STAR START START2 START3 STOP
-- STROKE STROKE2-5 SWAP SWEET THINK TIME TIMEOVER TOUCH TOUCH2 VALUE1-3 ZOOM.
-- ADDSCORE, PILE and ROLLUP loop (rendered to 4 s; the caller stops them).

return {
  -- menus and buttons, everywhere in Amie
  select = "se/kw_select",          -- a tap on a button or an item; [capture] the picker's arrows
  select2 = "se/kw_select2",        -- turning a page / a wallpaper / a game on the picker
  decide = "se/kw_decide",          -- a choice confirmed
  back = "se/kw_cancel",            -- back, return, close

  -- the room
  room_menu = "se/decide1",         -- [capture] a tap on the Pokemon opens its menu (SEQ_SE_DECIDE1)
  room_button = "se/decide1",       -- [capture] the menu's buttons (DECORATE)
  touch = "se/kw_touch",            -- [capture] a finger lands on the Pokemon in PLAY
  switch_to = "se/kw_decide2",      -- SWITCH: another Pokemon comes in
  gift = "se/kw_bonus",             -- a gift box opened
  milestone_gift = "se/kw_bonus",   -- the Pokemon has something for you
  dance = { "se/kw_heart1", "se/kw_heart2" },   -- each step of its dance
  visitor_enter = { "se/kw_enter", "se/kw_enter2" },
  visitor_leave = "se/kw_leave2",
  visitor_talk = { "se/kw_face1", "se/kw_face2" },   -- a chat bubble pops up
  visitor_think = "se/kw_think",    -- the "..." bubble

  -- PLAY
  open_puffs = "se/kw_selsweet",    -- [capture] the Poke Puff button opens the drawer
  close_puffs = "se/kw_closesweet",
  open_games = "se/kw_selplay",     -- [capture] the play button opens the minigame picker
  pick_game = "se/kw_selgame",      -- [capture] a game's badge picked (SELGAME = DECIDE = DECIDE2)
  start_game = "se/kw_decide",      -- [capture] a difficulty picked: the game starts
  wake = "se/kw_face2",             -- [capture] tapped awake: it turns round
  doze = "se/kw_sleep",             -- it dozes off
  stroke = "se/kw_stroke",          -- [capture] every 8 frames while the finger moves on it
  heart = "se/kw_stroke",           -- [capture] a favoured spot strokes the same
  pet_reward = "se/kw_heart2",      -- petted enough: it hops for joy (Wooble: a sound plays with
                                    -- its cry; which, the capture could not settle; by name)
  pet_dislike = "se/kw_elshock",    -- [capture] a disliked spot (the hand's shock)
  burn = "se/kw_burn",              -- an effect spot: burning
  shock = "se/kw_elshock",          -- an effect spot: shocking
  hurt = "se/kw_injure",            -- other effect spots, and the recoil
  hit = "se/kw_smack",              -- tapped too fast: it feels hit
  high_five = "se/kw_snap",         -- the slap
  pull_puff = "se/kw_pick",         -- a puff pulled from the drawer (Wooble: a distinct pop;
                                    -- too quiet under the music to match; by name)
  offer_puff = "se/kw_draw",        -- [capture] held to it: the white flash into the close-up
  bite = "se/kw_eat",               -- [capture] each bite
  meal_done = "se/kw_eatswallow",   -- the last bite: hearts and a hop (Wooble: a sound plays with
                                    -- its cry; which, the capture could not settle; by name)
  refuse = "se/kw_fault",           -- it will not eat
  drop_puff = "se/kw_fallsweet",    -- a puff let go falls away

  -- DECORATE (capture 5: the game's general effects, none of Amie's own)
  deco_tab = "se/decide1",          -- [capture] the Interior Items / Poke Puffs pills
  drawer_open = false,              -- [capture] the drawer slides out silently (the pill's sound)
  hold_item = "se/catch",           -- [capture] an item or puff taken into the finger
  place_item = "se/release",        -- [capture] let go in the room
  place_puff = "se/release",        -- [capture] a puff let go: it goes to the middle
  put_back = "se/release",          -- [capture] let go on the tray
  select2 = false,                  -- [capture] the wallpaper arrows: no sound
  deco_done = false,                -- (the check: nothing matched in the capture)

  -- the minigames, shared
  countdown = "se/kw_countdown1",   -- 3, 2, 1
  go = "se/kw_start",               -- [capture] START! (Berry Picker's READY has none)
  time_up = "se/kw_timeover",
  stamp = "se/kw_stamp",            -- [capture] the HIGH SCORE stamp
  puffs = "se/kw_sweet",            -- [capture] the smoke clears on the Poke Puffs won
  results = false,                  -- [capture] no chime when a game ends (each card has its own)
  again = "se/kw_onceagain",        -- Play Again
  quit = "se/kw_cancel",

  -- Berry Picker
  berry_pick = "se/kw_pick",        -- [capture] a berry taken from the tree
  berry_give = "se/kw_give",        -- [capture] the right berry handed over
  berry_rise = { "se/kw_enter", "se/kw_enter2" },   -- [capture] an asking Pokemon rises into view
  berry_leave = "se/kw_leave2",     -- [capture] it drops out of view
  berry_time_up = "se/kw_end",      -- [capture] TIME'S UP (END, not TIMEOVER)
  berry_give_fast = "se/kw_givefast",
  berry_wrong = "se/kw_fail",       -- the wrong berry, or it gave up waiting
  berry_drop = "se/kw_fallsweet",   -- a berry let go falls
  berry_rain = "se/kw_falling",     -- the berries rain down at the end
  berry_land = "se/kw_landheavy",   -- the heap lands

  -- Head It
  head_good = "se/kw_headok",       -- [capture] a good heading
  head_just = "se/kw_headgood",     -- [capture] a just heading
  head_good_fever = "se/kw_fheadok",    -- (the F ones match the same moments as closely)
  head_just_fever = "se/kw_fheadgood",
  head_miss = "se/kw_headfail",     -- [capture]
  giant_good = "se/kw_lheadok",
  giant_just = "se/kw_lheadgood",   -- [capture]
  giant_miss = "se/kw_lheadfail",
  giant_fall = "se/kw_lballfall",   -- [capture] the giant ball drops
  giant_alert = "se/kw_alert",      -- [capture] "!!" for the giant to come
  head_leave = "se/kw_leave2",      -- [capture] TIME'S UP: the side Pokemon leave
  head_time_up = false,             -- [capture] TIME'S UP itself is silent
  fever = false,                    -- [capture] FEVER: no effect; its music rises 2 semitones
  combo3 = "se/kw_combo",           -- [capture] a combo begins: its 3-hit popup
  combo10 = "se/kw_combo2",         -- [capture] the 10-hit combo
  combo50 = "se/kw_combo3",
  combo100 = "se/kw_combo4",

  -- Head It's RESULTS card
  results_card = "se/kw_number",    -- [capture] the card comes in
  result_add = "se/kw_addscore",    -- [capture] a bonus row counts into TOTAL (a loop, stopped)
  result_row = "se/kw_score",       -- [capture] ...and settles
  rank_high = "se/kw_value3",       -- [capture] the stars: five
  rank_mid = "se/kw_value2",        -- (by name: three or four)
  rank_low = "se/kw_value1",        -- (by name: fewer)

  -- Tile Puzzle
  tile_select = "se/kw_float",      -- [capture] the first tile of a swap lifts
  tile_swap = "se/kw_swap",         -- [capture] the second: they swap
  tile_home = "se/kw_setpanel",     -- [capture] a tile lands in its place
  tile_shuffle = "se/kw_setpanel",  -- [capture] each tile landing in the opening shuffle
  tile_go = "se/kw_start3",         -- [capture] Tile Puzzle's START!
  puzzle_done = "se/kw_star",       -- [capture] the picture whole (not COMPLETE)
  view = "se/kw_draw",              -- View Picture
  EVIDENCE = {
    open_games = "capture 6.89 s, r 0.93 (SELPLAY; DECIDE 0.91)",
    pick_game = "capture 16.05 s, r 0.91 (DECIDE = SELGAME = DECIDE2, one waveform; SELPLAY 0.89)",
    start_game = "capture 18.47 s, r 0.62 (DECIDE; SELPLAY 0.64, under the music)",
    select = "capture 10.42 / 12.05 s, r 0.51 / 0.52: the picker's arrows (SELECT2 0.51)",
    wake = "capture 3.86 / 118.24 s, r 0.73 / 0.60: the turn after the tap (no AWAKE)",
    berry_pick = "capture 41.67-91.95 s, 14 picks, r 0.78-0.99",
    berry_give = "capture 34.08 / 59.29 / 86.20 / 90.18 / 90.95 s, r 0.50-0.58 (under the music)",
    berry_rise = "capture 21.57 s ENTER2 r 0.49 (the demo), 63.10 / 84.60 s ENTER r 0.62 / 0.63",
    berry_leave = "capture 28.42 s, r 0.49",
    berry_time_up = "capture 92.78 s, r 0.73",
    go = "capture 31.42 s, r 1.00; no countdown sound under READY",
    stamp = "capture 103.56 s, r 0.77 (STAR 0.53 at 103.85 s rides on it)",
    puffs = "capture 104.88 s, r 0.76",
    head = "capture 2: hits 10.22-74.17 s HEADGOOD / FHEADGOOD r 0.71-0.83 (just), HEADOK / FHEADOK 0.55-0.77 (good); HEADFAIL 34.79 / 43.98 / 70.19 / 71.22 r 0.82-0.93; START 13.35 r 0.90; COMBO 23.49 / 40.80 / 49.73 r 0.47-0.60 as a combo reaches 3 (the 3-HIT popup at 40.5), COMBO2 32.58 / 60.36 r 0.49 / 0.46 at 10 hits; time up 74: ALERT 74.59 r 0.38, LEAVE2 74.77 r 0.52, no TIMEOVER / END; LBALLFALL 76.11 r 0.81, LHEADGOOD 76.74 r 0.69; NUMBER 77.14 r 0.66, ADDSCORE 78.14 / 79.71 r 0.76, SCORE 78.71 / 81.39 r 0.70-0.74, STAMP 82.54 r 0.85, VALUE3 82.93 r 0.68 (five stars), SWEET 84.03 r 0.86; nothing at FEVER's start or end",
    decorate = "capture 5 (amieroom-decorate-sound): no SEQ_SE_KW at all (< 0.45); SEQ_SE_DECIDE1 15.74 (the room's menu) / 18.38 (DECORATE) / 30.35 / 40.96 (the pills) r 0.59-0.63; SEQ_SE_CATCH 32.86-53.05 s r 0.56-0.85 at each grab; SEQ_SE_RELEASE 35.24-54.52 s r 0.56-0.83 at each let-go (the tray too); the wallpaper arrows, the drawer, the check: nothing consistent (< 0.47)",
    play = "capture 4 (playsound): TOUCH 2.90 / 4.34 / 6.04 / 7.38 / 21.81 s r 0.87-0.95 as a finger lands; STROKE (the first only) every 0.267 s while stroking, 10.38-12.52 / 42.98-44.85 s, r 0.45-0.91; ELSHOCK 17.09 r 0.53 (a disliked spot, the hand's shock); SELSWEET 23.74 / 33.13 r 0.91 the drawer; DRAW 26.19 / 35.45 r 0.94 the offered puff's flash; EAT x3 per puff 0.47 s apart r 0.96-0.98; at the meal's end, the reward's hearts and a puff pulled out Wooble hears a sound (with the cry; a pop) that nothing matched: waveform < 0.49 over all 1,500 effects (KW, SYS, FLD, DEMO, BT, moves), a spectral match at the onsets only found the cry's noise (FLD_141 / W035 / DEMO_065 alike, 0.74-0.79); the city music subtracted did not help; PLAY has no music of its own (the overworld's plays on)",
    tile = "capture 3 (PuzzleSound): Begin DECIDE 21.84 s r 0.45-0.47; the shuffle SETPANEL 22.25-24.05 s r 0.51-0.73; START! START3 24.13 r 0.78; a first tile FLOAT r 0.50-0.84, ~1 s before SWAP r 0.57-0.79, then SETPANEL r 0.62-0.85 as it lands home (CORRECT 0.48-0.62 at the same instants); the picture whole STAR 62.00 r 0.63; STAMP 63.34 r 0.82; SWEET 64.67 r 0.80",
    MUSIC_TILE = "Tile Puzzle plays SEQ_BGM_KW_GAME03 throughout (0.944-0.963), x1.00, no key change",
    MUSIC_HEAD = "Head It plays SEQ_BGM_KW_GAME02 (notes 0.966 / 0.954 outside FEVER); FEVER plays it 2 semitones up and x1.12 faster together (chroma rotated +2: 0.931-0.945 in every FEVER window vs 0.887-0.917 unrotated): a pitch of 2^(2/12) on the same voice. No speed-up on the clock",
    MUSIC = "Berry Picker plays SEQ_BGM_KW_GAME01: its notes (chroma) match the capture's 20-110 s at 0.939 (GAME02 0.893, GAME03 0.877)",
  },
}
