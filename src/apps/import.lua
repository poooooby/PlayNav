-- PLAYNAV: the gate and progress screen for the Alpha Sapphire art extraction.
-- PlayNav needs its extracted art: opening Pokemon-Amie or Super Training with the
-- cache missing or stale lands here (main.lua's importGate) instead of a stand-in
-- version. States: the BEGIN / RESUME EXTRACTION button when the card image is
-- there, a modern progress bar while the jobs run, a slow-flashing warning when
-- the card image is missing. When the run finishes the bar fades out and a play
-- button fades in; pressing it depresses, the game's shutters close over the
-- screen (training/ss_black_out) and Super Training's home screen opens behind
-- them (app.openTraining, wired by main). The banner is drawn, not shipped.

return function(mod, Pointer, Extract, Assets)
  local app = { id = "import", title = "PLAYNAV", live = true }

  -- app space is 256 x 178 (the tab strip's 14 rows above are reached with -bleed)
  local W, H = 256, 178
  -- The screen's shape: laid out for the 3DS shape's 178 rows; on a taller screen (Kanto
  -- Gear's) the backdrop and the shutters fill it all, the banner and the x stay at the
  -- top, and the content (texts, buttons, bar, warning) centres DH/2 lower.
  local SH, DH = H, 0
  app.BEGIN = { x = 46, y = 92, w = 164, h = 30 }
  app.PAUSE = { x = 88, y = 150, w = 80, h = 18 }
  app.CLOSE = { x = 236, y = -8, r = 10 }   -- centre and tap radius, up in the strip's rows
  app.PLAY = { x = 128, y = 96, r = 22 }    -- the play button's centre and tap radius

  local function art(id)
    if not Assets or Assets.enabled == false then return nil end
    return Assets.image(id)
  end

  -- src/training/lyt.lua: the game's shutters for the way into Super Training
  do
    local src = mod.read and mod:read("src/training/lyt.lua")
    local chunk = src and load(src, "@" .. tostring(mod.path) .. "/src/training/lyt.lua")
    local ok, make = pcall(chunk or error)
    if ok and type(make) == "function" then app.lyt = make() end
  end

  -- the finale: doneAt starts the bar's fade, pressedAt the depress, shutterAt the close
  local doneAt, pressedAt, shutterAt, opened = nil, nil, nil, false
  local failNote = nil   -- { text, until } when Super Training would not open

  function app:wantsSurface()
    local s = Extract.state
    if s == "running" or s == "finishing" then return true end
    if (s == "done" or s == "complete") and Extract.cacheComplete() then
      -- "done" holds the play button up after a run; a boot that finds the cache
      -- already there ("complete") never shows the screen
      return s == "done" and not opened
    end
    doneAt, pressedAt, shutterAt, opened = nil, nil, nil, false
    return s == "idle" or s == "absent" or s == "failed"
  end

  local function inRect(ev, r)
    return ev.x >= r.x and ev.x <= r.x + r.w and ev.y >= r.y and ev.y <= r.y + r.h
  end
  local function inCircle(ev, c)
    local dx, dy = ev.x - c.x, ev.y - c.y
    return dx * dx + dy * dy <= c.r * c.r
  end

  function app:pointer(ev, rec)
    if not (ev.phase == "released" and Pointer.isTap(rec, 16, 1.0)) then return end
    local s = Extract.state
    if pressedAt or shutterAt then return end   -- on its way in; taps are done
    if s ~= "running" and s ~= "finishing" and inCircle(ev, app.CLOSE) then
      if app.close then app.close() end
      return
    end
    -- the content sits DH/2 lower on a taller screen
    ev = { x = ev.x, y = ev.y - DH / 2, phase = ev.phase }
    if s == "running" then
      if inRect(ev, app.PAUSE) then Extract.cancel() end
    elseif s == "idle" or s == "failed" then
      if inRect(ev, app.BEGIN) then Extract.start() end
    elseif s == "absent" then
      Extract.check()   -- a tap re-checks: the card image may have just been installed
    elseif s == "done" and doneAt and Pointer.now() - doneAt > 0.8 then
      if inCircle(ev, app.PLAY) then pressedAt = Pointer.now() end
    end
  end

  -- ------- drawing. One accent, the banner's violet, over a near-black ground.

  local INK = { bg = { 0.055, 0.04, 0.09 }, glow = { 0.486, 0.227, 0.929 },
    text = { 0.66, 0.61, 0.78 }, dim = { 0.48, 0.435, 0.59 }, bright = { 0.92, 0.9, 0.98 },
    accent = { 0.545, 0.36, 0.965 }, sheen = { 0.68, 0.53, 1.0 }, line = { 0.255, 0.2, 0.42 },
    track = { 0.133, 0.1, 0.21 }, warn = { 1.0, 0.69, 0.125 }, ok = { 0.2, 0.83, 0.6 },
    bandL = { 0.21, 0.1, 0.35 }, bandR = { 0.08, 0.045, 0.15 }, outline = { 0.42, 0.18, 0.85 } }

  local function col(G, c, a) G.setColor(c[1], c[2], c[3], a or 1) end

  local function text(G, s, y, k, c, a, wLimit)
    col(G, c, a)
    local wl = wLimit or 236
    G.printf(s, (W - wl) / 2, y, wl / k, "center", 0, k, k)
  end

  -- the PlayNav banner, recreated with the engine: the violet band, the two-figure
  -- icon and the chunky outlined wordmark (imgs/banner.png is the model, GitHub only)
  local function banner(G)
    local b = app.bleed or 0
    local y0, y1 = -b, 24
    local n = 8
    for i = 0, n - 1 do
      local t = i / (n - 1)
      G.setColor(INK.bandL[1] + (INK.bandR[1] - INK.bandL[1]) * t,
        INK.bandL[2] + (INK.bandR[2] - INK.bandL[2]) * t,
        INK.bandL[3] + (INK.bandR[3] - INK.bandL[3]) * t, 1)
      G.rectangle("fill", i * W / n, y0, W / n + 1, y1 - y0)
    end
    col(G, INK.outline, 0.55)
    G.rectangle("fill", 0, y1 - 1.2, W, 1.2)
    local f = G.getFont()
    local k = 1.55
    local word = "PlayNav"
    local tw = f:getWidth(word) * k
    local iconW = 30
    local x0 = (W - (iconW + 9 + tw)) / 2
    local cy = (y0 + y1) / 2 - 1
    -- the icon: a violet rounded square, white border, two figures
    local ic = { x = x0 + iconW / 2, y = cy }
    col(G, { 0.49, 0.25, 0.9 })
    G.rectangle("fill", ic.x - 14, ic.y - 10.5, 28, 21, 6, 6)
    col(G, { 1, 1, 1 }, 0.95)
    G.setLineWidth(2)
    G.rectangle("line", ic.x - 14, ic.y - 10.5, 28, 21, 6, 6)
    G.setLineWidth(1)
    for _, dx in ipairs({ -6, 6 }) do
      G.circle("fill", ic.x + dx, ic.y - 3.8, 2.8)
      -- the body: an arch, round at the shoulders and flat at the floor
      G.rectangle("fill", ic.x + dx - 4, ic.y - 0.2, 8, 7.2, 3.5, 3.5)
      G.rectangle("fill", ic.x + dx - 4, ic.y + 3.4, 8, 3.6)
    end
    -- the wordmark: a violet glow, a rounded outline, then the near-white fill
    local tx, ty = x0 + iconW + 9, cy - f:getHeight() * k / 2
    col(G, INK.glow, 0.16)
    for a = 0, 7 do
      G.print(word, tx + 3.1 * math.cos(a * math.pi / 4), ty + 3.1 * math.sin(a * math.pi / 4), 0, k, k)
    end
    col(G, INK.outline)
    for a = 0, 11 do
      G.print(word, tx + 1.7 * math.cos(a * math.pi / 6), ty + 1.7 * math.sin(a * math.pi / 6), 0, k, k)
    end
    col(G, { 0.96, 0.94, 1 })
    G.print(word, tx, ty, 0, k, k)
    -- a hairline under the band, bright in the middle
    for _, seg in ipairs({ { 42, 0.12 }, { 86, 0.3 } }) do
      col(G, INK.accent, seg[2])
      G.rectangle("fill", W / 2 - seg[1], 30, seg[1] * 2, 1)
    end
  end

  local function backdrop(G)
    local b = app.bleed or 0
    col(G, INK.bg)
    G.rectangle("fill", 0, -b, W, SH + b)
    for i, r in ipairs({ 100, 72, 48 }) do
      col(G, INK.glow, 0.028 * i)
      G.circle("fill", W / 2, 96 + DH / 2, r)
    end
    banner(G)
  end

  local function closeButton(G)
    G.push()
    G.translate(0, -DH / 2)   -- drawn inside the content's shift; it belongs in the strip
    local c = app.CLOSE
    col(G, INK.track)
    G.circle("fill", c.x, c.y, 7)
    col(G, INK.line)
    G.circle("line", c.x, c.y, 7)
    col(G, INK.text)
    G.printf("x", c.x - 10, c.y - 5.5, 20 / 0.7, "center", 0, 0.7, 0.7)
    G.pop()
  end

  local function button(G, r, label, filled)
    if filled then
      col(G, INK.accent)
      G.rectangle("fill", r.x, r.y, r.w, r.h, 9, 9)
      col(G, INK.sheen, 0.4)
      G.rectangle("fill", r.x + 2, r.y + 2, r.w - 4, r.h / 2 - 2, 7, 7)
      col(G, INK.sheen, 0.5)
      G.rectangle("line", r.x, r.y, r.w, r.h, 9, 9)
      col(G, { 1, 1, 1 })
    else
      col(G, INK.line)
      G.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
      col(G, INK.text)
    end
    local k = filled and 0.8 or 0.62
    G.printf(label, r.x, r.y + r.h / 2 - 6 * k - 1 + (filled and 2 or 1.5), r.w / k, "center", 0, k, k)
  end

  local function drawReady(G)
    local resumed = Extract.cancelled or (Extract.progress()) > 0
    text(G, "Pokemon-Amie and Super Training are built\nfrom your own Alpha Sapphire card image.", 50, 0.55, INK.text)
    button(G, app.BEGIN, resumed and "RESUME EXTRACTION" or "BEGIN EXTRACTION", true)
    text(G, "One import. It keeps running in the background while you play.", 132, 0.5, INK.dim)
    if Extract.state == "failed" and Extract.message then
      text(G, tostring(Extract.message), 146, 0.5, INK.warn)
    end
    closeButton(G)
  end

  local function drawBar(G, frac, a)
    local bx, by, bw, bh = 28, 76, 200, 12
    col(G, INK.track, a)
    G.rectangle("fill", bx, by, bw, bh, 6, 6)
    col(G, INK.line, 0.8 * a)
    G.rectangle("line", bx, by, bw, bh, 6, 6)
    local fw = math.max(0, math.floor(bw * frac))
    if fw > 2 then
      local r = math.min(6, fw / 2)
      col(G, INK.accent, a)
      G.rectangle("fill", bx, by, fw, bh, r, r)
      col(G, INK.sheen, 0.45 * a)
      G.rectangle("fill", bx + 1, by + 1, math.max(1, fw - 2), bh / 2 - 1, math.max(0, r - 1), math.max(0, r - 1))
    end
  end

  local function drawRunning(G)
    local done, total = Extract.progress()
    local frac = total > 0 and done / total or 0
    text(G, Extract.state == "finishing" and "Decoding art..." or "Reading Alpha Sapphire...", 52, 0.62, INK.text)
    drawBar(G, frac, 1)
    text(G, ("%d%%"):format(math.floor(frac * 100)), 96, 1.0, INK.bright)
    text(G, ("%d / %d"):format(done, total), 114, 0.55, INK.dim)
    if Extract.message and Extract.state ~= "finishing" then
      text(G, tostring(Extract.message), 128, 0.5, INK.dim)
    end
    if Extract.failed > 0 then
      text(G, ("%d could not be decoded"):format(Extract.failed), 140, 0.5, INK.warn)
    end
    if Extract.state == "running" then button(G, app.PAUSE, "PAUSE", false) end
  end

  local function drawAbsent(G)
    -- the slow flash: a breath about every three seconds
    local a = 0.35 + 0.55 * (0.5 + 0.5 * math.sin(Pointer.now() * 2.0))
    col(G, INK.warn, a)
    G.polygon("fill", W / 2, 58, W / 2 - 27, 104, W / 2 + 27, 104)
    col(G, INK.bg)
    G.rectangle("fill", W / 2 - 2.5, 70, 5, 20, 2, 2)
    G.rectangle("fill", W / 2 - 2.5, 94, 5, 5, 2, 2)
    text(G, "ALPHA SAPPHIRE ROM IS MISSING", 114, 0.66, INK.warn, a)
    text(G, "PlayNav builds its art from your own card image.", 132, 0.5, INK.text)
    text(G, "Install the import, then tap to check again.", 144, 0.5, INK.dim)
    closeButton(G)
  end

  -- the play button: no words, just the triangle; sunk while pressed
  local function drawPlay(G, a, sunk)
    local c = app.PLAY
    local k = (sunk and 0.9 or 1)
    local r = 19 * k
    col(G, INK.glow, 0.22 * a)
    G.circle("fill", c.x, c.y, r + 5)
    col(G, sunk and { 0.36, 0.17, 0.72 } or INK.accent, a)
    G.circle("fill", c.x, c.y, r)
    if not sunk then
      col(G, INK.sheen, 0.4 * a)
      G.arc("fill", c.x, c.y - r * 0.25, r * 0.78, math.pi, 2 * math.pi)
    end
    col(G, INK.sheen, 0.55 * a)
    G.circle("line", c.x, c.y, r)
    col(G, { 1, 1, 1 }, (sunk and 0.85 or 1) * a)
    local t = 9 * k
    G.polygon("fill", c.x - t * 0.62 + 1.5, c.y - t, c.x - t * 0.62 + 1.5, c.y + t, c.x + t + 1.5, c.y)
  end

  -- after the run: the bar fades out, the play button fades in, a press sinks it and
  -- the shutters close; behind them Super Training's home screen opens
  local function drawFinale(G)
    doneAt = doneAt or Pointer.now()
    local d = Pointer.now() - doneAt
    if d < 0.45 then
      local _, total = Extract.progress()
      drawBar(G, 1, 1 - d / 0.45)
      if total and total > 0 then
        text(G, ("%d / %d"):format(total, total), 114, 0.55, INK.dim, 1 - d / 0.45)
      end
    end
    local a = math.max(0, math.min(1, (d - 0.45) / 0.4))
    if a > 0 then
      local sunk = pressedAt ~= nil and (Pointer.now() - pressedAt) < 0.14
      if pressedAt and not shutterAt and Pointer.now() - pressedAt >= 0.14 then
        shutterAt = Pointer.now()
      end
      drawPlay(G, a, sunk)
      if not pressedAt then closeButton(G) end
    end
    if failNote and Pointer.now() < failNote[2] then
      text(G, failNote[1], 140, 0.5, INK.warn)
    end
    if shutterAt then
      local f = (Pointer.now() - shutterAt) * 30
      local b = app.bleed or 0
      -- the whole screen, not the shifted content
      G.push()
      G.translate(0, -b - DH / 2)
      if app.lyt then
        app.lyt.shutters(G, art, W, SH + b, "close", math.min(f, 10))
      else
        col(G, { 0, 0, 0 }, math.min(1, f / 10))
        G.rectangle("fill", 0, 0, W, SH + b)
      end
      G.pop()
    end
  end

  -- the handoff runs here, not mid-draw: once the shutters are shut, open Super Training
  function app:update(dt)
    if not (shutterAt and not opened) then return end
    if (Pointer.now() - shutterAt) * 30 < 16 then return end
    opened = true
    local ok, why = false, "unavailable"
    if app.openTraining then ok, why = app.openTraining() end
    if not ok then
      -- stuck shut would be worse: back to the button with the reason
      opened, pressedAt, shutterAt = false, nil, nil
      failNote = { ("Super Training could not open (%s)"):format(tostring(why)), Pointer.now() + 3 }
    end
  end

  function app:draw(G, w, h)
    SH = h or H
    DH = math.max(0, SH - H)
    backdrop(G)
    G.push()
    G.translate(0, DH / 2)
    local s = Extract.state
    if s == "running" or s == "finishing" then
      doneAt = nil
      drawRunning(G)
    elseif s == "absent" then
      drawAbsent(G)
    elseif (s == "done" or s == "complete") and Extract.cacheComplete() then
      drawFinale(G)
    else
      doneAt = nil
      drawReady(G)
    end
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  return app
end
