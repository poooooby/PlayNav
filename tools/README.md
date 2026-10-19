# Development pipeline for the Alpha Sapphire art

Nothing in this folder ships to players (it is listed in `.modkitignore`). It exists to find the
textures, to produce `data/oras_recipe.lua`, and to prove the mod's pure-Lua decoders against two
independent references. Players never run any of it: the game extracts the art itself from the
card image they supply in the launcher.

## Tools built from source (Windows, Visual Studio 2026)

| Tool | Source | Build | Output |
| --- | --- | --- | --- |
| ctrtool v1.3.0 | `github.com/3DSGuy/Project_CTR` | `MSBuild ctrtool/build/visualstudio/CTRTool.sln -p:Configuration=Release -p:Platform=x64 -p:PlatformToolset=v145 -p:WindowsTargetPlatformVersion=10.0.26100.0` | `build/visualstudio/x64/Release/CTRTool.exe` |
| bclimtool v1.1.1 | `github.com/dnasdw/bclimtool` (with submodules) | `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5` then `cmake --build build`, inside a `vcvars64` shell | `bin/Release/bclimtool.exe` |

Prebuilt fallbacks: `ctrtool-v1.3.0-win_x64.zip` and `bclimtool.zip` on the projects' release pages.

ctrtool reads the card (`CTRTool.exe -i game.cci`) and extracts the RomFS
(`CTRTool.exe -n 0 --romfsdir=romfs game.cci`), but it stops at the first zero-length RomFS file
(`a/0/8/7` in Alpha Sapphire). `romfs_extract.py` finishes the job and doubles as the reference for
the mod's `src/import/ctr.lua`.

## Scripts (Python 3.14, standard library only)

```sh
# 1. RomFS -> loose files (handles zero-length entries); `list` prints every path
python tools/romfs_extract.py "<game.cci>" extract <work>/romfs a/

# 2. GARC archives -> every BCLIM (LZ11 decompressed), plus index.json
python tools/garc_dump.py <work>/romfs <work>/garc_all

# 3. decode twice (bclim.py and bclimtool), compare pixel for pixel, contact sheets + REPORT.md + results.lua
python tools/discover.py <work>/garc_all <work>/png <work>/sheets --bclimtool <bclimtool.exe>

# 4. look at an archive as one image (plus a .txt sidecar: cell -> file)
python tools/montage.py <work>/sheets a_0_4_2 <work>/montage/a_0_4_2.png --cols 8 --cell 80

# 5. check the recipe against the dump and measure the asset set
python tools/recipe_check.py <work>/garc_all <work>/recipe_png
```

The in-game decoders are tested against the same data with
`luajit mods/play_nav/tests/oras_local_test.lua` from the engine root (it skips when the dump or
`results.lua` is absent).

## Findings for Alpha Sapphire (USA) Rev 2

- 2 GiB CARD2 image, title `000400000011c500`, decrypted. MD5 `0563f9dee1b95de32d579e40c20e2bfc`.
- 655 RomFS files, 299 GARC archives under `a/`, 9,974 BCLIMs in 141 of them.
- Texture formats seen in the Amie archives: RGBA4 (most UI), ETC1A4, RGBA8, ETC1 (wallpapers),
  RGB8, RGBA5551, RGB565, LA4, L8. Texture memory is padded to power-of-two sizes; the header
  carries the visible size.
- Archives used by the recipe: `a/0/4/2` hands, `a/0/4/1` emote faces / bubbles / stars /
  badges / the 15 minigame badges, `a/0/4/3` frames, `a/1/4/6` Poké Puffs, `a/1/4/5` the whole
  décor catalogue (34 wallpapers with thumbnails, 104 cushions, 68 objects in blocks per
  category), `a/0/2/6` reaction bubbles and effects, `a/0/1/6` Berry Picker, `a/0/1/7` Head It,
  `a/0/1/8` Tile Puzzle.
- The 421 chosen textures (recipe version 3) total about 2.0 MB as RGBA8 PNG (19 MB raw). PNG in
  `mod.cache` is the storage format; nothing smaller was worth a second decoder.
- Not BCLIM, out of scope for now: water, shock and other battle effects (they live in BCH /
  CGFX model files).

## Data generators (Bulbapedia-derived, CC BY-NC-SA 2.5)

- `petting_table.py` downloads the "Petting" article through the MediaWiki API (or reads a
  cached wikitext with `--cache`) and writes `data/petting_gen3.lua`: favored / disfavored /
  effect zones for National Dex 1..386, mapped from the spot text to the zones the mod lays
  over a front sprite. The original text travels with each row so a zone can be hand-tuned.
