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
    local src = cacheRead("oras/manifest.lua")
    if not src then
      A.manifest = nil
      return nil
    end
    local chunk = load(src, "=oras/manifest.lua")
    local ok, m = pcall(chunk)
    A.manifest = (ok and type(m) == "table") and m or nil
    A.images, A.missing, A.texts, A.tracks = {}, {}, {}, {}
    A.loadedAt = os.time()
    return A.manifest
  end

  function A.ready()
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

  -- love Image or nil
  function A.image(id)
    if not (love and love.graphics and love.image and love.data) then return nil end
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
  -- { sd = love SoundData, rate, channels, samples, loop, loopStart } or nil
  A.tracks = {}
  function A.music(id)
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
    A.tracks[id] = track
    return track or nil
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
