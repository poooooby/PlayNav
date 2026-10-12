-- Pokemon-Amie stat rules, pure Lua: affection / fullness / enjoyment and
-- every event that moves them, the Poke Puff catalogue and jar. No love, no
-- engine. `N` is data/amie_rules.lua, passed in so tests can load both files.

return function(N)
  local R = { N = N }
  local MAX = N.MAX

  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end
  R.clamp = clamp
  function R.clamp255(v) return clamp(math.floor(v + 0.5), 0, MAX) end

  local function add(meters, field, delta)
    local before = meters[field] or 0
    meters[field] = R.clamp255(before + (delta or 0))
    return meters[field] - before
  end
  R.add = add

  -- ------- levels

  function R.level(points)
    points = points or 0
    local lv = 0
    for i = 1, 5 do
      if points >= N.LEVELS[i] then lv = i end
    end
    return lv
  end
  R.hearts = R.level

  function R.newMeters()
    return { affection = 0, fullness = 0, enjoyment = 0, puffsEaten = 0 }
  end

  -- ------- petting

  -- spot: "normal" | "favored" | "disfavored". Until the Pokemon has any
  -- affection every spot counts as normal. Returns the affection gained
  -- (hearts to show; 0 means a music note) and the enjoyment spent.
  function R.pet(meters, spot)
    if (meters.affection or 0) <= 0 then spot = "normal" end
    if spot == "disfavored" then
      local e = add(meters, "enjoyment", N.PET.disfavored.enj)
      return 0, e
    end
    local rows = N.PET[spot] or N.PET.normal
    local enj = meters.enjoyment or 0
    for _, row in ipairs(rows) do
      if enj >= row.min then
        local e = add(meters, "enjoyment", row.enj)
        local a = add(meters, "affection", row.aff)
        return a, e
      end
    end
    return 0, 0
  end

  -- how many px of stroke make the next petting event
  R.PET_STEP = N.PET.STEP_PX
  R.PET_FAST = N.PET.FAST_PX_PER_S

  -- ------- other play events

  function R.hit(meters) return add(meters, "enjoyment", N.HIT.ENJOYMENT) end
  function R.highFive(meters) return add(meters, "enjoyment", N.HIGH_FIVE.ENJOYMENT) end
  function R.canHighFive(meters) return (meters.affection or 0) >= N.HIGH_FIVE.MIN_AFFECTION end
  function R.openPlay(meters) return add(meters, "enjoyment", N.OPEN_PLAY.ENJOYMENT) end
  function R.openGame(meters) return add(meters, "enjoyment", N.GAME.OPEN_ENJOYMENT) end

  -- a won minigame, applied to every participant
  function R.gameWin(meters, game, difficulty)
    local enj = N.GAME.ENJOYMENT
    if game == "tile" and (difficulty == "easy" or difficulty == "normal") then enj = N.GAME.ENJOYMENT_EASY_TILE end
    add(meters, "fullness", N.GAME.FULLNESS)
    return add(meters, "enjoyment", enj)
  end

  function R.battleEntered(meters)
    add(meters, "fullness", N.BATTLE.FULLNESS)
    add(meters, "enjoyment", N.BATTLE.ENJOYMENT)
  end

  -- `blocks` completed blocks of 50 steps
  function R.steps(meters, blocks)
    for _ = 1, blocks or 1 do
      add(meters, "fullness", N.STEPS.FULLNESS)
      if (meters.enjoyment or 0) < N.STEPS.ENJOYMENT_BELOW then add(meters, "enjoyment", N.STEPS.ENJOYMENT) end
    end
  end

  -- milestones crossed between two affection values
  function R.danceCrossed(before, after)
    if after <= before then return false end
    if after >= MAX and before < MAX then return 3 end
    local b, a = math.floor(before / N.DANCE_EVERY), math.floor(after / N.DANCE_EVERY)
    if a > b and a * N.DANCE_EVERY ~= 250 then return 2 end
    return false
  end

  function R.giftsCrossed(before, after)
    local out = {}
    for _, t in ipairs(N.GIFT_AFFECTION) do
      if before < t and after >= t then out[#out + 1] = t end
    end
    return out
  end

  -- the icon over a wandering Pokemon: "puff" | "note" | "orange_note" | nil
  function R.hint(meters)
    local f, e = meters.fullness or 0, meters.enjoyment or 0
    if f < N.HINT.LOW or e < N.HINT.LOW then
      return (f <= e) and "puff" or "note"
    end
    if f >= N.HINT.HIGH and e >= N.HINT.HIGH then return "orange_note" end
    return nil
  end

  function R.canEat(national) return not N.NON_EATERS[national or 0] end
  function R.canPet(national) return not N.NO_PET[national or 0] end

  -- ------- Poke Puffs: 26 varieties, ids match data/oras_recipe.lua

  R.PUFFS, R.PUFF_BY_ID = {}, {}
  do
    local flavors = { "sweet", "mint", "citrus", "mocha", "spice" }
    local tiers = { { "basic", "" }, { "frosted", "Frosted " }, { "fancy", "Fancy " }, { "deluxe", "Deluxe " } }
    local weights = { basic = 60, frosted = 25, fancy = 10, deluxe = 4 }
    local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end
    for _, tier in ipairs(tiers) do
      for _, flavor in ipairs(flavors) do
        local p = { id = "puff/" .. flavor .. "_" .. tier[1], tier = tier[1], flavor = flavor,
          name = tier[2] .. cap(flavor) .. " Poke Puff",
          affection = N.PUFF.AFFECTION[tier[1]], weight = weights[tier[1]] / #flavors }
        R.PUFFS[#R.PUFFS + 1] = p
        R.PUFF_BY_ID[p.id] = p
      end
    end
    for _, s in ipairs({ "honor", "wish", "spring", "summer", "fall", "winter" }) do
      local special = (s == "honor" or s == "wish")
      local p = { id = "puff/supreme_" .. s, tier = "supreme", flavor = s, seasonal = not special,
        name = "Supreme " .. (s == "fall" and "Autumn" or cap(s)) .. " Poke Puff",
        affection = special and N.PUFF.AFFECTION.supreme_special or N.PUFF.AFFECTION.supreme,
        weight = special and 0 or 1 / 4 }
      R.PUFFS[#R.PUFFS + 1] = p
      R.PUFF_BY_ID[p.id] = p
    end
  end

  -- the game's own name when the text is extracted (R.textPuffName is set by the session)
  R.textPuffName = nil
  function R.puffName(id)
    local t = R.textPuffName and R.textPuffName(id)
    if t then return t end
    local p = R.PUFF_BY_ID[id]
    return p and p.name or "Poke Puff"
  end

  -- ------- evidence: where each number in data/amie_rules.lua comes from

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
      if k ~= "EVIDENCE" and k ~= "version" then
        if type(v) == "table" then walk(v, k) else out[#out + 1] = k end
      end
    end
    table.sort(out)
    return out
  end

  function R.puffTier(id)
    local p = R.PUFF_BY_ID[id]
    return p and p.tier or nil
  end

  -- The jar is a list of puff ids in the order they were obtained; past the
  -- cap the oldest is lost, the way the game's 100-puff inventory behaves.
  function R.jarAdd(jar, id)
    jar[#jar + 1] = id
    while #jar > N.PUFF.CAP do table.remove(jar, 1) end
    return jar
  end

  -- remove the oldest puff of that variety; false when none
  function R.jarTake(jar, id)
    for i, v in ipairs(jar) do
      if v == id then table.remove(jar, i); return true end
    end
    return false
  end

  function R.jarCount(jar, id)
    local n = 0
    for _, v in ipairs(jar) do if v == id then n = n + 1 end end
    return n
  end

  function R.jarTotal(jar) return #jar end

  -- the varieties the player has, in catalogue order
  function R.ownedPuffs(jar)
    local counts = {}
    for _, v in ipairs(jar) do counts[v] = (counts[v] or 0) + 1 end
    local out = {}
    for _, p in ipairs(R.PUFFS) do
      if (counts[p.id] or 0) > 0 then out[#out + 1] = { id = p.id, count = counts[p.id], name = p.name, tier = p.tier } end
    end
    return out
  end

  -- one random puff by tier weight; rng() in [0, 1)
  function R.randomPuff(rng)
    rng = rng or math.random
    local total = 0
    for _, p in ipairs(R.PUFFS) do total = total + p.weight end
    local r = rng() * total
    for _, p in ipairs(R.PUFFS) do
      r = r - p.weight
      if r < 0 and p.weight > 0 then return p.id end
    end
    return R.PUFFS[1].id
  end

  function R.grantPuffs(jar, n, rng)
    for _ = 1, n or 1 do R.jarAdd(jar, R.randomPuff(rng)) end
    return jar
  end

  -- v1 saves: { plain = n } or { ["puff/x"] = count }; v2: an ordered list
  function R.migrateJar(old)
    local jar = {}
    if type(old) ~= "table" then return jar end
    if #old > 0 then
      for _, v in ipairs(old) do jar[#jar + 1] = v end
      return jar
    end
    local n = tonumber(old.plain) or 0
    for i = 1, n do jar[#jar + 1] = R.PUFFS[(i - 1) % 5 + 1].id end
    for _, p in ipairs(R.PUFFS) do
      for _ = 1, tonumber(old[p.id]) or 0 do jar[#jar + 1] = p.id end
    end
    while #jar > N.PUFF.CAP do table.remove(jar, 1) end
    return jar
  end

  -- ------- feeding

  -- how many bites a Pokemon takes: by its sprite size class
  function R.bitesFor(sizeClass)
    if sizeClass == "large" then return 2 end
    if sizeClass == "medium" then return 3 end
    return 5
  end

  -- "quick" | "slow_late" | "slow": how the bites play
  function R.bitePace(meters, bites)
    local f = meters.fullness or 0
    if f >= N.PUFF.ALL_SLOW_FROM then return "slow" end
    if f >= N.PUFF.SLOW_FROM then return bites == 2 and "quick" or "slow_late" end
    return "quick"
  end

  -- can the puff be offered? false, "full" | "cannot"
  function R.canFeed(meters, national)
    if not R.canEat(national) then return false, "cannot" end
    if (meters.fullness or 0) >= MAX then return false, "full" end
    return true
  end

  -- one bite of a puff that is not (yet) finished
  function R.bite(meters, bites)
    return add(meters, "fullness", N.PUFF.BITE_FULLNESS[bites] or N.PUFF.BITE_FULLNESS[3])
  end

  -- the whole puff eaten: fullness +50 total, affection by tier. `bitesTaken`
  -- partial bites were already credited and are deducted from the 50.
  function R.finishPuff(meters, id, bitesCredited, bites)
    local p = R.PUFF_BY_ID[id]
    local perBite = N.PUFF.BITE_FULLNESS[bites] or 0
    add(meters, "fullness", N.PUFF.FULLNESS - perBite * (bitesCredited or 0))
    meters.puffsEaten = (meters.puffsEaten or 0) + 1
    return add(meters, "affection", p and p.affection or N.PUFF.AFFECTION.basic)
  end

  -- the simple path: a whole puff in one call. Returns ok, hearts | reason
  function R.feed(meters, jar, id, national)
    local ok, why = R.canFeed(meters, national)
    if not ok then return false, why end
    if not R.jarTake(jar, id) then return false, "none" end
    return true, R.finishPuff(meters, id, 0, 2)
  end

  -- Status strings the host normalises to; nil when healthy
  R.STATUS_LABEL = {
    PSN = "POISONED", TOX = "BADLY POISONED", BRN = "BURNED", FRZ = "FROZEN",
    SLP = "ASLEEP", PAR = "PARALYZED",
  }

  return R
end