- `decor_catalog.py <garc_all/index.json>` writes `data/decor_catalog.lua` (34 wallpapers,
  104 cushions, 68 objects with their sets and the eleven defaults) from the block layout of
  archive `a/1/4/5` and, with `--recipe-out`, the matching `add(...)` lines for
  `data/oras_recipe.lua`. Re-run `recipe_check.py` afterwards.

## Super Training (added for 0.3.0)

- `st_evidence.py <romfs> [--only a/x/y/z,...] [--dump <dir>]` parses every GARC under `romfs/a`,
  LZ10/LZ11-decompresses each subfile and scans for the known regimen scores (Lv1 500/300/400/
  300/200/200, Lv2, Lv3, the secret bots) as u16 and u32. Findings for Alpha Sapphire (USA) Rev 2:
  51,043 subfiles scanned, no subfile holds the course table as plain integers (the 58 hits are
  coincidences inside textures and one 636-byte level table in `a/0/7/9` / `a/0/8/0` entry 635).
  The feature's code is `romfs/DllSparring.cro` (124 KiB; RTTI names `SparringBossActor`,
  `WaveActor`, `EnemyActor`, `JiraiActor`, `MissileActor`, `PlayerActor`, `ParticleActor`) and
  `DllSparringMenu.cro`; the course numbers are most likely immediates in that ARM code, which
  this pass does not disassemble. pk3DS has no Super Training editor.
- The six Super Training texture archives, decoded with `discover.py` into `oras-extract/sheets_st`
  and `montage/a_0_2_7.png` ... `a_2_1_7.png`: `a/0/2/7` the Core Training bottom UI, `a/0/2/8`
  entry 0 the 27 bag icons (20x50) and entry 1 the 39 course badges (64x64; Scatterbug, Spewpa,
  then per level Sp. Atk, HP, Atk, Sp. Def, Spe, Def; the secret order is unverified), `a/1/1/3`
  course select and results (the medal is CLIM 9), `a/1/1/4` entry 0 the top HUD (goal ring
  frames 8-16, big rings 57-65, the barrier 19, charge 21, guts 24, timer digits 28-37, score
  digits 43-52, balls 69-74, caution 76, banner 80) and entry 1 the aim pad (pentagon 10, aim
  ring 8, exit 4, marker 5), `a/2/1/7` banners and stat labels per language, `a/2/1/6` result
  titles. Recipe version 4 carries 121 of them under `training/`.
- `shot_types.py` downloads Bulbapedia's "List of Pokemon by Super Training Energy Shot" and
  writes `data/training_shot_types.lua` (386 species, no gaps).
- `items_pokeapi.py` writes `data/training_items.lua` from PokeAPI (names, effects, flavour text)
  with the X/Y era "Wing" names and Bulbapedia's prices; the icons come from PokéSprite (images © Nintendo / Creatures / GAME FREAK; credited in `assets/credits.txt`).
- `gen6_text.py <romfs> a/0/7/3 [--find text] [--file N] [--vars]` decodes Gen 6 text files.
  Alpha Sapphire's English game text is `a/0/7/3`: file 24 holds the 26 training bag names in
  the game's order, file 27 the bag screen (13-17 Use / Discard / Back / Yes / No, 7 and 8 the
  use and discard questions, 9 and 10 the replace warnings, 19-44 the descriptions). Variable
  0x010A is the bag's name, 0x0102 the Pokemon's. The recipe carries these as `kind = "text"`
  entries; the mod never ships the text itself.
- The course side of the same archive: file 44 holds the course names in the game's order
  (0-1 the tutorials, 2-19 the regular courses in Sp. Atk / HP / Atk / Sp. Def / Spe / Def order
  per level, 20-31 the secret courses, 32-37 distribution courses) and the coach's "Secrets to
  Super Training Success" tips (59-90), which state the mechanics in the game's words; file 45
  repeats the names (20-57), has the level headings (1-6), the per-course blurbs (75-112), the
  result screen (59-74, 125-168). `data/training_courses.lua` carries each course's `order` so
  text lines and the course icons (a/0/2/8 entry 1 follows the same order) index from it.
- `lyt_rows.py <romfs> <pack>=<archive>:<entry>:<sub> ... -- <pack>:<layout.bclyt>:<packs> ...`
  writes the recipe rows for a screen played by `src/lytplayer.lua`: a `files` row per layout
  pack (its `.bclyt` and `.bclan` are copied into the cache as they are) and an `add` row for
  every texture the layouts and their clips' texture patterns name, found in the listed packs in
  order (`lyt/<pack>/<darc texture name>`). Names no pack holds are filled by the game at run
  time (icons, sprites) and are listed on stderr. The regimen's screens: `upper.bclyt` (top HUD)
  and `lower.bclyt` (aim) in `a/1/1/4`, `result_upper` / `result_lower` in `a/1/1/3`, the shared
  pack `a/0/2/8` entry 2, the English words in `a/2/1/7` entry 0 sub 2. File 98 of `a/0/7/3` is
  the species names by National Dex number (0 Egg).

