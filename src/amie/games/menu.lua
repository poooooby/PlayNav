-- GAMES: the minigame picker. Three badges (Berry Picker, Head It, Tile
-- Puzzle), four difficulty buttons under the chosen one with the best
-- rating in stars, the last result when a game just ended, BACK to play.

return function(mod, Pointer, G, Games, host)

  -- a line that fits its strip: wrapped, and drawn smaller if it still runs over (src/textfit.lua)
  local function fitText(G2, text, x, y, w, h, align)
    local TF = mod.textfit
    local font = G2.getFont()
    if TF and font then return TF.print(G2, font, text, x, y, w, h, align) end
    G2.printf(text, x, y, w, align or "center")
  end
  local app = { id = "games", title = "GAMES", live = false }

  function app:wantsSurface() return G.session ~= nil and G.session.mode == "games" end

  local W, H = 256, 178
  local BADGE = { y = 44, size = 56, gap = 24 }
  local DIFF_ROW = { y = 112, w = 54, h = 18, gap = 6 }
  local BACK = { x = 200, y = 158, w = 50, h = 16 }
  local selected = "berry"

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  local function inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
  end

  local function badgeX(i) return (W - 3 * BADGE.size - 2 * BADGE.gap) / 2 + (i - 1) * (BADGE.size + BADGE.gap) end
  local function diffX(i) return (W - 4 * DIFF_ROW.w - 3 * DIFF_ROW.gap) / 2 + (i - 1) * (DIFF_ROW.w + DIFF_ROW.gap) end

  -- badge art: five looks per game in the misc pack, in game order
  local BADGE_BASE = { berry = 0, head = 5, tile = 10 }
  local function badgeId(game, diff)
    local d = Games.DIFF_INDEX[diff] or 1
    return ("game/badge_%02d"):format((BADGE_BASE[game] or 0) + d - 1)
  end

  function app.geometry()
    return { badgeX = badgeX, diffX = diffX, BADGE = BADGE, DIFF_ROW = DIFF_ROW, BACK = BACK }
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "games") then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    if inRect(x, y, BACK) then G.back(); return end
    for i, game in ipairs(Games.GAMES) do
      local bx = badgeX(i)
      if x >= bx and x <= bx + BADGE.size and y >= BADGE.y and y <= BADGE.y + BADGE.size then
        selected = game
        host.playSe("SE_SELECT")
        return
      end
    end
    for i, diff in ipairs(Games.DIFFS) do
      local r = { x = diffX(i), y = DIFF_ROW.y, w = DIFF_ROW.w, h = DIFF_ROW.h }
      if inRect(x, y, r) then
        if Games.isUnlocked(selected, diff) then
          G.startGame(selected, diff)
        else
          G.say("Earn three stars on the difficulty below first.", 2.5)
        end
        return
      end
    end
  end

  function app:update(dt) end

  local function drawStars(G2, x, y, stars, size)
    Games.drawStars(G2, x, y, stars, size, art)
  end

  function app:draw(G2, w, h)
    local s = G.session
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local bg = art("bg/plain")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local bl = app.bleed or 0
      local sc = math.max(w / bw, (h + bl) / bh)
      G2.draw(bg, (w - bw * sc) / 2, -bl + (h + bl - bh * sc) / 2, 0, sc, sc)
    else
      G2.setColor(0.55, 0.78, 0.98, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    end
    if not s then return end
    G2.setColor(0, 0, 0, 0.35)
    G2.rectangle("fill", 8, 6, w - 16, 20, 6, 6)
    G2.setColor(1, 1, 1, 1)
    if app.smallFont then G2.setFont(app.smallFont) end
    G2.printf(G.text and G.text.get("whichGame") or "MINIGAMES", 8, 10, w - 16, "center")
    if app.font then G2.setFont(app.font) end

    -- the three badges
    for i, game in ipairs(Games.GAMES) do
      local bx = badgeX(i)
      local lit = game == selected
      if lit then
        G2.setColor(1, 1, 1, 0.5)
        G2.rectangle("fill", bx - 4, BADGE.y - 4, BADGE.size + 8, BADGE.size + 8, 8, 8)
      end
      local best = 0
      for _, d in ipairs(Games.DIFFS) do best = math.max(best, Games.best(game, d)) end
      local unlocked = Games.unlocked(game)
      local img = art(badgeId(game, Games.DIFFS[math.max(1, math.min(4, unlocked))]))
      if img then
        G2.setColor(1, 1, 1, 1)
        local iw, ih = img:getDimensions()
        G2.draw(img, bx + BADGE.size / 2, BADGE.y + BADGE.size / 2, 0, BADGE.size / iw, BADGE.size / ih, iw / 2, ih / 2)
      else
        local colors = { berry = { 0.4, 0.75, 0.35 }, head = { 0.4, 0.6, 0.95 }, tile = { 0.9, 0.55, 0.3 } }
        local c = colors[game]
        G2.setColor(c[1], c[2], c[3], 1)
        G2.circle("fill", bx + BADGE.size / 2, BADGE.y + BADGE.size / 2, BADGE.size / 2, 24)
      end
      G2.setColor(0.1, 0.1, 0.15, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(Games.name(game), bx - 12, BADGE.y + BADGE.size + 2, BADGE.size + 24, "center")
      if app.font then G2.setFont(app.font) end
    end

    -- difficulties of the chosen game
    for i, diff in ipairs(Games.DIFFS) do
      local x = diffX(i)
      local open = Games.isUnlocked(selected, diff)
      G2.setColor(open and 0.25 or 0.15, open and 0.45 or 0.15, open and 0.7 or 0.18, open and 1 or 0.7)
      G2.rectangle("fill", x, DIFF_ROW.y, DIFF_ROW.w, DIFF_ROW.h, 5, 5)
      G2.setColor(1, 1, 1, open and 1 or 0.5)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(open and Games.diffLabel(diff):upper() or "LOCKED", x, DIFF_ROW.y + 4, DIFF_ROW.w, "center")
      if app.font then G2.setFont(app.font) end
      drawStars(G2, x + 8, DIFF_ROW.y + DIFF_ROW.h + 8, Games.best(selected, diff), 4)
    end

    -- the last result
    local r = s.lastResult
    if r then
      G2.setColor(0, 0, 0, 0.55)
      G2.rectangle("fill", 8, 142, 150, 32, 6, 6)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(("%s %s: %s"):format(Games.name(r.game), Games.diffLabel(r.diff), r.title), 12, 144, 142, "left")
      drawStars(G2, 20, 165, r.stars, 4)
      G2.printf(("+%d puffs"):format(#r.puffs), 80, 160, 74, "right")
      if app.font then G2.setFont(app.font) end
    elseif s.message then
      G2.setColor(0, 0, 0, 0.6)
      G2.rectangle("fill", 4, 160, 192, 14, 4, 4)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      fitText(G2, s.message, 6, 160, 188, 14, "center")
      if app.font then G2.setFont(app.font) end
    end
    G2.setColor(0.3, 0.3, 0.36, 1)
    G2.rectangle("fill", BACK.x, BACK.y, BACK.w, BACK.h, 6, 6)
    G2.setColor(1, 1, 1, 0.95)
    G2.printf("BACK", BACK.x, BACK.y + BACK.h / 2 - 7, BACK.w, "center")
  end

  function app:releaseAll() end
  app.leave = app.releaseAll
  return app
end
