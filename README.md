# PlayNav: Pokémon-Amie and Super Training

PlayNav (mod id `play_nav`; it was `ds_touch` before 0.3.0) is a DS-style bottom touch
screen for [gen1recomp](https://github.com/poooooby/gen1recomp) whose
job is **Pokémon-Amie** (the X/Y and Omega Ruby/Alpha Sapphire play rules), Sun/Moon style care
after a battle, and the touch minigames that follow. Open it from the START menu or accept the
care prompt after a battle: your Pokémon appears on the bottom screen, you pet it where it likes
to be petted, feed it Poké Puffs bite by bite, clean off the mud a battle left and cure a status.
Affection earned here gives real bonuses in battle. The top screen keeps playing as before.

Battle commands, the bag and the pad are **not** this mod's business; Kanto Gear handles those.
The touch screen stays dormant until a session (or a future minigame) needs it, so a mod that
owns the bottom screen keeps it the rest of the time.

Gen 3 (Emerald, FireRed, LeafGreen, Ruby, Sapphire) is the target. The mod also loads on Gen 1/2,
where only the surface plumbing is active.

## How it plays

1. **START menu > AMIE** opens the Amie room: your active Pokémon wanders about, plays when
   it is happy, naps with a status, and stops to ask for food when it is starving. Tap it for
   **DECORATE / PLAY / SWITCH**; SWITCH picks another party member, who is remembered. After a battle, if the Pokémon that was
   out got dirty (chances follow what happened: damage, wild grass, a Water-type foe) or carries
   a status, both screens ask **"TORCHIC could use some care. Refresh?"**. YES opens play, NO (or
   B) returns to the field. The field and the post-battle script wait until you answer.
2. **The tray** along the top shows the cleaning tools and MEDIC only while they are needed
   (towel for mud, brush for dust, dryer for water, comb for ruffled fur; medicine cures with a
   tap), and PUFFS always.
3. **Petting.** Stroke the Pokémon with no tool selected. Every species has a spot it loves and
   a spot it dislikes (Pikachu: under the chin, not its stomach), and some have spots you should
   not touch at all: a Charmander's tail flame burns, Pikachu's cheeks shock, Regice freezes,
   blades cut. Hearts show the affection gained, a music note means none (a Pokémon with low
   enjoyment stops gaining). Until a Pokémon has any affection every spot counts as neutral.
   Rubbing too fast is scrubbing, not petting.
4. **Poké Puffs.** PUFFS opens a row of the varieties you own with their counts, six per page with
   arrows. Drag one onto the Pokémon and **hold it there**: it eats in three bites, slower when
   nearly full. Pull it away early and it only got the bites so far. A full Pokémon (255) turns
   away; Metapod, Kakuna, Pineco, Silcoon, Cascoon and Shedinja never eat.
5. **Hit and high-five.** Two quick taps on the same place is a hit (it costs enjoyment). Rest a
   finger beside the Pokémon for five seconds, once it has 5 affection, and it high-fives you.
6. The top screen shows the name, status, the three meters the game names (**Affection**,
   **Fullness**, **Enjoyment**, five icons each) and a message box. DONE (or B) saves and
   releases the field.

Every 50 affection (not 250) the Pokémon dances with hearts and two cries; at 255 three. At 25,
50, 75, 100, 150 and 255 affection it leaves you a present in the room ("You and TORCHIC are
looking close! Found a Leaf Cushion!"; at 255 "You'll be friends forever with TORCHIC!").

With the Alpha Sapphire card supplied (see below) the words on these screens are the game's
own: Poké Puff and Décor names, the status words, the prompts, the minigames' HUD and result
lines and rank titles. Without it the mod's own wording stands in.

## The stats, with the games' numbers

Affection, fullness and enjoyment run 0..255 per Pokémon, in the mod's own save data (keyed by
personality and OT id; the game's friendship stat is untouched). Levels are 0 / 1 / 50 / 100 /
150 / 255 points. Every number lives in `data/amie_rules.lua`:

| Event | Affection | Fullness | Enjoyment |
| --- | --- | --- | --- |
| Pet a normal spot (enjoyment 20-34 / 35-49 / 50+) | +1 / +2 / +3 | | −20 / −35 / −50 |
| Pet a favored spot (enjoyment 16-41 / 42+) | +1 / +3 | | −16 / −42 |
| Pet a disfavored spot | 0 | | −20 |
| Whole puff: Basic / Frosted / Fancy / Deluxe / Supreme seasonal / Wish, Honor | +2 / +3 / +4 / +5 / +6 / +10 | +50 | |
| Bite of an unfinished puff | | +16 (per bite of three) | |
| Enter a battle with the active Pokémon | | −10 | +5 |
| 50 steps | | −1 | +1 while below 70 |
| Hit | | | −5 |
| High-five | | | +10 |
| Open play | | | +10 |

Puffs: 10 Basic to start, one random variety per battle won (option; Basic most often, then
Frosted, Fancy, Deluxe and the seasonal Supremes), a jar of 100 with the oldest lost first.

## The minigames

GAMES in the play tray opens the picker ("Which game do you want to play?") when three party
members are healthy (no status, not fainted; the game's line: "You need three Pokémon in good
condition."): the active Pokémon plus the two with the least enjoyment play. Each game has Easy,
Normal, Hard and Unlimited; three stars on one difficulty unlock the next, and the result screen
hands out Poké Puffs by rating (Basic on Easy, Frosted on Normal, Fancy on Hard, Deluxe on
Unlimited, with the game's Supreme seasonal puff for five stars on Unlimited). Every participant
loses 110 fullness and gains 80 enjoyment per game (30 for an Easy or Normal Tile Puzzle).

- **Berry Picker**: one to three Pokémon pop out of the grass asking for a berry; drag the right
  one from the heap before the ring runs out. Three berry kinds on Easy, five on Normal, seven on
  Hard; 60 seconds, or three misses on Unlimited. Ratings at 5 / 10 / 15 / 20 / 30 / 40 berries.
- **Head It**: yarn falls over one, two, then three Pokémon; tap one when the ball is in the sweet
  spot above its head (3 points, marked by a star on Easy and Normal) or a little early or late
  (1 point). A combo of 5 (Easy) or 15 hits starts FEVER (double points), every tenth hit adds a
  bonus, a big ball drops at the end for up to 50, and the longest combo is added to the score.
  The result adds it up the game's way: Heading Points + Last Combo Record + Big Yarn Bonus =
  TOTAL. Unlimited shows its three Chances as balls of yarn.
- **Tile Puzzle**: a moving picture of the three Pokémon is cut into 5x4, 6x5 or 8x6 tiles and
  every tile is swapped once; tap two tiles to swap them back. Rated by time (Easy: a minute for
  one star, 15 seconds for five). Unlimited chains Easy, Normal and Hard puzzles against a
  30-second clock that every second correct tile and every finished puzzle top up.

Unlocking a difficulty and five-star runs also leave décor gifts on the room's floor. The
result card shows each Poké Puff won on the ring of its tier, the stars and the rank title
("Berry Amateur" ... "Magnificent Berry Master"), and "You can now access the next rank!".

## Decorate and visitors

**DECORATE** (tap your Pokémon in the room) opens a drawer along the bottom: WALL lists the
wallpapers you own (tap to apply), CUSHION and OBJECT the items (drag one up into the room to
place it, up to 30; drag a placed item to move it, or down into the drawer to put it away), PUFF
sets a Poké Puff out for visitors (changing it sends the current visitors home, as the game
warns). The catalogue is the games' full set, 34 wallpapers and 172 items in sets A to F
(colours, patterns, clouds, the 18 types, classy), named as the game names them; you start with
the same eleven pieces as in X/Y. Your Pokémon likes to sit on a placed cushion.

While the room is open, **visitors** drop by one at a time from the species your Pokédex has
seen (plus your party). Each decides whether to stay (half the time with no puff out; 65 / 80 /
90 / 95 / 100 % with a Basic / Frosted / Fancy / Deluxe / Supreme puff, which lasts 1 / 2 / 3 /
4 / 5 groups, 7 for Wish and Honor). When three have stayed they chat for thirty seconds, with
"?", "...", "!", notes and hearts hinting at the gift, then leave a present and go. The gift set
follows their combined affection (A to F), never below the set-out puff's minimum (Deluxe: B,
seasonal Supreme: C, Wish or Honor: D); three Pokémon of one type give that type's seven items,
three of one evolutionary line give anything. Up to six presents wait on the floor; tap one to
open it ("You got a Campfire Object from PIKACHU, EEVEE, and TORCHIC!"). Gifts you are owed by
affection milestones, newly unlocked difficulties and five-star runs appear there too. A set you
have completed yields a Poké Puff of the matching tier instead.

## Affection benefits in battle

On by default (option AFFECTION BENEFITS), skipped in link, facility and tutorial battles:

- 2 hearts: 1.2x experience.
- 3 hearts: the Pokémon may endure a knockout at 1 HP (10%, 15% at 4 hearts, 20% at 200
  affection, 25% at 5 hearts). "TORCHIC toughed it out to show its best side to COLLIN!"
- 4 hearts: 20% to shake off a status at the end of the turn, with the per-status line.
- 200 affection: the foe's accuracy drops 10 points (moves that cannot miss are unaffected).
- 5 hearts: critical-hit chance doubled.

## Super Training

The X/Y and ORAS EV trainer, a sibling of Amie on the same two screens. **TRAINING** on the
Gen 3 START menu opens Core Training: the lead Pokémon stands beside its training bag on the
touch screen with the **Effort-o-Meter** (green: the species' base stats, yellow: its EVs up to
252 per stat, the column: the 510 total), the party strip to switch Pokémon, **REGIMENS** and
**BAGS**. Tap the bag (or press A) to hit it; the Pokémon hits it once a minute on its own, lies
down for a rest now and then, and a tap wakes it with a second wind that halves the hits a bag
needs. Tapping the empty black bag can drop a bag. The rack holds twelve.

The 26 bags follow the games: HP / Attack / Defense / Sp. Atk / Sp. Def / Speed bags in S, M and
L (10 / 25 / 50 hits for +1 / +4 / +12 EVs), the Reset Bag (100 hits, EVs to zero), the Soothing
Bag (250 hits, +20 friendship) and the one-regimen bags Big-Shot, Double-Up, Strength,
Swiftness, Toughen-Up and Team Flare (10 hits; one pending effect at a time, spent by the next
regimen). A cleared regimen always gives one bag of its stat (bigger with a faster clear) or a
Double-Up (more often with Pokérus); a time-out gives a support bag.

**Super-Training Regimens** play on the top screen with the touch screen as the aiming pad:
tap to shoot an Energy Shot at the white goals on the Balloon Bot, hold to charge (three
stages, 3x points at the top, hold too long and the Pokémon stalls), move with the d-pad
(left / right across the pitch, up / down nearer or farther), block with L or the BLOCK button. Goals turn yellow after 8 s and vanish at 12 s;
clearing a group can bring the red Chance Goal; the balloon grows with every goal; the bot's
attacks are telegraphed by a red aura (rapid balls, big balls, rings, homing balls, crosses,
waves, a barrier whose yellow marker breaks it, bit balloons that block shots and fire back);
getting hit costs points. The round energy meter is what the game's coach explains: a shot
fired with the meter full becomes the species' **Energy Shot**; before that it is a plain ball
worth less the emptier the meter, and a nearly dry meter gives a weak ball. Each shot spends
energy and it refills with time. Each species has its Energy Shot colour (black average, yellow
rapid-fire that sprays while held and bursts seven at full charge, orange big, green slow and
strong, blue fast and small). Bitbots regenerate if left alone; Aegislash rages and Roserade
calms past 2,400 points; Aerodactyl flies up and down; Probopass's goals keep moving. EVs matter: Attack / Sp. Atk raise the points per goal, HP grows
the shot and softens hits, Defense / Sp. Def fill guts faster and lengthen the block, Speed
moves and shoots faster.

Eighteen regular courses (Lv1 +4, Lv2 +8, Lv3 +12 EVs) with the games' Balloon Bots and
scores (Wailmer 500 ... Wailord 4000, Noivern 2000); Lv2 opens once all six Lv1 courses are
cleared by any Pokémon, Lv3 after Lv2. Every course runs a 3:00 clock; an **Award** (the
game's word; the result screen shows "Target Time Remaining") needs the time left at the pop
to reach the course's target (2:30 for Lv1, 2:00 for Lv2 and Lv3, 1:30 for most secret
courses). The course names, blurbs, level headings, result screen and the coach's praise are
the game's own text, decoded from your card like the art; our wording stands in without it. At 510 EVs a Pokémon is **Fully Trained** (kept after a Reset Bag) and
the twelve **Secret regimens** open one after another: circuits with +30 s per popped bot, no
EVs but a bag and an item (Wings, Stardust, Hard Stone, drinks, PP Up / PP Max, evolution stones
on a new best time), Hydreigon's sudden death, Aegislash raging and Roserade calming at 2400
points, the Aron line and Mega Aggron at the end. Medals on all thirty make it **Supremely
Trained**.

The six stat **Wings**, the Pretty Wing and the Dusk, Shiny and Dawn Stones did not exist in
Gen 3; the mod registers them as items 400-409 (bag, mart, save), with their icons and text.
A Wing used from the bag raises one EV by 1 within the 252 / 510 caps. The three stones are
registered under their own ids (ST_DUSK_STONE and so on) so that a mod which brings the real
Gen 4 stones with their evolutions, such as national_dex_gen3, keeps the plain ids; when that
mod is installed, a stone won in a secret regimen is its stone.

Numbers with a public source (bag hits and EVs, course bots and scores, EVs per level, the
unlock ladder, the goal timings, the 3x charge, the seven-shot burst, the shot colours) are
marked verified in `data/training_rules.lua`; the ones no guide states (points per goal, point
loss per hit, energy and charge timings, bag and prize odds, attack schedules) are provisional
and marked as such, with the reasoning, so they can be corrected without touching the code.


Tap a regimen in the list to see its card on the top screen: the course badge, its name,
the game's own description of it, the EVs it gives, the target time and your best. START
(or tapping it again) begins it.


Each Balloon Bot is the course's Pokémon itself: its sprite blown up in balloon blue, with
the goals sitting on its body. Goals start on their part of it (head, arms, tail) and travel
over the sprite, never off it; on moving parts, at higher levels and on the fleeing and
roaming courses they move faster and further. A Pokémon the game has no sprite for keeps the
round course badge.

## Real Pokémon-Amie art from your own Alpha Sapphire

Supply a **decrypted Pokémon Alpha Sapphire (USA) Rev 2 card image** (`.cci`, exactly 2 GiB,
MD5 `0563f9dee1b95de32d579e40c20e2bfc`) in the launcher: open the mod, **Imported files**,
**Choose file**. The launcher validates it and copies it into the mod's private folder (about
25 seconds of hashing on a PC; Android hashes while it streams). On the next game start the mod
extracts about 600 textures and thirteen text files in background jobs (a few seconds) with a
progress panel on the touch screen, then says the ROM copy can be removed under Imported files.
From then on play uses the Amie hand cursor, Poké Puffs, emote bubbles, the room's PLAY /
DECORATE / SWITCH buttons, the status icons, the minigame art, HUD digits and result pieces, the
whole décor catalogue and the game's own English words for Amie and Super Training; without the
file the drawn shapes and our wording stay (décor items become labelled blocks). Nothing from the ROM is ever part of this mod: it ships only `data/oras_recipe.lua`
(which archive, entry and texture index) and pure-Lua decoders for the 3DS containers (NCSD,
NCCH, RomFS), GARC archives, LZ11 and BCLIM textures including ETC1. Players never need ctrtool,
bclimtool or any PC step. `tools/README.md` describes the development pipeline that produced the
recipe.

## Sharp at any size

PlayNav draws its own two screens, the touch screen and its top screens for Amie and Super
Training, at your display's real resolution. The game's 3DS art is smoothed when it is
shrunk and when it is enlarged, the way the 3DS shows it, instead of being squeezed onto a
low-resolution grid and blown up in blocks. Pokémon sprites and icons stay pixel-sharp: at
whole multiples they are drawn pixel for pixel, and at in-between sizes each pixel keeps
its hard square with only a one-screen-pixel blend at its edge, so no rows come out doubled.
Text is crisp at any size, and a line too long for its box wraps inside it and shrinks to
fit rather than running past the edge. The overworld, battles and every other screen of the game are
untouched. Turn HD RENDERING off for the plain low-resolution look.

## Options (Mod Manager)

| Option | Values | Notes |
| --- | --- | --- |
| POKEMON-AMIE | on / off | the whole feature |
| DIRT AFTER BATTLE | OFF, LOW, NORMAL, HIGH | how often marks appear |
| ASK AFTER EVERY BATTLE | on / off | prompt even when the Pokémon is clean |
| PUFFS PER WIN | 0..3 | Poké Puffs granted after a won battle |
| AFFECTION BENEFITS | on / off | the battle bonuses above |
| SUPER TRAINING | on / off | the TRAINING entry and Core Training |
| TOP SCREEN PICTURE | SMALL, LARGE | size of the Pokémon on the top screen |
| TOUCH SCREEN | AUTO, SECOND SCREEN, SPLIT SCREEN, OFF | where the surface goes; AUTO uses a detected second display, else splits |
| SHOW TOUCH SCREEN | WHEN NEEDED, ALWAYS | WHEN NEEDED keeps it dormant outside a session |
| SPLIT SIZES | AUTO, 3DS, EQUAL, 3DS FLIPPED, MAX GAME, MAX TOUCH | split screen: AUTO keeps the picture as large as a 1x surface allows; 3DS puts the play screen one scale step above the touch screen; EQUAL gives both the same scale (the DS look); 3DS FLIPPED puts the touch screen one step above; MAX GAME / MAX TOUCH give one side everything it can take |
| GAME SCALE | AUTO, 1X..6X | split screen: pin the picture's scale; the surface fills the rest |
| TOUCH SCALE | AUTO, 1X..6X | split screen: pin the surface's scale; the picture fills the rest |
| GAME SHARE % | 35..80 | split screen, AUTO only: the most of the height (portrait) or width (landscape) the picture may take |
| BOTTOM SAFE PX | 0..200 | room for an Android gesture bar |
| HIDE VIRTUAL PAD | on / off | hide the engine pad while the surface is active |
| 2ND SCREEN SCALE | 1..6 | integer upscale of the frame pushed to the second display |
| DEV: SCRATCH APP | on / off | a free-touch demo app with a pointer readout |
| EXTRACT AMIE ART ON BOOT | on / off | start the extraction automatically when the card image is present |
| USE EXTRACTED ART | on / off | draw with the Alpha Sapphire textures when they are in the cache |
| HD RENDERING | on / off | draw PlayNav's two screens at your display's full resolution (on by default) |

## Where the surface lives

- **Second display** (AYN Thor through the engine's SecondScreen bridge; a companion window on
  Windows / Linux / macOS): the game window is untouched, the 256x192 surface is pushed as a
  frame and its touches come back. One pointer, no pressure, every move event preserved.
- **Split** on a single screen (phones, a PC window): the game picture and the surface are
  stacked in portrait and placed side by side in landscape. The mod picks the largest integer
  scale for the picture that still leaves the surface at least 1x (a 1080-wide phone shows the
  picture at 4x over a 4x surface; a 720-wide one 3x over 2x; a 1280x720 PC window a 3x picture
  beside a 2x surface), centres the pair, and hands the picture area to the engine, so the two
  never overlap and both follow the window size. SPLIT SIZES switches between that AUTO rule,
  3DS (play screen one step larger, like a 3DS), EQUAL (the DS look), 3DS FLIPPED (touch screen
  one step larger), MAX GAME and MAX TOUCH; GAME SCALE and TOUCH SCALE pin one
  side's scale and the other fills the rest; GAME SHARE % (default 60) caps the picture in AUTO.
  A pinned scale that does not fit is clamped so the pair still fits. Pressure and multi-touch work here.

## For other mods and future minigames

`mod.find("play_nav").exports` gives:

- `pointer` - the stream: `pointer:each()`, `pointer:get(id)`, `pointer:on(fn)`, helpers
  `pointer.isTap(rec)`, `isHold(rec, secs)`, `swipe(rec)`, `speed(rec)`. Records carry `x, y,
  vx, vy, travel, path, pressure`.
- `apps:register({ id, title, draw(G, w, h), update(dt, game), pointer(ev, rec, game),
  wantsSurface() })` - an app on the surface. Return `true` from `wantsSurface` while you need
  the screen and it wakes; the app area is 256 x (192 - tab strip) in logical units.
- `amie.open(mon)` (the room), `amie.openPlay(mon)`, `amie.state()`, `amie.puffs()` (the jar),
  `amie.meters(key)`, `amie.rules` (the pure rules and `PUFFS`), `amie.petting`, `amie.care`,
  `amie.store`, `amie.session` (`enterPlay`, `enterGames`, `enterDecorate`, `startGame(id,
  diff)`, `switchTo`), `amie.games` (ratings, rewards, participants), `amie.decor` (the
  catalogue, placement, gift rolls), `amie.visitors` (`force`, `claim`, `pending`), `amie.benefits`. `exports.refresh` is the same
  table under the first release's name.
- `layout`, `W`, `H`, `state()`.

## Developing

The repo root is the mod root; link it into the engine as a directory junction:

```bat
mklink /J C:\Users\<you>\Documents\GitHub\gen1recomp\mods\play_nav C:\Users\<you>\Documents\GitHub\g1r-ds-touch
```

Headless suites (from the engine root): `luajit mods/play_nav/tests/<name>.lua` for
`amie_rules_test` (every row of the table above), `petting_test`, `games_test` (ratings,
rewards, unlocks, participants), `decor_test` (the catalogue, placement, puff out, gifts),
`care_test`,
`refresh_flow_test` (the whole session against a fake host), `layout_test`,
`play_nav_loads_test` (Gen 3 loads, Gen 1 and 2 skip), `pointer_stream_test` (skips: Gen 3 only), `rename_test`, `import_fixtures_test` (synthetic card image in
`tests/fixtures/`, no ROM bytes), `oras_local_test` (the real dump, skips when absent),
`training_rules_test`, `training_courses_test`, `training_sim_test` (the regimen, seeded) and
`training_flow_test` (Super Training against a fake host). For
in-game testing hard-link the dump to `baseroms/alpha_sapphire_rev2.cci` with a receipt;
`baseroms/` is git-ignored and must be absent for `modkit pack` (rule MK307).
Static checks: `python3 tools/modkit.py validate mods/play_nav --base imported`, `lint`,
`gen3check`. `python tools/petting_table.py` regenerates `data/petting_gen3.lua` from Bulbapedia;
`python tools/decor_catalog.py <garc_all/index.json>` regenerates `data/decor_catalog.lua` and the
recipe's décor block from the dump layout.

Real window on Emerald (captures PNGs into `SHOT_DIR`):

```sh
SHOT_DIR=/tmp/play_nav POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
POKEPORT_DRIVER=mods/play_nav/tests/drivers/emerald_shot.lua love .
```

The driver opens AMIE from the START menu (the room, PLAY, BACK, SWITCH, CLOSE), fights,
declines the first prompt, poisons the lead, fights again, accepts, cleans every mark, cures,
pets, feeds a puff bite by bite, pets a favored and a disfavored spot, hits, opens the minigame
picker and plays a few seconds of each game, decorates the room (a cushion, a wallpaper, a puff
set out), forces a visitor group and opens its present, finishes, fights once more with affection pinned to
255 to exercise the benefits, then checks the field moves again and the second display receives
frames. `tests/drivers/games_probe.lua` is a short probe of the game loop alone;
`tests/drivers/split_probe.lua` cycles the SPLIT SIZES presets at three window sizes and logs
where the picture and the surface land. `tests/drivers/training_probe.lua` opens TRAINING from
the START menu, hits a bag to completion on the touch screen, plays a regimen with the pad and
the aiming pad, checks the EVs on the party record, and uses a Health Wing from the bag.

## Known limits

- Gen 3 has no `input.pointer` seam, so single-screen touch there is routed by wrapping the
  engine's touch controls, and a plain desktop mouse by wrapping the Gen 3 mouse handlers
  (`engine_internals`). While a mouse button is held on the surface the cursor is also polled
  every frame, so a drag registers with or without `POKEPORT_TOUCH`.
- Petting spots are coarse zones over the front sprite (head, face, cheeks, chest, belly, side,
  limbs, bottom) mapped from Bulbapedia's text, so "left ear" and "right ear" both land on the
  head. Every Pokémon takes three bites of a puff: Gen 3 has no species size table.
- A cleaning stroke may start anywhere below the tray; petting, hits and medicine need the
  finger on the Pokémon. Marks sit on an ellipse over the sprite body, not on its pixels.
- Enduring a hit, dodging and shaking off a status change battle outcomes. Turn AFFECTION
  BENEFITS off for vanilla battles. Confusion self-hits are not endured.
- On Windows, Linux and macOS the engine's companion window for the second display sends only
  press and release, so in SECOND SCREEN mode on a desktop a tool registers taps but not
  strokes. Use SPLIT SCREEN on a desktop; the AYN Thor's own second panel sends every move.
- With Kanto Gear also pushing to the Thor's second display, the two mods take turns during a
  session; keep SHOW TOUCH SCREEN on WHEN NEEDED so the surface releases afterwards.
- Gen 1/2 get the surface plumbing only; Amie needs a Gen 1/2 host adapter.
- Azahar `.zcci` files cannot be accepted yet: their metadata carries a creation timestamp, so
  no MD5 can match, and reading them needs a zstd decoder the engine does not have. Supply the
  raw `.cci`. Ultra Moon is over the engine's 2 GiB import cap.
- Deleting the ROM copy after extraction is a manual step in Imported files; no mod API exists.
- Super Training's Balloon Bots are the ORAS course badges (every course has one); the
  regimen's scoring, damage, energy and attack timings are provisional (see the section above).
- The ten new items live at ids 400-409; a save that holds them shows them as numbers when the
  mod is removed.

## Credits

The petting spots (`data/petting_gen3.lua`), the décor names (`data/decor_catalog.lua`, three
pairs put in the game's own order) and the stat, minigame and benefit tables are derived from
[Bulbapedia](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon-Amie) (articles
"Pokémon-Amie", "Petting", "Poké Puff", "Affection", "Berry Picker", "Head It", "Tile Puzzle",
"Super Training", "List of Pokémon by Super Training Energy Shot",
"List of Pokémon-Amie Décor items"), text available under
[CC BY-NC-SA 2.5](https://creativecommons.org/licenses/by-nc-sa/2.5/).

Super Training's course and bag tables also draw on the Japanese guides pente.koro-pokemon.com,
the ORAS atwiki and gamepedia.jp, and on the ORAS Wiki. The Wing and stone icons are from
[pokesprite](https://github.com/msikma/pokesprite) (MIT); their names and descriptions from
[PokeAPI](https://pokeapi.co).

## Renamed from ds_touch

Up to 0.3.0 the mod's id was `ds_touch`. The engine keys save data and Mod Manager options
by id, so on the first load of a save that has `ds_touch` data PlayNav copies it into its
own record (affection, puffs, décor, games, visitors, Super Training) and leaves the old
record in place; options set under the old id fill in any option not set under the new one.
The extracted Alpha Sapphire art lives in a per-id cache, so it is extracted once more
(a few seconds, automatic when the card image is present).
