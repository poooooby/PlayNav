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

  -- (mod.stillPic: the first frame of an animated sprite mod's pic, the game's own as it is)
  local function still(fn, ...)
    local SP = mod and mod.stillPic
    if SP then return SP.get(fn, ...) end
    local ok, entry = pcall(fn, ...)
    if ok and type(entry) == "table" and entry.image then return entry end
    return nil
  end

  function H.frontPic(mon)
    if not (mon and H.Pokemon and H.Pokemon.monFrontPic) then return nil end
    return still(H.Pokemon.monFrontPic, mon, nil, "summary")
  end

  -- gen3-hd-sprites (optional) hands out back pics as a 64x64 stand-in cropped for the battle's
  -- overdraw, tagged with the full frame (`texture`, `quad`, `scale`: texture px x scale = the
  -- pic's px). The whole frame comes back as a 64x64 pic of its own, shrunk to fit when larger
  -- (Zygarde Complete's is 140 across), feet at the bottom, at the stand-in's density.
  local whole = setmetatable({}, { __mode = "k" })
  local function wholeFrame(entry)
    local img = entry and entry.image
    if not img then return entry end
    local hit = whole[img]
    if hit ~= nil then return hit or entry end
    whole[img] = false
    local ok, out = pcall(function()
      local lib = mod and mod.find and mod:find("gen3-hd-sprites")
      local ex = lib and lib.exports
      local tag = type(ex) == "table" and type(ex.tagOf) == "function" and ex.tagOf(img) or nil
      if not (type(tag) == "table" and tag.texture and tag.quad and love and love.graphics) then return nil end
      local _, _, qw, qh = tag.quad:getViewport()
      local scale = tonumber(tag.scale) or 1
      local W, Hh = tonumber(entry.w) or 64, tonumber(entry.h) or 64
      local k = math.min(scale, W / qw, Hh / qh)
      local dpi = img.getDPIScale and img:getDPIScale() or 1
      local c = love.graphics.newCanvas(W, Hh, { dpiscale = dpi })
      c:setFilter("nearest", "nearest")
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(tag.texture, tag.quad, (W - qw * k) / 2, Hh - qh * k, 0, k, k)
      love.graphics.pop()
      local e = {}
      for key, v in pairs(entry) do e[key] = v end
      e.image, e.w, e.h = c, W, Hh
      return e
    end)
    if ok and out then whole[img] = out; return out end
    return entry
  end

  -- the back pic: the Play screen's Pokemon asleep with its back turned (until a tap wakes it)
  function H.backPic(mon)
    if not (mon and H.Pokemon and H.Pokemon.monBackPic) then return nil end
    return wholeFrame(still(H.Pokemon.monBackPic, mon))
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

  -- a species' National Dex number (internal ids differ past Celebi)
  function H.speciesNational(species)
    if not (H.Pokemon and H.Pokemon.national) then return tonumber(species) end
    local ok, n = pcall(H.Pokemon.national, species)
    return ok and tonumber(n) or tonumber(species)
  end

  function H.playerName()
    local ok, session = pcall(H.Runtime3.getSession)
    local n = ok and session and session.name
    return type(n) == "string" and n or nil
  end

  -- the player has entered the Hall of Fame (FLAG_SYS_GAME_CLEAR, Emerald and FireRed)
  function H.gameCleared()
    local ok, v = pcall(function()
      local session = H.Runtime3.getSession()
      local Sem, Flags = req("src.core.game3.field_semantics"), req("src.core.game3.scripting.flags")
      if not (session and Sem and Flags) then return false end
      local id = Sem.flag(session, "FLAG_SYS_GAME_CLEAR")
      if not id then return false end
      local Space = package.loaded["src.core.game3.scripting.space"]
      local store = (Space and Space.active and Space.store) or session
      return Flags.getFlag(store, nil, id) == true
    end)
    return ok and v == true
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
