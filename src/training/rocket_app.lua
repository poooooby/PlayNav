-- The alley on the touch screen (src/training/rocket.lua's easter egg): the 3D alley with the
-- dealer and the rain (src/training/rocket_scene.lua), his words in a dark box along the foot,
-- and while his shop is open (on the top screen) the bag picked shown big (a tap asks to buy
-- it), arrows up and down the list, Yes / No when asked, and the red button that leaves.
-- Anywhere else a tap goes on with what he says.

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
    G_.PICK = { x = 6, y = top + 8, w = 126, h = 54 }
    G_.YES = { x = w - 136, y = h - 80, w = 52, h = 26 }
    G_.NO = { x = w - 78, y = h - 80, w = 52, h = 26 }
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
      if st.confirm ~= nil then
        if inRect(x, y, G_.YES) then T.rocketTap("yes")
        elseif inRect(x, y, G_.NO) then T.rocketTap("no") end
        return
      end
      if inRect(x, y, G_.BACK) then T.rocketTap("back")
      elseif inRect(x, y, G_.UP) then T.rocketTap("up")
      elseif inRect(x, y, G_.DOWN) then T.rocketTap("down")
      elseif inRect(x, y, G_.PICK) then T.rocketTap("buy")
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

  -- a round art button (or a drawn disc), centred in r, pressed in by `down`
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

  local function panel(G, r, alpha)
    G.setColor(0.04, 0.04, 0.06, alpha or 0.86)
    G.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
    G.setColor(0.6, 0.06, 0.1, 1)
    G.setLineWidth(1.2)
    G.rectangle("line", r.x, r.y, r.w, r.h, 5, 5)
  end

  local function arrow(G, r, up)
    panel(G, r, 0.75)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    local s = up and -1 or 1
    G.setColor(0.95, 0.9, 0.9, 1)
    G.polygon("fill", cx - 8, cy - 4 * s, cx + 8, cy - 4 * s, cx, cy + 6 * s)
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
      -- the shop's controls
      if st.phase == "shop" and st.shopT >= 1 then
        if st.confirm == nil then
          local P = G_.PICK
          panel(G, P)
          local id = st.id
          if id then
            Rkm.bagIcon(G, id, P.x + 18, P.y + P.h / 2, P.h - 10)
            G.setFont(font)
            G.setColor(1, 1, 1, 1)
            G.print(T.bagName(id), P.x + 36, P.y + 7)
            G.setColor(1, 0.86, 0.35, 1)
            Rkm.printMoney(G, font, Rkm.price(id) or 0, P.x + 36, P.y + 7 + font:getHeight())
            G.setFont(small)
            G.setColor(1, 0.45, 0.45, 1)
            G.print("TAP TO BUY", P.x + 36, P.y + P.h - small:getHeight() - 5)
          end
          arrow(G, G_.UP, true)
          arrow(G, G_.DOWN, false)
        else
          for _, b in ipairs({ { G_.YES, "YES", st.confirm == true }, { G_.NO, "NO", st.confirm == false } }) do
            local r, on = b[1], b[3]
            G.setColor(on and 0.6 or 0.12, on and 0.06 or 0.12, on and 0.1 or 0.14, 0.95)
            G.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
            G.setColor(on and 1 or 0.6, on and 0.5 or 0.2, on and 0.5 or 0.25, 1)
            G.setLineWidth(1.2)
            G.rectangle("line", r.x, r.y, r.w, r.h, 5, 5)
            G.setFont(font)
            G.setColor(1, 1, 1, 1)
            G.print(b[2], r.x + (r.w - font:getWidth(b[2])) / 2, r.y + (r.h - font:getHeight()) / 2)
          end
        end
        if st.confirm == nil then roundButton(G, "rocket/back", G_.BACK, { 0.8, 0.1, 0.12 }) end
      end
      -- his words
      if st.line then
        local B = G_.BOX
        local bw = (st.phase == "shop") and B.w or (w - 12)
        panel(G, { x = B.x, y = B.y, w = bw, h = B.h }, 0.88)
        -- his name tag
        G.setFont(small)
        local tag = "???"
        local tw = small:getWidth(tag) + 12
        G.setColor(0.32, 0.03, 0.06, 1)
        G.rectangle("fill", B.x + 8, B.y - small:getHeight() - 2, tw, small:getHeight() + 4, 3, 3)
        G.setColor(1, 0.85, 0.85, 1)
        G.print(tag, B.x + 14, B.y - small:getHeight())
        G.setFont(font)
        G.setColor(0.95, 0.93, 0.9, 1)
        G.printf(st.shown or "", B.x + 9, B.y + 7, bw - 22, "left")
        -- the line is out: a blinking mark to go on (not while the shop waits for a pick)
        if st.typed and st.phase ~= "shop" and (st.clock * 2) % 1 < 0.6 then
          local mx, my = B.x + bw - 12, B.y + B.h - 9
          G.setColor(1, 0.4, 0.4, 1)
          G.polygon("fill", mx - 4, my - 3, mx + 4, my - 3, mx, my + 2)
        end
      end
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