- `bcstm.py info <file.bcstm> ...` / `bcstm.py wav <file.bcstm> <out.wav>` reads the game's music
  streams (`sound/*.dspadpcm.bcstm`, DSP-ADPCM, stereo, intro + loop point) and decodes one to a
  WAV; the twin of `src/import/bcstm.lua`, which the import job runs (recipe kind `stream`).
  Super Training's tracks are `bgm_xy_sp_*` (28000 Hz): `menu` (17.4 s, loop from 6.14),
  `gamestart` (2.6 s, once), `stage` (64.2 s, loop 7.68), `stage_02` (67.8 s, loop 10.75),
  `clear` (21.6 s, loop 6.14), `gameover` (34.1 s, loop 5.63), plus the jingle
  `me_xy_sp_stage_open` (32728 Hz). Matched by cross-correlation against a capture of a Lv. 1
  regimen (r 0.95-1.0): menu on the picker, gamestart with the title, stage 3.0 s later, silence
  from the last hit, clear with the banner and through the results, menu again on the picker.

- `bcsar.py list|render|renderall|match` reads the sound archive (`sound/sango_sound.bcsar`: STRG
  names -> item ids, INFO tables sounds 0x2100 / banks 0x2101 / wave archives 0x2103 / files
  0x2106, FILE) and renders sound effects: a CSEQ sequence (notes, waits, note-wait `c7`, pan /
  volume / pitch bend + range / vibrato `ca`-`cd` / ADSR `d0`-`d3` / hold `b1`, tracks `fe` +
  `88`, random `a0`, sweeps `a3`, loops `d4`/`fc`) on its CBNK (instrument -> direct / range /
  index tables -> velocity region: wave, original key, volume, pan, pitch float, ADSR) with the
  CWARs' DSP-ADPCM CWAVs, at 32728 Hz. Twin of `src/import/bcsar.lua` + `seqsynth.lua` (sample
  for sample, `tests/bcsar_test.lua`). Super Training is `SEQ_SE_SP_001`..`051` + `_DECIDE`
  (each its own bank; 68 waves, all DSP-ADPCM); Amie is `SEQ_SE_KW_*` (104) and the
  `GROUP_KW_GAME1..3` minigames. `match` cross-correlates every render against a capture's
  audio: with the capture's known music subtracted (aligned per half second, +-25 ms) the
  regimen sounds matched at r 0.70-0.99; `data/training_sounds.lua` holds what was found.

- `bch.py list <garc> [entry]` / `bch.py extract <garc> <entry> <dir>`: the textures in 3D model /
  effect files (BCH 0x21): the main header's fourth (pointer table, count) is the textures; each
  texture entry holds its GPU command list (offset, words: texture unit registers 0x82 size,
  0x85 data address relative to the data section, 0x8e PICA format) and its name at +0x1c in
  the string table. Pixels decode with `bclim.py`'s routines. Twin of `src/import/bch.lua`
  (`tests/bch_test.lua`). The regimen's 3D scene is `a/1/1/4` (85 BCH: stadium e80-87, shots
  e24-60 `emd_sp*` / `etxm_*`, barriers e62-67, flags / sky e75, grid e78); no balloon or
  deflation effect is named anywhere. The battle effects `a/0/3/2` hold the shared smoke family:
  e240 `etxm_streamline02f` (8 frames of 128x64, the air gusts) and `etxm_circle01m` (soft round
  mask), e155 `etxm_kumo01m` (cloud shading), e68 `etxm_smoke01m/02m`, e445 `etxm_bombsmoke01`.
