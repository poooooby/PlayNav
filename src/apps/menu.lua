-- The PlayNav menu: the START menu's PLAYNAV entry opens it on the touch screen, as the
-- game's PlayNav lists its apps (Player Search System, Pokemon-Amie, Super Training; the
-- PSS is left out). Drawn by the engine in PlayNav's look (src/apps/brand.lua): the banner
-- and its x, then one card per app, each a colour band with its caption, its Kanto Gear
-- icon and its name as a wordmark. A tap sinks the card; Super Training opens behind the
-- game's shutters (as from the import screen), Pokemon-Amie after a fade. The field stays
-- live meanwhile, as on Super Training's home; closing an app comes back here (the
-- sessions return to the app they were opened from), the x leaves.
--
-- app = menu(mod, Pointer, deps) ; deps = { apps = { { id, caption, name, colours, icon,
--   enabled(), open() -> ok, why } }, inBattle(), Assets }
-- app.show(opts) (opts.shutters: part the shutters over it), app.hide(), app.shown(),
-- app.tapPoint("card", i | id) / ("close"), app.cards() -> the cards on screen

return function(mod, Pointer, deps)
  deps = deps or {}
  local app = { id = "menu", title = "PLAYNAV", live = true }

  local W, H = 256, 178
  local SH, DH = H, 0
  app.CLOSE = { x = 237, y = 3, r = 12 }   -- in the banner's band
  local CARD = { x = 16, w = 224, h = 58, gap = 12, top = 36 }
  local SINK_S, FADE_S = 0.14, 0.25

  local function sibling(path)
    local src = mod.read and mod:read(path)
    local chunk = src and load(src, "@" .. tostring(mod.path) .. "/" .. path)
    local ok, make = pcall(chunk or error)
    return (ok and type(make) == "function") and make() or nil
  end
  local Brand = sibling("src/apps/brand.lua")
  if not Brand then error("src/apps/brand.lua missing") end
  local Lyt = sibling("src/training/lyt.lua")
  local INK, col = Brand.INK, Brand.col

  local function art(id)
    local A = deps.Assets
    if not A or A.enabled == false then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end

  -- ------- state

  local shown = false
  local press = nil      -- { i } while a finger is on a card
  local going = nil      -- { i, at, opened } after a tap on one
  local enterAt = nil    -- the shutters parting over the menu
  local failNote = nil   -- { text, until }

  function app.show(opts)
    shown, press, going, failNote = true, nil, nil, nil
    enterAt = (opts and opts.shutters) and Pointer.now() or nil
    if deps.setActive then deps.setActive("menu") end
    return true
  end
  function app.hide()
    shown, press, going, enterAt = false, nil, nil, nil
  end
  function app.shown() return shown end

  function app:wantsSurface()
    if not shown then return false end
    return not (deps.inBattle and deps.inBattle())
  end

  -- ------- geometry (app units; the cards centre in the room under the banner)

  local list, listN = {}, 0
  function app.cards()
    listN = 0
    for _, a in ipairs(deps.apps or {}) do
      if not a.enabled or a.enabled() then
        listN = listN + 1
        list[listN] = a
      end
    end
    for i = listN + 1, #list do list[i] = nil end
    return list
  end
  local function cardRect(i, n)
    local total = n * CARD.h + (n - 1) * CARD.gap
    local y0 = CARD.top + math.max(0, (SH - 6 - CARD.top - total) / 2)
    return CARD.x, y0 + (i - 1) * (CARD.h + CARD.gap), CARD.w, CARD.h
  end
  local function cardAt(x, y)
    local cards = app.cards()
    for i = 1, #cards do
      local cx, cy, cw, ch = cardRect(i, #cards)
      if x >= cx and x <= cx + cw and y >= cy and y <= cy + ch then return i end
    end
    return nil
  end

  function app.tapPoint(what, which)
    if what == "close" then return app.CLOSE.x, app.CLOSE.y end
    local cards = app.cards()
    for i, a in ipairs(cards) do
      if i == which or a.id == which then
        local cx, cy, cw, ch = cardRect(i, #cards)
        return cx + cw / 2, cy + ch / 2
      end
    end
    return nil
  end

  local function busy() return going ~= nil or (enterAt ~= nil and (Pointer.now() - enterAt) * 30 < 10) end
  app.busy = busy

  function app:pointer(ev, rec)
    if busy() then return end
    local H_ = mod.haptics
    if ev.phase == "pressed" then
      local i = cardAt(ev.x, ev.y)
      press = i and { i = i } or nil
      if i and H_ then H_.pulse("tick") end
      return
    end
    if ev.phase ~= "released" then return end
    local held = press
    press = nil
    if not Pointer.isTap(rec, 16, 1.0) then return end
    local dx, dy = ev.x - app.CLOSE.x, ev.y - app.CLOSE.y
    if dx * dx + dy * dy <= app.CLOSE.r * app.CLOSE.r then
      if H_ then H_.pulse("tick") end
      app.hide()
      if deps.setActive then deps.setActive("play") end
      return
    end
    local i = cardAt(ev.x, ev.y)
    -- a pad's tap comes as press and release together; a finger must lift on the card it pressed
    if i and (not held or held.i == i) then
      going = { i = i, at = Pointer.now() }
      -- the shutters' system sound, as Super Training's own screen changes
      local a = app.cards()[i]
      if a and a.shutters and deps.shutterSound then pcall(deps.shutterSound) end
    end
  end

  -- the handoff runs here, never mid-draw: Super Training once the shutters are shut,
  -- Pokemon-Amie once the fade is black
  function app:update(dt)
    if not going or going.opened then return end
    local a = app.cards()[going.i]
    if not a then going = nil; return end
    local d = Pointer.now() - going.at
    if a.shutters then
      if (d - SINK_S) * 30 < 16 then return end
    elseif d < SINK_S + FADE_S then
      return
    end
    going.opened = true
    local ok, why = false, "unavailable"
    if a.open then
      local okC, r1, r2 = pcall(a.open)
      if okC then ok, why = r1, r2 else why = r1 end
    end
    going = nil
    if not ok then
      failNote = { ("%s could not open (%s)"):format(a.name, tostring(why)), Pointer.now() + 3 }
    end
  end

  -- ------- drawing

  -- the cards' colour bands: a unit quad, its left edge one colour and its right the other
  local meshes = {}
  local function bandMesh(a)
    local m = meshes[a.id]
    if m == nil then
      m = false
      local L, R = a.colours.left, a.colours.right
      local ok, mesh = pcall(love.graphics.newMesh, {
        { 0, 0, 0, 0, L[1], L[2], L[3], 1 }, { 1, 0, 0, 0, R[1], R[2], R[3], 1 },
        { 1, 1, 0, 0, R[1], R[2], R[3], 1 }, { 0, 1, 0, 0, L[1], L[2], L[3], 1 } }, "fan", "static")
      if ok then m = mesh end
      meshes[a.id] = m
    end
    return m or nil
  end

  -- the Kanto Gear icons (24 x 24, a letter per pixel, `o` the outline), made once
  local icons = {}
  local OUTLINE = "1c1828"
  local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
  end
  local function iconOf(a)
    local img = icons[a.id]
    if img == nil then
      img = false
      local spec = a.icon
      if spec and spec.rows and love and love.image and love.graphics then
        local ok, data = pcall(love.image.newImageData, 24, 24)
        if ok and data then
          for y, row in ipairs(spec.rows) do
            for x = 1, math.min(24, #row) do
              local ch = row:sub(x, x)
              local c = (ch == "o") and OUTLINE or (spec.pal and spec.pal[ch])
              if c then
                local r, g, b = hex(c)
                data:setPixel(x - 1, y - 1, r, g, b, 1)
              end
            end
          end
          local okI, image = pcall(love.graphics.newImage, data)
          if okI and image then
            image:setFilter("nearest", "nearest")
            img = image
          end
        end
      end
      icons[a.id] = img
    end
    return img or nil
  end

  local function drawCard(G, a, x, y, w, h, held)
    local cx, cy = x + w / 2, y + h / 2
    G.push()
    if held then
      G.translate(cx, cy)
      G.scale(0.96, 0.96)
      G.translate(-cx, -cy)
    end
    local L, R = a.colours.left, a.colours.right
    local r = 9
    -- a glow behind it in its own colour
    col(G, R, 0.12)
    G.rectangle("fill", x - 3, y - 3, w + 6, h + 6, r + 3, r + 3)
    -- the band: its ends as rounded halves, the gradient between them
    col(G, L)
    G.rectangle("fill", x, y, w / 2, h, r, r)
    col(G, R)
    G.rectangle("fill", x + w / 2, y, w / 2, h, r, r)
    local mesh = bandMesh(a)
    if mesh then
      G.setColor(1, 1, 1, 1)
      G.draw(mesh, x + r, y, 0, w - 2 * r, h)
    end
    -- the lower half's darker stripe the name sits on, as the game's cards have
    G.setColor(0, 0, 0, 0.28)
    G.rectangle("fill", x, y + h * 0.42, w, h * 0.42)
    -- a sheen along the top and a fine edge
    G.setColor(1, 1, 1, held and 0.2 or 0.12)
    G.rectangle("fill", x + 2, y + 2, w - 4, h * 0.36, r - 2, r - 2)
    col(G, a.colours.edge, 0.7)
    G.rectangle("line", x, y, w, h, r, r)
    -- the icon on a round tile
    local tile = 40
    local tx, ty = x + 9, cy - tile / 2
    G.setColor(1, 1, 1, 0.92)
    G.rectangle("fill", tx, ty, tile, tile, 10, 10)
    col(G, a.colours.edge)
    G.rectangle("line", tx, ty, tile, tile, 10, 10)
    local img = iconOf(a)
    if img then
      G.setColor(1, 1, 1, 1)
      G.draw(img, tx + 2, ty + 2, 0, (tile - 4) / 24, (tile - 4) / 24)
    end
    -- the caption, then the name as a wordmark
    local f = G.getFont()
    local left = tx + tile + 10
    local room = x + w - 22 - left
    G.setColor(1, 1, 1, 0.92)
    local kc = 0.74
    G.print(a.caption, left, y + 5, 0, kc, kc)
    local k = math.min(1.25, room / math.max(1, f:getWidth(a.name)))
    local ny = y + h * 0.42 + (h * 0.42 - f:getHeight() * k) / 2
    if a.slant then
      G.push()
      G.translate(left, ny + f:getHeight() * k)
      G.shear(-a.slant, 0)
      Brand.wordmark(G, a.name, 0, -f:getHeight() * k, k, a.colours.word, a.colours.wordEdge)
      G.pop()
    else
      Brand.wordmark(G, a.name, left, ny, k, a.colours.word, a.colours.wordEdge)
    end
    -- a chevron: it opens
    G.setColor(1, 1, 1, 0.85)
    local chx = x + w - 12
    G.setLineWidth(2)
    G.line(chx - 4, cy - 6, chx + 1, cy, chx - 4, cy + 6)
    G.setLineWidth(1)
    G.pop()
  end

  local function backdrop(G)
    local b = app.bleed or 0
    col(G, INK.bg)
    G.rectangle("fill", 0, -b, W, SH + b)
    for i, r in ipairs({ 110, 80, 52 }) do
      col(G, INK.glow, 0.024 * i)
      G.circle("fill", W / 2, (CARD.top + SH) / 2, r)
    end
    Brand.banner(G, W, b)
    if not going then Brand.close(G, app.CLOSE) end
  end

  local function shutters(G, phase, f)
    local b = app.bleed or 0
    G.push()
    G.translate(0, -b)
    if Lyt then
      Lyt.shutters(G, art, W, SH + b, phase, f)
    else
      local a = phase == "close" and math.min(1, f / 10) or math.max(0, 1 - f / 10)
      G.setColor(0, 0, 0, a)
      G.rectangle("fill", 0, 0, W, SH + b)
    end
    G.pop()
  end

  function app:draw(G, w, h)
    SH = h or H
    DH = math.max(0, SH - H)
    backdrop(G)
    local cards = app.cards()
    local now = Pointer.now()
    for i, a in ipairs(cards) do
      local x, y, cw, ch = cardRect(i, #cards)
      local held = (press and press.i == i) or (going and going.i == i and now - going.at < SINK_S)
      drawCard(G, a, x, y, cw, ch, held)
    end
    if #cards == 0 then
      col(G, INK.dim)
      G.printf("No PlayNav apps are available in this game.", 16, SH / 2, 224 / 0.55, "center", 0, 0.55, 0.55)
    end
    if failNote and now < failNote[2] then
      col(G, INK.warn)
      G.printf(failNote[1], 8, SH - 14, 240 / 0.5, "center", 0, 0.5, 0.5)
    end
    -- on the way out: the shutters close, or the screen fades to black
    if going then
      local a = cards[going.i]
      local d = now - going.at - SINK_S
      if a and d > 0 then
        if a.shutters then
          shutters(G, "close", math.min(d * 30, 10))
        else
          G.setColor(0, 0, 0, math.min(1, d / FADE_S))
          local b = app.bleed or 0
          G.rectangle("fill", 0, -b, W, SH + b)
        end
      end
    elseif enterAt then
      local f = (now - enterAt) * 30
      if f < 10 then shutters(G, "open", f) else enterAt = nil end
    end
    G.setColor(1, 1, 1, 1)
  end

  return app
end
