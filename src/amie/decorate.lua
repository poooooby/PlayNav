-- DECORATE, played from the game's own layout (customize.bclyt, a/1/4/4 entry 0). The wallpaper fills the screen under a header with the wallpaper's
-- name and gold < > (they slide to the next owned wallpaper: bg_move_left / right); along
-- the bottom the "Interior Items" and "Poke Puffs" pills open the drawer (goodsFolder_up:
-- a 5 x 3 page of what is owned, with counts; < > turn pages, item_scroll_left / right) and
-- the corner button is the check (leave), the return (close the drawer) or, while an item
-- is held, the put-back tray (button_Tex_back / close / itemreturn). Picking an entry closes
-- the drawer and the item waits in the room: the header names it, a puff dims the room and
-- shows its spot, a cushion or object shows the free seats; let go near one and it settles
-- exactly on it, elsewhere it stays where it was let go (a puff only goes on its spot).
-- Tapping a placed item picks it up again. Rules and units: src/amie/decor.lua.

return function(mod, Pointer, G, Decor, Rules, Store, host)

  local app = { id = "decorate", title = "DECOR", live = true }

  function app:wantsSurface() return G.session ~= nil and G.session.mode == "decorate" end

  local L = 256 / 320
  local BLEED = 14
  local LH, D = 240, 0
  local FPS = 30
  local FADE_S = 10 / FPS
  local PER_PAGE = 15
  -- the drawer's three pages of cells (and their counts), row by row: the middle one shows,
  -- the left and right ones slide in when a page turns
  local MID = { "1z", "21", "23", "25", "27", "29", "2b", "2d", "2f", "2h", "2j", "2l", "2n", "2p", "2r" }
  local MIDC = { "4l", "4r", "4x", "53", "59", "4n", "4t", "4z", "55", "5b", "4p", "4v", "51", "57", "5d" }
  local LEFT = { "13", "15", "17", "19", "1b", "1d", "1f", "1h", "1j", "1l", "1n", "1p", "1r", "1t", "1v" }
  local LEFTC = { "3r", "3t", "3v", "3x", "3z", "41", "43", "45", "47", "49", "4b", "4d", "4f", "4h", "4j" }
  local RIGHT = { "2u", "2w", "2y", "30", "32", "34", "36", "38", "3a", "3c", "3e", "3g", "3i", "3k", "3m" }
  local RIGHTC = { "5f", "5l", "5r", "5x", "63", "5h", "5n", "5t", "5z", "65", "5j", "5p", "5v", "61", "67" }
  local SEAT_PANES = { "6t", "6v", "6x" }   -- Decor.SEATS in order
  local ROOM_PANES = { "6t", "6v", "6x", "ad" }
  local LOW_PANES = { "6s", "9z", "a5", "3q", "v", "b4", "1x" }

  local P, Pfail = nil, false
  local mode = "browse"        -- browse | drawer | hold
  local tab = "interior"       -- interior | puffs
  local page = { interior = 1, puffs = 1 }
  local turning = nil          -- { dir, clip } while a page slides
  local slide = nil            -- { dir, to, clip } while the wallpaper slides
  local held = nil             -- { id, puff, x, y, fromRoom, pointer, ox, oy }
  local settle = nil           -- { id, puff, x, y, t } the little drop when something lands
  local fade = nil             -- { t, dir = 1 out | -1 in, after }
  local away = true

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
  local function toLyt(x, y) return x / L, (y + bleed()) / L end
  local function toRoom(x, y) return x / L, (y + bleed()) / L - D / 2 end
  local function fromLyt(x, y) return x * L, y * L - bleed() end

  local function records()
    local decor = Decor.ensure(Store.decor())
    local room = Decor.ensureRoom(Store.room(), decor)
    return decor, room
  end

  local function tx(key, fallback) return G.tx and G.tx(key, nil, fallback) or fallback end

  -- ------- the screen

  local function applyShape()
    if not P or (P.shapeLH == LH and not app.shapeDirty) then return end
    P.shapeLH, app.shapeDirty = LH, false
    if D <= 0 then
      P.stretchY, P.stretchMode, P.adjust = nil, nil, nil
      return
    end
    P.stretchY, P.stretchMode = LH / 240, "backdrop"
    local adj = {}
    for _, n in ipairs(ROOM_PANES) do adj[n] = { dy = -D / 2 } end
    for _, n in ipairs(LOW_PANES) do adj[n] = { dy = -D } end
    P.adjust = adj
  end

  local function screen()
    if P or Pfail then return P end
    local S = mod.lyt
    P = S and S.open("amie_deco", "customize.bclyt", { "amie_deco" }) or nil
    if not P then Pfail = S == nil; return nil end
    P:set("74", "visible", false)   -- the wallpapers are drawn under the room's items, by us
    app.shapeDirty = true
    return P
  end
  app.screen = screen

  -- the drawer's pages for the open tab: { category, items = { { id, count, puff } } }.
  -- Interior Items go by the game's categories (a page per category, owned items only; a
  -- category of more than fifteen runs on to its own next page); Poke Puffs are one list.
  local function pageList()
    local decor, room = records()
    local out = {}
    local function chunk(category, items)
      for i = 1, math.max(1, #items), PER_PAGE do
        local pg = { category = category, items = {} }
        for k = i, math.min(#items, i + PER_PAGE - 1) do pg.items[#pg.items + 1] = items[k] end
        out[#out + 1] = pg
      end
    end
    if tab == "puffs" then
      local items = {}
      for _, p in ipairs(Rules.ownedPuffs(Store.puffs())) do items[#items + 1] = { id = p.id, count = p.count, puff = true } end
      chunk(nil, items)
      return out
    end
    for _, g in ipairs(Decor.ownedByCategory(decor)) do
      local items = {}
      for _, r in ipairs(g.rows) do items[#items + 1] = { id = r.id, count = Decor.inDrawer(room, decor, r.id) } end
      chunk(g.category, items)
    end
    if #out == 0 then out[1] = { category = nil, items = {} } end
    return out
  end
  app.pageList = pageList

  -- the counts: white with a black outline, readable on the white drawer and on the art
  local COUNT_TEXT = { align = "center", valign = "center", color = { 255, 255, 255, 255 }, outline = { 0, 0, 0, 255 } }
  local CENTRED = { align = "center", valign = "center" }

  local function fillCells(panes, counts, pg)
    local list = pg and pg.items or {}
    for i, name in ipairs(panes) do
      local e = list[i]
      if e then
        local img = art(e.id)
        P:set(name, "visible", true)
        if img then
          P:setImage(name, img)
          local iw, ih = img:getDimensions()
          local k = 40 / math.max(iw, ih)
          P:set(name, "w", iw * k); P:set(name, "h", ih * k)
        end
        P:set(name, "alpha", e.count > 0 and 255 or 110)
        P:set(counts[i], "visible", true)
        P:setText(counts[i], tostring(e.count), COUNT_TEXT)
      else
        P:set(name, "visible", false)
      end
    end
  end

  local function refreshCells()
    if not P then return end
    local list = pageList()
    local n = #list
    page[tab] = math.min(math.max(page[tab] or 1, 1), n)
    fillCells(MID, MIDC, list[page[tab]])
    -- the neighbours, for a page turn (wrapping round, as the game's arrows do)
    fillCells(LEFT, LEFTC, list[(page[tab] - 2) % n + 1])
    fillCells(RIGHT, RIGHTC, list[page[tab] % n + 1])
    local more = n > 1
    P:set("al", "visible", true); P:set("an", "visible", true)
    P:set("al", "alpha", more and 255 or 120); P:set("an", "alpha", more and 255 or 120)
    -- the drawer's tab names the page's category (the game's tab_goods, its arrow and text)
    local cat = list[page[tab]] and list[page[tab]].category
    for _, nme in ipairs({ "t", "w", "10" }) do P:set(nme, "visible", cat ~= nil) end
    if cat then P:setText("10", cat, CENTRED) end
  end

  local function wallName(id) return Decor.name(id) end

  -- header, pills and the corner button for the current mode (only when something changed:
  -- a clip played again starts over, and the texture clips' answer is on their last frame)
  local dressedClips, dressedKey = nil, nil
  local function dress()
    if not P then return end
    local _, room = records()
    local holding = mode == "hold"
    local s = G.session
    local words = s and s.message
    local clipsKey = mode .. "/" .. tab
    if clipsKey ~= dressedClips then
      dressedClips = clipsKey
      local lit = mode == "drawer"
      P:play((lit and tab == "interior") and "goods_btn_anm" or "goods_btn_anm_def", { from = 1 })
      P:play((lit and tab == "puffs") and "goods_btn_anm2" or "goods_btn_anm_def2", { from = 1 })
      P:play(holding and "button_Tex_itemreturn" or (mode == "drawer" and "button_Tex_close" or "button_Tex_back"), { from = 1 })
      -- the category tab only over the open Interior Items drawer (refreshCells names it)
      if mode ~= "drawer" then for _, nme in ipairs({ "t", "w", "10" }) do P:set(nme, "visible", false) end end
    end
    local name = (holding and held) and (held.puff and Rules.puffName(held.id) or Decor.name(held.id))
      or wallName((slide and slide.to) or room.wallpaper)
    local key = clipsKey .. "/" .. tostring(name) .. "/" .. tostring(words) .. "/" .. tostring(held and held.fromRoom)
      .. "/" .. #(room.items or {})
    if key == dressedKey then return end
    dressedKey = key
    P:set("f", "visible", not holding)
    P:set("h", "visible", not holding)
    P:setText("y", name, CENTRED)
    P:setText("a1", tx("interior", "Interior Items"), CENTRED)
    P:setText("a3", tx("puffsTab", "Poke Puffs"), CENTRED)
    -- placement: a puff dims the room and shows its spot; an item shows the free seats
    P:set("6z", "visible", holding)
    P:set("9t", "visible", holding and held and held.puff or false)
    P:set("ad", "visible", holding and held and held.puff or false)
    -- the no-go areas (area_ng) while an item is held: where it cannot be put down
    local item = holding and held and not held.puff or false
    P:set("9v", "visible", item)
    P:set("9x", "visible", item)
    local free = {}
    if holding and held and not held.puff then
      for _, sp in ipairs(Decor.freeSeats(room, held.fromRoom)) do free[sp.i] = true end
    end
    for i, n in ipairs(SEAT_PANES) do P:set(n, "visible", free[i] or false) end
    -- the session's words in the game's bottom bar
    P:set("b4", "visible", words ~= nil)
    P:set("1x", "visible", words ~= nil)
    if words then P:setText("1x", words, CENTRED) end
  end

  local function openDrawer(t)
    tab = t
    mode = "drawer"
    refreshCells()
    if P then P:play("goodsFolder_up") end
    host.playSe("SE_SELECT")
  end
  local function closeDrawer()
    if mode ~= "drawer" then return end
    mode = "browse"
    if P then P:play("goodsFolder_down") end
  end

  -- ------- actions

  local function pick(e)
    local _, room = records()
    if e.count <= 0 then
      if e.puff then return end
      G.say(tx("whatDecor", "It's already in the room."), 2)
      return
    end
    -- the item waits in the room to be dragged; the drawer folds away
    if e.puff then held = { id = e.id, puff = true, x = Decor.PUFF_SPOT.x + 50, y = Decor.PUFF_SPOT.y }
    else held = { id = e.id, x = 160, y = 165 } end
    if #(room.items or {}) >= Decor.MAX_ITEMS and not e.puff then
      held = nil
      G.say(tx("roomFull", "You cannot put out any more Décor!"), 2)
      return
    end
    if P then P:play("goodsFolder_down") end
    mode = "hold"
    host.playSe("SE_SELECT")
  end

  local function putBack()
    if not held then return end
    local _, room = records()
    if held.fromRoom then
      Decor.remove(room, held.fromRoom)
      Store.saveRoom()
    end
    held = nil
    mode = "browse"
    host.playSe("SE_SELECT")
  end

  -- let go at (x, y), room units
  local function drop(x, y)
    local decor, room = records()
    local h = held
    if h.puff then
      if not Decor.onPuffSpot(x, y) then h.x, h.y = x, y; return end
      local ok = Decor.setPuffOut(room, Store.puffs(), h.id)
      if ok then
        Store.savePuffs(); Store.saveRoom()
        if G.Visitors then
          if G.Visitors.sendOff then G.Visitors.sendOff() elseif G.Visitors.reset then G.Visitors.reset() end
        end
        if G.session then G.session.puffDrop = true end
        settle = { id = h.id, puff = true, x = Decor.PUFF_SPOT.x, y = Decor.PUFF_SPOT.y, t = 0 }
        host.playSe("SE_PIN")
      end
      held, mode = nil, "browse"
      return
    end
    -- a free seat, or the open floor; never a no-go area (the middle round the seats and the band
    -- below them), so a seat holds one item. There it stays held, as a puff off its spot does.
    local sx, sy = Decor.settle(room, x, y, h.fromRoom)
    if not sx then
      h.x, h.y = x, y
      if mod.haptics then mod.haptics.pattern("bad") end
      return
    end
    if h.fromRoom then
      Decor.move(room, h.fromRoom, sx, sy)
    else
      local ok, why = Decor.place(room, decor, h.id, sx, sy)
      if not ok and why == "full" then G.say(tx("roomFull", "You cannot put out any more Décor!"), 2) end
    end
    Store.saveRoom()
    settle = { id = h.id, x = sx, y = sy, t = 0 }
    host.playSe("SE_PIN")
    held, mode = nil, "browse"
  end

  local function stepWallpaper(dir)
    if slide then return end
    local decor, room = records()
    local walls = Decor.owned(decor, "wall")
    if #walls < 2 then return end
    local at = 1
    for i, r in ipairs(walls) do if r.id == room.wallpaper then at = i end end
    local to = walls[(at - 1 + dir) % #walls + 1].id
    -- > brings the next one in from the right (the room slides left)
    local clip = dir > 0 and "bg_move_left" or "bg_move_right"
    slide = { dir = dir, to = to, clip = clip }
    if P then
      P:play(dir > 0 and "R_select" or "L_select")
      P:play(clip)
    end
    host.playSe("SE_SELECT")
  end

  local function turnPage(dir)
    if turning then return end
    if #pageList() < 2 then return end
    local clip = dir > 0 and "item_scroll_left" or "item_scroll_right"
    turning = { dir = dir, clip = clip }
    if P then
      P:play("itembutton_select")
      P:play(clip)
    end
    host.playSe("SE_SELECT")
  end

  local function leave()
    if fade then return end
    if P then P:play("button_select") end
    host.playSe("SE_SELECT")
    fade = { t = 0, dir = 1, after = function()
      Store.saveRoom()
      if G.session then G.session.fromDecorate = true end
      G.enterHome(false)
    end }
  end

  -- B on the top screen: the drawer folds, a held item goes back, else leave
  function G.decorateBack()
    if mode == "drawer" then closeDrawer()
    elseif mode == "hold" then putBack()
    else leave() end
  end

  -- ------- input

  local function boxHit(name, x, y, pad)
    if not P then return false end
    local bx, by, bw, bh = P:box(name)
    if not bx then return false end
    pad = pad or 0
    -- a mirrored pane (the right arrow's 6q is -60 wide) reports a negative size
    if bw < 0 then bx, bw = bx + bw, -bw end
    if bh < 0 then by, bh = by + bh, -bh end
    return x >= bx - pad and x <= bx + bw + pad and y >= by - pad and y <= by + bh + pad
  end

  local function heldHit(x, y)
    if not held then return false end
    if held.puff then return math.abs(x - held.x) <= 24 and y >= held.y - Decor.PUFF_LIFT - 24 and y <= held.y - Decor.PUFF_LIFT + 24 end
    local r = Decor.get(held.id)
    local w, h = (r and r.w or 40) / 2 + 6, (r and r.h or 40) + 6
    local foot = held.y + Decor.FOOT
    return math.abs(x - held.x) <= w and y <= foot + 6 and y >= foot - h
  end

  local function cellAt(lx, ly)
    for i, name in ipairs(MID) do
      if boxHit(name, lx, ly, 5) then
        local pg = pageList()[page[tab]]
        return pg and pg.items[i]
      end
    end
    return nil
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "decorate") or fade then return end
    local lx, ly = toLyt(ev.x, ev.y)
    local rx, ry = toRoom(ev.x, ev.y)
    if ev.phase == "pressed" then
      if mode == "hold" and heldHit(rx, ry) then
        held.pointer, held.ox, held.oy = ev.id, held.x - rx, held.y - ry
        return
      end
      if mode == "browse" and not slide then
        -- a placed item picks up again; the puff once set out stays
        local _, room = records()
        local idx, it = Decor.itemAt(room, rx, ry, 4)
        if idx then
          held = { id = it.id, x = it.x, y = it.y, fromRoom = idx, pointer = ev.id, ox = it.x - rx, oy = it.y - ry,
            fresh = true }
          mode = "hold"
          host.playSe("SE_SELECT")
          return
        end
        local ps = Decor.PUFF_SPOT
        if room.puffOut and math.abs(rx - ps.x) <= 22 and math.abs(ry - (ps.y - Decor.PUFF_LIFT)) <= 22 then
          G.say(tx("usedNoReturn", "Used Poké Puffs can't be put back."), 2.5)
          return
        end
      end
      return
    end
    if ev.phase == "moved" then
      if held and held.pointer == ev.id then
        held.x, held.y = rx + (held.ox or 0), ry + (held.oy or 0)
      end
      return
    end
    -- released / cancelled
    if held and held.pointer == ev.id then
      held.pointer = nil
      local fresh = held.fresh
      held.fresh = nil
      if ev.phase ~= "released" then return end
      if boxHit("6o", lx, ly, 6) then putBack(); return end
      -- a tap on a placed item picks it up and leaves it held (the spots show); a drag sets it down
      if fresh and Pointer.isTap(rec, 8, 1.0) then return end
      drop(held.x, held.y)
      return
    end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    if boxHit("6o", lx, ly, 4) then
      if P then P:play("button_select") end
      if mode == "hold" then putBack()
      elseif mode == "drawer" then closeDrawer(); host.playSe("SE_SELECT")
      else leave() end
      return
    end
    if mode ~= "hold" then
      if boxHit("6p", lx, ly) then stepWallpaper(-1); return end
      if boxHit("6q", lx, ly) then stepWallpaper(1); return end
      if boxHit("ac", lx, ly, 3) then
        if mode == "drawer" and tab == "interior" then closeDrawer() else openDrawer("interior") end
        return
      end
      if boxHit("a9", lx, ly, 3) then
        if mode == "drawer" and tab == "puffs" then closeDrawer() else openDrawer("puffs") end
        return
      end
    end
    if mode == "drawer" and not turning then
      if boxHit("aq", lx, ly) then turnPage(-1); return end
      if boxHit("ap", lx, ly) then turnPage(1); return end
      local e = cellAt(lx, ly)
      if e then pick(e) end
    end
  end

  -- ------- update

  local function onEnter()
    away = false
    mode, held, settle, turning, slide = "browse", nil, nil, nil, nil
    dressedClips, dressedKey = nil, nil
    fade = { t = 0, dir = -1 }
    if P then
      P:play("goodsFolder_down", { from = 5 })
      for _, name in ipairs(MID) do P:clear(name, "tx") end
    end
  end

  function app:update(dt)
    local s = G.session
    if not (s and s.mode == "decorate") then app.live = false; return end
    screen()
    if away then onEnter() end
    dt = dt or 0
    if P then P:advance(dt * FPS) end
    if fade then
      fade.t = fade.t + dt
      if fade.t >= FADE_S then
        local after = fade.after
        fade = nil
        if after then after() end
      end
    end
    if settle then
      settle.t = settle.t + dt
      if settle.t > 0.25 then settle = nil end
    end
    -- the wallpaper's slide ends: the new one is the room's
    if slide and (not P or P:finished(slide.clip)) then
      local decor, room = records()
      Decor.setWallpaper(room, decor, slide.to)
      Store.saveRoom()
      if P then P:stop(slide.clip) end
      slide = nil
    end
    -- a page's slide ends: the middle row takes the new page
    if turning and (not P or P:finished(turning.clip)) then
      local n = #pageList()
      page[tab] = (page[tab] - 1 + turning.dir) % n + 1
      if P then P:stop(turning.clip) end
      turning = nil
      refreshCells()
    end
    app.live = true
  end

  -- ------- drawing (layout units)

  local function drawItem(G2, id, x, y, k, alpha)
    local img = art(id)
    k = k or 1
    G2.setColor(1, 1, 1, alpha or 1)
    if img then
      local iw, ih = img:getDimensions()
      G2.draw(img, x, y + Decor.FOOT, 0, k, k, iw / 2, ih)
    else
      local r = Decor.get(id)
      local w, h = (r and r.w or 40) * k, (r and r.h or 40) * k * 0.6
      G2.setColor(0.8, 0.6, 0.4, alpha or 1)
      G2.rectangle("fill", x - w / 2, y + Decor.FOOT - h, w, h, 4, 4)
    end
  end
  app.drawItem = drawItem

  local function drawPuff(G2, id, x, y, k, alpha)
    local img = art(id)
    G2.setColor(1, 1, 1, alpha or 1)
    local cy = y - Decor.PUFF_LIFT
    if img then
      local iw, ih = img:getDimensions()
      G2.draw(img, x, cy, 0, 40 * (k or 1) / iw, 40 * (k or 1) / ih, iw / 2, ih / 2)
    else
      G2.setColor(0.95, 0.55, 0.2, alpha or 1)
      G2.ellipse("fill", x, cy, 12, 9)
    end
  end

  -- the game's 320x240 picture, its Poke Ball's middle on the puff's spot (Decor.wallPlace)
  local function coverDraw(G2, img, x)
    local iw, ih = img:getDimensions()
    local sc, ox, oy = Decor.wallPlace(LH, D / 2)
    G2.draw(img, x + ox, oy, 0, 320 * sc / iw, 240 * sc / ih)
  end

  local function drawWallpapers(G2, room)
    local cur = art(room.wallpaper) or art("bg/plain")
    G2.setColor(1, 1, 1, 1)
    if not cur then
      G2.setColor(0.98, 0.86, 0.45, 1)
      G2.rectangle("fill", 0, 0, 320, LH)
      return
    end
    local x0 = 0
    if P then x0 = (P:box("72")) or 0 end
    coverDraw(G2, cur, x0)
    if slide then
      local nxt = art(slide.to)
      if nxt then coverDraw(G2, nxt, x0 + (slide.dir > 0 and 320 or -320)) end
    end
  end

  function app:draw(G2, w, h)
    local s = G.session
    setShape(h)
    local decor, room = records()
    G2.push()
    G2.translate(0, -bleed())
    G2.scale(L, L)
    drawWallpapers(G2, room)
    if not s then G2.pop(); return end
    -- the room scene, D/2 lower on a taller screen
    G2.push()
    G2.translate(0, D / 2)
    local order = {}
    for i, it in ipairs(room.items or {}) do order[#order + 1] = { i = i, it = it } end
    table.sort(order, function(a, b) return (a.it.y or 0) < (b.it.y or 0) end)
    for _, o in ipairs(order) do
      if not (held and held.fromRoom == o.i) then
        local k = 1
        if settle and not settle.puff and settle.x == o.it.x and settle.y == o.it.y then
          k = 1 + 0.12 * math.sin(math.min(1, settle.t / 0.25) * math.pi)
        end
        drawItem(G2, o.it.id, o.it.x, o.it.y, k, 1)
      end
    end
    if room.puffOut then
      local k = (settle and settle.puff) and (1 + 0.12 * math.sin(math.min(1, settle.t / 0.25) * math.pi)) or 1
      drawPuff(G2, room.puffOut, Decor.PUFF_SPOT.x, Decor.PUFF_SPOT.y, k, 1)
    end
    G2.pop()
    if P then
      dress()
      -- the page turn: all three pages ride the anchor 9s the clip moves
      local off = 0
      if turning then
        local bx = P:box("9s")
        off = bx and (bx + 5 - 160) or 0
      end
      for _, set in ipairs({ MID, LEFT, RIGHT }) do
        for _, name in ipairs(set) do
          if off ~= 0 then
            local pane = P.L.byName[name]
            P:set(name, "tx", pane.t[1] + off)
          else
            P:clear(name, "tx")
          end
        end
      end
      applyShape()
      P:draw(G2)
    else
      G2.setColor(0, 0, 0, 0.6)
      G2.rectangle("fill", 0, LH - 30, 320, 30)
      G2.setColor(1, 1, 1, 1)
      G2.print("DECORATE (the game's art is needed)", 10, LH - 24, 0, 1 / L, 1 / L)
    end
    -- what is held rides over everything, in the room's place
    if held then
      G2.push()
      G2.translate(0, D / 2)
      if held.puff then drawPuff(G2, held.id, held.x, held.y, 1, 1) else drawItem(G2, held.id, held.x, held.y, 1, 1) end
      G2.pop()
    end
    if fade then
      local k = math.min(1, fade.t / FADE_S)
      G2.setColor(0, 0, 0, fade.dir > 0 and k or 1 - k)
      G2.rectangle("fill", 0, -20, 320, LH + 40)
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  -- ------- for the driver and tests: where to tap (app units)

  local function centre(name)
    if not P then return nil end
    local bx, by, bw, bh = P:box(name)
    if not bx then return nil end
    return fromLyt(bx + bw / 2, by + bh / 2)
  end
  function app.tapPoint(what, i)
    if what == "interior" then return centre("ac") end
    if what == "puffs" then return centre("a9") end
    if what == "corner" then return centre("6o") end
    if what == "wallLeft" then return centre("6p") end
    if what == "wallRight" then return centre("6q") end
    if what == "pageLeft" then return centre("aq") end
    if what == "pageRight" then return centre("ap") end
    if what == "cell" then return centre(MID[i or 1]) end
    if what == "seat" then local sp = Decor.SEATS[i or 1]; return fromLyt(sp.x, sp.y + D / 2) end
    if what == "puffSpot" then return fromLyt(Decor.PUFF_SPOT.x, Decor.PUFF_SPOT.y - Decor.PUFF_LIFT + D / 2) end
    if what == "held" and held then
      if held.puff then return fromLyt(held.x, held.y - Decor.PUFF_LIFT + D / 2) end
      return fromLyt(held.x, held.y - 8 + D / 2)
    end
    if what == "room" then return fromLyt(i and i[1] or 160, (i and i[2] or 160) + D / 2) end
    return nil
  end
  function app.state()
    local pg = pageList()[page[tab] or 1]
    return { mode = mode, tab = tab, page = page[tab], category = pg and pg.category, held = held and held.id,
      sliding = slide ~= nil }
  end
  -- something is still moving (a fade, a slide, a page turn, the drawer, a settle)
  function app.busy()
    if fade or slide or turning or settle then return true end
    if P and not (P:finished("goodsFolder_up") and P:finished("goodsFolder_down")) then return true end
    return false
  end
  app.setTab = function(t) tab = t end

  function app:releaseAll()
    if held then held.pointer = nil end
  end
  function app.leave()
    app:releaseAll()
    away = true
    fade = nil
  end
  return app
end
