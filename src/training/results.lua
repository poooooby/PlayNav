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
  -- the trained stat's label, +N and gauge arrow pulse on this beat (seconds)
  R.BEAT_S = 0.4
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

  -- the grid over the room's top, seen from below like a ceiling: lines run down toward the
  -- middle, rows spread apart toward the top, everything fading out downward. One mesh of
  -- thin quads (w x hh units, lines lw wide), made once per size
  local function gridMesh(w, hh, lw)
    local v = {}
    local A0 = 0.7
    -- each line twice: a wide faint glow, then its core
    local function one(x0, y0, x1, y1, a0, a1, width)
      local dx, dy = x1 - x0, y1 - y0
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 1e-6 then return end
      local nx, ny = -dy / d * width / 2, dx / d * width / 2
      local p1 = { x0 + nx, y0 + ny, 0, 0, 1, 1, 1, a0 }
      local p2 = { x0 - nx, y0 - ny, 0, 0, 1, 1, 1, a0 }
      local p3 = { x1 - nx, y1 - ny, 0, 0, 1, 1, 1, a1 }
      local p4 = { x1 + nx, y1 + ny, 0, 0, 1, 1, 1, a1 }
      v[#v + 1] = p1; v[#v + 1] = p2; v[#v + 1] = p3
      v[#v + 1] = p1; v[#v + 1] = p3; v[#v + 1] = p4
    end
    local function quad(x0, y0, x1, y1, a0, a1)
      one(x0, y0, x1, y1, a0 * 0.22, a1 * 0.22, lw * 3.5)
      one(x0, y0, x1, y1, a0, a1, lw)
    end
    local cx, step = w / 2, w / 11
    -- the long lines, in pieces so the fade follows them down
    for i = -12, 12 do
      local xt, xb = cx + i * step, cx + i * step * 0.55
      for j = 0, 5 do
        local t0, t1 = j / 6, (j + 1) / 6
        quad(xt + (xb - xt) * t0, hh * t0, xt + (xb - xt) * t1, hh * t1, A0 * (1 - t0), A0 * (1 - t1))
      end
    end
    -- the rows: far apart at the top, closer together further down
    local yy, gap = 2, hh * 0.2
    while yy < hh do
      local a = A0 * (1 - yy / hh)
      quad(-1, yy, w + 1, yy, a, a)
      yy = yy + gap
      gap = math.max(hh * 0.05, gap * 0.78)
    end
    if #v == 0 then return nil end
    return love.graphics.newMesh(v, "triangles", "static")
  end

  -- the blue room behind both screens: the gradient, the grid hung from the top (shallower on
  -- the touch screen, gridTop), the + drifting
  local function backdrop(G, x, y, w, h, t, gridTop)
    local m = R.bgMesh
    if not m then
      m = love.graphics.newMesh({ { 0, 0, 0, 0, 0, 0.43, 0.82, 1 }, { 1, 0, 0, 0, 0, 0.43, 0.82, 1 },
        { 1, 1, 0, 0, 0.33, 0.78, 1, 1 }, { 0, 1, 0, 0, 0.33, 0.78, 1, 1 } }, "fan", "static")
      R.bgMesh = m
    end
    G.setColor(1, 1, 1, 1)
    G.draw(m, x, y, 0, w, h)
    local A = T.assets
    -- the grid hangs from the top like a ceiling (its lines wider apart toward the top) and
    -- fades out downward; stretched further down the top screen than the touch screen
    local hh = h * (gridTop and 0.62 or 0.88)
    R.gridCache = R.gridCache or {}
    local slot = gridTop and 2 or 1
    local c = R.gridCache[slot]
    if not c or c.w ~= w or c.h ~= hh then
      c = { w = w, h = hh, mesh = gridMesh(w, hh, gridTop and 1.2 or 0.75) }
      R.gridCache[slot] = c
    end
    local m = c.mesh
    if m then
      G.setColor(1, 1, 1, 1)
      G.draw(m, x, y)
    end
    local tile = A and A.image and A.image("training/home_bg_ptn")
    if tile then
      tile:setWrap("repeat", "repeat")
      local tw, th = tile:getDimensions()
      -- as the home screen and the picker: 40-unit tiles drifting 2 left and 1 up every 200
      -- frames (30 a second); the top screen's are 24 of its units, as the game's
      local k = (gridTop and 40 or 24) / tw
      R.ptnQuad = R.ptnQuad or love.graphics.newQuad(0, 0, 1, 1, tw, th)
      local ox, oy = (t * 30 * 2 / 200 * tw) % tw, (t * 30 / 200 * th) % th
      R.ptnQuad:setViewport(ox, oy, w / k, h / k, tw, th)
      G.setColor(0, 80 / 255, 147 / 255, 0.55)
      G.draw(tile, R.ptnQuad, x, y, 0, k, k)
    end
  end

  -- pieces of the drawn images (src/training/ui_art.lua's res_*), made once per image
  local quads = {}
  local function piece(name, img, x, y, w, h)
    local q = quads[name]
    if not q or q.img ~= img then
      local iw, ih = img:getDimensions()
      q = { img = img, q = love.graphics.newQuad(x, y, w, h, iw, ih) }
      quads[name] = q
    end
    return q.q
  end
  local function art(id)
    local A = T.assets
    return A and A.image and A.image(id) or nil
  end
  -- a stat row's plate from x0 to x1 (layout units), h tall: its rounded end, the middle
  -- stretched, its point
  local function rowPlate(G, img, x0, x1, y, h)
    local k = h / 26
    G.draw(img, piece("rowL", img, 0, 0, 30, 26), x0, y, 0, k, k)
    local mid = (x1 - x0) - 63 * k
    if mid > 0 then G.draw(img, piece("rowM", img, 30, 0, 1, 26), x0 + 30 * k, y, 0, mid, k) end
    G.draw(img, piece("rowR", img, 31, 0, 33, 26), x1 - 33 * k, y, 0, k, k)
  end
  local function ease(k)
    k = math.max(0, math.min(1, k))
    return k * k * (3 - 2 * k)
  end
  local TITLE_INK, BAND_TOP, BAND_FOOT = { 10, 52, 52 }, { 0.06, 0.12, 0.2, 0.9 }, { 0.08, 0.16, 0.26, 0.8 }
  local LIME, OLIVE_INK = { 160, 255, 96 }, { 34, 46, 12 }
  local WIN_INK, TIME_INK, BAND_INK = { 0, 90, 80 }, { 0, 70, 64 }, { 0, 60, 60 }

  -- the top screen in the layout's 400x240 units (drawn at 0.6, top-anchored): the title bar
  -- across the top, the band "Stat gain:", the six rows sliding in (each shorter than the one
  -- above), the meter with its labels, the trained stat's +N on its burst, the total's gauge
  local LABEL_AT = { hp = { 0, -64 }, atk = { 50, -38 }, def = { 50, 40 }, spe = { 0, 66 }, spd = { -50, 40 }, spa = { -50, -38 } }
  local function topEngine(G2, s)
    local r = R.r
    local e = T.topExtent or { x = 0, y = 0, w = 240, h = 160 }
    backdrop(G2, e.x, e.y, e.w, e.h, R.t or 0)
    if not r then return end
    local t = R.t or 0
    G2.push()
    local ox = e.x + e.w / 2 - 120
    G2.translate(ox, e.y)
    G2.scale(0.6, 0.6)
    local LX0, LX1 = (e.x - ox) / 0.6, (e.x + e.w - ox) / 0.6
    -- the title bar
    local title = art("training/res_title")
    G2.setColor(1, 1, 1, 1)
    if title then
      -- each half: its outer part from the screen's edge, the plain teal stretched, its inner
      -- end (with the tab) against the middle (layout x 200)
      local qA, qM, qB = piece("titleA", title, 0, 0, 150, 30), piece("titleM", title, 150, 0, 1, 30),
        piece("titleB", title, 150, 0, 50, 30)
      local span = math.max(0, 150 - LX0 - 150)
      G2.draw(title, qA, LX0, 0)
      G2.draw(title, qM, LX0 + 150, 0, 0, span, 1)
      G2.draw(title, qB, 150, 0)
      G2.draw(title, qB, 250, 0, 0, -1, 1)
      G2.draw(title, qM, 250 + span, 0, 0, -span, 1)
      G2.draw(title, qA, LX1, 0, 0, -1, 1)
    else
      col(G2, TEAL); G2.rectangle("fill", LX0, 0, LX1 - LX0, 30)
    end
    local lv = s.course and s.course.level
    say(G2, lv and (line(9 + lv) or ("Lv. " .. lv)) or "", 30, 8, 13, "left", TITLE_INK)
    say(G2, r.courseName or "", 76, 6, 16, "left", TITLE_INK)
    -- the band under it
    local bm = R.bandMesh
    if not bm then
      bm = love.graphics.newMesh({ { 0, 0, 0, 0, BAND_TOP[1], BAND_TOP[2], BAND_TOP[3], BAND_TOP[4] },
        { 1, 0, 0, 0, BAND_TOP[1], BAND_TOP[2], BAND_TOP[3], BAND_TOP[4] },
        { 1, 1, 0, 0, BAND_FOOT[1], BAND_FOOT[2], BAND_FOOT[3], BAND_FOOT[4] },
        { 0, 1, 0, 0, BAND_FOOT[1], BAND_FOOT[2], BAND_FOOT[3], BAND_FOOT[4] } }, "fan", "static")
      R.bandMesh = bm
    end
    G2.setColor(1, 1, 1, 1)
    G2.draw(bm, LX0, 35, 0, LX1 - LX0, 22)
    G2.setColor(0.5, 0.85, 0.95, 0.35); G2.rectangle("fill", LX0, 35, LX1 - LX0, 0.8); G2.rectangle("fill", LX0, 56.2, LX1 - LX0, 0.8)
    say(G2, r.clear and (line(60) or "Base stat increase:") or (line(59) or "Possible base stat increase:"),
      146, 38, 15, "center", WHITE)
    -- the six rows sliding in from the left, one after another
    local row, arrow = art("training/res_row"), art("training/res_arrow")
    for i, k in ipairs(STATS) do
      local inK = ease((t - R.TOP.STATUS_IN - (i - 1) * 0.05) / 0.25)
      local y = 61 + (i - 1) * 29
      local x1 = 186 - (i - 1) * 5
      G2.push()
      G2.translate((1 - inK) * -(x1 - LX0 + 20), 0)
      G2.setColor(1, 1, 1, 1)
      if row then rowPlate(G2, row, LX0 - 4, x1, y, 25)
      else col(G2, NAVY, 0.92); G2.polygon("fill", LX0, y, x1 - 10, y, x1, y + 12, x1 - 10, y + 25, LX0, y + 25) end
      local up = R.cues.up and r.stat == k
      -- the arrow and the +N hop together on the radar's beat (highest as the label swells)
      local hop = up and 3.2 * (0.5 + 0.5 * math.cos((t - R.TOP.STAT_UP) * 2 * math.pi / R.BEAT_S)) or 0
      if up and arrow then
        G2.setColor(0.6, 1, 0.35, 1)
        G2.draw(arrow, 7, y + 2.5 - hop, 0, 1, 1)
      end
      say(G2, T.statWord and T.statWord(k) or k, 23, y + 4, 16, "left", STAT_RGB[k])
      if up then say(G2, "+" .. tostring(r.ev), 128, y + 4 - hop, 16, "left", LIME) end
      G2.pop()
    end
    -- the meter on the right: the hexagon, the stats in it, the labels, the total's gauge
    if t >= R.TOP.STATUS_IN + 0.1 then
      local mk = ease((t - R.TOP.STATUS_IN - 0.1) / 0.3)
      local cx, cy = 300, 160
      local meter = art("training/home_meter")
      if meter then
        local mw, mh = meter:getDimensions()
        G2.setColor(1, 1, 1, 0.92 * mk)
        -- the hexagon's centre in the texture is (63.5, 85.5)
        G2.draw(meter, cx - 63.5, cy - 85.5, 0, 150 / mw, 150 / mh)
      end
      if Rules.meterAxes and Radar then
        local ri, ro = Rules.meterAxes(s.base or {}, s.evs or {}, Radar.ORDER)
        local inner, outer = {}, {}
        for i = 1, 6 do
          local a = -math.pi / 2 + (i - 1) * math.pi / 3
          inner[#inner + 1] = cx + math.cos(a) * ri[i] * mk; inner[#inner + 1] = cy + math.sin(a) * ri[i] * mk
          outer[#outer + 1] = cx + math.cos(a) * ro[i] * mk; outer[#outer + 1] = cy + math.sin(a) * ro[i] * mk
        end
        G2.setColor(0.8, 1, 0.25, 0.95); G2.polygon("fill", outer)
        G2.setColor(0.05, 0.62, 0.45, 1); G2.polygon("fill", inner)
        G2.setLineWidth(2); G2.setColor(0.85, 1, 0.3, 1); G2.polygon("line", outer)
      end
      -- the trained stat's beat (the game's: every 0.4 s its label, its +N on the burst and the
      -- gauge's arrow swell and shrink together), with a pop as it first goes up
      local up = R.cues.up and r.stat and LABEL_AT[r.stat] and true or false
      local since = t - R.TOP.STAT_UP
      local beat = up and (1 + 0.16 * math.cos(since * 2 * math.pi / R.BEAT_S)) or 1
      local pop = up and (1 + 0.3 * (1 - ease(since / 0.2))) or 1
      for k, at in pairs(LABEL_AT) do
        local img = art("training/label_" .. k)
        if img then
          local iw, ih = img:getDimensions()
          local ks = (up and k == r.stat) and beat * pop or 1
          G2.setColor(1, 1, 1, mk)
          G2.draw(img, cx + at[1], cy + at[2], 0, 60 * ks / iw, 19 * ks / ih, iw / 2, ih / 2)
        end
      end
      -- the +N on its dark burst, under the label
      if up then
        local at = LABEL_AT[r.stat]
        local ks = beat * pop
        local bx, by = cx + at[1], cy + at[2] + (at[2] < 0 and 21 or -21)
        local burst = art("training/point_up_win")
        if burst then
          local iw, ih = burst:getDimensions()
          G2.setColor(1, 1, 1, 1)
          G2.draw(burst, bx, by, 0, 46 * ks / iw, 22 * ks / ih, iw / 2, ih / 2)
        end
        say(G2, "+" .. tostring(r.ev), bx, by - 7 * ks, 14 * ks, "center", LIME)
      end
      -- the total: the bar up the track at the right, the arrow just above its top (never over
      -- the bar), pulsing on the same beat
      local gx, foot = cx + 79.5, cy + 47.5
      local hgt = (R.gaugeNow or 0)
      if hgt > 0 then
        G2.setColor(186 / 255, 1, 122 / 255, 1)
        G2.rectangle("fill", gx - 2, foot - hgt, 4, hgt)
        G2.setColor(1, 1, 1, 0.5); G2.rectangle("fill", gx - 0.6, foot - hgt, 1.2, hgt)
      end
      local block = art("training/arrow")
      if up and block then
        local bw = block:getDimensions()
        local size = 15 * beat
        -- the arrow's foot (its texture's y 15 of 16) on the bar's top
        G2.setColor(0.82, 1, 0.62, 1)
        G2.draw(block, gx, foot - hgt - 1, 0, size / bw, size / bw, bw / 2, bw * 15.5 / 16)
      end
    end
    G2.pop()
  end

  -- the touch screen in its 320 x lh layout units: the medallion and the time window hung
  -- from the top (the window inside the screen's right edge), or the bags banner; the band
  -- with its medal over the foot
  local function bottomEngine(G, lh)
    local D = math.max(0, (lh or 240) - 240)
    backdrop(G, -10, -20, 340, lh + 40, R.t or 0, true)
    local r = R.r
    local p = R.list and R.list[R.page]
    if not r then return D end
    local inK = ease(R.shownAt and ((R.t or 0) - R.shownAt) / 0.25 or 1)
    G.setColor(1, 1, 1, 1)
    if R.shown == "time" then
      -- the course's medallion pops in at the top left
      local pop = 0.6 + 0.4 * inK + 0.08 * math.sin(math.min(1, inK) * math.pi)
      G.push()
      G.translate(36, 37)
      G.scale(pop, pop)
      local frame = art("training/res_frame")
      if frame then
        local iw = frame:getDimensions()
        G.setColor(1, 1, 1, inK)
        G.draw(frame, 0, 0, 0, 70 / iw, 70 / iw, iw / 2, iw / 2)
      end
      if R.badge then
        local iw, ih = R.badge:getDimensions()
        G.setColor(1, 1, 1, inK)
        G.draw(R.badge, 0, 0, 0, 50 / iw, 50 / ih, iw / 2, ih / 2)
      end
      G.pop()
      -- the time window slides in from the right, its bracket inside the screen's edge
      local win = art("training/res_timewin")
      local wx, ww, wh = 92 + (1 - inK) * 240, 226, 64
      G.setColor(1, 1, 1, 1)
      if win then
        local iw, ih = win:getDimensions()
        G.draw(win, wx, 0, 0, ww / iw, wh / ih)
      else
        col(G, TEAL, 0.9); G.rectangle("fill", wx, 0, ww, wh, 6, 6)
      end
      say(G, T.resultText and T.resultText("timeRemaining") or "Time Remaining:", wx + 112, 9, 14, "center", WHITE, WIN_INK)
      say(G, clock(r.remaining), wx + 120, 30, 21, "left", WHITE, TIME_INK)
      local icon = R.icon
      if icon and icon.image then
        local q = icon.quads and (icon.quads[0] or icon.quads[1])
        local fw, fh = icon.w or 32, icon.h or 32
        local k = 40 / fw
        G.setColor(1, 1, 1, 1)
        local HD = mod.hd
        local draw = HD and HD.drawPixel or G.draw
        if q then draw(icon.image, q, wx + 52, 40, 0, k, k, fw / 2, fh / 2)
        else draw(icon.image, wx + 52, 40, 0, k, k, fw / 2, fh / 2) end
      end
    elseif R.shown == "bags" then
      -- the lime banner slides in from the left with the bags on their plates
      local bx = (1 - inK) * -340
      G.push()
      G.translate(bx, 0)
      local banner = art("training/res_banner")
      G.setColor(1, 1, 1, 1)
      if banner then
        local iw, ih = banner:getDimensions()
        G.draw(banner, -10, 34, 0, 340 / iw, 62 / ih)
      else
        G.setColor(0.75, 0.9, 0.35, 0.8); G.rectangle("fill", -10, 34, 340, 56)
      end
      say(G, T.resultText and T.resultText("bagsReceived") or "Training bags received:", 142, 40, 14, "center", OLIVE_INK)
      local row = art("training/res_row")
      local y = 61
      local function plate(x1)
        if row then G.setColor(0.78, 0.92, 0.66, 1); rowPlate(G, row, -14, x1, y, 26)
        else G.setColor(0.15, 0.2, 0.1, 0.9); G.rectangle("fill", -14, y, x1 + 14, 26) end
      end
      if r.bag then
        plate(206)
        local img = art(("training/sand_bag_%02d"):format(Rules.BAG_ART[r.bag] or 0))
        if img then
          local iw, ih = img:getDimensions()
          G.setColor(1, 1, 1, 1)
          G.draw(img, 22, y + 12, -0.35, 15 / iw, 37 / ih, iw / 2, ih / 2)
        end
        say(G, T.bagName and T.bagName(r.bag) or r.bag, 46, y + 5, 15, "left", WHITE)
        y = y + 30
      end
      if r.item then
        plate(206)
        local icon = T.items and T.items.icon and r.item.index and T.items.icon(r.item.index)
        if icon then
          local iw = icon:getDimensions()
          G.setColor(1, 1, 1, 1)
          G.draw(icon, 19, y + 13, 0, 22 / iw, 22 / iw, iw / 2, iw / 2)
        end
        say(G, r.item.name or "", 42, y + 5, 15, "left", WHITE)
      end
      G.pop()
    end
    -- the band: New best time! and the like, across the foot, the medal at its right
    if p and p.band then
      local y = 150 + D
      local band = art("training/res_band")
      G.setColor(1, 1, 1, 1)
      if band then
        local iw, ih = band:getDimensions()
        G.draw(band, -10, y, 0, 340 / iw, 44 / ih)
      else
        col(G, TEAL, 0.92); G.rectangle("fill", -10, y, 340, 26)
      end
      say(G, p.band, 160, y + 3.5, 15, "center", WHITE, BAND_INK)
      local medal = (r.medal or r.newBest) and art("training/medal")
      if medal then
        local iw = medal:getDimensions()
        local k = 32 / iw * (1 + 0.04 * math.sin((R.t or 0) * 4))
        G.setColor(1, 1, 1, 1)
        G.draw(medal, 298, y + 18, 0, k, k, iw / 2, iw / 2)
      end
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
