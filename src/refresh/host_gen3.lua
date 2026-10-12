-- Everything Pokemon Refresh needs from the Gen 3 engine, behind one table so
-- the care rules and the surface app never touch engine modules directly
-- and a fake host can drive them headless. Every require is guarded; an
-- engine without a piece reports it through `available()`.

return function(mod)
  local function req(name)
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then return m end
    return nil
  end

  local H = {
    Stack = req("src.ui.game3.stack"),
    Pokemon = req("src.core.game3.pokemon"),
    Audio = req("src.core.game3.audio"),
    Runtime3 = req("src.core.game3.runtime"),
    Summary = req("src.core.game3.summary_data"),
    Font = req("src.ui.game3.frlg_font"),
    Chrome = req("src.ui.game3.chrome"),
    Field = req("src.core.game3.field"),
    name = "gen3",
  }

  function H.available()
    return H.Stack ~= nil and H.Pokemon ~= nil and H.Runtime3 ~= nil
  end

  function H.now()
    if love and love.timer then return love.timer.getTime() end
    return os.clock()
  end

  function H.wallClock() return os.time() end

  function H.party()
    local ok, session = pcall(H.Runtime3.getSession)
    local party = ok and session and session.party
    return type(party) == "table" and party or {}
  end

  function H.monKey(mon)
    if type(mon) ~= "table" then return nil end
    return ("%s:%s"):format(tostring(mon.personality or "?"), tostring(mon.otId or "?"))
  end

  -- the battle hands over its own copy of the mon; act on the party record
  function H.resolve(mon)
    local key = H.monKey(mon)
    if not key then return nil end
    for _, p in ipairs(H.party()) do
      if H.monKey(p) == key then return p end
    end
    return mon
  end

  function H.isEgg(mon)
    local ok, egg = pcall(H.Pokemon.isEgg, mon)
    return ok and egg == true
  end

  function H.speciesOf(mon)
    local ok, id = pcall(H.Pokemon.speciesOf, mon)
    if ok and id then return id end
    return mon and mon.species
  end

  function H.displayName(mon)
    local ok, name = pcall(H.Pokemon.displayName, mon)
    if ok and type(name) == "string" and name ~= "" then return name end
    local okN, n = pcall(H.Pokemon.name, H.speciesOf(mon))
    if okN and type(n) == "string" then return n end
    return "POKEMON"
  end

  function H.frontPic(mon)
    local ok, entry = pcall(H.Pokemon.monFrontPic, mon, nil, "summary")
    if ok and type(entry) == "table" and entry.image then return entry end
    return nil
  end

  function H.icon(mon)
    local ok, entry = pcall(H.Pokemon.monIcon, mon)
    if ok and type(entry) == "table" and entry.image then return entry end
    return nil
  end

  -- National Dex number of a mon (Hoenn species sit at other internal indices)
  function H.national(mon)
    local species = H.speciesOf(mon)
    if H.Pokemon.national then
      local ok, n = pcall(H.Pokemon.national, species)
      if ok and tonumber(n) then return tonumber(n) end
    end
    return tonumber(species)
  end

  function H.playerName()
    local ok, session = pcall(H.Runtime3.getSession)
    local n = ok and session and session.name
    return type(n) == "string" and n or nil
  end

  -- species the Pokedex marks as seen (internal species ids)
  function H.dexSeen()
    local ok, session = pcall(H.Runtime3.getSession)
    local dex = ok and session and session.dex
    local Dex = req("src.core.game3.dex")
    local out = {}
    if not (dex and Dex and Dex.isSeen) then return out end
    for sp = 1, 440 do
      local okS, seen = pcall(Dex.isSeen, dex, sp)
      if okS and seen then out[#out + 1] = sp end
    end
    return out
  end

  function H.speciesName(species)
    local ok, n = pcall(H.Pokemon.name, species)
    if ok and type(n) == "string" then return n end
    return "???"
  end

  function H.iconSpecies(species)
    if not H.Pokemon.icon then return nil end
    local ok, entry = pcall(H.Pokemon.icon, species)
    if ok and type(entry) == "table" and entry.image then return entry end
    return nil
  end

  function H.typeName(id)
    local Types = req("src.core.game3.battle.types")
    if Types and Types.name then
      local ok, n = pcall(Types.name, id)
      if ok and type(n) == "string" then
        n = n:lower()
        return n:sub(1, 1):upper() .. n:sub(2)
      end
    end
    local NAMES = { [0] = "Normal", "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel",
      "Mystery", "Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark" }
    return NAMES[tonumber(id) or -1]
  end

  -- the first species of a Pokemon's evolutionary line (built once from the
  -- forward evolution table)
  local evoParent
  function H.evoRoot(species)
    species = tonumber(species)
    if not species then return nil end
    if not evoParent then
      evoParent = {}
      if H.Pokemon.evolutions then
        for sp = 1, 440 do
          local ok, list = pcall(H.Pokemon.evolutions, sp)
          if ok and type(list) == "table" then
            for _, e in ipairs(list) do
              local target = type(e) == "table" and tonumber(e.species or e.target or e[3] or e.into) or nil
              if target and not evoParent[target] then evoParent[target] = sp end
            end
          end
        end
      end
    end
    local root, guard = species, 0
    while evoParent[root] and guard < 8 do root = evoParent[root]; guard = guard + 1 end
    return root
  end

  function H.typesOf(species)
    if not H.Pokemon.types then return {} end
    local ok, a, b = pcall(H.Pokemon.types, species)
    if not ok then return {} end
    if type(a) == "table" then return a end
    return { a, b }
  end

  local STATUS = { [1] = "PSN", [2] = "PAR", [3] = "SLP", [4] = "FRZ", [5] = "BRN" }

  -- "PSN" | "PAR" | "SLP" | "FRZ" | "BRN" | nil (healthy, fainted or pokerus)
  function H.statusOf(mon)
    if not mon then return nil end
    if H.Summary and H.Summary.statusAilment then
      local ok, code = pcall(H.Summary.statusAilment, mon)
      if ok then return STATUS[code] end
    end
    local s = mon.status
    if type(s) == "string" then
      s = s:upper()
      if s:find("TOX") or s:find("PSN") then return "PSN" end
      if s:find("PAR") or s:find("PRZ") then return "PAR" end
      if s:find("SLP") then return "SLP" end
      if s:find("FRZ") then return "FRZ" end
      if s:find("BRN") then return "BRN" end
    end
    return nil
  end

  -- the engine's own pattern (item_use.lua): clear every status mirror
  function H.cureStatus(mon)
    if not mon then return false end
    mon.status = nil
    mon.sleep = 0
    mon.statusNum = nil
    mon.status1 = nil
    return true
  end

  function H.playCry(mon)
    if not (H.Audio and H.Audio.playCry) then return end
    local species = H.speciesOf(mon)
    if species then pcall(H.Audio.playCry, species) end
  end

  function H.playSe(name)
    if H.Audio and H.Audio.playSe then pcall(H.Audio.playSe, name) end
  end

  H.LAYER_ID = "play_nav_amie"

  function H.pushLayer(module)
    return pcall(H.Stack.push, H.LAYER_ID, module, { hideBelow = true, fullscreen = true })
  end

  function H.popLayer()
    return pcall(H.Stack.pop, H.LAYER_ID)
  end

  function H.layerOpen()
    local ok, has = pcall(H.Stack.has, H.LAYER_ID)
    return ok and has == true
  end

  -- what the battle tells us about how dirty the Pokemon got
  function H.battleFacts(ev)
    local st = ev and ev.battle or {}
    local mon = st.player and st.player.mon
    local maxHp = mon and (mon.maxHp or (mon.stats and mon.stats.hp)) or nil
    local foe = st.enemy and st.enemy.mon
    local foeTypes = foe and H.typesOf(foe.species) or {}
    local names = {}
    for _, t in ipairs(foeTypes) do
      -- Gen 3 hands back GBA type indices; 11 is Water
      if t == H.WATER_TYPE_INDEX then names[#names + 1] = "WATER" else names[#names + 1] = tostring(t) end
    end
    return {
      damaged = mon ~= nil and maxHp ~= nil and (mon.hp or maxHp) < maxHp,
      wild = st.wild == true,
      grass = st.wild == true,
      water = false,
      rain = false,
      foeTypes = names,
      result = ev and ev.result,
    }
  end

  function H.activeMon(ev)
    local st = ev and ev.battle
    local mon = st and st.player and st.player.mon
    if not mon then
      local party = H.party()
      for _, p in ipairs(party) do
        if (p.hp or 0) > 0 and not H.isEgg(p) then return p end
      end
      return party[1]
    end
    return H.resolve(mon)
  end

  function H.leadMon()
    for _, p in ipairs(H.party()) do
      if not H.isEgg(p) then return p end
    end
    return nil
  end

  -- the number 11 keeps a Water-type foe honest when types come back as
  -- GBA indices rather than names
  H.WATER_TYPE_INDEX = 11

  -- true while a Gen 3 battle is running (the care prompt must never open
  -- over a live battle)
  function H.battleActive()
    local B = req("src.core.game3.battle")
    if not (B and B.isActive) then return false end
    local ok, active = pcall(B.isActive)
    return ok and active == true
  end

  return H
end
