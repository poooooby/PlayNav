-- DECORATE, laid out as the game's customize (PANES, src/amie/panes.lua; its clips' motion in
-- code). The wallpaper fills the screen under a header with the wallpaper's
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
  local LOW_PANES = { "ac", "a9", "9z", "a5", "3q", "v", "b4", "1x" }

  -- the screen's panes: name, parent, tx, ty (the middle, from the parent's, y up), w, h, and
  -- its picture (lyt/amie_deco/<art>), words, or a window drawn here; panes with none of them
  -- are hit boxes
  local BLACK = { 0, 0, 0 }
  local WORDS = { size = 19, color = BLACK }
  local LIGHT = { size = 19, color = { 1, 1, 1 } }
  local COUNT = { size = 16, color = { 1, 1, 1 }, outline = BLACK }
  local PANES = {
    -- where a held thing can go: the room dimmed and the puff's spot, or the seats
    { "6z", nil, 0, 0, 30, 40, hidden = true },
    { "9t", "6z", 0, 0, 320, 240, window = "dim" },
    { "6t", "6z", 0, 26, 28, 18, art = "area_seat" },
    { "6v", "6z", 35, 1, 28, 18, art = "area_seat" },
    { "6x", "6z", -35, 1, 28, 18, art = "area_seat" },
    { "ad", "6z", 0, 4, 28, 17, art = "area_okashi" },
    -- the header: the lilac bar, the name on its paper tab, the wallpaper arrows
    { "b1", nil, 0, 102, 320, 36, art = "bar_title", tile = 10 },
    { "12", nil, 0, 0, 30, 40 },
    { "af", "12", 0, 105, 280, 36, window = "tab" },
    { "y", "12", 0, 106, 180, 20, text = WORDS },
    { "6p", "12", -108, 104, 60, 40 },
    { "6q", "12", 108, 104, 60, 40 },
    { "f", nil, -108, 104, 30, 30, art = "bgbutton_L" },
    { "h", nil, 108, 104, 30, 30, art = "bgbutton_R" },
    -- the drawer, folded below the screen until it comes up
    { "v", nil, 0, 0, 30, 40 },
    { "j", "v", 0, -185, 320, 202, window = "drawer" },
    { "az", "j", 0, 56, 320, 24, art = "goods_win_line_up" },
    { "ax", "j", 0, -53, 320, 24, art = "goods_win_line_dw" },
    { "t", "v", 0, -79, 136, 32, art = "tab_goods", hidden = true },
    { "w", "t", -47, 0, 16, 22, art = "tab_arrow", rz = 90 },
    { "10", "t", 10, 0, 90, 20, text = LIGHT },
    { "2t", "v", 0, -159, 30, 40 },
    { "9s", "2t", 0, 0, 10, 10 },
    { "al", "v", -140, -177, 30, 30, art = "bgbutton_L" },
    { "an", "v", 140, -177, 30, 30, art = "bgbutton_R" },
    { "aq", "v", -143, -177, 35, 60 },
    { "ap", "v", 143, -177, 35, 60 },
    -- the foot: the two pills, the session's words, the corner button
    { "9z", nil, -90, -106, 110, 32, art = "button_system" },
    { "a1", "9z", 0, 0, 90, 20, text = WORDS },
    { "a5", nil, 40, -106, 110, 32, art = "button_system" },
    { "a3", "a5", 0, 0, 90, 20, text = WORDS },
    { "ac", nil, -90, -106, 100, 25 },
    { "a9", nil, 40, -106, 100, 25 },
    { "b4", nil, -14, -107, 298, 36, window = "tab", hidden = true },
    { "1x", nil, -14, -105, 270, 20, text = WORDS, hidden = true },
    { "3q", nil, 145, -106, 30, 30 },
    { "3o", "3q", 0, 0, 30, 30, art = "button_exit" },
    { "6o", "3q", 0, 0, 30, 30 },
  }
  -- the drawer's cells, five across and three down on each page, the pages 280 apart on the
  -- anchor 9s (a page turn slides it), each with its count at its corner
  for set, x0 in pairs({ [MID] = -100, [LEFT] = -380, [RIGHT] = 180 }) do
    local counts = set == MID and MIDC or (set == LEFT and LEFTC or RIGHTC)
    for i, name in ipairs(set) do
      local c, r = (i - 1) % 5, math.floor((i - 1) / 5)
      PANES[#PANES + 1] = { name, "9s", x0 + 50 * c, 16 - 40 * r, 40, 40 }
      PANES[#PANES + 1] = { counts[i], name, 10, -13.5, 20, 10, text = COUNT }
    end
  end

  -- the clips' motion (the game's frames at FPS): the drawer folding up / down, the wallpaper
  -- and the drawer's pages sliding, the buttons' press
  local FOLDER_F, SLIDE_F, PRESS_F = 5, 8, 5
  local FOLDER_UP = 157                       -- v rises this far to open the drawer
  local PAGE_W = 280
  local PRESS = { { 0, 0.8 }, { 1, 1 }, { 3, 0.95 }, { 5, 1 } }   -- L_select / button_select's scale
  local folder = { up = false, f = FOLDER_F }
  local presses = {}           -- pane -> frames since its press

  local P = nil
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
    if D <= 0 then P.adjust = nil; return end
    local adj = { ["6z"] = { dy = -D / 2 } }
    for _, n in ipairs(LOW_PANES) do adj[n] = { dy = -D } end
    P.adjust = adj
  end

  -- the windows: the paper tab under the header's name and the foot's words (bg_tab, its
  -- corner mirrored round), the drawer (the lilac bar along its top, torn edge up, and its foot,
  -- white between), the dim over the room while a puff is held (black at 150)
  local function tabWindow(G2, x0, y0, w, h, a)
    local img = art("lyt/amie_deco/bg_tab")
    if not img then return end
    local iw, ih = img:getDimensions()
    local kx, ky = w / 2 / iw, h / 2 / ih
    G2.setColor(1, 1, 1, a)
    G2.draw(img, x0, y0, 0, kx, ky)
    G2.draw(img, x0 + w, y0, 0, -kx, ky)
    G2.draw(img, x0, y0 + h, 0, kx, -ky)
    G2.draw(img, x0 + w, y0 + h, 0, -kx, -ky)
  end
  local barQuad = nil
  local function drawerWindow(G2, x0, y0, w, h, a)
    local bar, white = art("lyt/amie_deco/bar_title"), art("lyt/amie_deco/goods_win_c")
    if not (bar and white) then return end
    local bw, bh = bar:getDimensions()
    local ww, wh = white:getDimensions()
    G2.setColor(1, 1, 1, a)
    G2.draw(white, x0, y0 + bh, 0, w / ww, (h - 2 * bh) / wh)
    bar:setWrap("repeat", "clamp")
    if not barQuad then barQuad = G2.newQuad(0, 0, w, bh, bw, bh) else barQuad:setViewport(0, 0, w, bh, bw, bh) end
    G2.draw(bar, barQuad, x0, y0 + bh, 0, 1, -1)
    G2.draw(bar, barQuad, x0, y0 + h - bh)
  end
  local function dimWindow(G2, x0, y0, w, h, a)
    G2.setColor(0, 0, 0, a * 150 / 255)
    G2.rectangle("fill", x0 - 200, y0 - 400, w + 400, h + 800)
  end

  local function screen()
    if P then return P end
    if not mod.panes then return nil end
    P = mod.panes.new(PANES, { art = art, prefix = "lyt/amie_deco/",
      windows = { tab = tabWindow, drawer = drawerWindow, dim = dimWindow } })
    app.shapeDirty = true
    return P
  end
  app.screen = screen

  local function press(name) presses[name] = 0 end
  local function fold(up) folder.up, folder.f = up, 0 end

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
        P:setText(counts[i], tostring(e.count))
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
    if cat then P:setText("10", cat) end
  end

  local function wallName(id) return Decor.name(id) end

  -- header, pills and the corner button for the current mode (only when something changed)
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
      -- the open drawer's pill pale (goods_btn_anm), the corner the check, the return or the
      -- tray (button_Tex_back / close / itemreturn)
      local lit = mode == "drawer"
      P:setImage("9z", (lit and tab == "interior") and "lyt/amie_deco/button_system_02" or "lyt/amie_deco/button_system")
      P:setImage("a5", (lit and tab == "puffs") and "lyt/amie_deco/button_system_02" or "lyt/amie_deco/button_system")
      P:setImage("3o", holding and "lyt/amie_deco/button_itemreturn"
        or (mode == "drawer" and "lyt/amie_deco/button_back" or "lyt/amie_deco/button_exit"))
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
    P:setText("y", name)
    P:setText("a1", tx("interior", "Interior Items"))
    P:setText("a3", tx("puffsTab", "Poke Puffs"))
    -- placement: a puff dims the room and shows its spot; an item shows the free seats
    P:set("6z", "visible", holding)
    P:set("9t", "visible", holding and held and held.puff or false)
    P:set("ad", "visible", holding and held and held.puff or false)
    -- the three seats while a cushion is held (the game's 0x4f78: all three, taken or not; none
    -- for an object, which ignores them)
    local seats = holding and held and not held.puff and Decor.isCushion(held.id) or false
    for _, n in ipairs(SEAT_PANES) do P:set(n, "visible", seats) end
    -- the session's words in the game's bottom bar
    P:set("b4", "visible", words ~= nil)
    P:set("1x", "visible", words ~= nil)
    if words then P:setText("1x", words) end
  end

  local function openDrawer(t)
    tab = t
    mode = "drawer"
    refreshCells()
    fold(true)
    G.se("drawer_open", "SE_SELECT")
  end
  local function closeDrawer()
    if mode ~= "drawer" then return end
    mode = "browse"
    fold(false)
  end

  -- ------- actions

  -- a press on a drawer cell takes the item into the finger (as the game: it follows the stylus
  -- and the drawer folds away; let go in the room to set it down, on the tray to put it back);
  -- held where the finger is, the item's middle (a puff: itself) under it. A tap leaves it held
  -- there, to be dragged.
  local function pick(e, rx, ry, pointer)
    local _, room = records()
    if e.count <= 0 then
      if e.puff then return end
      G.say(tx("whatDecor", "It's already in the room."), 2)
      return
    end
    if #(room.items or {}) >= Decor.MAX_ITEMS and not e.puff then
      G.say(tx("roomFull", "You cannot put out any more Décor!"), 2)
      return
    end
    rx, ry = rx or 160, ry or 165
    if e.puff then
      held = { id = e.id, puff = true, x = rx, y = ry + Decor.PUFF_LIFT }
    else
      local r = Decor.get(e.id)
      held = { id = e.id, x = rx, y = ry - Decor.FOOT + (r and r.h or 40) / 2 }
    end
    held.pointer, held.ox, held.oy, held.fresh = pointer, held.x - rx, held.y - ry, true
    fold(false)
    mode = "hold"
    G.se("hold_item", "SE_SELECT")
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
    G.se("put_back", "SE_SELECT")
  end

  -- let go at (x, y), room units
  local function drop(x, y)
    local decor, room = records()
    local h = held
    if h.puff then
      -- a puff let go anywhere in the room goes to the middle, the room's one puff spot (one out
      -- at a time: a new one takes the place of the one out, which is used up)
      local ok = Decor.setPuffOut(room, Store.puffs(), h.id)
      if ok then
        Store.savePuffs(); Store.saveRoom()
        if G.Visitors then
          if G.Visitors.sendOff then G.Visitors.sendOff() elseif G.Visitors.reset then G.Visitors.reset() end
        end
        if G.session then G.session.puffDrop = true end
        settle = { id = h.id, puff = true, x = Decor.PUFF_SPOT.x, y = Decor.PUFF_SPOT.y, t = 0 }
        G.se("place_puff", "SE_PIN")
      end
      held, mode = nil, "browse"
      return
    end
    -- as the game's code: a cushion on a seat's box takes the seat (one per seat: off a taken one
    -- it is pushed aside), anywhere else the 10-unit grid inside the room (Decor.settle)
    local sx, sy = Decor.settle(room, x, y, h.fromRoom, h.id)
    if h.fromRoom then
      Decor.move(room, h.fromRoom, sx, sy)
    else
      local ok, why = Decor.place(room, decor, h.id, sx, sy)
      if not ok and why == "full" then G.say(tx("roomFull", "You cannot put out any more Décor!"), 2) end
    end
    Store.saveRoom()
    settle = { id = h.id, x = sx, y = sy, t = 0 }
    G.se("place_item", "SE_PIN")
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
    -- > brings the next one in from the right (the room slides left: bg_move_left)
    slide = { dir = dir, to = to, f = 0 }
    press(dir > 0 and "h" or "f")
    G.se("select2", "SE_SELECT")
  end

  local function turnPage(dir)
    if turning then return end
    if #pageList() < 2 then return end
    -- > slides the pages left (item_scroll_left)
    turning = { dir = dir, f = 0 }
    press("al"); press("an")
    G.se("select", "SE_SELECT")
  end

  local function leave()
    if fade then return end
    press("3q")
    G.se("deco_done", "SE_SELECT")
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
      if mode == "drawer" and not turning then
        local e = cellAt(lx, ly)
        if e then pick(e, rx, ry, ev.id); return end
      end
      if mode == "browse" and not slide then
        -- a placed item picks up again; the puff once set out stays
        local _, room = records()
        local idx, it = Decor.itemAt(room, rx, ry, 4)
        if idx then
          held = { id = it.id, x = it.x, y = it.y, fromRoom = idx, pointer = ev.id, ox = it.x - rx, oy = it.y - ry,
            fresh = true }
          mode = "hold"
          G.se("hold_item", "SE_SELECT")
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
      press("3q")
      if mode == "hold" then putBack()
      elseif mode == "drawer" then closeDrawer(); G.se("back", "SE_SELECT")
      else leave() end
      return
    end
    if mode ~= "hold" then
      if boxHit("6p", lx, ly) then stepWallpaper(-1); return end
      if boxHit("6q", lx, ly) then stepWallpaper(1); return end
      if boxHit("ac", lx, ly, 3) then
        G.se("deco_tab", "SE_SELECT")
        if mode == "drawer" and tab == "interior" then closeDrawer() else openDrawer("interior") end
        return
      end
      if boxHit("a9", lx, ly, 3) then
        G.se("deco_tab", "SE_SELECT")
        if mode == "drawer" and tab == "puffs" then closeDrawer() else openDrawer("puffs") end
        return
      end
    end
    if mode == "drawer" and not turning then
      if boxHit("aq", lx, ly) then turnPage(-1); return end
      if boxHit("ap", lx, ly) then turnPage(1); return end
    end
  end

  -- ------- update

  local function onEnter()
    away = false
    mode, held, settle, turning, slide = "browse", nil, nil, nil, nil
    dressedClips, dressedKey = nil, nil
    fade = { t = 0, dir = -1 }
    folder.up, folder.f = false, FOLDER_F
    presses = {}
    if P then P:set("9s", "tx", 0) end
  end

  function app:update(dt)
    local s = G.session
    if not (s and s.mode == "decorate") then app.live = false; return end
    screen()
    if away then onEnter() end
    dt = dt or 0
    local df = dt * FPS
    folder.f = math.min(FOLDER_F, folder.f + df)
    for name, f in pairs(presses) do
      presses[name] = f + df
      if f + df >= PRESS_F then presses[name] = nil end
    end
    if slide then slide.f = math.min(SLIDE_F, slide.f + df) end
    if turning then turning.f = math.min(SLIDE_F, turning.f + df) end
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
    if slide and slide.f >= SLIDE_F then
      local decor, room = records()
      Decor.setWallpaper(room, decor, slide.to)
      Store.saveRoom()
      slide = nil
    end
    -- a page's slide ends: the middle row takes the new page
    if turning and turning.f >= SLIDE_F then
      local n = #pageList()
      page[tab] = (page[tab] - 1 + turning.dir) % n + 1
      turning = nil
      if P then P:set("9s", "tx", 0) end
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
  -- the clips' motion onto the panes
  local function pressScale(name)
    local f = presses[name]
    if not f then return 1 end
    for i = 2, #PRESS do
      local a, b = PRESS[i - 1], PRESS[i]
      if f <= b[1] then
        local t = (f - a[1]) / (b[1] - a[1])
        return a[2] + (b[2] - a[2]) * t * t * (3 - 2 * t)
      end
    end
    return 1
  end
  local function animate()
    local t = folder.f / FOLDER_F
    local open = folder.up and t or 1 - t
    P:set("v", "ty", FOLDER_UP * open)
    P:set("w", "rz", 90 - 180 * open)
    for _, name in ipairs({ "f", "h", "al", "an", "3q" }) do
      local k = pressScale(name)
      P:set(name, "sx", k); P:set(name, "sy", k)
    end
    if turning then P:set("9s", "tx", -turning.dir * PAGE_W * turning.f / SLIDE_F) end
  end

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
    -- the slide (bg_move_left / right: 320 over SLIDE_F frames, easing out)
    local x0 = 0
    if slide then
      local t = slide.f / SLIDE_F
      x0 = -slide.dir * 320 * (t + t * t - t * t * t)
    end
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
      animate()
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
    -- where to bring the "held" point (8 above the item's foot) so the item lands on seat i
    if what == "seatHold" then local sp = Decor.SEATS[i or 1]; return fromLyt(sp.x, sp.y - 8 + D / 2) end
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
    return folder.f < FOLDER_F
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
