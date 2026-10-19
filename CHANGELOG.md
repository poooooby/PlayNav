# Changelog

All notable changes to this mod are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.4.0] - 2026-10-18 (pre-alpha)

### Added

- In Play your Pokémon moves with its mood: breathing, swaying and hopping when it's happy and
  played with, slower and drooping when it's hungry or low, shivering or twitching when it's
  unwell, and almost still, leaning into your hand, while you pet or feed it.
- Pokémon-Amie's Play screen rebuilt from the game's own screen (from Wooble's capture): your
  Pokémon stands large on a lawn under a blue sky with clouds and bushes, its back turned
  until you tap it ("!", a flash, then it faces you with notes); the round puff, play and
  return buttons; the view eases in as you stroke it, the hand changes with what you touch
  (hot, shocking, cold, sharp spots, a disliked spot's yellow burst) and it reacts with
  hearts, notes or anger; the puff button slides out a strip of your Poké Puffs, and a puff
  dropped on it brings a flash of stars and a close-up of it eating, bite by bite; the play
  button brings the game's picker, one big badge at a time with gold arrows, then the
  difficulty ribbons with your stars. The top screen during Play is the sky alone: Wooble's
  dotted sky with its rainbow, drifting clouds and rising bubbles.
- Berry Picker, closer to the game: each Pokémon rises from the bottom of the screen to ask
  for its berry and drops back out of sight once served; a berry let go anywhere but on an
  asking Pokémon falls to the ground and is lost, back on the tree once it has fallen off
  the screen; the end-of-game rain shows only falling berries (none bunched at the top);
  the RESULTS card sits in the middle of the top screen with its frame's corners matching
  (window frames now honour the game's texture rotation), gold stars over all five faint
  ones, and the berry count centred on its tan box; the thought bubbles sit lower and the
  Pokémon a size larger, as in the game; "Time Left" is larger and in from the corner,
  turning red at 5 seconds with a beat each second; the HIGH SCORE bar is larger and off
  the edges; the heap at the end is every berry you picked, stacked, each the kind you
  delivered at the tree berries' size; which Pokémon asks next is random, and different
  every game.
- Berry Picker is the game's own (from Wooble's capture): the demo where the hand feeds each
  Pokémon, READY and START!, Pokémon under the tree thinking of the berry they want, a yellow
  note for the right berry and an orange one with stars for a quick one, an X for the wrong
  one, "Time Left" turning red at the end, TIME'S UP, the view rising into the canopy as the
  berries rain onto the heap, a puff of smoke revealing the Poké Puffs you won, and Play Again
  or Quit (Quit goes back to petting, as in the game). The top screen shows HIGH SCORE and
  then the RESULTS card counting up, with stars, your rank and the HIGH SCORE stamp. Your
  Pokémon stand in with their battle sprites. The art is unpacked again once, automatically.

- Pokémon-Amie's room and **DECORATE** screen are now the game's own, played from its layout
  files (from Wooble's capture). The room has its scalloped frame; tapping your Pokémon dims
  the room for **DECORATE / PLAY / SWITCH**, with bubbles that show how much it wants Poké
  Puffs and play (and hearts for its affection). DECORATE fades in on the wallpaper with its
  name between gold arrows that slide to the next one; **Interior Items** and **Poké Puffs**
  open the drawer (pages of fifteen, with counts); the item you pick waits in the room for you
  to drag. Near one of the spots around the middle it settles exactly on it (a Poké Puff dims
  the room and goes only on its spot); tap a placed item to move it, or use the tray to put it
  back. The check returns to the room, where a Poké Puff you set out falls into place. The top
  screen shows the game's Decorate picture meanwhile. Visitors now sit on the seats around the
  puff, chat in the game's speech bubbles, and gifts use the game's gift box.
- Pokémon-Amie is laid out like Super Training: the top screen fills the whole space above
  the touch screen, and the touch screen sits across the bottom at the same size. While you
  decorate, the top screen shows Wooble's own cottage art.
- **TOUCH SCREEN SHAPE** option, Kanto Gear by default: the touch screen takes the Gear
  phone's proportions (10:9, 256x230), since Super Training and Pokémon-Amie are headed
  into the Gear as modules. Every bottom screen is laid out for it with the art at its own
  size: top bars stay at the top, bottom bars and buttons go to the new bottom, and the
  room in between grows. **3DS** keeps the original 4:3 layout exactly.
- The 15 colour, cloud and pattern wallpapers (Pink through Checkered) show their real
  room pictures instead of a blown-up thumbnail, and those sets' cushions, stars, cubes and
  cloud items show their own pictures: the import had labelled them one archive entry early.
  The art is unpacked again once, automatically.
- **CLEAR EXTRACTED ART** option, a press-to-clear button: deletes everything PlayNav unpacked
  from your card image and returns to the PlayNav screen (Begin extraction, or the missing-card
  warning when the image is no longer imported), then reads PRESS TO CLEAR again. Pressed in
  the launcher, it reads CLEARS AT NEXT START and clears once you're in the game.

- With Kanto Gear 4.3+ installed, Super Training appears in the Silph Store as a
  third-party app (the Gear's `exports.modules` hook): PlayNav's own engine-drawn
  boxing glove, words and translations, installed and moved like any Gear module.
  Pressing it opens Super Training (or the PlayNav import screen first); the Gear
  steps aside while PlayNav's screens are up and returns to its home screen after.

- A proper PlayNav screen for the art import, in the banner's own look: **Begin extraction**
  (or Resume) when the import hasn't run, a modern progress bar while it does, a slow-flashing
  warning when the Alpha Sapphire card image is missing, and a brief READY card when it's done.
- Core Training plays the game's presentation when a punch digs up a new bag (from Wooble's
  capture and the game's own `sand_bag_get` animation): punching pauses, the found bag drops
  down in front for a look with your Pokémon celebrating, rises back behind the top frame,
  and the announcement comes up over the dimmed room.

### Changed

- Battles no longer give Poké Puffs: as in the game, they come from the Amie minigames only
  (the PUFFS PER WIN option is gone).
- The Amie room leaves the top screen to the game, as Super Training's home does: you can walk
  about while the room is open, and a battle takes the bottom screen back. Play, DECORATE and
  the minigames still bring up their own top screen.
- DECORATE's Interior Items drawer is sorted by the game's Décor categories (Normal through
  Fairy, then Color, Cloud, Pattern and Classy): each category gets its own page, named on the
  drawer's tab, and the arrows step through them. Only categories you own something from show.

- The Super Training stadium is Wooble's updated art (`stadiumlarge.png`).

- Décor works the game's way: you have one of each item, and placing it takes it out of the
  drawer (shown faded at 0) until you put it back. Rooms you decorated before keep everything
  where it was. The art is unpacked again once, automatically, for the new screens.
- The room's Pokémon is drawn at the game's size, and the room's CLOSE is the blue return button
  in the corner, as on Super Training's home screen.

- Pokémon-Amie and Super Training now require the extracted art: opening them before the
  import has run lands on the PlayNav screen instead of a stand-in-art version. Other mods
  calling the exports get `false, "import_needed"` meanwhile.

### Fixed

- The Amie room's wallpaper lines up with its spots again: the middle of the floor's Poké
  Ball is where the Poké Puff and the seats are (it used to sit above them).

- DECORATE's drawer and header draw whole: the drawer has its white sides and striped bands
  (no wallpaper showing through at the edges or by the torn lines), the header's name bar is
  mirrored on its right half instead of cut in the middle, the pill labels are centred, and
  the item counts are white with a black outline so they read on any item.


- The PlayNav strip's arrows over Pokémon-Amie's room (and anything else on a screen's top
  rows) now take taps: the hidden tab strip was still swallowing them.


## [0.3.5] - 2026-10-15 (pre-alpha)

### Added

- After you enter the Hall of Fame, visitors to the room bring you a Supreme Honor Poké Puff
  (once).
- Unlimited clears in any minigame can now give the Supreme Spring Poké Puff, alongside each
  game's own seasonal one.

### Changed

- Super Training on split screen: the regimen picker, the regimens and the results fill the
  whole top of the screen instead of a box with black around it, and the touch screen stays on
  the pad's room throughout, as on the home screen (it no longer moves between screens).
  - A regimen's stadium is Wooble's new, taller art and shows more of the stands; balls and the
    beaten balloon fly on past the old edge. The HUD's bands reach the edges and the names,
    timer and score sit in the corners.
  - The guts circle sits at the bottom of the bigger screen, and the HUD's bands, names, timer
    and score grow with the screen on phones where the game picture is small next to it.
  - The stadium grows to cover a wide screen instead of stretching its edges.
  - The beaten balloon flies off to just above the stadium roof's edge on every screen size,
    and its star is bigger.
- Super Training's regimen intro: the view starts close on the flat balloon and zooms out and up
  as it is pumped full; once up, the balloon sways gently in the air and settles into its
  starting place as the game begins; your Pokémon rides in from the right on its board just
  before its name shows, instead of waiting on screen.
  - The picker's title runs across the top. On a tall screen its stats and the course's
    picture grow to fill it and the target and best times sit under the stats; otherwise the
    stats keep to the left and the picture and times to the right.
  - The results' title, stat rows, Effort-o-Meter and bar grow into the extra room without
    overlapping (the stat rows and the meter together, at one size). The meter's shape no longer shows before the meter slides in.
  - Needs HD DRAWING on (the default).
- Tile Puzzle: the picture has a two-colour patterned border and stars and petals scattered
  over it, as the game's does, so you can tell where edge and middle tiles go.
- A Pokémon leaves you a present each time it gains a heart (50, 100, 150 and 255 affection),
  as in the game, instead of at our own steps (25 and 75 are gone).

### Fixed

- Super Training: a big Pokémon on the hover board (Rapidash, for one) lost its head and hooves.
  PlayNav cut a 64x64 square out of the picture a sprite mod hands it, which can be larger than
  that; the rider is now drawn whole, measured by its own pixels, feet on the board.
- Walking 50 steps still raises enjoyment at exactly 70; it stopped one point early.

## [0.3.0] - 2026-10-14 (pre-alpha)

### Added

- A Pokémon with four or more hearts says the game's own lines in battle: "That's it! I knew you
  could do it!" on a super-effective hit, "...is in a bit of a pinch. It looks like it might
  cry..." when its HP turns red, "...is thrilled to bits!" when you heal it with an item, and
  "...is fast asleep... Zzz... Zzz..." when it falls asleep.

### Changed

- The minigames are picked on the Play screen itself: the GAMES button opens the three badges
  and their ranks over your Pokémon, and a finished game brings you back there.
- Smoother on low-power devices. A regimen's top screen was making about 2.6 MB of garbage a
  frame, which kept the device's memory collector busy and the frame rate uneven; it now makes
  about 10 KB. The home screen asks the game for your party once a frame instead of eight
  times, sound effects share one buffer per effect, and the split layout is measured only when
  the window changes.
- Decorating: the drawer slides away while you hold an item, so you can set it down anywhere
  on the floor, including where the drawer was. Drop it on the strip at the bottom to put it
  away.
- Berry Picker: the berry a Pokémon asks for no longer overlaps the pile.
- Tile Puzzle: the board has the game's dark frame, the tiles already in place stand out from
  the ones still to move, and your Pokémon are bigger in the picture.
- Split screen, while you walk the overworld with Super Training's home screen open: the touch
  screen spans the width and sits just above the on-screen pad, and the overworld fills all the
  room above it instead of a fixed picture with black around it. Held sideways, the overworld
  fills the whole left side. Menus and text stay sharp at the game's own size.
- With Kanto Gear's combined screen also on, PlayNav's split no longer gets shrunk into Kanto
  Gear's top half; PlayNav's layout wins while its touch screen shows.

### Removed

- Care after battle. Your Pokémon no longer comes back muddy or dusty, both screens no longer
  ask to clean it, and the DIRT AFTER BATTLE and ASK AFTER EVERY BATTLE options are gone. A won
  battle still drops Poké Puffs into your jar.

### Fixed

- The split-screen touch screen was drawn slightly soft at most window sizes (rendered a little
  larger than shown, then shrunk). It now renders at exactly its size on screen.
- On high-DPI phones the split screen's game area could be placed at the wrong size for the
  overworld: PlayNav answered the engine in window units where it asked in screen pixels.

- Affection's doubled critical-hit chance now doubles the real chance for moves and items that
  raise it (Slash, Focus Energy, Scope Lens): before, it added the base chance only.
- Shaking off a status through affection no longer clears confusion too; as in the game, it
  covers burn, poison, sleep, freeze and paralysis.

## [0.2.5] - 2026-10-14 (pre-alpha)

### Changed

- The beaten balloon leaks and bursts with the game's own air: gusts curling off it as it
  zigzags, then a burst of cloud as it zips away, leaving a trail. The art comes from your card
  image.

## [0.2.4] - 2026-10-14 (pre-alpha)

### Added

- Super Training plays the game's own sound effects, unpacked from your card image: the
  Regimens button, picking and accepting a course, the balloon's five pumps, its name, Start!,
  your shots (tapped and charged) and their hits, new goals, the balloon winding up and
  throwing and its balls in flight, the clearing hit, the balloon leaking air and bursting
  off, the star as it vanishes, and the results' lines, Award and rewards. Sounds the game's
  own effects don't cover yet keep their old ones. They follow the game's effects volume.

### Changed

- Punching the bag is silent, as it is in the game.
- The balloon is pumped up the way the game does it: five pumps, each a quick swell on its
  sound that sags back a little before the next.
- Super Training's music and sound effects are balanced as the game balances them: the music
  sits lower, so the effects come through.
- Super Training's music follows the game's sound settings like the game's own music: it is
  off when the music volume is 0 or the audio mode is EXT. ONLY, follows the music volume and
  MUSIC FILTER, dips under cries, and pauses whenever the game's sound does.

## [0.2.3] - 2026-10-13 (pre-alpha)

### Changed

- Split screen has one layout, like a New 3DS XL: the game as large as it fits and the touch
  screen at the same height. Held upright, the game is at the top with the touch screen just
  under it and room left below for the on-screen pad; held sideways, the game is on the left
  with the touch screen beside it, both along the top.
- The second display always gets the sharpest touch screen PlayNav draws.

### Removed

- The options SPLIT SIZES, GAME SCALE, TOUCH SCALE, GAME SHARE %, BOTTOM SAFE PX and 2ND SCREEN
  SCALE (the layouts above replace them), and TOP SCREEN PICTURE (Amie is moving to the touch
  screen; the top screen is kept for its games).

### Fixed

- Smoother frame rate on handhelds with a second screen, such as the AYN Thor: the touch
  screen now reaches the second display without making the game wait for it, which caused
  stutters while the screen was animating (punching the bag back to back, for one), and PlayNav
  checks on the second display far less often.

## [0.2.3-beta.1] - 2026-10-13 (pre-alpha)

### Fixed

- Smoother frame rate on handhelds with a second screen, such as the AYN Thor: the touch
  screen now reaches the second display without making the game wait for it, which caused
  stutters while the screen was animating (punching the bag back to back, for one), and PlayNav
  checks on the second display far less often.
- **2ND SCREEN SCALE** now goes up to 4, as sharp as PlayNav draws: higher settings only sent
  the same picture larger and slowed the game down. A saved 5 or 6 counts as 4.

## [0.2.2] - 2026-10-13 (pre-alpha)

### Added

- Super Training has its music: the regimen picker, the regimens and their results play the
  game's own tracks from your Alpha Sapphire card image, and the overworld's music waits until
  you leave. The art is unpacked again once on the next start to pick the music up.

## [0.2.1] - 2026-10-13 (pre-alpha)

### Fixed

- A training bag cleared on the Super Training home screen now always raises your Pokémon's
  EVs. With the screen left open through a battle, a bag could add them to an out-of-date copy
  of your Pokémon that the summary screen never shows.

## [0.2.0] - 2026-10-12 (pre-alpha)

### Changed

- A Super-Training Regimen plays like the game's, start to finish, on the game's own screens
  and animations (copied from your card image with the rest of the art; it is extracted once
  more on the next start):
  - Starting one fades both screens to black. The top screen opens on the course's title,
    which grows in and flies off. The balloon is pumped up on the grass and floats up, and its name and
    then your Pokémon's name show in a band at the foot. The HUD slides in: the balloon's name,
    the clock, SCORE with its big digits and your Pokémon's name. Then Start, and only then
    does the clock run.
  - The touch screen is the game's aim screen: the drifting + field, the frame, the brackets and
    the reticle where you touch, your best time, and the return button that lights up once play
    begins. Blocking is L / R, as in the game; the on-screen BLOCK button is gone.
  - Every hit shows its points over the balloon; the energy gauge fills at the foot.
  - When the target is reached the HUD leaves, the balloon wobbles, deflates and zips away in
    puffs, and Success! comes up before the screens fade.
  - The results are the game's two screens. The top shows the stat rows sliding in, the trained
    stat's arrow and +N, the meter and the total gauge rising. On the touch screen the coach
    speaks a line at a time (tap or A for the next): the results, what the stat did, the
    course's badge with the time left, New best time! and the praise, the bags received, how
    many bags you hold, and the parting words. Then the picker comes back. The total gauge rises
    from the foot of the meter to your Pokémon's new total and stops there.
  - Times show as the game writes them (2:52.7).
- The bag drawer's + pattern is the game's: three columns at the game's scale.
- A regimen's top screen is the stadium (a backdrop of our own), with the Balloon Bot drawn
  much larger and your Pokémon a little smaller in front of it:
  - The balloon lies flat on the grass, is pumped up in a few puffs and floats up to its
    place; at the end it zigzags off and shrinks away into the sky. Its shadow stays on the
    grass.
  - The touch screen's brackets stand for the top screen's: where you touch between them is
    where you aim between the HUD's brackets.
  - A white mark on the top screen shows where your last shot was aimed, so you can correct
    the next one.
- The goals behave as the game's do, read from the game while it ran:
  - They stay where they appear and move only with the balloon. The balloon sways more with
    each level: gently at Lv. 1, more at Lv. 2, in big swings at Lv. 3. It shakes for a few
    seconds after each goal.
  - Lv. 1 shows one goal at a time. Sp. Atk Lv. 2 and Lv. 3 show three. A new group comes
    1.5 s after one is cleared, and the red goal (it takes several hits) after every second
    group.
  - Goals are the game's size and use its markers: the white grid, or the red one.
- Your Pokémon moves up and down with the d-pad as well as across, anywhere on the screen,
  riding a hover board (art of our own) that bobs and tips with its moves: sideways, back and
  forth, and both at once on diagonals. It moves a little slower than before, and the
  balloon's shots aim at where it is.
- Holding the touch screen (or A) only charges a shot; it fires when you let go. Pokémon with
  the yellow Energy Shot no longer spray shots while you hold.
- The balloon grows a little with each goal, up to 1.2 times its size.
- The balloon's shots are the game's soccer ball. Each one grows as it comes at your Pokémon
  and on past it. They are bigger at higher levels, up to the ball's own size at Lv. 1 and
  Lv. 2 and twice it at Lv. 3, with room left to get out of the way.
- From Lv. 2, the balloon also lobs balls up off the top of the screen. A red shadow on the
  grass marks where each one will come down: on the spot your Pokémon stood when it was
  thrown. When the ball is back in view, a real shadow takes the red one's place.
- The ten Wing and stone icons are one atlas, `assets/items.png`, instead of ten files; each
  item's icon is cut from it once. The credits say the images are © Nintendo / Creatures /
  GAME FREAK (PokéSprite's own wording), not MIT.
- Super Training's home screen is laid out from the game's own layout file: the framed teal
  name band with the training-state plate and the shot-ball tag, the blue room with its grid,
  the grey punching bag hanging behind the frame, the teal Effort-o-Meter with its coloured stat
  labels and the total gauge, and the rest of the party on the tray between the Regimens and
  Bags buttons. The art is unpacked from your card image like the rest (it is extracted once
  more on the next start). It moves like the game's too, from the game's own animations: the
  Pokémon sways and bobs, lunges into the bag on a hit, the bag swings, the hit marks burst and
  the room shakes; the pattern in the background drifts. A tap anywhere in the room punches the
  bag, as in the game, and a punch lands only once the last one's animation has finished, so tapping faster does not train faster.
- The support bags use the game's own numbers, read from its training-bag table: Strength,
  Swiftness and Big-Shot multiply by 1.5 and Toughen-Up divides damage by 1.5 (Strength was
  doubled and Swiftness 1.3 before).
- The regimen shots use the game's own shot table: how many points each colour scores, how
  fast and big it is and what it costs, relative to the black shot.
- The Effort-o-Meter is drawn with the game's own steps: each axis grows in the same pixel steps
  for base stats and EVs as on the 3DS.
- Super Training's home screen and bag drawer run on the touch screen alone, as in the game:
  the overworld stays on top and you can walk about while your Pokémon trains. The top screen
  is used for the regimen picker, a regimen and its result. Messages show in the game's window
  on the touch screen; the game's blue return button (or TRAINING on the START menu again)
  closes it, the strip's arrows switch between Super Training and Pokémon-Amie,
  and a battle takes the touch screen back until it ends.
- The training bags open as the game's drawer over the home screen: the room dims, the drawer
  slides in with the bags in two tilted columns, the Bags button turns into the return button,
  and tapping a bag opens the game's description window with Use / Discard / Back (Use and
  Discard ask first). Positions, tints and the slide come from the game's own layout files.
- Resting and the second wind work like the game's. Your Pokémon punches its bag once a minute
  on its own, also while the screen is closed. It lies down after 30 to 60 minutes, or after 3
  to 5 bags cleared, whichever comes first, and stays down until tapped (a fainted Pokémon
  cannot be woken). Waking, a rare find, the Team Flare Bag and some cleared bags give it a
  second wind: double-strength punches for one bag, or double points in one regimen. The
  blank bag finds a bag on 5% of punches (10% for a fully trained Pokémon), any of the game's
  bags but Team Flare with equal odds: the game's own roll, read from its code. Lying down, getting up and the second wind use the
  game's own animations.
- The regimen picker is the game's own screen: one level per page with its six courses in
  their round frames and stat labels, CLEARED and the award medal on the ones you have done,
  the medal count with your Pokémon's icon, and the bar with the page and the return button
  (the secret courses come as more pages once a Pokémon is Fully Trained). Tapping a course
  puts the game's brackets round it, its description in the message window and its card on
  the top screen: the stats it can raise, the target time and your best time. Tap it again to
  start. Going there plays the game's transition: the button bounces, the touch screen's
  shutters close with the glowing seam, both screens go black and fade into the picker; going
  back closes the picker's shutters and opens them on the home screen.
- The coach cheers while a training bag hangs, as in the game: a line for the bag's kind comes
  up as soon as it is set, stays ten seconds, goes, and another follows ten seconds later. The
  wait stands still while a punch plays, so fast tapping spaces the lines out. Lines, groups and
  timing are the game's own, read from its code and checked live.
- A cleared training bag ends with the game's finishing move, from its own animations: one of
  its three special attacks, each with its own coach's line ("This is it! The muscles that will
  make the future bright!" and two others), the bag spinning off its hook, a glow around your
  Pokémon sized to its sprite, then the stat that went up. Back on the home screen, the stat's
  label pulses with a "+N" over it and an arrow pulses at the top of the total gauge until the
  next hit or tap, and the next bag drops onto the hook. Taps wait until it has played out. The
  silver strip along the bottom now meets the Regimens and Bags buttons' lower edge.

### Fixed

- The top screens (Pokémon-Amie, Super Training) are drawn at the window's resolution again;
  they had fallen back to the low-resolution picture enlarged.
- The item icons' credits are in `assets/credits.txt`.
- With Kanto Gear on, the two mods no longer fight over a second display (AYN Thor). PlayNav
  has it while Amie or Super Training is open: Kanto Gear's picture and taps stay off it until
  they close, then Kanto Gear shows there again at once.

## [0.1.1] - 2026-10-12 (pre-alpha)

### Changed

- The mod's description in the Mod Manager and the description of the Alpha Sapphire card
  image import describe PlayNav as it is: Pokémon-Amie and Super Training, with the 3DS art
  and English text unpacked from your own card image.
- The README is written for players, with a pre-alpha caution, the options table with
  defaults, and the card image's exact size and MD5 in the installation steps. Developer
  notes are in DEVELOPMENT.md, which the package leaves out.
- The code is under the MIT licence (LICENSE).

## [0.1.0] - 2026-10-12 (experimental)

First public release, Gen 3 (Emerald, Ruby, Sapphire, FireRed, LeafGreen) only. Everything
below shipped together in it: a DS-style touch screen (split screen or a second display) with
Pokémon-Amie (petting, Poké Puffs, care after battle, the room, Décor and visitors, Berry
Picker, Head It, Tile Puzzle, affection benefits in battle) and Super Training (Core
Training, the 26 training bags, the 30 regimens with sprite Balloon Bots, Awards and secret
prizes), drawn at the display's full resolution. The 3DS art and English text come from the
player's own Alpha Sapphire card image, extracted on their machine; nothing from the games
ships with the mod. Many Super Training numbers are provisional (see the README).

## Development history (internal builds before the first release)

### Internal build 0.4.2 (2026-10-12)

#### Changed

- Super Training's Balloon Bots are the Pokémon's own front sprite, blown up in balloon blue
  with a dark outline, instead of the round course badge. The pixels stay square at any size. A species the game has no sprite for
  (the Generation 4-6 bots, unless a National Dex mod adds them) keeps its course badge.
- Goals sit on the sprite itself and travel over it, cell by cell, never across empty space:
  each starts on its part of the body (head, arms, tail ...), wanders around it, faster and
  further on moving parts, at higher levels and on the fleeing and roaming courses
  (`GOALS.WANDER` in `data/training_rules.lua`, inferred from the game's coach tips; the
  speeds are ours). Goals keep apart from each other.
- A sprite balloon hovers higher and is sized so that, fully grown, it stays inside the sky
  the aim pad reaches; the pad covers that larger area (`BOT.SHAPE_CY`, `BOT.AIM_X`,
  `BOT.AIM_Y`), so every goal on it shows on the pad and can be hit. The reticle starts on
  the balloon's centre.
- The player's Pokémon in a regimen hops as it moves: a squash on each landing, a stretch in
  the air, a lean into the direction, facing it, and a last squash when it stops, instead of
  gliding. Drawing only: its position and hit area are the sim's as before.

### Internal build 0.4.1 (2026-10-12)

#### Changed

- The session screens on the touch screen (Amie, the minigames, Décor, Super Training, the
  import panel) no longer carry a title bar; their backgrounds reach the top edge.
- Text that does not fit its box is wrapped inside it and drawn smaller (down to 60%) instead
  of running past the edge: the touch screen's message strips, the regimen picker's status
  window and both top screens' text boxes.
- The emotion bubbles sit above-left of the Pokémon, where their tails point; in the Amie
  room they are smaller and closer, clear of the PLAY / DECORATE / SWITCH buttons.
- Picking a regimen shows its card on the top screen: the level heading, the course badge,
  its name, the game's description of it, the EVs it gives, the target time, your best time
  and Award. START (or a second tap) begins it; a locked course says why.

### Internal build 0.4.0 (2026-10-12)

#### Added

- **HD rendering** (option HD RENDERING, on by default). The touch screen renders at the
  output's pixel density (its scale times the screen's DPI, up to 4x) while the apps keep
  drawing in 256x192 units, and its text is rasterised at that density. The second display
  gets a frame rendered at its push scale instead of an upscaled one. Amie's and Super
  Training's top screens are drawn again over the finished frame at window resolution while
  they are the top of the game's menu stack (the engine's own canvas then holds only their
  backdrop). The overworld, battles and the engine's passes are untouched.
- The Alpha Sapphire textures are mipmapped and linearly filtered; Pokémon sprites and party
  icons stay nearest at whole multiples and use a small sharp-bilinear shader at fractional
  sizes. Tile Puzzle's picture is rendered at the surface's density.

#### Fixed

- Super Training's caution strip shows the word CAUTION! (the texture is only its backing).

### Internal build 0.3.2 (2026-10-12)

#### Changed

- Pokémon-Amie reads the game's own text (recipe version 8 adds nine files of `a/0/7/3`):
  the 26 Poké Puff names ("Supreme Autumn Poké Puff", not Fall), every Décor name, the words
  Affection / Fullness / Enjoyment, "Switch Pokémon!", "Select the Pokémon you'd like to play
  with!", "You can't play with an Egg, silly!", "You need three Pokémon in good condition.",
  "You cannot put out any more Décor!", the gift lines ("You got X from A, B, and C!", "You and
  TORCHIC are looking close! Found X!", "You'll be friends forever with TORCHIC!"), the picker's
  "Which game do you want to play?", the minigames' HUD words (Time Left:, Chances:, FEVER,
  MISS!, N-HIT COMBO, Time Remaining:, Puzzle No. N, NEXT!), their rank titles, their result
  lines ("Poké Puffs Received!", "You can now access the next rank!") and Head It's score
  breakdown (Heading Points, Last Combo Record, Big Yarn Bonus, TOTAL:). Our wording stands in
  without the card.
- The game's own list of Décor (text file 110, in archive order) corrected three pairs the
  catalogue had the other way round: entry 82 is the **Blue** Circle Cushion and 83 the Red,
  entry 132 the **Iron** Cushion and 133 the Cast-Iron, and the Lightbulb Object is one word.
  Saves that own or placed the old ids are renamed once on load (the art the player saw is
  unchanged).
- The Supreme Wish and Supreme Honor Poké Puff icons were swapped (the archive runs in the
  text's order: Wish is the cake with candles).
- Art for the room and the games: the PLAY / DECORATE / SWITCH buttons, the Affection /
  Fullness / Enjoyment icons on the top screen (three named rows of five, as the game shows
  them) and on the play screen, the HUD digits and white HUD box in all three minigames, the
  yarn "Chances" markers in Head It, the tier rings behind the Poké Puffs won, the star art and
  the Pokémon-Amie wreath on the result card.
- Visitors leave when the Poké Puff set out changes (the game warns of exactly that).
- `data/amie_rules.lua` carries an `EVIDENCE` row for every number (verified / inferred /
  placeholder with its source), like Super Training's.

### Internal build 0.3.1 (2026-10-12)

#### Changed

- Super Training reads more of the game's own text (recipe version 7 adds the course and
  coach files of `a/0/7/3`): the official English course names ("Raise Your HP with
  Wailmer!", "Break It! Golem's Defensive Line!" ...), each course's blurb, the level
  headings, the result screen ("Target Time Remaining:", "Award received!", "New best
  time!", "Base stat increase:", the coach's praise, the stat lines), unlock announcements,
  the Core Training completion lines ("TORCHIC's base HP stat went up!"), the resting,
  second-wind, found-a-bag and rack-full lines. The medal is an **Award**, as the game says.
- The Energy Shot works as the game's tutorial describes: a shot fired with a full energy
  meter is the species' Energy Shot; before that it is a plain black ball worth less the
  emptier the meter; a nearly dry meter gives the weak ball. The meter refills faster.
- Bitbots regenerate after a while, as the tips say. Aegislash's rage also speeds up and
  strengthens its shots; Roserade calms down the same way. Aerodactyl's balloon rises and
  falls; Probopass's goals keep moving; point loss grows with the course level.
- The course order from the text archive fixes the course icons: every secret course now
  shows its ORAS badge.
- Art for the screens: the Regimens and Bags buttons, the Effort-o-Meter canvas, the
  shot-type icon and the mood bubbles on the Core screen; course cards, badges, the status
  window and Award medals in the picker; timer and score digits, the energy gauge, the
  charge ring, the caution strip and the Start banner in the regimen; the Success / Try
  Again banners, stat labels and the RESULTS ribbon on the result screens; the aim ring,
  cursors and return button on the pad.

### Internal build 0.3.0 (2026-10-11)

#### Added

- Super Training (X/Y, ORAS) as a sibling of Amie: a TRAINING entry on the Gen 3 START menu
  opens Core Training on both screens. The lead Pokemon stands by its training bag; tap the bag
  (or press A) to hit it, the Pokemon hits it once a minute by itself, rests now and then and
  gets a second wind when tapped (half the hits needed). The Effort-o-Meter hexagon shows the
  species' base stats in green and the EVs in yellow (252 per stat) with the 510 column; the
  party strip switches Pokemon; a shot-colour badge shows the species' Energy Shot.
- The 26 training bags with the games' numbers (`data/training_rules.lua`): stat bags S / M / L
  at 10 / 25 / 50 hits for +1 / +4 / +12 EVs, Big-Shot, Double-Up, Strength, Swiftness,
  Toughen-Up and Team Flare at 10, Reset at 100, Soothing at 250 (+20 friendship); a rack of
  twelve; tapping the empty black bag can drop a bag; a cleared regimen always gives one.
- The 18 Super-Training Regimens and the 12 Secret regimens (`data/training_courses.lua`):
  the Bulbapedia Balloon Bots and scores (Wailmer 500 ... Wailord 4000, Aegislash 4800, the
  Aron line and Mega Aggron), +4 / +8 / +12 EVs, Lv2 and Lv3 unlocked by clearing all six of
  the level below, secret courses one after another for a Fully Trained Pokemon (510 EVs,
  kept after a Reset Bag), circuits with +30 s per popped bot, a 3:00 clock with the medal at
  2:30 / 2:00 / 1:30 left, item prizes (evolution stones only on a new best), Hydreigon's
  sudden death, Aegislash raging and Roserade calming at 2400.
- The regimen itself on the top screen: goals on the balloon that turn yellow at 8 s and vanish
  at 12 s, the red Chance Goal, the bot growing with every goal, telegraphed attacks (rapid,
  big, ring, homing, cross, waves, barrier with its marker, bit balloons), the pad to move,
  L to block, the guts circle, three charge stages (3x at the top, a stun past it), the five
  Energy Shot colours per species (`data/training_shot_types.lua`, Bulbapedia, all 386 Gen 3
  species) with yellow spraying while held and bursting seven at full charge, EVs raising
  points, shot size, guts, block time and speed. The bottom screen is the aiming pad with a
  BLOCK button; the Pokemon moves with the d-pad.
- Ten new items the engine never had, registered through the content registry: Health, Muscle,
  Resist, Genius, Clever and Swift Wing (+1 EV from the bag, within 252 / 510), Pretty Wing,
  Dusk, Shiny and Dawn Stone (collectibles to sell), with pokesprite icons in the bag and
  PokeAPI text. The stones are registered as ST_DUSK_STONE etc.; with national_dex_gen3
  installed a stone prize is that mod's real Gen 4 stone.
- Alpha Sapphire art for all of it (recipe version 4, 542 textures): the 27 bag icons, the
  39 course badges, the aim pad, goal rings, the six balls, the medal.

#### Changed

- Amie and Super Training refuse to open while the other is on screen.
- The mod is now **PlayNav**, id `play_nav` (was `ds_touch`), and declares Gen 3 only. Save data
  and options stored under `ds_touch` are carried over once on load (`src/rename.lua`); the old
  record is left in place. Layer and START menu ids are `play_nav_amie` / `play_nav_training`;
  `mod.find("play_nav").exports` replaces `mod.find("ds_touch").exports`. The extracted art is
  cached per id and is extracted once more.
- Super Training regimens move with the d-pad only; the touch MOVE strip is gone.
- Tapping a training bag opens its box as in the game: icon, name, description, Use /
  Discard / Back, each with the game's Yes / No question. Setting a new bag discards the one
  on the stand, as the game's own prompt says. The names, descriptions and button words are
  the game's, decoded from the player's card into the cache (recipe version 5 adds two text
  entries from a/0/7/3; `src/import/gen6text.lua` reads Gen 6 text); our own wording stands
  in without a card. The game order of the bags also fixes the icons of the five
  regimen-effect bags.

### Notes

- Points per goal, point loss per hit, guts and charge timings, bag and prize odds and the
  attack schedules have no public source; `data/training_rules.lua` carries every number with
  its class (verified / inferred / placeholder) and its source so they can be corrected.
- The engine gained two small seams for this: the item name index is rebuilt after a content
  registry write, and both bag skins ask an `item.icon` hook before their own art.

### Internal build 0.2.0 (2026-10-11)

#### Added

- Pokemon-Amie play rules from X/Y and ORAS (numbers in `data/amie_rules.lua`): affection,
  fullness and enjoyment levels at 0/1/50/100/150/255 points; petting events every 60 px with the
  Bulbapedia gains per spot and enjoyment band; favored, disfavored and effect spots per species
  (`data/petting_gen3.lua`, 386 species, derived from Bulbapedia's "Petting" article, CC BY-NC-SA
  2.5), burning / paralyzing / freezing / cutting spots that interrupt a stroke; a rapid
  double-tap "hit" (-5 enjoyment); the five-second high-five (+10 enjoyment, needs 5 affection);
  +10 enjoyment on opening play; Metapod, Kakuna, Pineco, Silcoon, Cascoon and Shedinja refuse
  puffs; Slugma and Regice cannot be petted.
- Poke Puffs eaten bite by bite while held on the Pokemon (2, 3 or 5 bites by sprite size, slower
  when nearly full); a puff pulled away early gives fullness only; the jar is an ordered list of
  up to 100 puffs, the oldest lost first; puff affection by tier +2 / +3 / +4 / +5 / +6 (+10 for
  Supreme Wish and Honor); a whole puff is +50 fullness.
- Stats move outside a session too: entering a battle with the active Pokemon takes 10 fullness
  and gives 5 enjoyment; every 50 steps take 1 fullness and give 1 enjoyment below 70.
- Affection benefits in battle, on by default (option AFFECTION BENEFITS): 1.2x experience at
  2 hearts, enduring a knockout at 1 HP from 3 hearts (10 / 15 / 20 / 25 %), shaking off a status
  at the end of the turn at 4 hearts (20 %), a 10-point accuracy drop for the foe at 200
  affection, double critical-hit odds at 5 hearts, with the games' battle messages. Skipped in
  link, facility and tutorial battles.
- Milestones: a dance with hearts and cries at every 50 affection (three cries at 255) and a gift
  left in the room at 25 / 50 / 75 / 100 / 150 / 255 affection.
- The Amie room (START menu > AMIE): the active Pokemon wanders as its party icon, plays when
  enjoyment is high, naps with a status, stops and asks for food at 0 fullness, shows the puff /
  note hints over its head; tap it for DECORATE / PLAY / SWITCH, the hearts / puffs / notes loop
  while the menu is open, SWITCH picks a party member who is remembered as the active one.
- The three minigames with their Bulbapedia ladders: Berry Picker, Head It and Tile Puzzle, Easy
  to Unlimited, three stars unlock the next difficulty, Poke Puff rewards per rating and the
  seasonal Supremes on Unlimited, three healthy participants (active plus the two least enjoyed),
  -110 fullness / +80 (or +30) enjoyment per game, titles, decor gifts for unlocks and five-star
  runs. GAMES sits in the play tray.
- Decorate: the full X/Y decor catalogue (34 wallpapers, 104 cushions, 68 objects in sets A-F,
  `data/decor_catalog.lua`), the eleven starting pieces, a drawer over the room (WALL / CUSHION /
  OBJECT / PUFF), up to 30 placed items, dragging to place, move and put away, a Poke Puff set out
  for visitors; the Pokemon sits on a placed cushion.
- Visitors: Pokedex-seen species (plus the party) drop by while the room is open, stay by the
  puff-out odds, chat for thirty seconds with the set's bubbles and leave a present; gift sets by
  combined affection raised by the puff's minimum, same-type and same-line groups, up to six
  presents on the floor, milestone / unlock / five-star gifts delivered the same way; a complete
  set yields a puff of its tier.
- 278 more Alpha Sapphire textures (recipe version 3, re-extracted automatically, 421 in all):
  the 15 game badges, berries, the berry heap and grass, yarn frames, the big finale yarn, clouds,
  the Fever rainbow, "!" bubbles, the game backdrops, the puzzle frames and the whole decor
  catalogue with its wallpaper thumbnails.

#### Changed

- Split screen on Gen 3 stacks the picture and the surface instead of overlaying the surface
  on the engine's centred picture: the largest integer picture scale that leaves the surface
  at least 1x, the pair centred, the picture area handed to the engine through its playfield
  cutout, so nothing overlaps at any window size (phones, a resized PC window, landscape).
  New options SPLIT SIZES (AUTO / 3DS / EQUAL / 3DS FLIPPED / MAX GAME / MAX TOUCH), GAME SCALE and TOUCH SCALE
  (AUTO or 1X..6X, clamped so the pair fits) decide how the room is shared.
- The START menu entry is now AMIE; the care tray only shows the cleaning tools and medicine
  while the Pokemon needs them, and PUFFS otherwise.
- The mod save moved to schema 2 (`puffs` list, `room`, `decor`, `games`, `visitors`, `meta`);
  0.1.0 saves migrate on load. `mod.find("ds_touch").exports.amie` replaces `exports.refresh`,
  which remains as an alias.
- The old time-based fullness decay is gone; steps and battles do that job as in the games.

### Internal build 0.1.0 (2026-10-10)

#### Added

- Pokémon Refresh on Gen 3: a care prompt after battle on both screens, then a bottom-screen
  session with towel / brush / dryer / comb for mud, dust, water and ruffled fur, medicine for
  status conditions, petting with hearts, and Poké Puff feeding (26 varieties with their own
  fullness values, a scrollable row of the ones you own, the dragged puff is the one you picked). A REFRESH entry in the START
  menu opens it any time.
- Per-Pokémon affection, fullness and enjoyment in the mod save; a Poké Puff jar fed by won battles (one
  random variety per win, weighted toward Basic).
- The DS-style 256x192 touch surface: second-screen (AYN Thor / desktop companion) and
  single-screen split placement, a pointer stream with per-pointer records, velocity, path and
  gesture helpers, and an app registry exported for future minigames. The surface stays dormant
  until an app asks for it.
- Option to hide the engine's built-in virtual pad while the surface is active.

- Optional Alpha Sapphire (USA) Rev 2 card image import: validated by the launcher, extracted
  in-game by pure-Lua decoders (NCSD/NCCH/RomFS, GARC, LZ11, BCLIM with ETC1) in background
  jobs into `mod.cache`; Refresh then draws the Amie hand cursor, Poké Puffs, emote bubbles and
  the room wallpaper. The mod ships only the recipe.

### Notes

- Battle commands, the bag and a touch pad are deliberately not part of this mod; Kanto Gear
  covers them.
