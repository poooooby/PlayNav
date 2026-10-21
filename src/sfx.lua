-- The game's own sound effects (rendered into the cache by the import, recipe kind "sfx"),
-- played the way the game's effects are: at the effects volume of the game's settings, not at
-- all while that is 0 or the engine's sound is suspended. Shared as mod.sfx.
--
-- local Sfx = makeSfx(mod, { assets = Assets, host = <a host with sfxGain / audioSuspended> })
-- Sfx.play(id, opts) -> a handle (handle:stop()) or false when the effect is not there (the
--   caller keeps its stand-in) ; opts = { volume = 0..1 }
-- Sfx.has(id) ; Sfx.stopAll()

return function(mod, deps)
  local S = { playing = {} }
  local Assets, host = deps.assets, deps.host

  function S.has(id)
    return Assets ~= nil and Assets.sound ~= nil and Assets.sound(id) ~= nil
  end

  local function gain()
    return host and host.sfxGain and host.sfxGain() or 1
  end

  -- one static Source per effect (its samples uploaded once); every play is a clone of it,
  -- which shares the buffer instead of uploading the samples again
  local bases = setmetatable({}, { __mode = "k" })
  local function voice(id, sd)
    local base = bases[sd]
    if base == nil then
      local ok, src = pcall(love.audio.newSource, sd, "static")
      if not ok then
        mod.log:warn("sound %s would not play: %s", id, tostring(src))
        bases[sd] = false
        return nil
      end
      base = src
      bases[sd] = base
    end
    if not base then return nil end
    if base.clone then
      local ok, c = pcall(base.clone, base)
      if ok and c then return c end
    end
    local ok, src = pcall(love.audio.newSource, sd, "static")
    return ok and src or nil
  end

  -- the game's SOUND option on Mono: a stereo effect plays from a one-channel copy (made once),
  -- centred, as the engine's own effects are
  local monos = setmetatable({}, { __mode = "k" })
  local function monoOf(sd)
    local m = monos[sd]
    if m ~= nil then return m or sd end
    m = false
    local okC, ch = pcall(sd.getChannelCount, sd)
    if okC and ch == 2 then
      local ok, made = pcall(function()
        local n = sd:getSampleCount()
        local out = love.sound.newSoundData(n, sd:getSampleRate(), 16, 1)
        for i = 0, n - 1 do out:setSample(i, (sd:getSample(i, 1) + sd:getSample(i, 2)) * 0.5) end
        return out
      end)
      if ok then m = made end
    end
    monos[sd] = m
    return m or sd
  end

  -- the game's own effect if it is in the cache: true when it played (or was silent on purpose:
  -- effects volume 0 or sound suspended), false when it is missing
  function S.play(id, opts)
    local sd = Assets and Assets.sound and Assets.sound(id)
    if not (sd and love and love.audio and love.audio.newSource) then return false end
    if host and host.soundMono and host.soundMono() then sd = monoOf(sd) end
    local handle = { stop = function() end }
    local g = gain() * (opts and opts.volume or 1)
    if g <= 0 or (host and host.audioSuspended and host.audioSuspended()) then return handle end
    local src = voice(id, sd)
    if not src then return false end
    pcall(src.setVolume, src, math.min(1, g))
    pcall(src.play, src)
    S.playing[src] = true
    handle.source = src
    function handle.stop()
      pcall(src.stop, src)
      S.playing[src] = nil
    end
    -- forget the ones that have finished
    for s in pairs(S.playing) do
      local okP, on = pcall(s.isPlaying, s)
      if not (okP and on) then S.playing[s] = nil end
    end
    return handle
  end

  function S.stopAll()
    for s in pairs(S.playing) do pcall(s.stop, s) end
    S.playing = {}
  end

  return S
end
