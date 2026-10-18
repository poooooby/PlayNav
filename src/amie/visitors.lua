-- Visitors: while the room is open, Pokemon from the player's Pokedex (seen
-- species plus the party) drop by one at a time, decide whether to stay,
-- and once three have stayed they chat for thirty seconds and leave a gift
-- before departing. The gift set follows their combined affection, raised
-- by the Poke Puff set out; three of a type give that type's set, one
-- evolutionary line gives anything. Rules: Bulbapedia "Pokemon-Amie", Visitors.
--
-- deps = { session = G, Rules, Decor, Store, host }

return function(mod, deps)
  local G, Rules, Decor, Store, host = deps.session, deps.Rules, deps.Decor, deps.Store, deps.host
  local V = { present = {}, group = nil, nextArrival = 6, pool = nil, rng = math.random }

  -- in the game's 320x240 room units (src/amie/decor.lua): the guests take the three seats
  -- around the puff, as kawaii_lower's guestA / B / C_seat do (anchors 5d, 5b, 5c)
  V.SPOTS = { { x = 125, y = 123 }, { x = 160, y = 98 }, { x = 195, y = 123 } }
  V.MID = 160
  V.CHAT_SECS = 30
  V.MAX_PENDING = 6
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
      for _, sp in ipairs(V.FALLBACK) do if not set[sp] then set[sp] = true; list[#list + 1] = sp end end
    end
    V.pool = list
    return list
  end
  V.poolOf = pool

  function V.reset()
    V.present = {}
    V.group = nil
    V.nextArrival = 4 + V.rng() * 4
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
    local avg = averageAffection()
    local aff = Rules.clamp(math.floor(avg + (V.rng() - 0.5) * 200), 0, 255)
    local side = V.rng() < 0.5 and -1 or 1
    local spot = #V.present + 1
    return { species = sp, name = host.speciesName and host.speciesName(sp) or tostring(sp),
      affection = aff, types = host.typesOf and host.typesOf(sp) or {}, root = host.evoRoot and host.evoRoot(sp) or sp,
      icon = host.iconSpecies and host.iconSpecies(sp) or nil,
      x = side < 0 and -25 or 345, y = V.SPOTS[spot].y, tx = V.SPOTS[spot].x, ty = V.SPOTS[spot].y,
      side = side, state = "enter", timer = 0, facing = side < 0 and 1 or -1, frame = 0, frameT = 0 }
  end

  -- the gift set from the group's combined affection and the puff set out
  function V.giftRequest(group, room)
    local total = 0
    local sameRoot, sameType = true, nil
    local typeCount = {}
    for _, v in ipairs(group) do
      total = total + (v.affection or 0)
      if v.root ~= group[1].root then sameRoot = false end
      local seenT = {}
      for _, t in ipairs(v.types or {}) do
        if not seenT[t] then seenT[t] = true; typeCount[t] = (typeCount[t] or 0) + 1 end
      end
    end
    if sameRoot then return { any = true, set = "D" } end
    for t, n in pairs(typeCount) do
      if n == #group then sameType = t end
    end
    if sameType ~= nil then
      local name = host.typeName and host.typeName(sameType)
      if name and Decor.BY_CATEGORY[name] then return { category = name, set = "D" } end
    end
    local idx = 1 + math.floor(total / 766 * 6)
    idx = math.min(6, math.max(1, idx))
    local effect = Decor.puffOutEffect(room)
    local minIdx = Decor.SET_INDEX[effect.minSet or "A"] or 1
    if idx < minIdx then idx = minIdx end
    return { set = Decor.SETS[idx] }
  end

  local function startChat(room)
    local req = V.giftRequest(V.present, room)
    V.group = { t = 0, req = req, bubble = nil, bubbleT = 0 }
    for _, v in ipairs(V.present) do v.state = "chat" end
  end

  local function leaveGift()
    local pending = Store.visitors().gifts
    local names = {}
    for _, v in ipairs(V.present) do names[#names + 1] = v.name end
    local rec = { kind = "visitor", set = V.group.req.set, category = V.group.req.category, any = V.group.req.any,
      from = table.concat(names, ", "), names = names }
    pending[#pending + 1] = rec
    while #pending > V.MAX_PENDING do table.remove(pending, 1) end
    Store.saveVisitors()
    Decor.puffGroupUsed(Store.room())
    Store.saveRoom()
    for _, v in ipairs(V.present) do v.state = "leave"; v.timer = 0 end
    V.group = nil
    V.lastGift = rec
    if G.say then G.say("The visitors left a gift!", 3) end
  end

  -- one chat bubble per visitor, cycling through the set's conversation
  local function nextBubble()
    local req = V.group.req
    local set = req.set or "D"
    local words = V.CONVERSATION[set] or V.CONVERSATION.A
    local who = math.floor(V.rng() * #V.present) + 1
    V.group.bubble = { who = who, word = words[math.floor(V.rng() * #words) + 1], t = 1.4 }
  end

  function V.update(dt)
    local room = Store.room()
    local stayChance = Decor.puffOutEffect(room).stay
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
        if v.timer >= 2 then
          if V.rng() < stayChance then
            v.state = "stay"
            v.facing = v.x < V.MID and 1 or -1
          else
            v.state, v.timer = "leave", 0
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
        -- a leaver still walking out keeps its spot until gone
        local occupied = {}
        for _, v in ipairs(V.present) do occupied[v.tx] = true end
        local free
        for i, sp in ipairs(V.SPOTS) do if not occupied[sp.x] then free = i; break end end
        if free then
          local v = newVisitor()
          v.tx, v.ty, v.y = V.SPOTS[free].x, V.SPOTS[free].y, V.SPOTS[free].y
          V.present[#V.present + 1] = v
        end
        V.nextArrival = 6 + V.rng() * 6
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
    V.nextArrival = 6 + V.rng() * 4
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
