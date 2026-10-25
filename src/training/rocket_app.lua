-- The alley on the touch screen (src/training/rocket.lua's easter egg): the 3D alley with the
-- dealer and the rain (src/training/rocket_scene.lua), his words in a dark box along the foot,
-- and while his shop is open (on the top screen) arrows up and down the list and the red button
-- that leaves. A (or a tap on his box) asks for the bag picked: "You want the ...? It's ...", with
-- a YES / NO choice above his box as the game's shops have it (up / down, A, B; or a tap on
-- YES or NO). Anywhere else a tap goes on with what he says.

return function(mod, Pointer, T, Rules)
  local app = { id = "training_rocket", title = "ALLEY", live = true, hideTabs = true }

  function app:wantsSurface()
    local s = T.session
    return s ~= nil and s.mode == "rocket" and not (T.inBattle and T.inBattle())
  end

  local BLEED = 14
  local W, H = 256, 178
  -- the places in app units (y from -bleed), rebuilt for the height drawn
  local G_ = {}
  local function geo(w, h)
    local top = -(app.bleed or BLEED)
    G_.top, G_.w, G_.h = top, w, h
    G_.BOX = { x = 6, y = h - 50, w = w - 52, h = 44 }
    G_.BACK = { x = w - 44, y = h - 46, w = 38, h = 38 }
    G_.UP = { x = w - 40, y = top + 8, w = 32, h = 30 }
    G_.DOWN = { x = w - 40, y = top + 44, w = 32, h = 30 }
    -- the YES / NO choice, above his box at the right
    G_.CHOICE = { x = w - 84, y = h - 50 - 56, w = 72, h = 50 }
    G_.YES = { x = G_.CHOICE.x, y = G_.CHOICE.y, w = G_.CHOICE.w, h = G_.CHOICE.h / 2 }
    G_.NO = { x = G_.CHOICE.x, y = G_.CHOICE.y + G_.CHOICE.h / 2, w = G_.CHOICE.w, h = G_.CHOICE.h / 2 }
    return G_
  end
  geo(W, H)
  function app.geometry() return G_ end

  local function inRect(x, y, r) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
  local function Rk() return T.rocket end

  -- a tap: on a control, else on with the words
  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "rocket") or s.trans then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 18, 1.2) then return end
    local st = Rk() and Rk().state()
    if not st then return end
    local x, y = ev.x, ev.y
    local H_ = mod.haptics
    if H_ then H_.pulse("tick") end
    if st.phase == "shop" then
      -- asked to buy: YES or NO
      if st.confirm ~= nil then
        if inRect(x, y, G_.YES) then T.rocketTap("yes") elseif inRect(x, y, G_.NO) then T.rocketTap("no") end
        return
      end
      if inRect(x, y, G_.BACK) then T.rocketTap("back")
      elseif inRect(x, y, G_.UP) then T.rocketTap("up")
      elseif inRect(x, y, G_.DOWN) then T.rocketTap("down")
      elseif inRect(x, y, G_.BOX) then T.rocketTap("buy")
      else T.rocketTap("advance") end
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

  -- the alley's panels (src/training/ui_art.lua's rocket/*, nine-sliced by Rk.slice)
  local function panel(G, r, alpha)
    local Rkm = Rk()
    if Rkm and Rkm.slice then Rkm.slice(G, "rocket/panel", r.x, r.y, r.w, r.h, 8, alpha or 0.96, true); return end
    G.setColor(0.04, 0.04, 0.06, alpha or 0.86)
    G.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
  end

  local function arrow(G, r, up)
    roundButton(G, up and "rocket/up" or "rocket/down", r, { 0.7, 0.1, 0.14 })
  end

  -- the YES / NO choice: a panel, the two words, the cursor at the one picked
  local function drawChoice(G, Rkm, font, yes)
    local C = G_.CHOICE
    panel(G, C, 0.98)
    for i, row in ipairs({ { G_.YES, "YES", yes }, { G_.NO, "NO", not yes } }) do
      local r, on = row[1], row[3]
      local ty = r.y + (r.h - font:getHeight()) / 2 + (i == 1 and 2 or -2)
      Rkm.print(G, font, row[2], r.x + 26, ty, 1, on and 1 or 0.78, on and 1 or 0.78)
      if on then
        local cx, cy = r.x + 15, ty + font:getHeight() / 2
        G.setColor(0, 0, 0, 0.7)
        G.polygon("fill", cx - 4.4, cy - 4.4, cx + 4.6, cy + 0.6, cx - 4.4, cy + 5.6)
        G.setColor(0.95, 0.22, 0.26, 1)
        G.polygon("fill", cx - 5, cy - 5, cx + 4, cy, cx - 5, cy + 5)
      end
    end
  end

  function app:draw(G, w, h)
    local s = T.session
    w, h = w or W, h or H
    geo(w, h)
    local top = G_.top
    local Rkm = Rk()
    local st = s and Rkm and Rkm.state() or nil
    local Scene = T.rocketScene
    if Scene then
      local ok, err = pcall(Scene.draw, G, 0, top, w, h - top, st and st.dealer or 0, st and st.clock or 0)
      if not ok and not app.warned then
        app.warned = true
        mod.log:warn("Super Training: the alley's draw failed (%s)", tostring(err))
      end
    else
      G.setColor(0.03, 0.035, 0.07, 1)
      G.rectangle("fill", 0, top, w, h - top)
    end
    if st then
      local fontAt = Rkm.fontAt
      local font, small = fontAt(G, 10), fontAt(G, 8)
      -- the shop's controls (the bag picked shows on the top screen)
      if st.phase == "shop" and st.shopT >= 1 then
        if st.confirm == nil then
          arrow(G, G_.UP, true)
          arrow(G, G_.DOWN, false)
          roundButton(G, "rocket/back", G_.BACK, { 0.8, 0.1, 0.12 })
        end
      end
      -- his words
      if st.line then
        local B = G_.BOX
        local bw = (st.phase == "shop") and B.w or (w - 12)
        panel(G, { x = B.x, y = B.y, w = bw, h = B.h }, 0.96)
        -- his name tag: a red glass plate over the box's corner
        G.setFont(small)
        local tag = "???"
        local tw, th = small:getWidth(tag) + 14, small:getHeight() + 5
        Rkm.slice(G, "rocket/red", B.x + 8, B.y - th + 3, tw, th, 4)
        Rkm.print(G, small, tag, B.x + 15, B.y - th + 5.5, 1, 0.9, 0.9)
        local shown = st.shown or ""
        if shown:find(Rkm.PD, 1, true) or shown:find("\n", 1, true) then
          -- his own lines (the price's sign drawn)
          Rkm.printLine(G, font, shown, B.x + 10, B.y + 8, 0.96, 0.94, 0.92)
        else
          G.setFont(font)
          G.setColor(0, 0, 0, 0.7)
          G.printf(shown, B.x + 10.6, B.y + 8.7, bw - 24, "left")
          G.setColor(0.96, 0.94, 0.92, 1)
          G.printf(shown, B.x + 10, B.y + 8, bw - 24, "left")
        end
        -- the line is out: a blinking mark to go on (not while the shop waits for a pick)
        if st.typed and st.phase ~= "shop" and (st.clock * 2) % 1 < 0.6 then
          local mx, my = B.x + bw - 12, B.y + B.h - 9
          G.setColor(1, 0.4, 0.4, 1)
          G.polygon("fill", mx - 4, my - 3, mx + 4, my - 3, mx, my + 2)
        end
      end
      if st.phase == "shop" and st.confirm ~= nil then drawChoice(G, Rkm, font, st.confirm) end
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
