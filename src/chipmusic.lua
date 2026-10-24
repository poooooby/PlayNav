-- PlayNav's own sound effects on the main thread: starts the render job (src/chip_job.lua)
-- once, polls it from the tick, and turns its WAVs into the SoundData src/sfx.lua plays (as
-- Assets.sound). Until one is ready its id is still ours (silence, never the card image's).
--
-- local C = makeChip(mod) ; C.update() ; C.sound(id) -> SoundData | nil, owned

return function(mod)
  local C = { sounds = {}, state = "idle" }

  local soundsSrc = mod.read and mod:read("data/chip_sounds.lua")
  local synthSrc = mod.read and mod:read("src/chipsynth.lua")
  local function keys(src, name)
    local out = {}
    local chunk = src and load(src, "=" .. name)
    local ok, t = pcall(chunk or error)
    if ok and type(t) == "table" then
      for id in pairs(t) do out[id] = true end
    end
    return out
  end
  C.soundIds = keys(soundsSrc, "data/chip_sounds.lua")

  function C.start()
    if C.state ~= "idle" or not synthSrc then return false end
    local okA, avail = pcall(function() return mod.job and mod.job:available() end)
    if not (okA and avail) then C.state = "failed"; return false end
    local handle, err = mod.job:run("src/chip_job.lua", { synth = synthSrc, sounds = soundsSrc },
      { maxSeconds = 120 })
    if not handle then
      -- the job slots may be busy (the art's extraction): try again on a later tick
      if tostring(err):find("in flight") then return false end
      C.state = "failed"
      mod.log:warn("music: the render job was refused (%s)", tostring(err))
      return false
    end
    C.handle, C.state, C.startedAt = handle, "running", os.clock()
    return true
  end

  local function soundData(wav, name)
    local ok, sd = pcall(function()
      return love.sound.newSoundData(love.filesystem.newFileData(wav, (name:gsub("/", "_")) .. ".wav"))
    end)
    if ok and sd then return sd end
    mod.log:warn("music: %s did not load (%s)", name, tostring(sd))
    return nil
  end

  function C.update()
    if C.state == "idle" then C.start(); return end
    if C.state ~= "running" then return end
    local ok, st = pcall(mod.job.poll, mod.job, C.handle)
    if not ok or not st or st.status == "pending" then return end
    pcall(mod.job.release, mod.job, C.handle)
    if st.status ~= "ok" or type(st.result) ~= "table" then
      C.state = "failed"
      mod.log:warn("music: the render job failed (%s)", tostring(st.err))
      return
    end
    local effects = 0
    for id, wav in pairs(st.result.sounds or {}) do
      local sd = soundData(wav, id)
      if sd then C.sounds[id] = sd; effects = effects + 1 end
    end
    for id, why in pairs(st.result.errors or {}) do mod.log:warn("music: %s did not render (%s)", id, tostring(why)) end
    C.state = "done"
    mod.log:info("music: %d sound effects rendered in %.1fs", effects,
      os.clock() - (C.startedAt or os.clock()))
  end

  -- the SoundData for an id, and whether the id is ours at all
  function C.sound(id)
    if not C.soundIds[id] then return nil, false end
    return C.sounds[id], true
  end

  return C
end
