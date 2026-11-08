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
-- On the Game Boy games (deps.gb) item ids are strings: each of ours is registered under its
-- own (HEALTH_WING, ST_DUSK_STONE), the index the engine's to give, and the Wings' +1 EV is an
-- item_effects record (Gen 1: use(ctx) -> "consumed" | "failed", messages; Gen 2: the native
-- action record, use(ctx) -> { used, text }). The bags draw no icons there.
--
-- I = items(mod, { host, Rules, data, gb, gen })

return function(mod, deps)
  local host, Rules, data = deps.host, deps.Rules, deps.data or {}
  local gb, gen = deps.gb == true, deps.gen
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
    if gb then return def end
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

  function I.isTrainingItem(id) return I.def(id) ~= nil end
  function I.def(id) return I.byIndex[id] or I.byIndex[tonumber(id) or -1] end

  function I.index(slug)
    local d = resolve(I.bySlug[slug])
    return d and d.index or nil
  end

  -- the icons are painted here, 32x32, on the CPU (an ImageData: safe inside a draw): a Wing is a
  -- feather in its stat's colour, the Pretty Wing a pink one, a stone a cut gem
  local SIZE = 32
  local WING_RGB = {
    hp = { 150, 230, 60 }, atk = { 250, 210, 40 }, def = { 250, 150, 40 },
    spa = { 120, 196, 255 }, spd = { 96, 156, 246 }, spe = { 236, 120, 240 },
  }
  local PRETTY_RGB = { 255, 170, 200 }
  local STONE_RGB = { ["dusk-stone"] = { 110, 70, 170 }, ["shiny-stone"] = { 245, 215, 90 },
    ["dawn-stone"] = { 240, 130, 170 } }

  local function shade(rgb, k) return { math.min(255, rgb[1] * k), math.min(255, rgb[2] * k), math.min(255, rgb[3] * k) } end

  local function featherPixel(x, y, rgb)
    -- the feather lies along the diagonal from the quill (low left) to the tip (high right)
    local ax, ay = (x + 0.5 - 6) / 20, (26 - (y + 0.5)) / 20
    local u = (ax + ay) * 0.7071
    local v = (ax - ay) * 0.7071
    if u < -0.02 or u > 1.12 then return nil end
    local half = (u < 0.12) and 0.012 or 0.21 * math.sin(math.pi * math.min(1, (u - 0.02) / 1.1) ^ 0.85)
    local d = math.abs(v)
    if d > half then return nil end
    if d > half - 0.05 and u > 0.12 then return shade(rgb, 0.55) end
    if d < 0.018 then return shade(rgb, 0.7) end
    local base = v > 0 and 1.0 or 0.86
    local barb = (math.floor((u + d * 0.8) * 22) % 2 == 0) and 0.0 or 0.07
    return shade(rgb, base - barb + (1 - u) * 0.1)
  end

  local function gemPixel(x, y, rgb)
    local dx, dy = (x + 0.5 - 16) / 11, (y + 0.5 - 16.5) / 12.5
    local m = math.abs(dx) + math.abs(dy)
    if m > 1 then return nil end
    if m > 0.86 then return shade(rgb, 0.45) end
    -- facets: upper left lit, lower right in shadow
    local k
    if m < 0.36 then k = 1.12
    elseif dx + dy < -0.2 then k = 1.28
    elseif dx - dy > 0.4 then k = 0.95
    elseif dx + dy > 0.35 then k = 0.66
    else k = 0.82 end
    if dx < -0.18 and dy < -0.18 and m > 0.4 and m < 0.55 then return { 255, 255, 255 } end
    return shade(rgb, k)
  end

  local function paintIcon(def)
    local LI = love and love.image
    if not (LI and love.graphics) then return nil end
    local stone = STONE_RGB[def.slug]
    local rgb = stone or (def.stat and WING_RGB[def.stat]) or PRETTY_RGB
    local data = LI.newImageData(SIZE, SIZE)
    for y = 0, SIZE - 1 do
      for x = 0, SIZE - 1 do
        local c = (stone and gemPixel or featherPixel)(x, y, rgb)
        if c then data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1) end
      end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
  end

  function I.icon(id)
    local def = I.def(id)
    if not def then return nil end
    if I.images[def.ownIndex] ~= nil then return I.images[def.ownIndex] or nil end
    local ok, img = pcall(paintIcon, def)
    I.images[def.ownIndex] = (ok and img) or false
    return ok and img or nil
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
    local A = mod.exports and mod.exports.achievements
    if A then A.note("wing") end
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
  local INSET = (SIZE - 24) / 2
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

  -- a Wing's use on the Game Boy games: +1 EV of its stat (Stat Exp, src/training/host_gb.lua)
  local function wingOn(def, mon)
    if type(mon) ~= "table" or mon.isEgg then return false, "It won't have any effect." end
    local evs = host.evsOf(mon)
    local added = Rules.addEv(evs, def.stat, N.ITEMS.WING_EV)
    if added <= 0 then return false, "It won't have any effect." end
    host.setEvs(mon, evs)
    if host.vitaminFriendship then host.vitaminFriendship(mon) end
    local name = host.displayName and host.displayName(mon) or "The POKeMON"
    local stat = Rules.statOf(def.stat)
    return true, ("%s's\n%s rose."):format(name, Rules.STAT_LABEL[stat] or stat)
  end

  local function installGb()
    local reg = mod.content and mod.content.items
    local effects = mod.content and mod.content.item_effects
    if not reg then return false, "no item registry" end
    local n = 0
    for _, def in ipairs(data) do
      local id = regId(def)
      local effectId = nil
      if def.stat and effects then
        -- Gen 2's PACK finds an effect by the item's own id, as the game's records are keyed
        -- (src/core/gen2/ItemEffects.lua recordFor); under another name it takes only a record
        -- the engine marked as a mod's, which ours did not pass, so a Wing did nothing there
        effectId = gen == 2 and id or ("PLAYNAV_" .. id)
        local rec
        if gen == 2 then
          rec = { action = "mod", field = true, battle = false, use = function(ctx)
            local ok, text = wingOn(def, ctx and ctx.mon)
            return { used = ok, text = text }
          end }
        else
          rec = { needsTarget = true, field = true, battle = false, use = function(ctx)
            local ok, text = wingOn(def, ctx and ctx.target)
            return ok and "consumed" or "failed", { text }
          end }
        end
        local okE, errE = pcall(effects.register, effects, effectId, rec)
        if not okE then mod.log:warn("item effect %s not registered: %s", effectId, tostring(errE)); effectId = nil end
      end
      local ok, err = pcall(reg.register, reg, id, { id = id, name = def.name, price = def.price,
        effect = effectId, needsTarget = def.stat ~= nil or nil })
      if ok then
        n = n + 1
        def.index, def.ownIndex = id, id
        I.byIndex[id] = def
      else
        mod.log:warn("item %s not registered: %s", def.slug, tostring(err))
      end
    end
    I.installed = n > 0
    mod.log:info("super training: %d items registered", n)
    return I.installed
  end

  function I.install()
    if I.installed then return true end
    if gb then return installGb() end
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
