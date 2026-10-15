-- PLAY: the bottom-screen half of Pokemon-Amie's close-up. The Pokemon in the middle, a
-- tray along the top (Poke Puffs, the games), petting with per-species favored / disfavored
-- spots and effects, a rapid double-tap "hit", the five-second high-five, puffs eaten bite by
-- bite while held on the Pokemon, and the games picker on this same screen (the GAMES tray
-- button: three badges, the four ranks under the chosen one).
-- Rules: src/amie/rules.lua, spots: src/amie/petting.lua, state: src/amie/session.lua.

return function(mod, Pointer, G, Rules, Petting)

  -- a line that fits its strip: wrapped, and drawn smaller if it still runs over (src/textfit.lua)
  local function fitText(G2, text, x, y, w, h, align)
    local TF = mod.textfit
    local font = G2.getFont()
    if TF and font then return TF.print(G2, font, text, x, y, w, h, align) end
    G2.printf(text, x, y, w, align or "center")
  end

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "play", title = "AMIE", live = true }

  function app:wantsSurface() return G.session ~= nil and G.session.mode ~= "home" end

  local W, H = 256, 178
  local TRAY = { y = 2, h = 32, slot = 36 }
  local TRAY_BOTTOM = TRAY.y + TRAY.h + 2
  local TOOL_LABEL = { beans = "PUFFS", games = "GAMES" }
  local BODY = { cx = 128, cy = 102, rx = 54, ry = 58 }
  local PLAY = { x = 0, y = TRAY_BOTTOM, w = 256, h = 110 }
  local PIC = { cx = 128, bottom = 150, scale = 2 }
  local DONE = { x = 200, y = 158, w = 50, h = 16 }
  -- the games picker over the Pokemon's head: the three badges, their names, the four ranks
  -- with their best stars
  local GAMES = { x = 8, y = 38, w = 240, h = 88, badge = 34, gap = 22, badgeY = 42, diffY = 92, diffW = 50, diffH = 13, diffGap = 5 }
  local gameSel = "berry"
  local function badgeRect(i)
    local x = (W - 3 * GAMES.badge - 2 * GAMES.gap) / 2 + (i - 1) * (GAMES.badge + GAMES.gap)
    return { x = x, y = GAMES.badgeY, w = GAMES.badge, h = GAMES.badge }
  end
  local function diffRect(i)
    local x = (W - 4 * GAMES.diffW - 3 * GAMES.diffGap) / 2 + (i - 1) * (GAMES.diffW + GAMES.diffGap)
    return { x = x, y = GAMES.diffY, w = GAMES.diffW, h = GAMES.diffH }
  end
  -- badge art: five looks per game in the misc pack, in game order
  local BADGE_BASE = { berry = 0, head = 5, tile = 10 }
  local function badgeId(game, diffIndex)
    return ("game/badge_%02d"):format((BADGE_BASE[game] or 0) + (diffIndex or 1) - 1)
  end
  local BEAN_ROW = { x = 40, y = 40, w = 174, h = 22 }
  local PUFF_SLOT = 29
  local PUFF_PER_PAGE = 6
  local ARROW_L = { x = 16, y = 40, w = 22, h = 22 }
  local ARROW_R = { x = 216, y = 40, w = 22, h = 22 }

  local particles = {}
  local drag = nil        -- { kind = <puff id>, x, y, id, feeding }
  local cursor = nil      -- { x, y, kind, down } the Amie hand
  local emote = nil       -- { id, untilT }
  local effectFx = nil    -- { kind, x, y, untilT } burning / paralyzing / ...
  local lastTap = nil     -- { x, y, t } for the hit
  local holdFive = nil    -- { id, startT, x, y } an off-body hold for a high-five
  local dance = nil       -- { cries, t, next }

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local function showEmote(id, secs)
    emote = { id = id, untilT = Pointer.now() + (secs or 1.2) }
  end

  -- the tray: Poke Puffs, and the games when they are built
  local function tools(s)
    local list = { "beans" }
    if G.Games then list[#list + 1] = "games" end
    return list
  end

  local function trayX(list, i) return (W - #list * TRAY.slot) / 2 + (i - 1) * TRAY.slot end

  local function toolAt(s, x, y)
    if y < TRAY.y or y > TRAY.y + TRAY.h then return nil end
    local list = tools(s)
    for i, t in ipairs(list) do
      local tx = trayX(list, i)
      if x >= tx and x < tx + TRAY.slot then return t end
    end
    return nil
  end

  local function inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
  end

  local function puffPages(s)
    local owned = Rules.ownedPuffs(s.puffs)
    local pages = math.max(1, math.ceil(#owned / PUFF_PER_PAGE))
    app.puffPage = math.min(math.max(app.puffPage or 1, 1), pages)
    return owned, pages
  end

  local function puffAt(s, x, y)
    if not inRect(x, y, BEAN_ROW) then return nil end
    local owned = puffPages(s)
    local i = math.floor((x - BEAN_ROW.x) / PUFF_SLOT) + 1
    if i < 1 or i > PUFF_PER_PAGE then return nil end
    return owned[(app.puffPage - 1) * PUFF_PER_PAGE + i]
  end

  local function arrowAt(x, y)
    if inRect(x, y, ARROW_L) then return -1 end
    if inRect(x, y, ARROW_R) then return 1 end
    return nil
  end

  local function toBody(x, y)
    return (x - BODY.cx) / BODY.rx, (y - BODY.cy) / BODY.ry
  end

  local function onBody(x, y, slack)
    local bx, by = toBody(x, y)
    return bx * bx + by * by <= (slack or 1.15) ^ 2
  end

  local function spawn(kind, x, y, n)
    for _ = 1, n or 1 do
      particles[#particles + 1] = {
        kind = kind, x = x + (math.random() - 0.5) * 16, y = y + (math.random() - 0.5) * 8,
        vx = (math.random() - 0.5) * 30, vy = -20 - math.random() * 30,
        life = 0.9 + math.random() * 0.5, age = 0, size = 3 + math.random() * 3,
      }
    end
  end

  -- what the species thinks of the stylus at (x, y) in app space
  local function spotAt(s, x, y)
    local bx, by = toBody(x, y)
    return Petting.spotAt(s.national, bx, by)
  end

  local EFFECT_HAND = { burning = "hand/hot", freezing = "hand/wet", paralyzing = "fx/spark", cutting = "fx/hit" }
  local EFFECT_TEXT = { burning = "Ouch, hot!", freezing = "Brr, freezing!", paralyzing = "Zap!", cutting = "Ow, sharp!" }

  local function hitEffect(s, kind, x, y)
    effectFx = { kind = kind, x = x, y = y, untilT = Pointer.now() + 0.7 }
    showEmote(kind == "burning" and "emote/furious" or "emote/nervous", 0.8)
    G.bump(-0.06, 0)
    if (app.effectSaidAt or 0) + 2 < Pointer.now() then
      app.effectSaidAt = Pointer.now()
      G.say(EFFECT_TEXT[kind] or "!", 1.2)
    end
  end

  -- ------- input

  local function react(hearts, spot, x, y)
    if hearts > 0 then
      spawn("heart", x, y - 10, hearts)
      showEmote(spot == "favored" and "emote/love" or "emote/happy", 1.0)
    elseif spot == "disfavored" then
      spawn("sweat", x, y, 1)
      showEmote("emote/angry", 0.8)
      app.dislikeUntil = Pointer.now() + 0.6
    else
      spawn("note", x, y - 10, 1)
    end
  end

  local function handlePlay(ev, rec, s)
    if ev.phase == "pressed" or ev.phase == "moved" then
      cursor = { x = ev.x, y = ev.y, kind = s.tool or "hand", down = true }
    else
      cursor = cursor and { x = cursor.x, y = cursor.y, kind = cursor.kind, down = false } or nil
    end
    if ev.phase == "pressed" then
      local t = toolAt(s, ev.x, ev.y)
      if t then rec.amieTray = t; return end
      if inRect(ev.x, ev.y, DONE) then rec.amieDone = true; return end
      if s.tool == "games" then
        -- the picker: a badge, a rank, or the panel itself (which the finger does not pet through)
        for i = 1, 3 do
          if inRect(ev.x, ev.y, badgeRect(i)) then rec.amieBadge = i; return end
        end
        for i = 1, 4 do
          if inRect(ev.x, ev.y, diffRect(i)) then rec.amieDiff = i; return end
        end
        if inRect(ev.x, ev.y, GAMES) then return end
      end
      if s.tool == "beans" then
        local dir = arrowAt(ev.x, ev.y)
        if dir then rec.amieArrow = dir; return end
        local p = puffAt(s, ev.x, ev.y)
        if p then
          drag = { kind = p.id, x = ev.x, y = ev.y, id = ev.id }
          return
        end
        if inRect(ev.x, ev.y, BEAN_ROW) then return end
      end
      if ev.y >= PLAY.y and ev.y <= PLAY.y + PLAY.h then
        rec.amieBody = true
        rec.lastBodyX, rec.lastBodyY = ev.x, ev.y
        -- a bare finger resting off the Pokemon may become a high-five
        if s.tool == nil and not onBody(ev.x, ev.y, 1.25) and G.canHighFive() then
          holdFive = { id = ev.id, startT = Pointer.now(), x = ev.x, y = ev.y }
        end
      end
    elseif ev.phase == "moved" then
      if drag and drag.id == ev.id then
        drag.x, drag.y = ev.x, ev.y
        return
      end
      if holdFive and holdFive.id == ev.id then
        local dx, dy = ev.x - holdFive.x, ev.y - holdFive.y
        if dx * dx + dy * dy > 64 or onBody(ev.x, ev.y, 1.25) then holdFive = nil end
      end
      if not rec.amieBody then return end
      local dx, dy = ev.x - (rec.lastBodyX or ev.x), ev.y - (rec.lastBodyY or ev.y)
      rec.lastBodyX, rec.lastBodyY = ev.x, ev.y
      local distPx = math.sqrt(dx * dx + dy * dy)
      if distPx <= 0 then return end
      if s.tool == nil and onBody(ev.x, ev.y, 1.2) then
        local spot, effect = spotAt(s, ev.x, ev.y)
        if spot == "effect" then
          -- an interrupting effect ends the stroke
          rec.amieBody = nil
          hitEffect(s, effect, ev.x, ev.y)
          return
        end
        local hearts, kind, event = G.petStroke(distPx, Pointer.speed(rec), spot)
        if kind == "fast" then
          if (app.fastAt or 0) + 1 < Pointer.now() then
            app.fastAt = Pointer.now()
            spawn("sweat", ev.x, ev.y, 1)
            showEmote("emote/dizzy", 0.6)
          end
        elseif event then
          react(hearts, kind, ev.x, ev.y)
        end
      end
    else -- released / cancelled
      if drag and drag.id == ev.id then
        local d = drag
        drag = nil
        if d.feeding then G.feedDrop(); showEmote("emote/sad", 1.2) end
        return
      end
      holdFive = nil
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) then
        local now = Pointer.now()
        if rec.amieTray and toolAt(s, ev.x, ev.y) == rec.amieTray then
          if rec.amieTray == "games" and s.tool ~= "games" then G.showGames() else G.selectTool(rec.amieTray) end
        elseif rec.amieBadge and inRect(ev.x, ev.y, badgeRect(rec.amieBadge)) then
          gameSel = G.Games.GAMES[rec.amieBadge] or gameSel
          G.click()
        elseif rec.amieDiff and inRect(ev.x, ev.y, diffRect(rec.amieDiff)) then
          local diff = G.Games.DIFFS[rec.amieDiff]
          if diff and G.Games.isUnlocked(gameSel, diff) then
            G.startGame(gameSel, diff)
          else
            G.say("Earn three stars on the rank below first.", 2.5)
          end
        elseif rec.amieArrow and arrowAt(ev.x, ev.y) == rec.amieArrow then
          local _, pages = puffPages(s)
          app.puffPage = math.min(math.max((app.puffPage or 1) + rec.amieArrow, 1), pages)
        elseif rec.amieDone and inRect(ev.x, ev.y, DONE) then
          G.back()
        elseif rec.amieBody and s.tool == nil and onBody(ev.x, ev.y, 1.2) then
          -- two quick taps on the same place is a hit; one tap is a pet
          local N = Rules.N.HIT
          if lastTap and now - lastTap.t <= N.WINDOW_S
              and math.abs(ev.x - lastTap.x) <= N.RADIUS_PX and math.abs(ev.y - lastTap.y) <= N.RADIUS_PX then
            lastTap = nil
            G.hit()
            spawn("sweat", ev.x, ev.y, 2)
            showEmote("emote/angry", 1.0)
          else
            lastTap = { x = ev.x, y = ev.y, t = now }
            local spot, effect = spotAt(s, ev.x, ev.y)
            if spot == "effect" then
              hitEffect(s, effect, ev.x, ev.y)
            else
              local hearts, kind = G.petEvent(spot)
              react(hearts, kind, ev.x, ev.y)
            end
          end
        end
      end
      rec.amieTray, rec.amieDone, rec.amieBody, rec.amieArrow, rec.amieBadge, rec.amieDiff = nil, nil, nil, nil, nil, nil
    end
  end

  function app:pointer(ev, rec, game)
    local s = G.session
    if not s then return end
    return handlePlay(ev, rec, s)
  end

  -- ------- update

  function app:update(dt)
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + dt
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vy = p.vy + ((p.kind == "heart" or p.kind == "note") and -10 or 40) * dt
      if p.age >= p.life then table.remove(particles, i) end
    end
    local s = G.session
    if s and s.mode == "play" then
      -- a puff held on the Pokemon is eaten bite by bite
      if drag then
        local over = onBody(drag.x, drag.y, 1.2)
        if over and not drag.feeding then
          if G.feedStart(drag.kind) then drag.feeding = true
          else drag = nil end
        elseif drag.feeding then
          if over then
            local what, hearts = G.feedHold(dt)
            if what == "bite" then spawn("puff", BODY.cx, BODY.cy - 10, 1)
            elseif what == "done" then
              drag = nil
              spawn("heart", BODY.cx, BODY.cy - 30, hearts or 1)
              showEmote("emote/happy", 1.5)
            end
          else
            G.feedDrop()
            drag = nil
            showEmote("emote/sad", 1.2)
          end
        end
      end
      -- the high-five: a still finger off the Pokemon for five seconds
      if holdFive and Pointer.now() - holdFive.startT >= Rules.N.HIGH_FIVE.HOLD_S then
        local hx, hy = holdFive.x, holdFive.y
        holdFive = nil
        if G.highFive() then spawn("sparkle", hx, hy, 6); showEmote("emote/laugh", 1.5) end
      end
      -- milestones the session reported
      for _, ev in ipairs(G.takeEvents()) do
        if ev.kind == "dance" then
          dance = { cries = ev.cries, t = 0, next = 0 }
          s.sparkle = (s.sparkle or 0) + 20
        elseif ev.kind == "gift" then
          G.say(("%s wants to give you something!"):format(s.name), 3)
          showEmote("emote/love", 2)
        end
      end
      if dance then
        dance.t = dance.t + dt
        if dance.t >= dance.next then
          dance.next = dance.next + 0.6
          dance.cries = dance.cries - 1
          G.bump(0.15, 12)
          spawn("heart", BODY.cx, BODY.cy - 40, 4)
          if dance.cries <= 0 then dance = nil end
        end
      end
      if s.sparkle and s.sparkle > 0 then
        spawn("sparkle", BODY.cx + (math.random() - 0.5) * 100, BODY.cy + (math.random() - 0.5) * 100, 1)
        s.sparkle = s.sparkle - 1
        if s.sparkle == 23 then showEmote("emote/happy", 1.5) end
      end
    end
    if emote and Pointer.now() > emote.untilT then emote = nil end
    if effectFx and Pointer.now() > effectFx.untilT then effectFx = nil end
    app.live = (s ~= nil) and (#particles > 0 or (s.anim and s.anim.timer > 0) or s.eating ~= nil
      or s.mode == "play")
  end

  -- ------- drawing helpers (shapes; the art replaces them when present)

  local function drawTool(G2, tool, x, y, size, lit)
    local a = lit and 1 or 0.55
    if tool == "beans" then
      G2.setColor(0.95, 0.55, 0.2, a); G2.ellipse("fill", x, y, size / 2, size / 3)
      G2.setColor(0.6, 0.3, 0.1, a); G2.ellipse("line", x, y, size / 2, size / 3)
    elseif tool == "games" then
      G2.setColor(0.35, 0.65, 0.95, a); G2.circle("fill", x, y, size / 2, 16)
      G2.setColor(1, 1, 1, a); G2.polygon("fill", x - 3, y - 5, x - 3, y + 5, x + 5, y)
    end
  end

  local function drawParticle(G2, p)
    local f = 1 - p.age / p.life
    if p.kind == "heart" then
      local img = art("fx/heart")
      if img then G2.setColor(1, 1, 1, f); G2.draw(img, p.x, p.y, 0, 1, 1, 8, 8); return end
      G2.setColor(0.95, 0.35, 0.5, f)
      local r = p.size
      G2.circle("fill", p.x - r * 0.5, p.y - r * 0.3, r * 0.55, 10)
      G2.circle("fill", p.x + r * 0.5, p.y - r * 0.3, r * 0.55, 10)
      G2.polygon("fill", p.x - r, p.y - r * 0.1, p.x + r, p.y - r * 0.1, p.x, p.y + r)
    elseif p.kind == "note" then
      local img = art("fx/note")
      if img then G2.setColor(1, 1, 1, f); G2.draw(img, p.x, p.y, 0, 1, 1, 9, 9); return end
      G2.setColor(0.3, 0.3, 0.6, f)
      G2.circle("fill", p.x - 2, p.y + 3, 3, 8)
      G2.rectangle("fill", p.x, p.y - 6, 1.5, 9)
    elseif p.kind == "sparkle" then
      G2.setColor(1, 0.95, 0.5, f)
      local r = p.size
      G2.polygon("fill", p.x, p.y - r, p.x + r * 0.3, p.y, p.x, p.y + r, p.x - r * 0.3, p.y)
      G2.polygon("fill", p.x - r, p.y, p.x, p.y + r * 0.3, p.x + r, p.y, p.x, p.y - r * 0.3)
    elseif p.kind == "steam" then
      G2.setColor(1, 1, 1, f * 0.6)
      G2.circle("fill", p.x, p.y, p.size * (1 + p.age), 10)
    elseif p.kind == "sweat" then
      G2.setColor(0.5, 0.7, 1, f)
      G2.circle("fill", p.x, p.y, 2.5, 8)
    else
      G2.setColor(0.7, 0.65, 0.55, f * 0.8)
      G2.circle("fill", p.x, p.y, p.size * 0.6, 8)
    end
  end

  local function drawButton(G2, r, label, color)
    G2.setColor(color[1], color[2], color[3], 1)
    G2.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
    G2.setColor(1, 1, 1, 0.95)
    G2.printf(label, r.x, r.y + r.h / 2 - 7, r.w, "center")
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
      G2.setColor(0.98, 0.86, 0.45, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(1, 0.95, 0.7, 0.5)
      for i = 1, 4 do G2.circle("line", BODY.cx, BODY.cy + 20, 30 + i * 22, 40) end
      G2.setColor(0.9, 0.72, 0.3, 0.8)
      G2.ellipse("fill", BODY.cx, PIC.bottom + 2, 56, 10)
    end

    if not s then
      G2.setColor(0.2, 0.15, 0.05, 1)
      G2.printf("POKEMON-AMIE", 8, h / 2 - 28, w - 16, "center")
      G2.printf("Opens after a battle, or from the START menu.", 8, h / 2 - 8, w - 16, "center")
      return
    end

    local pic = s.pic
    local sx = 1 + (s.anim.squash or 0)
    local sy = 1 - (s.anim.squash or 0)
    local bounce = s.anim.bounce or 0
    if pic and pic.image then
      G2.setColor(1, 1, 1, 1)
      drawPixel(pic.image, PIC.cx, PIC.bottom - bounce, 0, PIC.scale * sx, PIC.scale * sy,
        (pic.w or 64) / 2, (pic.h or 64))
    else
      G2.setColor(0.9, 0.75, 0.3, 1)
      G2.circle("fill", BODY.cx, BODY.cy - bounce, 40 * sx, 32)
    end

    -- tray
    local list = tools(s)
    G2.setColor(0, 0, 0, 0.25)
    G2.rectangle("fill", trayX(list, 1) - 4, TRAY.y, #list * TRAY.slot + 8, TRAY.h, 6, 6)
    for i, t in ipairs(list) do
      local x = trayX(list, i)
      local usable = true
      if t == "beans" then usable = Rules.jarTotal(s.puffs) > 0 and Rules.canEat(s.national) end
      if s.tool == t then
        G2.setColor(1, 1, 1, 0.9)
        G2.rectangle("fill", x + 2, TRAY.y + 2, TRAY.slot - 4, TRAY.h - 4, 5, 5)
      end
      local puffIcon = (t == "beans" and art("puff/sweet_basic")) or (t == "games" and art("ui/badge_music"))
      if t == "games" then
        local okPlay = G.Games and G.Games.canPlay(s.key)
        usable = okPlay and true or false
      end
      if puffIcon then
        G2.setColor(1, 1, 1, usable and 1 or 0.45)
        G2.draw(puffIcon, x + TRAY.slot / 2, TRAY.y + 13, 0, 0.5, 0.5, 20, 20)
      else
        drawTool(G2, t, x + TRAY.slot / 2, TRAY.y + 13, 16, usable)
      end
      G2.setColor(0.1, 0.1, 0.1, usable and 0.9 or 0.4)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(TOOL_LABEL[t], x, TRAY.y + TRAY.h - 11, TRAY.slot, "center")
      if app.font then G2.setFont(app.font) end
    end

    -- the puff row
    if s.tool == "beans" then
      local owned, pages = puffPages(s)
      G2.setColor(1, 1, 1, 0.75)
      G2.rectangle("fill", BEAN_ROW.x, BEAN_ROW.y, BEAN_ROW.w, BEAN_ROW.h, 6, 6)
      if app.smallFont then G2.setFont(app.smallFont) end
      local first = (app.puffPage - 1) * PUFF_PER_PAGE
      for i = 1, PUFF_PER_PAGE do
        local p = owned[first + i]
        if not p then break end
        local px = BEAN_ROW.x + (i - 1) * PUFF_SLOT
        local puff = art(p.id)
        if puff then
          G2.setColor(1, 1, 1, 1)
          G2.draw(puff, px + 11, BEAN_ROW.y + 11, 0, 0.5, 0.5, 20, 20)
        else
          drawTool(G2, "beans", px + 11, BEAN_ROW.y + 11, 12, true)
        end
        G2.setColor(0.1, 0.1, 0.1, 1)
        G2.printf(tostring(p.count), px + 18, BEAN_ROW.y + 12, 12, "left")
      end
      if #owned == 0 then
        G2.setColor(0.1, 0.1, 0.1, 0.8)
        G2.printf("No Poke Puffs", BEAN_ROW.x, BEAN_ROW.y + 7, BEAN_ROW.w, "center")
      end
      if pages > 1 then
        local function arrow(r, dir, lit)
          local img = art(dir < 0 and "ui/arrow_left" or "ui/arrow_right")
          G2.setColor(1, 1, 1, lit and 1 or 0.35)
          if img then
            G2.draw(img, r.x + r.w / 2, r.y + r.h / 2, 0, 0.5, 0.5, 21, 21)
          else
            local cx, cy = r.x + r.w / 2, r.y + r.h / 2
            G2.circle("fill", cx, cy, 9)
            G2.setColor(0.1, 0.1, 0.1, lit and 1 or 0.5)
            G2.polygon("fill", cx + dir * 4, cy, cx - dir * 2, cy - 5, cx - dir * 2, cy + 5)
          end
        end
        arrow(ARROW_L, -1, app.puffPage > 1)
        arrow(ARROW_R, 1, app.puffPage < pages)
        G2.setColor(0.1, 0.1, 0.1, 0.8)
        G2.printf(("%d/%d"):format(app.puffPage, pages), BEAN_ROW.x, BEAN_ROW.y + BEAN_ROW.h + 1, BEAN_ROW.w, "right")
      end
      if app.font then G2.setFont(app.font) end
    end

    -- the games picker
    if s.tool == "games" and G.Games then
      local Games = G.Games
      G2.setColor(0, 0, 0, 0.45)
      G2.rectangle("fill", GAMES.x, GAMES.y, GAMES.w, GAMES.h, 6, 6)
      for i, game in ipairs(Games.GAMES) do
        local r = badgeRect(i)
        if game == gameSel then
          G2.setColor(1, 1, 1, 0.5)
          G2.rectangle("fill", r.x - 3, r.y - 3, r.w + 6, r.h + 6, 6, 6)
        end
        local unlocked = math.max(1, math.min(4, Games.unlocked(game)))
        local img = art(badgeId(game, unlocked))
        if img then
          G2.setColor(1, 1, 1, 1)
          local iw, ih = img:getDimensions()
          G2.draw(img, r.x + r.w / 2, r.y + r.h / 2, 0, r.w / iw, r.h / ih, iw / 2, ih / 2)
        else
          local colors = { berry = { 0.4, 0.75, 0.35 }, head = { 0.4, 0.6, 0.95 }, tile = { 0.9, 0.55, 0.3 } }
          local c = colors[game] or { 0.5, 0.5, 0.5 }
          G2.setColor(c[1], c[2], c[3], 1)
          G2.circle("fill", r.x + r.w / 2, r.y + r.h / 2, r.w / 2, 24)
        end
        G2.setColor(1, 1, 1, 1)
        if app.smallFont then G2.setFont(app.smallFont) end
        G2.printf(Games.name(game), r.x - 14, r.y + r.h + 1, r.w + 28, "center")
      end
      for i, diff in ipairs(Games.DIFFS) do
        local r = diffRect(i)
        local open = Games.isUnlocked(gameSel, diff)
        G2.setColor(open and 0.25 or 0.15, open and 0.45 or 0.15, open and 0.7 or 0.18, open and 1 or 0.7)
        G2.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
        G2.setColor(1, 1, 1, open and 1 or 0.5)
        G2.printf(open and Games.diffLabel(diff):upper() or "LOCKED", r.x, r.y + 2, r.w, "center")
        Games.drawStars(G2, r.x + 7, r.y + r.h + 8, Games.best(gameSel, diff), 3, art)
      end
      if app.font then G2.setFont(app.font) end
    end

    -- emote bubble beside the head
    if emote then
      local img = art(emote.id)
      if img then
        G2.setColor(1, 1, 1, 1)
        local ey = (s.tool == "beans" or s.tool == "games") and BODY.cy - 24 or BODY.cy - 66
        -- the bubble's tail points down-right: it sits above-left of the Pokemon
        G2.draw(img, BODY.cx - 48, ey, 0, 0.8, 0.8, 25, 25)
      end
    end

    for _, p in ipairs(particles) do drawParticle(G2, p) end

    -- the dragged puff shrinks as it is eaten
    if drag then
      local puff = art(drag.kind)
      local f = s.feeding
      local k = 0.6
      if f and f.bites > 0 then k = 0.6 * (1 - 0.7 * f.taken / f.bites) end
      if puff then G2.setColor(1, 1, 1, 1); G2.draw(puff, drag.x, drag.y, 0, k, k, 20, 20)
      else drawTool(G2, "beans", drag.x, drag.y, 14 * k / 0.6, true) end
    end

    -- the cursor: the Amie hand for a bare finger (crossed right after a disliked rub, open
    -- while a high-five is building); the effect hand over a hot / shocking spot
    if effectFx then
      local img = art(EFFECT_HAND[effectFx.kind] or "fx/hit")
      if img then
        G2.setColor(1, 1, 1, 1)
        local iw, ih = img:getDimensions()
        G2.draw(img, effectFx.x, effectFx.y, 0, 1, 1, iw / 2, ih / 2)
      else
        G2.setColor(1, 0.6, 0.2, 0.9)
        G2.circle("line", effectFx.x, effectFx.y, 10)
      end
    elseif cursor and cursor.down and s.tool == nil then
      local annoyed = app.dislikeUntil and Pointer.now() < app.dislikeUntil
      local id = annoyed and "hand/dislike" or (holdFive and "hand/flat" or "hand/pet")
      local hand = art(id)
      if hand then
        G2.setColor(1, 1, 1, 1)
        G2.draw(hand, cursor.x, cursor.y, 0, 1, 1, 16, 16)
      end
      if holdFive then
        local f = math.min(1, (Pointer.now() - holdFive.startT) / Rules.N.HIGH_FIVE.HOLD_S)
        G2.setColor(1, 1, 1, 0.8)
        G2.arc("line", "open", cursor.x, cursor.y, 14, -math.pi / 2, -math.pi / 2 + f * 2 * math.pi, 20)
      end
    end

    local lv = Rules.level(s.meters.affection)
    local heartImg = art("ui/icon_heart")
    for i = 1, 5 do
      local hx, hy, r = 10 + (i - 1) * 12, 152, 4
      if heartImg then
        G2.setColor(1, 1, 1, i <= lv and 1 or 0.3)
        G2.draw(heartImg, hx, hy, 0, 10 / heartImg:getWidth(), 10 / heartImg:getHeight(), heartImg:getWidth() / 2, heartImg:getHeight() / 2)
      else
        G2.setColor(i <= lv and 0.95 or 0.6, i <= lv and 0.35 or 0.6, i <= lv and 0.5 or 0.65, 1)
        G2.circle("fill", hx - r * 0.5, hy - r * 0.3, r * 0.55, 10)
        G2.circle("fill", hx + r * 0.5, hy - r * 0.3, r * 0.55, 10)
        G2.polygon("fill", hx - r, hy - r * 0.1, hx + r, hy - r * 0.1, hx, hy + r)
      end
    end
    if s.message then
      G2.setColor(0, 0, 0, 0.6)
      G2.rectangle("fill", 4, 160, 192, 14, 4, 4)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      fitText(G2, s.message, 6, 160, 188, 14, "center")
      if app.font then G2.setFont(app.font) end
    end
    drawButton(G2, DONE, s.fromHome and "BACK" or "DONE", { 0.3, 0.3, 0.36 })
  end

  function app:releaseAll()
    if drag and drag.feeding then G.feedDrop() end
    drag, holdFive = nil, nil
  end
  app.leave = app.releaseAll

  -- for tests and the driver: geometry in app space
  app.geometry = { BODY = BODY, TRAY = TRAY, DONE = DONE, BEAN_ROW = BEAN_ROW,
    PUFF_SLOT = PUFF_SLOT, ARROW_L = ARROW_L, ARROW_R = ARROW_R, tools = tools, trayX = trayX,
    GAMES = GAMES, gameBadge = badgeRect, gameDiff = diffRect }

  return app
end
