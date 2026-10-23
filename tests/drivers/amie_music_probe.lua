-- Driver: Pokemon-Amie's minigame music. Berry Picker's theme (bgm/kw_game01) plays from the
-- game's start with the field's music held; at 30 s left it moves to the x1.125 render and at
-- 10 s to the x1.25, on from the same point in the song; TIME'S UP brings the x1 back; back on
-- PLAY the field's music returns. Head It and Tile Puzzle play GAME02 / GAME03.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/amie_music_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
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
    log("FAIL boot phase not reached")
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s0 = Runtime.getSession()
  if #(s0.party or {}) < 3 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 12)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 12)
    Party.giveMon(s0, C:require("species", "SPECIES_WURMPLE"), 12)
  end
  -- the engine's music volume for this run (the player's options.lua may have it at 0)
  local okAu, Audio = pcall(require, "src.core.game3.audio")
  if okAu then
    log("music volume was", tostring(Audio._bgmVolume), "mode", tostring(Audio._audioMode))
    Audio._bgmVolume = (tonumber(os.getenv("PROBE_MUSIC_VOL")) or 7) / 7
    if Audio._audioMode == "external_only" then Audio._audioMode = nil end
  end
  local A = X.amie
  local M = A.music
  if not M then log("FAIL no music player"); return end
  local function now(label)
    local v = M.voice
    local pos = v and v.q and v.q[1] or (v and v.pos) or -1
    log(("%-26s current %-22s game song %-22s engine song %s holding field %s  sample %d"):format(label, tostring(M.current),
      tostring(M.gameCurrent), tostring(Audio and Audio._currentSong and Audio._currentSong.id), tostring(M.holding), pos))
  end
  log("open play:", tostring(A.openPlay()))
  waitSecs(1)
  now("PLAY")
  local G = A.session
  G.startGame("berry", "easy")
  waitSecs(1.5)
  now("Berry Picker, the demo")
  local app = X.apps:get("game_berry")
  local st = app.debugState()
  waitFor(function() return st.phase == "play" end, 60 * 60)
  waitSecs(2)
  now("playing, 60 s")
  local before = M.voice and M.voice.q and M.voice.q[1] or 0
  st.timer = 29.5
  waitSecs(1.0)
  now("30 s left")
  local after = M.voice and M.voice.q and M.voice.q[1] or 0
  log(("  on from the same point: x1 sample %d -> x1.125 sample %d (x1.125 of it: %d)"):format(before, after, math.floor(after * 1.125)))
  st.timer = 9.5
  waitSecs(1.0)
  now("10 s left")
  st.timer = 0.2
  waitFor(function() return st.phase ~= "play" end, 60 * 10)
  waitSecs(1.0)
  now("TIME'S UP")
  if app.quit then app:quit() end
  waitSecs(1.5)
  now("back on PLAY")
  for _, g in ipairs({ "head", "tile" }) do
    G.startGame(g, "easy")
    waitSecs(1.5)
    now(g)
    if g == "head" then
      -- FEVER: the same voice, 2 semitones up
      local hs = X.apps:get("game_head").debugState()
      waitFor(function() return hs.phase == "play" end, 60 * 60)
      hs.fever = true
      waitSecs(0.5)
      log(("  FEVER: pitch %.4f (2^(2/12) = %.4f), track %s"):format(M.voice and M.voice.pitch or -1, 2 ^ (2 / 12), tostring(M.current)))
      hs.fever = false
      waitSecs(0.5)
      log(("  FEVER over: pitch %.4f"):format(M.voice and M.voice.pitch or -1))
    end
    local ga = X.apps:get("game_" .. g)
    if ga and ga.quit then ga:quit() end
    waitSecs(1.0)
  end
  now("back on PLAY")
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
