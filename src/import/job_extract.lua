-- Background job: decode one archive's worth of recipe textures from the
-- player's card image into raw RGBA files in the mod cache. Runs inside
-- mod.job with asset I/O: `job.imports:read` and `job.cache:write` are the
-- only doors. require is refused here, so the reader modules arrive as
-- source strings in the argument and are compiled with load().
--
-- arg = {
--   importId = "oras_cci", archive = "a/0/4/2",
--   items = { { entry, sub, clim, id, w, h, fmt, fp }, ... },
--   modules = { lz = <src>, garc = <src>, ctr = <src>, bclim = <src>, crc32, gen6text, darc, bcstm },
--   outPrefix = "oras/raw/",
--   verify = true, differs = <reason>, missingFp = <reason>,
-- }
-- returns { archive, results = { { id, ok, w, h, err } ... } }

local arg = ...

local function compile(name)
  local src = arg.modules and arg.modules[name]
  if type(src) ~= "string" then error("module source missing: " .. name, 0) end
  local chunk, err = load(src, "=" .. name)
  if not chunk then error(("module %s failed to compile: %s"):format(name, tostring(err)), 0) end
  return chunk()
end

local Lz = compile("lz")
local Garc = compile("garc")
local Ctr = compile("ctr")
local Bclim = compile("bclim")
local Text = arg.modules and arg.modules.gen6text and compile("gen6text") or nil
local Darc = arg.modules and arg.modules.darc and compile("darc") or nil
local Bcstm = arg.modules and arg.modules.bcstm and compile("bcstm") or nil
local Bcsar = arg.modules and arg.modules.bcsar and compile("bcsar") or nil
local Seq = arg.modules and arg.modules.seqsynth and compile("seqsynth") or nil
local Bch = arg.modules and arg.modules.bch and compile("bch") or nil
local Crc = arg.modules and arg.modules.crc32 and compile("crc32") or nil

-- arg.verify: every item carries `fp` = { size, crc } of the bytes it reads (or none recorded)
local VERIFY = arg.verify == true and Crc ~= nil
local DIFFERS = arg.differs or "fingerprint: differs"
local MISSING = arg.missingFp or "fingerprint: none recorded"
-- nil when the bytes match, else the reason every item cut from them fails with
local function checkBytes(fp, bytes)
  if not VERIFY then return nil end
  if not fp then return MISSING end
  if #bytes ~= fp.size or Crc.of(bytes) ~= fp.crc then return DIFFERS end
  return nil
end

local importId = arg.importId
local function read(offset, length)
  local data, err = job.imports:read(importId, offset, length)
  if not data then error(("import read failed at 0x%x+%d: %s"):format(offset, length, tostring(err)), 0) end
  return data
end

local fs, ferr = Ctr.open(read)
if not fs then error("card image: " .. tostring(ferr), 0) end
local aOff, aLen = fs:file(arg.archive)
if not aOff then error("archive " .. arg.archive .. ": " .. tostring(aLen), 0) end

local function u16le(v) return string.char(v % 256, math.floor(v / 256) % 256) end

-- a music stream (recipe kind "stream"): the file itself is the item, decoded to a WAV in
-- oras/bgm/<name>.wav with its loop point in oras/bgm/<name>.lua
local item1 = arg.items and arg.items[1]
if item1 and item1.kind == "stream" then
  local results = {}
  local wav, info = nil, "no stream reader"
  local bytes = read(aOff, aLen)
  local why = checkBytes(item1.fp, bytes)
  if why then return { archive = arg.archive, results = { { id = item1.id, ok = false, err = why } } } end
  if Bcstm then wav, info = Bcstm.wav(bytes) end
  -- its level (recipe gain, dB): Super Training's streams sit with gen1recomp's own music
  if wav and item1.gain and Seq and Seq.scaleWav then wav = Seq.scaleWav(wav, item1.gain) end
  if not wav then
    results[1] = { id = item1.id, ok = false, err = "stream: " .. tostring(info) }
  else
    local name = item1.id:gsub("^bgm/", "")
    local meta = ("return { rate = %d, channels = %d, samples = %d, loop = %s, loopStart = %d }\n"):format(
      info.rate, info.channels, info.samples, tostring(info.loop), info.loopStart)
    local okW, werr = job.cache:write("oras/bgm/" .. name .. ".wav", wav)
    if okW ~= false and not (okW == nil and werr) then okW, werr = job.cache:write("oras/bgm/" .. name .. ".lua", meta) end
    if okW == false or (okW == nil and werr) then
      results[1] = { id = item1.id, ok = false, err = "cache write: " .. tostring(werr) }
    else
      results[1] = { id = item1.id, ok = true, kind = "stream", count = info.samples }
    end
  end
  return { archive = arg.archive, results = results }
