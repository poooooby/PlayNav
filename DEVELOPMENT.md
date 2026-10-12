# PlayNav: developer guide

For mod authors and contributors. Players only need the [README](README.md).

The mod's id is `play_nav`; it was `ds_touch` in the early test builds (see "Renamed from
ds_touch" below). Gen 3 is the only supported generation (`games: ["gen3"]`).

## How it works

- **The surface.** A 256x192 logical touch screen (`src/surface.lua`). In split mode it is
  blitted into a window rect beside or below the game picture (Gen 3 places its picture through
  the `Playfield.cutout` seam, wrapped by `src/cutout.lua`); in second-screen mode it is read
  back and pushed through the engine's SecondScreen bridge, whose touches come back. It stays
  dormant until the active app's `wantsSurface()` is true.
- **Second display priority.** `main.lua` wraps `render.compose` at priority 1000, outside
  every other compose mod (Kanto Gear wraps at -1000), and replaces `ctx.secondScreen` with
  the proxy from `src/second_gate.lua`. While PlayNav is in second-screen mode the proxy
  reports `detected() == false`, swallows `push` and returns no touches, so downstream mods
  treat the display as disconnected; leaving the mode passes everything through again and
  re-enables the display as the downstream mod last asked. Driver:
  `tests/drivers/second_priority_probe.lua`.
- **High resolution.** The surface renders at the output's pixel density (`src/hd.lua`
  `density`, up to 4x) under a `scale(k)` transform, so apps keep 256x192 coordinates. The two
  top-screen layers (Amie and Super Training, Gen 3 UI-stack layers) are redrawn over the
  finished frame in `render.hud` at window resolution while they are the top of the stack
  (`src/hd_top.lua`). ORAS textures are mipmapped and linear; GBA pixel art goes through
  `HD.drawPixel` (nearest at whole multiples, a sharp-bilinear shader otherwise).
- **Pokémon-Amie** (`src/amie/`): pure rules over `data/amie_rules.lua`, the session (modes,
  the top layer), the play / room / decorate / minigame apps, the battle-benefit hooks.
- **Super Training** (`src/training/`): pure rules over `data/training_rules.lua`, the pure
  regimen simulation (`sim.lua`), the session and regimen flow, the Core / bags / courses / aim
  apps and the top-screen arena renderer. Balloon Bots are the species' front sprite: its alpha
  mask becomes a shape of cells the goals stand on and walk across.
- **Alpha Sapphire import** (`src/import/`): pure-Lua readers for NCSD / NCCH / RomFS, GARC,
  LZ11, BCLIM (including ETC1) and Gen 6 text, run in background jobs. `data/oras_recipe.lua`
  says which archive, entry and texture (or text file) each asset is; the mod ships the recipe
  and the decoders, never game data. Results land in the per-id `mod.cache`.
- **Game text.** `src/amie/text.lua` and the Super Training session read the decoded English
  text (`Assets.text(id)`) and fall back to the mod's own wording.

Every number with no public source is in a data file with an `EVIDENCE` row (verified /
measured / inferred / placeholder, source, confidence); tests fail when one is missing.

## The Amie stats

Affection, fullness and enjoyment run 0..255 per Pokémon in the mod's own save data (keyed by
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
| A minigame (each participant) | | −110 | +80 (+30 Easy / Normal Tile Puzzle) |

Benefits: 2 hearts 1.2x experience; 3 hearts endure at 1 HP (10%, 15% at 4 hearts, 20% at 200
affection, 25% at 5 hearts); 4 hearts 20% status cure at the end of a turn; 200 affection
−10 foe accuracy; 5 hearts doubled critical-hit chance. Skipped in link, facility and tutorial
battles.

## For other mods

`mod.find("play_nav").exports` gives:

- `pointer` - the touch stream: `pointer:each()`, `pointer:get(id)`, `pointer:on(fn)`, helpers
  `pointer.isTap(rec)`, `isHold(rec, secs)`, `swipe(rec)`, `speed(rec)`. Records carry `x, y,
  vx, vy, travel, path, pressure`.
