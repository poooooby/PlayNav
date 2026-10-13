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
