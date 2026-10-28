-- NAVIPLAY: the choice between the Alpha Sapphire card image's assets and NaviPlay's own,
-- and the progress screen for the extraction. With USE ROM ASSETS on, opening
-- Pokemon-Amie or Super Training with the cache missing or stale lands here (main.lua's
-- importGate). States: the BEGIN / RESUME EXTRACTION button when the card image is
-- there, a modern progress bar while the jobs run, a slow-flashing warning when the
-- card image is missing or is not Alpha Sapphire (Extract.why); under the button or the
-- warning, USE FALLBACK ASSETS (app.useFallback, wired by main: the option goes off).
-- When the run finishes the bar fades out and a play button fades in; pressing it
-- depresses, the game's shutters close over the screen (training/ss_black_out) and the
-- NaviPlay menu opens behind them, the shutters parting over it (app.openMenu, wired by
-- main); the fallback button leaves the same way. The banner is drawn
-- (src/apps/brand.lua), not shipped.

return function(mod, Pointer, Extract, Assets)
  local app = { id = "import", title = "NAVIPLAY", live = true, hapticTouch = true }

  -- app space is 256 x 178 (the tab strip's 14 rows above are reached with -bleed)
  local W, H = 256, 178
  -- The screen's shape: laid out for the 3DS shape's 178 rows; on a taller screen (Kanto
  -- Gear's) the backdrop and the shutters fill it all, the banner and the x stay at the
  -- top, and the content (texts, buttons, bar, warning) centres DH/2 lower.
  local SH, DH = H, 0
  app.BEGIN = { x = 46, y = 72, w = 164, h = 30 }
  app.FALLBACK = { x = 46, y = 110, w = 164, h = 30 }     -- under BEGIN, the same size
  app.FALLBACK_ABSENT = { x = 46, y = 128, w = 164, h = 30 }  -- under the warning
  app.PAUSE = { x = 88, y = 150, w = 80, h = 18 }
  app.CLOSE = { x = 237, y = 3, r = 12 }   -- centre and tap radius, in the banner's band
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
  local leaving = false  -- USE FALLBACK ASSETS pressed: on the way to the menu

  local function absentWhy()
    local s = Extract.state
    if s == "absent" then return Extract.why or "missing" end
    if s == "failed" and Extract.why == "wrong" then return "wrong" end
    return nil
  end

  function app:wantsSurface()
    if leaving then
      if opened then leaving, pressedAt, shutterAt, opened = false, nil, nil, false; return false end
      return true
    end
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

  -- how far the content sits lower on a taller screen (drivers add it to a button's place)
  function app.contentShift() return DH / 2 end

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
    local function fallback()
      leaving, pressedAt = true, Pointer.now()
      if app.useFallback then pcall(app.useFallback, absentWhy() or "declined") end
    end
    if s == "running" then
      if inRect(ev, app.PAUSE) then Extract.cancel() end
    elseif absentWhy() then
      if inRect(ev, app.FALLBACK_ABSENT) then fallback()
      else Extract.check() end   -- a tap re-checks: the card image may have just been installed
    elseif s == "idle" or s == "failed" then
      if inRect(ev, app.BEGIN) then
        if app.onExtract then pcall(app.onExtract) end
        Extract.start()
      elseif inRect(ev, app.FALLBACK) then
        fallback()
      end
    elseif s == "done" and doneAt and Pointer.now() - doneAt > 0.8 then
      if inCircle(ev, app.PLAY) then pressedAt = Pointer.now() end
    end
  end

  -- ------- drawing: NaviPlay's look (src/apps/brand.lua), shared with the menu

  local Brand
  do
    local src = mod.read and mod:read("src/apps/brand.lua")
    local chunk = src and load(src, "@" .. tostring(mod.path) .. "/src/apps/brand.lua")
    local ok, make = pcall(chunk or error)
    Brand = (ok and type(make) == "function") and make() or nil
  end
  if not Brand then error("src/apps/brand.lua missing") end
  local INK, col = Brand.INK, Brand.col

  local function text(G, s, y, k, c, a, wLimit)
    col(G, c, a)
    local wl = wLimit or 236
    G.printf(s, (W - wl) / 2, y, wl / k, "center", 0, k, k)
  end

  local function backdrop(G)
    local b = app.bleed or 0
    col(G, INK.bg)
    G.rectangle("fill", 0, -b, W, SH + b)
    for i, r in ipairs({ 100, 72, 48 }) do
      col(G, INK.glow, 0.028 * i)
      G.circle("fill", W / 2, 96 + DH / 2, r)
    end
    Brand.banner(G, W, b)
  end

  local function closeButton(G)
    G.push()
    G.translate(0, -DH / 2)   -- drawn inside the content's shift; it belongs in the strip
    Brand.close(G, app.CLOSE)
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

  -- USE FALLBACK ASSETS: words in an unfilled oval, quieter than the filled button; sunk
  -- once pressed
  local function fallbackButton(G, r)
    local sunk = leaving and pressedAt ~= nil and Pointer.now() - pressedAt < 0.14
    local k = sunk and 0.96 or 1
    local w, h = r.w * k, r.h * k
    local x, y = r.x + (r.w - w) / 2, r.y + (r.h - h) / 2
    col(G, INK.text, leaving and 0.9 or 0.6)
    G.setLineWidth(1.2)
    G.rectangle("line", x, y, w, h, h / 2, h / 2)
    G.setLineWidth(1)
    col(G, INK.text, leaving and 1 or 0.85)
    local tk = 0.62 * k
    G.printf("USE FALLBACK ASSETS", x, y + h / 2 - 6 * tk - 0.5, w / tk, "center", 0, tk, tk)
  end

  local function drawReady(G)
    local resumed = Extract.cancelled or (Extract.progress()) > 0
    text(G, "Use the assets from your own\nOmega Ruby or Alpha Sapphire copy, or NaviPlay's own.", 40, 0.55, INK.text)
    button(G, app.BEGIN, resumed and "RESUME EXTRACTION" or "BEGIN EXTRACTION", true)
    fallbackButton(G, app.FALLBACK)
    text(G, "One import. It keeps running in the background while you play.", 148, 0.5, INK.dim)
    if Extract.state == "failed" and Extract.message then
      text(G, tostring(Extract.message), 160, 0.5, INK.warn)
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
    text(G, Extract.state == "finishing" and "Decoding art..." or "Reading your OR/AS copy...", 52, 0.62, INK.text)
    drawBar(G, frac, 1)
    text(G, ("%d%%"):format(math.floor(frac * 100)), 96, 1.0, INK.bright)
    text(G, ("%d / %d"):format(done, total), 114, 0.55, INK.dim)
    if Extract.message and Extract.state ~= "finishing" then
      text(G, tostring(Extract.message), 128, 0.5, INK.dim)
    end
    local differs = Extract.differs or 0
    if Extract.failed > 0 and differs > 0 then
      text(G, ("%d could not be decoded, %d differ from Rev 2"):format(Extract.failed, differs), 140, 0.5, INK.warn)
    elseif Extract.failed > 0 then
      text(G, ("%d could not be decoded"):format(Extract.failed), 140, 0.5, INK.warn)
    elseif differs > 0 then
      text(G, ("%d differ from Alpha Sapphire Rev 2"):format(differs), 140, 0.5, INK.dim)
    end
    if Extract.state == "running" then button(G, app.PAUSE, "PAUSE", false) end
  end

  local function drawAbsent(G)
    local wrong = absentWhy() == "wrong"
    -- the slow flash: a breath about every three seconds
    local a = 0.35 + 0.55 * (0.5 + 0.5 * math.sin(Pointer.now() * 2.0))
    col(G, INK.warn, a)
    G.polygon("fill", W / 2, 38, W / 2 - 23, 78, W / 2 + 23, 78)
    col(G, INK.bg)
    G.rectangle("fill", W / 2 - 2.5, 49, 5, 17, 2, 2)
    G.rectangle("fill", W / 2 - 2.5, 69, 5, 5, 2, 2)
    text(G, wrong and "INCORRECT ROM ADDED" or "OR/AS ROM NOT FOUND", 86, 0.66, INK.warn, a)
    text(G, wrong and "The imported copy is not Omega Ruby or Alpha Sapphire."
      or "NaviPlay reads the OR/AS assets from your own card image.", 102, 0.5, INK.text)
    text(G, wrong and "Replace it under Imported files, then tap to check again."
      or "Install the import, then tap to check again.", 113, 0.5, INK.dim)
    fallbackButton(G, app.FALLBACK_ABSENT)
    closeButton(G)
  end

  -- the game's shutters over the whole screen (not the shifted content), f frames in
  local function drawShutters(G)
    local f = (Pointer.now() - shutterAt) * 30
    local b = app.bleed or 0
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

  -- a press (play or fallback) sinks for 0.14 s, then the shutters close
  local function startShutters()
    if pressedAt and not shutterAt and Pointer.now() - pressedAt >= 0.14 then
      shutterAt = Pointer.now()
      if app.shutterSound then pcall(app.shutterSound) end
    end
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
  -- the shutters close; behind them the NaviPlay menu opens
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
      drawPlay(G, a, sunk)
      if not pressedAt then closeButton(G) end
    end
    if failNote and Pointer.now() < failNote[2] then
      text(G, failNote[1], 140, 0.5, INK.warn)
    elseif a > 0 and not pressedAt and (Extract.differs or 0) > 0 then
      text(G, ("%d parts of your copy differ from Rev 2;\nNaviPlay draws its own there."):format(Extract.differs),
        136, 0.5, INK.dim, a)
    end
  end

  -- the handoff runs here, not mid-draw: once the shutters are shut, open the NaviPlay menu
  function app:update(dt)
    if not (shutterAt and not opened) then return end
    if (Pointer.now() - shutterAt) * 30 < 16 then return end
    opened = true
    local ok, why = false, "unavailable"
    if app.openMenu then ok, why = app.openMenu() end
    if not ok then
      -- stuck shut would be worse: back to the button with the reason
      opened, pressedAt, shutterAt, leaving = false, nil, nil, false
      failNote = { ("NaviPlay could not open (%s)"):format(tostring(why)), Pointer.now() + 3 }
    end
  end

  function app:draw(G, w, h)
    SH = h or H
    DH = math.max(0, SH - H)
    backdrop(G)
    G.push()
    G.translate(0, DH / 2)
    local s = Extract.state
    if leaving then
      -- the screen the fallback was chosen on, under the closing shutters
      if absentWhy() then drawAbsent(G) else drawReady(G) end
    elseif s == "running" or s == "finishing" then
      doneAt = nil
      drawRunning(G)
    elseif absentWhy() then
      drawAbsent(G)
    elseif (s == "done" or s == "complete") and Extract.cacheComplete() then
      drawFinale(G)
    else
      doneAt = nil
      drawReady(G)
    end
    if not ((s == "done" or s == "complete") and not leaving) and failNote and Pointer.now() < failNote[2] then
      text(G, failNote[1], 166, 0.5, INK.warn)
    end
    startShutters()
    if shutterAt then drawShutters(G) end
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  return app
end
