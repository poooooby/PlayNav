# State machines

NaviPlay's behaviour is a set of small state machines. Most keep their state in a plain field
(`s.mode`, `st.phase`, ...) that many places read. `src/fsm.lua` declares the states and the
legal moves of the ones listed under "Declared"; a change goes through `machine:enter(obj,
field, to, why)`, which assigns the field exactly as before, checks the declared edge and logs
once (`state machine <name>: undeclared transition a -> b`) when it is not declared. It never
blocks. `mod.exports.machines()` returns every declared machine (states, edges, last moves,
violation count) for probes.

Adding a mode or phase: declare it in its machine's table first, then write it with the
machine's choke point (`enterMode`, `setPhase`). `tests/fsm_test.lua` fails if a session writes
`s.mode` anywhere else.

## Declared

| Machine | Field | States | Choke point |
|---|---|---|---|
| `amie.mode` | `s.mode` (Amie session) | home, play, decorate, game | `enterMode` in `src/amie/session.lua` |
| `training.mode` | `s.mode` (Super Training) | core, bags, courses, regimen, result, rocket | `setMode` in `src/training/session.lua` |
| `berry.phase` | `st.phase` | countdown, play, timeUp, rain, smoke, buttons | `setPhase` in `src/amie/games/berry_picker.lua` |
| `head.phase` | `st.phase` | intro, demo, ready, play, timeup, leave, giant, results, smoke, buttons | `setPhase` in `head_it.lua` |
| `tile.phase` | `st.phase` | intro, shuffle, start, play, next, view, finished, smoke, buttons | `setPhase` in `tile_puzzle.lua` |
| `amie.visitor` | `v.state` | enter, decide, stay, chat, leave | `go` in `src/amie/visitors.lua` |
| `main.display` | `state.mode` | off, split, second_screen, handheld | `setMode` in `main.lua` |
| `import.extract` | `Extract.state` | idle, absent, complete, running, finishing, done, failed | `setState` in `src/import/extract.lua` |
| `training.sim` | `sim.phase` | countdown, play, between, clear, timeout | `setPhase` in `src/training/sim.lua` |

Each game's `running` group is the set of phases in which the run can still be quit or force-ended.

## Not declared yet (still implicit)

Listed by risk. Each has its states in a comment next to the field.

- Training `s.trans` (screen change, `{ to, from, t, switched }`, stepped by `stepTrans`; main.lua writes a
  `from = "gate"` one) and the overlay tables `s.anim.finish / gift / rocket`, `s.outro`.
- Amie PLAY (`src/amie/play.lua`, file-local): `wake.stage` asleep, exclaim, flash, awake, dozing,
  sick, ball; `feed.stage` flash, eat, after; `picker.stage` badge, diff; with `touch`, `drag`,
  `jump`. `app:update` sits at LuaJIT's 60-upvalue limit, so a new upvalue there needs another
  one removed first.
- The import gate's other flags (`extractChecked`, `gateDisabled`, the asset choice file), the second-display
  flags (`ssEnabled`, `ssShown`), the home, decorate (`mode` browse, drawer, hold), menu and import apps.
