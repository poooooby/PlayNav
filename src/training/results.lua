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
      add({ show = "time", band = band, text = T.praise(r, true) or r.praise })
    else
      add({ text = line(127) or T.resultText("failed") })
    end
    if r.bag or r.item then
      add({ show = "bags", text = line(165) or "You faced the challenge of a Super-Training Regimen and got a reward in return!" })
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

  function R.begin(s)
    local r = s and s.result
    R.s, R.r = s, r
    R.t, R.page, R.pageT, R.cues, R.done, R.shown = 0, 1, 0, {}, false, nil
    R.list = r and pages(s, r) or {}
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
    R.page = R.page + 1
    R.enterPage()
    return true
  end

  function R.update(dt)
    if not R.list then return end
    dt = dt or 0
    R.t, R.pageT = R.t + dt, R.pageT + dt
    local P, B = R.top, R.bottom
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
    local x, y, w, h = P:box("7o")
    if not (x and Rules.meterAxes and Radar) then return end
    local cx, cy = x + w / 2, y + h / 2
    local ri, ro = Rules.meterAxes(s.base or {}, s.evs or {}, Radar.ORDER)
    local inner, outer = {}, {}
    for i = 1, 6 do
      local a = -math.pi / 2 + (i - 1) * math.pi / 3
      inner[#inner + 1] = cx + math.cos(a) * ri[i]
      inner[#inner + 1] = cy + math.sin(a) * ri[i]
      outer[#outer + 1] = cx + math.cos(a) * ro[i]
      outer[#outer + 1] = cy + math.sin(a) * ro[i]
    end
    G.setColor(0.8, 1, 0.25, 1)
    G.polygon("fill", outer)
    G.setColor(0.05, 0.62, 0.45, 1)
    G.polygon("fill", inner)
    G.setLineWidth(2)
    G.setColor(0.85, 1, 0.3, 1)
    G.polygon("line", outer)
    G.setLineWidth(1)
  end

  -- 400x240 into the top screen's 240x160: the card's way (0.6, top-anchored), the backdrop
  -- reaching the foot
  function R.drawTop(G2, s)
    local P = R.top
    if not P or R.s ~= s then return false end
    G2.push()
    G2.scale(0.6, 0.6)
    -- the layout as the game has it, top-aligned at 0.6; only the backdrops fill down to 160
    -- (spreading the panes would pull the gauge's bar off its track)
    P.stretchY = (160 / 0.6) / 240
    P.stretchMode = "backdrop"
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

  function R.drawBottom(G)
    local B = R.bottom
    if not B then return false end
    B:draw(G)
    -- the course's badge in its frame (the game renders it into stage_icon01's place)
    if R.badge and R.shown == "time" then
      local x, y, w, h = B:box("3n")
      if x then
        local iw, ih = R.badge:getDimensions()
        G.setColor(1, 1, 1, 1)
        G.draw(R.badge, x + w / 2, y + h / 2, 0, w * 0.86 / iw, h * 0.86 / ih, iw / 2, ih / 2)
      end
    end
    -- the trainee's party icon in the time window
    local icon = R.icon
    if icon and icon.image and R.shown == "time" then
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
        local foot = p.band and MSG.footBand or MSG.foot
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
