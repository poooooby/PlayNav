-- Driver: the controller through every screen that takes it, by real pad presses (U.tap, the
-- engine's input queue, so they reach NaviPlay's layers as a controller's do): Super
-- Training's regimen picker (the D-pad's selection, A to select / start) and its results (A
-- through the pages); Amie's PLAY (A to wake, SELECT for the drawer, A for the picker), the
-- picker into a game; each minigame's pad (Head It's three Pokemon, Tile Puzzle's cursor and
-- a swap that puts a tile home, the end buttons' focus, A and B); DECORATE's left / right.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/pad_probe.lua love .

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
  local function waitSecs(s) local t = love.timer.getTime(); while love.timer.getTime() - t < s do U.wait(1) end end
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
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) < 3 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 12)
    Party.giveMon(s0, C:require("species", "SPECIES_WURMPLE"), 8)
  end
  U.wait(30)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function press(btn, n) for _ = 1, n or 1 do U.tap(game, btn); U.wait(4) end end

  -- ------- Super Training: the regimen picker and the results
  do
    local TR = X.training
    local T = TR.session
    log("training open:", TR.open())
    T.session.rec.fully = true
    for _, c in ipairs(T.courseList()) do TR.store.cleared()[c.id] = true end
    T.REGIMEN_SHOW = true
    T.goTo("courses")
    waitFor(function() return TR.state().mode == "courses" and not T.session.trans end, 600)
    U.wait(10)
    local function picked() return T.session.picked or "none" end
    press("right"); log("pad right: picked", picked())
    press("right"); log("pad right: picked", picked())
    press("down"); log("pad down: picked", picked())
    press("left"); log("pad left: picked", picked())
    press("up"); log("pad up: picked", picked())
    press("right", 3); log("pad right x3 (past the page's end):", picked())
    shot("k01_picker_pad")
    press("left", 3); log("pad left x3 (back a page):", picked())
    press("a"); log("pad A on the selected one: mode", TR.state().mode, "trans", tostring(T.session.trans ~= nil))
    waitFor(function() return T.sim ~= nil end, 3000)
    waitFor(function() return T.sim and T.sim.phase == "play" end, 3000)
    U.wait(30)
    log("regimen running:", T.sim and T.sim.phase)
    T.forceEnd({ clear = true, remaining = 30 })
    waitFor(function() return TR.state().mode == "result" end, 60 * 30)
    U.wait(30)
    local Rs = T.results
    local pages = Rs and Rs.list and #Rs.list or 0
    log("results:", pages, "pages, on", Rs and Rs.page)
    for k = 1, pages + 2 do
      waitSecs(0.4)
      press(k % 2 == 0 and "b" or "a")
      if TR.state().mode ~= "result" then break end
    end
    waitFor(function() return TR.state().mode == "courses" end, 600)
    log("after A / B through the results: mode", TR.state().mode)
    T.finish()
    U.wait(10)
  end

  -- ------- Amie: PLAY, the picker, the minigames
  local A = X.amie
  local S = A.session
  local Apps = X.apps
  log("amie open play:", A.openPlay())
  U.wait(20)
  local play = Apps:get("play")
  local pst = function() return play.state() end
  log("asleep:", pst().wake)
  press("a"); log("pad A: wake", pst().wake)
  waitFor(function() return pst().wake == "awake" end, 1200)
  U.wait(10)
  local jar = A.puffs()
  for _, p in ipairs(A.rules.PUFFS) do A.rules.jarAdd(jar, p.id) end
  press("select"); waitSecs(0.5); log("pad SELECT: drawer", ("%.2f"):format(pst().strip))
  press("right", 3); waitSecs(0.4); log("pad right x3 in the drawer: scroll", ("%.1f"):format(pst().scroll))
  press("select"); waitSecs(0.5); log("pad SELECT again: drawer", ("%.2f"):format(pst().strip))
  press("a"); U.wait(10); log("pad A: picker", pst().picker and pst().picker.stage)

  local function game(id)
    -- from the picker: right to the game, A for its difficulties, A to start the selected one
    local order = { berry = 1, head = 2, tile = 3 }
    while (pst().picker and pst().picker.game or 1) > 1 do press("left") end
    press("right", order[id] - 1)
    press("a"); U.wait(10)
    press("a"); U.wait(20)
    log(("%s: mode %s app %s"):format(id, tostring(S.session and S.session.mode), tostring(Apps:active() and Apps:active().id)))
    return Apps:get("game_" .. id)
  end
  local function toButtons(app, value)
    if app.forceEnd then app.forceEnd(value or 3) end
    waitFor(function() local st = app.debugState(); return st and st.phase == "buttons" end, 60 * 60)
    U.wait(10)
  end
  local function backToPicker()
    waitFor(function() return S.session and S.session.mode == "play" end, 600)
    U.wait(10)
    if not pst().picker then press("a"); U.wait(10) end
  end

  -- Head It: left / up / right head the three Pokemon
  do
    local app = game("head")
    waitFor(function() local st = app.debugState(); return st and st.phase == "play" end, 60 * 60)
    local st = app.debugState()
    -- wait for the third Pokemon (all three slots), then press each when its ball is in the window
    local hits0 = st.hits or 0
    local tries = 0
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 20 and (st.hits or 0) - hits0 < 4 do
      local slot = app.nextTap("just") or app.nextTap("good")
      if slot then
        press(slot == 2 and "left" or (slot == 3 and "right" or "up"))
        tries = tries + 1
      else
        U.wait(1)
      end
    end
    log(("head it: %d pad presses on a ball in the window, %d hits"):format(tries, (st.hits or 0) - hits0))
    shot("k02_head_pad")
    toButtons(app, 40)
    press("down"); log("head it buttons: focus", tostring(app.debugState().focus))
    press("down"); log("...down: focus", tostring(app.debugState().focus))
    shot("k03_head_focus")
    press("b")
    backToPicker()
    log("after B on the buttons: mode", S.session and S.session.mode)
  end

  -- Tile Puzzle: A to begin, the cursor and a swap that puts a tile home
  do
    local app = game("tile")
    waitFor(function() local st = app.debugState(); return st and st.phase == "intro" end, 600)
    U.wait(30)
    press("a")
    waitFor(function() local st = app.debugState(); return st and st.phase == "play" and not app.busy() end, 60 * 60)
    U.wait(10)
    local st = app.debugState()
    local pz = st.pz
    local g = pz.g
    local function walkTo(pos)
      if not pz.cursor then press("right"); U.wait(2) end   -- shows the cursor at the first tile
      local c, r = (pos - 1) % g.cols, math.floor((pos - 1) / g.cols)
      for _ = 1, 20 do
        local cc, cr = (pz.cursor - 1) % g.cols, math.floor((pz.cursor - 1) / g.cols)
        if cc == c and cr == r then break end
        if cc < c then press("right") elseif cc > c then press("left")
        elseif cr < r then press("down") else press("up") end
      end
    end
    local pos, at = app.nextMove()
    log("tile: put tile", pos, "home from", at, "; correct before", pz.correct)
    walkTo(at); press("a")
    walkTo(pos)
    shot("k04_tile_cursor")
    press("a")
    waitFor(function() return not app.busy() end, 600)
    U.wait(10)
    log(("tile: after the swap, tile %s home %s; correct %d"):format(tostring(pos), tostring(pz.tiles[pos] == pos), pz.correct))
    toButtons(app, 60)
    press("down"); press("down")
    log("tile buttons: focus", tostring(app.debugState().focus))
    shot("k05_tile_focus")
    press("up", 2); press("a"); U.wait(20)
    log("A on View Picture: phase", app.debugState() and app.debugState().phase)
    press("b"); U.wait(20)
    log("B back from the picture: phase", app.debugState() and app.debugState().phase)
    press("b")
    backToPicker()
    log("after B: mode", S.session and S.session.mode)
  end

  -- Berry Picker: its end buttons; A on Play Again starts another round
  do
    local app = game("berry")
    waitFor(function() local st = app.debugState(); return st and st.phase == "play" end, 60 * 60)
    toButtons(app, 12)
    local before = app.debugState()
    press("a"); U.wait(20)
    log("berry: A on Play Again: a new round", tostring(app.debugState() ~= before), "phase", app.debugState() and app.debugState().phase)
    toButtons(app, 5)
    press("b")
    backToPicker()
    log("after B: mode", S.session and S.session.mode)
  end

  -- DECORATE: left / right through the wallpapers
  do
    press("b"); U.wait(10)   -- the picker folds
    S.finish(); U.wait(10)
    A.open(); U.wait(30)
    S.enterDecorate()
    local deco = Apps:get("decorate")
    waitFor(function() return deco.busy and not deco.busy() end, 1200)
    waitSecs(1.5)   -- past the fade in, which takes no input (touch or pad)
    local function step(btn)
      local w0 = A.store.room().wallpaper
      press(btn)
      waitSecs(0.8)
      waitFor(function() return not deco.busy() end, 600)
      log(("decorate: pad %s: wallpaper %s -> %s"):format(btn, tostring(w0), tostring(A.store.room().wallpaper)))
    end
    step("right"); step("left"); step("right")
    S.finish()
  end
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
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
