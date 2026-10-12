-- REGIMENS, the course picker on the bottom screen: a 3x6 grid of the regular courses
-- (rows Lv1-3, columns HP / Atk / Def / SpA / SpD / Spe) with locks, medals and best
-- times, the twelve secret courses once the Pokemon is Fully Trained, the pending bag
-- effect, START and BACK.

return function(mod, Pointer, T, Rules)
  local app = { id = "training_courses", title = "REGIMENS", live = true, hideTabs = true }
  local N = Rules.N

  function app:wantsSurface() return T.session ~= nil and T.session.mode == "courses" end

  local W, H = 256, 178
  local TILE = { w = 40, h = 24, gapX = 1, gapY = 12, x0 = 5, y0 = 12 }
  local SECRET = { w = 19, h = 14, gapX = 1, x0 = 5, y0 = 120 }
  local STATUS = { x = 4, y = 137, w = 248, h = 24 }
  local START = { x = 4, y = 161, w = 60, h = 15 }
  local BACK = { x = 192, y = 161, w = 60, h = 15 }

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end
  local selected = nil

  local function fitText(G, text, x, y, w, h)
    local TF = mod.textfit
    if TF and G.getFont() then return TF.print(G, G.getFont(), text, x, y, w, h, "center") end
    G.printf(text, x, y, w, "center")
  end

  local function fonts()
    if app.fontsFn then
      local f, s = app.fontsFn()
      if f then return f, s or f end
    end
    local f = love.graphics.getFont()
    return f, f
  end

  local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

  local function tileRect(level, col)
    return { x = TILE.x0 + (col - 1) * (TILE.w + TILE.gapX), y = TILE.y0 + (level - 1) * (TILE.h + TILE.gapY), w = TILE.w, h = TILE.h }
  end
  -- the twelve secret courses in one row
  local function secretRect(n)
    return { x = SECRET.x0 + (n - 1) * 20, y = SECRET.y0, w = SECRET.w, h = SECRET.h }
  end

  function app.geometry()
    return { tileRect = tileRect, secretRect = secretRect, START = START, BACK = BACK, TILE = TILE }
  end
  function app.select(id)
    selected = id
    if T.session then T.session.picked = id end
  end
  function app.selected() return selected end

  local function courseAt(x, y)
    for _, c in ipairs(T.courseList()) do
      local r
      if c.secret then r = secretRect(c.secret)
      else
        local col = 1
        for i, st in ipairs(Rules.STATS) do if st == c.stat then col = i end end
        r = tileRect(c.level, col)
      end
      if inRect(x, y, r) then return c end
    end
    return nil
  end

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "courses") then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    if inRect(x, y, BACK) then selected = nil; s.picked = nil; T.enterCore(); return end
    if inRect(x, y, START) then
      if selected then T.startCourse(selected) end
      return
    end
    local c = courseAt(x, y)
    if c then
      if selected == c.id then
        T.startCourse(c.id)
      else
        selected = c.id
        s.picked = c.id   -- the top screen shows its card
        local ok, why = T.canEnter(c)
        if not ok then
          T.say(why == "not_fully_trained" and "Only a Fully Trained POKeMON may enter." or "Clear every course of the level below first.", 2.5)
        end
        -- an open course needs no message: the top screen shows its card
      end
    end
  end

  function app:update(dt) end

  local function drawTile(G, r, c, font, small)
    local ok = T.canEnter(c)
    local rec = T.courseRecord(c.id)
    local sel = selected == c.id
    local card = art("training/stage_win")
    if card then
      G.setColor(1, 1, 1, ok and 1 or 0.45)
      G.draw(card, r.x, r.y, 0, r.w / 128, r.h / 64)
      if sel then
        G.setColor(0.25, 0.65, 0.95, 0.45)
        G.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
      end
    else
      if sel then G.setColor(0.25, 0.65, 0.95, 1)
      elseif not ok then G.setColor(0.16, 0.18, 0.24, 1)
      else
        local rgb = c.stat and T.STAT_RGB[c.stat] or { 0.5, 0.45, 0.7 }
        G.setColor(rgb[1] * 0.55, rgb[2] * 0.55, rgb[3] * 0.55, 1)
      end
      G.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
    end
    G.setColor(1, 1, 1, ok and 0.9 or 0.35)
    G.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
    -- the course's badge (or the lock) on the left, the score on the right; the row's
    -- heading already says the level and the badge shows the bot
    local badge = ok and c.bots[1].art and art(c.bots[1].art) or (not ok and art("training/locked")) or nil
    G.setFont(small)
    G.setColor(ok and 1 or 0.6, ok and 1 or 0.6, ok and 1 or 0.6, 1)
    if c.secret then
      local size = math.min(r.h - 2, 13)
      if badge then
        G.setColor(1, 1, 1, 1)
        G.draw(badge, r.x + (r.w - size) / 2, r.y + (r.h - size) / 2, 0, size / badge:getWidth(), size / badge:getHeight())
      else
        G.printf(tostring(c.secret), r.x, r.y + (r.h - small:getHeight()) / 2, r.w, "center")
      end
    else
      -- the badge top left, the score along the bottom (four digits need the width)
      local size = 13
      if badge then
        G.setColor(1, 1, 1, 1)
        G.draw(badge, r.x + 2, r.y + 1, 0, size / badge:getWidth(), size / badge:getHeight())
      end
      G.setColor(ok and 1 or 0.6, ok and 1 or 0.6, ok and 1 or 0.6, 1)
      G.printf(ok and tostring(c.bots[1].score) or (badge and "" or "LOCK"), r.x, r.y + r.h - small:getHeight() - 1, r.w - 3, "right")
    end
    if rec and rec.medal then
      local medal = art("training/medal")
      if medal then
        G.setColor(1, 1, 1, 1)
        G.draw(medal, r.x + r.w - 11, r.y - 2, 0, 0.4, 0.4)
      else
        G.setColor(1, 0.85, 0.2, 1)
        G.circle("fill", r.x + r.w - 5, r.y + 5, 3, 8)
      end
    elseif rec and rec.clears and rec.clears > 0 then
      G.setColor(0.7, 0.9, 0.7, 1)
      G.circle("fill", r.x + r.w - 5, r.y + 5, 2, 8)
    end
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    G.setColor(0.09, 0.11, 0.16, 1)
    G.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    if not s then return end
    -- the game's headings over each row
    G.setFont(small)
    for lv = 1, 3 do
      G.setColor(1, 1, 1, 0.75)
      G.print(T.levelHeading(lv), TILE.x0, tileRect(lv, 1).y - 9)
    end
    for _, c in ipairs(T.courseList()) do
      if c.secret then
        if s.rec.fully then drawTile(G, secretRect(c.secret), c, font, small) end
      else
        local col = 1
        for i, st in ipairs(Rules.STATS) do if st == c.stat then col = i end end
        drawTile(G, tileRect(c.level, col), c, font, small)
      end
    end
    G.setFont(small)
    G.setColor(1, 1, 1, 0.75)
    if s.rec.fully then
      G.print(T.levelHeading(nil, 1), SECRET.x0, SECRET.y0 - 9)
    else
      G.printf("Secret regimens open to Fully Trained POKeMON", 0, SECRET.y0 + 2, w, "center")
    end
    -- the selected course's details
    local c = selected and T.course(selected)
    local y = STATUS.y + 1
    local win = art("training/status_win")
    if win then
      G.setColor(1, 1, 1, 0.95)
      G.draw(win, STATUS.x, STATUS.y, 0, STATUS.w / 190, STATUS.h / 40)
    end
    if c then
      local rec = T.courseRecord(c.id)
      local target = Rules.medalTarget(c)
      G.setColor(win and 0.1 or 1, win and 0.12 or 1, win and 0.16 or 1, 0.95)
      local name = T.courseName(c.id)
      local parts = { ("Score %d"):format(c.bots[#c.bots].score), ("Target %d:%02d left"):format(math.floor(target / 60), target % 60) }
      if #c.bots > 1 then parts[#parts + 1] = ("%d bots"):format(#c.bots) end
      if rec and rec.best then parts[#parts + 1] = ((T.resultText("bestTime") .. " %s"):format(T.Draw and T.Draw.clock(rec.best) or tostring(rec.best))) end
      -- both lines inside the window's art, smaller when they would run past it
      fitText(G, name .. "\n" .. table.concat(parts, "   "), 16, STATUS.y + 1, w - 40, 16)
    else
      G.setColor(win and 0.2 or 1, win and 0.22 or 1, win and 0.28 or 1, 0.8)
      G.printf("Pick a regimen.", 8, y + 4, w - 16, "center")
    end
    if s.rec.pending then
      G.setColor(1, 0.9, 0.5, 1)
      G.printf("NEXT: " .. (Rules.EFFECT_LABEL[s.rec.pending] or s.rec.pending), 70, 164, 116, "center")
    end
    local function button(r, label, on)
      G.setColor(on and 0.2 or 0.25, on and 0.6 or 0.3, on and 0.85 or 0.42, 1)
      G.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
      G.setColor(1, 1, 1, 0.9)
      G.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
      G.printf(label, r.x, r.y + 3, r.w, "center")
    end
    button(START, "START", c ~= nil and T.canEnter(c))
    button(BACK, "BACK", false)
    G.setColor(1, 1, 1, 1)
  end

  return app
end
