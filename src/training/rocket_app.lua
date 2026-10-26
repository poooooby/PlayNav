-- The alley's touch screen (src/training/rocket.lua's easter egg): a grimy brick wall, and from
-- the shop on the dealer's store over it (Rk.drawBottom): the money, the list (a tap picks a
-- bag, a second asks for it; a drag scrolls), the bag picked's line and the red back button in
-- its head. Asked "You want the ...?" (his words are on the top screen, with the alley), the
-- store dims and a YES / NO choice comes up over it, as the game's shops have it (up / down,
-- A, B; or a tap on YES or NO). Before the shop, and after, a tap goes on with what he says.

return function(mod, Pointer, T, Rules)
  local app = { id = "training_rocket", title = "ALLEY", live = true, hideTabs = true }

  function app:wantsSurface()
    local s = T.session
    return s ~= nil and s.mode == "rocket" and not (T.inBattle and T.inBattle())
  end

  local BLEED = 14
  local W, H = 256, 178
  -- the YES / NO choice, in app units (y from -bleed), rebuilt for the height drawn
  -- (the rects are made once and filled again for each draw's size)
  local G_ = { CHOICE = {}, YES = {}, NO = {} }
  local function rset(t, x, y, w, h) t.x, t.y, t.w, t.h = x, y, w, h; return t end
  local function geo(w, h)
    local top = -(app.bleed or BLEED)
    G_.top, G_.w, G_.h = top, w, h
    local cw, ch = 84, 56
    local cx, cy = w - cw - 22, top + (h - top) / 2 - ch / 2
    rset(G_.CHOICE, cx, cy, cw, ch)
    rset(G_.YES, cx, cy, cw, ch / 2)
    rset(G_.NO, cx, cy + ch / 2, cw, ch / 2)
    return G_
  end
  geo(W, H)
  -- the store's places come from its last draw (Rk.where: panel, back, rows, list)
  function app.geometry()
    local Rkm = T.rocket
    local wh = Rkm and Rkm.where or {}
    return { CHOICE = G_.CHOICE, YES = G_.YES, NO = G_.NO, BACK = wh.back, LIST = wh.list, ROWS = wh.rows,
      PANEL = wh.panel }
  end

  local function inRect(x, y, r) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
  local function Rk() return T.rocket end

  -- a press on the list may become a drag that scrolls it
  local drag = nil
  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "rocket") or s.trans then drag = nil; return end
    local Rkm = Rk()
    local st = Rkm and Rkm.state()
    if not st then return end
    local wh = Rkm.where
    local x, y = ev.x, ev.y
    if ev.phase == "pressed" then
      drag = nil
      if st.phase == "shop" and st.confirm == nil and inRect(x, y, wh.list) then
        drag = { id = ev.id, y0 = y, top0 = st.top, moved = false }
      end
      return
    end
    if ev.phase == "moved" then
      if drag and drag.id == ev.id then
        local rows = (Rkm.SHOP and Rkm.SHOP.rowH) or 20
        local d = (drag.y0 - y) / rows
        if math.abs(drag.y0 - y) > 6 then drag.moved = true end
        if drag.moved then T.rocketTap("scroll", drag.top0 + d) end
      end
      return
    end
    if ev.phase ~= "released" then return end
    local dragged = drag and drag.moved
    drag = nil
    if dragged or not Pointer.isTap(rec, 18, 1.2) then return end
    local H_ = mod.haptics
    if H_ then H_.pulse("tick") end
    if st.phase == "shop" then
      -- asked to buy: YES or NO
      if st.confirm ~= nil then
        if inRect(x, y, G_.YES) then T.rocketTap("yes") elseif inRect(x, y, G_.NO) then T.rocketTap("no") end
        return
      end
      if inRect(x, y, wh.back) then T.rocketTap("back"); return end
      for _, row in ipairs(wh.rows or {}) do
        if inRect(x, y, row) then T.rocketTap("row", row.idx); return end
      end
      T.rocketTap("advance")
      return
    end
    T.rocketTap("advance")
  end

  local function art(id)
    local A = app.assets
    if not (A and A.image) then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end

  -- a round art button (or a drawn disc), centred in r
  local function roundButton(G, id, r, fallback)
    local img = art(id)
    local cx, cy, d = r.x + r.w / 2, r.y + r.h / 2, math.min(r.w, r.h)
    if img then
      local iw, ih = img:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(img, cx, cy, 0, d / iw, d / ih, iw / 2, ih / 2)
    else
      G.setColor(fallback[1], fallback[2], fallback[3], 1)
      G.circle("fill", cx, cy, d / 2, 32)
    end
  end

  -- the YES / NO choice: a panel, the two words, the cursor at the one picked
  local function choiceRow(G, Rkm, font, r, word, on, nudge)
    local ty = r.y + (r.h - font:getHeight()) / 2 + nudge
    Rkm.print(G, font, word, r.x + 30, ty, 1, on and 1 or 0.78, on and 1 or 0.78)
    if on then
      local cx, cy = r.x + 18, ty + font:getHeight() / 2
      G.setColor(0, 0, 0, 0.7)
      G.polygon("fill", cx - 4.4, cy - 4.4, cx + 4.6, cy + 0.6, cx - 4.4, cy + 5.6)
      G.setColor(0.95, 0.22, 0.26, 1)
      G.polygon("fill", cx - 5, cy - 5, cx + 4, cy, cx - 5, cy + 5)
    end
  end
  local function drawChoice(G, Rkm, font, yes)
    local C = G_.CHOICE
    Rkm.slice(G, "rocket/panel", C.x, C.y, C.w, C.h, 8, 1, true)
    choiceRow(G, Rkm, font, G_.YES, "YES", yes, 2)
    choiceRow(G, Rkm, font, G_.NO, "NO", not yes, -2)
  end

  function app:draw(G, w, h)
    local s = T.session
    w, h = w or W, h or H
    geo(w, h)
    local top = G_.top
    local Rkm = Rk()
    if s and Rkm and Rkm.drawBottom then
      Rkm.drawBottom(G, s, 0, top, w, h - top)
      local st = Rkm.state()
      if st and st.phase == "shop" and st.shopT >= 1 then
        if st.confirm == nil then
          if Rkm.where.back then roundButton(G, "rocket/back", Rkm.where.back, { 0.8, 0.1, 0.12 }) end
        else
          drawChoice(G, Rkm, Rkm.fontAt(G, 11), st.confirm)
        end
      end
    else
      G.setColor(0.03, 0.035, 0.07, 1)
      G.rectangle("fill", 0, top, w, h - top)
    end
    -- in and out of the alley: black over everything
    local v = T.transView and T.transView("bottom")
    if v and v.black and v.black > 0 then
      G.setColor(0, 0, 0, v.black)
      G.rectangle("fill", -10, top - 10, w + 20, h - top + 20)
    end
    G.setColor(1, 1, 1, 1)
  end

  return app
end
