-- DECORATE: the room with a drawer along the bottom. WALL lists the owned
-- wallpapers (tap to apply), CUSHION and OBJECT the owned items (drag one
-- up into the room to place it, up to 30; drag a placed item to move it,
-- or down into the drawer to take it away), PUFF sets a Poke Puff out for
-- visitors. DONE returns to the room. Rules: src/amie/decor.lua.

return function(mod, Pointer, G, Decor, Rules, Store, host)

  -- a line that fits its strip: wrapped, and drawn smaller if it still runs over (src/textfit.lua)
  local function fitText(G2, text, x, y, w, h, align)
    local TF = mod.textfit
    local font = G2.getFont()
    if TF and font then return TF.print(G2, font, text, x, y, w, h, align) end
    G2.printf(text, x, y, w, align or "center")
  end
  local app = { id = "decorate", title = "DECOR", live = true }

  function app:wantsSurface() return G.session ~= nil and G.session.mode == "decorate" end

  local W, H = 256, 178
  local DRAWER = { y = 126, h = 52 }
  local TABS = { "wall", "cushion", "object", "puff" }
  local TAB_LABEL = { wall = "WALL", cushion = "CUSHION", object = "OBJECT", puff = "PUFF" }
  local TAB = { y = 126, h = 14, w = 46 }
  local ROW = { y = 142, h = 34, slot = 34, perPage = 6 }
  local ARROW_L = { x = 2, y = 144, w = 18, h = 30 }
  local ARROW_R = { x = 236, y = 144, w = 18, h = 30 }
  local DONE = { x = 206, y = 128, w = 46, h = 12 }
  local FLOOR = { y0 = 60, y1 = 160 }     -- where items may stand (their feet); the drawer is away while one is held
  local PUT_AWAY = { y = H - 14, h = 14 } -- the strip that takes an item back while the drawer is away
  local drawerT = 1                        -- 1 the drawer is up, 0 slid away (while an item is held)
  local PLATE = { x = 212, y = 72 }       -- where the set-out puff sits
  -- The screen's shape (as home.lua): items live in the room's 178-row coordinates; on a
  -- taller screen the room scene draws DH/2 lower (RO, the same as the room screen, so an
  -- item lands where it was put) and the drawer, its tabs, row, arrows, DONE and the
  -- put-away strip go to the bottom (DH). DH = 0 on the 3DS shape.
  local DH, RO = 0, 0
  local function setShape(h)
    local dh = math.max(0, (h or H) - H)
    if dh == DH then return end
    DH, RO = dh, dh / 2
    DRAWER.y, TAB.y, ROW.y = 126 + DH, 126 + DH, 142 + DH
    ARROW_L.y, ARROW_R.y, DONE.y = 144 + DH, 144 + DH, 128 + DH
    PUT_AWAY.y = H - 14 + DH
  end
  app.setShape = setShape

  local tab = "cushion"
  local page = { wall = 1, cushion = 1, object = 1, puff = 1 }
  local drag = nil   -- { id, x, y, pointer, fromRoom = index | nil }

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local function inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
  end

  local function tabX(i) return 4 + (i - 1) * (TAB.w + 2) end
  local function slotX(i) return 24 + (i - 1) * ROW.slot end

  local function records()
    local decor = Decor.ensure(Store.decor())
    local room = Decor.ensureRoom(Store.room(), decor)
    return decor, room
  end

  -- the rows the current tab shows
  local function entries()
    local decor, room = records()
    if tab == "puff" then
      local out = {}
      for _, p in ipairs(Rules.ownedPuffs(Store.puffs())) do out[#out + 1] = { id = p.id, name = p.name, count = p.count } end
      return out
    end
    local out = {}
    for _, r in ipairs(Decor.owned(decor, tab)) do out[#out + 1] = { id = r.id, name = r.name } end
    return out
  end

  local function pages(list)
    local n = math.max(1, math.ceil(#list / ROW.perPage))
    page[tab] = math.min(math.max(page[tab] or 1, 1), n)
    return n
  end

  local function entryAt(x, y)
    if y < ROW.y or y > ROW.y + ROW.h then return nil end
    local list = entries()
    pages(list)
    local i = math.floor((x - 24) / ROW.slot) + 1
    if i < 1 or i > ROW.perPage then return nil end
    local e = list[(page[tab] - 1) * ROW.perPage + i]
    return e, i
  end

  local function floorY(y) return math.min(FLOOR.y1, math.max(FLOOR.y0, y)) end

  -- for the driver and tests
  app.drawerT = function() return drawerT end
  function app.geometry()
    return { TAB = TAB, tabX = tabX, slotX = slotX, ROW = ROW, DONE = DONE, DRAWER = DRAWER, ARROW_L = ARROW_L, ARROW_R = ARROW_R }
  end
  function app.setTab(t) tab = t end

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "decorate") then return end
    local decor, room = records()
    if ev.phase == "pressed" then
      if drawerT > 0.5 then
        if inRect(ev.x, ev.y, DONE) then rec.decorDone = true; return end
        for i, t in ipairs(TABS) do
          if inRect(ev.x, ev.y, { x = tabX(i), y = TAB.y, w = TAB.w, h = TAB.h }) then rec.decorTab = t; return end
        end
        if inRect(ev.x, ev.y, ARROW_L) then rec.decorArrow = -1; return end
        if inRect(ev.x, ev.y, ARROW_R) then rec.decorArrow = 1; return end
        local e = entryAt(ev.x, ev.y)
        if e then
          if tab == "cushion" or tab == "object" then
            drag = { id = e.id, x = ev.x, y = ev.y, pointer = ev.id }
          else
            rec.decorEntry = e.id
          end
          return
        end
      end
      -- a placed item anywhere, the drawer's empty parts included (items may stand under it)
      local idx = Decor.itemAt(room, ev.x, ev.y - RO, 4)
      if idx then
        local it = room.items[idx]
        drag = { id = it.id, x = ev.x, y = ev.y, pointer = ev.id, fromRoom = idx, ox = it.x - ev.x, oy = it.y - (ev.y - RO) }
      end
    elseif ev.phase == "moved" then
      if drag and drag.pointer == ev.id then drag.x, drag.y = ev.x, ev.y end
    else
      if drag and drag.pointer == ev.id then
        local d = drag
        drag = nil
        if ev.phase ~= "released" then return end
        if d.fromRoom then
          if ev.y >= PUT_AWAY.y then
            Decor.remove(room, d.fromRoom)
            host.playSe("SE_SELECT")
            G.say(("Put the %s away."):format(Decor.name(d.id)), 1.5)
          else
            Decor.move(room, d.fromRoom, ev.x + (d.ox or 0), floorY(ev.y - RO + (d.oy or 0)))
          end
        elseif ev.y < PUT_AWAY.y then
          local ok, why = Decor.place(room, decor, d.id, ev.x, floorY(ev.y - RO))
          if ok then host.playSe("SE_PIN")
          elseif why == "full" then G.say(G.tx("roomFull", nil, "The room is full (30 items)."), 2) end
        end
        Store.saveRoom()
        return
      end
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) then
        if rec.decorDone and inRect(ev.x, ev.y, DONE) then
          Store.saveRoom()
          G.enterHome(false)
        elseif rec.decorTab then
          tab = rec.decorTab
          host.playSe("SE_SELECT")
        elseif rec.decorArrow then
          local n = pages(entries())
          page[tab] = math.min(math.max((page[tab] or 1) + rec.decorArrow, 1), n)
        elseif rec.decorEntry then
          if tab == "wall" then
            if Decor.setWallpaper(room, decor, rec.decorEntry) then host.playSe("SE_SELECT"); Store.saveRoom() end
          elseif tab == "puff" then
            local ok = Decor.setPuffOut(room, Store.puffs(), rec.decorEntry)
            if ok then
              host.playSe("SE_SELECT")
              Store.savePuffs(); Store.saveRoom()
              G.say(("Set out a %s for visitors."):format(Rules.puffName(rec.decorEntry)), 2.5)
              if G.Visitors then
                if G.Visitors.sendOff then G.Visitors.sendOff() elseif G.Visitors.reset then G.Visitors.reset() end
              end
            end
          end
        end
      end
      rec.decorDone, rec.decorTab, rec.decorArrow, rec.decorEntry = nil, nil, nil, nil
    end
  end

  function app:update(dt)
    local s = G.session
    -- the drawer slides away while an item is held, so it can be set down where the drawer was
    local target = drag and 0 or 1
    drawerT = drawerT + (target - drawerT) * math.min(1, (dt or 0) * 12)
    if math.abs(target - drawerT) < 0.01 then drawerT = target end
    app.live = s ~= nil and s.mode == "decorate" and (drag ~= nil or drawerT ~= target)
  end

  -- ------- drawing

  local function drawItem(G2, id, x, y, scale, alpha)
    local img = art(id)
    scale = scale or 1
    G2.setColor(1, 1, 1, alpha or 1)
    if img then
      local iw, ih = img:getDimensions()
      G2.draw(img, x, y, 0, scale, scale, iw / 2, ih)
    else
      local r = Decor.get(id)
      local w, h = (r and r.w or 40) * scale, (r and r.h or 40) * scale * 0.6
      G2.setColor(0.8, 0.6, 0.4, alpha or 1)
      G2.rectangle("fill", x - w / 2, y - h, w, h, 4, 4)
      G2.setColor(0.1, 0.1, 0.15, alpha or 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf((r and r.name or "?"):sub(1, 1), x - w / 2, y - h / 2 - 5, w, "center")
      if app.font then G2.setFont(app.font) end
    end
  end
  app.drawItem = drawItem

  function app:draw(G2, w, h)
    local s = G.session
    setShape(h)
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local decor, room = records()
    local bg = art(room.wallpaper) or art("bg/plain")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local bl = app.bleed or 0
      local sc = math.max(w / bw, (h + bl) / bh)
      G2.draw(bg, (w - bw * sc) / 2, -bl + (h + bl - bh * sc) / 2, 0, sc, sc)
    else
      G2.setColor(0.98, 0.86, 0.45, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    end
    if not s then return end
    -- the room scene, RO lower (as on the room screen)
    G2.push()
    G2.translate(0, RO)
    -- placed items by depth
    local order = {}
    for i, it in ipairs(room.items or {}) do order[#order + 1] = { i = i, it = it } end
    table.sort(order, function(a, b) return (a.it.y or 0) < (b.it.y or 0) end)
    for _, o in ipairs(order) do
      if not (drag and drag.fromRoom == o.i) then drawItem(G2, o.it.id, o.it.x, o.it.y, 1, 1) end
    end
    -- the puff set out
    if room.puffOut then
      local img = art(room.puffOut)
      G2.setColor(1, 1, 1, 0.9)
      G2.ellipse("fill", PLATE.x, PLATE.y + 2, 14, 5)
      if img then G2.setColor(1, 1, 1, 1); G2.draw(img, PLATE.x, PLATE.y - 8, 0, 0.5, 0.5, 20, 20)
      else G2.setColor(0.95, 0.55, 0.2, 1); G2.ellipse("fill", PLATE.x, PLATE.y - 6, 8, 6) end
    end
    G2.pop()
    -- the drawer (slid down out of view while an item is held)
    G2.push()
    G2.translate(0, (1 - drawerT) * (DRAWER.h + 2))
    G2.setColor(0.12, 0.12, 0.18, 0.88)
    G2.rectangle("fill", 0, DRAWER.y, w, DRAWER.h)
    for i, t in ipairs(TABS) do
      local lit = t == tab
      G2.setColor(lit and 0.95 or 0.3, lit and 0.9 or 0.3, lit and 0.7 or 0.36, 1)
      G2.rectangle("fill", tabX(i), TAB.y, TAB.w, TAB.h, 3, 3)
      G2.setColor(lit and 0.1 or 0.9, lit and 0.1 or 0.9, lit and 0.1 or 0.9, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(TAB_LABEL[t], tabX(i), TAB.y + 2, TAB.w, "center")
      if app.font then G2.setFont(app.font) end
    end
    local list = entries()
    local n = pages(list)
    local first = (page[tab] - 1) * ROW.perPage
    if app.smallFont then G2.setFont(app.smallFont) end
    for i = 1, ROW.perPage do
      local e = list[first + i]
      if not e then break end
      local sx = slotX(i)
      G2.setColor(1, 1, 1, 0.12)
      G2.rectangle("fill", sx + 1, ROW.y, ROW.slot - 2, ROW.h, 4, 4)
      if tab == "wall" then
        local thumb = art(Decor.thumbOf(e.id))
        if thumb then
          G2.setColor(1, 1, 1, 1)
          G2.draw(thumb, sx + ROW.slot / 2, ROW.y + 14, 0, 0.6, 0.6, 20, 20)
        else
          G2.setColor(0.6, 0.5, 0.7, 1)
          G2.rectangle("fill", sx + 5, ROW.y + 3, ROW.slot - 10, 20, 3, 3)
        end
        if room.wallpaper == e.id then
          G2.setColor(1, 0.9, 0.3, 1)
          G2.rectangle("line", sx + 1, ROW.y, ROW.slot - 2, ROW.h, 4, 4)
        end
      elseif tab == "puff" then
        local img = art(e.id)
        if img then G2.setColor(1, 1, 1, 1); G2.draw(img, sx + ROW.slot / 2, ROW.y + 14, 0, 0.5, 0.5, 20, 20)
        else G2.setColor(0.95, 0.55, 0.2, 1); G2.ellipse("fill", sx + ROW.slot / 2, ROW.y + 14, 8, 6) end
        G2.setColor(1, 1, 1, 1)
        G2.printf(tostring(e.count), sx, ROW.y + 24, ROW.slot, "center")
      else
        local r = Decor.get(e.id)
        local k = math.min(1, 26 / math.max(r and r.w or 40, r and r.h or 40))
        drawItem(G2, e.id, sx + ROW.slot / 2, ROW.y + 30, k, 1)
      end
    end
    if #list == 0 then
      G2.setColor(1, 1, 1, 0.8)
      G2.printf(tab == "puff" and "No Poke Puffs" or "Nothing owned yet", 24, ROW.y + 12, 204, "center")
    end
    if n > 1 then
      G2.setColor(1, 1, 1, page[tab] > 1 and 1 or 0.3)
      G2.polygon("fill", ARROW_L.x + 14, ARROW_L.y + 6, ARROW_L.x + 14, ARROW_L.y + 24, ARROW_L.x + 4, ARROW_L.y + 15)
      G2.setColor(1, 1, 1, page[tab] < n and 1 or 0.3)
      G2.polygon("fill", ARROW_R.x + 4, ARROW_R.y + 6, ARROW_R.x + 4, ARROW_R.y + 24, ARROW_R.x + 14, ARROW_R.y + 15)
      G2.setColor(1, 1, 1, 0.8)
      G2.printf(("%d/%d"):format(page[tab], n), w - 60, TAB.y + 2, 30, "right")
    end
    G2.setColor(1, 1, 1, 0.7)
    G2.printf(("%d/%d items"):format(#(room.items or {}), Decor.MAX_ITEMS), 120, TAB.y + 2, 60, "right")
    G2.setColor(0.3, 0.3, 0.36, 1)
    G2.rectangle("fill", DONE.x, DONE.y, DONE.w, DONE.h, 4, 4)
    G2.setColor(1, 1, 1, 0.95)
    G2.printf("DONE", DONE.x, DONE.y + 1, DONE.w, "center")
    if app.font then G2.setFont(app.font) end
    G2.pop()
    -- while the drawer is away: the strip that takes an item back
    if drawerT < 0.99 then
      local a = 1 - drawerT
      G2.setColor(0.12, 0.12, 0.18, 0.88 * a)
      G2.rectangle("fill", 0, PUT_AWAY.y, w, PUT_AWAY.h)
      G2.setColor(1, 1, 1, 0.9 * a)
      if app.smallFont then G2.setFont(app.smallFont) end
      G2.printf(drag and drag.fromRoom and "PUT AWAY" or "DROP HERE TO CANCEL", 0, PUT_AWAY.y + 2, w, "center")
      if app.font then G2.setFont(app.font) end
    end
    if drag then drawItem(G2, drag.id, drag.x + (drag.ox or 0), floorY(drag.y - RO + (drag.oy or 0)) + RO, 1, 0.85) end
    if s.message then
      G2.setColor(0, 0, 0, 0.6)
      G2.rectangle("fill", 4, DRAWER.y - 18, 192, 14, 4, 4)
      G2.setColor(1, 1, 1, 1)
      if app.smallFont then G2.setFont(app.smallFont) end
      fitText(G2, s.message, 6, DRAWER.y - 18, 188, 14, "center")
      if app.font then G2.setFont(app.font) end
    end
  end

  function app:releaseAll() drag = nil end
  app.leave = app.releaseAll
  return app
end
