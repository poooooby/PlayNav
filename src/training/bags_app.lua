-- BAGS, the training bag rack on the bottom screen: the twelve slots, the bag on the stand
-- and TAKE DOWN / BACK. Tapping a bag opens its box, as in the game: the bag's icon, its
-- name, its description, then USE / DISCARD / BACK; USE and DISCARD each ask the game's
-- question (Yes / No) first. Names, descriptions and button words are the game's own when
-- the player's card has been extracted (T.bagName / T.bagDescription / T.uiText).

return function(mod, Pointer, T, Rules, Store)
  local app = { id = "training_bags", title = "TRAINING BAGS", live = true, hideTabs = true }
  local N = Rules.N

  function app:wantsSurface() return T.session ~= nil and T.session.mode == "bags" end

  local W, H = 256, 178
  local SLOT = { x0 = 8, y0 = 8, w = 36, h = 54, gapX = 5, gapY = 6, cols = 6 }
  local STAND = { x = 8, y = 128, w = 60, h = 44 }
  local TAKE = { x = 76, y = 154, w = 70, h = 18 }
  local BACK = { x = 192, y = 158, w = 60, h = 16 }
  -- the box over the rack
  local BOX = { x = 10, y = 6, w = 236, h = 166 }
  local ICON = { x = 20, y = 18, w = 40, h = 74 }
  local BTN_Y, BTN_W, BTN_H = 146, 68, 20
  local function btn(i, n)
    local gap = 8
    local total = n * BTN_W + (n - 1) * gap
    return { x = BOX.x + (BOX.w - total) / 2 + (i - 1) * (BTN_W + gap), y = BTN_Y, w = BTN_W, h = BTN_H }
  end

  -- nil (the rack), { index } (the box), { index, ask = "use" | "discard" } (the question)
  local view = nil

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  local function fonts()
    if app.fontsFn then
      local f, s = app.fontsFn()
      if f then return f, s or f end
    end
    local f = love.graphics.getFont()
    return f, f
  end

  local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

  local function slotRect(i)
    local col = (i - 1) % SLOT.cols
    local row = math.floor((i - 1) / SLOT.cols)
    return { x = SLOT.x0 + col * (SLOT.w + SLOT.gapX), y = SLOT.y0 + row * (SLOT.h + SLOT.gapY), w = SLOT.w, h = SLOT.h }
  end

  function app.geometry()
    return { slotRect = slotRect, STAND = STAND, TAKE = TAKE, BACK = BACK, BOX = BOX,
      button = function(i, n) return btn(i, n) end }
  end
  function app.view() return view end
  function app.leave() view = nil end

  local function close() view = nil; if T.onChange then T.onChange() end end

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "bags") then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    local bags = Store.bags()
    if view then
      local id = bags[view.index]
      if not id then close(); return end
      if view.ask then
        if inRect(x, y, btn(1, 2)) then                      -- Yes
          if view.ask == "use" then
            if T.attachBag(view.index) then view = nil; T.enterCore() else close() end
          else
            T.discardBag(view.index)
            T.say(("Threw away the %s."):format(T.bagName(id)), 2.5)
            close()
          end
        elseif inRect(x, y, btn(2, 2)) then                  -- No
          view.ask = nil
          if T.onChange then T.onChange() end
        end
        return
      end
      if inRect(x, y, btn(1, 3)) then view.ask = "use"; view.question = T.useQuestion(id)
      elseif inRect(x, y, btn(2, 3)) then view.ask = "discard"; view.question = "askDiscard"
      elseif inRect(x, y, btn(3, 3)) or not inRect(x, y, BOX) then view = nil end
      if T.onChange then T.onChange() end
      return
    end
    if inRect(x, y, BACK) then T.enterCore(); return end
    if inRect(x, y, TAKE) then T.takeDownBag(); return end
    for i = 1, N.LIMITS.BAG_MAX do
      if inRect(x, y, slotRect(i)) and bags[i] then
        view = { index = i }
        if T.session and T.session.anim then T.session.anim.hit = 0 end
        if T.onChange then T.onChange() end
        return
      end
    end
  end

  function app:update(dt) end

  local function drawBagIcon(G, id, x, y, w, h, small)
    local def = Rules.bag(id)
    local img = art(("training/sand_bag_%02d"):format(Rules.BAG_ART[id] or 0))
    if img then
      local iw, ih = img:getDimensions()
      local sc = math.min(w / iw, h / ih)
      G.setColor(1, 1, 1, 1)
      G.draw(img, x + w / 2, y + (h - ih * sc) / 2, 0, sc, sc, iw / 2, 0)
      return
    end
    local rgb = (def and def.stat and T.STAT_RGB[def.stat]) or (def and { 0.6, 0.6, 0.7 }) or { 0.2, 0.2, 0.24 }
    local bw = math.min(16, w)
    G.setColor(rgb[1], rgb[2], rgb[3], 1)
    G.rectangle("fill", x + w / 2 - bw / 2, y, bw, h, 6, 6)
    if def then
      G.setFont(small)
      G.setColor(1, 1, 1, 1)
      local letter = def.stat and Rules.STAT_SHORT[def.stat] or def.label:sub(1, 2)
      G.printf(letter, x, y + h / 2 - 8, w, "center")
      if def.size then G.printf(Rules.SIZE_LABEL[def.size], x, y + h / 2 + 2, w, "center") end
    end
  end

  local function button(G, r, label, font, on)
    G.setColor(on and 0.2 or 0.25, on and 0.6 or 0.3, on and 0.85 or 0.42, 1)
    G.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
    G.setColor(1, 1, 1, 0.9)
    G.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
    G.setFont(font)
    G.printf(label, r.x, r.y + math.floor((r.h - font:getHeight()) / 2), r.w, "center")
  end

  local function drawBox(G, font, small)
    local id = Store.bags()[view.index]
    if not id then view = nil; return end
    local def = Rules.bag(id)
    G.setColor(0, 0, 0, 0.55)
    G.rectangle("fill", 0, 0, W, H)
    G.setColor(0.93, 0.95, 0.98, 1)
    G.rectangle("fill", BOX.x, BOX.y, BOX.w, BOX.h, 6, 6)
    G.setColor(0.25, 0.65, 0.85, 1)
    G.setLineWidth(2)
    G.rectangle("line", BOX.x + 1, BOX.y + 1, BOX.w - 2, BOX.h - 2, 6, 6)
    G.setLineWidth(1)
    -- the bag
    G.setColor(0.82, 0.87, 0.93, 1)
    G.rectangle("fill", ICON.x, ICON.y, ICON.w, ICON.h, 4, 4)
    drawBagIcon(G, id, ICON.x + 4, ICON.y + 6, ICON.w - 8, ICON.h - 12, small)
    local tx = ICON.x + ICON.w + 10
    local tw = BOX.x + BOX.w - tx - 10
    G.setColor(0.1, 0.12, 0.16, 1)
    if view.ask then
      G.setFont(small)
      G.printf(T.uiText(view.question or (view.ask == "use" and "askUse" or "askDiscard"), id), tx, ICON.y + 4, tw, "left")
      button(G, btn(1, 2), T.uiText("yes"), small, true)
      button(G, btn(2, 2), T.uiText("no"), small, false)
      return
    end
    G.setFont(font)
    G.printf(T.bagName(id), tx, ICON.y, tw, "left")
    G.setFont(small)
    G.setColor(0.35, 0.4, 0.48, 1)
    G.printf(("%d hits"):format(def and def.hits or 0), tx, ICON.y + font:getHeight() + 2, tw, "left")
    G.setColor(0.1, 0.12, 0.16, 1)
    G.printf(T.bagDescription(id), tx, ICON.y + font:getHeight() + small:getHeight() + 8, tw, "left")
    button(G, btn(1, 3), T.uiText("use"), small, true)
    button(G, btn(2, 3), T.uiText("discard"), small, false)
    button(G, btn(3, 3), T.uiText("back"), small, false)
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    G.setColor(0.09, 0.11, 0.16, 1)
    G.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    if not s then return end
    local bags = Store.bags()
    for i = 1, N.LIMITS.BAG_MAX do
      local r = slotRect(i)
      G.setColor(0.14, 0.18, 0.26, 1)
      G.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
      G.setColor(0.3, 0.38, 0.5, 0.8)
      G.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
      local id = bags[i]
      if id then
        drawBagIcon(G, id, r.x + 2, r.y + 3, r.w - 4, r.h - 18, small)
        local def = Rules.bag(id)
        G.setFont(small)
        G.setColor(1, 1, 1, 0.9)
        G.printf(def and tostring(def.hits) or "?", r.x, r.y + r.h - 13, r.w, "center")
      end
    end
    -- the stand
    G.setColor(0.14, 0.18, 0.26, 1)
    G.rectangle("fill", STAND.x, STAND.y, STAND.w, STAND.h, 4, 4)
    G.setFont(small)
    G.setColor(1, 1, 1, 0.8)
    G.print("ON STAND", STAND.x + 4, STAND.y + 2)
    local bag = s.rec.bag
    if bag then
      drawBagIcon(G, bag.id, STAND.x + 4, STAND.y + 12, 24, 28, small)
      G.setColor(1, 1, 1, 0.9)
      G.printf(("%d/%d"):format(bag.hits, bag.needed), STAND.x + 28, STAND.y + 18, STAND.w - 30, "left")
    else
      G.setColor(1, 1, 1, 0.5)
      G.printf("empty", STAND.x, STAND.y + 20, STAND.w, "center")
    end
    button(G, TAKE, "TAKE DOWN", small, bag ~= nil)
    button(G, BACK, "BACK", small, false)
    G.setColor(1, 1, 1, 0.7)
    G.printf(("%d/%d bags.  Tap a bag to see it."):format(#bags, N.LIMITS.BAG_MAX), 76, 128, 176, "center")
    if view then drawBox(G, font, small) end
    G.setColor(1, 1, 1, 1)
  end

  return app
end
