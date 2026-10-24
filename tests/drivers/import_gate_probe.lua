-- Driver: the PLAYNAV gate screen's states, shot without running a real extraction
-- (states are pinned on the live Extract and restored). Also checks that opening
-- Super Training while the cache is "stale" lands on the gate instead.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/import_gate_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  -- CLEAR EXTRACTED ART may be on in the player's options: a driver run never acts on it
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  pcall(Map.load, nil, game, "EM_LITTLEROOT_TOWN", { x = 14, y = 12, facing = "down" })
  local s = Runtime.getSession()
  if s then s.x, s.y = 14, 12 end
  Player.cellX, Player.cellY, Player.px, Player.py = 14, 12, 14 * 16, 12 * 16
  Player.targetX, Player.targetY = 14, 12
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
  end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports["play_nav"]
  if not X then log("FAIL no exports"); return end
  loader.modOptions["play_nav"] = loader.modOptions["play_nav"] or {}
  loader.modOptions["play_nav"].display_mode = "combined"
  local Apps = X.apps
  local Extract = X._test.extract and X._test.extract()
  if not Extract then log("FAIL no Extract"); return end
  -- a real run may have started on boot; let it finish so the cache stays complete
  waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 120)
  U.wait(30)
  log("extract state after boot:", Extract.state, "complete:", tostring(Extract.cacheComplete()))

  local function shot(name)
    log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING")
  end
  local state0, message0, progress0 = Extract.state, Extract.message, Extract.progress

  -- the gate: a "stale" cache sends Super Training's entry to the PLAYNAV screen
  Extract.state = "idle"
  local complete0 = Extract.cacheComplete
  Extract.cacheComplete = function() return false end
  local ok, why = X.training.open()
  log("training.open while stale:", tostring(ok), tostring(why), "active:", Apps:active().id)
  U.wait(5)
  shot("g01_ready")

  -- pinned "running" must not reach the real update(): with no jobs it would conclude
  -- the run and write an empty manifest over the good cache
  local update0 = Extract.update
  Extract.update = function() end
  Extract.state = "running"
  Extract.progress = function() return 377, 845 end
  Extract.message = "a/0/2/6 entry 1..."
  U.wait(5)
  shot("g02_running")
  Extract.update = update0

  Extract.state, Extract.why = "absent", "missing"
  U.wait(5)
  shot("g03_absent")
  U.wait(50)   -- most of a flash period later: the warning at another brightness
  shot("g04_absent_pulse")
  Extract.why = "wrong"
  U.wait(5)
  shot("g04b_wrong_rom")
  Extract.state, Extract.why = "failed", "wrong"
  Extract.message = "Nothing could be read from that card image."
  U.wait(5)
  shot("g04c_wrong_after_run")
  Extract.why = nil

  Extract.state = "failed"
  Extract.message = "Background jobs are unavailable."
  U.wait(5)
  shot("g05_failed")

  local function waitSecs0(secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do U.wait(1) end
  end
  local function tapApp(id, ax, ay)
    local r = X.state().rect
    local tab = X.state().tabHeight or 0
    local x, y = r.x + ax * r.scale, r.y + (ay + tab) * r.scale
    love.touchpressed(id, x, y, 0, 0, 1); U.wait(2)
    love.touchreleased(id, x, y, 0, 0, 1); U.wait(2)
  end

  -- USE FALLBACK ASSETS (from the missing-ROM warning): the option goes off, the shutters
  -- close and the PlayNav menu opens; with the option off the apps open without the gate.
  -- options.lua is never written (writeOptions stubbed) and the option and the stored
  -- choice are put back afterwards
  do
    local C = X._test.assetChoice()
    local choice0 = C.read()
    local opts = loader.modOptions["play_nav"]
    local rom0 = opts.use_rom_assets
    local saved = game.save and game.save.options and game.save.options.modOptions
    local savedRom0 = saved and saved.play_nav and saved.play_nav.use_rom_assets
    local write0 = game.writeOptions
    game.writeOptions = function() end
    Apps:setActive("import", game)
    Extract.state, Extract.why = "absent", "missing"
    U.wait(5)
    local g = Apps:get("import")
    local fb = g.FALLBACK_ABSENT
    tapApp(11, fb.x + fb.w / 2, fb.y + fb.h / 2 + g.contentShift())
    waitSecs0(0.05)
    shot("g05b_fallback_pressed")
    waitSecs0(0.25)
    shot("g05c_fallback_shutters")
    waitSecs0(1.0)
    local ch = C.read()
    log("after fallback: option", tostring(opts.use_rom_assets), "romOn", tostring(C.romOn()),
      "choice", tostring(ch and ch.rom), tostring(ch and ch.why), "active", Apps:active().id)
    shot("g05d_fallback_menu")
    -- the gate stands down while the option is off
    local okT = X.training.open()
    log("training.open with the option off (stale cache):", tostring(okT), "active", Apps:active().id)
    U.wait(10)
    shot("g05e_training_fallback")
    if X.training.session then X.training.finish() end
    -- switched back on: checked again, the PLAYNAV screen asks
    opts.use_rom_assets = true
    loader.events:emit("mod.options_changed", { mod = "play_nav", key = "use_rom_assets", value = true })
    U.wait(5)
    log("option on again: active", Apps:active().id, "state", tostring(Extract.state))
    Extract.state, Extract.why = "idle", nil
    U.wait(5)
    shot("g05f_option_on_again")
    -- restore
    opts.use_rom_assets = rom0
    if saved and saved.play_nav then saved.play_nav.use_rom_assets = savedRom0 end
    game.writeOptions = write0
    if choice0 then C.write(choice0.rom, choice0.why) else C.remove() end
    C.apply()
    log("restored: option", tostring(opts.use_rom_assets), "choice", tostring(C.read() and C.read().rom))
  end

  -- the finale: the bar fades into the play button; a tap sinks it, the shutters
  -- close and Super Training's home opens behind them
  local function waitSecs(secs)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < secs do U.wait(1) end
  end
  local function win(ax, ay)
    local r = X.state().rect
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local function tapAt(id, ax, ay)
    local x, y = win(ax, ay)
    love.touchpressed(id, x, y, 0, 0, 1); U.wait(2)
    love.touchreleased(id, x, y, 0, 0, 1); U.wait(2)
  end
  Extract.cacheComplete = complete0
  Extract.state = "done"
  Extract.progress = progress0
  Extract.message = message0
  U.wait(3)
  shot("g06_done_fade")
  waitSecs(1.0)
  shot("g06_play")
  tapAt(9, 128, 96)
  waitSecs(0.06)
  shot("g06_pressed")
  waitSecs(0.3)
  shot("g06_shutters")
  waitSecs(0.6)
  log("after play: active", Apps:active().id, "training session:", tostring(X.training.state().mode))
  shot("g07_shutters_open")
  waitSecs(0.6)
  shot("g08_training_home")
  Extract.state = state0
  if X.training.session then X.training.finish() end

  -- CLEAR EXTRACTED ART through the real option event, with Super Training open: the
  -- session closes, the cache empties, the gate shows BEGIN EXTRACTION; then a fresh
  -- extraction restores the art (the probe never leaves the player's cache empty)
  -- destructive: only when the card image is there to rebuild from (PROBE_CLEAR=1 too)
  if not (os.getenv("PROBE_CLEAR") == "1" and Extract.importPresent()) then
    log("clear stage skipped: PROBE_CLEAR", tostring(os.getenv("PROBE_CLEAR")),
      "import present", tostring(Extract.importPresent()))
    log("DONE")
    return
  end
  X.training.open()
  U.wait(20)
  loader.events:emit("mod.options_changed", { mod = "play_nav", key = "clear_rom_art", value = true })
  U.wait(10)
  log("after clear: state", tostring(Extract.state), "complete", tostring(Extract.cacheComplete()),
    "manifest", tostring(Extract.cacheManifest() ~= nil), "active", Apps:active().id,
    "training open", tostring(X.training.session ~= nil and X.training.session.session ~= nil),
    "option back off", tostring(loader.modOptions["play_nav"].clear_rom_art ~= true))
  shot("g09_after_clear")
  local okS = Extract.start()
  log("re-extract started:", tostring(okS))
  waitFor(function() return Extract.state ~= "running" and Extract.state ~= "finishing" end, 60 * 300)
  U.wait(10)
  log("re-extract done: state", tostring(Extract.state), "complete", tostring(Extract.cacheComplete()))
  log("DONE")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
