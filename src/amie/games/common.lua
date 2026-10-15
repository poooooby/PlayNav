-- What the three Pokemon-Amie minigames share: who plays, the difficulty
-- ladder, star ratings, Poke Puff rewards, unlocks and the gifts they owe,
-- and the result bookkeeping. Pure rules apart from the save writes, so the
-- tests build it with fakes.
--
-- deps = { Rules, Store, host, session }

return function(mod, deps)
  local Rules, Store, host, G = deps.Rules, deps.Store, deps.host, deps.session
  local C = {}

  C.GAMES = { "berry", "head", "tile" }
  C.NAMES = { berry = "Berry Picker", head = "Head It", tile = "Tile Puzzle" }
  C.DIFFS = { "easy", "normal", "hard", "unlimited" }
  C.DIFF_LABEL = { easy = "EASY", normal = "NORMAL", hard = "HARD", unlimited = "UNLIMITED" }
  C.DIFF_INDEX = { easy = 1, normal = 2, hard = 3, unlimited = 4 }
  C.STARS = { 0, 1, 2, 3, 4, 4.5, 5 }

  -- minimum score for each star step (0, 1, 2, 3, 4, 4.5, 5); Tile Puzzle's
  -- timed difficulties use seconds and read "at most"
  local BERRY = { 0, 5, 10, 15, 20, 30, 40 }
  C.THRESHOLDS = {
    berry = { easy = BERRY, normal = BERRY, hard = BERRY, unlimited = { 0, 10, 20, 40, 60, 70, 100 } },
    head = {
      easy = { 0, 20, 30, 40, 100, 200, 300 }, normal = { 0, 20, 35, 50, 110, 220, 330 },
      hard = { 0, 30, 50, 70, 130, 240, 350 }, unlimited = { 0, 50, 100, 200, 400, 600, 800 },
    },
    tile = {
      -- seconds: more than the first is 0 stars; then 1, 2, 3, 4, 4.5, 5 stars at most these
      easy = { 60, 50, 40, 30, 20, 15 }, normal = { 120, 90, 60, 50, 40, 30 }, hard = { 180, 120, 100, 80, 70, 50 },
      unlimited = { 0, 2, 3, 6, 9, 13, 17 },  -- puzzles completed
    },
  }

  -- rewards per star step: B basic, Fr frosted, Fa fancy, D deluxe, S the game's seasonal supreme
  local STD = {
    easy = { "1B", "2B", "3B", "4B", "5B", "5B+1Fr", "4B+2Fr" },
    normal = { "1B", "2Fr", "3Fr", "4Fr", "5Fr", "5Fr+1Fa", "4Fr+2Fa" },
    hard = { "1B", "2Fa", "3Fa", "4Fa", "5Fa", "5Fa+1D", "4Fa+2D" },
    unlimited = { "1B", "2D", "3D", "1Fa+4D", "2Fa+4D", "1Fa+5D", "4D+2S" },
  }
  C.REWARDS = {
    berry = STD, head = STD,
    tile = {
      easy = { "2B", "3B", "3B", "3B", "3B", "2B+1Fr", "1B+2Fr" },
      normal = { "1B+2Fr", "3Fr", "1B+3Fr", "4Fr", "4Fr", "3Fr+1Fa", "2Fr+2Fa" },
      hard = { "1B+1Fr+1Fa", "1Fr+2Fa", "3Fa", "3Fa", "4Fa", "3Fa+1D", "3Fa+2D" },
      unlimited = { "1B+1Fr+1Fa", "1Fr+2Fa", "4Fa", "2Fa+2D", "2Fa+4D", "2Fa+5D", "4D+2S" },
    },
  }
  C.SEASONAL = { berry = "puff/supreme_fall", head = "puff/supreme_summer", tile = "puff/supreme_winter" }
  C.SPRING_ODDS = 0.5           -- ours: the wiki names no odds
  local TIER_OF = { B = "basic", Fr = "frosted", Fa = "fancy", D = "deluxe", S = "supreme" }

  C.TITLES = {
    berry = { easy = { "Berry Amateur", "Berry Superstar" }, normal = { "Berry Semipro", "Berry Master" },
      hard = { "Berry Pro", "Berry Grand Master" }, unlimited = { "Berry Elite", "Magnificent Berry Master" } },
    head = { easy = { "Header Amateur", "Header Hyper Master" }, normal = { "Header Semipro", "Eccentric Header Master" },
      hard = { "Header Pro", "Unbelievable Header Master" }, unlimited = { "Header Elite", "Ultimate Header Master" } },
    tile = { easy = { "Puzzle Amateur", "Puzzle Wizard" }, normal = { "Puzzle Semipro", "Puzzle Champion" },
      hard = { "Puzzle Pro", "Puzzle Hotshot" }, unlimited = { "Puzzle Elite", "Puzzle Legend" } },
  }

  -- the game's own words when its text is extracted (G.text, src/amie/text.lua), else ours
  function C.name(game) return (G.text and G.text.gameName(game)) or C.NAMES[game] or tostring(game) end
  function C.diffLabel(diff)
    if G.text and G.text.has(diff) then return G.text.get(diff) end
    return C.DIFF_LABEL[diff] or tostring(diff)
  end
  function C.line(game, key, vars, fallback)
    if G.text then return G.text.game(game, key, vars) end
    return fallback or key
  end
  -- tests swap the text helper in and out
  function C._setText(AT) G.text = AT end

  -- the decor set a gift comes from (resolved by the decor update)
  C.UNLOCK_SET = { normal = "D", hard = "E", unlimited = "F" }
  function C.fiveStarSet(game, diff)
    if diff == "easy" then return "A" end
    if diff == "normal" then return game == "head" and "C" or "B" end
    if diff == "hard" then return "D" end
    return "E"
  end

  -- ------- ratings

  -- the star step index 1..7 for a value
  function C.stepFor(game, diff, value)
    local t = C.THRESHOLDS[game] and C.THRESHOLDS[game][diff]
    if not t then return 1 end
    value = tonumber(value) or 0
    if game == "tile" and diff ~= "unlimited" then
      if value > t[1] then return 1 end
      local step = 2
      for i = 2, #t do
        if value <= t[i] then step = i + 1 end
      end
      return step
    end
    local step = 1
    for i = 1, #t do
      if value >= t[i] then step = i end
    end
    return step
  end

  function C.rate(game, diff, value)
    return C.STARS[C.stepFor(game, diff, value)]
  end

  function C.title(game, diff, stars)
    if G.text then
      local s = G.text.title(game, diff, stars >= 5)
      if s and s ~= "" then return s end
    end
    local t = C.TITLES[game] and C.TITLES[game][diff]
    if not t then return "" end
    return stars >= 5 and t[2] or t[1]
  end

  -- "4Fa+2D" -> { { tier = "fancy", n = 4 }, { tier = "deluxe", n = 2 } }
  function C.parseReward(spec)
    local out = {}
    for part in tostring(spec):gmatch("[^+]+") do
      local n, code = part:match("^(%d+)(%a+)$")
      if n and TIER_OF[code] then out[#out + 1] = { tier = TIER_OF[code], n = tonumber(n) } end
    end
    return out
  end

  local FLAVORS = { "sweet", "mint", "citrus", "mocha", "spice" }

  -- the puff ids a rating earns; flavours are random, the supreme is the game's season
  function C.rewardList(game, diff, stars, rng)
    rng = rng or math.random
    local step = 1
    for i, s in ipairs(C.STARS) do if stars >= s then step = i end end
    local spec = C.REWARDS[game] and C.REWARDS[game][diff] and C.REWARDS[game][diff][step] or "1B"
    local ids = {}
    for _, r in ipairs(C.parseReward(spec)) do
      for _ = 1, r.n do
        if r.tier == "supreme" then
          -- any game's Unlimited can give Supreme Spring; the other seasons are each game's own
          ids[#ids + 1] = (rng() < C.SPRING_ODDS or not C.SEASONAL[game]) and "puff/supreme_spring" or C.SEASONAL[game]
        else
          local flavor = FLAVORS[math.floor(rng() * #FLAVORS) + 1] or "sweet"
          ids[#ids + 1] = "puff/" .. flavor .. "_" .. r.tier
        end
      end
    end
    return ids
  end

  -- ------- who plays

  local function healthy(mon)
    if type(mon) ~= "table" then return false end
    if host.isEgg and host.isEgg(mon) then return false end
    if (mon.hp or 0) <= 0 then return false end
    if host.statusOf and host.statusOf(mon) then return false end
    return true
  end
  C.healthy = healthy

  -- the active Pokemon plus the two healthy party members with the least
  -- enjoyment (party order breaks ties); nil, reason when fewer than three
  function C.participants(activeKey)
    local party = host.party and host.party() or {}
    local active, others = nil, {}
    for i, mon in ipairs(party) do
      if healthy(mon) then
        local key = host.monKey(mon)
        local entry = { mon = mon, key = key, order = i, enjoyment = Store.meters(key).enjoyment or 0 }
        if key == activeKey and not active then active = entry else others[#others + 1] = entry end
      end
    end
    if not active then
      if #others == 0 then return nil, "need three healthy Pokemon" end
      active = table.remove(others, 1)
    end
    table.sort(others, function(a, b)
      if a.enjoyment ~= b.enjoyment then return a.enjoyment < b.enjoyment end
      return a.order < b.order
    end)
    if #others < 2 then return nil, "need three healthy Pokemon" end
    return { active, others[1], others[2] }
  end

  function C.canPlay(activeKey)
    local list, why = C.participants(activeKey)
    return list ~= nil, why
  end

  -- ------- records

  function C.record(game)
    local g = Store.games()
    g[game] = g[game] or { unlocked = 1, best = {} }
    return g[game]
  end

  function C.unlocked(game) return C.record(game).unlocked or 1 end

  function C.isUnlocked(game, diff)
    return (C.DIFF_INDEX[diff] or 99) <= C.unlocked(game)
  end

  function C.best(game, diff)
    return C.record(game).best[diff] or 0
  end

  -- once per save load, opening a minigame cheers the active Pokemon up
  C.openedThisLoad = {}
  function C.noteOpened(key)
    if not key or C.openedThisLoad[key] then return false end
    C.openedThisLoad[key] = true
    Rules.openGame(Store.meters(key))
    Store.saveMons()
    return true
  end

  -- a finished game: rating, puffs, unlocks, gifts, the participants' stats
  -- `value` is the score (berries, points, puzzles) or seconds for a timed Tile Puzzle
  function C.finish(game, diff, value, participants, rng)
    local stars = C.rate(game, diff, value)
    local result = { game = game, diff = diff, value = value, stars = stars,
      title = C.title(game, diff, stars), puffs = C.rewardList(game, diff, stars, rng),
      unlockedNew = nil, fiveStar = stars >= 5, gifts = {} }
    local jar = Store.puffs()
    for _, id in ipairs(result.puffs) do Rules.jarAdd(jar, id) end
    Store.savePuffs()
    local rec = C.record(game)
    if stars > (rec.best[diff] or 0) then rec.best[diff] = stars end
    local idx = C.DIFF_INDEX[diff] or 1
    if stars >= 3 and idx < 4 and (rec.unlocked or 1) <= idx then
      rec.unlocked = idx + 1
      result.unlockedNew = C.DIFFS[idx + 1]
    end
    Store.saveGames()
    local pending = Store.visitors().gifts
    if result.unlockedNew then
      local set = C.UNLOCK_SET[result.unlockedNew]
      pending[#pending + 1] = { kind = "unlock", game = game, diff = result.unlockedNew, set = set }
      result.gifts[#result.gifts + 1] = set
    end
    if stars >= 5 then
      local set = C.fiveStarSet(game, diff)
      pending[#pending + 1] = { kind = "five_star", game = game, diff = diff, set = set }
      result.gifts[#result.gifts + 1] = set
    end
    Store.saveVisitors()
    for _, p in ipairs(participants or {}) do
      local key = p.key or (p.mon and host.monKey(p.mon))
      if key then Rules.gameWin(Store.meters(key), game, diff) end
    end
    Store.saveMons()
    return result
  end

  -- ------- drawing shared by the games (love only when called)

  -- a number in the game's HUD digits ("10" is one glyph; the font stands in without the art)
  function C.drawNumber(G2, art, value, x, y, height, align)
    local s = tostring(math.floor(tonumber(value) or 0))
    local imgs, total = {}, 0
    if art then
      for ch in s:gmatch(".") do
        local img = art("game/digit_" .. ch)
        if not img then imgs = nil; break end
        imgs[#imgs + 1] = img
        total = total + img:getWidth() * (height / img:getHeight()) * 0.78
      end
    else
      imgs = nil
    end
    if not imgs then
      if align == "right" then G2.printf(s, x - 100, y, 100, "right")
      elseif align == "center" then G2.printf(s, x - 50, y, 100, "center")
      else G2.print(s, x, y) end
      return
    end
    local cx = (align == "right") and (x - total) or ((align == "center") and (x - total / 2) or x)
    for _, img in ipairs(imgs) do
      local k = height / img:getHeight()
      G2.draw(img, cx, y, 0, k, k)
      cx = cx + img:getWidth() * k * 0.78
    end
  end

  -- the game's white HUD box, else a dark strip
  function C.drawHudBox(G2, art, x, y, w, h)
    local box = art and art("game/hud_box")
    if box then
      G2.setColor(1, 1, 1, 0.95)
      G2.draw(box, x, y, 0, w / box:getWidth(), h / box:getHeight())
      return true
    end
    G2.setColor(0, 0, 0, 0.5)
    G2.rectangle("fill", x, y, w, h, 4, 4)
    return false
  end

  function C.drawStars(G2, x, y, stars, size, art)
    size = size or 6
    local fullImg = art and art("star/orange")
    local halfImg = art and art("star/orange_small")
    for i = 1, 5 do
      local full = stars >= i
      local half = (not full) and stars >= i - 0.5
      local sx = x + (i - 1) * (size * 2 + 2)
      if fullImg then
        local k = (size * 2.2) / fullImg:getWidth()
        G2.setColor(1, 1, 1, full and 1 or 0.25)
        G2.draw(fullImg, sx, y, 0, k, k, fullImg:getWidth() / 2, fullImg:getHeight() / 2)
        if half and halfImg then
          G2.setColor(1, 1, 1, 1)
          G2.draw(halfImg, sx, y, 0, k, k, halfImg:getWidth() / 2, halfImg:getHeight() / 2)
        end
      else
      local function star(fillHalf)
        if fillHalf then
          G2.polygon("fill", sx, y - size, sx, y + size * 0.55, sx - size * 0.6, y + size,
            sx - size * 0.45, y + size * 0.15, sx - size, y - size * 0.3, sx - size * 0.3, y - size * 0.3)
        else
          G2.polygon("fill", sx, y - size, sx + size * 0.3, y - size * 0.3, sx + size, y - size * 0.3,
            sx + size * 0.45, y + size * 0.15, sx + size * 0.6, y + size, sx, y + size * 0.55,
            sx - size * 0.6, y + size, sx - size * 0.45, y + size * 0.15, sx - size, y - size * 0.3,
            sx - size * 0.3, y - size * 0.3)
        end
      end
      G2.setColor(full and 1 or 0.35, full and 0.85 or 0.35, full and 0.2 or 0.4, 1)
      star(false)
      if half then G2.setColor(1, 0.85, 0.2, 1); star(true) end
      end
    end
  end

  -- the result panel: title, stars, puffs won; a tap leaves the game
  function C.drawResult(G2, w, h, result, app, art, detail)
    G2.setColor(0, 0, 0, 0.55)
    G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    G2.setColor(1, 1, 1, 0.95)
    G2.rectangle("fill", 24, 24, w - 48, h - 48, 8, 8)
    local badge = art and art("game/amie_badge")
    if badge then
      G2.setColor(1, 1, 1, 1)
      G2.draw(badge, 42, 42, 0, 28 / badge:getWidth(), 28 / badge:getHeight(), badge:getWidth() / 2, badge:getHeight() / 2)
    end
    G2.setColor(0.1, 0.1, 0.15, 1)
    G2.printf(result.title or "", 28, 32, w - 56, "center")
    C.drawStars(G2, w / 2 - 34, 62, result.stars or 0, 7, art)
    if app.smallFont then G2.setFont(app.smallFont) end
    local score = detail or (C.name(result.game) .. " " .. C.diffLabel(result.diff) .. ": " .. tostring(result.value))
    local font = app.smallFont or G2.getFont()
    local _, wrapped = font:getWrap(score, w - 56)
    G2.setColor(0.1, 0.1, 0.15, 1)
    G2.printf(score, 28, 76, w - 56, "center")
    local y = 76 + math.max(1, #wrapped) * (font:getHeight() + 1) + 4
    -- the puffs won, each on the ring of its tier
    local puffs = result.puffs or {}
    local n = #puffs
    local x0 = w / 2 - (n - 1) * 12
    for i, id in ipairs(puffs) do
      local px = x0 + (i - 1) * 24
      local ring = art and art("game/ring_" .. (Rules.puffTier(id) or "basic"))
      if ring then
        G2.setColor(1, 1, 1, 1)
        G2.draw(ring, px, y + 11, 0, 24 / ring:getWidth(), 24 / ring:getHeight(), ring:getWidth() / 2, ring:getHeight() / 2)
      end
      local img = art and art(id)
      if img then
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, px, y + 11, 0, 0.5, 0.5, 20, 20)
      else
        G2.setColor(0.95, 0.55, 0.2, 1)
        G2.ellipse("fill", px, y + 11, 8, 6)
      end
    end
    G2.setColor(0.1, 0.1, 0.15, 1)
    if n > 0 then
      local got = C.line(result.game, n == 1 and "puffReceived" or "puffsReceived", nil,
        ("%d Poke Puff%s won"):format(n, n == 1 and "" or "s"))
      G2.printf(got, 28, y + 26, w - 56, "center")
    end
    local bottom = y + 36
    if result.unlockedNew then
      G2.printf(C.line(result.game, "nextRank", nil, (C.DIFF_LABEL[result.unlockedNew] or "") .. " unlocked!"), 28, y + 37, w - 56, "center")
      bottom = y + 48
    end
    if bottom + 10 <= h - 30 then
      G2.setColor(0.3, 0.3, 0.4, 1)
      G2.printf("tap to continue", 28, h - 34, w - 56, "center")
    end
    if app.font then G2.setFont(app.font) end
  end

  return C
end
