-- Driver: PlayNav first on the second display. A stand-in for Kanto Gear wraps
-- render.compose at its priority (-1000) and does what it does every frame:
-- setEnabled, detected, push, pollTouch through ctx.secondScreen. The real
-- bridge's push is counted per sender while PlayNav is idle, while Super
-- Training is open, and after it closes.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/second_priority_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
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
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 30)
  end
  U.wait(30)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end

  local SS = require("src.render.SecondScreen")
  local count = { kg = 0, pn = 0, other = 0 }
  local realPush = SS.push
  SS.push = function(img, w, h, bg, pref)
    if pref == "kg" then count.kg = count.kg + 1
    elseif pref == "secondary" then count.pn = count.pn + 1
    else count.other = count.other + 1 end
    return realPush(img, w, h, bg, pref == "kg" and "secondary" or pref)
  end
  local kg = { frames = 0, detectedFalse = 0, proxied = 0 }
  local blank
  loader.hooks:wrap("render.compose", function(next, renderer, ctx)
    local c = ctx and ctx.secondScreen
    if c then
      kg.frames = kg.frames + 1
      if c ~= SS then kg.proxied = kg.proxied + 1 end
      c.setEnabled(true)
      if c.detected() then
        if not blank and love.image then blank = love.image.newImageData(8, 6) end
        if blank then c.push(blank, 8, 6, 0, "kg") end
      else
        kg.detectedFalse = kg.detectedFalse + 1
      end
      for _ = 1, 8 do if not c.pollTouch() then break end end
    end
    return next()
  end, -1000, "kanto_gear_standin")

  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display = "second_screen"
  local detected = waitFor(function() local ok, d = pcall(SS.detected); return ok and d end, 600)
  log("companion detected", detected, "usable", SS.usable())
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end

  local function phase(name, frames)
    count.kg, count.pn, count.other = 0, 0, 0
    kg.frames, kg.detectedFalse, kg.proxied = 0, 0, 0
    U.wait(frames)
    log(("%s: mode %s | real pushes kg %d playnav %d other %d | stand-in frames %d proxied %d saw-no-display %d")
      :format(name, X._test.state.mode, count.kg, count.pn, count.other, kg.frames, kg.proxied, kg.detectedFalse))
    return count.kg, count.pn
  end

  local kgIdle = phase("idle", 60)
  local TR = X.training
  log("open training:", TR.open())
  local kgOpen, pnOpen = phase("training open", 120)
  TR.session.finish()
  U.wait(2)
  local kgAfter = phase("closed", 60)
  log(("RESULT %s"):format((kgIdle > 0 and kgOpen == 0 and pnOpen > 0 and kgAfter > 0) and "PASS" or "FAIL"))
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