- `bch.py ... --deep` / `bch.py find <romfs-dir> <regex>` (2026-10-18): most 3D scenery sits inside
  Game Freak's packages (a two-letter tag - 'PC' Pokemon, 'GR' field, 'MM', 'AD' ... - a u16
  count and count + 1 u32 offsets), often LZ-compressed and nested; `--deep` opens them, `find`
  lists every texture whose name matches across every GARC (a sub entry prints as its path
  through the packages, e.g. `0/1/0 1.0/3`: entry 1, GARC sub 0, package file 3). Found for
  Amie PLAY: the grassy battle background a/1/3/6 e94 `0/0` (`btl_sG_kusa_ji1` lawn,
  `btl_sG_kusa_ki2b` bush line, `ki4` / `ki5` trees), the overworld skybox a/0/1/0 e1
  (`hare_kumo_yoko` 1, `kumo_yoko_a1` 2, `kumo_yoko_a2` 3: cumulus), bubbles a/0/6/4 e0 `0/26`
  (`awa_spring01`: four sizes, then popping rings). Not found anywhere: the Amie top screen's
  dotted sky and rainbow (a 3D effect scene; Wooble's art stands in) - a/0/4/0 is 431 tiny 'MM'
  metadata packages, a/0/3/9 857 LZ 'GR' field chunks.
- Amie PLAY's 2D screens (2026-10-18), missed by the first darc scan: `game_select_lower.bclyt`
  a/0/4/1 e0 (raw, darc at +20352: buttons, face bubbles, the puff strip, the minigame picker;
  146 clips) and `kawaigari_icon.bclyt` a/0/4/2 e0 (+5248: the hand's 15 flipbook clips);
  `tools/lyt_rows.py <romfs> amie_play=a/0/4/1:0:0 amie_hand=a/0/4/2:0:0 -- amie_play:
  game_select_lower.bclyt:amie_play amie_hand:kawaigari_icon.bclyt:amie_hand` writes the rows.

## Pokémon-Amie text and UI (added for 0.3.2)

- The same English archive `a/0/7/3` holds Amie: file 81 the 26 Poké Puff names (tiers x
  Sweet / Mint / Citrus / Mocha / Spice, then Wish, Honor, Spring, Summer, Autumn, Winter), file
  110 the 34 wallpapers then every Décor item in the order of archive `a/1/4/5` (which showed
  three pairs the Bulbapedia-derived catalogue had reversed), file 111 the room (Affection /
  Fullness / Enjoyment, Switch Pokémon!, the Egg line, the gift lines with variables 0x018C
  Décor and 0x01A0 Poké Puff), file 109 the Décor drawer, file 124 the picker (game names,
  Easy .. Unlimited, "You need three Pokémon in good condition."), files 105 / 106 / 107 Tile
  Puzzle / Head It / Berry Picker (HUD words, rank titles, "Poké Puff(s) Received!"), file 123
  the short labels (PLAY / DECORATE / SWITCH, Pokémon-Amie, RESULTS). File 20 lines 9-11 are
  the three help pages (not extracted).
- Amie UI textures beyond the first pass: `a/0/2/6` entry 1 holds the PLAY / DECORATE / SWITCH
  buttons per language (sub 2 English), entry 0 the status panel (62), meter bar (1), the three
  meter icons (34 note, 35 heart, 36 the blue swirl read as Fullness), the green puff bar (3),
  a red check (4); `a/0/1/6` entry 6 the HUD digits 0-9 and "10" (44x44), entry 0 CLIM 9 the
  white HUD box, entry 7 CLIMs 31-35 the five puff tier rings and 36 the Amie wreath; `a/0/1/7`
  entry 1 CLIMs 10-12 the yarn "Chances" markers, entry 3 CLIM 25 the result box (CLIM 15 is a
  Japanese-only results banner); `a/0/1/8` entry 1 CLIM 0 the orange pill button.
- Amie's own screens (found 2026-10-17 by a scan of every GARC's darc packs; no other pack is
  Amie's): `a/0/2/6` entry 0 is a darc with `kawaii_lower.bclyt` (the room: frame, menu,
  bubbles, guests, gifts, puff) and `kawaii_windows.bclyt` (the Switch list and dialogs) and
  145 clips; `a/1/4/4` entry 0 holds `customize.bclyt` (DECORATE) and `customize_upper.bclyt`
  (its top screen) and 34 clips. Some a/0/2/6 textures were imported under first-pass names
  by CLIM index (`ui/gift` is really the room's `frame`, `check` = button_exit, `coin` =
  button_pokemon); the layout rows carry the darc names. Rows from
  `python tools/lyt_rows.py romfs amie_deco=a/1/4/4:0:0 amie_room=a/0/2/6:0:0 --
  amie_deco:customize.bclyt:amie_deco amie_deco:customize_upper.bclyt:amie_deco
  amie_room:kawaii_lower.bclyt:amie_room amie_room:kawaii_windows.bclyt:amie_room`.
- Berry Picker's screens: `a/0/1/6` entries 0-7 (NOT LZ-compressed: a name table, then the
  darc; `Darc.find` handles it) - demoanimation02, nuts, nuts_animation, balloon,
  background_rear, background_front, score (upper, 400x240), reward; the RESULTS ribbon
  `result_title` is in the English pack `a/2/1/6` entry 0 sub 2. Rows from `lyt_rows.py` with
  packs berry_demo / nuts / nutsanim / balloon / rear / front / score (+ berry_lang) / reward.
  Clip keys sit on one long master timeline (some at -760 or 400); `F.eval` holds the ends.
