-- Decor rules: the catalogue, who owns what, the room's placed items, the
-- wallpaper, the puff set out for visitors, and how a gift of "set D" turns
-- into an item the player does not have yet. Pure Lua over the save tables;
-- the apps draw, this decides.
--
-- CATALOG rows: { id, name, kind (wall|thumb|cushion|object), category, set, entry, w, h, default }

return function(CATALOG, Rules)
  local D = { CATALOG = CATALOG or {} }

  D.MAX_ITEMS = 30
  D.SETS = { "A", "B", "C", "D", "E", "F" }
  D.SET_INDEX = { A = 1, B = 2, C = 3, D = 4, E = 5, F = 6 }
  -- the puff a visitor group leaves instead of an item, by set
  D.SET_PUFF_TIER = { A = "basic", B = "frosted", C = "fancy", D = "deluxe" }
  -- affection milestones to sets (Bulbapedia: 25 -> B, 50 -> C, 75 and 100 -> D, 150 -> E, 255 -> F)
  D.MILESTONE_SET = { [25] = "B", [50] = "C", [75] = "D", [100] = "D", [150] = "E", [255] = "F" }

  D.BY_ID = {}
  D.ITEMS = {}        -- cushions and objects
  D.WALLS = {}
  D.BY_SET = {}
  D.BY_CATEGORY = {}
  for _, row in ipairs(D.CATALOG) do
    D.BY_ID[row.id] = row
    if row.kind ~= "thumb" then
      D.BY_SET[row.set] = D.BY_SET[row.set] or {}
      table.insert(D.BY_SET[row.set], row)
      D.BY_CATEGORY[row.category] = D.BY_CATEGORY[row.category] or {}
      table.insert(D.BY_CATEGORY[row.category], row)
      if row.kind == "wall" then D.WALLS[#D.WALLS + 1] = row else D.ITEMS[#D.ITEMS + 1] = row end
    end
  end

  -- ids that changed in 0.3.2 when the catalogue took the game's own order (the art behind
  -- each entry is unchanged; two pairs had swapped names and one spelling differed)
  D.RENAMED = {
    ["object/light_bulb_object"] = "object/lightbulb_object",
    ["cushion/red_circle_cushion"] = "cushion/blue_circle_cushion",
    ["cushion/blue_circle_cushion"] = "cushion/red_circle_cushion",
    ["cushion/cast_iron_cushion"] = "cushion/iron_cushion",
    ["cushion/iron_cushion"] = "cushion/cast_iron_cushion",
  }
  D.NAMES_VERSION = 2

  function D.get(id) return D.BY_ID[id] end
  -- the game's own name when the text is extracted (D.textName is set by the session), else ours
  D.textName = nil
  function D.name(id)
    local r = D.BY_ID[id]
    local t = D.textName and D.textName(id)
    if t then return t end
    return r and r.name or tostring(id)
  end
  function D.thumbOf(wallId)
    local r = D.BY_ID[wallId]
    if not r then return nil end
    return "thumb/" .. wallId:gsub("^wall/", "")
  end

  -- ------- ownership

  function D.defaults()
    local out = {}
    for _, row in ipairs(D.CATALOG) do
      if row.default then out[#out + 1] = row.id end
    end
    return out
  end

  -- make sure a decor record has the starting set; owned ids follow a rename once
  function D.ensure(decor)
    decor.owned = decor.owned or {}
    if not decor.seeded then
      for _, id in ipairs(D.defaults()) do decor.owned[id] = true end
      decor.seeded = true
    end
    if (decor.names or 1) < D.NAMES_VERSION then
      local moved = {}
      for id in pairs(decor.owned) do
        local to = D.RENAMED[id]
        if to then moved[to] = true; decor.owned[id] = nil end
      end
      for id in pairs(moved) do decor.owned[id] = true end
      decor.names = D.NAMES_VERSION
    end
    return decor
  end

  function D.owns(decor, id) return decor.owned and decor.owned[id] == true end

  function D.own(decor, id)
    if not D.BY_ID[id] then return false end
    decor.owned = decor.owned or {}
    if decor.owned[id] then return false end
    decor.owned[id] = true
    return true
  end

  -- owned rows of a kind ("wall" | "cushion" | "object"), catalogue order
  function D.owned(decor, kind)
    local out = {}
    for _, row in ipairs(D.CATALOG) do
      if row.kind ~= "thumb" and (kind == nil or row.kind == kind) and decor.owned and decor.owned[row.id] then
        out[#out + 1] = row
      end
    end
    return out
  end

  function D.ownedCount(decor)
    local n = 0
    for _ in pairs(decor.owned or {}) do n = n + 1 end
    return n
  end

  -- ------- the room

  function D.ensureRoom(room, decor)
    room.items = room.items or {}
    if (room.names or 1) < D.NAMES_VERSION then
      for _, it in ipairs(room.items) do it.id = D.RENAMED[it.id] or it.id end
      room.names = D.NAMES_VERSION
    end
    if not room.wallpaper or not (decor and decor.owned and decor.owned[room.wallpaper]) then
      room.wallpaper = "wall/pink"
    end
    return room
  end

  function D.setWallpaper(room, decor, id)
    local r = D.BY_ID[id]
    if not (r and r.kind == "wall") then return false, "not a wallpaper" end
    if decor and not D.owns(decor, id) then return false, "not owned" end
    room.wallpaper = id
    return true
  end

  -- place a copy of an owned item; false, reason when the room is full
  function D.place(room, decor, id, x, y)
    local r = D.BY_ID[id]
    if not (r and (r.kind == "cushion" or r.kind == "object")) then return false, "not an item" end
    if decor and not D.owns(decor, id) then return false, "not owned" end
    room.items = room.items or {}
    if #room.items >= D.MAX_ITEMS then return false, "full" end
    room.items[#room.items + 1] = { id = id, x = x, y = y }
    return true, #room.items
  end

  function D.move(room, index, x, y)
    local it = room.items and room.items[index]
    if not it then return false end
    it.x, it.y = x, y
    return true
  end

  function D.remove(room, index)
    if not (room.items and room.items[index]) then return false end
    table.remove(room.items, index)
    return true
  end

  -- the item under a point, topmost first (later in the list draws on top)
  function D.itemAt(room, x, y, slack)
    slack = slack or 0
    local items = room.items or {}
    for i = #items, 1, -1 do
      local it = items[i]
      local r = D.BY_ID[it.id]
      local w, h = (r and r.w or 40) / 2 + slack, (r and r.h or 40) + slack
      if math.abs(x - it.x) <= w and y <= it.y + slack and y >= it.y - h then return i, it end
    end
    return nil
  end

  -- a cushion the Pokemon may sit on, nearest to (x, y)
  function D.nearestCushion(room, x, y)
    local best, bd
    for _, it in ipairs(room.items or {}) do
      local r = D.BY_ID[it.id]
      if r and r.kind == "cushion" then
        local d = (it.x - x) ^ 2 + (it.y - y) ^ 2
        if not bd or d < bd then best, bd = it, d end
      end
    end
    return best
  end

  -- ------- the puff set out for visitors

  function D.setPuffOut(room, jar, id)
    if id == nil then room.puffOut, room.puffOutGroups = nil, 0; return true end
    if not Rules.jarTake(jar, id) then return false, "none" end
    room.puffOut = id
    local tier = Rules.puffTier(id)
    local groups = ({ basic = 1, frosted = 2, fancy = 3, deluxe = 4 })[tier] or 1
    if tier == "supreme" then
      local p = Rules.PUFF_BY_ID[id]
      groups = (p and p.seasonal) and 5 or 7
    end
    room.puffOutGroups = groups
    return true
  end

  -- a group has been and gone: the puff lasts a number of groups
  function D.puffGroupUsed(room)
    if not room.puffOut then return end
    room.puffOutGroups = (room.puffOutGroups or 1) - 1
    if room.puffOutGroups <= 0 then room.puffOut, room.puffOutGroups = nil, 0 end
  end

  -- how the set-out puff changes visitors: stay chance, minimum gift set
  function D.puffOutEffect(room)
    local id = room.puffOut
    if not id then return { stay = 0.5, minSet = "A" } end
    local tier = Rules.puffTier(id)
    if tier == "basic" then return { stay = 0.65, minSet = "A" } end
    if tier == "frosted" then return { stay = 0.8, minSet = "A" } end
    if tier == "fancy" then return { stay = 0.9, minSet = "A" } end
    if tier == "deluxe" then return { stay = 0.95, minSet = "B" } end
    local p = Rules.PUFF_BY_ID[id]
    if p and p.seasonal then return { stay = 1.0, minSet = "C" } end
    return { stay = 1.0, minSet = "D" }
  end

  -- ------- gifts

  -- an item from a set the player does not own yet; nil when the set is complete
  function D.unownedFrom(rows, decor, rng)
    rng = rng or math.random
    local pool = {}
    for _, r in ipairs(rows or {}) do
      if not D.owns(decor, r.id) then pool[#pool + 1] = r end
    end
    if #pool == 0 then return nil end
    return pool[math.floor(rng() * #pool) + 1]
  end

  -- resolve one gift request into { kind = "item", id } or { kind = "puff", id }
  -- req = { set = "A".."F" } | { category = "Fire" } | { any = true }
  function D.roll(req, decor, rng)
    rng = rng or math.random
    local rows
    if req.any then rows = D.ITEMS
    elseif req.category then rows = D.BY_CATEGORY[req.category]
    else rows = D.BY_SET[req.set or "A"] end
    local item = D.unownedFrom(rows, decor, rng)
    if item then return { kind = "item", id = item.id, name = item.name } end
    -- everything in that set is owned: a puff of the matching tier
    local tier = D.SET_PUFF_TIER[req.set or "A"] or "deluxe"
    local flavors = { "sweet", "mint", "citrus", "mocha", "spice" }
    local id = "puff/" .. flavors[math.floor(rng() * 5) + 1] .. "_" .. tier
    return { kind = "puff", id = id, name = Rules.puffName(id) }
  end

  -- give a resolved gift to the player; returns the text to show
  function D.grant(gift, decor, jar)
    if gift.kind == "item" then
      D.own(decor, gift.id)
      return ("You received the %s!"):format(gift.name or D.name(gift.id))
    end
    Rules.jarAdd(jar, gift.id)
    return ("You received a %s!"):format(gift.name or Rules.puffName(gift.id))
  end

  -- pending records (from milestones, unlocks, five-star runs, visitor groups)
  -- carry a set or category; turn them into concrete gifts
  function D.requestOf(pending)
    if pending.category then return { category = pending.category } end
    if pending.any then return { any = true } end
    if pending.set then return { set = pending.set } end
    if pending.kind == "milestone" then return { set = D.MILESTONE_SET[pending.affection] or "A" } end
    return { set = "A" }
  end

  return D
end
