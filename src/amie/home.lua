-- HOME: the Pokemon-Amie room on the bottom screen. The active Pokemon
-- wanders about as its party icon, plays when it is happy, naps when it has
-- a status, stops and asks for food when it is starving. Tap it for the
-- DECORATE / PLAY / SWITCH buttons; SWITCH shows the party. Decor and
-- visitors arrive with later phases; the room already reads the saved
-- wallpaper and placed items so they draw as soon as they exist.
-- State: src/amie/session.lua (mode "home"); numbers: data/amie_rules.lua.

return function(mod, Pointer, G, Rules, Store, host)

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
  local app = { id = "home", title = "ROOM", live = true }

  function app:wantsSurface() return G.session ~= nil and G.session.mode == "home" end

  local W, H = 256, 178
  local FLOOR = { x = 28, y = 78, w = 200, h = 78 }     -- where the Pokemon may walk
  local CLOSE = { x = 200, y = 158, w = 50, h = 16 }
  local SPEED = 38                                     -- px/s
  local ICON_SCALE = 2

  -- the wandering Pokemon
  local pet = { x = 128, y = 120, tx = 128, ty = 120, facing = -1, state = "idle", timer = 1.2,
    frame = 0, frameT = 0, bounce = 0, hops = 0 }
  local menu = nil        -- { x, y } the three buttons around the Pokemon
  local switchOpen = false
  local particles = {}
  local emote = nil
  local dance = nil
  local loopT = 0         -- the hearts / puffs / notes loop while the menu is open
  local lastKey = nil

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  local function inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
  end

  local function showEmote(id, secs)
    emote = { id = id, untilT = Pointer.now() + (secs or 1.2) }
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

  -- a point in the floor band, away from the current spot
  local function pickTarget()
    for _ = 1, 8 do
      local tx = FLOOR.x + math.random() * FLOOR.w
      local ty = FLOOR.y + math.random() * FLOOR.h
      if math.abs(tx - pet.x) + math.abs(ty - pet.y) > 40 then return tx, ty end
    end
    return FLOOR.x + FLOOR.w / 2, FLOOR.y + FLOOR.h / 2
  end

  -- the Pokemon's mood decides what it does next
  local function nextBehaviour(s)
    local m = s.meters
    if s.status or (s.mon and (s.mon.hp or 1) <= 0) then return "nap", 3 end
    if (m.fullness or 0) <= 0 and not pet.acknowledged then return "hungry", 2 end
    local r = math.random()
    local happy = (m.enjoyment or 0) >= Rules.N.HINT.HIGH
    if r < (happy and 0.3 or 0.12) then return "play", 1.8 end
    if r < 0.5 then return "idle", 0.8 + math.random() * 1.6 end
    -- a cushion in the room is a favourite spot
    local cushion = G.Decor and G.Decor.nearestCushion(Store.room(), pet.x, pet.y)
    if cushion and r < 0.7 then
      pet.tx, pet.ty = cushion.x, cushion.y - 2
      pet.sitNext = true
      return "walk", 10
    end
    pet.tx, pet.ty = pickTarget()
    return "walk", 10
  end

  local function resetFor(s)
    pet.x, pet.y = FLOOR.x + FLOOR.w / 2, FLOOR.y + FLOOR.h / 2
    pet.tx, pet.ty = pet.x, pet.y
    pet.state, pet.timer = "idle", 1.0
    pet.acknowledged = false
    pet.hops = 0
    menu, switchOpen = nil, false
    lastKey = s.key
  end

  -- ------- geometry the driver and tests can ask for

  function app.petPos() return pet.x, pet.y end
  function app.giftPos(i) return 22 + (i - 1) * 16, 150 end

  local BUTTONS = { "decorate", "play", "switch" }
  local function buttonPos(which)
    local cx = math.min(math.max(pet.x, 70), W - 70)
    local cy = math.min(math.max(pet.y - 62, 46), H - 70)
    if which == "decorate" then return cx - 64, cy + 14 end
    if which == "play" then return cx, cy - 12 end
    return cx + 64, cy + 14
  end
  function app.buttonPos(which) return buttonPos(which) end
  function app.menuOpen() return menu ~= nil end

  local SWITCH_ROW = { y = 120, slot = 36 }
  local function switchX(i, n) return (W - n * SWITCH_ROW.slot) / 2 + (i - 1) * SWITCH_ROW.slot end

  -- ------- input

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "home") then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    if inRect(x, y, CLOSE) then G.finish(); return end
    if switchOpen then
      local party = host.party and host.party() or {}
      local n = math.min(6, #party)
      for i = 1, n do
        local sx = switchX(i, n)
        if x >= sx and x < sx + SWITCH_ROW.slot and y >= SWITCH_ROW.y - 20 and y <= SWITCH_ROW.y + 24 then
          if host.isEgg and host.isEgg(party[i]) then
            G.say(G.tx("egg"), 2.5)
          elseif G.switchTo(party[i]) then resetFor(G.session) end
          switchOpen = false
          return
        end
      end
      switchOpen = false
      return
    end
    if menu then
      for _, which in ipairs(BUTTONS) do
        local bx, by = buttonPos(which)
        if ((x - bx) / 32) ^ 2 + ((y - by) / 20) ^ 2 <= 1 then
          menu = nil
          host.playSe("SE_SELECT")
          if which == "play" then G.enterPlay()
          elseif which == "switch" then switchOpen = true; G.say(G.tx("selectMon"), 3)
          elseif not G.enterDecorate() then G.say("Decorating is unavailable.", 2) end
          return
        end
      end
      menu = nil
      return
    end
    -- a gift box on the floor
    local gifts = G.Visitors and G.Visitors.pending() or {}
    for i = 1, math.min(#gifts, 6) do
      local gx, gy = app.giftPos(i)
      if math.abs(x - gx) <= 12 and math.abs(y - gy) <= 14 then
        local text = G.Visitors.claim(i)
        if text then
          host.playSe("SE_SUCCESS")
          G.say(text, 3.5)
          showEmote("emote/happy", 1.5)
          spawn("heart", gx, gy - 10, 3)
        end
        return
      end
    end
    -- on the Pokemon: the menu; near it: it looks over; starving: acknowledge
    local dx, dy = x - pet.x, y - (pet.y - 16)
    if dx * dx + dy * dy <= 26 ^ 2 then
      if pet.state == "hungry" then
        pet.acknowledged = true
        pet.state, pet.timer = "idle", 0.5
        G.say(("%s is hungry!"):format(s.name), 2)
        showEmote("emote/sad", 1.5)
        return
      end
      menu = { x = pet.x, y = pet.y }
      loopT = 0
      pet.state, pet.timer = "look", 4
      host.playSe("SE_SELECT")
      return
    end
    if math.abs(dx) < 90 then
      pet.facing = dx < 0 and -1 or 1
      pet.state, pet.timer = "look", 1.5
    end
  end

  -- ------- update

  function app:update(dt)
    local s = G.session
    if not (s and s.mode == "home") then
      app.live = false
      return
    end
    if s.key ~= lastKey then resetFor(s) end
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + dt
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vy = p.vy + ((p.kind == "heart" or p.kind == "note") and -10 or 40) * dt
      if p.age >= p.life then table.remove(particles, i) end
    end
    if emote and Pointer.now() > emote.untilT then emote = nil end
    loopT = loopT + dt
    if G.Visitors and not menu and not switchOpen then G.Visitors.update(dt) end

    -- behaviour
    pet.timer = pet.timer - dt
    if pet.state == "walk" then
      local dx, dy = pet.tx - pet.x, pet.ty - pet.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 2 or pet.timer <= 0 then
        if pet.sitNext and d < 2 then
          pet.sitNext = false
          pet.state, pet.timer = "sit", 3 + math.random() * 4
        else
          pet.sitNext = false
          pet.state, pet.timer = "idle", 0.6 + math.random() * 1.4
        end
      else
        local step = math.min(d, SPEED * dt)
        pet.x = pet.x + dx / d * step
        pet.y = pet.y + dy / d * step
        if math.abs(dx) > 1 then pet.facing = dx < 0 and -1 or 1 end
        pet.frameT = pet.frameT + dt
        if pet.frameT >= 0.18 then pet.frameT = 0; pet.frame = 1 - pet.frame end
      end
      -- starving: stop where it is
      if (s.meters.fullness or 0) <= 0 and not pet.acknowledged then pet.state, pet.timer = "hungry", 2 end
    elseif pet.state == "play" then
      pet.frameT = pet.frameT + dt
      if pet.frameT >= 0.12 then pet.frameT = 0; pet.frame = 1 - pet.frame end
      pet.bounce = math.abs(math.sin(pet.timer * 9)) * 10
      if pet.timer <= 0 then pet.bounce = 0; pet.state, pet.timer = "idle", 1 end
    else
      pet.frameT = pet.frameT + dt
      local rate = (pet.state == "nap") and 1.2 or 0.5
      if pet.frameT >= rate then pet.frameT = 0; pet.frame = 1 - pet.frame end
      if pet.state == "nap" and pet.frameT < dt * 1.5 and math.random() < 0.5 then spawn("zzz", pet.x + 10, pet.y - 40, 1) end
      if pet.timer <= 0 and not menu and not switchOpen then
        local st, t = nextBehaviour(s)
        pet.state, pet.timer = st, t
      elseif pet.timer <= 0 then
        pet.timer = 1
      end
    end

    -- milestones
    for _, ev in ipairs(G.takeEvents()) do
      if ev.kind == "dance" then dance = { cries = ev.cries, t = 0, next = 0 }
      elseif ev.kind == "gift" then G.say(("%s wants to give you something!"):format(s.name), 3); showEmote("emote/love", 2) end
    end
    if dance then
      dance.t = dance.t + dt
      if dance.t >= dance.next then
        dance.next = dance.next + 0.6
        dance.cries = dance.cries - 1
        pet.bounce = 12
        host.playCry(s.mon)
        spawn("heart", pet.x, pet.y - 44, 4)
        if dance.cries <= 0 then dance = nil end
      end
      pet.bounce = math.max(0, pet.bounce - 40 * dt)
    end
    app.live = true
  end

  -- ------- drawing

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
    elseif p.kind == "zzz" then
      G2.setColor(0.3, 0.3, 0.6, f)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.print("z", p.x, p.y)
      if app.font then G2.setFont(app.font) end
    else
      G2.setColor(1, 0.95, 0.5, f)
      G2.circle("fill", p.x, p.y, 2, 6)
    end
  end

  -- the room's three buttons are the game's own when extracted; else a round icon and the word
  local BUTTON_ART = { PLAY = "ui/btn_play", DECORATE = "ui/btn_decorate", SWITCH = "ui/btn_switch" }
  local BUTTON_WORD = { PLAY = "play", DECORATE = "decorate", SWITCH = "switchLabel" }
  local function drawRoundButton(G2, x, y, label, imgId, lit)
    local btn = art(BUTTON_ART[label])
    if btn then
      G2.setColor(1, 1, 1, lit and 1 or 0.55)
      local bw, bh = btn:getDimensions()
      local k = 62 / bw
      G2.draw(btn, x, y, 0, k, k, bw / 2, bh / 2)
      return
    end
    label = G.tx(BUTTON_WORD[label] or label, nil, label)
    local img = art(imgId)
    G2.setColor(1, 1, 1, lit and 1 or 0.5)
    if img then
      local iw, ih = img:getDimensions()
      local k = 36 / math.max(iw, ih)
      G2.draw(img, x, y, 0, k, k, iw / 2, ih / 2)
    else
      G2.setColor(1, 1, 1, 0.95)
      G2.circle("fill", x, y, 18, 24)
      G2.setColor(0.25, 0.3, 0.4, 1)
      G2.circle("line", x, y, 18, 24)
    end
    G2.setColor(1, 1, 1, 0.85)
    G2.rectangle("fill", x - 26, y - 31, 52, 11, 3, 3)
    G2.setColor(0.1, 0.1, 0.15, 1)
    if app.smallFont then G2.setFont(app.smallFont) end
    G2.printf(label, x - 30, y - 30, 60, "center")
    if app.font then G2.setFont(app.font) end
  end

  -- the icon above a wandering Pokemon: what it wants
  local function drawHint(G2, s, x, y)
    local hint = Rules.hint(s.meters)
    if not hint then return end
    local bob = math.sin(Pointer.now() * 4) * 2
    if hint == "puff" then
      local img = art("puff/sweet_basic")
      if img then G2.setColor(1, 1, 1, 1); G2.draw(img, x, y + bob, 0, 0.45, 0.45, 20, 20)
      else G2.setColor(0.95, 0.55, 0.2, 1); G2.ellipse("fill", x, y + bob, 7, 5) end
    else
      local img = art("fx/note")
      if hint == "orange_note" then G2.setColor(1, 0.6, 0.15, 1) else G2.setColor(1, 1, 1, 1) end
      if img then G2.draw(img, x, y + bob, 0, 1, 1, 9, 9)
      else
        if hint ~= "orange_note" then G2.setColor(0.3, 0.3, 0.6, 1) end
        G2.circle("fill", x - 2, y + bob + 3, 3, 8)
        G2.rectangle("fill", x, y + bob - 6, 1.5, 9)
      end
    end
  end

  -- while the menu is open: a loop of hearts (level), puffs and notes (distance to level 5)
  local function drawLoop(G2, s, x, y)
    local lv = Rules.level(s.meters.affection)
    local puffs = 5 - Rules.level(s.meters.fullness)
    local notes = 5 - Rules.level(s.meters.enjoyment)
    local seq = {}
    for _ = 1, lv do seq[#seq + 1] = "heart" end
    for _ = 1, puffs do seq[#seq + 1] = "puff" end
    for _ = 1, notes do seq[#seq + 1] = "note" end
    if #seq == 0 then return end
    local i = math.floor(loopT / 0.5) % #seq + 1
    local kind = seq[i]
    local f = 1 - (loopT % 0.5) / 0.5
    G2.setColor(1, 1, 1, 0.4 + 0.6 * f)
    if kind == "heart" then
      local img = art("fx/heart")
      if img then G2.draw(img, x, y - 4 * f, 0, 1.2, 1.2, 8, 8)
      else G2.setColor(0.95, 0.35, 0.5, 1); G2.circle("fill", x, y, 5, 10) end
    elseif kind == "puff" then
      local img = art("puff/sweet_basic")
      if img then G2.draw(img, x, y - 4 * f, 0, 0.45, 0.45, 20, 20)
      else G2.setColor(0.95, 0.55, 0.2, 1); G2.ellipse("fill", x, y, 7, 5) end
    else
      local img = art("fx/note")
      if img then G2.draw(img, x, y - 4 * f, 0, 1, 1, 9, 9)
      else G2.setColor(0.3, 0.3, 0.6, 1); G2.circle("fill", x, y, 4, 8) end
    end
  end

  function app:draw(G2, w, h)
    local s = G.session
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local room = Store.room()
    local bg = art(room.wallpaper or "bg/plain") or art("bg/plain")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local bl = app.bleed or 0
      local sc = math.max(w / bw, (h + bl) / bh)
      G2.draw(bg, (w - bw * sc) / 2, -bl + (h + bl - bh * sc) / 2, 0, sc, sc)
    else
      G2.setColor(0.98, 0.86, 0.45, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(0.9, 0.72, 0.3, 0.8)
      G2.rectangle("fill", 0, FLOOR.y - 10, w, h - FLOOR.y + 10)
    end
    if not s then return end

    -- placed decor, visitors and the Pokemon, all sorted by their feet
    local drawables = {}
    for _, it in ipairs(room.items or {}) do drawables[#drawables + 1] = { y = it.y or 0, item = it } end
    for _, v in ipairs(G.Visitors and G.Visitors.present or {}) do drawables[#drawables + 1] = { y = v.y, visitor = v } end
    drawables[#drawables + 1] = { y = pet.y, pet = true }
    table.sort(drawables, function(a, b) return a.y < b.y end)
    local function drawVisitor(v)
      local ic = v.icon
      if ic and ic.image and ic.quads then
        G2.setColor(1, 1, 1, 1)
        local q = ic.quads[v.frame % (ic.frames or 1)] or ic.quads[0]
        drawPixel(ic.image, q, v.x, v.y, 0, 1.6 * -v.facing, 1.6, (ic.w or 32) / 2, ic.h or 32)
      else
        G2.setColor(0.6, 0.6, 0.7, 1)
        G2.circle("fill", v.x, v.y - 14, 10, 14)
      end
    end
    local function drawPet()
      G2.setColor(0, 0, 0, 0.18)
      G2.ellipse("fill", pet.x, pet.y + 2, 16, 5)
      local icon = s.icon
      local by = pet.y - (pet.bounce or 0)
      if icon and icon.image and icon.quads then
        local q = icon.quads[pet.frame % (icon.frames or 1)] or icon.quads[0]
        G2.setColor(1, 1, 1, 1)
        if pet.state == "nap" then G2.setColor(0.8, 0.8, 0.9, 1) end
        drawPixel(icon.image, q, pet.x, by, 0, ICON_SCALE * -pet.facing, ICON_SCALE, (icon.w or 32) / 2, icon.h or 32)
      elseif s.pic and s.pic.image then
        G2.setColor(1, 1, 1, 1)
        drawPixel(s.pic.image, pet.x, by, 0, -pet.facing, 1, (s.pic.w or 64) / 2, s.pic.h or 64)
      else
        G2.setColor(0.9, 0.75, 0.3, 1)
        G2.circle("fill", pet.x, by - 20, 18, 24)
      end
    end
    for _, d in ipairs(drawables) do
      if d.item then
        local img = art(d.item.id)
        if img then
          G2.setColor(1, 1, 1, 1)
          local iw, ih = img:getDimensions()
          G2.draw(img, d.item.x, d.item.y, 0, 1, 1, iw / 2, ih)
        else
          G2.setColor(0.8, 0.6, 0.4, 1)
          G2.rectangle("fill", d.item.x - 14, d.item.y - 14, 28, 14, 4, 4)
        end
      elseif d.visitor then
        drawVisitor(d.visitor)
      else
        drawPet()
      end
    end
    -- the set-out puff and the visitors' chat
    if room.puffOut then
      local img = art(room.puffOut)
      G2.setColor(1, 1, 1, 0.9)
      G2.ellipse("fill", 212, 74, 14, 5)
      if img then G2.setColor(1, 1, 1, 1); G2.draw(img, 212, 64, 0, 0.5, 0.5, 20, 20) end
    end
    local grp = G.Visitors and G.Visitors.group
    if grp and grp.bubble then
      local v = G.Visitors.present[grp.bubble.who]
      if v then
        local bx, by = v.x, v.y - 60
        local bub = art("bubble/solid")
        if bub then G2.setColor(1, 1, 1, 1); G2.draw(bub, bx, by, 0, 0.7, 0.7, 30, 30)
        else G2.setColor(1, 1, 1, 0.95); G2.circle("fill", bx, by, 14, 16) end
        local word = grp.bubble.word
        if word == "heart" then
          local img = art("fx/heart")
          if img then G2.setColor(1, 1, 1, 1); G2.draw(img, bx, by, 0, 1.2, 1.2, 8, 8)
          else G2.setColor(0.95, 0.35, 0.5, 1); G2.circle("fill", bx, by, 5, 10) end
        elseif word == "note" then
          local img = art("fx/note")
          if img then G2.setColor(1, 1, 1, 1); G2.draw(img, bx, by, 0, 1, 1, 9, 9)
          else G2.setColor(0.3, 0.3, 0.6, 1); G2.circle("fill", bx, by, 4, 8) end
        else
          G2.setColor(0.1, 0.1, 0.15, 1)
          G2.printf(word, bx - 20, by - 7, 40, "center")
        end
      end
    end
    -- gift boxes waiting on the floor
    local gifts = G.Visitors and G.Visitors.pending() or {}
    for i = 1, math.min(#gifts, 6) do
      local gx, gy = app.giftPos(i)
      local img = art("ui/gift")
      if img then
        G2.setColor(1, 1, 1, 1)
        local iw, ih = img:getDimensions()
        G2.draw(img, gx, gy, 0, 20 / iw, 20 / ih, iw / 2, ih / 2)
      else
        G2.setColor(0.9, 0.3, 0.4, 1)
        G2.rectangle("fill", gx - 7, gy - 7, 14, 14, 2, 2)
        G2.setColor(1, 0.9, 0.3, 1)
        G2.rectangle("fill", gx - 1, gy - 7, 2, 14)
      end
    end

    if menu then drawLoop(G2, s, pet.x, pet.y - 72)
    elseif pet.state == "walk" or pet.state == "hungry" then drawHint(G2, s, pet.x, pet.y - 72) end

    if emote then
      local img = art(emote.id)
      -- up-left by the head (the tail points down-right), small enough to clear the buttons
      if img then G2.setColor(1, 1, 1, 1); G2.draw(img, pet.x - 18, pet.y - 40, 0, 0.5, 0.5, 25, 25) end
    end
    for _, p in ipairs(particles) do drawParticle(G2, p) end

    -- the three buttons
    if menu then
      local bx, by2 = buttonPos("decorate")
      drawRoundButton(G2, bx, by2, "DECORATE", "ui/gift", false)
      bx, by2 = buttonPos("play")
      drawRoundButton(G2, bx, by2, "PLAY", "ui/badge_pokeball", true)
      bx, by2 = buttonPos("switch")
      drawRoundButton(G2, bx, by2, "SWITCH", "ui/refresh_round", true)
    end

    -- the party strip
    if switchOpen then
      local party = host.party and host.party() or {}
      local n = math.min(6, #party)
      G2.setColor(0, 0, 0, 0.5)
      G2.rectangle("fill", switchX(1, n) - 6, SWITCH_ROW.y - 24, n * SWITCH_ROW.slot + 12, 52, 6, 6)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(G.tx("switch"), 0, SWITCH_ROW.y - 38, W, "center")
      if app.font then G2.setFont(app.font) end
      for i = 1, n do
        local p = party[i]
        local sx = switchX(i, n)
        local ic = host.icon and host.icon(p)
        local isActive = host.monKey(p) == s.key
        if isActive then
          G2.setColor(1, 1, 1, 0.35)
          G2.rectangle("fill", sx + 2, SWITCH_ROW.y - 22, SWITCH_ROW.slot - 4, 48, 5, 5)
        end
        G2.setColor(1, 1, 1, 1)
        if ic and ic.image and ic.quads then
          drawPixel(ic.image, ic.quads[0], sx + SWITCH_ROW.slot / 2, SWITCH_ROW.y + 4, 0, 1, 1, (ic.w or 32) / 2, ic.h or 32)
        else
          G2.circle("fill", sx + SWITCH_ROW.slot / 2, SWITCH_ROW.y - 10, 10, 16)
        end
        if app.smallFont then G2.setFont(app.smallFont) end
        local lvl = Rules.level(Store.meters(host.monKey(p)).affection)
        G2.printf(("%d"):format(lvl), sx, SWITCH_ROW.y + 8, SWITCH_ROW.slot, "center")
        if app.font then G2.setFont(app.font) end
      end
    end

    -- hearts, message, CLOSE
    local lv = Rules.level(s.meters.affection)
    for i = 1, 5 do
      G2.setColor(i <= lv and 0.95 or 0.6, i <= lv and 0.35 or 0.6, i <= lv and 0.5 or 0.65, 1)
      local hx, hy, r = 10 + (i - 1) * 12, 152, 4
      G2.circle("fill", hx - r * 0.5, hy - r * 0.3, r * 0.55, 10)
      G2.circle("fill", hx + r * 0.5, hy - r * 0.3, r * 0.55, 10)
      G2.polygon("fill", hx - r, hy - r * 0.1, hx + r, hy - r * 0.1, hx, hy + r)
    end
    if s.message then
      G2.setColor(0, 0, 0, 0.6)
      G2.rectangle("fill", 4, 160, 192, 14, 4, 4)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      fitText(G2, s.message, 6, 160, 188, 14, "center")
      if app.font then G2.setFont(app.font) end
    end
    G2.setColor(0.3, 0.3, 0.36, 1)
    G2.rectangle("fill", CLOSE.x, CLOSE.y, CLOSE.w, CLOSE.h, 6, 6)
    G2.setColor(1, 1, 1, 0.95)
    G2.printf("CLOSE", CLOSE.x, CLOSE.y + CLOSE.h / 2 - 7, CLOSE.w, "center")
  end

  function app:releaseAll()
    menu, switchOpen = nil, false
  end
  app.leave = app.releaseAll

  return app
end
