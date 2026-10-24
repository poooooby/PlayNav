-- Driver: DISPLAY MODE SEPARATE SCREENS with PLAYNAV OUTPUT MAIN SCREEN: PlayNav on the main
-- window and the game sent to the second display (the engine's SecondScreen bridge stood in
-- for: it keeps what it is handed). Logs the mode, the frames the "second display" got (size,
-- rate, the hint) and saves the last one; QUICK SWAP turns it back to PlayNav on the second
-- display. Options and the bridge are put back at the end; options.lua is never written.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/output_probe.lua love .

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
  local function waitSecs(s)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < s do U.wait(1) end
  end
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
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
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end

  -- the second display: what it is handed is kept
  local SS = require("src.render.SecondScreen")
  local saved = {}
  for _, k in ipairs({ "usable", "available", "detected", "push", "pollTouch", "setEnabled" }) do saved[k] = SS[k] end
  local got = { n = 0 }
  SS.usable = function() return true end
  SS.available = function() return true end
  SS.detected = function() return true end
  SS.push = function(image, w, h, bg, hint)
    got.n, got.w, got.h, got.hint, got.last = got.n + 1, w, h, hint, image
    got.first = got.first or love.timer.getTime()
    got.at = love.timer.getTime()
    return true
  end
  SS.pollTouch = function() return nil end
  SS.setEnabled = function() return true end
  local opts = loader.modOptions.play_nav
  local mode0, target0 = opts.display_mode, opts.display_target
  opts.display_mode, opts.display_target = "separate", "handheld"
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end

  local ok, err = pcall(function()
    log("amie open:", X.amie.open())
    waitFor(function() return X.state().mode == "handheld" end, 300)
    log("display mode:", X.state().mode)
    got.n, got.first = 0, nil
    waitSecs(2)
    local rate = got.first and got.at > got.first and (got.n - 1) / (got.at - got.first) or 0
    log(("second display got %d frames, %dx%d, %.0f a second, hint %s"):format(got.n, got.w or 0, got.h or 0,
      rate, tostring(got.hint)))
    local r = X.state().rect
    log("playnav on the main window:", r and ("%d,%d %dx%d @%.3f"):format(r.x, r.y, r.w, r.h, r.scale) or "none")
    shot("o01_main_window")
    if got.last and got.last.encode then
      local okE = pcall(function() got.last:encode("png", "o02_second_display.png") end)
      log("second display frame saved:", tostring(okE), "(LOVE save dir)")
    end
    -- QUICK SWAP on: Y turns it round (PlayNav to the second display)
    opts.screen_swap = true
    local S = X._test.state
    S.swapped = true
    U.wait(10)
    log("after quick swap:", X.state().mode)
    S.swapped = nil
    U.wait(10)
    log("swapped back:", X.state().mode)
  end)
  if not ok then log("ERROR", tostring(err)) end
  if X.amie.session then pcall(X.amie.finish) end
  U.wait(10)
  log("closed:", X.state().mode)
  opts.display_mode, opts.display_target, opts.screen_swap = mode0, target0, nil
  for k, v in pairs(saved) do SS[k] = v end
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