- `apps:register({ id, title, draw(G, w, h), update(dt, game), pointer(ev, rec, game),
  wantsSurface(), hideTabs })` - an app on the surface. Return `true` from `wantsSurface` while
  you need the screen and it wakes. The app area is 256 x (192 - 14) logical units; an app with
  `hideTabs` gets no title strip and may paint its backdrop up into it (`app.bleed`).
- `amie` - `open(mon)`, `openPlay(mon)`, `state()`, `puffs()`, `meters(key)`, `rules`,
  `petting`, `care`, `store`, `session` (`enterPlay`, `enterGames`, `enterDecorate`,
  `startGame(id, diff)`, `switchTo`), `games`, `decor`, `visitors` (`force`, `claim`,
  `pending`), `benefits`. `exports.refresh` is the same table under the first build's name.
- `training` - `open`, `finish`, `state`, `session`, `rules`, `store`, `items`, `host`,
  `courses`, `sim`.
- `assets`, `layout`, `W`, `H`, `state()`.

## Developing

The repo root is the mod root; link it into the engine as a directory junction:

```bat
mklink /J C:\Users\<you>\Documents\GitHub\gen1recomp\mods\play_nav C:\Users\<you>\Documents\GitHub\PlayNav
```

Headless suites, from the engine root: `luajit mods/play_nav/tests/<name>.lua` for
`amie_rules_test`, `petting_test`, `games_test`, `decor_test`, `care_test`,
`refresh_flow_test` (the whole Amie session against a fake host), `layout_test`,
`amie_text_test`, `hd_test`, `second_gate_test`, `training_rules_test`, `training_courses_test`,
`training_sim_test` (the regimen, seeded), `training_flow_test`, `play_nav_loads_test`,
`rename_test`, `pointer_stream_test` (skips: Gen 3 only), `import_fixtures_test` (a synthetic
card image in `tests/fixtures/`, no ROM bytes), `oras_local_test` (the real dump; skips when
absent) and `release_test`.

Static checks: `python tools/modkit.py validate mods/play_nav --base imported`, `lint`,
`gen3check`.

Real windows on Emerald (PNGs into `SHOT_DIR`):

```sh
SHOT_DIR=/tmp/play_nav POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
POKEPORT_DRIVER=mods/play_nav/tests/drivers/emerald_shot.lua love .
```

- `emerald_shot.lua` - Amie end to end: the room, care after battle, petting, puffs, the
  minigames, Décor and visitors, benefits, the second display. `SHOT_W` / `SHOT_H` set the window;
  `PLAYNAV_HD=0` compares against the low-resolution path.
- `training_probe.lua` - Super Training: a bag to completion, a regimen played with the pad,
  the result, a Wing from the bag.
- `balloon_probe.lua` - several regimens' Balloon Bots and goals over time
  (`BALLOON_COURSES`, `BALLOON_MOVE`).
- `games_probe.lua`, `split_probe.lua` - the minigame loop; the split-screen presets.
- `second_priority_probe.lua` - PlayNav taking the second display from a compose mod and
  handing it back.

For in-game testing with the art, hard-link the dump to `baseroms/alpha_sapphire_rev2.cci`
with its receipt. `baseroms/` is git-ignored.

### Reading the game's own layouts, animations and live numbers

- **Layouts and animations.** Each 3DS screen's textures come in a darc pack with the game's
  layout (`.bclyt`) and animation (`.bclan`) files. `tools/garc_blob.py` writes an archive
  entry's decompressed blob, `tools/darc.py` lists the pack, `tools/clyt.py` prints the pane
  tree (centres in 320x240, sizes, vertex colours, textures) and `tools/clan.py` the animation
  keys (hermite frame / value / slope, 30 fps). Super Training's home screen is drawn from
  these; use them instead of measuring screenshots.
