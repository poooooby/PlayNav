-- The import flow on the main thread: notice the player's card image, run
-- one background job per recipe archive, turn the raw RGBA the jobs leave in
-- the cache into PNGs with love.image, and publish oras/manifest.lua when the
-- set is complete. The surface's IMPORT app and the Assets loader read the
-- state from here.

return function(mod, deps)
  local Recipe, Assets = deps.recipe, deps.assets
  local onChange = deps.onChange or function() end

  local E = {
    state = "idle",      -- idle | absent | complete | running | finishing | done | failed
    total = 0, done = 0, failed = 0,
    archives = {},       -- queue of { archive, items }
    jobs = {},           -- handle -> archive
    pending = {},        -- raw ids waiting for PNG conversion
    results = {},        -- id -> { ok, w, h, err }
    message = nil,
    startedAt = nil,
    cancelled = false,
  }

  local IMPORT = Recipe.source.import or "oras_cci"
  local MODULES = { "lz", "garc", "ctr", "bclim", "crc32", "gen6text", "darc", "bcstm", "bcsar", "seqsynth", "bch" }

  local function log(fmt, ...) mod.log:info("import: " .. fmt, ...) end

  -- Each row's bytes are checked against Alpha Sapphire Rev 2's (data/oras_fingerprints.lua),
  -- so any decrypted dump that holds them works: a row whose bytes differ is skipped and its
  -- feature draws PlayNav's own art, as without the import. Off when the table is absent or
  -- was made for another recipe.
  local Fp = nil
  do
    local src = mod.read and mod:read("src/import/fingerprint.lua")
    local chunk = src and load(src, "=src/import/fingerprint.lua")
    local ok, F = pcall(chunk or error)
    local rows = deps.fingerprints
    if ok and type(F) == "table" and type(rows) == "table" and rows.recipe == Recipe.version
        and type(rows.rows) == "table" then
      Fp = { key = F.key, rows = rows.rows, DIFFERS = F.DIFFERS, MISSING = F.MISSING }
    elseif type(rows) == "table" then
      mod.log:warn("import: fingerprints are for recipe %s, not %s; rows are not checked (regenerate with tools/oras_fingerprints.lua)",
        tostring(rows.recipe), tostring(Recipe.version))
    end
  end
  E.verifying = Fp ~= nil
  E.differs = 0
  function E.fingerprints() return Fp and Fp.rows end

  local function isDiffers(err) return type(err) == "string" and err:find("^fingerprint:") ~= nil end

  -- true, info; or false, nil, the engine's reason
  function E.importPresent()
    local ok, info, err = pcall(mod.imports.info, mod.imports, IMPORT)
    if ok and type(info) == "table" then return true, info end
    return false, nil, ok and err or info
  end

  -- why the card image cannot be used: "missing" (nothing imported) or "wrong" (a file is
  -- there but it is not Alpha Sapphire: the engine's size or MD5 check refused it)
  local function whyAbsent(err)
    local s = tostring(err or "")
    if s == "" or s:find("missing", 1, true) or s:find("undeclared", 1, true)
        or s:find("unavailable", 1, true) then
      return "missing"
    end
    return "wrong"
  end

  function E.cacheManifest()
    local ok, src, readErr = pcall(mod.cache.read, mod.cache, "oras/manifest.lua")
    if not ok then E.lastManifestError = "read raised: " .. tostring(src); return nil end
    if type(src) ~= "string" or #src == 0 then
      E.lastManifestError = "read failed: " .. tostring(readErr or src)
      return nil
    end
    local chunk, cerr = load(src, "=oras/manifest.lua")
    if not chunk then E.lastManifestError = "compile: " .. tostring(cerr); return nil end
    local okRun, m = pcall(chunk)
    if okRun and type(m) == "table" then
      E.lastManifestError = nil
      return m
    end
    E.lastManifestError = "run: " .. tostring(m)
    return nil
  end

  -- a manifest counts when it is for this recipe and holds at least one asset
  -- (a run where every job was refused must not pass as done)
  function E.cacheComplete()
    local m = E.cacheManifest()
    if not (m ~= nil and m.version == Recipe.version and m.source and m.source.md5 == Recipe.source.md5) then
      return false
    end
    return type(m.assets) == "table" and next(m.assets) ~= nil
  end

  -- what should happen on this boot; never disturbs a run in progress
  function E.check()
    if E.state == "running" or E.state == "finishing" then return "running" end
    if E.cacheComplete() then
      E.state, E.why = "complete", nil
      return "complete"
    end
    local present, _, err = E.importPresent()
    if not present then
      E.state, E.why = "absent", whyAbsent(err)
      return "absent"
    end
    E.state, E.why = "idle", nil
    return "ready"
  end

  local function jobAvailable()
    local ok, avail = pcall(function() return mod.job and mod.job:available() end)
    return ok and avail == true
  end

  local function moduleSources()
    local out = {}
    for _, name in ipairs(MODULES) do
      local src = mod:read("src/import/" .. name .. ".lua")
      if not src then return nil, name end
      out[name] = src
    end
    return out
  end

  function E.start()
    if E.state == "running" or E.state == "finishing" then return false, "already running" end
    local present, _, err = E.importPresent()
    if not present then E.state, E.why = "absent", whyAbsent(err); return false, "no import" end
    E.why = nil
    if not jobAvailable() then E.state = "failed"; E.message = "Background jobs are unavailable."; return false, "no jobs" end
    local sources, missing = moduleSources()
    if not sources then E.state = "failed"; E.message = "Reader module missing: " .. tostring(missing); return false, "module" end
    E.sources = sources
    -- group recipe items per archive, keep recipe order
    local byArchive, order = {}, {}
    for _, item in ipairs(Recipe.assets) do
      if not byArchive[item.archive] then
        byArchive[item.archive] = { archive = item.archive, items = {} }
        order[#order + 1] = item.archive
      end
      local list = byArchive[item.archive].items
      list[#list + 1] = item
    end
    E.archives = {}
    for _, a in ipairs(order) do E.archives[#E.archives + 1] = byArchive[a] end
    E.total, E.done, E.failed, E.differs = #Recipe.assets, 0, 0, 0
    E.results, E.pending, E.jobs = {}, {}, {}
    E.cancelled = false
    E.state = "running"
    E.startedAt = os.time()
    E.message = "Extracting OR/AS assets..."
    log("start: %d textures from %d archives%s", E.total, #E.archives,
      Fp and ", each checked against Alpha Sapphire Rev 2" or ", unchecked")
    onChange()
    return true
  end

  function E.cancel()
    if E.state ~= "running" and E.state ~= "finishing" then return end
    E.cancelled = true
    for handle in pairs(E.jobs) do pcall(mod.job.cancel, mod.job, handle) end
    E.jobs = {}
    E.state = "idle"
    E.message = "Extraction paused; it resumes on the next boot."
    onChange()
  end

  -- CLEAR EXTRACTED ART: every file the import wrote goes. The manifest first, so the
  -- cache counts as incomplete from that instant even if a later delete fails; then each
  -- recipe row's outputs, by kind, as the job names them (mod.cache has no listing, so
  -- the layout packs are found through the index the job writes beside them). Returns
  -- the number of files removed.
  function E.clear()
    E.cancel()
    local function del(rel)
      local ok, done = pcall(mod.cache.delete, mod.cache, rel)
      return ok and done ~= false and done ~= nil
    end
    local removed = del("oras/manifest.lua") and 1 or 0
    for _, item in ipairs(Recipe.assets or {}) do
      local id, kind = item.id, item.kind
      if kind == "text" then
        if del("oras/text/" .. id:gsub("^text/", "") .. ".lua") then removed = removed + 1 end
      elseif kind == "stream" or kind == "song" then
        local name = id:gsub("^bgm/", "")
        if del("oras/bgm/" .. name .. ".wav") then removed = removed + 1 end
        if del("oras/bgm/" .. name .. ".lua") then removed = removed + 1 end
      elseif kind == "sfx" then
        if del("oras/se/" .. id:gsub("^se/", "") .. ".wav") then removed = removed + 1 end
      elseif kind == "files" then
        local pack = id:gsub("^lyt/", "")
        local okI, src = pcall(mod.cache.read, mod.cache, "oras/lyt/" .. pack .. "/index.lua")
        local chunk = okI and type(src) == "string" and load(src, "=index", "t", {}) or nil
        local okN, names = pcall(chunk or error)
        for _, name in ipairs(okN and type(names) == "table" and names or {}) do
          if type(name) == "string" and del("oras/lyt/" .. pack .. "/" .. name) then removed = removed + 1 end
        end
        if del("oras/lyt/" .. pack .. "/index.lua") then removed = removed + 1 end
      else
        -- an image (CLIM or BCH texture): the PNG, and any raw pixels left mid-run
        if del("oras/png/" .. id .. ".png") then removed = removed + 1 end
        if del("oras/raw/" .. id .. ".rgba") then removed = removed + 1 end
      end
    end
    E.results, E.pending, E.archives = {}, {}, {}
    E.total, E.done, E.failed, E.differs = 0, 0, 0, 0
    E.cancelled, E.message = false, nil
    E.state = "idle"
    if Assets and Assets.refresh then Assets.refresh() end
    E.check()
    onChange()
    mod.log:info("extracted art cleared: %d files removed", removed)
    return removed
  end

  local function launch(group)
    local arg = {
      importId = IMPORT, archive = group.archive, items = {},
      modules = E.sources, outPrefix = "oras/raw/",
      verify = Fp ~= nil, differs = Fp and Fp.DIFFERS, missingFp = Fp and Fp.MISSING,
    }
    for i, item in ipairs(group.items) do
      arg.items[i] = { entry = item.entry, sub = item.sub, clim = item.clim, id = item.id,
        w = item.w, h = item.h, fmt = item.fmt, kind = item.kind, lines = item.lines,
        match = item.match, count = item.count, name = item.name, path = item.path, tempo = item.tempo, gain = item.gain,
        fp = Fp and Fp.rows[Fp.key(item)] or nil }
    end
    local handle, err = mod.job:run("src/import/job_extract.lua", arg, { assetIO = true, maxSeconds = 300 })
    if not handle then
      -- the engine's job slots are busy (another mod, or jobs of ours it
      -- still counts): try this archive again shortly
      if tostring(err):find("in flight") and (group.retries or 0) < 40 then
        group.retries = (group.retries or 0) + 1
        table.insert(E.archives, 1, group)
        E.retryAt = os.clock() + 0.5
        if group.retries == 1 then log("job for %s waits: %s", group.archive, tostring(err)) end
        return "retry"
      end
      log("job for %s refused: %s", group.archive, tostring(err))
      for _, item in ipairs(group.items) do
        E.results[item.id] = { ok = false, err = "job: " .. tostring(err) }
        E.done, E.failed = E.done + 1, E.failed + 1
      end
      return false
    end
    E.jobs[handle] = group
    return true
  end

  local function inflight()
    local n = 0
    for _ in pairs(E.jobs) do n = n + 1 end
    return n
  end

  -- one raw -> PNG conversion; returns true when something was converted
  local function convertOne()
    local id = table.remove(E.pending, 1)
    if not id then return false end
    local okR, raw = pcall(mod.cache.read, mod.cache, "oras/raw/" .. id .. ".rgba")
    if not (okR and type(raw) == "string" and raw:sub(1, 4) == "DSRW") then
      E.results[id] = { ok = false, err = "raw missing" }
      E.failed = E.failed + 1
      return true
    end
    local w = raw:byte(5) + raw:byte(6) * 256
    local h = raw:byte(7) + raw:byte(8) * 256
    local rgba = raw:sub(9)
    local okP, png = pcall(function()
      local data = love.image.newImageData(w, h, "rgba8", rgba)
      local file = data:encode("png")
      local s = file:getString()
      file:release()
      data:release()
      return s
    end)
    if okP and type(png) == "string" then
      pcall(mod.cache.write, mod.cache, "oras/png/" .. id .. ".png", png)
      pcall(mod.cache.delete, mod.cache, "oras/raw/" .. id .. ".rgba")
      E.results[id] = { ok = true, w = w, h = h, bytes = #png }
    else
      E.results[id] = { ok = false, err = "png: " .. tostring(png) }
      E.failed = E.failed + 1
    end
    return true
  end

  local function writeManifest()
    local lines = { "return {", ("  version = %d,"):format(Recipe.version),
      ("  source = { name = %q, md5 = %q, size = %d },"):format(Recipe.source.name, Recipe.source.md5, Recipe.source.size),
      ("  extractedAt = %d,"):format(os.time()), "  assets = {" }
    local missing = {}
    for _, item in ipairs(Recipe.assets) do
      local r = E.results[item.id]
      if r and r.ok then
        lines[#lines + 1] = ("    [%q] = { w = %d, h = %d, bytes = %d },"):format(item.id, r.w, r.h, r.bytes or 0)
      else
        missing[#missing + 1] = ("    [%q] = %q,"):format(item.id, r and tostring(r.err) or "not extracted")
      end
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "  missing = {"
    for _, m in ipairs(missing) do lines[#lines + 1] = m end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "}"
    local ok, err = pcall(mod.cache.write, mod.cache, "oras/manifest.lua", table.concat(lines, "\n") .. "\n")
    return ok, err, #missing
  end

  -- call every frame
  function E.update()
    if E.state ~= "running" and E.state ~= "finishing" then return end
    -- keep up to 2 jobs in flight
    while E.state == "running" and inflight() < 2 and #E.archives > 0
        and not (E.retryAt and os.clock() < E.retryAt) do
      local group = table.remove(E.archives, 1)
      if launch(group) == "retry" then break end
    end
    -- poll
    for handle, group in pairs(E.jobs) do
      local ok, st = pcall(mod.job.poll, mod.job, handle)
      if not ok then
        st = { status = "error", err = tostring(st) }
      end
      if st and st.status ~= "pending" then
        E.jobs[handle] = nil
        pcall(mod.job.release, mod.job, handle)
        if st.status == "ok" and type(st.result) == "table" then
          for _, r in ipairs(st.result.results or {}) do
            if r.ok and (r.kind == "text" or r.kind == "files" or r.kind == "stream" or r.kind == "sfx" or r.kind == "song") then
              E.results[r.id] = { ok = true, w = 0, h = 0, bytes = r.count or 0, text = true }
              E.done = E.done + 1
            elseif r.ok then
              E.pending[#E.pending + 1] = r.id
            else
              E.results[r.id] = { ok = false, err = r.err }
              if isDiffers(r.err) then E.differs = E.differs + 1 else E.failed = E.failed + 1 end
              E.done = E.done + 1
            end
          end
          local seen = {}
          for _, r in ipairs(st.result.results or {}) do seen[r.id] = true end
          for _, item in ipairs(group.items) do
            if not seen[item.id] then
              E.results[item.id] = { ok = false, err = "no result" }
              E.failed, E.done = E.failed + 1, E.done + 1
            end
          end
        else
          log("job for %s failed: %s", group.archive, tostring(st and st.err))
          for _, item in ipairs(group.items) do
            E.results[item.id] = { ok = false, err = "job: " .. tostring(st and st.err) }
            E.failed, E.done = E.failed + 1, E.done + 1
          end
        end
        onChange()
      end
    end
    -- convert a few raws per frame
    for _ = 1, 4 do
      if not convertOne() then break end
      E.done = E.done + 1
      onChange()
    end
    if E.state == "running" and #E.archives == 0 and inflight() == 0 and #E.pending == 0 then
      E.state = "finishing"
      local ok, err, missing = writeManifest()
      if ok and E.total > 0 and missing >= E.total then
        -- nothing matched: another game, an encrypted dump, or not a 3DS image at all
        E.state, E.why = "failed", "wrong"
        local why = nil
        for _, r in pairs(E.results) do
          if r.err and not isDiffers(r.err) then why = tostring(r.err):gsub("^job: ", ""); break end
        end
        E.message = E.differs > 0 and why == nil
          and "This file holds none of Alpha Sapphire's art. Import a decrypted Alpha Sapphire."
          or ("This file could not be read: %s"):format(tostring(why))
        log("nothing extracted: %d rows differ, first error %s", E.differs, tostring(why))
      elseif ok then
        E.state = "done"
        E.message = missing == 0
          and "OR/AS assets are ready. You can remove the ROM copy under Imported files."
          or ("OR/AS assets ready (%d of %d). You can remove the ROM copy under Imported files."):format(E.total - missing, E.total)
        log("done: %d ok, %d differ from Rev 2, %d failed in %ds", E.total - missing, E.differs, E.failed,
          os.time() - (E.startedAt or os.time()))
        if Assets then Assets.refresh() end
      else
        E.state = "failed"
        E.message = "Could not write the asset manifest: " .. tostring(err)
      end
      onChange()
    end
  end

  function E.progress()
    return E.done, E.total
  end

  return E
end
