-- Super Training's host on the Game Boy games, over the Amie host (src/refresh/host_gb.lua):
-- what src/training/host.lua gives on Gen 3 - EVs and stats, friendship, Pokerus, money, the
-- bag, the songs and the audio settings - from the Gen 1 / 2 engine.
--
-- EVs are Stat Exp there (0..65535 a stat, five of them: HP, Attack, Defense, Speed and one
-- Special; no total). Super Training keeps its 0..252 EVs a stat and they map onto Stat Exp as
-- EV = ceil(sqrt(StatExp)) and StatExp = EV^2: a stat's bonus is ceil(sqrt(StatExp)) / 4 in
-- both games, so 252 (63504) is the full +63, as on Gen 3. evsOf hands Special as spc and as
-- spa / spd (the game's shot power, refill and the radar read those); a write takes spc.
-- A stat a write leaves at its EV keeps the Stat Exp it had (battles add odd amounts).

return function(mod, base)
  local H = setmetatable({}, { __index = base })
  H.base = base
  H.LAYER_ID = "play_nav_training"
  local profile = base.profile or {}
  local gen = profile.gen or 1

  local function req(name)
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then return m end
    return nil
  end
  H.Bag = req("src.inventory.Bag")
  H.Stats = gen == 1 and req("src.pokemon.Stats") or nil
  H.Mon = gen == 2 and req("src.battle.gen2.Mon") or nil
  H.Happiness = gen == 2 and req("src.core.gen2.Happiness") or nil
  H.Pokerus = gen == 2 and req("src.core.gen2.Pokerus") or nil

  local save, data = base.save, base.data

  function H.available() return base.available() end

  function H.pushLayer(module) return base.pushLayerAs(H.LAYER_ID, module) end
  function H.popLayer() return base.popLayerAs(H.LAYER_ID) end
  function H.layerOpen() return base.layerOpenAs(H.LAYER_ID) end

  function H.gameVersion() return profile.version end
  function H.songFamily() return profile.family end

  -- ------- music: the game's own player (src/core/Music)

  local function songs()
    local d = data()
    return d and d.audio and d.audio.songs or {}
  end
  -- a song label (or the first of a list) this game has
  function H.songId(name)
    local have = songs()
    if type(name) == "table" then
      for _, n in ipairs(name) do if have[n] then return n end end
      return nil
    end
    return (name and have[name]) and name or nil
  end
  -- the field's song, played back with the map's own restore
  H.FIELD = "__map"
  function H.fieldSong() return H.FIELD end
  function H.fadeToSong(id, speed)
    local M, d = base.Music, data()
    if not (M and d and id) then return false end
    if id == H.FIELD then return pcall(M.restoreMap, d, "play_nav") == true end
    return pcall(M.play, d, id, true, { fade = speed or 2, reason = "play_nav" }) == true
  end
  function H.fadeOutSong(speed)
    local M = base.Music
    if not (M and M.fadeOut) then return false end
    return pcall(M.fadeOut, speed or 2) == true
  end
  -- the field's music held while PlayNav's own plays (Gen 1 / 2 have no pause: it stops, and
  -- comes back from the map's start)
  function H.overworldMusic(on)
    local M, d = base.Music, data()
    if not M then return false end
    if on then return d ~= nil and pcall(M.restoreMap, d, "play_nav") == true end
    return pcall(M.stop) == true
  end

  -- the audio options (MUSIC / SFX volume 0..7, AUDIO MODE, MUSIC FILTER): Gen 1 keeps them in
  -- the save's options, Gen 2 on the game
  local function options()
    local g = base.game()
    if not g then return nil end
    if gen == 2 and type(g.options) == "table" then return g.options end
    local s = g.save
    return s and type(s.options) == "table" and s.options or (type(g.options) == "table" and g.options or nil)
  end
  H.options = options
  local function level(key)
    local o = options()
    local v = o and tonumber(o[key])
    if not v then return 1 end
    return math.max(0, math.min(1, v / 7))
  end
  function H.musicOn()
    local o = options()
    if o and o.audioMode == "external_only" then return false end
    return level("musicVol") > 0
  end
  function H.musicGain() return level("musicVol") end
  H.MUSIC_FILTER = { 0.4, 0.16, 0.064 }
  function H.musicFilter()
    local o = options()
    local l = o and tonumber(o.musicFilter)
    return l and H.MUSIC_FILTER[l] or nil
  end
  function H.soundMono() return false end
  function H.sfxGain() return level("sfxVol") end
  function H.audioSuspended() return false end

  -- ------- money

  H.MAX_MONEY = 999999
  local function purse()
    local s = save()
    if not s then return nil end
    if gen == 2 and type(s.player) == "table" then return s.player end
    return s
  end
  function H.session() return save() end
  function H.money()
    local p = purse()
    return p and math.max(0, math.floor(tonumber(p.money) or 0)) or 0
  end
  function H.spendMoney(n)
    local p = purse()
    n = math.floor(tonumber(n) or 0)
    if not p or n < 0 then return false end
    local have = H.money()
    if have < n then return false end
    p.money = have - n
    return true
  end

  -- ------- EVs over Stat Exp

  H.STAT_EXP = { hp = "hp", atk = "attack", def = "defense", spe = "speed", spc = "special" }
  H.KEYS = { "hp", "atk", "def", "spe", "spc" }
  H.EV_MAX = 255
  H.STAT_EXP_MAX = 65535

  local function virt(se)
    se = math.max(0, math.floor(tonumber(se) or 0))
    return math.min(H.EV_MAX, math.ceil(math.sqrt(se) - 1e-9))
  end
  H.evOfStatExp = virt
  function H.statExpOfEv(ev)
    ev = math.max(0, math.min(H.EV_MAX, math.floor(tonumber(ev) or 0)))
    return math.min(H.STAT_EXP_MAX, ev * ev)
  end

  function H.evsOf(mon)
    if type(mon) ~= "table" then return {} end
    local se = type(mon.statExp) == "table" and mon.statExp or {}
    local out = {}
    for _, k in ipairs(H.KEYS) do out[k] = virt(se[H.STAT_EXP[k]]) end
    out.spa, out.spd = out.spc, out.spc
    return out
  end

  function H.evTotal(mon)
    local t = 0
    local evs = H.evsOf(mon)
    for _, k in ipairs(H.KEYS) do t = t + evs[k] end
    return t
  end

  local function recalc(mon)
    local d = data()
    local rec = d and d.pokemon and d.pokemon[mon.species]
    if not (rec and rec.baseStats) then return false end
    if gen == 1 and H.Stats and H.Stats.calc then
      local ok, stats = pcall(H.Stats.calc, rec, mon.level or 1, mon.dvs or {}, mon.statExp)
      if ok and type(stats) == "table" then mon.stats = stats; return true end
    elseif gen == 2 and H.Mon and H.Mon.stats then
      local ok, stats = pcall(H.Mon.stats, rec.baseStats, mon.dvs, mon.level or 1, mon.statExp)
      if ok and type(stats) == "table" then
        if H.Mon.writeStats then pcall(H.Mon.writeStats, mon, stats) else mon.stats = stats end
        mon.maxHp = stats.hp
        return true
      end
    end
    return false
  end
  local function maxHp(mon)
    return tonumber(mon.maxHp) or tonumber(mon.stats and mon.stats.hp) or 0
  end

  -- writes the EVs as Stat Exp (spc, else the larger of spa / spd), recalculates the stats and
  -- moves the current HP with the max HP, never fainting a living Pokemon
  function H.setEvs(mon, evs)
    if not (type(mon) == "table" and type(evs) == "table") then return false end
    mon.statExp = type(mon.statExp) == "table" and mon.statExp or {}
    local se = mon.statExp
    local want = {}
    for _, k in ipairs(H.KEYS) do want[k] = evs[k] end
    if want.spc == nil and (evs.spa ~= nil or evs.spd ~= nil) then
      want.spc = math.max(tonumber(evs.spa) or 0, tonumber(evs.spd) or 0)
    end
    for _, k in ipairs(H.KEYS) do
      local key = H.STAT_EXP[k]
      local v = want[k]
      if v ~= nil then
        v = math.max(0, math.min(H.EV_MAX, math.floor(tonumber(v) or 0)))
        if v ~= virt(se[key]) then se[key] = H.statExpOfEv(v) end
        se[key] = se[key] or 0
      end
    end
    local oldMax, oldHp = maxHp(mon), tonumber(mon.hp) or 0
    if not recalc(mon) then mod.log:warn("stats not recalculated for %s", tostring(mon.species)) end
    local newMax = maxHp(mon)
    if oldHp ~= 0 or oldMax ~= 0 then
      local hp = oldHp + (newMax - oldMax)
      if oldHp > 0 then hp = math.max(1, hp) end
      mon.hp = math.max(0, math.min(newMax, hp))
    end
    return true
  end

  -- { hp, atk, def, spe, spa, spd } base stats (Gen 1's one Special as both)
  function H.baseStats(species)
    local d = data()
    local rec = d and d.pokemon and d.pokemon[species]
    local b = rec and rec.baseStats
    if type(b) ~= "table" then return nil end
    local spa = b.specialAttack or b.special
    local spd = b.specialDefense or b.special
    return { hp = b.hp, atk = b.attack, def = b.defense, spe = b.speed, spa = spa, spd = spd, spc = b.special or spa }
  end

  -- ------- friendship (Gen 2's happiness; Gen 1 has none but Yellow's Pikachu's)

  -- Yellow keeps its partner Pikachu's friendship in the save (save.pikachuHappiness)
  local function yellowPikachu(mon)
    local s = save()
    return gen == 1 and type(mon) == "table" and mon.species == "PIKACHU" and s ~= nil and s.pikachuHappiness ~= nil
  end
  function H.friendshipOf(mon)
    if type(mon) ~= "table" then return 0 end
    if gen == 2 then return tonumber(mon.happiness) or 0 end
    if yellowPikachu(mon) then
      local s = save()
      return tonumber(s and s.pikachuHappiness) or 0
    end
    return 0
  end
  function H.addFriendship(mon, amount)
    local f = math.max(0, math.min(255, H.friendshipOf(mon) + (amount or 0)))
    if gen == 2 and type(mon) == "table" and not mon.isEgg then mon.happiness = f
    elseif yellowPikachu(mon) then
      local s = save()
      if s then s.pikachuHappiness = f end
    end
    return f
  end
  function H.vitaminFriendship(mon)
    local Hp = H.Happiness
    if Hp and Hp.change and Hp.EVENT then pcall(Hp.change, mon, Hp.EVENT.USEDITEM) end
  end

  function H.hasPokerus(mon)
    if gen ~= 2 or type(mon) ~= "table" then return false end
    local P = H.Pokerus
    if P and P.doublesStatExp then
      local ok, v = pcall(P.doublesStatExp, mon)
      if ok then return v == true end
    end
    return (tonumber(mon.pokerus) or 0) ~= 0
  end

  function H.isFainted(mon) return type(mon) == "table" and (tonumber(mon.hp) or 0) <= 0 end
  function H.level(mon) return tonumber(mon and mon.level) or 1 end

  -- ------- items into the player's bag (string ids; "ITEM_FIRE_STONE" is "FIRE_STONE" here)

  local function items()
    local d = data()
    return d and d.items or {}
  end
  -- a regimen's prize the game lacks (Gen 1 has no Hard Stone, Stardust, Sun Stone, PP Max or
  -- Moomoo Milk; Gen 2 no PP Max): the nearest it has, the first it carries
  H.PRIZE_STAND_IN = {
    HARD_STONE = { "ETHER" }, STARDUST = { "NUGGET" }, SUN_STONE = { "MOON_STONE" },
    PP_MAX = { "PP_UP" }, MOOMOO_MILK = { "LEMONADE", "FRESH_WATER" },
  }
  function H.itemId(name)
    if type(name) ~= "string" then return nil end
    local all = items()
    if all[name] then return name end
    local bare = name:gsub("^ITEM_", "")
    if all[bare] then return bare end
    for _, alt in ipairs(H.PRIZE_STAND_IN[bare] or {}) do
      if all[alt] then return alt end
    end
    return nil
  end
  function H.itemName(id)
    local rec = items()[id]
    return (type(rec) == "table" and rec.name) or tostring(id)
  end
  function H.canGiveItem(id, qty)
    local B, s = H.Bag, save()
    if not (B and B.add and B.remove and s and id) then return false end
    local ok, added = pcall(B.add, s, id, qty or 1, data())
    if not (ok and added) then return false end
    pcall(B.remove, s, id, qty or 1, data())
    return true
  end
  function H.giveItem(id, qty)
    local B, s = H.Bag, save()
    if not (B and B.add and s and id) then return false end
    local ok, added = pcall(B.add, s, id, qty or 1, data())
    return ok and added == true
  end
  function H.removeItem(id, qty)
    local B, s = H.Bag, save()
    if not (B and B.remove and s and id) then return false end
    return pcall(B.remove, s, id, qty or 1, data()) == true
  end
  function H.itemIcon() return nil end

  return H
end
