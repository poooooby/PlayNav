-- Super Training's music: the game's own tracks (recipe kind "stream", decoded by the import),
-- chosen from the session's state every frame. The field's music is held while the top-screen
-- layer is up (the picker, a regimen, its results) and carries on when it goes.
--
-- From a capture of a Lv. 1 regimen, its audio matched against the decoded tracks:
--   the picker            sp_menu, looping (from its start each time the picker comes up)
--   into a regimen        the picker's music fades with the screens
--   the title             sp_gamestart (2.6 s, once), from the intro's first frame
--   the balloon inflates  sp_stage, looping, from 3.0 s into the intro
--   the last hit          the music stops; the balloon's exit plays to effects alone
--   the banner            sp_clear (cleared) or sp_gameover (time ran out), on through the results
--   back to the picker    the result's music fades with the screens, sp_menu again
--   back home             the picker's music fades with its shutters; the field's carries on
-- A secret regimen plays sp_stage_02 (not heard in a capture).
-- The game's audio settings drive it like the game's own music: the music volume (0 or EXT.
-- ONLY = off), the duck under cries and loud effects, the music filter, and a pause while the
-- engine's audio is suspended (host.musicOn / musicGain / musicFilter / audioSuspended).
--
-- M = makeMusic(mod, T, host) ; M.wanted(s) -> id, loop, fade (pure) ; M.update(dt)

