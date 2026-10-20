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
  -- affection milestones to sets (the game's: 25 -> B, 50 -> C, 75 and 100 -> D, 150 -> E, 255 -> F;
  -- data/amie_rules.lua GIFT_SET)
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

  -- the drawer's categories (Bulbapedia "List of Pokémon-Amie Décor items", the game's order):
  -- the type sets go by type, set A is Color, B Pattern, C Cloud, F Classy
  D.CATEGORY_ORDER = { "Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison",
    "Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy",
    "Color", "Cloud", "Pattern", "Classy" }
  D.CATEGORY_RANK = {}
  for i, c in ipairs(D.CATEGORY_ORDER) do D.CATEGORY_RANK[c] = i end
  local SET_CATEGORY = { A = "Color", B = "Pattern", C = "Cloud", F = "Classy" }
  function D.drawerCategory(row)
    if not row then return nil end
    return SET_CATEGORY[row.set] or row.category
  end

  -- owned cushions and objects as the drawer shows them: { category, rows } in the game's
  -- category order, catalogue order within each, categories with nothing owned left out
  function D.ownedByCategory(decor)
    local by = {}
    for _, row in ipairs(D.CATALOG) do
      if (row.kind == "cushion" or row.kind == "object") and decor.owned and decor.owned[row.id] then
        local c = D.drawerCategory(row)
        by[c] = by[c] or {}
        table.insert(by[c], row)
      end
    end
    local out = {}
    for _, c in ipairs(D.CATEGORY_ORDER) do
      if by[c] then out[#out + 1] = { category = c, rows = by[c] } end
    end
    return out
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

  -- The room is in the game's own units (2026-10-17): its 320x240 lower screen, y down, as
  -- kawaii_lower.bclyt (a/0/2/6) and customize.bclyt (a/1/4/4) lay it out. An item's (x, y)
  -- is the point on the floor it stands on (its art's foot is FOOT below). Saves before then
  -- held the touch screen's 256-wide units under its 14-row title strip: x / 0.8, (y + 14) / 0.8.
  D.UNITS = "lyt"
  D.FOOT = 11   -- measured on the capture: a cushion's 38-row art centred 8 above its seat
  -- the game's placement spots (customize 6z): three cushion seats around the puff's spot
  -- (area_seat 6t / 6v / 6x) and the puff's own (area_okashi ad); kawaii_lower draws the
  -- set-out puff 20 above its spot (okashi_00 1t at 160,96 over 6a at 160,116)
  D.SEATS = { { x = 160, y = 94 }, { x = 195, y = 119 }, { x = 125, y = 119 } }
  D.PUFF_SPOT = { x = 160, y = 116 }
  D.PUFF_LIFT = 20
  -- released this close to a free spot, an item settles exactly on it (the game's "perfect fit")
  D.SNAP = 22
  -- the game's no-go areas while an item is held (customize 6z: area_ng 9x, 120 x 50 about
  -- 160,105 - the middle, all three seats inside it - and 9v, 576 x 20 about y 140), in the
  -- layout's units; an item's point is SEAT_DY above its seat pane's middle (6t 160,103 holds
  -- the item at 160,94). Inside them an item can only settle on a free seat, so each seat holds
  -- one; anywhere else it stands where it is let go.
  D.SEAT_DY = 9
  D.NO_GO = { { x0 = 100, y0 = 80, x1 = 220, y1 = 130 }, { x0 = -128, y0 = 130, x1 = 448, y1 = 150 } }
  function D.inNoGo(x, y)
    local py = y + D.SEAT_DY
    for _, r in ipairs(D.NO_GO) do
      if x >= r.x0 and x <= r.x1 and py >= r.y0 and py <= r.y1 then return true end
    end
    return false
  end
  -- where an item let go at (x, y) can go: a free seat within SNAP, else there unless that is a
  -- no-go area -> x, y, seat index (or nil); nil when it cannot be put down there
  function D.settle(room, x, y, skip)
    local sx, sy, seat = D.snap(room, x, y, skip)
    if seat then return sx, sy, seat end
    if D.inNoGo(x, y) then return nil end
    return x, y, nil
  end

  -- where a 320x240 wallpaper goes on a screen LH layout units tall whose room sits roomDy
  -- lower (the Kanto Gear shape's D / 2): the picture's own point under the puff's spot (its
  -- Poke Ball's middle, as the game draws it 1:1) lands on the spot, at the least scale that
  -- still covers the screen. Returns the scale and the picture's top left. On the 3DS shape:
  -- 1, 0, 0, the game's own placement.
  function D.wallPlace(LH, roomDy)
    local sy = D.PUFF_SPOT.y
    local A = sy + (roomDy or 0)
    local sc = math.max(1, A / sy, ((LH or 240) - A) / (240 - sy))
    return sc, 160 - 160 * sc, A - sy * sc
  end

  function D.migrateRoom(room)
    if room.units == D.UNITS then return false end
    for _, it in ipairs(room.items or {}) do
      it.x, it.y = (it.x or 128) / 0.8, ((it.y or 120) + 14) / 0.8
    end
    room.units = D.UNITS
    return true
  end

  -- the seat an item sits on, if any (index into D.SEATS)
  function D.seatOf(it)
    for i, sp in ipairs(D.SEATS) do
      if it and it.x == sp.x and it.y == sp.y then return i end
    end
    return nil
  end

  -- seats no other item takes (skip: the index of the item being moved)
  function D.freeSeats(room, skip)
    local taken = {}
    for i, it in ipairs(room.items or {}) do
      if i ~= skip then
        local s = D.seatOf(it)
        if s then taken[s] = true end
      end
    end
    local out = {}
    for i, sp in ipairs(D.SEATS) do if not taken[i] then out[#out + 1] = { i = i, x = sp.x, y = sp.y } end end
    return out
  end

  -- where an item released at (x, y) settles: a free seat within D.SNAP, else where it was let go
  function D.snap(room, x, y, skip)
    local best, bd
    for _, sp in ipairs(D.freeSeats(room, skip)) do
      local d = math.sqrt((x - sp.x) ^ 2 + (y - sp.y) ^ 2)
      if d <= D.SNAP and (not bd or d < bd) then best, bd = sp, d end
    end
    if best then return best.x, best.y, best.i end
    return x, y, nil
  end

  -- whether a puff let go at (x, y) lands on its spot
  function D.onPuffSpot(x, y)
    return math.sqrt((x - D.PUFF_SPOT.x) ^ 2 + (y - D.PUFF_SPOT.y) ^ 2) <= D.SNAP
  end

  function D.ensureRoom(room, decor)
    room.items = room.items or {}
    D.migrateRoom(room)
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

  -- how many of an item are still in the drawer: the game keeps one of each, and placing it
  -- takes it out (the drawer shows a placed item at 0, faded)
  function D.inDrawer(room, decor, id)
    if decor and not D.owns(decor, id) then return 0 end
    for _, it in ipairs(room.items or {}) do if it.id == id then return 0 end end
    return 1
  end

  -- place an owned item that is still in the drawer; false, reason when the room is full
  function D.place(room, decor, id, x, y)
    local r = D.BY_ID[id]
    if not (r and (r.kind == "cushion" or r.kind == "object")) then return false, "not an item" end
    if decor and not D.owns(decor, id) then return false, "not owned" end
    room.items = room.items or {}
    if D.inDrawer(room, nil, id) == 0 then return false, "placed" end
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
      local foot = it.y + D.FOOT
      if math.abs(x - it.x) <= w and y <= foot + slack and y >= foot - h then return i, it end
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
    -- how many visitor groups it lasts: the puff table a/2/2/3's b3 (read 2026-10-20: basic 1,
    -- frosted 2, fancy 3, deluxe 4, the seasonal supremes 5, the others 7); a group spends one
    -- as it leaves its gift (puffGroupUsed, visitors.lua)
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

  -- the set-out puff for visitors (the puff table a/2/2/3: b2 the stay odds in percent, the u32 a
  -- bonus to the group's affection when the gift is chosen); none set out: 50, 0
  D.PUFF_OUT = { none = { 50, 0 }, basic = { 70, 0 }, frosted = { 80, 50 }, fancy = { 90, 100 },
    deluxe = { 90, 150 }, seasonal = { 100, 300 }, special = { 100, 500 } }
  -- a Decor item set exactly on a guest seat adds SEAT_BONUS to the stay odds, SEAT_BONUS_MAX at most
  D.SEAT_BONUS, D.SEAT_BONUS_MAX = 10, 30
  local function puffOutRow(room)
    local id = room.puffOut
    if not id then return D.PUFF_OUT.none end
    local tier = Rules.puffTier(id)
    if tier == "supreme" then
      local p = Rules.PUFF_BY_ID[id]
      return (p and p.seasonal) and D.PUFF_OUT.seasonal or D.PUFF_OUT.special
    end
    return D.PUFF_OUT[tier] or D.PUFF_OUT.none
  end

  -- items sitting on the guest seats
  function D.seatedItems(room)
    local n = 0
    for _, it in ipairs(room.items or {}) do
      for _, sp in ipairs(D.SEATS) do
        if math.abs(it.x - sp.x) < 1 and math.abs(it.y - sp.y) < 1 then n = n + 1; break end
      end
    end
    return n
  end

  -- how the set-out puff changes visitors: the stay chance (0..1, with the seat bonus) and the
  -- gift bonus
  function D.puffOutEffect(room)
    local row = puffOutRow(room)
    local bonus = math.min(D.SEAT_BONUS_MAX, D.SEAT_BONUS * D.seatedItems(room))
    return { stay = math.min(100, row[1] + bonus) / 100, giftBonus = row[2] }
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

  -- while the player owns fewer than LOCK_UNTIL Decor, the Poison, Ghost and Dark Decor is
  -- never given (but by a group of that type)
  D.LOCK_UNTIL = 20
  D.LOCKED = { Poison = true, Ghost = true, Dark = true }

  local function pick(list, rng) return list[math.floor(rng() * #list) + 1] end
  local function puffOf(tier, rng)
    local flavors = { "sweet", "mint", "citrus", "mocha", "spice" }
    local id = "puff/" .. pick(flavors, rng) .. "_" .. tier
    return { kind = "puff", id = id, name = Rules.puffName(id) }
  end
  local function wallGift(r) return { kind = "item", id = r.id, name = r.name } end

  -- resolve one gift request (the game's DllField 0x0d70d0 / 0x0694ec) into { kind = "item", id }
  -- or { kind = "puff", id }:
  --   { set = "A".."F" }: a wallpaper of the set not owned (half the time, when there is one),
  --     else any item of the set (it may be one already owned)
  --   { category = "Fire" }: the type's wallpaper half the time when not owned, else one of its items
  --   { any = true }: an item not owned from any set (any item once all are owned)
  --   { puffTier = "deluxe" }: a puff of that tier
  function D.roll(req, decor, rng)
    rng = rng or math.random
    if req.puff then return { kind = "puff", id = req.puff, name = Rules.puffName(req.puff) } end
    if req.puffTier then return puffOf(req.puffTier, rng) end
    local locked = (D.ownedCount(decor) < D.LOCK_UNTIL) and not req.category
    local function allowed(r) return not (locked and D.LOCKED[r.category]) end
    if req.any then
      local item = D.unownedFrom(D.ITEMS, decor, rng) or pick(D.ITEMS, rng)
      return { kind = "item", id = item.id, name = item.name }
    end
    local rows = req.category and D.BY_CATEGORY[req.category] or D.BY_SET[req.set or "A"] or {}
    local walls, items = {}, {}
    for _, r in ipairs(rows) do
      if allowed(r) then
        if r.kind == "wall" then
          if not D.owns(decor, r.id) then walls[#walls + 1] = r end
        elseif r.kind == "cushion" or r.kind == "object" then
          items[#items + 1] = r
        end
      end
    end
    if #walls > 0 and (rng() < 0.5 or #items == 0) then return wallGift(pick(walls, rng)) end
    if #items > 0 then
      local it = pick(items, rng)
      return { kind = "item", id = it.id, name = it.name }
    end
    return puffOf(D.SET_PUFF_TIER[req.set or "A"] or "deluxe", rng)
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
    if pending.puff then return { puff = pending.puff } end
    if pending.puffTier then return { puffTier = pending.puffTier } end
    if pending.category then return { category = pending.category } end
    if pending.any then return { any = true } end
    if pending.set then return { set = pending.set } end
    if pending.kind == "milestone" then return { set = D.MILESTONE_SET[pending.affection] or "A" } end
    return { set = "A" }
  end

  return D
end
