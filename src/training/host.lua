-- Everything Super Training needs from the Gen 3 engine beyond what the Amie host already
-- offers (party, pics, names, cries, sounds): EVs and stats, friendship, Pokerus, the bag,
-- species pictures for Balloon Bots, and its own layer id on the UI stack. Built over the
-- Amie host so a fake can replace both at once in the headless tests.

return function(mod, base)
  local H = setmetatable({}, { __index = base })
  H.base = base
  H.LAYER_ID = "play_nav_training"

  local function req(name)
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then return m end
    return nil
  end

  H.Bag = req("src.core.game3.bag")
  H.ItemsData = req("src.core.game3.items_data")
  H.Constants = req("src.core.game3.constants")

  function H.available()
    return base.available() and H.Pokemon ~= nil and H.Pokemon.evsOf ~= nil and H.Pokemon.applyStats ~= nil
  end

  -- the game's own songs for Super Training: which set this game carries ("frlg" for FireRed /
  -- LeafGreen, "emerald", "rs" for Ruby / Sapphire), and playing one through the game's music
  -- player (faded over, as the game changes map music)
  local FAMILY = { firered = "frlg", leafgreen = "frlg", emerald = "emerald", ruby = "rs", sapphire = "rs" }
  -- the GBA game being played ("ruby", "sapphire", "emerald", "firered", "leafgreen"), or nil
  function H.gameVersion()
    local R = H.Runtime3
    local ok, session = pcall(function() return R and R.getSession() end)
    local v = ok and type(session) == "table" and session.version or nil
    return v and tostring(v):lower() or nil
  end
  function H.songFamily()
    local R = H.Runtime3
    local ok, session = pcall(function() return R and R.getSession() end)
    local v = ok and type(session) == "table" and session.version or nil
    return v and FAMILY[tostring(v):lower()] or nil
  end
  -- a song by name, as a number, when this game has it
  function H.songId(name)
    local A = H.Audio
    if not (A and A.songs) then return nil end
    local ok, id = pcall(function() return A.songs()[name] end)
    return ok and tonumber(id) or nil
  end
  function H.fieldSong()
    local A = H.Audio
    if not (A and A.currentMapMusic) then return nil end
    local ok, id = pcall(A.currentMapMusic)
    return ok and tonumber(id) or nil
  end
  function H.fadeToSong(id, speed)
    local A = H.Audio
    if not (A and id) then return false end
    local fn = A.fadeOutAndPlay or A.playSong
    return pcall(fn, id, speed or 2, speed or 2) == true
  end
  -- the song playing faded to silence (no field song to go back to)
  function H.fadeOutSong(speed)
    local A = H.Audio
    if not (A and A.fadeOutBgm) then return false end
    return pcall(A.fadeOutBgm, speed or 2) == true
  end

  function H.pushLayer(module)
    return pcall(H.Stack.push, H.LAYER_ID, module, { hideBelow = true, fullscreen = true })
  end

  function H.popLayer()
    return pcall(H.Stack.pop, H.LAYER_ID)
  end

  -- the field's music, held while Super Training's own plays (the engine's pause keeps its
  -- place; resume carries on from there)
  function H.overworldMusic(on)
    local A = H.Audio
    if not A then return false end
    local fn = on and A.resumeBgm or A.pauseBgm
    return fn ~= nil and pcall(fn) == true
  end

  -- The game's audio settings, read every frame from the engine's Gen 3 audio (the same state
  -- its own music and effects use), so a change in the options menu applies at once.
  -- Music on: music volume above 0 and the audio mode not EXT. ONLY (the external player in
  -- place of the game's music).
  function H.musicOn()
    local A = H.Audio
    if not A then return true end
    if A._audioMode == "external_only" then return false end
    return (tonumber(A._bgmVolume) or 1) > 0
  end

  -- the music's gain, 0..1: the music volume, held down while a cry or a loud effect plays
  -- (the engine's duck) and halved under the help screen, as the game's own music is
  function H.musicGain()
    local A = H.Audio
    local v = A and tonumber(A._bgmVolume) or 1
    if A then
      v = v * math.min(tonumber(A._duck) or 1, tonumber(A._seDuck) or 1)
      if A._helpActive then v = v * 0.5 end
    end
    return math.max(0, math.min(1, v))
  end

  -- the music filter (options MUSIC FILTER 1-3): the low-pass high gain the engine gives its
  -- own music, or nil when off
  H.MUSIC_FILTER = { 0.4, 0.16, 0.064 }
  function H.musicFilter()
    local A = H.Audio
    local level = A and tonumber(A._filterLevel)
    return level and H.MUSIC_FILTER[level] or nil
  end

  -- the game's SOUND option: true on Mono, when the engine mixes its own music and effects to
  -- one channel; PlayNav's music and effects follow it
  function H.soundMono()
    local A = H.Audio
    return A ~= nil and A._mono == true
  end

  -- the effects volume, 0..1 (for sounds PlayNav plays itself; host.playSe goes through the
  -- engine, which applies it already)
  function H.sfxGain()
    local A = H.Audio
    return math.max(0, math.min(1, A and tonumber(A._sfxVolume) or 1))
  end

  -- the engine has stopped its audio (the window lost focus, the app was suspended)
  function H.audioSuspended()
    local A = H.Audio
    return A ~= nil and A._suspended == true
  end

  function H.layerOpen()
    local ok, has = pcall(H.Stack.has, H.LAYER_ID)
    return ok and has == true
  end

  function H.session()
    local ok, s = pcall(H.Runtime3.getSession)
    return ok and s or nil
  end

  -- ------- EVs and stats

  local KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

  -- a copy of the six EVs (the engine clamps to 0..255 and creates the table)
  function H.evsOf(mon)
    if not mon then return {} end
    local ok, evs = pcall(H.Pokemon.evsOf, mon)
    if not (ok and type(evs) == "table") then evs = type(mon.evs) == "table" and mon.evs or {} end
    local out = {}
    for _, k in ipairs(KEYS) do out[k] = math.max(0, math.floor(tonumber(evs[k]) or 0)) end
    return out
  end

  function H.evTotal(mon)
    local t = 0
    for _, v in pairs(H.evsOf(mon)) do t = t + v end
    return t
  end

  -- writes the six EVs, recalculates the stats and moves the current HP with the max HP
  -- (the engine's own vitamin rule), never fainting a living Pokemon
  function H.setEvs(mon, evs)
    if not (mon and type(evs) == "table") then return false end
    local ok, cur = pcall(H.Pokemon.evsOf, mon)
    if not (ok and type(cur) == "table") then
      cur = type(mon.evs) == "table" and mon.evs or {}
      mon.evs = cur
    end
    for _, k in ipairs(KEYS) do
      cur[k] = math.max(0, math.min(255, math.floor(tonumber(evs[k]) or 0)))
    end
    local oldMax, oldHp = tonumber(mon.maxHp) or 0, tonumber(mon.hp) or 0
    local okA, err = pcall(H.Pokemon.applyStats, mon)
    if not okA then mod.log:warn("applyStats failed: %s", tostring(err)) end
    local newMax = tonumber(mon.maxHp) or oldMax
    if oldHp ~= 0 or oldMax ~= 0 then
      local hp = oldHp + (newMax - oldMax)
      if oldHp > 0 then hp = math.max(1, hp) end
      mon.hp = math.max(0, math.min(newMax, hp))
    end
    return true
  end

  -- { hp, atk, def, spe, spa, spd } base stats of a species, or nil
  function H.baseStats(species)
    if not (H.Pokemon and H.Pokemon.stats) then return nil end
    local ok, s = pcall(H.Pokemon.stats, species)
    if ok and type(s) == "table" then return s end
    return nil
  end

  function H.friendshipOf(mon)
    local ok, f = pcall(H.Pokemon.friendshipOf, mon)
    if ok and tonumber(f) then return tonumber(f) end
    return tonumber(mon and mon.friendship) or 0
  end

  function H.addFriendship(mon, amount)
    local f = math.max(0, math.min(255, H.friendshipOf(mon) + (amount or 0)))
    if H.Pokemon.setFriendship then
      local ok = pcall(H.Pokemon.setFriendship, mon, f)
      if ok then return f end
    end
    if mon then mon.friendship = f end
    return f
  end

  -- vitamins raise friendship by the engine's low/mid/high table; Wings do the same
  function H.vitaminFriendship(mon)
    if H.Pokemon.itemFriendship and H.Pokemon.VITAMIN_FRIENDSHIP_CHANGE then
      pcall(H.Pokemon.itemFriendship, mon, H.Pokemon.VITAMIN_FRIENDSHIP_CHANGE, {})
    end
  end

  function H.hasPokerus(mon)
    return mon ~= nil and (tonumber(mon.pokerus) or 0) ~= 0
  end

  function H.isFainted(mon)
    return mon ~= nil and (tonumber(mon.hp) or 0) <= 0
  end

  function H.level(mon) return tonumber(mon and mon.level) or 1 end

  -- ------- items into the player's bag

  function H.itemName(id)
    if H.ItemsData and H.ItemsData.displayName then
      local ok, n = pcall(H.ItemsData.displayName, id)
      if ok and type(n) == "string" then return n end
    end
    return tostring(id)
  end

  -- a numeric item id for "ITEM_FIRE_STONE" or a number (the constants of the version being
  -- played: Constants.of takes "emerald" / "firered" / ..., not the game object)
  function H.itemId(name)
    if type(name) == "number" then return name end
    if H.Constants and H.Constants.of then
      local v = H.gameVersion()
      if not v and H.Constants.versionOf then
        local okV, got = pcall(H.Constants.versionOf, nil)
        v = okV and got or nil
      end
      local ok, C = pcall(H.Constants.of, v)
      if ok and C and C.id then
        local okI, id = pcall(C.id, C, "items", name)
        if okI and tonumber(id) then return tonumber(id) end
      end
    end
    return nil
  end

  function H.canGiveItem(id, qty)
    local s = H.session()
    if not (s and s.bag and H.Bag and H.Bag.canAdd) then return false end
    local ok, can = pcall(H.Bag.canAdd, s.bag, id, qty or 1)
    return ok and can == true
  end

  function H.giveItem(id, qty)
    local s = H.session()
    if not (s and s.bag and H.Bag and H.Bag.add) then return false end
    local ok, added = pcall(H.Bag.add, s.bag, id, qty or 1)
    return ok and added == true
  end

  -- an engine item's bag icon (24x24) by its numeric id, or nil: FRLG's bag hands out an image
  -- (BagChrome.iconImage); RSE's only draws one (drawItemIcon from its icon strip), so that is
  -- drawn once into a canvas of its own. Cached per id.
  local itemIcons = {}
  function H.itemIcon(id)
    id = tonumber(id)
    if not id then return nil end
    if itemIcons[id] ~= nil then return itemIcons[id] or nil end
    local img = nil
    local frlg = req("src.ui.game3.bag_chrome")
    if frlg and frlg.iconImage then
      local ok, r = pcall(frlg.iconImage, id)
      if ok and r then img = r end
    end
    local G = love and love.graphics
    local rse = not img and req("src.ui.game3.rse.bag_chrome") or nil
    if rse and rse.drawItemIcon and G and G.newCanvas then
      local okC, c = pcall(G.newCanvas, 24, 24, { dpiscale = 1 })
      if okC and c then
        G.push("all")
        G.setCanvas(c)
        G.origin()
        G.clear(0, 0, 0, 0)
        local ok = pcall(rse.drawItemIcon, id, 0, 0)
        G.pop()
        if ok then
          c:setFilter("nearest", "nearest")
          img = c
        end
      end
    end
    itemIcons[id] = img or false
    return img
  end

  function H.removeItem(id, qty)
    local s = H.session()
    if not (s and s.bag and H.Bag and H.Bag.remove) then return false end
    local ok, removed = pcall(H.Bag.remove, s.bag, id, qty or 1)
    return ok and removed ~= false
  end

  -- ------- pictures

  -- (mod.stillPic: the first frame of an animated sprite mod's pic, the game's own as it is)
  local function still(fn, ...)
    local SP = mod and mod.stillPic
    if SP then return SP.get(fn, ...) end
    local ok, entry = pcall(fn, ...)
    if ok and type(entry) == "table" and entry.image then return entry end
    return nil
  end

  -- the front pic of a species (Gen 1-3) for Balloon Bots without ORAS art
  function H.speciesFrontPic(species)
    if not (species and H.Pokemon and H.Pokemon.frontPic) then return nil end
    return still(H.Pokemon.frontPic, species)
  end

  function H.backPic(mon)
    if not (mon and H.Pokemon and H.Pokemon.monBackPic) then return nil end
    return still(H.Pokemon.monBackPic, mon)
  end

  -- a Gen 3 internal species id from a National number, or nil
  function H.speciesFromNational(national)
    if not (national and H.Pokemon and H.Pokemon.speciesFromNational) then return nil end
    local ok, sp = pcall(H.Pokemon.speciesFromNational, national)
    if ok and tonumber(sp) and tonumber(sp) > 0 then return tonumber(sp) end
    return nil
  end

  return H
end
