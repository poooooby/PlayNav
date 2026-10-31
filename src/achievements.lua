-- NaviPlay's achievements, reported to the recomp_achievements framework (provider "play_nav")
-- when it is installed; without it every call here is a no-op.
--
--   A.note(event, ...)  the moments the code reports (a bag cleared, a regimen over, a game
--                       finished...); a few keep a lifetime count in the save's "achievements" table
--   A.sweep()           the facts the saves already hold (clears, affection, puffs, Decor...),
--                       recomputed idempotently; runs when the framework's save is ready and
--                       again, at most once a second, after the notes
--   A.tick(dt)          main's frame: runs a sweep a note asked for
--
-- deps: data (data/achievements.lua), training() / amie() -> the stores and rules (nil when
-- that app is off), now() -> seconds (tests).

return function(mod, deps)
  local A = { PROVIDER = "play_nav", SWEEP_GAP_S = 1 }
  local data = deps.data

  local ach, handle
  local ready = false
  local earned = {}     -- id -> true once the framework has it
  local lastValue = {}  -- id -> the last progress sent
  local dirty, lastSweep = false, -1e9
  local defs = {}
  for _, row in ipairs(data.list) do defs[row.id] = row end

  local function now()
    if deps.now then return deps.now() end
    local timer = love and love.timer
    return timer and timer.getTime and timer.getTime() or os.clock()
  end

  -- ---------------------------------------------------------------- the framework

  local function warn(fmt, ...)
    if mod.log and mod.log.warn then mod.log:warn(fmt, ...) end
  end

  local function find()
    local other = mod.find and mod:find("recomp_achievements")
    local api = other and other.exports
    if not (api and api.connect and api.supports) then return nil end
    local major = tonumber(tostring(api.apiVersion):match("^(%d+)"))
    if major ~= 1 or not api.supports("register_many") or not api.supports("progress") then return nil end
    return api
  end

  -- true while achievements are being tracked (framework found, ids registered)
  function A.active() return handle ~= nil end
  function A.isReady() return ready end

  function A.install()
    if handle then return true end
    ach = find()
    if not ach then return false end
    local okC, h = pcall(ach.connect, mod)
    if not (okC and h) then
      warn("achievements: could not connect to recomp_achievements (%s)", tostring(h))
      return false
    end
    local list = {}
    for i, row in ipairs(data.list) do
      local def = {}
      for k, v in pairs(row) do def[k] = v end
      list[i] = def
    end
    local okR, count, errors = pcall(h.registerMany, h, list)
    if not okR then
      warn("achievements: registration failed (%s)", tostring(count))
      return false
    end
    for _, e in ipairs(errors or {}) do
      warn("achievements: a definition was refused (%s: %s)", tostring(e.code), tostring(e.msg or e.message))
    end
    handle = h
    if mod.log and mod.log.info then mod.log:info("achievements: %d registered with recomp_achievements", tonumber(count) or 0) end
    if mod.events and mod.events.on and ach.events and ach.events.ready then
      mod.events:on(ach.events.ready, function()
        ready = true
        earned, lastValue = {}, {}
        dirty = true
        A.sweep(true)
      end)
    end
    return true
  end

  -- ---------------------------------------------------------------- reporting

  local function unlock(id)
    if not handle or earned[id] then return end
    if not defs[id] then return end
    local ok, res, code = pcall(handle.unlock, handle, id)
    if ok and (res == true or code == "already_unlocked") then earned[id] = true end
  end

  local function progress(id, n)
    if not handle or earned[id] then return end
    local def = defs[id]
    if not def then return end
    n = math.max(0, math.min(math.floor(tonumber(n) or 0), def.goal or 0))
    if lastValue[id] == n then return end
    local ok, res, code = pcall(handle.setProgress, handle, id, n)
    if ok and res == true then
      lastValue[id] = n
      if def.goal and n >= def.goal then earned[id] = true end
    elseif ok and code == "already_unlocked" then
      earned[id] = true
    end
  end

  -- ---------------------------------------------------------------- lifetime counts

  local function counts()
    if not (mod.save and mod.save.get) then return nil end
    local c = mod.save:get("achievements")
    if type(c) ~= "table" then
      c = {}
      mod.save:set("achievements", c)
    end
    c.bags = c.bags or 0
    c.bits = c.bits or 0
    c.gifts = c.gifts or 0
    c.flags = c.flags or {}
    c.puffKinds = c.puffKinds or {}
    return c
  end

  local function save()
    if mod.save and mod.save.set then
      local c = counts()
      if c then mod.save:set("achievements", c) end
    end
  end

  local function flag(name)
    local c = counts()
    if c and not c.flags[name] then
      c.flags[name] = true
      save()
    end
  end

  -- a one-shot moment: kept in the save so a sweep awards it even if the framework's save
  -- was not up when it happened
  local function mark(id)
    flag(id)
    unlock(id)
  end

  local function bump(field, by)
    local c = counts()
    if not c then return 0 end
    c[field] = (c[field] or 0) + (by or 1)
    save()
    return c[field]
  end

  -- ---------------------------------------------------------------- the sweep

  local function countPrefix(map, prefix)
    local n = 0
    for id, v in pairs(map or {}) do
      if v and type(id) == "string" and id:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
  end

  local function sweepTraining(T)
    local Store, Rules = T.Store, T.Rules
    local d = Store.data()
    local hits, clears, fully, supremely = 0, 0, false, false
    for _, m in pairs(d.mons or {}) do
      hits = hits + (tonumber(m.hits) or 0)
      if m.fully then fully = true end
      if m.supremely then supremely = true end
      for _, rec in pairs(m.courses or {}) do clears = clears + (tonumber(rec.clears) or 0) end
    end
    if hits >= 1 then unlock("first_punch") end
    progress("heavy_hitter", hits)
    progress("clears_30", clears)
    if fully then unlock("fully_trained") end
    if supremely then unlock("all_awards") end

    local cleared = d.cleared or {}
    if next(cleared) then unlock("first_regimen") end
    for level = 1, 3 do
      if countPrefix(cleared, "lv" .. level .. "_") >= 6 then unlock("lv" .. level .. "_grad") end
    end
    if T.courses and Rules.regularCleared then
      local okC, list = pcall(T.courses)
      if okC and Rules.regularCleared(cleared, list) then unlock("regular_clear") end
    end
    local secrets = countPrefix(cleared, "secret_")
    if secrets >= 1 then unlock("first_secret") end
    if secrets >= 12 then unlock("all_secret") end
    if cleared.secret_02 and cleared.secret_03 and cleared.secret_04 then unlock("stone_cups") end
    if cleared.secret_11 then unlock("sudden_death") end
    if cleared.secret_12 then unlock("finale") end
    if d.meta and d.meta.rocketShown then unlock("rocket_earned") end

    local c = counts()
    if c then
      progress("bag_collector", c.bags)
      progress("bit_buster", c.bits)
    end
  end

  local function sweepAmie(M)
    local Store, Rules = M.Store, M.Rules
    local puffs, maxed = 0, 0
    local fond, best = false, false
    for _, m in pairs(Store.mons() or {}) do
      puffs = puffs + (tonumber(m.puffsEaten) or 0)
      local a = tonumber(m.affection) or 0
      if Rules.level(a) >= 3 then fond = true end
      if a >= 255 then best = true; maxed = maxed + 1 end
    end
    if puffs >= 1 then unlock("first_puff") end
    progress("well_fed", puffs)
    if fond then unlock("fond") end
    if best then unlock("best_friends") end
    progress("squad", maxed)

    local games = Store.games() or {}
    local fives = 0
    local PRO = { berry = "berry_3", head = "head_3", tile = "puzzle_3" }
    for _, g in ipairs({ "berry", "head", "tile" }) do
      local rec = games[g]
      if rec then
        local star = false
        for _, v in pairs(rec.best or {}) do if (tonumber(v) or 0) >= 5 then star = true end end
        if star then fives = fives + 1 end
        if rec.best and (tonumber(rec.best.hard) or 0) >= 3 then unlock(PRO[g]) end
        if (tonumber(rec.unlocked) or 1) >= 4 then unlock("unlimited") end
      end
    end
    if fives >= 1 then unlock("five_star") end
    if fives >= 3 then unlock("five_each") end

    local D = M.Decor
    if D then
      local owned = D.ownedCount(Store.decor())
      progress("decor_50", owned)
      local total = 0
      for _, row in ipairs(D.CATALOG or {}) do if row.kind ~= "thumb" then total = total + 1 end end
      if total > 0 and owned >= total then unlock("decor_all") end
    end
    local room = Store.room()
    if room and room.items and next(room.items) then unlock("decor_first") end

    local meta = Store.meta()
    progress("walk", meta and meta.steps or 0)

    -- the kinds of Poke Puff ever owned: noted as they arrive, and the jar as it stands
    local c = counts()
    if c then
      for _, p in ipairs(Rules.ownedPuffs(Store.puffs() or {})) do
        if not c.puffKinds[p.id] then c.puffKinds[p.id] = true; save() end
      end
      local kinds = 0
      for _ in pairs(c.puffKinds) do kinds = kinds + 1 end
      progress("puffs_10", kinds)
      progress("puffs_all", kinds)
      progress("visitors_10", c.gifts)
      if c.puffKinds[data.HONOR_PUFF] then unlock("honor") end
    end
  end

  function A.sweep(force)
    if not (handle and ready) then return false end
    local t = now()
    if not force and t - lastSweep < A.SWEEP_GAP_S then dirty = true; return false end
    lastSweep, dirty = t, false
    local T = deps.training and deps.training() or nil
    if T then pcall(sweepTraining, T) end
    local M = deps.amie and deps.amie() or nil
    if M then pcall(sweepAmie, M) end
    local c = counts()
    if c then
      for name in pairs(c.flags) do unlock(name) end
    end
    return true
  end

  function A.tick()
    if dirty then A.sweep() end
  end

  -- ---------------------------------------------------------------- the moments

  local EVENTS = {}

  -- Super Training
  EVENTS.punch = function() end
  EVENTS.step = function() end
  EVENTS.bag_cleared = function() mark("bag_cleared"); bump("bags") end
  EVENTS.blank_find = function(rare)
    mark("lucky_find")
    if rare then mark("rare_find") end
  end
  EVENTS.second_wind = function() mark("second_wind") end
  EVENTS.goal_hit = function(e)
    if type(e) == "table" and (tonumber(e.stage) or 0) >= 1 then mark("charged") end
  end
  -- res: the result table; stats: the sim's; with3d / circuit: how it was played
  EVENTS.regimen_end = function(res, stats, with3d, circuit)
    stats = stats or {}
    if (tonumber(stats.blocked) or 0) > 0 then mark("shield") end
    if (tonumber(stats.bitsPopped) or 0) > 0 then bump("bits", stats.bitsPopped) end
    if res and res.clear then
      if res.medal then mark("first_award") end
      if res.newBest and not res.firstClear then mark("new_best") end
      if (tonumber(stats.playerHits) or 0) == 0 then mark("flawless") end
      if circuit then mark("circuit") end
      if with3d then mark("stadium_3d") end
    end
  end
  EVENTS.konami = function() mark("konami") end
  EVENTS.rocket_buy = function() mark("dealer") end
  EVENTS.wing = function() mark("wing") end

  -- Pokemon-Amie
  EVENTS.pet_reward = function() mark("first_pet") end
  EVENTS.gift = function() mark("first_gift") end
  EVENTS.dance = function() mark("dance") end
  EVENTS.high_five = function() mark("high_five") end
  EVENTS.hit = function() mark("ouch") end
  EVENTS.effect_spot = function() mark("handle_care") end
  EVENTS.endure = function() mark("endure") end
  EVENTS.fever = function() mark("fever") end
  EVENTS.combo = function(n)
    if (tonumber(n) or 0) >= 100 then mark("combo_100") end
  end
  -- result: Games.finish's table
  EVENTS.game_finished = function(result)
    mark("first_game")
    if type(result) ~= "table" then return end
    if result.game == "tile" and result.diff == "hard" and result.value
        and tonumber(result.value) <= data.PUZZLE_SECONDS and (tonumber(result.stars) or 0) >= 1 then
      mark("puzzle_time")
    end
  end
  EVENTS.gift_claimed = function()
    mark("visitor")
    bump("gifts")
  end
  EVENTS.puff_owned = function(kind)
    local c = counts()
    if c and kind and not c.puffKinds[kind] then
      c.puffKinds[kind] = true
      save()
    end
    if kind == data.HONOR_PUFF then mark("honor") end
  end
  
  -- a note never throws into the game; with the framework connected the moment is kept in the
  -- save, and awarded at once when its save is up
  function A.note(event, ...)
    if not handle then return end
    local fn = EVENTS[event]
    if not fn then return end
    pcall(fn, ...)
    dirty = true
  end

  A.EVENTS = EVENTS
  A.defs = defs
  return A
end
