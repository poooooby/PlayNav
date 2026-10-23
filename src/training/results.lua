-- A regimen's results as the game shows them: result_upper on the top screen (the course's
-- title, "Base stat increase:", the six stat rows sliding in, the trained stat's arrow and +N
-- on its row and over the meter, the meter with the Pokemon's base stats and EVs, the total
-- gauge rising) and result_lower on the touch screen (a/1/1/3; src/lytplayer.lua plays them),
-- where the coach's lines come one after another in the message window, a tap (or A) for the
-- next: "And the results are...", what the stat did, the course's badge and the time left with
-- New best time! and the praise, the bags received, the rack's count, the parting words.
-- From a capture of Hone Sp. Atk with Magnemite.
--
-- R = makeResults(mod, T, Rules, Radar) ; R.begin(s) ; R.update(dt) ; R.next()
-- R.drawTop(G2, s) / R.drawBottom(G) (layout units, the caller scales) -> false without art

return function(mod, T, Rules, Radar)
  local R = {}
  local FPS = 30
  local N = Rules.N
  -- the top screen: rows in at once, the stat's rise a second later
  R.TOP = { STATUS_IN = 0.2, STAT_UP = 1.2 }
  -- "And the results are..." stays this long before the next line on its own
  R.FIRST_S = 2.4
  -- the word window: two lines at least, its foot at 207 (above the band at 147)
  local MSG = { x = 6, w = 308, foot = 207, footBand = 147, line = 17, pad = 13 }

  local STATS = { "hp", "atk", "def", "spa", "spd", "spe" }
  local ROW_LABEL = { hp = "65", atk = "67", def = "69", spa = "6b", spd = "6d", spe = "6f" }
  local ROW_UP = { hp = "6h", atk = "6j", def = "6l", spa = "6n", spd = "6p", spe = "6r" }
  local POINT_UP = { hp = "8c", atk = "82", def = "84", spa = "8a", spd = "88", spe = "86" }
  local UP_CLIP = { hp = "hp_up", atk = "kougeki_up", def = "bougyo_up", spa = "tokukou_up", spd = "tokubou_up",
    spe = "subayasa_up" }

  local function clock(secs)
    secs = math.max(0, secs or 0)
    local m = math.floor(secs / 60)
    return ("%d:%04.1f"):format(m, secs - m * 60)
  end

  local function line(n, vars, keep)
    return T.gameLine and T.gameLine("training_courses", n, vars, keep ~= false) or nil
  end

  -- the lines, in the game's order
  local function pages(s, r)
    local out = {}
    local function add(p) out[#out + 1] = p end
    add({ text = line(166) or "And the results are...", auto = R.FIRST_S })
    if r.clear then
      if r.stat then
        add({ text = T.statLine(r.stat, true) or r.statText or ("%s's %s went up!"):format(s.name, T.statWord(r.stat)) })
      end
      local band = r.newBest and (line(139) or "New best time!") or (r.medal and (line(137) or "You've achieved the target time!"))
        or (line(136) or "Don't give up! Try to reach that target time!")
      -- an Award or a new best time: the game's jingle with it
      add({ show = "time", band = band, text = T.praise(r, true) or r.praise, jingle = (r.newBest or r.medal) and true or nil })
    else
      add({ text = line(127) or T.resultText("failed") })
    end
    if r.bag or r.item then
      add({ show = "bags", jingle = true,
        text = line(165) or "You faced the challenge of a Super-Training Regimen and got a reward in return!" })
      if r.bag then
        if r.bagKept == false then
          add({ show = "bags", text = line(163) or T.resultText("rackFull") })
        else
          local count = T.bagCount and T.bagCount() or nil
          add({ show = "bags", text = (line(167, { N = count or "" }) or ("Training Bags:\n%s"):format(tostring(count or ""))) })
        end
      end
    end
    if r.unlockText then add({ text = r.unlockText }) end
    if r.supremely then add({ text = line(153) or T.resultText("supremelyNow") })
    elseif r.fully then add({ text = line(150) or T.resultText("fullyNow") })
    elseif r.clear and not (s.rec and s.rec.fully) then add({ text = line(149) or "Don't slow down now! Keep on training to make it a Fully Trained Pokemon!" }) end
    return out
  end

  local function open(name)
    local Sc = T.lyt
    if not Sc then return nil end
    if name == "upper" then return Sc.open("st_menu", "result_upper.bclyt", { "st_menu", "st_common", "st_lang" }) end
    return Sc.open("st_menu", "result_lower.bclyt", { "st_menu", "st_common" })
  end

  -- the engine draws the screens (src/training/ui_art.lua's Assets.engine); off, the game's layouts
  local function engineOn()
    local A = T.assets
    return A ~= nil and A.engine ~= nil
  end

  function R.begin(s)
    local r = s and s.result
    R.s, R.r = s, r
    R.t, R.page, R.pageT, R.cues, R.done, R.shown = 0, 1, 0, {}, false, nil
    R.list = r and pages(s, r) or {}
    R.engine = engineOn()
    R.gauge = math.min(1, Rules.evTotal(s and s.evs or {}) / N.LIMITS.EV_TOTAL) * 128
    R.gaugeNow = 0
    if R.engine then
      R.top, R.bottom = nil, nil
      local c = r and T.course and T.course(r.courseId)
      local A = T.assets
      R.badge = c and c.bots[1] and c.bots[1].art and A and A.image and A.image(c.bots[1].art) or nil
      R.icon = s and s.icon
      R.enterPage()
      return
    end
    R.top, R.bottom = open("upper"), open("lower")
    local P = R.top
    if P and r then
      P:play("bg_anime", { loop = true })
      local lv = s.course and s.course.level
      P:setText("5n", lv and (line(9 + lv) or ("Lv. " .. lv)) or (line(9) or "Lv. ?"))
      P:setText("5l", r.courseName or "", { align = "left" })
      P:setText("63", r.clear and (line(60) or "Base stat increase:") or (line(59) or "Possible base stat increase:"))
      for _, k in ipairs(STATS) do
        P:setText(ROW_LABEL[k], T.statWord and T.statWord(k) or k, { align = "left" })
        P:set(ROW_UP[k], "visible", false)
      end
      -- the rows wait off to the left for status_in
      P:play("status_in", { speed = 0 })
      -- the total gauge and its arrow: one frame (0..128) for the EV total, both clips held at
      -- it (meter2_gage scales the bar 8g, arrow_up lifts the arrow 8i 128 units); the bar's
      -- length is the code's to set (the layout leaves it 0 tall). They rise from the foot to
      -- the Pokemon's new total and stop there.
      R.gauge = math.min(1, Rules.evTotal(s.evs or {}) / N.LIMITS.EV_TOTAL) * 128
      P:set("8g", "h", 128)
      P:play("meter2_gage", { speed = 0 })
      P:play("arrow_up", { speed = 0 })
      P:set("8j", "visible", false)
    end
    local B = R.bottom
    if B then
      B:play("bg_anime", { loop = true })
      B:play("no_mask")
      -- both groups wait out of sight for their cue
      B:play("result_01_out", { from = 6 })
      B:play("result_02_out", { from = 6 })
      B:setText("3l", "")
      if r then
        B:setText("4x", T.resultText and T.resultText("timeRemaining") or "Time Remaining:")
        B:setText("4z", clock(r.remaining))
        B:setText("45", T.resultText and T.resultText("bagsReceived") or "Training bags received:")
        if r.bag then
          B:setText("49", T.bagName and T.bagName(r.bag) or r.bag, { align = "left" })
          local A = T.assets
          local img = A and A.image and A.image(("training/sand_bag_%02d"):format(Rules.BAG_ART[r.bag] or 0))
          if img then B:setImage("4b", img) end
        else
          B:set("3z", "visible", false)
        end
        if r.item then
          B:setText("4d", r.item.name or "", { align = "left" })
          local icon = T.items and T.items.icon and r.item.index and T.items.icon(r.item.index)
          if icon then B:setImage("4f", icon) else B:set("4f", "visible", false) end
        else
          B:set("41", "visible", false)
        end
        -- the course's badge (its first bot's art) and the trainee's party icon, drawn over
        -- the panes the game renders them into
        local c = T.course and T.course(r.courseId)
        local A = T.assets
        R.badge = c and c.bots[1] and c.bots[1].art and A and A.image and A.image(c.bots[1].art) or nil
        R.icon = s.icon
        B:set("3p", "visible", false)
        B:set("4l", "visible", false)
        B:set("51", "visible", false)
      end
    end
    R.enterPage()
  end

  -- what a page shows on the touch screen
  function R.enterPage()
    local p = R.list[R.page]
    R.pageT = 0
    -- an Award / new best time, a reward received: the game's jingle (data/training_sounds.lua)
    if p and p.jingle and T.playSe then T.playSe("result_jingle")
    elseif p and mod.haptics then mod.haptics.pulse("light") end   -- each page as it comes up
    if p and R.engine then
      if p.show ~= R.shown then R.shown, R.shownAt = p.show, R.t end
      return
    end
    local B = R.bottom
    if not (p and B) then return end
    if p.show ~= R.shown then
      if R.shown == "time" then B:play("result_01_out") end
      if R.shown == "bags" then B:play("result_02_out") end
      if p.show == "time" then B:play("result_01_in") end
      if p.show == "bags" then B:play("result_02_in") end
      R.shown = p.show
    end
    B:setText("3l", p.band or "")
    B:set("3j", "visible", p.band ~= nil)
  end

  function R.next()
    if not R.list or R.done then return false end
    local p = R.list[R.page]
    if p and R.pageT < 0.25 then return false end
    if R.page >= #R.list then
      R.done = true
      if T.goTo then T.goTo("courses") elseif T.leaveResult then T.leaveResult() end
      return true
    end
    -- a tap on: the game's continue sound
    if T.playSe then T.playSe("result_next") end
    R.page = R.page + 1
    R.enterPage()
    return true
  end

  function R.update(dt)
    if not R.list then return end
    dt = dt or 0
    R.t, R.pageT = R.t + dt, R.pageT + dt
    if R.t >= R.TOP.STATUS_IN then R.gaugeNow = math.min(R.gauge or 0, (R.gaugeNow or 0) + dt * FPS * 1.5) end
    local P, B = R.top, R.bottom
    -- the trained stat's rise: the drawn screens read the cue; the game's layout plays its clips
    if R.engine and not R.cues.up and R.t >= R.TOP.STAT_UP and R.r and R.r.stat and (R.r.ev or 0) > 0 then
      R.cues.up = true
    end
    if P then
      P:advance(dt * FPS)
      local r = R.r
      local g = P:entry("meter2_gage")
      if g and R.t >= R.TOP.STATUS_IN then
        g.frame = math.min(R.gauge or 0, g.frame + dt * FPS * 1.5)
        local a = P:entry("arrow_up")
        if a then a.frame = g.frame end
      end
      if not R.cues.status and R.t >= R.TOP.STATUS_IN then
        R.cues.status = true
        local e = P:entry("status_in")
        if e then e.speed = 1 end
      end
      if not R.cues.up and R.t >= R.TOP.STAT_UP and r and r.stat and (r.ev or 0) > 0 then
        R.cues.up = true
        local k = r.stat
        P:set(ROW_UP[k], "visible", true)
        P:setText(ROW_UP[k], "+" .. tostring(r.ev), { align = "left" })
        P:setText(POINT_UP[k], "+" .. tostring(r.ev))
        P:play(UP_CLIP[k])
        P:set("8j", "visible", true)
        P:play("arrow_scale", { loop = true })
      end
    end
    if B then B:advance(dt * FPS) end
    local p = R.list[R.page]
    if p and p.auto and not R.done and R.pageT >= p.auto then R.next() end
  end

  -- ------- drawing

  local function drawMeter(G, P, s)
    -- the meter slides in with status_in; its shape waits for it
    if (R.t or 0) < R.TOP.STATUS_IN + 0.1 then return end
    local x, y, w, h = P:box("7o")
    if not (x and Rules.meterAxes and Radar) then return end
    local cx, cy = x + w / 2, y + h / 2
    local ri, ro = Rules.meterAxes(s.base or {}, s.evs or {}, Radar.ORDER)
    local k = w / 128   -- the canvas pane is 128 across; larger when the meter is scaled up
    local inner, outer = {}, {}
    for i = 1, 6 do
      local a = -math.pi / 2 + (i - 1) * math.pi / 3
      inner[#inner + 1] = cx + math.cos(a) * ri[i] * k
      inner[#inner + 1] = cy + math.sin(a) * ri[i] * k
      outer[#outer + 1] = cx + math.cos(a) * ro[i] * k
      outer[#outer + 1] = cy + math.sin(a) * ro[i] * k
    end
    G.setColor(0.8, 1, 0.25, 1)
    G.polygon("fill", outer)
    G.setColor(0.05, 0.62, 0.45, 1)
    G.polygon("fill", inner)
    G.setLineWidth(2 * k)
    G.setColor(0.85, 1, 0.3, 1)
    G.polygon("line", outer)
    G.setLineWidth(1)
  end

  -- A larger area (Wl x Hl layout units, the layout centred across it from its top): the
  -- full-width backdrops widen; the title bar and the band under it grow (`t`, as far as the
  -- width allows); the stat rows (5r .. 5z, with their +N) and the meter (7n: the radar, its
  -- labels and +N, the bar 8g, with the bar's arrow 8i) grow by one scale (`s`), the rows from
  -- the left edge, the meter on the right, as large as the room under the band allows without
  -- the two meeting.
  -- Natural boxes (layout units, y down): title 0..30, band to 60; rows x 0..180, y 55..235;
  -- meter x 224..390, y 100..235 (centre 307, 167.5).
  R.FIT = { ROWS = { "5r", "5t", "5v", "5x", "61", "5z" }, ROWS_TOP = 55, ROWS_W = 180, ROWS_H = 180,
    METER = { cx = 307, cy = 167.5, hw = 83, hh = 67.5 }, BAND = 60, GAP = 12, EDGE = 8, MAX = 1.9 }
  function R.fitAdjust(P, Wl, Hl)
    local F, A = R.FIT, {}
    local kx = Wl / P.L.W
    for name, pane in pairs(P.L.byName) do
      if pane.kind == "pic" and math.abs(pane.w or 0) >= P.L.W - 0.5 then A[name] = { qx = kx } end
    end
    if Wl < P.L.W + 1 and Hl < P.L.H + 1 then return A end
    local Lx, Rx = (P.L.W - Wl) / 2, (P.L.W + Wl) / 2
    local M = F.METER
    -- the title bar (5j carries 6t and the texts) about the top middle; the band (5p, with 6v
    -- and its text) under it, its picture still across the area
    local t = math.max(1, math.min(F.MAX, Wl / P.L.W, Hl / P.L.H))
    local function about(name, ax, ay, k, extra)
      local pane = P.L.byName[name]
      if not pane then return end
      local parent = pane.parent
      local px, py = 0, 0
      if parent and parent ~= P.L.root then px, py = parent.t[1], parent.t[2] end
      local ox, oy = P.L.W / 2 + px + pane.t[1], P.L.H / 2 - py - pane.t[2]
      local nx, ny = ax + (ox - ax) * k, ay + (oy - ay) * k
      local a = extra or {}
      a.dx, a.dy, a.sx, a.sy = nx - ox, -(ny - oy), k, k
      A[name] = a
    end
    about("5j", P.L.W / 2, 0, t)
    about("5p", P.L.W / 2, 0, t, { qx = kx / t })
    A["6v"] = { qx = kx / t }
    local band = F.BAND * t
    -- the rows and the meter: one scale
    local room = Hl - band - F.EDGE
    local s = math.min(F.MAX, (Wl - 2 * F.EDGE - F.GAP) / (F.ROWS_W + 2 * M.hw),
      (room + 5) / F.ROWS_H, room / (2 * M.hh))
    s = math.max(1, s)
    -- the rows: each grows from its left edge (x -> Lx + x * s, the slide in scaled with it,
    -- so they wait fully off the area), from just under the band; their parent 5i sits at the
    -- layout's middle
    local top = band - (F.BAND - F.ROWS_TOP)
    for _, name in ipairs(F.ROWS) do
      local pane = P.L.byName[name]
      if pane then
        local y = P.L.H / 2 - pane.t[2]
        local ny = top + (y - F.ROWS_TOP) * s
        A[name] = { mx = s, dx = Lx + P.L.W / 2 * (s - 1), dy = -(ny - y), sx = s, sy = s }
      end
    end
    -- the meter: right-aligned, centred down the room under the band
    local Xc = Rx - F.EDGE - M.hw * s
    local Yc = band + F.EDGE / 2 + room / 2
    local function place(name)
      local pane = P.L.byName[name]
      if not pane then return end
      local ox, oy = P.L.W / 2 + pane.t[1], P.L.H / 2 - pane.t[2]
      local nx, ny = Xc + (ox - M.cx) * s, Yc + (oy - M.cy) * s
      A[name] = { dx = nx - ox, dy = -(ny - oy), sx = s, sy = s }
    end
    place("7n"); place("8i")
    R.fitScales = { title = t, rows = s, meter = s }
    return A
  end

  -- ------- the screens drawn by the engine

  local efonts = {}
  local function efont(px)
    local f = efonts[px]
    if not f then
      local ok, made = pcall(love.graphics.newFont, px)
      f = ok and made or love.graphics.getFont()
      efonts[px] = f
    end
    return f
  end
  local function col(G, rgb, a) G.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, a or 1) end
  local function say(G, text, x, y, hgt, align, fill, ink, a)
    local f = efont(40)
    local k = hgt / f:getHeight()
    local w = f:getWidth(text) * k
    local x0 = (align == "center" and x - w / 2) or (align == "right" and x - w) or x
    G.setFont(f)
    if ink then
      col(G, ink, a)
      local o = math.max(0.4, hgt * 0.06)
      for dx = -1, 1 do
        for dy = -1, 1 do
          if dx ~= 0 or dy ~= 0 then G.print(text, x0 + dx * o, y + dy * o, 0, k, k) end
        end
      end
    end
    col(G, fill, a)
    G.print(text, x0, y, 0, k, k)
    return w
  end
  local WHITE, INK = { 255, 255, 255 }, { 0, 30, 40 }
  local TEAL, TEAL_HI, NAVY = { 30, 190, 160 }, { 120, 245, 225 }, { 16, 34, 64 }
  local STAT_RGB = { hp = { 150, 230, 60 }, atk = { 250, 210, 40 }, def = { 250, 150, 40 },
    spa = { 120, 196, 255 }, spd = { 96, 156, 246 }, spe = { 236, 120, 240 } }

  -- the blue room behind both screens: the gradient, the grid glowing at the foot, the + drifting
  local function backdrop(G, x, y, w, h, t)
    local m = R.bgMesh
    if not m then
      m = love.graphics.newMesh({ { 0, 0, 0, 0, 0, 0.43, 0.82, 1 }, { 1, 0, 0, 0, 0, 0.43, 0.82, 1 },
        { 1, 1, 0, 0, 0.33, 0.78, 1, 1 }, { 0, 1, 0, 0, 0.33, 0.78, 1, 1 } }, "fan", "static")
      R.bgMesh = m
    end
    G.setColor(1, 1, 1, 1)
    G.draw(m, x, y, 0, w, h)
    local A = T.assets
    local grid = A and A.image and A.image("training/home_bg01")
    if grid then
      local gw, gh = grid:getDimensions()
      G.setColor(0.66, 0.89, 1, 0.45)
      G.draw(grid, x, y + h - h * 0.45, 0, w / gw, h * 0.45 / gh)
    end
    local tile = A and A.image and A.image("training/home_bg_ptn")
    if tile then
      tile:setWrap("repeat", "repeat")
      local tw, th = tile:getDimensions()
      -- as the home screen and the picker: 40-unit tiles drifting 2 left and 1 up every 200
      -- frames (30 a second)
      local k = 40 / tw
      R.ptnQuad = R.ptnQuad or love.graphics.newQuad(0, 0, 1, 1, tw, th)
      local ox, oy = (t * 30 * 2 / 200 * tw) % tw, (t * 30 / 200 * th) % th
      R.ptnQuad:setViewport(ox, oy, w / k, h / k, tw, th)
      G.setColor(0, 80 / 255, 147 / 255, 0.55)
      G.draw(tile, R.ptnQuad, x, y, 0, k, k)
    end
  end

  -- the top screen in the layout's 400x240 units (drawn at 0.6, top-anchored)
  local function topEngine(G2, s)
    local r = R.r
    local e = T.topExtent or { x = 0, y = 0, w = 240, h = 160 }
    backdrop(G2, e.x, e.y, e.w, e.h, R.t or 0)
    if not r then return end
    G2.push()
    G2.translate(e.x + e.w / 2 - 120, e.y)
    G2.scale(0.6, 0.6)
    -- the title bar: the level, the course's name
    col(G2, INK); G2.polygon("fill", -40, 0, 440, 0, 440, 24, 380, 32, -40, 32)
    col(G2, TEAL); G2.polygon("fill", -40, 0, 440, 0, 440, 21, 378, 29, -40, 29)
    local lv = s.course and s.course.level
    say(G2, lv and (line(9 + lv) or ("Lv. " .. lv)) or "", 12, 6, 15, "left", WHITE)
    say(G2, r.courseName or "", 64, 6, 15, "left", WHITE)
    -- the band under it
    col(G2, NAVY, 0.85); G2.rectangle("fill", -40, 32, 480, 22)
    say(G2, r.clear and (line(60) or "Base stat increase:") or (line(59) or "Possible base stat increase:"),
      200, 35, 14, "center", WHITE)
    -- the six rows sliding in from the left, one after another
    for i, k in ipairs(STATS) do
      local inK = math.max(0, math.min(1, ((R.t or 0) - R.TOP.STATUS_IN - (i - 1) * 0.05) / 0.25))
      local slide = (1 - inK * inK * (3 - 2 * inK)) * -200
      local y = 58 + (i - 1) * 30
      G2.push()
      G2.translate(slide, 0)
      col(G2, NAVY, 0.92); G2.polygon("fill", 0, y, 172, y, 182, y + 11, 172, y + 22, 0, y + 22)
      col(G2, TEAL, 0.5); G2.setLineWidth(1); G2.line(0, y + 22, 172, y + 22, 182, y + 11)
      local up = R.cues.up and r.stat == k
      if up then
        col(G2, { 150, 240, 80 })
        G2.polygon("fill", 8, y + 5, 13, y + 11, 10, y + 11, 10, y + 18, 6, y + 18, 6, y + 11, 3, y + 11)
      end
      say(G2, T.statWord and T.statWord(k) or k, 16, y + 3, 15, "left", STAT_RGB[k])
      if up then say(G2, "+" .. tostring(r.ev), 128, y + 3, 15, "left", { 200, 255, 120 }) end
      G2.pop()
    end
    -- the meter on the right: the hexagon, the stats in it, the labels, the total's gauge
    if (R.t or 0) >= R.TOP.STATUS_IN + 0.1 then
      local cx, cy, rr = 300, 160, 50.5
      local A = T.assets
      local meter = A and A.image and A.image("training/home_meter")
      if meter then
        local mw, mh = meter:getDimensions()
        G2.setColor(1, 1, 1, 0.9)
        -- the hexagon's centre in the texture is (63.5, 85.5)
        G2.draw(meter, cx - 63.5, cy - 85.5, 0, 150 / mw, 150 / mh)
      end
      if Rules.meterAxes and Radar then
        local ri, ro = Rules.meterAxes(s.base or {}, s.evs or {}, Radar.ORDER)
        local inner, outer = {}, {}
        for i = 1, 6 do
          local a = -math.pi / 2 + (i - 1) * math.pi / 3
          inner[#inner + 1] = cx + math.cos(a) * ri[i]; inner[#inner + 1] = cy + math.sin(a) * ri[i]
          outer[#outer + 1] = cx + math.cos(a) * ro[i]; outer[#outer + 1] = cy + math.sin(a) * ro[i]
        end
        G2.setColor(0.8, 1, 0.25, 1); G2.polygon("fill", outer)
        G2.setColor(0.05, 0.62, 0.45, 1); G2.polygon("fill", inner)
        G2.setLineWidth(2); G2.setColor(0.85, 1, 0.3, 1); G2.polygon("line", outer)
      end
      local LABEL_AT = { hp = { 0, -62 }, atk = { 46, -38 }, def = { 46, 38 }, spe = { 0, 62 }, spd = { -46, 38 }, spa = { -46, -38 } }
      for k, at in pairs(LABEL_AT) do
        local img = A and A.image and A.image("training/label_" .. k)
        if img then
          local iw, ih = img:getDimensions()
          G2.setColor(1, 1, 1, 1)
          G2.draw(img, cx + at[1], cy + at[2], 0, 52 / iw, 16 / ih, iw / 2, ih / 2)
        end
      end
      if R.cues.up and r.stat and LABEL_AT[r.stat] then
        local at = LABEL_AT[r.stat]
        say(G2, "+" .. tostring(r.ev), cx + at[1], cy + at[2] - 18, 13, "center", { 255, 170, 60 }, { 40, 10, 0 })
      end
      -- the total: the bar up the track at the right, its arrow at the top
      local gx, foot = cx + 79.5, cy + 47.5
      local hgt = (R.gaugeNow or 0)
      if hgt > 0 then
        G2.setColor(186 / 255, 1, 122 / 255, 1)
        G2.rectangle("fill", gx - 2, foot - hgt, 4, hgt)
      end
      if R.cues.up then
        local p = 1 + 0.15 * math.sin((R.t or 0) * 8)
        G2.setColor(222 / 255, 1, 151 / 255, 1)
        local ay = foot - hgt - 6
        G2.polygon("fill", gx, ay - 6 * p, gx - 5 * p, ay, gx + 5 * p, ay)
      end
    end
    G2.pop()
  end

  -- the touch screen in its 320 x lh layout units
  local function bottomEngine(G, lh)
    local D = math.max(0, (lh or 240) - 240)
    backdrop(G, -10, -20, 340, lh + 40, R.t or 0)
    local r = R.r
    local p = R.list and R.list[R.page]
    if not r then return D end
    local inK = R.shownAt and math.min(1, ((R.t or 0) - R.shownAt) / 0.2) or 1
    local slide = (1 - inK) * 40
    if R.shown == "time" then
      -- the course's badge, the time remaining, the trainee
      local y = 18 + D / 2 - slide
      col(G, NAVY, 0.88); G.rectangle("fill", 40, y, 240, 70, 8, 8)
      col(G, TEAL, 0.9); G.setLineWidth(2); G.rectangle("line", 40, y, 240, 70, 8, 8)
      if R.badge then
        local iw, ih = R.badge:getDimensions()
        G.setColor(1, 1, 1, 1)
        G.draw(R.badge, 76, y + 35, 0, 56 / iw, 56 / ih, iw / 2, ih / 2)
      end
      say(G, T.resultText and T.resultText("timeRemaining") or "Time Remaining:", 116, y + 12, 15, "left", TEAL_HI)
      say(G, clock(r.remaining), 116, y + 34, 22, "left", WHITE, INK)
      local icon = R.icon
      if icon and icon.image then
        local q = icon.quads and (icon.quads[0] or icon.quads[1])
        local fw, fh = icon.w or 32, icon.h or 32
        local k = 40 / fw
        G.setColor(1, 1, 1, 1)
        local HD = mod.hd
        local draw = HD and HD.drawPixel or G.draw
        if q then draw(icon.image, q, 252, y + 40, 0, k, k, fw / 2, fh / 2)
        else draw(icon.image, 252, y + 40, 0, k, k, fw / 2, fh / 2) end
      end
    elseif R.shown == "bags" then
      local y = 18 + D / 2 - slide
      col(G, NAVY, 0.88); G.rectangle("fill", 40, y, 240, 80, 8, 8)
      col(G, TEAL, 0.9); G.setLineWidth(2); G.rectangle("line", 40, y, 240, 80, 8, 8)
      say(G, T.resultText and T.resultText("bagsReceived") or "Training bags received:", 56, y + 8, 14, "left", TEAL_HI)
      local A = T.assets
      if r.bag then
        local img = A and A.image and A.image(("training/sand_bag_%02d"):format(Rules.BAG_ART[r.bag] or 0))
        if img then
          local iw, ih = img:getDimensions()
          G.setColor(1, 1, 1, 1)
          G.draw(img, 70, y + 50, 0, 18 / iw, 45 / ih, iw / 2, ih / 2)
        end
        say(G, T.bagName and T.bagName(r.bag) or r.bag, 90, y + 32, 15, "left", WHITE)
      end
      if r.item then
        local icon = T.items and T.items.icon and r.item.index and T.items.icon(r.item.index)
        if icon then
          G.setColor(1, 1, 1, 1)
          local iw = icon:getDimensions()
          G.draw(icon, 200, y + 44, 0, 24 / iw, 24 / iw, iw / 2, iw / 2)
        end
        say(G, r.item.name or "", 216, y + 36, 13, "left", WHITE)
      end
    end
    -- the band: New best time! and the like, across the foot
    if p and p.band then
      local y = 152 + D
      col(G, TEAL, 0.92); G.rectangle("fill", -10, y, 340, 26)
      col(G, INK, 0.5); G.rectangle("fill", -10, y + 24, 340, 2)
      say(G, p.band, 160, y + 5, 15, "center", WHITE, INK)
    end
    return D
  end

  -- 400x240 into the top screen's 240x160: the card's way (0.6, top-anchored), the backdrop
  -- reaching the foot
  function R.drawTop(G2, s)
    if R.engine and R.s == s then
      topEngine(G2, s)
      return true
    end
    local P = R.top
    if not P or R.s ~= s then return false end
    -- the area: the frame, or the whole playfield when the top screen fills it (T.topExtent);
    -- the layout keeps its size, centred across the area from its top
    local e = T.topExtent
    G2.push()
    if e then G2.translate(e.x + e.w / 2 - 120, e.y) end
    G2.scale(0.6, 0.6)
    -- the layout as the game has it, top-aligned at 0.6; only the backdrops fill down to the
    -- area's bottom (spreading the panes would pull the gauge's bar off its track) and, when
    -- it is wider, across it
    P.stretchY = ((e and e.h or 160) / 0.6) / 240
    P.stretchMode = "backdrop"
    local fitKey = e and ("%.2f %.2f"):format(e.w, e.h) or "frame"
    if P._fitKey ~= fitKey then
      P._fitKey = fitKey
      P.adjust = e and R.fitAdjust(P, e.w / 0.6, e.h / 0.6) or nil
    end
    -- the meter's canvas is drawn by the game: hide the pane, draw the stats over it after
    P:set("7o", "visible", false)
    P:draw(G2)
    drawMeter(G2, P, s)
    G2.pop()
    return true
  end

  local function wrapLines(font, text, width)
    local out = {}
    for para in (text .. "\n"):gmatch("(.-)\n") do
      local _, wrapped = font:getWrap(para, width)
      if #wrapped == 0 then out[#out + 1] = "" end
      for _, l in ipairs(wrapped) do out[#out + 1] = l end
    end
    return out
  end

  local winQuads
  local function drawWindow(G, x0, y0, w, h)
    local A = T.assets
    local win = A and A.image and A.image("training/win_bl")
    if not win then
      G.setColor(0.07, 0.85, 0.73, 0.9)
      G.rectangle("fill", x0, y0, w, h, 8, 8)
      return
    end
    local tw, th = win:getDimensions()
    winQuads = winQuads or { corner = G.newQuad(0, 0, tw, th, tw, th), h = G.newQuad(tw - 1, 0, 1, th, tw, th),
      v = G.newQuad(0, th - 1, tw, 1, tw, th), fill = G.newQuad(tw - 1, th - 1, 1, 1, tw, th) }
    local q = winQuads
    local iw, ih = w - 2 * tw, h - 2 * th
    G.setColor(1, 1, 1, 1)
    G.draw(win, q.corner, x0, y0); G.draw(win, q.corner, x0 + w, y0, 0, -1, 1)
    G.draw(win, q.corner, x0, y0 + h, 0, 1, -1); G.draw(win, q.corner, x0 + w, y0 + h, 0, -1, -1)
    G.draw(win, q.h, x0 + tw, y0, 0, iw, 1); G.draw(win, q.h, x0 + tw, y0 + h, 0, iw, -1)
    G.draw(win, q.v, x0, y0 + th, 0, 1, ih); G.draw(win, q.v, x0 + w, y0 + th, 0, -1, ih)
    G.draw(win, q.fill, x0 + tw, y0 + th, 0, iw, ih)
  end

  R.fonts = {}
  local function msgFont(G)
    local x0, y0 = G.transformPoint(0, 0)
    local x1, y1 = G.transformPoint(0, 1)
    local k = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    local size = math.max(6, math.floor(16 * 0.64 * k + 0.5))
    if R.fonts[size] == nil then
      local ok, f = pcall(G.newFont, size)
      R.fonts[size] = ok and f or false
    end
    return R.fonts[size] or nil, k
  end

  -- The lower screen on a taller shape (as core_app): lh layout units, D = lh - 240 more.
  -- The background (3b gradient, 3h + pattern, which repeats rather than stretches) reaches
  -- the new bottom; the low glow (3d) and the stage band (3j: course, time, medal) follow
  -- the bottom; the result windows (3w) centre D/2 lower; the word window's feet move with
  -- them. On the 3DS shape D = 0: the game's layout.
  local shapeD = nil
  local function fitBottom(B, lh)
    local D = math.max(0, (lh or 240) - 240)
    if shapeD == D and B.shapeD == D then return D end
    shapeD, B.shapeD = D, D
    if D <= 0 then B.adjust = nil; return 0 end
    local grow = (210 + D) / 210
    B.adjust = {
      ["3b"] = { qy = grow, dy = -D / 2 },
      ["3h"] = { qy = grow, tileY = grow, dy = -D / 2 },
      ["3d"] = { dy = -D / 2 },          -- with 3b's -D/2: at the bottom
      ["3f"] = { dy = D / 2 },           -- with 3b's -D/2: where it was
      ["3j"] = { dy = -D },
      ["3w"] = { dy = -D / 2 },
    }
    return D
  end

  function R.drawBottom(G, lh)
    local B = R.bottom
    if not (B or R.engine) then return false end
    local D
    if R.engine then
      D = bottomEngine(G, lh)
    else
      D = fitBottom(B, lh)
      B:draw(G)
    end
    -- the course's badge in its frame (the game renders it into stage_icon01's place)
    if B and R.badge and R.shown == "time" then
      local x, y, w, h = B:box("3n")
      if x then
        local iw, ih = R.badge:getDimensions()
        G.setColor(1, 1, 1, 1)
        G.draw(R.badge, x + w / 2, y + h / 2, 0, w * 0.86 / iw, h * 0.86 / ih, iw / 2, ih / 2)
      end
    end
    -- the trainee's party icon in the time window
    local icon = R.icon
    if B and icon and icon.image and R.shown == "time" then
      local x, y, w, h = B:box("51")
      if x then
        local q = icon.quads and (icon.quads[0] or icon.quads[1])
        local fw, fh = icon.w or 32, icon.h or 32
        local k = w / fw
        G.setColor(1, 1, 1, 1)
        local HD = mod.hd
        local draw = HD and HD.drawPixel or G.draw
        if q then draw(icon.image, q, x + w / 2, y + h / 2, 0, k, k, fw / 2, fh / 2)
        else draw(icon.image, x + w / 2, y + h / 2, 0, k, k, fw / 2, fh / 2) end
      end
    end
    local p = R.list and R.list[R.page]
    if p and p.text and p.text ~= "" then
      local font, k = msgFont(G)
      if font then
        local inv = 1 / k
        local lines = wrapLines(font, p.text, (MSG.w - 2 * MSG.pad) * k)
        local n = math.max(2, #lines)
        local h = n * MSG.line + 18
        local foot = (p.band and MSG.footBand or MSG.foot) + D
        local y0 = foot - h
        drawWindow(G, MSG.x, y0, MSG.w, h)
        G.setFont(font)
        for i, l in ipairs(lines) do
          local ty = y0 + 9 + (i - 1) * MSG.line
          G.setColor(0, 0.25, 0.22, 0.6)
          G.print(l, MSG.x + MSG.pad + 0.8, ty + 0.8, 0, inv, inv)
          G.setColor(1, 1, 1, 1)
          G.print(l, MSG.x + MSG.pad, ty, 0, inv, inv)
        end
        -- the red marker: tap for the next line
        if not p.auto and R.pageT > 0.3 and math.floor(R.pageT * 2.5) % 2 == 0 then
          local mx, my = MSG.x + MSG.w - 12, foot - 9
          G.setColor(0.9, 0.05, 0.1, 1)
          G.polygon("fill", mx - 5, my - 4, mx + 5, my - 4, mx, my + 3)
        end
      end
    end
    G.setColor(1, 1, 1, 1)
    return true
  end

  return R
end
