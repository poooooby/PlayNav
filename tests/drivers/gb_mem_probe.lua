-- Driver: memory over time on the Game Boy games. Opens Super Training's home, then the regimen
-- picker, and holds each a while, logging every PROBE_STEP seconds the Lua heap (KB), the GPU's
-- texture memory (MB), images, canvases, fonts and draw calls (love.graphics.getStats) and the
-- frame rate: anything that piles up shows as a column that only climbs.
--   SHOT_DIR=<dir> POKEPORT_GAME=yellow POKEPORT_VERSION=yellow POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/gb_mem_probe.lua love .
--   (PROBE_HOLD seconds per screen, default 20; PROBE_FALLBACK=1 NaviPlay's own assets)

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
  U.wait(2)
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  if os.getenv("PROBE_FALLBACK") == "1" and X and X._test and X._test.forceRom then X._test.forceRom(false) end
  local gen
  if game.world then
    gen = 2
    waitFor(function() return game.world and game.world.map end, 900)
  else
    gen = 1
    if not U.newGame(game) then log("FAIL no overworld"); return end
  end
  U.wait(30)
  X = game.mods.exports.play_nav
  local loader = game.mods
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = os.getenv("PROBE_DISPLAY") or "combined"
  -- (HD RENDERING off for this run only: keepArt keeps it out of options.lua)
  if os.getenv("PROBE_HD") == "0" then loader.modOptions.play_nav.hd_render = false end
  -- LOW POWER MODE for this run only
  if os.getenv("PROBE_LOWPOWER") == "1" then loader.modOptions.play_nav.low_power = true end
  if X.import and os.getenv("PROBE_FALLBACK") ~= "1" then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local data = game.data
  local function newMon(species, level)
    if gen == 1 then return require("src.pokemon.Pokemon").new(data, species, level) end
    return require("src.battle.gen2.Mon").new(data, species, level)
  end
  game.save.party = { newMon(gen == 1 and "PIKACHU" or "CYNDAQUIL", 20), newMon("PIDGEY", 8), newMon("RATTATA", 6) }
  U.wait(10)

  -- every texture of 1 MB or more made from here on: its size and the NaviPlay file that made it
  do
    local G = love.graphics
    local function watch(name)
      local orig = G[name]
      G[name] = function(...)
        local obj = orig(...)
        local ok, w, h = pcall(function() return obj:getPixelDimensions() end)
        if ok and w and h and w * h * 4 >= 1048576 then
          local tb = debug.traceback("", 2)
          local file = tb:match("play_nav[/\\]([%w_/\\]+%.lua:%d+)") or tb:match("mods[/\\]([%w_%-/\\]+%.lua:%d+)") or "?"
          log(("  %s %dx%d (%.1f MB) from %s"):format(name, w, h, w * h * 4 / 1048576, file))
        end
        return obj
      end
    end
    watch("newImage"); watch("newCanvas")
  end

  local HOLD = tonumber(os.getenv("PROBE_HOLD")) or 20
  local STEP = tonumber(os.getenv("PROBE_STEP")) or 2
  local function sample(label)
    local st = love.graphics.getStats()
    local ps = X.state()
    log(("%-8s display %s  push %sx"):format(label, tostring(ps.mode), tostring(ps.pushK)))
    log(("%-8s lua %8.0f KB  tex %7.1f MB  images %4d  canvases %3d  fonts %3d  draws %4d  fps %3d"):format(
      label, collectgarbage("count"), (st.texturememory or 0) / 1048576, st.images or 0, st.canvases or 0,
      st.fonts or 0, st.drawcalls or 0, love.timer.getFPS()))
  end
  -- the garbage made a second: every frame's rise in the heap summed (a collection's fall left
  -- out), over the hold
  local function hold(label)
    local t0 = love.timer.getTime()
    local nextAt = t0
    local made, last = 0, collectgarbage("count")
    while love.timer.getTime() - t0 < HOLD do
      if love.timer.getTime() >= nextAt then
        sample(label)
        nextAt = nextAt + STEP
      end
      U.wait(1)
      local now = collectgarbage("count")
      if now > last then made = made + (now - last) end
      last = now
    end
    log(("%-8s garbage %.0f KB a second"):format(label, made / (love.timer.getTime() - t0)))
  end

  hold("field")
  local TR = X.training
  log("training open:", tostring(TR.open()))
  local T = TR.session
  waitFor(function() return T.session and T.session.mode == "core" and not T.session.trans end, 600)
  hold("home")
  U.shot(game, (os.getenv("SHOT_DIR") or ".") .. "/mem_home.png")
  T.enterCourses()
  waitFor(function() return T.session.mode == "courses" and not T.session.trans end, 600)
  -- a course picked, as a player does: its card is what the top screen draws
  T.session.picked = os.getenv("PROBE_COURSE") or "lv1_hp"
  U.wait(10)
  -- NaviPlay's own share of the picker's garbage: each of its per-frame calls wrapped to count
  -- what it allocates
  local spent, frames = {}, 0
  local function wrap(tbl, key, name)
    local f = tbl and tbl[key]
    if type(f) ~= "function" then return function() end end
    tbl[key] = function(...)
      local k0 = collectgarbage("count")
      local a, b, c, d = f(...)
      local dk = collectgarbage("count") - k0
      if dk > 0 then spent[name] = (spent[name] or 0) + dk end
      return a, b, c, d
    end
    return function() tbl[key] = f end
  end
  local undo = {
    wrap(T, "drawCard", "the card (top)"), wrap(T, "tick", "session tick"),
    wrap(X.apps, "draw", "touch screen draw"), wrap(X.apps, "update", "apps update"),
    wrap(X.hdTop, "draw", "top screen redraw"), wrap(X._test, "tick", "frame tick"),
  }
  local f0 = 0
  local t0 = love.timer.getTime()
  hold("picker")
  local secs = love.timer.getTime() - t0
  for name, kb in pairs(spent) do log(("  picker: %-20s %7.0f KB a second"):format(name, kb / secs)) end
  for _, u in ipairs(undo) do u() end
  U.shot(game, (os.getenv("SHOT_DIR") or ".") .. "/mem_picker.png")
  T.goTo("core")
  waitFor(function() return T.session.mode == "core" and not T.session.trans end, 600)
  hold("home2")
  collectgarbage("collect")
  sample("after gc")
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