- **Live memory (Azahar's GDB stub).** With the game running in Azahar and its GDB stub on
  (Emulation > Configure > Debug, port 24689), `tools/gdbrsp.py` reads the running game:
  `python tools/gdbrsp.py ping | regs | read <addr> <len> | dump <addr> <len> <out>`. Send `?`
  first on a connection (the CLI does); code is at `0x00100000`, the heap at `0x08000000`, the
  linear heap at `0x14000000`. Breakpoints and watchpoints work (`Z0`-`Z4`), so the code
  that writes a value can be caught by watching its address. Use it to measure what the files do not hold (timers, odds, the
  regimen table built by `DllSparring.cro`): snapshot, act in the game, snapshot again, diff.
  Only the numbers go into `data/`, never game bytes.

- **The game's code (rules without guessing).** The 3DS code modules (`romfs/Dll*.cro`) and the
  main program hold the real numbers in their data tables and literal pools. `tools/cro.py`
  (needs `pip install capstone`; run it without `python -I`, which hides per-user packages):
  `segs <cro>`, `data <cro>` (read-only data as ints and floats), `asm <cro> <out>`,
  `refs <cro> <offset>` (the code that loads a constant), `find <file> float|int <values...>`,
  `words <file> <addr> <len> --base 0x100000`. Super Training: `DllSparring.cro` (regimens:
  the bag table at .rodata 0x18030, charge stages, per-difficulty records, the 180 s clock as
  5400 frames), `DllSparringMenu.cro` (the course picker: Effort-o-Meter EV-to-radius steps,
  course rows), and the main program (dump it from Azahar: `gdbrsp.py dump 0x00100000
  0x715000 code.bin`; the home screen's tables are around 0x007EC5A0-0x007ED1D0). The training
  bag table is { kind, value (float), hits / 5 } per bag. Cite the address in the data file's
  `EVIDENCE` row.

Tools (development only, not shipped): `tools/README.md` describes the extraction pipeline
that produced the recipe and the data generators (`petting_table.py`, `decor_catalog.py`,
`shot_types.py`, `items_pokeapi.py`, `gen6_text.py`, `st_evidence.py`).

## Releasing

1. Bump `manifest.json` and add the CHANGELOG entry; push.
2. Clone the pushed repo into a scratch folder and pack **the clone**:
   `python tools/modkit.py pack <clone> -o play_nav-X.Y.Z.zip`. Never pack the working folder:
   it holds `baseroms/`.
3. List the zip; it must hold only the mod (no `tests/`, `tools/`, `baseroms/`, game art).
4. `gh release create vX.Y.Z play_nav-X.Y.Z.zip`.

`.modkitignore` matches exact file paths only, never folders: every file under `tests/` and
`tools/`, plus `CLAUDE.md`, `DEVELOPMENT.md` and the dotfiles, is listed by path.
`release_test` fails when a new one is missing.

## Known limits (technical)

- Gen 3 has no `input.pointer` seam, so single-screen touch is routed by wrapping the engine's
  touch controls, and a desktop mouse by wrapping the Gen 3 mouse handlers (`engine_internals`).
  While a mouse button is held on the surface the cursor is also polled every frame.
- Petting spots are zones over the front sprite (head, face, cheeks, chest, belly, side, limbs,
  bottom) mapped from Bulbapedia's text. Every Pokémon takes three bites of a puff: Gen 3 has no
  species size table.
- The desktop companion window for the second display reports press and release only.
- Azahar `.zcci` files cannot be validated (their metadata carries a timestamp, so no MD5 can
  match) and need a zstd decoder the engine lacks. Ultra Moon is over the engine's 2 GiB
  import cap. Deleting the ROM copy after extraction is manual; no mod API exists.
- Super Training's points, damage, energy, charge timings, odds and attack schedules are
  provisional (`data/training_rules.lua` EVIDENCE).
- The ten new items live at ids 400-409.

## Renamed from ds_touch

The engine keys save data and Mod Manager options by id. On the first load of a save with
`ds_touch` data, `src/rename.lua` copies it into `play_nav`'s record once (a `renamedFrom`
marker) and leaves the old record in place; options set under the old id fill any option not set
under the new one. The extracted art lives in a per-id cache, so it is extracted once more.
