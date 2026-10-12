-- The mod's save data for Pokemon-Amie (mod.save travels with the normal
-- save file and rewinds with checkpoints). One accessor per record kind;
-- every accessor creates the record on first use and re-sets it on the
-- save so a fresh table is always registered.
--
-- Schema 2:
--   mons[key]  { affection, fullness, enjoyment, puffsEaten, lastCareAt, gifts = { [25] = true } }
--   puffs      { "puff/<id>", ... }   ordered, oldest first, at most 100
--   room       { wallpaper, items = { {id, x, y} }, puffOut, puffOutGroups }
--   decor      { owned = { [id] = true } }
--   games      { berry = { unlocked = 1, best = {} }, head = ..., tile = ... }
--   visitors   { gifts = { {kind, id} } }
--   meta       { steps, activeKey }
-- Schema 1 (play_nav 0.1): mons[key] with beansEaten, and `beans` as counts.

return function(mod, Rules)
  local S = {}

  local function get(key, default)
    local v = mod.save:get(key)
    if type(v) ~= "table" then
      v = default()
      mod.save:set(key, v)
    end
    return v
  end

  function S.migrate()
    local schema = tonumber(mod.save:get("schema")) or 1
    if schema >= 2 then return false end
    local beans = mod.save:get("beans")
    local puffs = Rules.migrateJar(beans)
    if #puffs == 0 and beans == nil then
      for i = 1, Rules.N.PUFF.START do puffs[i] = Rules.PUFFS[(i - 1) % 5 + 1].id end
    end
    mod.save:set("puffs", puffs)
    mod.save:set("beans", nil)
    local mons = mod.save:get("mons")
    if type(mons) == "table" then
      for _, m in pairs(mons) do
        if type(m) == "table" then
          m.puffsEaten = m.puffsEaten or m.beansEaten or 0
          m.beansEaten, m.petAccum, m.petSession = nil, nil, nil
        end
      end
      mod.save:set("mons", mons)
    end
    mod.save:set("schema", 2)
    mod.log:info("amie: save data migrated to schema 2 (%d puffs)", #puffs)
    return true
  end

  function S.mons() return get("mons", function() return {} end) end

  -- the live meters table for a Pokemon key; created at zero
  function S.meters(key)
    local all = S.mons()
    local m = all[key]
    if type(m) ~= "table" then
      m = Rules.newMeters()
      all[key] = m
      mod.save:set("mons", all)
    end
    for k, v in pairs(Rules.newMeters()) do
      if m[k] == nil then m[k] = v end
    end
    return m
  end

  function S.saveMons() mod.save:set("mons", S.mons()) end

  function S.puffs()
    local jar = mod.save:get("puffs")
    if type(jar) ~= "table" then
      S.migrate()
      jar = mod.save:get("puffs")
      if type(jar) ~= "table" then
        jar = {}
        for i = 1, Rules.N.PUFF.START do jar[i] = Rules.PUFFS[(i - 1) % 5 + 1].id end
        mod.save:set("puffs", jar)
      end
    end
    return jar
  end
  function S.savePuffs() mod.save:set("puffs", S.puffs()) end

  function S.room()
    return get("room", function() return { wallpaper = nil, items = {}, puffOut = nil, puffOutGroups = 0 } end)
  end
  function S.saveRoom() mod.save:set("room", S.room()) end

  function S.decor() return get("decor", function() return { owned = {} } end) end
  function S.saveDecor() mod.save:set("decor", S.decor()) end

  function S.games()
    return get("games", function()
      return { berry = { unlocked = 1, best = {} }, head = { unlocked = 1, best = {} }, tile = { unlocked = 1, best = {} } }
    end)
  end
  function S.saveGames() mod.save:set("games", S.games()) end

  function S.visitors() return get("visitors", function() return { gifts = {} } end) end
  function S.saveVisitors() mod.save:set("visitors", S.visitors()) end

  function S.meta() return get("meta", function() return { steps = 0, activeKey = nil } end) end
  function S.saveMeta() mod.save:set("meta", S.meta()) end

  function S.saveAll()
    S.saveMons(); S.savePuffs(); S.saveRoom(); S.saveDecor(); S.saveGames(); S.saveVisitors(); S.saveMeta()
  end

  return S
end
