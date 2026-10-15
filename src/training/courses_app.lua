-- REGIMENS, the course picker, as the game lays it out (a/1/1/3 entry 0: stageselect_lower on
-- the touch screen, stageselect_upper on the top; dump them with tools/clyt.py). One level per
-- page: the six courses in the layout's slots (Sp. Atk, HP, Attack / Sp. Def, Speed, Defense,
-- the game's own order), each its course picture with the stat's label, CLEARED and the award
-- medal; the medal-count tab with the Pokemon's icon; the level band; the bar with the page and
-- the return button. Tapping a course puts the brackets round it, its words in the message
-- window and its card on the top screen; tapping it again starts it. The secret courses come
-- as two more pages once the Pokemon is Fully Trained.
--
-- The card (drawn by the session's top layer through T.drawCard) is stageselect_upper at
-- 400x240, scaled into the top screen.

return function(mod, Pointer, T, Rules)
  local app = { id = "training_courses", title = "REGIMENS", live = true, hideTabs = true }
  local N = Rules.N
  -- src/training/lyt.lua: the layout drawing helpers (nil when missing: plain shapes)
  local L
  do
    local src = mod.read and mod:read("src/training/lyt.lua")
    local chunk = src and load(src, "@" .. tostring(mod.path) .. "/src/training/lyt.lua")
    local ok, make = pcall(chunk or error)
    if ok and type(make) == "function" then L = make() end
  end
  app.lyt = L

  function app:wantsSurface()
    return T.session ~= nil and T.session.mode == "courses" and not (T.inBattle and T.inBattle())
  end

  local K = 256 / 320
  local BLEED = 14

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end

  local function fonts()
    if app.fontsFn then
      local f, s = app.fontsFn()
      if f then return f, s or f end
    end
    local f = love.graphics.getFont()
    return f, f
  end

  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end

  -- ------- the layout (stageselect_lower, 320x240)

  local COLS = {
    bg = { { 0, 111, 209, 255 }, { 0, 111, 209, 255 }, { 84, 200, 255, 255 }, { 84, 200, 255, 255 } },
    glowLow = { { 168, 226, 255, 30 }, { 168, 226, 255, 30 }, { 168, 226, 255, 255 }, { 168, 226, 255, 255 } },
    glowHigh = { { 168, 226, 255, 255 }, { 168, 226, 255, 255 }, { 168, 226, 255, 30 }, { 168, 226, 255, 30 } },
    ptn = { { 0, 80, 147, 150 }, { 0, 80, 147, 150 }, { 0, 80, 147, 150 }, { 0, 80, 147, 150 } },
    meter = { { 162, 255, 255, 255 }, { 162, 255, 255, 255 }, { 162, 255, 255, 255 }, { 162, 255, 255, 255 } },
    tab = { { 168, 226, 255, 255 }, { 255, 255, 255, 255 }, { 168, 226, 255, 255 }, { 255, 255, 255, 255 } },
    band = { { 0, 128, 128, 255 }, { 0, 128, 128, 255 }, { 255, 255, 255, 255 }, { 255, 255, 255, 255 } },
  }
  -- the six slots: centre, and which stat's course sits there (the game's icon order)
  local SLOTS = { { 64, 105, "spa" }, { 160, 105, "hp" }, { 256, 105, "atk" },
    { 64, 178, "spd" }, { 160, 178, "spe" }, { 256, 178, "def" } }
  local RETURN = { 300, 225, 27, 27 }
  local ARROW_L, ARROW_R = { 20, 225, 14, 26 }, { 90, 225, 14, 26 }
  -- stageselect_lower_cur_anime: the brackets breathe 1 -> 1.1 -> 1 over 24 frames
  local CUR = { { 0, 1, 0.005 }, { 20, 1.1, 0 }, { 24, 1, -0.025 } }
  -- the + pattern drifts (-2, -1) tiles every 200 frames (bg_anime)
  local PTN = { u = -2 / 200, v = -1 / 200 }

  local function rect(cx, cy, w, h)
    return { x = (cx - w / 2) * K, y = (cy - h / 2) * K - BLEED, w = w * K, h = h * K }
  end
  local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

  -- ------- pages: the open levels, then the secret courses (six to a page)

  local page = 1
  app.clock = 0

  local function pages()
    local out = {}
    local list = T.courseList and T.courseList() or {}
    for lv = 1, 3 do
      local row = {}
      for _, c in ipairs(list) do
        if not c.secret and c.level == lv then row[c.stat] = c end
      end
      local first = row.spa or row.hp
      if first and (lv == 1 or T.canEnter(first)) then
        local slots = {}
        for i, sl in ipairs(SLOTS) do slots[i] = row[sl[3]] end
        out[#out + 1] = { level = lv, slots = slots }
      end
    end
    local s = T.session
    if s and s.rec.fully then
      local secrets = {}
      for _, c in ipairs(list) do if c.secret then secrets[#secrets + 1] = c end end
      table.sort(secrets, function(a, b) return a.secret < b.secret end)
      for p0 = 0, math.ceil(#secrets / 6) - 1 do
        local slots = {}
        for i = 1, 6 do slots[i] = secrets[p0 * 6 + i] end
        out[#out + 1] = { secret = p0 + 1, level = slots[1] and slots[1].level, slots = slots }
      end
    end
    return out
  end
  app.pages = pages

  local function current()
    local ps = pages()
    if page > #ps then page = #ps end
    if page < 1 then page = 1 end
    return ps[page], #ps
  end

  local function selected()
    local s = T.session
    return s and s.picked or nil
  end

  function app.select(id)
    local s = T.session
    if not s then return end
    s.picked = id
    -- the page that holds it
    for i, p in ipairs(pages()) do
      for _, c in pairs(p.slots) do if c and c.id == id then page = i end end
    end
  end
  function app.selected() return selected() end
  function app.page() return page end

  function app.setPage(n)
    local _, count = current()
    if n < 1 or n > count or n == page then return false end
    page = n
    local s = T.session
    if s then s.picked = nil end
    return true
  end

  -- where things are, in app space, for taps and the drivers
  function app.geometry()
    local slots = {}
    for i, sl in ipairs(SLOTS) do slots[i] = rect(sl[1], sl[2], 64, 64) end
    return { slots = slots, RETURN = rect(RETURN[1], RETURN[2], 34, 30), ARROW_L = rect(ARROW_L[1], ARROW_L[2], 30, 30),
      ARROW_R = rect(ARROW_R[1], ARROW_R[2], 30, 30),
      slotOf = function(id)
        local p = current()
        for i, c in pairs(p and p.slots or {}) do if c and c.id == id then return slots[i] end end
      end }
  end

  local function pick(c)
    local s = T.session
    if not (s and c) then return end
    if s.picked == c.id then
      T.startCourse(c.id)
      return
    end
    s.picked = c.id
    s.message = nil
    local ok, why = T.canEnter(c)
    if not ok then
      T.say(why == "not_fully_trained" and (T.gameLine("training_courses", 168) or "Only a Fully Trained POKeMON may enter.")
        or T.resultText("locked"), 3)
    end
    if T.playSe then T.playSe("select_course", "SE_SELECT") end
  end

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "courses") or s.trans then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    local g = app.geometry()
    if inRect(x, y, g.RETURN) then T.goTo("core"); return end
    local p, count = current()
    if count > 1 then
      if inRect(x, y, g.ARROW_L) then app.setPage(page - 1); return end
      if inRect(x, y, g.ARROW_R) then app.setPage(page + 1); return end
    end
    for i, r in ipairs(g.slots) do
      local c = p and p.slots[i]
      if c and inRect(x, y, r) then pick(c); return end
    end
  end

  -- L / R turn the page
  T.pickerInput = function(input)
    if input:wasPressed("l") or input:wasPressed("left") then app.setPage(page - 1)
    elseif input:wasPressed("r") or input:wasPressed("right") then app.setPage(page + 1) end
  end

  function app:update(dt) app.clock = app.clock + (dt or 0) * 30 end

  -- ------- drawing (layout units, scaled by K onto the 256x192 surface)

  local function drawBackground(G, W, H, cols, ptnAlpha, rep)
    if not L then
      G.setColor(0.1, 0.5, 0.85, 1)
      G.rectangle("fill", 0, 0, W, H)
      return
    end
    L.quad(G, nil, W / 2, H / 2, W, H, { colors = cols.bg })
    local glow = art("training/home_bg01")
    if glow and cols.glowLow then
      -- the touch screen: the grid lines above (flipped) and below the horizon
      L.quad(G, glow, W / 2, H * 0.333, W, H * 0.667, { colors = cols.glowHigh, flipY = true })
      L.quad(G, glow, W / 2, H * 0.833, W, H * 0.333, { colors = cols.glowLow })
    elseif glow then
      -- the top screen: one sheet, flipped, fading downwards
      L.quad(G, glow, W / 2, H / 2, W, H, { colors = cols.glowHigh, flipY = true })
    end
    local ptn = art("training/home_bg_ptn")
    if ptn then
      local t = app.clock % 200
      L.quad(G, ptn, W / 2, H / 2, W, H, { colors = cols.ptn, repU = rep[1], repV = rep[2], u0 = -PTN.u * t, v0 = -PTN.v * t })
    end
  end

  -- the message window (training_message_lower 71: 310x80 at 160,60, three lines)
  local function drawWords(G, text, small)
    local win = art("training/win_bl")
    local mx, my, mw, mh = 160, 60, 310, 80
    if win then
      local tw, th = win:getDimensions()
      app.winQuads = app.winQuads or {
        corner = G.newQuad(0, 0, tw, th, tw, th), h = G.newQuad(tw - 1, 0, 1, th, tw, th),
        v = G.newQuad(0, th - 1, tw, 1, tw, th), fill = G.newQuad(tw - 1, th - 1, 1, 1, tw, th) }
      local q, x0, y0 = app.winQuads, mx - mw / 2, my - mh / 2
      local iw, ih = mw - 2 * tw, mh - 2 * th
      G.setColor(1, 1, 1, 1)
      G.draw(win, q.corner, x0, y0); G.draw(win, q.corner, x0 + mw, y0, 0, -1, 1)
      G.draw(win, q.corner, x0, y0 + mh, 0, 1, -1); G.draw(win, q.corner, x0 + mw, y0 + mh, 0, -1, -1)
      G.draw(win, q.h, x0 + tw, y0, 0, iw, 1); G.draw(win, q.h, x0 + tw, y0 + mh, 0, iw, -1)
      G.draw(win, q.v, x0, y0 + th, 0, 1, ih); G.draw(win, q.v, x0 + mw, y0 + th, 0, -1, ih)
      G.draw(win, q.fill, x0 + tw, y0 + th, 0, iw, ih)
    else
      G.setColor(0.07, 0.85, 0.73, 0.85)
      G.rectangle("fill", mx - mw / 2, my - mh / 2, mw, mh, 8, 8)
    end
    G.setFont(small)
    local k = 17 / math.max(1, small:getHeight())
    local lines = {}
    -- the game's own line breaks as they come (a line too wide is drawn narrower, below);
    -- words without breaks wrap to the window (290 wide); more than three lines shrink
    if text:find("\n") then
      for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    else
      local _, wrapped = small:getWrap(text, 290 / k)
      for _, wl in ipairs(wrapped) do lines[#lines + 1] = wl end
    end
    local n = #lines
    if n > 3 then k = k * 3 / n end
    for i, line in ipairs(lines) do
      local y = my - (n - 1) * 10 * (3 / math.max(3, n)) + (i - 1) * 20 * (3 / math.max(3, n)) - small:getHeight() * k / 2
      local w = small:getWidth(line) * k
      local kk = w > 290 and k * 290 / w or k
      G.setColor(0.03, 0.25, 0.22, 0.7)
      G.print(line, 16, y + 1, 0, kk, k)
      G.setColor(1, 1, 1, 1)
      G.print(line, 15, y, 0, kk, k)
    end
  end

  local function medalCount()
    local n = 0
    for _, c in ipairs(T.courseList and T.courseList() or {}) do
      local r = T.courseRecord(c.id)
      if r and r.medal then n = n + 1 end
    end
    return n
  end

  -- the active Pokemon's icon once a frame (T.party asks the engine for the whole party)
  local iconAt, iconCache = nil, nil
  local function activeIcon()
    if iconCache ~= nil and iconAt == app.clock then return iconCache or nil end
    iconAt, iconCache = app.clock, false
    for _, p in ipairs(T.party and T.party() or {}) do
      if p.active then iconCache = p.icon or false end
    end
    return iconCache or nil
  end

  local function drawIcon(G, icon, cx, cy, w)
    if not (icon and icon.image) then return end
    local q = icon.quads and (icon.quads[0] or icon.quads[1])
    local fw, fh = icon.w or 32, icon.h or 32
    local k = w / fw
    G.setColor(1, 1, 1, 1)
    if q then drawPixel(icon.image, q, cx, cy, 0, k, k, fw / 2, fh / 2)
    else drawPixel(icon.image, cx, cy, 0, k, k, fw / 2, fh / 2) end
  end

  local function fit(G, img, cx, cy, w, h, alpha, flipX)
    if not img then return end
    local iw, ih = img:getDimensions()
    G.setColor(1, 1, 1, (alpha or 255) / 255)
    G.draw(img, cx, cy, 0, (flipX and -w or w) / iw, h / ih, iw / 2, ih / 2)
  end

  local function drawSlot(G, c, sl, sel)
    local x, y = sl[1], sl[2]
    local open = T.canEnter(c)
    local rec = T.courseRecord(c.id)
    local pic = c.bots[1] and c.bots[1].art and art(c.bots[1].art)
    if open and pic then
      fit(G, pic, x, y, 64, 64)
    else
      fit(G, art("training/ss_stage_icon00"), x, y, 64, 64)
    end
    if rec and rec.clears and rec.clears > 0 then fit(G, art("training/tag_cleared"), x, y + 15, 60, 20) end
    if rec and rec.medal then fit(G, art("training/medal"), x + 25, y - 19, 32, 32) end
    if c.stat then fit(G, art("training/label_" .. c.stat), x, y - 22, 64, 20) end
    if sel then
      local cur = art("training/ss_cur")
      local sc = L and L.eval(CUR, app.clock % 24) or 1
      if cur then fit(G, cur, x, y, 90 * sc, 64 * sc) end
    end
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    G.push()
    G.translate(0, -(app.bleed or BLEED))
    G.scale(K, K)
    drawBackground(G, 320, 210, COLS, 150, { 8, 5 })
    if not s then G.pop(); return end
    local meter = art("training/ss_meter_bg")
    if meter and L then L.mirror4(G, meter, 160, 140, 220, 130, { colors = COLS.meter, alpha = 150 }) end
    -- the medal tab: medals won, the Pokemon's icon, Fully / Supremely Trained
    local tab = art("training/ss_pokename_bg")
    if tab and L then L.quad(G, tab, 95, 20, 190, 40, { colors = COLS.tab }) end
    fit(G, art("training/medal"), 27, 16, 24, 24, 180)
    if L then L.text(G, small, ("x %d"):format(medalCount()), 39, 6, 40, 20, { color = { 0.05, 0.2, 0.2, 1 }, shadow = false }) end
    drawIcon(G, activeIcon(), 115, 15, 40)
    if s.rec.supremely then fit(G, art("training/ss_perfect_icon1"), 151, 16, 24, 24, 220)
    elseif s.rec.fully then fit(G, art("training/ss_perfect_icon2"), 151, 16, 24, 24, 220) end
    -- the level band
    local p, count = current()
    local band = art("training/ss_stage_win")
    if band and L then L.quad(G, band, 160, 55, 320, 24, { colors = COLS.band }) end
    if L and p then
      L.text(G, small, T.levelHeading(p.level, p.secret and (p.secret == 2 and 7 or 1) or nil), 8, 45, 290, 20,
        { color = { 1, 1, 1, 1 } })
    end
    -- the courses
    local sel = selected()
    for i, sl in ipairs(SLOTS) do
      local c = p and p.slots[i]
      if c then drawSlot(G, c, sl, sel == c.id) end
    end
    -- the bar: a white rule, the teal band, the page, the return button
    G.setColor(0.96, 0.99, 0.98, 1)
    G.rectangle("fill", 0, 210, 320, 2)
    if L then
      local top, bottom = { 74, 158, 142, 255 }, { 38, 82, 72, 255 }
      L.quad(G, nil, 160, 226, 320, 28, { colors = { top, top, bottom, bottom } })
      L.text(G, small, ("%d/%d"):format(page, math.max(1, count)), 35, 215, 40, 20, { color = { 0.05, 0.08, 0.08, 1 }, shadow = false })
    end
    if count > 1 then
      local arrow = art("training/ss_page_arrow")
      if page > 1 then fit(G, arrow, ARROW_L[1], ARROW_L[2], ARROW_L[3], ARROW_L[4]) end
      if page < count then fit(G, arrow, ARROW_R[1], ARROW_R[2], ARROW_R[3], ARROW_R[4], 255, true) end
    end
    fit(G, art("training/ss_return"), RETURN[1], RETURN[2], RETURN[3], RETURN[4])
    -- the words: what was said, else the picked course's blurb
    local words = s.message
    if not words and sel then
      local b = T.courseBlurb(sel)
      words = b ~= "" and b or nil
    end
    if words then drawWords(G, words, small) end
    -- a screen change: the shutters, or the black before the fade
    local v = T.transView and T.transView("bottom")
    if v and v.shutter and L then L.shutters(G, art, 320, 240, v.shutter, v.f) end
    if v and v.black and v.black > 0 then
      G.setColor(0, 0, 0, v.black)
      G.rectangle("fill", -10, -20, 340, 280)
    end
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  -- ------- the card on the top screen (stageselect_upper, 400x240 fitted to 240x160)

  local UP = {
    bg = { { 84, 200, 255, 255 }, { 84, 200, 255, 255 }, { 0, 111, 209, 255 }, { 0, 111, 209, 255 } },
    glowHigh = { { 168, 226, 255, 255 }, { 168, 226, 255, 255 }, { 168, 226, 255, 30 }, { 168, 226, 255, 30 } },
    ptn = { { 0, 80, 147, 100 }, { 0, 80, 147, 100 }, { 0, 80, 147, 100 }, { 0, 80, 147, 100 } },
    title = { { 219, 200, 197, 255 }, { 255, 255, 255, 255 }, { 219, 200, 197, 255 }, { 255, 255, 255, 255 } },
  }
  -- the stat rows (status_win da..di): width and the stat's colour (the up arrow's tint)
  local ROWS = {
    { "hp", 180, { 45, 255, 45 } }, { "atk", 176, { 255, 210, 32 } }, { "def", 172, { 255, 120, 25 } },
    { "spa", 168, { 26, 228, 255 } }, { "spd", 164, { 65, 134, 255 } }, { "spe", 160, { 255, 38, 244 } },
  }

  local function clock(secs)
    secs = math.max(0, secs or 0)
    local m = math.floor(secs / 60)
    local rest = secs - m * 60
    return ("%d:%04.1f"):format(m, rest)
  end
  app.clockText = clock

  -- the card's type, rasterised at the size it lands on screen: the top screen is drawn at
  -- window resolution (src/hd_top.lua) under a scale, so a font made at its nominal size
  -- would be magnified and blur. Fonts are kept per density (half steps).
  app.cardFonts = {}
  local function cardFont(G2)
    local x0, y0 = G2.transformPoint(0, 0)
    local x1, y1 = G2.transformPoint(1, 0)
    local px = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)   -- screen pixels per layout unit
    -- a 20-unit text pane holds the 9-point font at about 1.8x
    local d = math.max(1, math.min(16, math.floor(px * 1.8 * 2 + 0.5) / 2))
    if not app.cardFonts[d] then
      local ok, f = pcall(G2.newFont, 9, "normal", d)
      if not ok then ok, f = pcall(G2.newFont, 9) end
      app.cardFonts[d] = ok and f or false
    end
    return app.cardFonts[d] or select(2, fonts())
  end
  -- stageselect_upper_bg_anime: the brackets' shadow round the course turns once
  -- counter-clockwise every 200 frames
  local CUR_TURN = 200

  function app.drawCard(G2, s)
    local font = fonts()
    -- the background fills the whole top screen; the card's 400x240 fits its width
    G2.push()
    G2.scale(240 / 400, 160 / 240)
    drawBackground(G2, 400, 240, UP, 100, { 10, 6 })
    G2.pop()
    local c = s.picked and T.course(s.picked)
    if not c or not L then return end
    -- the card's width fits the top screen; its title sits at the top edge
    G2.push()
    G2.scale(0.6, 0.6)
    local small = cardFont(G2)
    -- the dark band and the title bar
    local clear = { 0, 0, 0, 0 }
    local black = { 0, 0, 0, 255 }
    L.quad(G2, nil, 200, 30, 400, 60, { colors = { black, black, clear, clear }, alpha = 180 })
    L.quad(G2, nil, 200, 44, 400, 22, { alpha = 160, colors = { black, black, black, black } })
    L.text(G2, small, T.resultText("possible"), 5, 34, 290, 20, { align = "center" })
    local title = art("training/ss_title_win")
    if title then
      L.quad(G2, title, 100, 15, 200, 30, { colors = UP.title })
      L.quad(G2, title, 300, 15, 200, 30, { colors = { UP.title[2], UP.title[1], UP.title[4], UP.title[3] }, flipX = true })
    end
    L.text(G2, small, ("Lv. %d"):format(c.level or 1), 19, 4, 60, 20, { align = "center" })
    L.text(G2, small, T.courseName(c.id), 79, 4, 290, 20)
    -- what it can raise: the six stats, the course's own with its arrow and gain
    local win = art("training/ss_status_win")
    local up = art("training/ss_up_arrow")
    local gain = c.stat and Rules.courseEv(c, s.rec.pending) or nil
    for i, row in ipairs(ROWS) do
      local y = 40 + i * 30
      local w = row[2]
      if win then L.quad(G2, win, w / 2, y, w, 30, { colors = { black, black, black, black }, alpha = 180 }) end
      local rgb = { row[3][1] / 255, row[3][2] / 255, row[3][3] / 255, 1 }
      L.text(G2, small, T.statWord(row[1]), 18, y - 10, 70, 20, { color = rgb })
      if c.stat == row[1] and gain then
        if up then L.quad(G2, up, 10, y, 10, 20, { colors = { row[3], row[3], row[3], row[3] } }) end
        L.text(G2, small, ("+%d"):format(gain), 103, y - 10, 50, 20, { color = rgb, align = "center" })
      end
    end
    -- the course's picture in its frame, the brackets' shadow round it
    local pic = c.bots[1] and c.bots[1].art and art(c.bots[1].art)
    local frame = art("training/ss_stage_icon01")
    if pic then fit(G2, pic, 348, 66, 64, 64) elseif frame then fit(G2, frame, 348, 66, 64, 64) end
    local cur = art("training/ss_cur")
    if cur then
      G2.push()
      G2.translate(348, 66)
      G2.rotate(-2 * math.pi * (app.clock % CUR_TURN) / CUR_TURN)
      L.quad(G2, cur, 0, 0, 90, 64, { colors = { black, black, black, black }, alpha = 100 })
      G2.pop()
    end
    -- the target time
    local lt, rt = art("training/ss_stage_win_lt"), art("training/ss_stage_win_rt")
    L.window(G2, lt, rt, 295, 130, 210, 62)
    L.text(G2, small, T.resultText("targetRemaining"), 202, 109, 180, 20)
    fit(G2, art("training/medal"), 218, 141, 20, 20, 180)
    L.text(G2, small, clock(Rules.medalTarget(c)), 235, 131, 150, 20)
    -- the best time, once there is one
    local rec = T.courseRecord(c.id)
    if rec and rec.best then
      L.window(G2, lt, rt, 290, 201, 220, 80)
      L.text(G2, small, T.resultText("bestTime"), 197, 174, 180, 20)
      drawIcon(G2, activeIcon(), 210, 212, 40)
      L.text(G2, small, clock(rec.best), 233, 202, 150, 20)
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end
  T.drawCard = app.drawCard

  return app
end
