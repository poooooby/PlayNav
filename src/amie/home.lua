-- HOME: the Pokemon-Amie room on the bottom screen, laid out as the game's (kawaii_lower and
-- kawaii_windows, a/0/2/6 entry 0) and drawn here: the wallpaper, the placed decor, the
-- set-out puff, visitors, gifts and the wandering Pokemon in the layout's 320x240 units; over
-- them the scalloped frame (opening on entry), the menu (the dim and the PLAY / DECORATE /
-- SWITCH buttons) and, while the menu is up, the bubbles over the Pokemon that say how much it
-- wants Poke Puffs and play, with hearts for its affection. A puff set out in DECORATE falls
-- onto its spot. SWITCH is the party list. The pictures are src/amie/ui_art.lua's.
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
  -- an icon of another size (the Game Boy games' 16, another mod's HD 64) drawn the same size
  local function iconScale(ic) return 32 / ((ic and ic.w) or 32) end
  local RETURN = { 305, 224, 27, 27 }                       -- the blue return (closes), Super Training's
  local BOTTOM_STRIP_H = (240 - 217.5) * 30 / 24
  local FPS = 30

  -- the wandering Pokemon: x, y is its anchor (the layout's pane 8: icon above, shadow at +8)
  local pet = { x = 160, y = 150, tx = 160, ty = 150, facing = -1, state = "idle", timer = 1.2,
    frame = 0, frameT = 0, bounce = 0, hops = 0 }
  local menu = nil        -- { press = which, t } once open; press runs the button's bounce
  local sw = nil          -- SWITCH's screen while up: { phase, t, sel, press, heartT, after }
  local particles = {}
  local emote = nil
  local dance = nil
  local lastKey = nil
  local away = true       -- left the screen: the next frame on it opens the frame again
  local fade = nil        -- { t, dir = 1 out to black | -1 in from black, after = fn }
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

  -- ------- the room's own screen, drawn here in the layout's units (320 wide, LH tall; the
  -- game's kawaii_lower: the scalloped frame over everything, the menu's dim and buttons, the
  -- bubbles over the Pokemon, a set-out puff falling onto its spot). Timings are in the
  -- game's 30 fps frames. On a taller screen the room's contents sit D/2 lower and the
  -- buttons D lower; the frame and the dim stretch to the whole height.

  -- a value along keys { { frame, value }... }, straight between them, held past the ends
  local function track(keys, f)
    if f <= keys[1][1] then return keys[1][2] end
    for i = 2, #keys do
      local a, b = keys[i - 1], keys[i]
      if f <= b[1] then
        local t = (f - a[1]) / math.max(1e-6, b[1] - a[1])
        return a[2] + (b[2] - a[2]) * t
      end
    end
    return keys[#keys][2]
  end
  local function smooth(t) t = math.max(0, math.min(1, t)); return t * t * (3 - 2 * t) end

  -- the frame opening (window_open, 10 frames): the window grows from nothing about the
  -- middle as the lace's sides draw back with it, white at first, settling to 200/255
  local OPEN_F = 10
  local FRAME_ALPHA = 200 / 255
  local openF = nil            -- frames into the opening; nil once open
  local LILAC = { 212 / 255, 187 / 255, 245 / 255 }
  local function drawFrame(G2)
    local img = art("lyt/amie_room/frame")
    local f = openF or OPEN_F
    local s = smooth(f / OPEN_F)
    local a = f <= 5 and 1 or 1 + (FRAME_ALPHA - 1) * (f - 5) / 5
    local white = 1 - math.min(1, f / OPEN_F)
    -- the window's box: 320 across, as tall again stretched to the screen's height
    local hw, hh = 160 * s, 160 * s * LH / 240
    local cx, cy = 160, LH / 2
    local function paint(mode)
      if mode == "add" then G2.setColor(white, white, white, a) else G2.setColor(1, 1, 1, a) end
      if img and s > 0 then
        local iw, ih = img:getDimensions()
        local kx, ky = hw / iw, hh / ih
        -- the texture is the top-right quarter; the others mirror it
        G2.draw(img, cx, cy - hh, 0, kx, ky)
        G2.draw(img, cx, cy - hh, 0, -kx, ky)
        G2.draw(img, cx, cy + hh, 0, kx, -ky)
        G2.draw(img, cx, cy + hh, 0, -kx, -ky)
      end
      if s < 1 then
        if mode == "add" then G2.setColor(white, white, white, a) else G2.setColor(LILAC[1], LILAC[2], LILAC[3], a) end
        G2.rectangle("fill", -40, -40, cx - hw + 40, LH + 80)
        G2.rectangle("fill", cx + hw, -40, 360 - cx - hw, LH + 80)
        G2.rectangle("fill", cx - hw, -40, hw * 2, cy - hh + 40)
        G2.rectangle("fill", cx - hw, cy + hh, hw * 2, LH + 40 - cy - hh)
      end
    end
    paint("alpha")
    if white > 0 then
      G2.setBlendMode("add")
      paint("add")
      G2.setBlendMode("alpha")
    end
  end

  -- the menu: the room dimmed (black at 128) and the three buttons, D lower on a taller screen
  local MENU_BUTTONS = {   -- which, art, x, y, w, h (the hit box is the same)
    { "play", "ui/btn_play", 160, 181, 90, 54 },
    { "decorate", "ui/btn_decorate", 75, 180, 74, 46 },
    { "switch", "ui/btn_switch", 245, 180, 74, 46 },
  }
  local function buttonBox(which)
    for _, b in ipairs(MENU_BUTTONS) do
      if b[1] == which then return b[3] - b[5] / 2, b[4] + D - b[6] / 2, b[5], b[6] end
    end
  end

  -- the bubbles over the Pokemon while the menu is up: how much it wants puffs (the cake, left)
  -- and play (the note, right), its affection (hearts, middle); each kind sends up 1-5 of its
  -- icon by level, rising and swaying (okashi_hungryNN / asobi_playNN / heart_nakayosiNN)
  local RISES = {   -- by level: the loop's length, then { first frame, frames } of each rise
    { 60, { 0, 30 } },
    { 60, { 0, 30 }, { 30, 30 } },
    { 40, { 0, 20 }, { 10, 20 }, { 20, 20 } },
    { 60, { 0, 20 }, { 30, 20 }, { 10, 20 }, { 20, 20 } },
    { 70, { 0, 20 }, { 30, 20 }, { 10, 20 }, { 40, 20 }, { 20, 20 }, { 50, 20 } },
  }
  local bubbleF = 0
  local bubbleLevels = { 0, 0, 0 }   -- puffs, play, hearts
  local BUBBLE_KINDS = {   -- art, dx, size
    { "lyt/amie_room/icon_okashi", -35, 50 },
    { "lyt/amie_room/icon_asobi", 35, 50 },
    { "lyt/amie_room/particle_01", 0, 30 },
  }
  local function drawRise(G2, img, x, y, size, u, len)
    local slow = len >= 30
    local ty = track(slow and { { 0, 54 }, { 16, 76.6 }, { 30, 88 } } or { { 0, 54 }, { 10, 76.6 }, { 20, 88 } }, u)
    local a = track({ { 0, 0 }, { 5, 1 }, { slow and 25 or 10, 1 }, { len, 0 } }, u)
    local k = track(slow and { { 0, 1 }, { 8, 1.1 }, { 12, 1 } } or { { 0, 1 }, { 4, 1.1 }, { 8, 1 } }, u)
    local rz = track({ { 0, 0 }, { len / 2, -5 }, { len, 10 } }, u)
    if a <= 0 then return end
    local iw, ih = img:getDimensions()
    G2.setColor(1, 1, 1, a)
    -- the layout's turn is anticlockwise (y up): the other way on screen
    G2.draw(img, x, y - ty, -math.rad(rz), size * k / iw, size * k / ih, iw / 2, ih / 2)
  end
  local function drawBubbles(G2)
    local ax, ay = pet.x, pet.y + D / 2
    for i, kind in ipairs(BUBBLE_KINDS) do
      local lvl = bubbleLevels[i]
      local img = lvl > 0 and art(kind[1])
      if img then
        local plan = RISES[math.min(5, lvl)]
        local f = bubbleF % plan[1]
        for j = 2, #plan do
          local u = f - plan[j][1]
          if u >= 0 and u <= plan[j][2] then drawRise(G2, img, ax + kind[2], ay, kind[3], u, plan[j][2]) end
        end
      end
    end
  end

  -- a set-out puff falling onto its spot (okashi_fall, 10 frames): from above the screen,
  -- tilted, a little bounce
  local FALL_F = 10
  local fallF = nil
  local function fallY(f)
    return 120 - track({ { 0, 150 }, { 6, 24 }, { 8, 29 }, { 10, 24 } }, f)
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

  -- the guest seats are the visitors': the Pokemon does not stop on one
  local SEAT_CLEAR = 22
  local function onGuestSeat(x, y)
    for _, sp in ipairs(G.Decor and G.Decor.SEATS or {}) do
      if math.abs(x - sp.x) < SEAT_CLEAR and math.abs(y - sp.y) < SEAT_CLEAR then return true end
    end
    return false
  end

  -- a point in the floor band, away from the current spot and off the guest seats
  local function pickTarget()
    for _ = 1, 12 do
      local tx = FLOOR.x0 + math.random() * (FLOOR.x1 - FLOOR.x0)
      local ty = FLOOR.y0 + math.random() * (FLOOR.y1 - FLOOR.y0)
      if math.abs(tx - pet.x) + math.abs(ty - pet.y) > 50 and not onGuestSeat(tx, ty) then return tx, ty end
    end
    return (FLOOR.x0 + FLOOR.x1) / 2, (FLOOR.y0 + FLOOR.y1) / 2
  end

  -- ours: from this much enjoyment it plays more often
  local PLAYFUL = 200

  -- the Pokemon's mood decides what it does next
  local function nextBehaviour(s)
    local m = s.meters
    if s.status or (s.mon and (s.mon.hp or 1) <= 0) then return "nap", 3 end
    local r = math.random()
    local happy = (m.enjoyment or 0) >= PLAYFUL
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
    pet.hops = 0
    menu, sw = nil, nil
    lastKey = s.key
  end

  -- the menu's bubbles: how much it wants puffs and play (5 - level, none when full), and its
  -- affection level as hearts (drawBubbles)
  local function needs(s)
    local m = s.meters
    return math.max(0, 5 - Rules.level(m.fullness)), math.max(0, 5 - Rules.level(m.enjoyment)),
      Rules.level(m.affection)
  end
  local function showBubbles(on)
    local s = G.session
    local hungry, bored, hearts = 0, 0, 0
    if on and s then hungry, bored, hearts = needs(s) end
    bubbleLevels[1], bubbleLevels[2], bubbleLevels[3] = hungry, bored, hearts
    bubbleF = 0
  end

  local function setMenu(on)
    if on then
      menu = {}
      G.se("room_menu", "SE_SELECT")
    else
      menu = nil
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
  function app.buttonPos(which)
    local x, y, w, h = buttonBox(which)
    return (x + w / 2) * L, (y + h / 2) * L - bleed()
  end
  function app.closePos() return RETURN[1] * L, (RETURN[2] + D) * L - bleed() end
  function app.menuOpen() return menu ~= nil end
  -- a set-out puff is falling onto its spot
  function app.falling() return fallF ~= nil end
  -- something is still moving (a fade, a button's bounce, the frame opening, a puff falling)
  function app.busy()
    if fade or fallPending or (menu and menu.press) then return true end
    if openF or fallF then return true end
    return false
  end

  local function leaveFor(after)
    fade = { t = 0, dir = 1, after = after }
  end

  -- ------- SWITCH: the party list, sliding in from the right over the room (the game's
  -- kawaii_windows, drawn here in its units). A pink striped room under a lilac bar, the party
  -- in gold medallions with the heart on the one in the room, a ruled card with the chosen
  -- one's icon, name and meters (five hearts / cakes / notes, full or spent), "Switch Pokémon!"
  -- when the chosen one is another (it comes into the room), the return sliding the list away.
  -- On a taller screen the list sits up to 18 lower (SW_DOWN) and the foot (the guide line, its
  -- ribbon, the return) D lower; the pink runs on down to it.
  local SLIDE_S = 6 / FPS
  local PRESS = { 1, 0.9, 0.8, 0.9, 1, 0.95, 0.9, 0.95, 1 }   -- pokelist_select's bounce
  local SW_DOWN = 18
  local METERS = {   -- { label key, y, filled, spent, meter, w, h }
    { "affection", 90, "heart_00", "heart_01", "affection", 16, 16 },
    { "fullness", 115, "ic_hungry", "ic_hungry_black", "fullness", 16, 18 },
    { "enjoyment", 140, "ic_asobu", "ic_asobu_black", "enjoyment", 18, 18 },
  }
  local changeShown = false   -- the Switch button is up (another Pokemon chosen)
  local swName = ""
  local swLevels = { 0, 0, 0 }
  local function ease(f) f = math.max(0, math.min(1, f)); return 1 - (1 - f) ^ 3 end

  -- where things are (layout units on the screen, the slide left out): x, y, w, h
  local function swDown() return math.min(D, SW_DOWN) end
  local function swBox(what, i)
    local dn = swDown()
    if what == "slot" then return 35 + 50 * (i - 1) - 21, 54 + dn - 21, 42, 42 end
    if what == "heart" then return 20 + 50 * (i - 1) - 10, 44 + dn - 10, 20, 20 end
    if what == "icon" then return 73 - 20, 105 + dn - 15, 40, 30 end
    if what == "button" then return 160 - 139, 180 + dn - 26, 278, 52 end
    if what == "return" then return 305 - 15, 225 + D - 15, 30, 30 end
  end

  local function swParty()
    local party = host.party and host.party() or {}
    local out = {}
    for i = 1, math.min(6, #party) do out[i] = party[i] end
    return out
  end
  local function activeSlot(party)
    local s = G.session
    for i, m in ipairs(party) do if s and host.monKey(m) == s.key then return i end end
    return 1
  end

  -- the card for slot i: name, meters, and the button when it is another Pokemon
  local function showSelected(i)
    local party = swParty()
    local mon = party[i]
    if not mon then return end
    local egg = host.isEgg and host.isEgg(mon)
    swName = egg and "Egg" or (host.displayName and host.displayName(mon) or "?")
    local m = Store.meters(host.monKey(mon))
    for r, row in ipairs(METERS) do swLevels[r] = egg and 0 or Rules.level(m[row[5]] or 0) end
    changeShown = i ~= activeSlot(party) and not egg
  end

  local function openSwitch()
    local party = swParty()
    local act = activeSlot(party)
    sw = { phase = "in", t = 0, sel = act, heart = act, heartT = 1 }
    showSelected(act)
    G.se("room_button", "SE_SELECT")
  end

  local function closeSwitch(after)
    if not sw or sw.phase == "out" then return end
    sw.phase, sw.t, sw.after = "out", 0, after
  end

  local function inRect(ax, ay, x, y, w, h) return x and ax >= x and ax <= x + w and ay >= y and ay <= y + h end

  -- a press: its bounce, then its work (stepSwitch)
  local function switchPointer(ax, ay)
    if not (sw and sw.phase == "open" and not sw.press) then return end
    local party = swParty()
    if inRect(ax, ay, swBox("return")) then
      G.se("back", "SE_SELECT")
      sw.press = { what = "return", t = 0, act = function() closeSwitch() end }
      return
    end
    if changeShown and inRect(ax, ay, swBox("button")) and sw.sel ~= activeSlot(party)
      and not (host.isEgg and host.isEgg(party[sw.sel])) then
      G.se("switch_to", "SE_SUCCESS")
      local i = sw.sel
      sw.press = { what = "button", t = 0, act = function()
        if G.switchTo(party[i]) then
          sw.heart, sw.heartT = i, 0
          showSelected(i)
          sw.wait = 0.45   -- the heart settles on it, then the list goes
        end
      end }
      return
    end
    for i = 1, #party do
      if inRect(ax, ay, swBox("slot", i)) then
        G.se("select", "SE_SELECT")
        sw.press = { what = "slot", i = i, t = 0, act = function()
          if host.isEgg and host.isEgg(party[i]) then G.say(G.tx("egg"), 2.5) end
          sw.sel = i
          showSelected(i)
        end }
        return
      end
    end
  end

  local function stepSwitch(dt)
    sw.t = sw.t + dt
    sw.heartT = math.min(1, (sw.heartT or 1) + dt / SLIDE_S)
    if sw.press then
      local p = sw.press
      p.t = p.t + dt
      local f = math.floor(p.t * FPS) + 1
      p.k = PRESS[math.min(#PRESS, f)]
      if f > #PRESS then
        sw.press = nil
        p.act()
      end
    end
    if sw.wait then
      sw.wait = sw.wait - dt
      if sw.wait <= 0 then
        sw.wait = nil
        -- the room again: the new Pokemon comes in after a moment
        closeSwitch(function() resetFor(G.session); pet.enterT = 0.4 end)
      end
    end
    if sw.phase == "in" and sw.t >= SLIDE_S then sw.phase, sw.t = "open", 0 end
    if sw.phase == "out" and sw.t >= SLIDE_S then
      local after = sw.after
      sw = nil
      if after then after() end
    end
  end

  local function swOffset()
    if not sw then return 320 end
    if sw.phase == "in" then return 320 * (1 - ease(sw.t / SLIDE_S)) end
    if sw.phase == "out" then return 320 * ease(sw.t / SLIDE_S) end
    return 0
  end

  -- for the driver: where to tap on the list (app units) and its state
  function app.switchPos(what, i)
    if not sw then return nil end
    local x, y, w, h = swBox(what == "slot" and "slot" or what, i or 1)
    if not x then return nil end
    return (x + swOffset() + w / 2) * L, (y + h / 2) * L - bleed()
  end
  function app.switchState()
    if not sw then return nil end
    return { phase = sw.phase, sel = sw.sel, heart = sw.heart, pressing = sw.press ~= nil, waiting = sw.wait ~= nil }
  end

  -- text in a box the way the game's text panes set it: its 19-unit font rasterised at the
  -- size it lands on screen, black, centred on the box's height, squeezed if too wide
  local swFonts = {}
  local function swText(G2, text, x, y, w, h, align)
    local x0, y0 = G2.transformPoint(0, 0)
    local x1, y1 = G2.transformPoint(0, 1)
    local k = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    if k <= 0 then return end
    local size = math.max(4, math.floor(19 * k * 0.64 + 0.5))
    local font = swFonts[size]
    if font == nil then
      local ok, f = pcall(mod.cjk and mod.cjk.newFont or G2.newFont, size)
      font = ok and f or false
      swFonts[size] = font
    end
    if not font then return end
    local inv = 1 / k
    local lw, lh = font:getWidth(text) * inv, font:getHeight() * inv
    local sx = lw > w and w / lw or 1
    local tx = align == "left" and x or x + (w - lw * sx) / 2
    G2.setFont(font)
    G2.setColor(0, 0, 0, 1)
    G2.print(text, tx, y + (h - lh) / 2, 0, inv * sx, inv)
  end

  -- an image drawn into a box about its middle, scaled by k
  local function swImage(G2, id, x, y, w, h, k, sx, sy)
    local img = art(id)
    if not img then return end
    k = k or 1
    local iw, ih = img:getDimensions()
    G2.draw(img, x + w / 2, y + h / 2, 0, (sx or 1) * w * k / iw, (sy or 1) * h * k / ih, iw / 2, ih / 2)
  end

  -- a band of the lilac bar (its corner mirrored for the right end, its inner column between),
  -- the torn edge down, or up when flip
  local barQuads = {}
  local pinkQuad = nil
  local function bar(G2, y, flip)
    local img = art("lyt/amie_room/bar_title")
    if not img then return end
    local iw, ih = img:getDimensions()
    local q = barQuads[img]
    if not q then q = love.graphics.newQuad(iw - 1, 0, 1, ih, iw, ih); barQuads[img] = q end
    local sy = flip and -1 or 1
    local oy = flip and y + ih or y
    G2.draw(img, 0, oy, 0, 1, sy)
    G2.draw(img, 320, oy, 0, -1, sy)
    G2.draw(img, q, iw, oy, 0, 320 - 2 * iw, sy)
  end

  local function drawSwitch(G2, s)
    local off = swOffset()
    local dn = swDown()
    local party = swParty()
    local p = sw.press
    local function pk(what, i) return p and p.what == what and (i == nil or p.i == i) and p.k or 1 end
    G2.push()
    G2.translate(off, 0)
    G2.setColor(1, 1, 1, 1)
    -- the pink room, the bar along the top and its twin at the foot
    local pink = art("lyt/amie_room/goods_win_c")
    if pink then
      pink:setWrap("repeat", "repeat")
      local iw, ih = pink:getDimensions()
      local h = 220 + D
      if not (pinkQuad and pinkQuad.h == h and pinkQuad.img == pink) then
        pinkQuad = { h = h, img = pink, q = love.graphics.newQuad(0, 0, 320 / 18 * iw, h / 18 * ih, iw, ih) }
      end
      G2.draw(pink, pinkQuad.q, 0, 10, 0, 18 / iw, 18 / ih)
    end
    -- the top bar, its torn foot reaching under the ribbon below the title (which comes down
    -- with the list): the window's own corner stops a few units short of it
    bar(G2, -8)
    bar(G2, dn)
    -- the foot's bar, turned over, and a second one higher over it: its body covers the first's
    -- torn edge, its own torn edge goes under the guide line's ribbon
    bar(G2, 212 + D, true)
    bar(G2, 200 + D, true)
    -- the card, the ribbons, the return, the guide line
    swImage(G2, "lyt/amie_room/win_pokelist", 11, 74 + dn, 298, 80)
    swImage(G2, "lyt/amie_room/goods_win_line_dw", 0, 186 + D, 320, 26)
    swImage(G2, "lyt/amie_room/goods_win_line_up", 0, 26 + dn, 320, 26)
    local rx, ry, rw, rh = swBox("return")
    swImage(G2, "lyt/amie_room/button_back", rx, ry, rw, rh, pk("return"))
    swText(G2, G.tx("selectMon"), 4, 215 + D, 280, 20, "left")
    -- the title on its paper tab (the tab's corner, mirrored round)
    for _, m in ipairs({ { 20, 1, 1 }, { 160, -1, 1 }, { 20, 1, -1 }, { 160, -1, -1 } }) do
      local ty = m[3] > 0 and -2 or 16
      G2.setColor(1, 1, 1, 1)
      swImage(G2, "lyt/amie_room/bg_tab", m[1], ty + dn, 140, 18, 1, m[2], m[3])
    end
    swText(G2, G.tx("switch"), 25, 6 + dn, 270, 20, "center")
    -- the party's medallions
    for i = 1, #party do
      local x, y, w, h = swBox("slot", i)
      G2.setColor(1, 1, 1, 1)
      swImage(G2, "lyt/amie_room/button_pokemon", x, y, w, h, pk("slot", i))
    end
    -- the card's words and meters
    swText(G2, swName, 23, 120 + dn, 100, 20, "center")
    for r, row in ipairs(METERS) do
      swText(G2, G.tx(row[1]), 134, row[2] + dn - 10, 70, 20, "left")
      for j = 1, 5 do
        G2.setColor(1, 1, 1, 1)
        local cx = 214 + 20 * (j - 1)
        swImage(G2, "lyt/amie_room/" .. (j <= swLevels[r] and row[3] or row[4]), cx - row[6] / 2, row[2] + dn - row[7] / 2, row[6], row[7])
      end
    end
    -- the Switch button
    if changeShown then
      local x, y, w, h = swBox("button")
      local k = pk("button")
      G2.setColor(1, 1, 1, 1)
      swImage(G2, "lyt/amie_room/button_change", x, y, w, h, k)
      G2.push()
      G2.translate(160, y + h / 2); G2.scale(k, k); G2.translate(-160, -(y + h / 2))
      swText(G2, G.tx("switch"), 75, y + h / 2 - 10, 190, 20, "left")
      G2.pop()
    end
    -- the heart on the Pokemon in the room: on its medallion's corner, popping in when moved
    if sw.heart and sw.heart <= #party then
      local x, y, w, h = swBox("heart", sw.heart)
      local k = 2 - ease(sw.heartT)
      G2.setColor(1, 1, 1, 1)
      swImage(G2, "lyt/amie_room/heart_00", x + w / 2 - 8, y + h / 2 - 8, 16, 16, k)
    end
    -- the party icons in the medallions and the chosen one's on the card
    local function icon(mon, x, y, w, h, k)
      local ic = mon and host.icon and host.icon(mon)
      if not (ic and ic.image and ic.quads) then return end
      local q = ic.quads[math.floor(love.timer.getTime() * 3) % (ic.frames or 1)] or ic.quads[0]
      G2.setColor(1, 1, 1, 1)
      local kk = k * iconScale(ic)
      drawPixel(ic.image, q, x + w / 2, y + h / 2 + 4, 0, kk, kk, (ic.w or 32) / 2, (ic.h or 32) / 2 + 4 / iconScale(ic))
    end
    for i, mon in ipairs(party) do
      local x, y, w, h = swBox("slot", i)
      icon(mon, x, y, w, h, 1.15 * pk("slot", i))
    end
    local x, y, w, h = swBox("icon")
    icon(party[sw.sel], x, y, w, h, 1.25)
    G2.pop()
  end

  -- ------- input

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "home") or fade then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local lx, ly = toLow(ev.x, ev.y)
    -- SWITCH first: its return sits over the room's
    if sw then switchPointer(ev.x / L, (ev.y + bleed()) / L); return end
    if math.abs(lx - RETURN[1]) <= 20 and math.abs(ly - RETURN[2]) <= 20 then G.finish(); return end
    local x, y = toRoom(ev.x, ev.y)
    if menu then
      if menu.press then return end
      -- the menu's buttons
      local ax, ay = ev.x / L, (ev.y + bleed()) / L
      for _, b in ipairs(MENU_BUTTONS) do
        local which = b[1]
        local bx, by, bw, bh = buttonBox(which)
        if ax >= bx and ax <= bx + bw and ay >= by and ay <= by + bh then
          G.se("select", "SE_SELECT")
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
          G.se("gift", "SE_SUCCESS")
          G.say(text, 3.5)
          showEmote("emote/happy", 1.5)
          spawn("heart", gx, gy - 12, 3)
        end
        return
      end
    end
    -- on the Pokemon: the menu; near it: it looks over
    local dx, dy = x - pet.x, y - (pet.y - 14)
    if dx * dx + dy * dy <= 28 ^ 2 then
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
    elseif which == "switch" then openSwitch()
    else
      -- DECORATE: the room fades to black first
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
    openF = 0
    setMenu(false)
    -- back from DECORATE: up from black; a puff just set out falls onto its spot
    if s.fromDecorate then
      fade = { t = 0, dir = -1 }
      s.fromDecorate = nil
    end
    -- (it falls once the room is up from black: held back until the fade ends)
    if s.puffDrop then
      s.puffDrop = nil
      fallPending = true
    end
  end

  function app:update(dt)
    local s = G.session
    if not (s and s.mode == "home") then
      app.live = false
      return
    end
    if s.key ~= lastKey then resetFor(s) end
    if away then onEnter(s) end
    local df = (dt or 0) * FPS
    if openF then openF = openF + df; if openF >= OPEN_F then openF = nil end end
    if fallF then fallF = fallF + df; if fallF >= FALL_F then fallF = nil end end
    bubbleF = bubbleF + df
    if fade then
      fade.t = fade.t + (dt or 0)
      if fade.t >= FADE_S then
        local after = fade.after
        fade = nil
        if after then after() end
      end
    end
    if fallPending and not fade then
      fallPending = false
      fallF = 0
    end
    if menu and menu.press then
      menu.press.t = menu.press.t + (dt or 0)
      local f = math.floor(menu.press.t * FPS) + 1
      menu.press.k = BOUNCE[math.min(#BOUNCE, f)]
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
    if sw then stepSwitch(dt or 0) end
    if pet.enterT then
      pet.enterT = pet.enterT - (dt or 0)
      if pet.enterT <= 0 then pet.enterT = nil; pet.bounce = 10; host.playCry(s.mon) end
    end
    if pet.bounce and pet.bounce > 0 and not dance and pet.state ~= "play" then pet.bounce = math.max(0, pet.bounce - 60 * (dt or 0)) end
    if G.Visitors and not menu and not sw then G.Visitors.update(dt) end

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
    elseif pet.state == "play" then
      pet.frameT = pet.frameT + dt
      if pet.frameT >= 0.12 then pet.frameT = 0; pet.frame = 1 - pet.frame end
      -- a hop about every 0.6 s
      pet.bounce = math.abs(math.sin(pet.timer * 5)) * 8
      if pet.timer <= 0 then pet.bounce = 0; pet.state, pet.timer = "idle", 1 end
    else
      pet.frameT = pet.frameT + dt
      local rate = (pet.state == "nap") and 1.2 or 0.5
      if pet.frameT >= rate then pet.frameT = 0; pet.frame = 1 - pet.frame end
      if pet.state == "nap" and pet.frameT < dt * 1.5 and math.random() < 0.5 then spawn("zzz", pet.x + 12, pet.y - 40, 1) end
      if pet.timer <= 0 and not menu and not sw then
        local st, t = nextBehaviour(s)
        pet.state, pet.timer = st, t
      elseif pet.timer <= 0 then
        pet.timer = 1
      end
    end

    -- milestones
    for _, ev in ipairs(G.takeEvents()) do
      if ev.kind == "dance" then dance = { cries = ev.cries, t = 0, next = 0 }
      elseif ev.kind == "gift" then
        G.say(("%s wants to give you something!"):format(s.name), 3)
        showEmote("emote/love", 2)
        if mod.haptics then mod.haptics.pattern("big") end; G.se("milestone_gift")
      end
    end
    if dance then
      dance.t = dance.t + dt
      if dance.t >= dance.next then
        dance.next = dance.next + 0.6
        dance.cries = dance.cries - 1
        pet.bounce = 15
        if mod.haptics then mod.haptics.pulse("medium") end; G.se("dance")   -- each step of its dance
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
  -- k: the bubble's scale, a: its alpha (the talk clips pop it in and fade it out)
  local function drawTalk(G2, x, y, word, k, a)
    k, a = k or 1, a or 1
    local bub = art("lyt/amie_room/talk_bubble_L")
    local sym = TALK[word] and art("lyt/amie_room/" .. TALK[word])
    if bub then
      local bw, bh = bub:getDimensions()
      G2.setColor(1, 1, 1, a)
      G2.draw(bub, x, y, 0, 32 * k / bw, 32 * k / bh, bw / 2, bh / 2)
      if sym then
        local sw, sh = sym:getDimensions()
        G2.draw(sym, x, y, 0, 32 * k / sw, 32 * k / sh, sw / 2, sh / 2)
        return
      end
    else
      G2.setColor(1, 1, 1, 0.95 * a); G2.circle("fill", x, y, 15 * k, 16)
    end
    G2.setColor(0.1, 0.1, 0.15, a)
    G2.printf(word, x - 25, y - 8, 50 * L, "center", 0, 1 / L, 1 / L)
  end

  -- where a visitor's bubble goes: centred over the visitor (the game's talk panes 2o / 2r / 2w
  -- sit 1 right of seats 5d / 5b / 5c), its foot just on the head of the icon as we draw it
  -- (feet at y + 10, the icon's figure ~30 tall). The side seats land 4 above the game's 94;
  -- the middle pane (160,78) would cover our taller sprite's head, so it rides above it too.
  local TALK_DX, TALK_DY = 1, -33
  function app.talkAt(v)
    return v.x + TALK_DX, v.y + TALK_DY
  end
  -- the talk clips (30 fps): scale 0 -> 1.1 at frame 3 -> 1 at 5; the last 3 frames fade out
  local function talkPose(age, left)
    local f = age * 30
    local k = f < 3 and (1.1 * f / 3) or (f < 5 and (1.1 - 0.1 * (f - 3) / 2) or 1)
    local a = math.max(0, math.min(1, left * 10))
    return k, a
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
    if fallF then y = fallY(fallF) end
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
    if pet.enterT then return end
    drawShadow(G2, pet.x, pet.y + 8, 23)
    local icon = s.icon
    local by = pet.y + 10 - (pet.bounce or 0)
    if icon and icon.image and icon.quads then
      local q = icon.quads[pet.frame % (icon.frames or 1)] or icon.quads[0]
      G2.setColor(1, 1, 1, 1)
      if pet.state == "nap" then G2.setColor(0.8, 0.8, 0.9, 1) end
      local k = ICON_K * iconScale(icon)
      drawPixel(icon.image, q, pet.x, by, 0, k * -pet.facing, k, (icon.w or 32) / 2, icon.h or 32)
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
      local k = ICON_K * iconScale(ic)
      drawPixel(ic.image, q, v.x, v.y + 10, 0, k * -v.facing, k, (ic.w or 32) / 2, ic.h or 32)
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

  -- the room's contents: the decor and the set-out puff by depth, then the visitors and the
  -- Pokemon by depth over all of them (they never pass behind an item); gifts; chat
  -- the items and visitors are sorted as they are (they carry y); the puff and the Pokemon
  -- ride in two reused records, so a frame's depth sort allocates nothing
  local floor, actors = {}, {}
  local puffRec, petRec = { y = 0, puff = nil }, { y = 0, pet = true }
  local function byY(a, b) return a.y < b.y end
  local function drawScene(G2, s, room)
    for i = #floor, 1, -1 do floor[i] = nil end
    for i = #actors, 1, -1 do actors[i] = nil end
    for _, it in ipairs(room.items or {}) do floor[#floor + 1] = it end
    if room.puffOut and not fallPending then
      puffRec.y, puffRec.puff = (G.Decor and G.Decor.PUFF_SPOT.y or 116), room.puffOut
      floor[#floor + 1] = puffRec
    end
    for _, v in ipairs(G.Visitors and G.Visitors.present or {}) do actors[#actors + 1] = v end
    petRec.y = pet.y
    actors[#actors + 1] = petRec
    table.sort(floor, byY)
    table.sort(actors, byY)
    for _, d in ipairs(floor) do
      if d == puffRec then drawPuff(G2, d.puff) else drawItem(G2, d) end
    end
    for _, d in ipairs(actors) do
      if d == petRec then drawPet(G2, s) else drawVisitor(G2, d) end
    end
    local grp = G.Visitors and G.Visitors.group
    if grp and grp.bubble then
      local b = grp.bubble
      local v = G.Visitors.present[b.who]
      if v then
        local tx, ty = app.talkAt(v)
        local k, a = talkPose((b.life or 1.4) - b.t, b.t)
        drawTalk(G2, tx, ty, b.word, k, a)
      end
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
    if menu then
      G2.setColor(0, 0, 0, 128 / 255)
      G2.rectangle("fill", -40, -40, 400, LH + 80)
      for _, b in ipairs(MENU_BUTTONS) do
        local img = art(b[2])
        if img then
          local k = menu.press and menu.press.which == b[1] and menu.press.k or 1
          local iw, ih = img:getDimensions()
          G2.setColor(1, 1, 1, 1)
          G2.draw(img, b[3], b[4] + D, 0, b[5] * k / iw, b[6] * k / ih, iw / 2, ih / 2)
        end
      end
      drawBubbles(G2)
    end
    drawFrame(G2)
    drawBottom(G2, s)
    if sw then
      G2.push("all")
      local ok, err = pcall(drawSwitch, G2, s)
      G2.pop()
      if not ok then mod.log:warn("amie switch screen: %s", tostring(err)) end
    end
    if fade then
      local k = math.min(1, fade.t / FADE_S)
      G2.setColor(0, 0, 0, fade.dir > 0 and k or 1 - k)
      G2.rectangle("fill", 0, -20, 320, LH + 40)
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  function app:releaseAll()
    menu, sw = nil, nil
    setMenu(false)
  end
  function app.leave()
    app:releaseAll()
    fade = nil
    away = true
  end

  return app
end
