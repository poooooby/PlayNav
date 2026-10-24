-- The items Super Training hands out that Gen 3 never had (data/training_items.lua):
-- registered with the engine's content registry (mod.content.items, indices 400..409) so
-- the bag, marts and the save carry them like any item; the Wings' +1 EV effect runs
-- through the `item.use` hook (vanilla refuses ids it does not know). No hook gives an item
-- its bag icon (and the item record has no icon field), so the bag skins' own icon draw is
-- wrapped, as national_dex_gen3 does (src/item_art.lua there): both read the numeric item
-- id, ours draw from the atlas, any other id falls through to the original.
--
-- The three Gen 4 stones are registered as ST_DUSK_STONE etc. so they never fight another
-- mod over the plain id: national_dex_gen3 registers DUSK_STONE / SHINY_STONE / DAWN_STONE
-- with its own evolutions. For every item of ours, when another mod has registered it by
-- the time a prize is handed out (the plain id, or a Wing by its later name, HEALTH_FEATHER),
-- the prize is that mod's item (its index), not this mod's copy, and its use is that mod's.
--
-- I = items(mod, { host, Rules, data })

return function(mod, deps)
  local host, Rules, data = deps.host, deps.Rules, deps.data or {}
  local N = Rules.N
  local I = { list = data, byIndex = {}, bySlug = {}, installed = false, images = {} }

  for _, def in ipairs(data) do
    def.ownIndex = def.index
    I.byIndex[def.index] = def
    I.bySlug[def.slug] = def
  end

  local function isStone(def) return def.slug:match("%-stone$") ~= nil end
  local function plainId(def) return (def.slug:upper():gsub("%-", "_")) end
  -- the registry id this mod writes ("HEALTH_WING", "ST_DUSK_STONE")
  local function regId(def) return isStone(def) and ("ST_" .. plainId(def)) or plainId(def) end
  I.regId, I.plainId = regId, plainId

  -- the ids another mod might give one of ours: the plain id, and a Wing's later name
  local function otherIds(def)
    local ids = { plainId(def) }
    if def.slug:match("%-wing$") then ids[2] = (plainId(def):gsub("_WING$", "_FEATHER")) end
    return ids
  end
  I.otherIds = otherIds
  -- another mod's copy of one of ours wins; learned when first asked. (A Wing's plain id is
  -- also the one we register: a mod that took it first leaves ours unregistered - the
  -- registry refuses a second record - and its record, with its own index, is found here.)
  local function resolve(def)
    if def and not def.shared then
      local reg = mod.content and mod.content.items
      for _, id in ipairs(reg and otherIds(def) or {}) do
        local ok, existing = pcall(reg.get, reg, id)
        local idx = ok and type(existing) == "table" and tonumber(existing.index) or nil
        if idx and idx ~= def.ownIndex then
          def.shared = true
          def.index = idx
          I.byIndex[idx] = def
          break
        end
      end
    end
    return def
  end

  function I.isTrainingItem(id) return I.byIndex[tonumber(id) or -1] ~= nil end
  function I.def(id) return I.byIndex[tonumber(id) or -1] end

  function I.index(slug)
    local d = resolve(I.bySlug[slug])
    return d and d.index or nil
  end

  -- the icons live in one atlas (assets/items.png, 32x32 cells, five to a row; `iconCell`
  -- in the data); each is cut out into an Image of its own once
  local CELL, COLS = 32, 5
  local atlasData
  local function cellImage(path, cell)
    local G, LI, LF = love and love.graphics, love and love.image, love and love.filesystem
    if not (G and LI and LF and mod.read) then return nil end
    if atlasData == nil then
      local bytes = mod:read(path)
      local ok, data = pcall(function() return LI.newImageData(LF.newFileData(bytes, path)) end)
      atlasData = (bytes and ok and data) or false
    end
    if not atlasData then return nil end
    local ok, img = pcall(function()
      local d = LI.newImageData(CELL, CELL)
      d:paste(atlasData, 0, 0, (cell % COLS) * CELL, math.floor(cell / COLS) * CELL, CELL, CELL)
      local image = G.newImage(d)
      image:setFilter("nearest", "nearest")
      return image
    end)
    return ok and img or nil
  end

  function I.icon(id)
    local def = I.def(id)
    if not def then return nil end
    if I.images[def.ownIndex] ~= nil then return I.images[def.ownIndex] or nil end
    local img = nil
    if def.iconCell then
      img = cellImage(def.icon, def.iconCell)
    elseif mod.assets and mod.assets.image then
      local ok, result = pcall(mod.assets.image, mod.assets, def.icon)
      if ok and result then img = result end
    end
    I.images[def.ownIndex] = img or false
    return img
  end

  -- a Wing used on the party member at `slot`: +1 EV within 252 / 510, vitamin friendship,
  -- one consumed; returns ok, kind, text like the engine's field use
  function I.useWing(def, slot)
    local session = host.session and host.session()
    local mon = session and session.party and session.party[tonumber(slot) or 0]
    if not mon then return false, "noeffect", "It won't have any effect." end
    local evs = host.evsOf(mon)
    local added = Rules.addEv(evs, def.stat, N.ITEMS.WING_EV)
    if added <= 0 then return false, "noeffect", "It won't have any effect." end
    host.setEvs(mon, evs)
    if host.vitaminFriendship then host.vitaminFriendship(mon) end
    host.removeItem(def.ownIndex, 1)
    local name = host.displayName and host.displayName(mon) or "The POKeMON"
    return true, "vitamin", ("%s's %s rose!"):format(name, Rules.STAT_LABEL[def.stat] or def.stat)
  end

  -- give one of the items (by index or slug) to the player; false when the bag is full
  function I.give(id, qty)
    local index
    if type(id) == "string" then
      index = I.index(id)
    else
      local def = I.def(id)
      index = def and resolve(def).index or tonumber(id)
    end
    if not index then return false end
    qty = qty or 1
    if host.canGiveItem and not host.canGiveItem(index, qty) then return false end
    return host.giveItem(index, qty)
  end

  -- the bag's icon for one of ours (by its own index): the 32x32 cell drawn 1:1, centred on
  -- the bag's 24x24 icon (the art is at most 19 across, as Gen 3's own items)
  local function bagIcon(id)
    local def = I.def(id)
    if not (def and tonumber(id) == def.ownIndex) then return nil end
    return I.icon(id)
  end
  local INSET = (CELL - 24) / 2
  local wrapped = setmetatable({}, { __mode = "k" })
  -- FireRed / LeafGreen: drawItemIcon(itemId, px, py, scale); Ruby / Sapphire / Emerald:
  -- drawItemIcon(index, x, y, rotation, ox, oy) (ox / oy in the 24x24 icon's pixels)
  local SKINS = {
    { path = "src.ui.game3.bag_chrome", make = function(orig)
      return function(itemId, px, py, scale)
        local img = bagIcon(itemId)
        if not img then return orig(itemId, px, py, scale) end
        local k = scale or 1
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, (px or 0) - INSET * k, (py or 0) - INSET * k, 0, k, k)
        return true
      end
    end },
    { path = "src.ui.game3.rse.bag_chrome", make = function(orig)
      return function(index, x, y, rotation, ox, oy)
        local img = bagIcon(index)
        if not img then return orig(index, x, y, rotation, ox, oy) end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x or 0, y or 0, rotation or 0, 1, 1, (ox or 0) + INSET, (oy or 0) + INSET)
      end
    end },
  }
  function I.wrapBagIcons()
    local n = 0
    for _, skin in ipairs(SKINS) do
      local ok, BagChrome = pcall(require, skin.path)
      local fn = ok and type(BagChrome) == "table" and BagChrome.drawItemIcon
      if type(fn) == "function" and not wrapped[fn] then
        local mine = skin.make(fn)
        wrapped[mine] = true
        BagChrome.drawItemIcon = mine
        n = n + 1
      elseif type(fn) == "function" then
        n = n + 1
      end
    end
    return n
  end

  function I.install()
    if I.installed then return true end
    if mod.generation ~= 3 then return false, "gen3 only" end
    local reg = mod.content and mod.content.items
    if not reg then return false, "no item registry" end
    local n = 0
    for _, def in ipairs(data) do
      local ok, err = pcall(reg.register, reg, regId(def), {
        id = regId(def), name = def.name, index = def.ownIndex, price = def.price,
        pocket = "ITEMS", fieldUse = def.fieldUse, description = def.description,
      })
      if ok then n = n + 1 else mod.log:warn("item %s not registered: %s", def.slug, tostring(err)) end
    end
    mod.hooks:wrap("item.use", function(next, game, extra, id, partySlot, bag)
      local def = I.def(id)
      -- (only our own copy: another mod's item of the same name keeps its own use)
      if def and def.stat and tonumber(id) == def.ownIndex then
        local ok, kind, text = I.useWing(def, partySlot)
        return ok, kind, text
      end
      return next(game, extra, id, partySlot, bag)
    end)
    I.wrapBagIcons()
    I.installed = n > 0
    mod.log:info("super training: %d items registered", n)
    return I.installed
  end

  return I
end