end

-- the game's sound effects (recipe kind "sfx"): each a sequence rendered on its bank's
-- instruments into oras/se/<name>.wav; the archive is read in ranges, never whole. Songs (kind
-- "song", the same archive) render in music mode at their tempo into oras/bgm/<name>.wav with
-- the loop point in oras/bgm/<name>.lua, as a stream's
if item1 and (item1.kind == "sfx" or item1.kind == "song") then
  local results = {}
  -- the archive is checked whole (read in ranges, never held), before anything renders from it
  if VERIFY then
    local fp = item1.fp
    local bad = not fp and MISSING
      or (aLen ~= fp.size or Crc.ofRange(read, aOff, aLen) ~= fp.crc) and DIFFERS or nil
    if bad then
      for _, item in ipairs(arg.items) do results[#results + 1] = { id = item.id, ok = false, err = bad } end
      return { archive = arg.archive, results = results }
    end
  end
  local ar, why = nil, "no sound-archive reader"
  if Bcsar and Seq and Bcstm then ar, why = Bcsar.open(read, aOff, aLen) end
  for _, item in ipairs(arg.items) do
    if not ar then
      results[#results + 1] = { id = item.id, ok = false, err = "sound archive: " .. tostring(why) }
    else
      local song = item.kind == "song"
      local ok, res = pcall(function()
        local snd = assert(ar:sound(item.name))
        local L, R, n, loop = Seq.render(snd, ar, { dsp = Bcstm.dspBlock, music = song, tempoScale = item.tempo or 1 })
        if song and item.gain then Seq.level(L, R, n, item.gain) end
        local wav, mono = Seq.wav(L, R, n)
        return { wav = wav, n = n, loop = loop, channels = mono and 1 or 2 }
      end)
      if not ok then
        results[#results + 1] = { id = item.id, ok = false, err = "render: " .. tostring(res) }
      elseif song then
        local name = item.id:gsub("^bgm/", "")
        local meta = ("return { rate = %d, channels = %d, samples = %d, loop = %s, loopStart = %d }\n"):format(
          Seq.OUT_RATE, res.channels, res.n, tostring(res.loop ~= nil), res.loop and res.loop[1] or 0)
        local okW, werr = job.cache:write("oras/bgm/" .. name .. ".wav", res.wav)
        if okW ~= false and not (okW == nil and werr) then okW, werr = job.cache:write("oras/bgm/" .. name .. ".lua", meta) end
        if okW == false or (okW == nil and werr) then
          results[#results + 1] = { id = item.id, ok = false, err = "cache write: " .. tostring(werr) }
        else
          results[#results + 1] = { id = item.id, ok = true, kind = "song", count = res.n }
        end
      else
        local name = item.id:gsub("^se/", "")
        local okW, werr = job.cache:write("oras/se/" .. name .. ".wav", res.wav)
        if okW == false or (okW == nil and werr) then
          results[#results + 1] = { id = item.id, ok = false, err = "cache write: " .. tostring(werr) }
        else
          results[#results + 1] = { id = item.id, ok = true, kind = "sfx", count = res.n }
        end
      end
    end
  end
  return { archive = arg.archive, results = results }
end

local g, gerr = Garc.open(read, aOff, aLen)
if not g then error("archive " .. arg.archive .. ": " .. tostring(gerr), 0) end

-- group items by entry/sub so each blob is read and decompressed once
local groups, order = {}, {}
for _, item in ipairs(arg.items or {}) do
  local key = item.entry .. ":" .. item.sub
  if not groups[key] then
    groups[key] = { entry = item.entry, sub = item.sub, fp = item.fp, items = {} }
    order[#order + 1] = key
  end
  local list = groups[key].items
  list[#list + 1] = item
end

local results = {}
local function fail(item, why)
  results[#results + 1] = { id = item.id, ok = false, err = why }
end

for _, key in ipairs(order) do
  local grp = groups[key]
  local bytes, berr = g:bytes(grp.entry, grp.sub)
  local differs = bytes and checkBytes(grp.fp, bytes)
  if not bytes then
    for _, item in ipairs(grp.items) do fail(item, "entry: " .. tostring(berr)) end
  elseif differs then
    for _, item in ipairs(grp.items) do fail(item, differs) end
  else
    local first = bytes:byte(1)
    local blob = (first == 0x10 or first == 0x11) and Lz.decode(bytes) or bytes
    local clims = nil
    for _, item in ipairs(grp.items) do
      if item.kind == "text" then
        local lines, n = nil, nil
        if Text then lines, n = Text.decode(blob) end
        if not lines then
          fail(item, "text: " .. tostring(n or "no decoder"))
        elseif item.lines and n < item.lines then
          fail(item, ("text has %d lines, recipe says %d"):format(n, item.lines))
        else
          local okW, werr = job.cache:write("oras/text/" .. item.id:gsub("^text/", "") .. ".lua", Text.serialize(lines, n))
          if okW == false or (okW == nil and werr) then
            fail(item, "cache write: " .. tostring(werr))
          else
            results[#results + 1] = { id = item.id, ok = true, kind = "text", lines = n }
          end
        end
        goto continue
      end
      if item.kind == "files" then
        -- a screen's layout and animations, copied as they are from the entry's darc into
        -- oras/lyt/<pack>/<name> (the layout player reads them; nothing is decoded here)
        local files, why = nil, "no darc reader"
        if Darc then files, why = Darc.files(blob) end
        if not files then
          fail(item, "darc: " .. tostring(why))
        else
          local pack = item.id:gsub("^lyt/", "")
          local n, werr, written = 0, nil, {}
          for _, name in ipairs(files.order) do
            if name:match(item.match or "%.bcl[ya][tn]$") then
              local r = files[name]
              local okW, e = job.cache:write("oras/lyt/" .. pack .. "/" .. name, blob:sub(r.start, r.stop))
              if okW == false or (okW == nil and e) then werr = e; break end
              n = n + 1
              written[#written + 1] = ("%q"):format(name)
            end
          end
          -- the names, so CLEAR EXTRACTED ART can find them (the cache has no listing)
          if not werr then
            local okI, e = job.cache:write("oras/lyt/" .. pack .. "/index.lua",
              "return { " .. table.concat(written, ", ") .. " }\n")
            if okI == false or (okI == nil and e) then werr = e end
          end
          if werr then fail(item, "cache write: " .. tostring(werr))
          elseif item.count and n < item.count then fail(item, ("darc holds %d files, recipe says %d"):format(n, item.count))
          else results[#results + 1] = { id = item.id, ok = true, kind = "files", count = n } end
        end
        goto continue
      end
      if item.kind == "bch" then
        -- a texture inside a 3D model / effect file (BCH), found by its name; its pixels go the
        -- same way as a CLIM's (raw RGBA, then a PNG on the main thread)
        -- (item.path: the BCH sits inside Game Freak's packages - field maps, battle scenery -
        -- reached by index, opening LZ at every level; tools/bch.py find prints the path)
        local t, why = nil, "no BCH reader"
        local src = blob
        if Bch and item.path then
          src, why = Bch.descend(blob, item.path, function(s)
            local f = s:byte(1)
            if f == 0x10 or f == 0x11 then
              local d = Lz.decode(s)
              if d then return d end
            end
            return s
          end)
        end
        if Bch and src then t, why = Bch.texture(src, item.name) end
        local img
        if t and t.format then
          img, why = Bclim.decodeRaw(t.format, t.w, t.h, src:sub(t.data + 1), #src - t.data)
        elseif t then
          why = "unknown texture format"
        end
        if not img then
          fail(item, "bch: " .. tostring(why))
        elseif img.w ~= item.w or img.h ~= item.h then
          fail(item, ("is %dx%d, recipe says %dx%d"):format(img.w, img.h, item.w, item.h))
        else
          local payload = "DSRW" .. u16le(img.w) .. u16le(img.h) .. img.rgba
          local okW, werr = job.cache:write((arg.outPrefix or "oras/raw/") .. item.id .. ".rgba", payload)
          if okW == false or (okW == nil and werr) then
            fail(item, "cache write: " .. tostring(werr))
          else
            results[#results + 1] = { id = item.id, ok = true, w = img.w, h = img.h }
          end
        end
        goto continue
      end
      clims = clims or Bclim.find(blob)
      local range = clims[(item.clim or 0) + 1]
      if not range then
        fail(item, ("no CLIM %d (%d found)"):format(item.clim or 0, #clims))
      else
        local img, derr = Bclim.decode(blob:sub(range.start, range.stop))
        if not img then
          fail(item, "decode: " .. tostring(derr))
        elseif img.w ~= item.w or img.h ~= item.h or (item.fmt and img.format ~= item.fmt) then
          fail(item, ("is %dx%d %s, recipe says %dx%d %s"):format(img.w, img.h, img.format,
            item.w, item.h, tostring(item.fmt)))
        else
          local payload = "DSRW" .. u16le(img.w) .. u16le(img.h) .. img.rgba
          local okW, werr = job.cache:write((arg.outPrefix or "oras/raw/") .. item.id .. ".rgba", payload)
          if okW == false or (okW == nil and werr) then
            fail(item, "cache write: " .. tostring(werr))
          else
            results[#results + 1] = { id = item.id, ok = true, w = img.w, h = img.h }
          end
        end
      end
      ::continue::
    end
  end
end

return { archive = arg.archive, results = results }