return function(mod, T, host)
  local M = {}
  M.STAGE_AT = 3.0       -- s into the intro: sp_stage begins
  M.FADE_S = 0.5         -- into a regimen: the picker's music fades out
  M.RESULT_FADE_S = 1.0  -- out of the results, with the screens' fade
  M.CHUNK = 4096         -- sample frames per queued buffer
  M.BUFFERS = 8
  M.enabled = true

  local LOOPS = { ["bgm/sp_gamestart"] = false }

  -- what should be playing now: the track id (nil = silence), whether it loops, and how long
  -- the one before it takes to fade (0 = cut)
  function M.wanted(s)
    if not (s and s.layered) then return nil, false, 0 end
    local tr = s.trans
    if tr and tr.to == "regimen" then return nil, false, M.FADE_S end
    if tr and tr.from == "result" and not tr.switched then return nil, false, M.RESULT_FADE_S end
    if tr and tr.to == "core" then return nil, false, M.FADE_S end
    local mode = s.mode
    if mode == "courses" then return "bgm/sp_menu", true, M.FADE_S end
    if mode == "result" then
      return (s.result and s.result.clear) and "bgm/sp_clear" or "bgm/sp_gameover", true, 0
    end
    if mode ~= "regimen" then return nil, false, 0 end
    local sim = T.sim
    if not sim then return nil, false, 0 end
    local o = s.outro
    if o then
      local banner = T.hud and T.hud.OUTRO and T.hud.OUTRO.BANNER or 0
      if o.t < banner then return nil, false, 0.1 end
      return (o.outcome and o.outcome.clear) and "bgm/sp_clear" or "bgm/sp_gameover", true, 0
    end
    local show = T.REGIMEN_SHOW and T.hud and T.hud.P
    if show and sim.phase == "countdown" and (sim.t or 0) < M.STAGE_AT then
      return "bgm/sp_gamestart", false, 0
    end
    local secret = s.course and s.course.secret ~= nil
    return secret and "bgm/sp_stage_02" or "bgm/sp_stage", true, 0
  end

  -- ------- playback: one voice per track, a QueueableSource fed from the decoded SoundData,
  -- wrapping at the track's loop point (the game's tracks have an intro before the loop)

  local function track(id)
    local A = T.assets
    return A and A.music and A.music(id) or nil
  end

  -- whether the music is there (the import ran): without it the field's music keeps playing
  function M.available()
    return M.enabled and track("bgm/sp_menu") ~= nil
  end

  local function queueChunk(v, from, n)
    local tk, src = v.track, v.src
    local bpf = 2 * tk.channels
    local ok, res = false, nil
    if v.pointer ~= false then
      ok, res = pcall(src.queue, src, tk.sd:getPointer(), from * bpf, n * bpf, tk.rate, 16, tk.channels)
      if not ok then v.pointer = false end
    end
    if not ok then
      -- no pointer queueing: copy the samples into a buffer of their own
      ok, res = pcall(function()
        local buf = love.sound.newSoundData(n, tk.rate, 16, tk.channels)
        for i = 0, n - 1 do
          for c = 1, tk.channels do buf:setSample(i, c, tk.sd:getSample(from + i, c)) end
        end
        return src:queue(buf)
      end)
    end
    return ok and res ~= false
  end

  local function pump(v)
    local src = v.src
    local okF, free = pcall(src.getFreeBufferCount, src)
    free = okF and free or 0
    local tk = v.track
    while free > 0 and not v.ended do
      local n = math.min(M.CHUNK, tk.samples - v.pos)
      if n <= 0 then
        if v.loop then
          v.pos = (tk.loopStart or 0) < tk.samples and (tk.loopStart or 0) or 0
        else
          v.ended = true
        end
      else
        if not queueChunk(v, v.pos, n) then v.ended = true; break end
        v.pos = v.pos + n
        free = free - 1
      end
    end
    if not src:isPlaying() and not v.ended then pcall(src.play, src) end
  end

  local function startVoice(id, loop)
    local tk = track(id)
    if not (tk and love and love.audio and love.audio.newQueueableSource) then return nil end
    local ok, src = pcall(love.audio.newQueueableSource, tk.rate, 16, tk.channels, M.BUFFERS)
    if not ok then
      mod.log:warn("music: no stream source (%s)", tostring(src))
      return nil
    end
    local v = { id = id, track = tk, src = src, pos = 0, loop = loop, gain = 1 }
    if loop == nil then v.loop = LOOPS[id] ~= false and tk.loop end
    pump(v)
    return v
  end

  local function stopVoice(v)
    if v and v.src then pcall(v.src.stop, v.src) end
  end

  -- the game's settings on one voice: its volume, and the music filter (applied when it changes)
  local function applySettings(v, gain, filter)
    pcall(v.src.setVolume, v.src, gain * v.gain)
    if v.filter ~= (filter or false) and v.src.setFilter then
      v.filter = filter or false
      pcall(function()
        if filter then v.src:setFilter({ type = "lowpass", volume = 1, highgain = filter })
        else v.src:setFilter() end
      end)
    end
  end

  M.voice, M.fading, M.holding = nil, {}, false

  function M.stopAll()
    stopVoice(M.voice)
    for _, f in ipairs(M.fading) do stopVoice(f) end
    M.voice, M.fading, M.current = nil, {}, nil
    if M.holding then
      M.holding = false
      host.overworldMusic(true)
    end
  end

  function M.update(dt)
    dt = dt or 0
    local s = T.session
    local on = M.available()
    -- hold the field's music while ours has the screen
    local hold = on and s ~= nil and s.layered == true
    if hold ~= M.holding then
      M.holding = hold
      if host.overworldMusic then host.overworldMusic(not hold) end
    end
    if not on then
      if M.voice or #M.fading > 0 then M.stopAll() end
      return
    end
    -- the engine has stopped its audio (focus lost, suspended): ours waits with it
    if host.audioSuspended and host.audioSuspended() then
      if not M.paused then
        M.paused = true
        if M.voice then pcall(M.voice.src.pause, M.voice.src) end
        for _, f in ipairs(M.fading) do pcall(f.src.pause, f.src) end
      end
      return
    end
    M.paused = false
    local id, loop, fade = M.wanted(s)
    -- music off in the game's settings (volume 0, or EXT. ONLY): silence; it starts afresh
    -- when turned back on
    if host.musicOn and not host.musicOn() then id, fade = nil, 0 end
    if id ~= M.current then
      M.current = id
      if M.voice then
        if (fade or 0) > 0 then
          M.voice.fade = { t = 0, dur = fade, from = M.voice.gain }
          M.fading[#M.fading + 1] = M.voice
        else
          stopVoice(M.voice)
        end
      end
      M.voice = id and startVoice(id, loop) or nil
    end
    local gain = host.musicGain and host.musicGain() or 1
    local filter = host.musicFilter and host.musicFilter() or nil
    for i = #M.fading, 1, -1 do
      local f = M.fading[i]
      f.fade.t = f.fade.t + dt
      local k = 1 - f.fade.t / f.fade.dur
      if k <= 0 then
        stopVoice(f)
        table.remove(M.fading, i)
      else
        f.gain = f.fade.from * k
        applySettings(f, gain, filter)
        pump(f)
      end
    end
    local v = M.voice
    if v then
      applySettings(v, gain, filter)
      pump(v)
    end
  end

  return M
end
