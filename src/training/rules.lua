-- Pure Super Training rules over data/training_rules.lua: the bag catalogue, EV maths
-- (252 per stat, 510 total), the unlock ladder, medals, the bag and prize rolls, and the
-- regimen modifiers a Pokemon's EVs and pending bag give the simulation. No engine, no love.
--
-- R = rules(N, ShotTypes)   N = data/training_rules.lua, ShotTypes = data/training_shot_types.lua

return function(N, ShotTypes)
  ShotTypes = ShotTypes or {}
  local R = { N = N }

  R.STATS = { "hp", "atk", "def", "spa", "spd", "spe" }
  R.STAT_LABEL = { hp = "HP", atk = "ATTACK", def = "DEFENSE", spa = "SP. ATK", spd = "SP. DEF", spe = "SPEED" }
  R.STAT_SHORT = { hp = "HP", atk = "ATK", def = "DEF", spa = "SPA", spd = "SPD", spe = "SPE" }
  -- the line each stat bag is patterned after (Bulbapedia)
  R.STAT_BAG_LINE = { hp = "Azurill", atk = "Machop", def = "Aron", spa = "Litwick", spd = "Flabebe", spe = "Zubat" }
  R.SIZES = { "s", "m", "l" }
  R.SIZE_LABEL = { s = "S", m = "M", l = "L" }
  R.COLOURS = { "black", "yellow", "orange", "green", "blue" }
  R.EFFECT_LABEL = {
    big_shot = "BIG SHOT", double_up = "DOUBLE-UP", strength = "STRENGTH", swiftness = "SWIFTNESS",
    toughen_up = "TOUGHEN-UP", refreshed = "TEAM FLARE", reset = "RESET", friendship = "SOOTHING",
  }

  -- ------- the 27 bags

  R.BAGS, R.BAG_LIST = {}, {}
  local function addBag(id, def)
    R.BAGS[id] = def
    R.BAG_LIST[#R.BAG_LIST + 1] = id
    def.id = id
  end
  for _, stat in ipairs(R.STATS) do
    for _, size in ipairs(R.SIZES) do
      local base = N.BAGS.STAT[size]
      addBag(stat .. "_" .. size, {
        kind = "stat", stat = stat, size = size, hits = base.hits, ev = base.ev,
        label = ("%s BAG %s"):format(R.STAT_LABEL[stat], R.SIZE_LABEL[size]),
      })
    end
  end
  for _, id in ipairs({ "big_shot", "double_up", "strength", "swiftness", "toughen_up", "team_flare", "reset", "soothing" }) do
    local b = N.BAGS[id]
    local kind = (id == "reset" and "reset") or (id == "soothing" and "soothing") or "effect"
    addBag(id, { kind = kind, hits = b.hits, effect = b.effect, amount = b.amount,
      label = (R.EFFECT_LABEL[b.effect] or id:upper()) .. " BAG" })
  end
  -- the game's own bag order (the name list in the ORAS text archive a/0/7/3 file 24,
  -- lines 1..26): the stat bags S/M/L per stat in HP, Atk, Def, SpA, SpD, Spe order,
  -- then Strength, Toughen-Up, Swiftness, Big-Shot, Double-Up, Team Flare, Reset,
  -- Soothing. The icons in a/0/2/8 entry 0 follow it (sand_bag00 is the empty bag), and
  -- the descriptions sit at a/0/7/3 file 27 lines 18 + n.
  R.GAME_ORDER = {}
  for _, stat in ipairs(R.STATS) do
    for _, size in ipairs(R.SIZES) do R.GAME_ORDER[#R.GAME_ORDER + 1] = stat .. "_" .. size end
  end
  for _, id in ipairs({ "strength", "toughen_up", "swiftness", "big_shot", "double_up", "team_flare", "reset", "soothing" }) do
    R.GAME_ORDER[#R.GAME_ORDER + 1] = id
  end
  R.BAG_ART, R.GAME_INDEX = { ["black"] = 0 }, {}
  for i, id in ipairs(R.GAME_ORDER) do R.BAG_ART[id] = i; R.GAME_INDEX[id] = i end
  -- where the game keeps the bag screen's strings (a/0/7/3 file 27)
  R.TEXT_LINE = { use = 13, discard = 14, back = 15, yes = 16, no = 17, askUse = 7, askDiscard = 8,
    replaceEffect = 9, replaceBag = 10, resting = 11, descBase = 18 }

  -- descriptions in our own words, used until the player's card supplies the game's
  local SIZE_WORD = { s = "slightly", m = "a fair amount", l = "quite a lot" }
  local EFFECT_TEXT = {
    strength = "More points for every goal in the next regimen.",
    toughen_up = "Balloon Bot hits cost fewer points in the next regimen.",
    swiftness = "Faster movement in the next regimen.",
    big_shot = "Bigger shots in the next regimen.",
    double_up = "Twice the stat gain from the next regimen.",
    team_flare = "Training feels great: half the hits for the next bag.",
    reset = "Clears every stat the Pokemon has trained.",
    soothing = "The Pokemon grows a little friendlier.",
  }
  function R.fallbackText(id)
    local b = R.BAGS[id]
    if not b then return "" end
    if b.kind == "stat" then
      return ("Trains %s %s (+%d).\n%d hits to finish."):format(R.STAT_LABEL[b.stat], SIZE_WORD[b.size], b.ev, b.hits)
    end
    return (EFFECT_TEXT[id] or "") .. ("\n%d hits to finish."):format(b.hits)
  end

  function R.bag(id) return R.BAGS[id] end

  -- hits a bag needs; a refreshed Pokemon needs fewer (rounded up)
  function R.bagHits(id, refreshed)
    local b = R.BAGS[id]
    if not b then return 0 end
    if refreshed then return math.ceil(b.hits / N.CORE.REFRESHED_HITS_DIV) end
    return b.hits
  end

  function R.isStatBag(id) local b = R.BAGS[id]; return b ~= nil and b.kind == "stat" end
  function R.isEffectBag(id) local b = R.BAGS[id]; return b ~= nil and b.kind == "effect" end

  -- ------- EVs

  local function evOf(evs, k) return math.max(0, math.floor(tonumber(evs and evs[k]) or 0)) end

  function R.evTotal(evs)
    local t = 0
    for _, k in ipairs(R.STATS) do t = t + evOf(evs, k) end
    return t
  end

  -- adds `amount` to evs[stat] within the 252 / 510 caps; returns the amount really added
  function R.addEv(evs, stat, amount)
    if not evs or not R.STAT_LABEL[stat] then return 0 end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    local cur = evOf(evs, stat)
    local room = math.min(N.LIMITS.EV_CAP - cur, N.LIMITS.EV_TOTAL - R.evTotal(evs))
    local add = math.max(0, math.min(amount, room))
    evs[stat] = cur + add
    return add
  end

  function R.resetEvs(evs)
    if not evs then return 0 end
    local before = R.evTotal(evs)
    for _, k in ipairs(R.STATS) do evs[k] = 0 end
    return before
  end

  function R.isFullyTrained(evs) return R.evTotal(evs) >= N.LIMITS.EV_TOTAL end
  function R.evRoom(evs) return math.max(0, N.LIMITS.EV_TOTAL - R.evTotal(evs)) end
  function R.statRoom(evs, stat)
    return math.max(0, math.min(N.LIMITS.EV_CAP - evOf(evs, stat), R.evRoom(evs)))
  end

  -- the EVs a cleared course gives: level x 4, doubled by a pending Double-Up
  function R.courseEv(course, pending)
    local ev = course and course.ev or 0
    if pending == "double_up" then ev = ev * N.LIMITS.DOUBLE_UP_MULT end
    return ev
  end

  -- ------- shot type

  -- colour for a species: the Bulbapedia table by National number, else by primary type
  function R.shotType(national, types)
    local c = national and ShotTypes[national]
    if c then return c end
    local t1 = type(types) == "table" and types[1] or types
    return (t1 and N.SHOT_TYPE_BY_TYPE[t1]) or "black"
  end

  -- ------- regimen modifiers from EVs and the pending bag

  local function frac(evs, ...)
    local sum, n = 0, select("#", ...)
    for i = 1, n do sum = sum + evOf(evs, (select(i, ...))) end
    return math.min(1, sum / (N.LIMITS.EV_CAP * n))
  end

  -- opts = { pokerus = bool }
  function R.modifiers(evs, pending, opts)
    opts = opts or {}
    local atk = frac(evs, "atk", "spa")
    local hp = frac(evs, "hp")
    local def = frac(evs, "def", "spd")
    local spe = frac(evs, "spe")
    local m = {
      pointMult = 1 + N.POINTS.ATK_BONUS * atk,
      shotSize = 1 + N.SHOT.HP_SIZE_BONUS * hp,
      lossMult = 1 - N.DAMAGE.HP_REDUCE * hp,
      gutsRate = 1 + N.GUTS.DEF_BONUS * def,
      blockLen = 1 + N.BLOCK.DEF_BONUS * def,
      moveMult = 1 + N.PLAYER.SPE_BONUS * spe,
      ballSpeedMult = 1 + N.SHOT.SPE_SPEED_BONUS * spe,
      evMult = 1,
      pending = pending,
    }
    if pending == "big_shot" then m.shotSize = m.shotSize * N.SHOT.BIG_SHOT_SIZE
    elseif pending == "strength" then m.pointMult = m.pointMult * N.POINTS.STRENGTH_MULT
    elseif pending == "swiftness" then m.moveMult = m.moveMult * N.PLAYER.SWIFT_MULT
    elseif pending == "toughen_up" then m.lossMult = m.lossMult * N.DAMAGE.TOUGHEN_MULT
    elseif pending == "double_up" then m.evMult = N.LIMITS.DOUBLE_UP_MULT end
    return m
  end

  -- ------- the ladder

  local function regularIds(courses, level)
    local out = {}
    for _, c in ipairs(courses or {}) do
      if not c.secret and c.level == level then out[#out + 1] = c.id end
    end
    return out
  end

  -- Lv1 is always open; Lv2 / Lv3 open when every course of the level below is cleared
  function R.levelUnlocked(cleared, level, courses)
    if level <= 1 then return true end
    local below = regularIds(courses, level - 1)
    if #below == 0 then return false end
    for _, id in ipairs(below) do
      if not (cleared and cleared[id]) then return false end
    end
    return true
  end

  -- the secret courses open one after another
  function R.nextSecret(cleared, courses)
    local n = 0
    for _, c in ipairs(courses or {}) do
      if c.secret then
        n = math.max(n, c.secret)
        if not (cleared and cleared[c.id]) then return c.secret end
      end
    end
    return n + 1
  end

  -- ok, why ("locked" | "not_fully_trained")
  function R.canEnter(course, cleared, courses, fully)
    if not course then return false, "locked" end
    if course.secret then
      if not fully then return false, "not_fully_trained" end
      if course.secret > R.nextSecret(cleared, courses) then return false, "locked" end
      return true
    end
    if not R.levelUnlocked(cleared, course.level, courses) then return false, "locked" end
    return true
  end

  function R.allMedals(mons, courses)
    for _, c in ipairs(courses or {}) do
      local rec = mons and mons.courses and mons.courses[c.id]
      if not (rec and rec.medal) then return false end
    end
    return #(courses or {}) > 0
  end

  -- ------- clocks and medals

  function R.courseTime(course) return (course and course.time) or N.CLOCK.TIME end

  -- the medal target in seconds remaining: the row's own, else by level
  function R.medalTarget(course)
    if course and course.medal then return course.medal end
    if course and course.secret then return N.CLOCK.TARGET.secret end
    return N.CLOCK.TARGET[course and course.level or 1] or N.CLOCK.TARGET[1]
  end

  function R.medal(course, remaining)
    return (tonumber(remaining) or 0) >= R.medalTarget(course)
  end

  -- ------- rolls (rng() in [0, 1))

  local function pick(weights, rng)
    local total = 0
    local keys = {}
    for k, w in pairs(weights) do
      if w > 0 then total = total + w; keys[#keys + 1] = k end
    end
    table.sort(keys)
    if total <= 0 then return nil end
    local r = (rng or math.random)() * total
    for _, k in ipairs(keys) do
      r = r - weights[k]
      if r < 0 then return k end
    end
    return keys[#keys]
  end

  local function randomStat(rng)
    return R.STATS[math.floor((rng or math.random)() * #R.STATS) + 1] or "hp"
  end

  local function resolve(key, rng)
    if key == "stat_s" then return randomStat(rng) .. "_s" end
    return key
  end

  -- the bag a cleared course gives: the course's stat bag sized by the clock left, or a
  -- Double-Up (more often with Pokerus); secret courses give a support bag
  -- opts = { pokerus = bool }
  function R.rollClearBag(course, remaining, rng, opts)
    rng = rng or math.random
    opts = opts or {}
    if not course or course.secret or not course.stat then return R.rollSupportBag(rng, opts) end
    local du = N.BAG_ODDS.clear.double_up * (opts.pokerus and N.BAG_ODDS.DOUBLE_UP_POKERUS_MULT or 1)
    if rng() < math.min(1, du) then return "double_up" end
    return course.stat .. "_" .. R.clearBagSize(course, remaining)
  end

  function R.clearBagSize(course, remaining)
    local f = (tonumber(remaining) or 0) / R.courseTime(course)
    if f >= N.BAG_ODDS.clear.l_at then return "l" end
    if f >= N.BAG_ODDS.clear.m_at then return "m" end
    return "s"
  end

  function R.rollSupportBag(rng, opts)
    opts = opts or {}
    local w = {}
    for k, v in pairs(N.BAG_ODDS.support) do w[k] = v end
    if opts.pokerus then w.double_up = (w.double_up or 0) * N.BAG_ODDS.DOUBLE_UP_POKERUS_MULT end
    return pick(w, rng) or "big_shot"
  end

  -- a bag dropping from the empty black bag, or nil
  function R.rollBlackBag(taps, rng)
    rng = rng or math.random
    if (taps or 0) < N.CORE.BLACK_BAG_MIN_TAPS then return nil end
    if rng() >= N.CORE.BLACK_BAG_DROP then return nil end
    return resolve(pick(N.BAG_ODDS.black, rng), rng)
  end

  -- a secret course's item: rows { item = "ITEM_X" | training = "<slug>" | "NAME", w,
  -- minRemaining?, bestOnly? }; opts = { newBest = bool }
  local function prizeKey(row) return row.item or row.training or row[1] end
  R.prizeKey = prizeKey

  function R.rollSecretPrize(course, remaining, rng, opts)
    opts = opts or {}
    local items = course and course.items
    if type(items) ~= "table" or #items == 0 then return nil end
    local w, byName = {}, {}
    for _, row in ipairs(items) do
      local key = prizeKey(row)
      local ok = key ~= nil
      if row.minRemaining and (tonumber(remaining) or 0) < row.minRemaining then ok = false end
      if row.bestOnly and not opts.newBest then ok = false end
      if ok then
        w[key] = (w[key] or 0) + (row.w or 1)
        byName[key] = row
      end
    end
    local name = pick(w, rng)
    return name and byName[name] or nil
  end

  -- ------- inventory (ordered list of bag ids, at most BAG_MAX)

  function R.inventoryAdd(bags, id)
    if not R.BAGS[id] then return false, "unknown" end
    if #bags >= N.LIMITS.BAG_MAX then return false, "full" end
    bags[#bags + 1] = id
    return true
  end

  function R.inventoryRemove(bags, index)
    if index < 1 or index > #bags then return nil end
    return table.remove(bags, index)
  end

  function R.inventoryFull(bags) return #bags >= N.LIMITS.BAG_MAX end

  -- ------- attack scripts

  -- spec: a list of { at = s, kind, ... } and { every = s, from = s, until = s, kind, ... },
  -- or the name of a list in `library`; returns the flat schedule sorted by time
  function R.compileAttacks(spec, library, horizon)
    horizon = horizon or N.CLOCK.TIME
    if type(spec) == "string" then spec = library and library[spec] end
    local out = {}
    for _, e in ipairs(spec or {}) do
      local function copy(t)
        local c = {}
        for k, v in pairs(e) do if k ~= "at" and k ~= "every" and k ~= "from" and k ~= "until" then c[k] = v end end
        c.t = t
        return c
      end
      if e.at then out[#out + 1] = copy(e.at) end
      if e.every and e.every > 0 then
        local t = e.from or e.every
        local last = e["until"] or horizon
        while t <= last do
          out[#out + 1] = copy(t)
          t = t + e.every
        end
      end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
  end

  -- ------- evidence coverage (for the tests and the docs)

  -- every leaf path of N (except EVIDENCE) and the evidence row that covers it, or nil
  function R.evidenceFor(path)
    local E = N.EVIDENCE or {}
    local p = path
    while p and p ~= "" do
      if E[p] then return E[p] end
      p = p:match("^(.*)%.[^.]+$")
    end
    return nil
  end

  function R.leafPaths()
    local out = {}
    local function walk(t, prefix)
      for k, v in pairs(t) do
        local p = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
        if type(v) == "table" then walk(v, p) else out[#out + 1] = p end
      end
    end
    for k, v in pairs(N) do
      if k ~= "EVIDENCE" then
        if type(v) == "table" then walk(v, k) else out[#out + 1] = k end
      end
    end
    table.sort(out)
    return out
  end

  return R
end
