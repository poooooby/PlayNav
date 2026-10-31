-- Visitors: while the room is open, Pokemon drop by one at a time (the next as soon as no one is
-- walking, as the game), each rolling on arrival whether it stays; once three sit they chat for thirty
-- seconds and leave a gift before departing. Rules from the game's room code (DllField.cro,
-- the gift choice at 0x0d6494): the stay odds come from the Poke Puff set out plus the Decor
-- on the guest seats; the gift by the group: Supreme Honor puffs after the Hall of Fame, a
-- basic puff for the special pairs, any new item for three of one species, set D or a deluxe
-- puff for one evolution line, the type's Decor for three of a type, else by their combined
-- affection plus the puff's bonus. Who visits is ours: the game's visitors are the players
-- passed in the PSS; ours are the species in the player's Pokedex.
--
-- deps = { session = G, Rules, Decor, Store, host }

return function(mod, deps)
  local G, Rules, Decor, Store, host = deps.session, deps.Rules, deps.Decor, deps.Store, deps.host
  local V = { present = {}, group = nil, nextArrival = 20, pool = nil, rng = math.random }

  -- in the game's 320x240 room units (src/amie/decor.lua): the guests take the three seats
  -- around the puff, as kawaii_lower's guestA / B / C_seat do (anchors 5d, 5b, 5c)
  V.SPOTS = { { x = 125, y = 123 }, { x = 160, y = 98 }, { x = 195, y = 123 } }
  V.MID = 160
  V.CHAT_SECS = 30
  V.MAX_PENDING = 5            -- a sixth gift pushes out the oldest (main 0x466800)
  V.LOOK_S = 1.0               -- ours: the pause on arriving before sitting or walking off
  -- waits before the next visitor, seconds rolled between min and max: none, as the game
  -- (DllField.cro 0xd6038: the next comes whenever no one is walking; read 2026-10-20). Visitors
  -- advance only while the room is open - the game tears the room down for PLAY and the
  -- minigames (field::EventLoveCall) and nothing catches up - and a set-out puff is spent one
  -- portion per departing group (0xd74e0 -> 0x466a90).
  V.FIRST_S = { 0, 0 }         -- the room opened: until the first arrives
  V.ARRIVAL_S = { 0, 0 }       -- after one arrives or walks off: until the next
  V.GROUP_S = { 0, 0 }         -- after a group leaves its gift: until anyone comes again
  -- the group's affection (plus the puff's bonus) to a set, or a puff of the tier, half and half
  V.BANDS = { { 150, "A", "basic" }, { 300, "B", "frosted" }, { 450, "C", "fancy" }, { 600, "D", "deluxe" }, { 765, "E" } }
  V.HONOR_GROUPS = 3           -- the Hall of Fame's Supreme Honor puffs, one a group
  V.CONVERSATION = {
    A = { "?", "..." }, B = { "?", "...", "!" }, C = { "...", "!", "note" },
    D = { "!", "!!", "note", "heart" }, E = { "!", "!!", "!!!", "note", "heart" }, F = { "!", "!!", "note", "heart", "heart", "heart" },
  }
  -- a short list for a player who has seen almost nothing yet (Hoenn internal ids)
  V.FALLBACK = { 286, 287, 288, 289, 290, 291, 300, 301, 304, 305 }

  local function pool()
    if V.pool then return V.pool end
    local set, list = {}, {}
    local seen = host.dexSeen and host.dexSeen() or {}
    for _, sp in ipairs(seen) do if not set[sp] then set[sp] = true; list[#list + 1] = sp end end
    for _, mon in ipairs(host.party and host.party() or {}) do
      local sp = host.speciesOf(mon)
      if sp and not set[sp] then set[sp] = true; list[#list + 1] = sp end
    end
    if #list < 4 then
      -- (the Game Boy games' hosts name their own: string species ids)
      local fallback = host.visitorFallback and host.visitorFallback() or V.FALLBACK
      for _, sp in ipairs(fallback) do if not set[sp] then set[sp] = true; list[#list + 1] = sp end end
    end
    V.pool = list
    return list
  end
  V.poolOf = pool

  local function gap(range) return range[1] + V.rng() * (range[2] - range[1]) end
  V.gap = gap

  function V.reset()
    V.present = {}
    V.group = nil
    V.nextArrival = gap(V.FIRST_S)
  end

  -- the player's average affection shapes how affectionate visitors are
  local function averageAffection()
    local n, sum = 0, 0
    for _, m in pairs(Store.mons()) do
      if type(m) == "table" then n = n + 1; sum = sum + (m.affection or 0) end
    end
    if n == 0 then return 0 end
    return sum / n
  end

  local function newVisitor()
    local list = pool()
    local sp = list[math.floor(V.rng() * #list) + 1]
    -- whether it stays is rolled as it arrives
    local stays = V.rng() < Decor.puffOutEffect(Store.room()).stay
    local avg = averageAffection()
    local aff = Rules.clamp(math.floor(avg + (V.rng() - 0.5) * 200), 0, 255)
    local side = V.rng() < 0.5 and -1 or 1
    local spot = #V.present + 1
    return { species = sp, national = host.speciesNational and host.speciesNational(sp) or nil,
      name = host.speciesName and host.speciesName(sp) or tostring(sp),
      affection = aff, types = host.typesOf and host.typesOf(sp) or {}, root = host.evoRoot and host.evoRoot(sp) or sp,
      icon = host.iconSpecies and host.iconSpecies(sp) or nil,
      x = side < 0 and -25 or 345, y = V.SPOTS[spot].y, tx = V.SPOTS[spot].x, ty = V.SPOTS[spot].y,
      side = side, state = "enter", timer = 0, facing = side < 0 and 1 or -1, frame = 0, frameT = 0, stays = stays }
  end

  -- the group's gift (the game's order: the first that applies)
  function V.giftRequest(group, room)
    local meta = Store.meta()
    if (meta.honorLeft or 0) > 0 then
      meta.honorLeft = meta.honorLeft - 1
      Store.saveMeta()
      return { puff = "puff/supreme_honor", set = "F" }
    end
    local has = {}
    for _, v in ipairs(group) do has[v.national or v.species] = true end
    -- Pidgey and Caterpie, or Karrablast and Shelmet: a basic puff (and their own reactions)
    if (has[16] and has[10]) or (has[588] and has[616]) then return { puffTier = "basic", set = "A" } end
    local total = 0
    local sameSpecies, sameRoot, sameType = true, true, nil
    local typeCount = {}
    for _, v in ipairs(group) do
      total = total + (v.affection or 0)
      if v.species ~= group[1].species then sameSpecies = false end
      if v.root ~= group[1].root then sameRoot = false end
      local seenT = {}
      for _, t in ipairs(v.types or {}) do
        if not seenT[t] then seenT[t] = true; typeCount[t] = (typeCount[t] or 0) + 1 end
      end
    end
    if sameSpecies then return { any = true, set = "D" } end
    if sameRoot then
      if V.rng() < 0.7 then return { set = "D" } end
      return { puffTier = "deluxe", set = "D" }
    end
    for t, n in pairs(typeCount) do
      if n == #group then sameType = t end
    end
    if sameType ~= nil then
      local name = host.typeName and host.typeName(sameType)
      if name and Decor.BY_CATEGORY[name] then return { category = name, set = "D" } end
    end
    total = total + (Decor.puffOutEffect(room).giftBonus or 0)
    for _, b in ipairs(V.BANDS) do
      if total < b[1] then
        if b[3] and V.rng() >= 0.5 then return { puffTier = b[3], set = b[2] } end
        return { set = b[2] }
      end
    end
    return { set = "F" }
  end

  local function startChat(room)
    local req = V.giftRequest(V.present, room)
    V.group = { t = 0, req = req, bubble = nil, bubbleT = 0 }
    for _, v in ipairs(V.present) do v.state = "chat" end
  end

  local function se(event) if G and G.se then G.se(event) end end

  local function leaveGift()
    local pending = Store.visitors().gifts
    local names = {}
    for _, v in ipairs(V.present) do names[#names + 1] = v.name end
    local req = V.group.req
    local rec = { kind = "visitor", set = req.set, category = req.category, any = req.any, puff = req.puff,
      puffTier = req.puffTier, from = table.concat(names, ", "), names = names }
    pending[#pending + 1] = rec
    while #pending > V.MAX_PENDING do table.remove(pending, 1) end
    Store.saveVisitors()
    Decor.puffGroupUsed(Store.room())
    Store.saveRoom()
    for _, v in ipairs(V.present) do v.state = "leave"; v.timer = 0 end
    se("visitor_leave")
    V.group = nil
    V.nextArrival = gap(V.GROUP_S)
    V.lastGift = rec
    if G.say then G.say("The visitors left a gift!", 3) end
  end

  -- one chat bubble per visitor, cycling through the set's conversation
  local function nextBubble()
    local req = V.group.req
    local set = req.set or "D"
    local words = V.CONVERSATION[set] or V.CONVERSATION.A
    local who = math.floor(V.rng() * #V.present) + 1
    V.group.bubble = { who = who, word = words[math.floor(V.rng() * #words) + 1], t = 1.4, life = 1.4 }
    se(V.group.bubble.word == "..." and "visitor_think" or "visitor_talk")
  end

  function V.update(dt)
    local room = Store.room()
    for _, v in ipairs(V.present) do
      v.frameT = v.frameT + dt
      if v.frameT >= 0.2 then v.frameT = 0; v.frame = 1 - v.frame end
      if v.state == "enter" then
        local dx = v.tx - v.x
        local step = 50 * dt
        if math.abs(dx) <= step then
          v.x = v.tx
          v.state, v.timer = "decide", 0
        else
          v.x = v.x + (dx > 0 and step or -step)
          v.facing = dx > 0 and 1 or -1
        end
      elseif v.state == "decide" then
        v.timer = v.timer + dt
        if v.timer >= V.LOOK_S then
          if v.stays then
            v.state = "stay"
            v.facing = v.x < V.MID and 1 or -1
          else
            v.state, v.timer = "leave", 0
            se("visitor_leave")
          end
        end
      elseif v.state == "leave" then
        v.timer = v.timer + dt
        local dir = v.side
        v.x = v.x + dir * 56 * dt
        v.facing = dir
      end
    end
    -- those who left are gone
    for i = #V.present, 1, -1 do
      local v = V.present[i]
      if v.state == "leave" and (v.x < -40 or v.x > 360) then table.remove(V.present, i) end
    end
    -- re-seat whoever is staying so the spots fill from the first
    local staying = 0
    for _, v in ipairs(V.present) do if v.state == "stay" or v.state == "chat" then staying = staying + 1 end end
    if V.group then
      V.group.t = V.group.t + dt
      V.group.bubbleT = V.group.bubbleT - dt
      if V.group.bubble then
        V.group.bubble.t = V.group.bubble.t - dt
        if V.group.bubble.t <= 0 then V.group.bubble = nil end
      end
      if V.group.bubbleT <= 0 then nextBubble(); V.group.bubbleT = 1.8 end
      if V.group.t >= V.CHAT_SECS then leaveGift() end
      return
    end
    if staying >= 3 then
      startChat(room)
      return
    end
    -- arrivals, one at a time, only while there is room to stand
    local busy = false
    for _, v in ipairs(V.present) do if v.state == "enter" or v.state == "decide" then busy = true end end
    if not busy and #V.present < 3 then
      V.nextArrival = V.nextArrival - dt
      if V.nextArrival <= 0 then
        -- a leaver still walking out keeps its spot until gone; the seats fill as the game's
        -- do: either side seat at random when both are free, the other side, the middle last
        local occupied = {}
        for _, v in ipairs(V.present) do occupied[v.tx] = true end
        local L, M, R = 1, 2, 3
        local freeL, freeR = not occupied[V.SPOTS[L].x], not occupied[V.SPOTS[R].x]
        local free
        if freeL and freeR then free = (V.rng() < 0.5) and L or R
        elseif freeL then free = L
        elseif freeR then free = R
        elseif not occupied[V.SPOTS[M].x] then free = M end
        if free then
          local v = newVisitor()
          v.tx, v.ty, v.y = V.SPOTS[free].x, V.SPOTS[free].y, V.SPOTS[free].y
          V.present[#V.present + 1] = v
          se("visitor_enter")
        end
        V.nextArrival = gap(V.ARRIVAL_S)
      end
    end
  end

  -- claim a pending gift: it becomes an item or a puff; returns the message
  function V.claim(index)
    local pending = Store.visitors().gifts
    local rec = pending[index]
    if not rec then return nil end
    table.remove(pending, index)
    local decor = Decor.ensure(Store.decor())
    local gift = rec.puff and { kind = "puff", id = rec.puff } or Decor.roll(Decor.requestOf(rec), decor, V.rng)
    local text = Decor.grant(gift, decor, Store.puffs())
    -- the game's own lines: "You got X from A, B, and C!" for a visitor group, "You and
    -- MON are looking close! Found X!" / "You'll be friends forever with MON!" for milestones
    local AT = G.text
    if AT then
      -- the game's variable carries its own article; ours adds one
      local what = gift.name or (gift.kind == "item" and Decor.name(gift.id)) or Rules.puffName(gift.id)
      what = (tostring(what):match("^[AEIOUaeiou]") and "an " or "a ") .. tostring(what)
      if rec.kind == "visitor" and type(rec.names) == "table" and #rec.names >= 3 then
        text = AT.get("visitorGift", { DECOR = what, PLAYER = rec.names })
      elseif rec.kind == "milestone" then
        local who = rec.name or (G.session and G.session.name) or "your Pokemon"
        text = AT.get((rec.affection or 0) >= 255 and "giftForever" or "giftClose", { MON = who, DECOR = what })
      end
    end
    Store.saveDecor(); Store.savePuffs(); Store.saveVisitors()
    local A = mod.exports and mod.exports.achievements
    if A then
      A.note("gift_claimed")
      if gift and gift.kind == "puff" then A.note("puff_owned", gift.id) end
    end
    return text, gift
  end

  function V.pending() return Store.visitors().gifts end

  -- the puff set out changed: whoever is here leaves (the game says so before it lets you)
  function V.sendOff()
    local any = false
    for _, v in ipairs(V.present) do
      if v.state ~= "leave" then v.state, v.timer = "leave", 0; any = true end
    end
    V.group = nil
    V.nextArrival = gap(V.ARRIVAL_S)
    return any
  end

  -- for tests and the driver: bring three visitors in and finish the chat now
  function V.force(species, affections)
    V.present = {}
    for i = 1, 3 do
      local v = newVisitor()
      if species and species[i] then
        v.species = species[i]
        v.types = host.typesOf and host.typesOf(v.species) or {}
        v.root = host.evoRoot and host.evoRoot(v.species) or v.species
        v.name = host.speciesName and host.speciesName(v.species) or tostring(v.species)
      end
      if affections and affections[i] then v.affection = affections[i] end
      v.x, v.tx, v.y = V.SPOTS[i].x, V.SPOTS[i].x, V.SPOTS[i].y
      v.state = "stay"
      V.present[i] = v
    end
    startChat(Store.room())
    local req = V.group.req
    V.group.t = V.CHAT_SECS
    leaveGift()
    return req
  end

  return V
end
