-- Driver: NaviPlay's music against gen1recomp's own, side by side. The engine's Emerald songs are
-- rendered offline through its own player (m4a_player.renderBuffered at master 1, as its worker
-- plays them) for MEASURE_S each; NaviPlay's tracks (Super Training's streams, the minigame songs)
-- are read from the extracted-art cache. Each gets rms, the loud parts (the 90th percentile of
-- 400 ms windows) and the peak, in dB of full scale. Both are played at the same music volume
-- (the engine's bgm gain; NaviPlay's host.musicGain reads the same settings) and NaviPlay's player
-- adds its MIX (src/training/music.lua), so NaviPlay's are reported as heard: the file's level
-- plus MIX in dB. These are what is heard against each other.
--   POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/music_level_probe.lua love .

local MEASURE_S = 40
local SONGS = { "MUS_LITTLEROOT", "MUS_ROUTE101", "MUS_OLDALE", "MUS_PETALBURG", "MUS_ROUTE104",
  "MUS_RUSTBORO", "MUS_VS_WILD", "MUS_VS_TRAINER" }
local OURS = { "sp_menu", "sp_stage", "sp_stage_02", "sp_clear", "kw_game01", "kw_game01_fast",
  "kw_game01_faster", "kw_game02", "kw_game03", "rocket" }

local function body(game, log)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached")
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if X and X._test and X._test.keepArt then X._test.keepArt() end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(60)
  local Audio = require("src.core.game3.audio")
  local Player = require("src.core.game3.m4a_player")
  local Mix = require("src.core.game3.m4a_mix")
  waitFor(function() return Audio.isReady and Audio.isReady() end, 1200)

  -- stats over a list of mono-mixed samples in -1..1
  local function stats(get, n, rate)
    local sum, peak = 0, 0
    local win = math.floor(rate * 0.4)
    local wins, acc, k = {}, 0, 0
    for i = 0, n - 1 do
      local v = get(i)
      sum = sum + v * v
      local a = math.abs(v)
      if a > peak then peak = a end
      acc, k = acc + v * v, k + 1
      if k == win then wins[#wins + 1] = math.sqrt(acc / win); acc, k = 0, 0 end
    end
    table.sort(wins)
    local db = function(v) return v > 0 and 20 * math.log10(v) or -99 end
    return db(math.sqrt(sum / math.max(1, n))), db(wins[math.max(1, math.floor(#wins * 0.9))] or 0), db(peak)
  end
  local function monoOf(sd)
    local ch = sd:getChannelCount()
    if ch == 1 then return function(i) return sd:getSample(i) end end
    return function(i) return (sd:getSample(i, 1) + sd:getSample(i, 2)) / 2 end
  end

  log("gen1recomp's own music (rendered through its player at master 1):")
  local engine = {}
  for _, name in ipairs(SONGS) do
    local id = Audio.resolveSong(name)
    local slot = { voices = {}, songId = id }
    local ok = pcall(Player.start, Audio._pack, Audio._cache, slot, id, { forceSeq = true })
    if not ok then
      log(("  %-16s could not start"):format(name))
    else
      local rate = Mix.SAMPLE_RATE
      local chunks, total = {}, 0
      while total < MEASURE_S * rate do
        local sd = Player.renderBuffered(slot, Player.BUFFER_SAMPLES, { master = 1, sampleRate = rate })
        if not sd then break end
        chunks[#chunks + 1] = sd
        total = total + sd:getSampleCount()
      end
      local idx = {}
      for _, sd in ipairs(chunks) do
        local f = monoOf(sd)
        for i = 0, sd:getSampleCount() - 1 do idx[#idx + 1] = f(i) end
      end
      local rms, p90, pk = stats(function(i) return idx[i + 1] end, #idx, rate)
      engine[#engine + 1] = rms
      log(("  %-16s rms %6.1f dB  loud %6.1f dB  peak %6.1f dB"):format(name, rms, p90, pk))
    end
    U.wait(1)
  end

  local mixDb = 20 * math.log10(0.505)
  do
    local T = X.training and X.training.session
    local M = T and T.music
    if M and M.MIX then mixDb = 20 * math.log10(M.MIX) end
  end
  log(("NaviPlay's music as heard (the extracted cache, plus the player's MIX %.1f dB):"):format(mixDb))
  for _, name in ipairs(OURS) do
    local ok, track = pcall(function() return X.assets.music and X.assets.music("bgm/" .. name) end)
    local sd = ok and track and track.sd
    if not sd then
      log(("  %-16s not in the cache"):format(name))
    else
      local rms, p90, pk = stats(monoOf(sd), sd:getSampleCount(), sd:getSampleRate())
      -- a track's own boost on top of MIX (music.lua M.BOOST_DB)
      local T = X.training and X.training.session
      local boost = T and T.music and T.music.BOOST_DB and T.music.BOOST_DB["bgm/" .. name] or 0
      local h = mixDb + boost
      log(("  %-16s rms %6.1f dB  loud %6.1f dB  peak %6.1f dB   (file rms %.1f%s)"):format(name, rms + h, p90 + h,
        pk + h, rms, boost ~= 0 and (", boost %+.1f dB"):format(boost) or ""))
    end
    U.wait(1)
  end
  -- the SOUND option: a stereo effect plays on two channels in Stereo, one (centred) in Mono
  do
    local Sfx = X.training and X.training.session and X.training.session.sfx
    local stereoId
    for _, id in ipairs({ "se/sp_044", "se/sp_008" }) do
      local sd = X.assets.sound and X.assets.sound(id)
      if sd and sd:getChannelCount() == 2 then stereoId = id; break end
    end
    if Sfx and stereoId then
      local mono0 = Audio._mono
      local function chans(mono)
        Audio._mono = mono
        local h = Sfx.play(stereoId, { volume = 0.01 })
        local src = h and h.source
        local n = src and src:getChannelCount()
        if h and h.stop then h.stop() end
        return n
      end
      log(("SOUND option, %s: Stereo plays %s channel(s), Mono %s"):format(stereoId, tostring(chans(false)), tostring(chans(true))))
      Audio._mono = mono0
    else
      log("SOUND option: no stereo effect found to check")
    end
  end
  table.sort(engine)
  if #engine > 0 then
    log(("gen1recomp's songs: rms from %.1f to %.1f dB, median %.1f dB"):format(engine[1], engine[#engine],
      engine[math.ceil(#engine / 2)]))
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
