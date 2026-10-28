-- BAGS, the training bag drawer, as the game draws it over the home screen: the room dims,
-- the drawer (training_lower.bclyt window 1a) slides in from the left with the twelve bags in
-- two tilted columns, and the Bags button turns into the return button. Tapping a bag opens
-- the description window (training_message_lower.bclyt 8y) with Use / Discard / Back; Use and
-- Discard ask the game's question (window 71, Yes / No) first. Positions, sizes, tints and the
-- slide come from the game's layout and animation files (tools/clyt.py, tools/clan.py); words
-- are the game's own once the player's card is extracted (T.bagName / bagDescription / uiText).

return function(mod, Pointer, T, Rules, Store)
  local app = { id = "training_bags", title = "TRAINING BAGS", live = true, hideTabs = true, hapticTouch = true }
  local N = Rules.N

  app.fieldPlay = true
  function app:wantsSurface()
    return T.session ~= nil and T.session.mode == "bags" and not (T.inBattle and T.inBattle())
  end

  local L = 256 / 320
  local BLEED = 14
  local FPS = 30
  -- the drawer: window 1a, 100x196, its centre slid from x -50 to 30 (list_win_in: tx -210 ->
  -- -125 at frame 3 -> -130 at frame 4; list_win_out back over 4 frames); y 120
  local DRAWER = { w = 100, h = 196, y = 120 }
  local SLIDE_IN = { { 0, -210, 28.33 }, { 3, -125, 20 }, { 4, -130, -17 } }
  local SLIDE_OUT = { { 0, -130, -17 }, { 4, -210, -20 } }
  -- the + pattern inside it (pic 23, tinted), and the bags: 18x30, tilted 25 degrees, two
  -- columns 30 apart, rows 30 apart from y 44 (pics 1d..1n then 1p..1z)
  -- (material 23 scales the texture 3 x 5.7 about its centre: three columns of + across)
  local PTN = { dx = 4, dy = -1, w = 80, h = 170, tint = { 127, 255, 252 }, repU = 3, repV = 5.7 }
  local BAG = { w = 18, h = 30, rz = 25, dx = { -10, 20 }, y0 = 44, dy = 30 }
  -- the selected bag's pulse (sand_bag_select, a 16-frame loop)
  local PULSE = { { 0, 1, 0 }, { 4, 1.5, 0 }, { 8, 1, -0.09 }, { 12, 0.75, 0 }, { 16, 1, 0.06 } }
  -- the message layout: the description window and its three bars (7x / 7y / 7z); the
  -- question window (71) and its Yes / No bars
  local DESC = { 200, 80, 230, 120 }
  local DESC_BARS = { { 230, 165, 180, 30 }, { 230, 195, 180, 30 }, { 230, 225, 180, 30 } }
  local ASK = { 160, 60, 310, 80 }
  -- Yes / No: panes 82 and 88, under the question window on the right
  local ASK_BARS = { { 230, 115, 180, 30 }, { 230, 145, 180, 30 } }
  local RETURN = { 292, 193, 48, 48 }
  local LEAVE = { 305, 224, 27, 27 }   -- NaviPlay's return button (pane ab)

  -- nil (the drawer), { index } (the description), { index, ask = "use" | "discard" }
  local view = nil
  local clock, openAt, closeAt, viewAt = 0, nil, nil, 0
  local lastMode

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
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

  local function eval(keys, f)
    local core = app.core
    if core and core.eval then return core.eval(keys, f) end
    return keys[#keys][2]
  end

  local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
  -- a layout rect (centre, size) in app space
  local function rect(p) return { x = (p[1] - p[3] / 2) * L, y = (p[2] - p[4] / 2) * L - BLEED, w = p[3] * L, h = p[4] * L } end

  -- The screen's shape (as core_app): LH layout units tall, D = LH - 240 more than the
  -- game's. The drawer (window, pattern, bags) keeps its size and centres in the taller
  -- room (D/2 lower); so do the message windows; the return buttons and the bottom strip's
  -- dim follow the bottom (D). On the 3DS shape D = 0. K stays in the transform (1).
  local LH, D, K = 240, 0, 1
  local function setShape(lh)
    LH = math.max(240, lh)
    D = LH - 240
    K = 1
  end
  local function drawerPt(x, y) return (x - 30) * K + 30, (y - 120) * K + 120 + D / 2 end
  local function drawerRect(p)
    local x, y = drawerPt(p[1], p[2])
    return rect({ x, y, p[3] * K, p[4] * K })
  end
  local function midRect(p) return rect({ p[1], p[2] + D / 2, p[3], p[4] }) end
  local function lowRect(p) return rect({ p[1], p[2] + D, p[3], p[4] }) end
  local function pushDrawer(G)
    G.push()
    G.translate(30, 120 + D / 2)
    G.scale(K, K)
    G.translate(-30, -120)
  end

  local function drawerX()
    if closeAt then return 160 + eval(SLIDE_OUT, clock - closeAt) end
    if openAt then return 160 + eval(SLIDE_IN, clock - openAt) end
    return 30
  end

  -- slot i: the left column holds 1..6, the right 7..12
  local function slotCentre(i, cx)
    local col = (i <= 6) and 1 or 2
    local row = (i - 1) % 6
    return (cx or 30) + BAG.dx[col], BAG.y0 + row * BAG.dy
  end
  local function slotRect(i)
    local x, y = slotCentre(i)
    return drawerRect({ x, y, 28, 30 })
  end

  function app.geometry()
    return {
      slotRect = slotRect,
      BACK = lowRect(RETURN),
      LEAVE = lowRect({ LEAVE[1], LEAVE[2], 36, 36 }),
      DRAWER = drawerRect({ 30, DRAWER.y, DRAWER.w, DRAWER.h }),
      button = function(i, n)
        if n == 2 then return midRect(ASK_BARS[i]) end
        return midRect(DESC_BARS[i])
      end,
    }
  end
  function app.view() return view end
  function app.leave() view = nil end

  local function changed() if T.onChange then T.onChange() end end
  local function se(event) if T.playSe then T.playSe(event) end end
  local function open(v) view = v; viewAt = clock; changed() end
  local function close()
    if not closeAt then closeAt = clock end
    view = nil
    changed()
  end

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "bags") or closeAt then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    local bags = Store.bags()
    local g = app.geometry()
    if view then
      local id = bags[view.index]
      if not id then open(nil); return end
      if view.ask then
        if inRect(x, y, g.button(1, 2)) then                    -- Yes
          se("bag_select")
          if view.ask == "use" then
            if T.attachBag(view.index) then view = nil; close() else open(nil) end
          else
            T.discardBag(view.index)
            T.say(("Threw away the %s."):format(T.bagName(id)), 2.5)
            open(nil)
          end
        elseif inRect(x, y, g.button(2, 2)) then                -- No
          se("bag_select")
          open({ index = view.index })
        end
        return
      end
      if inRect(x, y, g.button(1, 3)) then se("bag_select"); open({ index = view.index, ask = "use", question = T.useQuestion(id) })
      elseif inRect(x, y, g.button(2, 3)) then se("bag_select"); open({ index = view.index, ask = "discard", question = "askDiscard" })
      elseif inRect(x, y, g.button(3, 3)) then se("bag_select"); open(nil) end
      return
    end
    if inRect(x, y, g.BACK) then se("bags_close"); close(); return end
    if inRect(x, y, g.LEAVE) then T.finish(); return end
    for i = 1, N.LIMITS.BAG_MAX do
      if bags[i] and inRect(x, y, slotRect(i)) then
        se("bag_select")
        open({ index = i })
        return
      end
    end
    -- outside the drawer: the drawer closes, as the return button does
    if not inRect(x, y, g.DRAWER) then se("bags_close"); close() end
  end

  -- only the active app is updated, so the mode it last saw would carry over to the next
  -- visit (a close still pending then shut the drawer the moment it opened)
  function app:leave()
    lastMode, closeAt = nil, nil
  end

  function app:update(dt)
    clock = clock + (dt or 0) * FPS
    if app.core and app.core.update then app.core:update(dt) end
    local s = T.session
    local mode = s and s.mode
    if mode == "bags" and lastMode ~= "bags" then openAt, closeAt, view = clock, nil, nil end
    lastMode = mode
    -- the slide out finished: back to the room
    if closeAt and clock - closeAt >= SLIDE_OUT[#SLIDE_OUT][1] then
      closeAt, openAt = nil, nil
      if s and s.mode == "bags" then T.enterCore() end
    end
  end

  -- ------- drawing (layout units; the caller scales by L)

  -- a window with one frame texture: the texture is the top-left corner, mirrored to the
  -- others; its last column / row stretches along the edges, its last pixel fills the middle
  local function window(G, img, cx, cy, w, h, alpha)
    local tw, th = img:getDimensions()
    local x0, y0 = cx - w / 2, cy - h / 2
    local iw, ih = math.max(0, w - 2 * tw), math.max(0, h - 2 * th)
    app.quads = app.quads or {}
    local key = tostring(img)
    local q = app.quads[key]
    if not q then
      q = {
        corner = G.newQuad(0, 0, tw, th, tw, th),
        hEdge = G.newQuad(tw - 1, 0, 1, th, tw, th),
        vEdge = G.newQuad(0, th - 1, tw, 1, tw, th),
        fill = G.newQuad(tw - 1, th - 1, 1, 1, tw, th),
      }
      app.quads[key] = q
    end
    G.setColor(1, 1, 1, alpha or 1)
    -- corners
    G.draw(img, q.corner, x0, y0)
    G.draw(img, q.corner, x0 + w, y0, 0, -1, 1)
    G.draw(img, q.corner, x0, y0 + h, 0, 1, -1)
    G.draw(img, q.corner, x0 + w, y0 + h, 0, -1, -1)
    -- edges
    G.draw(img, q.hEdge, x0 + tw, y0, 0, iw, 1)
    G.draw(img, q.hEdge, x0 + tw, y0 + h, 0, iw, -1)
    G.draw(img, q.vEdge, x0, y0 + th, 0, 1, ih)
    G.draw(img, q.vEdge, x0 + w, y0 + th, 0, -1, ih)
    -- the middle
    G.draw(img, q.fill, x0 + tw, y0 + th, 0, iw, ih)
  end

  local function plainWindow(G, cx, cy, w, h)
    G.setColor(0.07, 0.85, 0.73, 0.8)
    G.rectangle("fill", cx - w / 2, cy - h / 2, w, h, 8, 8)
    G.setColor(0.8, 1, 0.95, 0.9)
    G.rectangle("line", cx - w / 2, cy - h / 2, w, h, 8, 8)
  end

  local function bagImage(id)
    return art(Rules.bagArt(id))
  end

  local function drawBag(G, id, x, y, scale)
    local img = bagImage(id)
    local r = math.rad(-BAG.rz)
    if img then
      local iw, ih = img:getDimensions()
      local def = Rules.bag(id)
      -- the alley's R+ bags glow (their halo twice the bag's size, about its middle)
      local glow = def and def.glow and art(Rules.bagGlowArt(def.id))
      if glow then
        local gw, gh = glow:getDimensions()
        G.setColor(1, 1, 1, 1)
        G.draw(glow, x, y, r, BAG.w / iw * scale, BAG.h / ih * scale, gw / 2, gh / 2)
      end
      G.setColor(1, 1, 1, 1)
      G.draw(img, x, y, r, BAG.w / iw * scale, BAG.h / ih * scale, iw / 2, ih / 2)
    else
      local def = Rules.bag(id)
      local rgb = (def and def.stat and T.STAT_RGB[def.stat]) or { 0.6, 0.6, 0.7 }
      G.push()
      G.translate(x, y)
      G.rotate(r)
      G.scale(scale, scale)
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.rectangle("fill", -BAG.w / 2, -BAG.h / 2, BAG.w, BAG.h, 5, 5)
      G.pop()
    end
  end

  local function bar(G, p, label, small)
    local img = art("training/meter_bar")
    if img then
      local iw, ih = img:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(img, p[1] - p[3] / 2, p[2] - p[4] / 2, 0, p[3] / iw, p[4] / ih)
    else
      G.setColor(0.45, 0.85, 0.15, 1)
      G.rectangle("fill", p[1] - p[3] / 2, p[2] - p[4] / 2 + 2, p[3], p[4] - 4, 10, 10)
    end
    G.setFont(small)
    local k = 1.1 / L
    G.setColor(0.05, 0.12, 0.05, 0.9)
    G.print(label, p[1] - p[3] / 2 + 21, p[2] - small:getHeight() * k / 2 + 1, 0, k, k)
    G.setColor(1, 1, 1, 1)
    G.print(label, p[1] - p[3] / 2 + 20, p[2] - small:getHeight() * k / 2, 0, k, k)
  end

  local function text(G, s, x, y, w, small, k)
    G.setFont(small)
    G.setColor(0.03, 0.25, 0.22, 0.7)
    G.printf(s, x + 1, y + 1, w / k, "left", 0, k, k)
    G.setColor(1, 1, 1, 1)
    G.printf(s, x, y, w / k, "left", 0, k, k)
  end

  local function drawMessage(G, small)
    local bags = Store.bags()
    local id = view and bags[view.index]
    if not id then return end
    local winImg = art("training/win_bl")
    -- the game fits a description line ("Trains Speed stat a fair amount.") in the window's
    -- 210 units: the font sized to that, never larger than its 20-unit line spacing
    local k = math.min(18 / math.max(1, small:getHeight()), 200 / math.max(1, small:getWidth("Trains Speed stat a fair amount.")))
    -- the room under the window darkens a little more
    G.setColor(0, 0, 0.08, 0.35)
    G.rectangle("fill", 0, 0, 320, LH)
    G.push()
    G.translate(0, D / 2)
    if view.ask then
      if winImg then window(G, winImg, ASK[1], ASK[2], ASK[3], ASK[4], 1) else plainWindow(G, ASK[1], ASK[2], ASK[3], ASK[4]) end
      text(G, T.uiText(view.question or (view.ask == "use" and "askUse" or "askDiscard"), id), ASK[1] - ASK[3] / 2 + 12, ASK[2] - ASK[4] / 2 + 8, ASK[3] - 24, small, k)
      bar(G, ASK_BARS[1], T.uiText("yes"), small)
      bar(G, ASK_BARS[2], T.uiText("no"), small)
      G.pop()
      return
    end
    if winImg then window(G, winImg, DESC[1], DESC[2], DESC[3], DESC[4], 1) else plainWindow(G, DESC[1], DESC[2], DESC[3], DESC[4]) end
    local x0, y0 = DESC[1] - DESC[3] / 2 + 10, DESC[2] - DESC[4] / 2 + 8
    -- the game's diamond before the name
    local d, my = 4, y0 + small:getHeight() * k / 2
    G.setColor(1, 1, 1, 1)
    G.polygon("fill", x0 + d, my - d, x0 + 2 * d, my, x0 + d, my + d, x0, my)
    text(G, T.bagName(id), x0 + 2 * d + 5, y0, DESC[3] - 20 - 2 * d - 5, small, k)
    text(G, T.bagDescription(id), x0, y0 + 20, DESC[3] - 16, small, k)
    local labels = { T.uiText("use"), T.uiText("discard"), (T.uiText("back")) }
    for i = 1, 3 do bar(G, DESC_BARS[i], labels[i], small) end
    G.pop()
  end

  function app:draw(G, w, h)
    local s = T.session
    local _, small = fonts()
    -- the room as it stands, under everything
    if app.core and app.core.draw then app.core:draw(G, w, h) end
    if not s then return end
    setShape(((h or 178) + (app.bleed or BLEED)) / L)
    G.push()
    G.translate(0, -(app.bleed or BLEED))
    G.scale(L, L)
    -- the room dims (pic 2w: black at half alpha) and so do the bottom icons (black_mask_c)
    G.setColor(0, 0, 0, 0.5)
    G.rectangle("fill", 0, 20, 320, 192 + D)
    local mask = art("training/black_mask")
    G.setColor(0, 0, 0, mask and 136 / 255 or 0.5)
    G.rectangle("fill", 0, 212 + D, 320, 28)   -- the bottom strip (28 tall, see core_app)
    G.push()
    G.translate(0, D)
    local leave = art("training/home_return")
    if leave then
      local iw, ih = leave:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(leave, LEAVE[1] - LEAVE[3] / 2, LEAVE[2] - LEAVE[4] / 2, 0, LEAVE[3] / iw, LEAVE[4] / ih)
    end
    -- the Bags button is the return button while the drawer is out
    local ret = art("training/btn_return")
    if ret then
      local iw, ih = ret:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(ret, RETURN[1] - RETURN[3] / 2, RETURN[2] - RETURN[4] / 2, 0, RETURN[3] / iw, RETURN[4] / ih)
    end
    G.pop()
    -- the drawer
    pushDrawer(G)
    local cx = drawerX()
    local winImg = art("training/list_win")
    if winImg then window(G, winImg, cx, DRAWER.y, DRAWER.w, DRAWER.h, 1) else plainWindow(G, cx, DRAWER.y, DRAWER.w, DRAWER.h) end
    local ptn = art("training/home_bg_ptn")
    if ptn then
      local tw, th = ptn:getDimensions()
      ptn:setWrap("repeat", "repeat")
      local qw, qh = tw * PTN.repU, th * PTN.repV
      app.ptnQuad = app.ptnQuad or G.newQuad((1 - PTN.repU) / 2 * tw, (1 - PTN.repV) / 2 * th, qw, qh, tw, th)
      G.setColor(PTN.tint[1] / 255, PTN.tint[2] / 255, PTN.tint[3] / 255, 0.6)
      G.draw(ptn, app.ptnQuad, cx + PTN.dx - PTN.w / 2, DRAWER.y + PTN.dy - PTN.h / 2, 0, PTN.w / qw, PTN.h / qh)
    end
    local bags = Store.bags()
    for i = 1, N.LIMITS.BAG_MAX do
      local id = bags[i]
      if id then
        local x, y = slotCentre(i, cx)
        local scale = 1
        if view and view.index == i then scale = eval(PULSE, (clock - viewAt) % 16) end
        drawBag(G, id, x, y, scale)
      end
    end
    G.pop()
    drawMessage(G, small)
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  return app
end
