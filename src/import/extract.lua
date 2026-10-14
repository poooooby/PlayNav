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
  local MODULES = { "lz", "garc", "ctr", "bclim", "gen6text", "darc", "bcstm", "bcsar", "seqsynth", "bch" }

  local function log(fmt, ...) mod.log:info("import: " .. fmt, ...) end

  function E.importPresent()
    local ok, info = pcall(mod.imports.info, mod.imports, IMPORT)
    return ok and type(info) == "table", info
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
      E.state = "complete"
      return "complete"
    end
    if not E.importPresent() then
      E.state = "absent"
      return "absent"
    end
    E.state = "idle"
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
    if not E.importPresent() then E.state = "absent"; return false, "no import" end
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
    E.total, E.done, E.failed = #Recipe.assets, 0, 0
    E.results, E.pending, E.jobs = {}, {}, {}
    E.cancelled = false
    E.state = "running"
    E.startedAt = os.time()
    E.message = "Extracting Pokemon-Amie art..."
    log("start: %d textures from %d archives", E.total, #E.archives)
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

  local function launch(group)
    local arg = {
      importId = IMPORT, archive = group.archive, items = {},
      modules = E.sources, outPrefix = "oras/raw/",
    }
    for i, item in ipairs(group.items) do
      arg.items[i] = { entry = item.entry, sub = item.sub, clim = item.clim, id = item.id,
        w = item.w, h = item.h, fmt = item.fmt, kind = item.kind, lines = item.lines,
        match = item.match, count = item.count, name = item.name }
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
            if r.ok and (r.kind == "text" or r.kind == "files" or r.kind == "stream" or r.kind == "sfx") then
              E.results[r.id] = { ok = true, w = 0, h = 0, bytes = r.count or 0, text = true }
              E.done = E.done + 1
            elseif r.ok then
              E.pending[#E.pending + 1] = r.id
            else
              E.results[r.id] = { ok = false, err = r.err }
              E.failed = E.failed + 1
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
      if ok then
        E.state = "done"
        E.message = missing == 0
          and "Pokemon-Amie art is ready. You can remove the ROM copy under Imported files."
          or ("Art ready (%d of %d). You can remove the ROM copy under Imported files."):format(E.total - missing, E.total)
        log("done: %d ok, %d failed in %ds", E.total - E.failed, E.failed, os.time() - (E.startedAt or os.time()))
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
