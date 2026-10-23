-- Extracted-art loader: turns the PNGs the import wrote into mod.cache into
-- love Images on demand, with an in-memory cache and a clean nil when the
-- art is absent so every caller keeps its drawn fallback.

return function(mod)
  local A = { images = {}, missing = {}, manifest = nil, loadedAt = nil }

  local function cacheRead(rel)
    local ok, bytes = pcall(mod.cache.read, mod.cache, rel)
    if ok and type(bytes) == "string" and #bytes > 0 then return bytes end
    return nil
  end

  -- the manifest the extractor writes when the set is complete
  function A.refresh()
    local src = not A.cardOff and cacheRead("oras/manifest.lua") or nil
    if not src then
      -- no art (never extracted, or just cleared): nothing loaded earlier may still draw
      A.manifest = nil
      A.images, A.missing, A.texts, A.tracks, A.sounds = {}, {}, {}, {}, {}
      A.loadedAt = os.time()
      return nil
    end
    local chunk = load(src, "=oras/manifest.lua")
    local ok, m = pcall(chunk)
    A.manifest = (ok and type(m) == "table") and m or nil
    A.images, A.missing, A.texts, A.tracks, A.sounds = {}, {}, {}, {}, {}
    A.loadedAt = os.time()
    return A.manifest
  end

  -- A.cardOff (option USE ROM ASSETS off): the card image's cache is left unread, so every
  -- caller takes PlayNav's own art, sounds and words
  function A.ready()
    if A.cardOff then return false end
    if A.manifest == nil and A.loadedAt == nil then A.refresh() end
    return A.manifest ~= nil
  end

  function A.list()
    if not A.ready() then return {} end
    local out = {}
    for id, entry in pairs(A.manifest.assets or {}) do out[#out + 1] = { id = id, w = entry.w, h = entry.h } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end

  -- love Image or nil. A.engine (set in main: src/training/ui_art.lua) draws the UI ids
  -- itself, so those never come from the card image.
  function A.image(id)
    if not (love and love.graphics and love.image and love.data) then return nil end
    if A.engine then
      local drawn, owned = A.engine(id)
      if drawn or owned then return drawn end
    end
    local img = A.images[id]
    if img then return img end
    if A.missing[id] then return nil end
    if not A.ready() then A.missing[id] = true; return nil end
    local entry = A.manifest.assets and A.manifest.assets[id]
    if not entry then A.missing[id] = true; return nil end
    local bytes = cacheRead("oras/png/" .. id .. ".png")
    if not bytes then A.missing[id] = true; return nil end
    local ok, result = pcall(function()
      local data = love.data.newByteData(bytes)
      local imageData = love.image.newImageData(data)
      local HD = mod.hd
      local hd = HD and HD.enabled
      local image = love.graphics.newImage(imageData, hd and { mipmaps = true } or nil)
      if HD then HD.prepareArt(image) else image:setFilter("nearest", "nearest") end
      return image
    end)
    if not ok then
      mod.log:warn("asset %s failed to load: %s", id, tostring(result))
      A.missing[id] = true
      return nil
    end
    A.images[id] = result
    return result
  end

  -- extracted game text: the lines table ([0] .. [n-1]) or nil
  A.texts = {}
  function A.text(id)
    if A.texts[id] ~= nil then return A.texts[id] or nil end
    local src = A.ready() and cacheRead("oras/text/" .. id .. ".lua") or nil
    local lines = nil
    if src then
      local chunk = load(src, "=oras/text/" .. id, "t", {})
      local ok, t = pcall(chunk or error)
      if ok and type(t) == "table" then lines = t end
    end
    A.texts[id] = lines or false
    return lines
  end

  -- a file the extract copied from a darc as it is (recipe kind "files"): the bytes of
  -- oras/lyt/<pack>/<name>, or nil
  function A.file(pack, name)
    if not A.ready() then return nil end
    local m = A.manifest.assets
    if not (m and m["lyt/" .. pack]) then return nil end
    return cacheRead("oras/lyt/" .. pack .. "/" .. name)
  end

  -- a music track the extract decoded (recipe kind "stream", id "bgm/<name>"):
  -- { sd = love SoundData, rate, channels, samples, loop, loopStart } or nil. Without the
  -- card image's, PlayNav's own file for the id (A.ownMusic[id] = a path in the mod, looping
  -- whole) stands in.
  A.tracks = {}
  A.ownMusic = { ["bgm/sp_menu"] = "assets/stmenu.ogg" }
  local function ownTrack(id)
    local path = A.ownMusic[id]
    if not (path and love and love.sound and love.filesystem and mod.read) then return false end
    local ok, sd = pcall(function()
      local bytes = mod:read(path)
      return bytes and love.sound.newSoundData(love.filesystem.newFileData(bytes, path:match("[^/]+$")))
    end)
    if not (ok and sd) then
      mod.log:warn("music %s (%s) failed to load: %s", id, path, tostring(sd))
      return false
    end
    return { sd = sd, rate = sd:getSampleRate(), channels = sd:getChannelCount(), samples = sd:getSampleCount(),
      loop = true, loopStart = 0 }
  end
  function A.music(id)
    -- PlayNav's own songs (src/chipmusic.lua) take their ids before the card image's
    if A.engineMusic then
      local own, owned = A.engineMusic(id)
      if own or owned then return own end
    end
    if A.tracks[id] ~= nil then return A.tracks[id] or nil end
    local track = false
    local m = A.ready() and A.manifest.assets or nil
    if m and m[id] and love and love.sound and love.filesystem then
      local name = id:gsub("^bgm/", "")
      local wav = cacheRead("oras/bgm/" .. name .. ".wav")
      local metaSrc = cacheRead("oras/bgm/" .. name .. ".lua")
      local chunk = metaSrc and load(metaSrc, "=oras/bgm/" .. name, "t", {})
      local okM, meta = pcall(chunk or error)
      if wav and okM and type(meta) == "table" then
        local ok, sd = pcall(function()
          return love.sound.newSoundData(love.filesystem.newFileData(wav, name .. ".wav"))
        end)
        if ok and sd then
          track = { sd = sd, rate = meta.rate, channels = meta.channels, samples = meta.samples,
            loop = meta.loop, loopStart = meta.loopStart }
        else
          mod.log:warn("music %s failed to load: %s", id, tostring(sd))
        end
      end
    end
    if not track then track = ownTrack(id) end
    A.tracks[id] = track
    return track or nil
  end

  -- a sound effect the extract rendered (recipe kind "sfx", id "se/<name>"): love SoundData or nil
  A.sounds = {}
  function A.sound(id)
    -- PlayNav's own effects (src/chipmusic.lua) take their ids before the card image's
    if A.engineSound then
      local own, owned = A.engineSound(id)
      if own or owned then return own end
    end
    if A.sounds[id] ~= nil then return A.sounds[id] or nil end
    local sd = false
    local m = A.ready() and A.manifest.assets or nil
    if m and m[id] and love and love.sound and love.filesystem then
      local name = id:gsub("^se/", "")
      local wav = cacheRead("oras/se/" .. name .. ".wav")
      if wav then
        local ok, res = pcall(function()
          return love.sound.newSoundData(love.filesystem.newFileData(wav, name .. ".wav"))
        end)
        if ok and res then sd = res else mod.log:warn("sound %s failed to load: %s", id, tostring(res)) end
      end
    end
    A.sounds[id] = sd
    return sd or nil
  end

  -- draw helper: image centred at (x, y) scaled by s, or nothing (returns false)
  function A.draw(G, id, x, y, s, r)
    local img = A.image(id)
    if not img then return false end
    local w, h = img:getDimensions()
    G.draw(img, x, y, r or 0, s or 1, s or 1, w / 2, h / 2)
    return true
  end

  return A
end
