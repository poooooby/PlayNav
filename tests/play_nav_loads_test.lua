-- The mod loads clean through the real headless loader on Gen 3, the only game
-- its manifest claims, is skipped (not failed) on Gen 1 and 2, and publishes the
-- surface for other mods. Run from the engine root:
--   luajit mods/play_nav/tests/play_nav_loads_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

for _, generation in ipairs({ 1, 2 }) do
  local run = T.sdk.loadMod("mods/play_nav", { generation = generation })
  T.eq(run.mod and run.mod.state, "wrong_generation",
    ("gen %d: the mod is skipped, Gen 3 only"):format(generation))
  T.eq(#run.errors, 0, ("gen %d: and the skip is not an error (%s)"):format(generation, tostring(run.errors[1])))
  run.release()
end

for _, generation in ipairs({ 3 }) do
  local opts = { generation = generation }
  if T.sdk.gen3Data then opts.data = T.sdk.gen3Data() end
  local run = T.sdk.loadMod("mods/play_nav", opts)
  T.eq(run.mod and run.mod.state, "loaded",
    ("gen %d: the mod loads (%s)"):format(generation,
      tostring(run.mod and run.mod.skipReason)))
  T.eq(#run.errors, 0,
    ("gen %d: no boot errors (%s)"):format(generation, tostring(run.errors[1])))
  local exports = run.loader.exports.play_nav
  T.check(type(exports) == "table", ("gen %d: exports are published"):format(generation))
  if exports then
    T.check(type(exports.pointer) == "table" and type(exports.pointer.begin) == "function",
      "the pointer stream is exported")
    local apps = type(exports.apps) == "table" and exports.apps.list or {}
    local ids = {}
    for _, a in ipairs(apps) do ids[a.id] = true end
    T.check(apps[1] and apps[1].id == "play" and ids.home and ids.decorate and ids.game_berry
      and ids.game_head and ids.game_tile and ids.import and ids.training_core,
      "play, home, decorate, the three games, import and training are registered")
    T.check(type(exports.training) == "table" and type(exports.training.open) == "function",
      "super training is exported")
    T.check(type(exports.import) == "table" and type(exports.import.check) == "function",
      "the import flow is exported")
    -- DISPLAY MODE (Kanto Gear's set): K-GEAR follows the Gear's display_mode; without the Gear it
    -- looks for a second display ("detect"); the old `display` key carries over while
    -- display_mode was never set
    local X = exports._test
    X.setGame({ mods = run.loader })   -- the loader, as the game hands it, for what is stored
    local opts3 = run.loader.modOptions
    opts3.play_nav = opts3.play_nav or {}
    local mode0, old0 = opts3.play_nav.display_mode, opts3.play_nav.display
    opts3.play_nav.display_mode = "kanto_gear"
    for gear, want in pairs({ separate = "separate", combined = "combined", fullscreen = "fullscreen",
        phone = "combined", none = "detect" }) do
      X.gearMode(gear ~= "none" and gear or nil)
      T.eq(X.displayChoice(), want, "K-GEAR with Kanto Gear on " .. gear)
    end
    X.gearMode(nil)
    for _, v in ipairs({ "fullscreen", "combined", "separate" }) do
      opts3.play_nav.display_mode = v
      T.eq(X.displayChoice(), v, v .. " is itself")
    end
    opts3.play_nav.display_mode = nil
    for old, want in pairs({ split = "combined", combined = "combined", second_screen = "separate",
        off = "detect", auto = "detect" }) do
      opts3.play_nav.display = old
      T.eq(X.displayChoice(), want, "the old DISPLAY MODE " .. old .. " carries over")
    end
    opts3.play_nav.display_mode, opts3.play_nav.display = mode0, old0
    X.setGame(nil)
    T.check(exports.import.check() ~= "running", "nothing runs headless without a card image")
    T.check(type(exports.refresh) == "table", "refresh is exported under its old name")
    T.eq(exports._test.surfaceWanted(), false, "the surface is dormant with no session")
    T.eq(exports.W, 256, "the surface is 256 wide")
    T.eq(exports.H, 230, "...and 230 tall (Kanto Gear's shape, the default)")
    T.eq(exports.state().mode, "off", "before the first frame nothing is active")

    -- CLEAR EXTRACTED ART pressed: it clears, then reads PRESS TO CLEAR again, saved (mods get
    -- no options setter; main writes where the Mod Manager does and has the engine save).
    -- The clear itself is a counter here: never the real cache.
    local Ex = exports._test.extract()
    local clear0, clears = Ex.clear, 0
    Ex.clear = function() clears = clears + 1 end
    local loader = run.loader
    local written = 0
    local savedOpts = { modOptions = { play_nav = { clear_rom_art = true } } }
    exports._test.setGame({ mods = loader, save = { options = savedOpts },
      writeOptions = function() written = written + 1 end })
    loader.modOptions.play_nav = loader.modOptions.play_nav or {}
    local before = loader.modOptions.play_nav.clear_rom_art
    loader.modOptions.play_nav.clear_rom_art = true
    loader.events:emit("mod.options_changed", { mod = "play_nav", key = "clear_rom_art", value = true })
    T.eq(clears, 1, "CLEAR EXTRACTED ART pressed: the art is cleared")
    T.eq(loader.modOptions.play_nav.clear_rom_art, false, "...the option reads PRESS TO CLEAR again")
    T.eq(savedOpts.modOptions.play_nav.clear_rom_art, false, "...in the saved options too")
    T.eq(written, 1, "...and the engine writes them")
    Ex.clear = clear0
    loader.modOptions.play_nav.clear_rom_art = before

    -- 3D SUPER TRAINING: built, off by default, switched live from the options screen
    local TRx = exports.training
    local Draw = TRx and TRx.session and TRx.session.arenaDraw
    T.check(Draw ~= nil and Draw.arena3d ~= nil, "the 3D arena is built")
    if Draw then
      T.eq(Draw.mode3d, false, "3D SUPER TRAINING is off by default")
      loader.events:emit("mod.options_changed", { mod = "play_nav", key = "training_3d", value = true })
      T.eq(Draw.mode3d, true, "...switched on, regimens draw in 3D")
      loader.events:emit("mod.options_changed", { mod = "play_nav", key = "training_3d", value = false })
      T.eq(Draw.mode3d, false, "...and off again")
    end
  end
  run.release()
end

T.finish("play_nav loads")
