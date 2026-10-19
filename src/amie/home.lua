-- HOME: the Pokemon-Amie room on the bottom screen, played from the game's own layout
-- (kawaii_lower.bclyt, a/0/2/6 entry 0; Wooble's capture 2026-10-17). The wallpaper, the
-- placed decor, the set-out puff, visitors, gifts and the wandering Pokemon are drawn in
-- the layout's 320x240 units; the layout adds the scalloped frame (5z, opened by
-- window_open), the menu (f: the dim 5h and the game's PLAY / DECORATE / SWITCH buttons)
-- and, while the menu is up, the bubbles over the Pokemon that say how much it wants Poke
-- Puffs (g, okashi_hungry1..5) and play (h, asobi_play1..5), with hearts for its affection
-- (5n, heart_nakayosi1..5). A puff set out in DECORATE falls onto its spot (okashi_fall).
-- State: src/amie/session.lua (mode "home"); numbers: data/amie_rules.lua; the room's
-- units and spots: src/amie/decor.lua.

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
  -- the room lives on the bottom screen alone, as Super Training's home: the game keeps the
  -- top screen (no Amie layer in this mode) and the player walks about meanwhile; a battle
  -- takes the bottom screen back
  app.fieldPlay = true

  function app:wantsSurface()
    return G.session ~= nil and G.session.mode == "home" and not (G.inBattle and G.inBattle())
  end

  -- the layout's units: 320 wide, LH tall (240 on the 3DS shape); drawn under scale(L) from
  -- the top of the screen (app y + bleed). On a taller screen (Kanto Gear's) the room's
  -- contents sit D/2 lower and the menu buttons, the bottom strip and the return button D
  -- lower, the wallpaper and the frame cover it all (D = LH - 240; 0 on the 3DS shape).
  local L = 256 / 320
  local BLEED = 14
  local LH, D = 240, 0
  local FLOOR = { x0 = 40, x1 = 280, y0 = 100, y1 = 198 }  -- where the Pokemon's anchor may go
  local SPEED = 47                                          -- layout units a second
  local ICON_K = 1.25         -- a 32x32 party icon drawn 40 across, as the game's poke_icon_2 pane
  local RETURN = { 305, 224, 27, 27 }                       -- the blue return (closes), Super Training's
  local BOTTOM_STRIP_H = (240 - 217.5) * 30 / 24
  local FPS = 30

  -- the wandering Pokemon: x, y is its anchor (the layout's pane 8: icon above, shadow at +8)
  local pet = { x = 160, y = 150, tx = 160, ty = 150, facing = -1, state = "idle", timer = 1.2,
    frame = 0, frameT = 0, bounce = 0, hops = 0 }
  local menu = nil        -- { press = which, t } once open; press runs the button's bounce
  local switchOpen = false
  local particles = {}
  local emote = nil
  local dance = nil
  local lastKey = nil
  local away = true       -- left the screen: the next frame on it opens the frame again
  local fade = nil        -- { t, dir = 1 out to black | -1 in from black, after = fn }
  local P, Pfail = nil, false
  local fallPending = false
  local FADE_S = 10 / FPS

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local function bleed() return app.bleed or BLEED end
  local function setShape(h)
    local lh = math.max(240, ((h or 178) + bleed()) / L)
    if lh == LH then return end
    LH, D = lh, lh - 240
    app.shapeDirty = true
  end
  app.setShape = setShape

  -- app point -> room point (layout units, 3DS shape) and back
  local function toRoom(x, y) return x / L, (y + bleed()) / L - D / 2 end
  local function fromRoom(x, y) return x * L, (y + D / 2) * L - bleed() end
  local function toLow(x, y) return x / L, (y + bleed()) / L - D end
  local function inBox(x, y, b) return b and x >= b[1] and x <= b[1] + b[3] and y >= b[2] and y <= b[2] + b[4] end

  -- the game's screen, or nil (no extracted art: the room draws without it)
  local ROOM_PANES = { "1t", "8", "g", "h", "5n", "17", "3", "4", "18", "31", "1h", "1j", "1l", "1n", "1p", "1r",
    "2w", "2r", "2o", "w", "x", "y", "z", "10" }
  local BUTTONS = { "5e", "5f", "5g" }
  local function screen()
    if P or Pfail then return P end
    local S = mod.lyt
    P = S and S.open("amie_room", "kawaii_lower.bclyt", { "amie_room" }) or nil
    if not P then Pfail = S == nil; return nil end
    -- drawn by us, in depth order with the Pokemon and the decor
    for _, n in ipairs({ "3b", "8", "1t", "17", "3", "4", "18", "31" }) do P:set(n, "visible", false) end
    -- the game fills the buttons with its own art (a/0/2/6 entry 1)
    P:setImage("5", art("ui/btn_play"))
    P:setImage("11", art("ui/btn_decorate"))
    P:setImage("13", art("ui/btn_switch"))
    P:play("window_open")
    app.shapeDirty = true
    return P
  end
  app.screen = screen

  local function applyShape()
    if not P or (P.shapeLH == LH and not app.shapeDirty) then return end
    P.shapeLH, app.shapeDirty = LH, false
    if D <= 0 then
      P.stretchY, P.stretchMode, P.adjust = nil, nil, nil
      return
    end
    P.stretchY, P.stretchMode = LH / 240, "backdrop"
    local adj = {}
    -- y is up in the layout: down the screen is a negative dy
    for _, n in ipairs(ROOM_PANES) do adj[n] = { dy = -D / 2 } end
    for _, n in ipairs(BUTTONS) do adj[n] = { dy = -D } end
    P.adjust = adj
  end

  local function showEmote(id, secs)
    emote = { id = id, untilT = Pointer.now() + (secs or 1.2) }
  end

  local function spawn(kind, x, y, n)
    for _ = 1, n or 1 do
      particles[#particles + 1] = {
        kind = kind, x = x + (math.random() - 0.5) * 20, y = y + (math.random() - 0.5) * 10,
        vx = (math.random() - 0.5) * 38, vy = -25 - math.random() * 38,
        life = 0.9 + math.random() * 0.5, age = 0, size = 4 + math.random() * 4,
      }
    end
  end

  -- a point in the floor band, away from the current spot
  local function pickTarget()
    for _ = 1, 8 do
      local tx = FLOOR.x0 + math.random() * (FLOOR.x1 - FLOOR.x0)
      local ty = FLOOR.y0 + math.random() * (FLOOR.y1 - FLOOR.y0)
      if math.abs(tx - pet.x) + math.abs(ty - pet.y) > 50 then return tx, ty end
    end
    return (FLOOR.x0 + FLOOR.x1) / 2, (FLOOR.y0 + FLOOR.y1) / 2
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
      pet.tx, pet.ty = cushion.x, cushion.y
      pet.sitNext = true
      return "walk", 10
    end
    pet.tx, pet.ty = pickTarget()
    return "walk", 10
  end

  local function resetFor(s)
    pet.x, pet.y = 160, 150
    pet.tx, pet.ty = pet.x, pet.y
    pet.state, pet.timer = "idle", 1.0
    pet.acknowledged = false
    pet.hops = 0
    menu, switchOpen = nil, false
    lastKey = s.key
  end

  -- the menu's bubbles: how much it wants puffs and play (5 - level, none when full), and its
  -- affection level as hearts; each the game's own looping clip
  local function needs(s)
    local m = s.meters
    return math.max(0, 5 - Rules.level(m.fullness)), math.max(0, 5 - Rules.level(m.enjoyment)),
      Rules.level(m.affection)
  end
  local function showBubbles(on)
    if not P then return end
    local s = G.session
    local hungry, bored, hearts = 0, 0, 0
    if on and s then hungry, bored, hearts = needs(s) end
    local function one(pane, clip, n)
      if n > 0 then
        P:set(pane, "visible", true)
        P:play(clip .. string.format("%02d", math.min(5, n)), { loop = true })
      else
        P:set(pane, "visible", false)
      end
    end
    one("g", "okashi_hungry", hungry)
    one("h", "asobi_play", bored)
    one("5n", "heart_nakayosi", hearts)
  end

  local function setMenu(on)
    if on then
      menu = {}
      host.playSe("SE_SELECT")
    else
      menu = nil
    end
    if P then
      for _, n in ipairs({ "f", "5h", "5e", "5", "5f", "11", "5g", "13" }) do P:set(n, "visible", on and true or false) end
      for _, n in ipairs({ "5", "11", "13" }) do P:clear(n, "sx"); P:clear(n, "sy") end
    end
    showBubbles(on)
  end

  -- ------- geometry the driver and tests can ask for (app units: where to tap)

  function app.petPos() return fromRoom(pet.x, pet.y - 14) end
  local function giftRoomPos(i)
    if i == 6 then return 160, 155 end
    return 60 + (i - 1) * 50, 190
  end
  function app.giftPos(i) return fromRoom(giftRoomPos(i)) end
  local BUTTON_PANE = { play = "7", decorate = "15", switch = "16" }
  local BUTTON_ART = { play = "5", decorate = "11", switch = "13" }
  function app.buttonPos(which)
    local b
    if P then
      local x, y, w, h = P:box(BUTTON_PANE[which])
      if x then b = { x + w / 2, y + h / 2 } end
    end
    b = b or ({ play = { 160, 181 + D }, decorate = { 75, 180 + D }, switch = { 245, 180 + D } })[which]
    return b[1] * L, b[2] * L - bleed()
  end
  function app.closePos() return RETURN[1] * L, (RETURN[2] + D) * L - bleed() end
  function app.menuOpen() return menu ~= nil end
  -- something is still moving (a fade, a button's bounce, the frame opening, a puff falling)
  function app.busy()
    if fade or fallPending or (menu and menu.press) then return true end
    if P and not (P:finished("window_open") and P:finished("okashi_fall")) then return true end
    return false
  end

  local SWITCH_ROW = { y = 150, slot = 45 }
  local function switchX(i, n) return (320 - n * SWITCH_ROW.slot) / 2 + (i - 1) * SWITCH_ROW.slot end

  local function leaveFor(after)
    fade = { t = 0, dir = 1, after = after }
  end

  -- ------- input

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "home") or fade then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local lx, ly = toLow(ev.x, ev.y)
    if math.abs(lx - RETURN[1]) <= 20 and math.abs(ly - RETURN[2]) <= 20 then G.finish(); return end
    local x, y = toRoom(ev.x, ev.y)
    if switchOpen then
      local party = host.party and host.party() or {}
      local n = math.min(6, #party)
      for i = 1, n do
        local sx = switchX(i, n)
        if x >= sx and x < sx + SWITCH_ROW.slot and y >= SWITCH_ROW.y - 25 and y <= SWITCH_ROW.y + 30 then
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
      if menu.press then return end
      -- the game's buttons, where the layout has them this frame
      local ax, ay = ev.x / L, (ev.y + bleed()) / L
      for which, pane in pairs(BUTTON_PANE) do
        local bx, by, bw, bh
        if P then bx, by, bw, bh = P:box(pane) end
        local hit
        if bx then hit = ax >= bx and ax <= bx + bw and ay >= by and ay <= by + bh
        else
          local px, py = app.buttonPos(which)
          hit = math.abs(ev.x - px) <= 30 and math.abs(ev.y - py) <= 18
        end
        if hit then
          host.playSe("SE_SELECT")
          menu.press = { which = which, t = 0 }
          return
        end
      end
      setMenu(false)
      return
    end
    -- a gift box on the floor
    local gifts = G.Visitors and G.Visitors.pending() or {}
    for i = 1, math.min(#gifts, 6) do
      local gx, gy = giftRoomPos(i)
      if math.abs(x - gx) <= 16 and math.abs(y - (gy - 4)) <= 20 then
        local text = G.Visitors.claim(i)
        if text then
          host.playSe("SE_SUCCESS")
          G.say(text, 3.5)
          showEmote("emote/happy", 1.5)
          spawn("heart", gx, gy - 12, 3)
        end
        return
      end
    end
    -- on the Pokemon: the menu; near it: it looks over; starving: acknowledge
    local dx, dy = x - pet.x, y - (pet.y - 14)
    if dx * dx + dy * dy <= 28 ^ 2 then
      if pet.state == "hungry" then
        pet.acknowledged = true
        pet.state, pet.timer = "idle", 0.5
        G.say(("%s is hungry!"):format(s.name), 2)
        showEmote("emote/sad", 1.5)
        return
      end
      pet.state, pet.timer = "look", 4
      setMenu(true)
      return
    end
    if math.abs(dx) < 110 then
      pet.facing = dx < 0 and -1 or 1
      pet.state, pet.timer = "look", 1.5
    end
  end

  -- a menu button's work, once its bounce has played
  local function runButton(which)
    setMenu(false)
    if which == "play" then G.enterPlay()
    elseif which == "switch" then switchOpen = true; G.say(G.tx("selectMon"), 3)
    else
      -- DECORATE: the room fades to black first (Wooble's capture)
      leaveFor(function()
        if not G.enterDecorate() then G.say("Decorating is unavailable.", 2) end
      end)
    end
  end

  -- ------- update

  -- the game's press: PLAY's button1_anime2 scale curve (12 frames), on whichever was pressed
  local BOUNCE = { 0.8, 0.852, 0.971, 1.1, 1.17, 1.15, 1.08, 1, 0.937, 0.9, 0.938, 1 }

  local function onEnter(s)
    away = false
    if P then
      P:play("window_open")
      setMenu(false)
    end
    -- back from DECORATE: up from black; a puff just set out falls onto its spot
    if s.fromDecorate then
      fade = { t = 0, dir = -1 }
      s.fromDecorate = nil
    end
    -- (it falls once the room is up from black: held back until the fade ends)
    if s.puffDrop then
      s.puffDrop = nil
      fallPending = P ~= nil
    end
  end

  function app:update(dt)
    local s = G.session
    if not (s and s.mode == "home") then
      app.live = false
      return
    end
    if s.key ~= lastKey then resetFor(s) end
    screen()
    if away then onEnter(s) end
    if P then P:advance((dt or 0) * FPS) end
    if fade then
      fade.t = fade.t + (dt or 0)
      if fade.t >= FADE_S then
        local after = fade.after
        fade = nil
        if after then after() end
      end
    end
    if fallPending and not fade and P then
      fallPending = false
      P:play("okashi_fall")
    end
    if menu and menu.press then
      menu.press.t = menu.press.t + (dt or 0)
      local f = math.floor(menu.press.t * FPS) + 1
      local k = BOUNCE[math.min(#BOUNCE, f)]
      if P then
        local pane = BUTTON_ART[menu.press.which]
        P:set(pane, "sx", k); P:set(pane, "sy", k)
      end
      if f > #BOUNCE then runButton(menu.press.which) end
    end
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + dt
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vy = p.vy + ((p.kind == "heart" or p.kind == "note") and -12 or 50) * dt
      if p.age >= p.life then table.remove(particles, i) end
    end
    if emote and Pointer.now() > emote.untilT then emote = nil end
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
      pet.bounce = math.abs(math.sin(pet.timer * 9)) * 12
      if pet.timer <= 0 then pet.bounce = 0; pet.state, pet.timer = "idle", 1 end
    else
      pet.frameT = pet.frameT + dt
      local rate = (pet.state == "nap") and 1.2 or 0.5
      if pet.frameT >= rate then pet.frameT = 0; pet.frame = 1 - pet.frame end
      if pet.state == "nap" and pet.frameT < dt * 1.5 and math.random() < 0.5 then spawn("zzz", pet.x + 12, pet.y - 40, 1) end
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
        pet.bounce = 15
        host.playCry(s.mon)
        spawn("heart", pet.x, pet.y - 50, 4)
        if dance.cries <= 0 then dance = nil end
      end
      pet.bounce = math.max(0, pet.bounce - 50 * dt)
    end
    app.live = true
  end

  -- ------- drawing (layout units)

  local function drawParticle(G2, p)
    local f = 1 - p.age / p.life
    if p.kind == "heart" then
      local img = art("lyt/amie_room/particle_01") or art("fx/heart")
      if img then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, f); G2.draw(img, p.x, p.y, 0, 18 / iw, 18 / ih, iw / 2, ih / 2); return
      end
      G2.setColor(0.95, 0.35, 0.5, f)
      local r = p.size
      G2.circle("fill", p.x - r * 0.5, p.y - r * 0.3, r * 0.55, 10)
      G2.circle("fill", p.x + r * 0.5, p.y - r * 0.3, r * 0.55, 10)
      G2.polygon("fill", p.x - r, p.y - r * 0.1, p.x + r, p.y - r * 0.1, p.x, p.y + r)
    elseif p.kind == "zzz" then
      G2.setColor(0.3, 0.3, 0.6, f)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.print("z", p.x, p.y, 0, 1 / L, 1 / L)
    else
      G2.setColor(1, 0.95, 0.5, f)
      G2.circle("fill", p.x, p.y, 2.5, 6)
    end
  end

  -- a visitor's words in the game's talk bubble (talk_bubble_L and its symbols)
  local TALK = { ["?"] = "talk_question", ["..."] = "talk_silent", ["!"] = "talk_exc1", ["!!"] = "talk_exc2",
    ["!!!"] = "talk_exc3", note = "talk_onpu", heart = "talk_heart" }
  local function drawTalk(G2, x, y, word)
    local bub = art("lyt/amie_room/talk_bubble_L")
    local sym = TALK[word] and art("lyt/amie_room/" .. TALK[word])
    if bub then
      local bw, bh = bub:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(bub, x, y, 0, 32 / bw, 32 / bh, bw / 2, bh / 2)
      if sym then
        local sw, sh = sym:getDimensions()
        G2.draw(sym, x, y, 0, 32 / sw, 32 / sh, sw / 2, sh / 2)
        return
      end
    else
      G2.setColor(1, 1, 1, 0.95); G2.circle("fill", x, y, 15, 16)
    end
    G2.setColor(0.1, 0.1, 0.15, 1)
    G2.printf(word, x - 25, y - 8, 50 * L, "center", 0, 1 / L, 1 / L)
  end

  local function drawShadow(G2, x, y, w)
    local sh = art("lyt/amie_room/shadow")
    if sh then
      local iw, ih = sh:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(sh, x, y, 0, w / iw, (w * 8 / 23) / ih, iw / 2, ih / 2)
    else
      G2.setColor(0, 0, 0, 0.18)
      G2.ellipse("fill", x, y, w / 2, w * 4 / 23)
    end
  end

  local function drawItem(G2, it)
    local img = art(it.id)
    G2.setColor(1, 1, 1, 1)
    if img then
      local iw, ih = img:getDimensions()
      G2.draw(img, it.x, it.y + (G.Decor and G.Decor.FOOT or 11), 0, 1, 1, iw / 2, ih)
    else
      G2.setColor(0.8, 0.6, 0.4, 1)
      G2.rectangle("fill", it.x - 16, it.y - 10, 32, 18, 4, 4)
    end
  end

  -- the set-out puff: on its spot, or where okashi_fall has it on the way down
  local function puffPos()
    local Dc = G.Decor
    local x, y = Dc and Dc.PUFF_SPOT.x or 160, (Dc and Dc.PUFF_SPOT.y or 116) - (Dc and Dc.PUFF_LIFT or 20)
    if P and P:entry("okashi_fall") then
      local bx, by, bw, bh = P:box("1t")
      -- the box is on screen (the shape's D/2 included); the scene draws D/2 lower itself
      if bx then x, y = bx + bw / 2, by + bh / 2 - D / 2 end
    end
    return x, y
  end

  local function drawPuff(G2, id)
    local x, y = puffPos()
    local img = art(id)
    if img then
      local iw, ih = img:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(img, x, y, 0, 40 / iw, 40 / ih, iw / 2, ih / 2)
    else
      G2.setColor(0.95, 0.55, 0.2, 1); G2.ellipse("fill", x, y, 12, 9)
    end
  end

  local function drawPet(G2, s)
    drawShadow(G2, pet.x, pet.y + 8, 23)
    local icon = s.icon
    local by = pet.y + 10 - (pet.bounce or 0)
    if icon and icon.image and icon.quads then
      local q = icon.quads[pet.frame % (icon.frames or 1)] or icon.quads[0]
      G2.setColor(1, 1, 1, 1)
      if pet.state == "nap" then G2.setColor(0.8, 0.8, 0.9, 1) end
      drawPixel(icon.image, q, pet.x, by, 0, ICON_K * -pet.facing, ICON_K, (icon.w or 32) / 2, icon.h or 32)
    elseif s.pic and s.pic.image then
      G2.setColor(1, 1, 1, 1)
      drawPixel(s.pic.image, pet.x, by, 0, -pet.facing * 0.6, 0.6, (s.pic.w or 64) / 2, s.pic.h or 64)
    else
      G2.setColor(0.9, 0.75, 0.3, 1)
      G2.circle("fill", pet.x, by - 18, 16, 24)
    end
  end

  local function drawVisitor(G2, v)
    drawShadow(G2, v.x, v.y + 8, 20)
    local ic = v.icon
    if ic and ic.image and ic.quads then
      G2.setColor(1, 1, 1, 1)
      local q = ic.quads[v.frame % (ic.frames or 1)] or ic.quads[0]
      drawPixel(ic.image, q, v.x, v.y + 10, 0, ICON_K * -v.facing, ICON_K, (ic.w or 32) / 2, ic.h or 32)
    else
      G2.setColor(0.6, 0.6, 0.7, 1)
      G2.circle("fill", v.x, v.y - 8, 12, 14)
    end
  end

  local function drawWallpaper(G2, room)
    local bg = art(room.wallpaper or "wall/pink") or art("bg/plain")
    if bg then
      -- the game's 320x240 picture, its Poke Ball's middle on the puff's spot (Decor.wallPlace)
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local sc, ox, oy = 1, 0, 0
      if G.Decor and G.Decor.wallPlace then sc, ox, oy = G.Decor.wallPlace(LH, D / 2) end
      G2.draw(bg, ox, oy, 0, 320 * sc / bw, 240 * sc / bh)
    else
      G2.setColor(0.98, 0.86, 0.45, 1)
      G2.rectangle("fill", 0, 0, 320, LH)
    end
  end

  -- the room's contents: decor, the puff, visitors and the Pokemon by depth; gifts; chat
  local function drawScene(G2, s, room)
    local list = {}
    for _, it in ipairs(room.items or {}) do list[#list + 1] = { y = it.y, item = it } end
    for _, v in ipairs(G.Visitors and G.Visitors.present or {}) do list[#list + 1] = { y = v.y, visitor = v } end
    if room.puffOut and not fallPending then list[#list + 1] = { y = G.Decor and G.Decor.PUFF_SPOT.y or 116, puff = room.puffOut } end
    list[#list + 1] = { y = pet.y, pet = true }
    table.sort(list, function(a, b) return a.y < b.y end)
    for _, d in ipairs(list) do
      if d.item then drawItem(G2, d.item)
      elseif d.visitor then drawVisitor(G2, d.visitor)
      elseif d.puff then drawPuff(G2, d.puff)
      else drawPet(G2, s) end
    end
    local grp = G.Visitors and G.Visitors.group
    if grp and grp.bubble then
      local v = G.Visitors.present[grp.bubble.who]
      if v then drawTalk(G2, v.x + 12, v.y - 44, grp.bubble.word) end
    end
    -- gift boxes waiting on the floor (the game's gift panes 1j..1r, 1h)
    local gifts = G.Visitors and G.Visitors.pending() or {}
    for i = 1, math.min(#gifts, 6) do
      local gx, gy = giftRoomPos(i)
      local img = art("lyt/amie_room/gift")
      if img then
        G2.setColor(1, 1, 1, 1)
        local iw, ih = img:getDimensions()
        G2.draw(img, gx, gy, 0, 32 / iw, 40 / ih, iw / 2, ih / 2)
      else
        G2.setColor(0.9, 0.3, 0.4, 1)
        G2.rectangle("fill", gx - 9, gy - 9, 18, 18, 2, 2)
        G2.setColor(1, 0.9, 0.3, 1)
        G2.rectangle("fill", gx - 1.5, gy - 9, 3, 18)
      end
    end
    if emote then
      local img = art(emote.id)
      -- up-left by the head (the tail points down-right)
      if img then G2.setColor(1, 1, 1, 1); G2.draw(img, pet.x - 22, pet.y - 44, 0, 0.6, 0.6, 25, 25) end
    end
    for _, p in ipairs(particles) do drawParticle(G2, p) end
  end

  -- the party row SWITCH shows
  local function drawSwitch(G2, s)
    local party = host.party and host.party() or {}
    local n = math.min(6, #party)
    G2.setColor(0, 0, 0, 0.5)
    G2.rectangle("fill", switchX(1, n) - 8, SWITCH_ROW.y - 30, n * SWITCH_ROW.slot + 16, 65, 8, 8)
    G2.setColor(1, 1, 1, 1)
    if app.smallFont then G2.setFont(app.smallFont) end
    G2.printf(G.tx("switch"), 0, SWITCH_ROW.y - 48, 320 * L, "center", 0, 1 / L, 1 / L)
    for i = 1, n do
      local p = party[i]
      local sx = switchX(i, n)
      local ic = host.icon and host.icon(p)
      if host.monKey(p) == s.key then
        G2.setColor(1, 1, 1, 0.35)
        G2.rectangle("fill", sx + 3, SWITCH_ROW.y - 28, SWITCH_ROW.slot - 6, 60, 6, 6)
      end
      G2.setColor(1, 1, 1, 1)
      if ic and ic.image and ic.quads then
        drawPixel(ic.image, ic.quads[0], sx + SWITCH_ROW.slot / 2, SWITCH_ROW.y + 6, 0, ICON_K, ICON_K, (ic.w or 32) / 2, ic.h or 32)
      else
        G2.circle("fill", sx + SWITCH_ROW.slot / 2, SWITCH_ROW.y - 12, 12, 16)
      end
      local lvl = Rules.level(Store.meters(host.monKey(p)).affection)
      G2.printf(("%d"):format(lvl), sx, SWITCH_ROW.y + 10, SWITCH_ROW.slot * L, "center", 0, 1 / L, 1 / L)
    end
  end

  -- the PlayNav strip upside down along the bottom with the blue return, as Super Training's
  local function drawBottom(G2, s)
    local strip = art("training/home_strip")
    if strip then
      local sw, sh = strip:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(strip, 0, LH, 0, 160 / sw, -BOTTOM_STRIP_H / sh)
      G2.draw(strip, 320, LH, 0, -160 / sw, -BOTTOM_STRIP_H / sh)
    else
      G2.setColor(0.45, 0.46, 0.5, 1)
      G2.rectangle("fill", 0, LH - BOTTOM_STRIP_H, 320, BOTTOM_STRIP_H)
    end
    local ret = art("training/home_return")
    local x, y, w, h = RETURN[1], RETURN[2] + D, RETURN[3], RETURN[4]
    if ret then
      local iw, ih = ret:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(ret, x - w / 2, y - h / 2, 0, w / iw, h / ih)
    else
      G2.setColor(0.3, 0.3, 0.36, 1)
      G2.circle("fill", x, y, w / 2)
      G2.setColor(1, 1, 1, 0.95)
      G2.printf("X", x - 10, y - 7, 20 * L, "center", 0, 1 / L, 1 / L)
    end
    if s.message then
      local my = LH - BOTTOM_STRIP_H - 24
      G2.setColor(0, 0, 0, 0.6)
      G2.rectangle("fill", 6, my, 260, 20, 5, 5)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.push()
      G2.scale(1 / L, 1 / L)
      fitText(G2, s.message, 9 * L, my * L, 254 * L, 20 * L, "center")
      G2.pop()
    end
  end

  function app:draw(G2, w, h)
    setShape(h)
    local s = G.session
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local room = Store.room()
    if G.Decor then G.Decor.migrateRoom(room) end
    G2.push()
    G2.translate(0, -bleed())
    G2.scale(L, L)
    drawWallpaper(G2, room)
    if not s then G2.pop(); return end
    G2.push()
    G2.translate(0, D / 2)
    drawScene(G2, s, room)
    G2.pop()
    if P then
      if menu then
        -- the bubbles ride over the Pokemon (the layout parks them off to the right)
        for _, n in ipairs({ "g", "h", "5n" }) do
          P:set(n, "tx", pet.x - 160)
          P:set(n, "ty", 120 - pet.y)
        end
      end
      applyShape()
      P:draw(G2)
    end
    if switchOpen then
      G2.push()
      G2.translate(0, D / 2)
      drawSwitch(G2, s)
      G2.pop()
    end
    drawBottom(G2, s)
    if fade then
      local k = math.min(1, fade.t / FADE_S)
      G2.setColor(0, 0, 0, fade.dir > 0 and k or 1 - k)
      G2.rectangle("fill", 0, -20, 320, LH + 40)
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  function app:releaseAll()
    menu, switchOpen = nil, false
    if P then setMenu(false) end
  end
  function app.leave()
    app:releaseAll()
    fade = nil
    away = true
  end

  return app
end
