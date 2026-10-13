-- The DS bottom screen as a drawing target: the apps draw into a 256x192 logical space,
-- blitted into a window rect (split mode) or read back and pushed to a second display.
--
-- High resolution: the canvas is W*k by H*k real pixels, k the output's pixels per logical
-- unit (src/hd.lua HD.density), and the apps draw under a scale(k) transform. Their
-- coordinates, sizes and hit areas stay 256x192, but every image is sampled at the pixels it
-- will finally occupy, so art is never shrunk onto a coarse grid and blown up in blocks.
-- k = 1 is the plain low-resolution path. Everything love-related is guarded so a headless
-- load never touches the GPU.

return function(mod, Layout, HD)
  local G = love and love.graphics

  local S = {
    W = Layout.W, H = Layout.H,
    canvas = nil, k = 1, font = nil, smallFont = nil, fontK = nil,
    dirty = true,
  }

  local function density(k)
    if HD then return HD.density(k, 1) end
    return 1
  end

  -- the canvas for density k (rebuilt only when k changes)
  function S:ensure(k)
    if not G then return nil end
    k = k or self.k or 1
    if not self.canvas or self.k ~= k then
      local pw, ph = math.floor(self.W * k + 0.5), math.floor(self.H * k + 0.5)
      local ok, canvas = pcall(G.newCanvas, pw, ph, { dpiscale = 1 })
      if not ok then
        if k > 1 then return self:ensure(1) end
        return nil
      end
      canvas:setFilter("nearest", "nearest")
      self.canvas, self.k = canvas, k
      self.dirty = true
    end
    if not self.font or self.fontK ~= k then
      -- glyphs rasterised at k times the size, metrics in logical units: crisp text, the
      -- same widths every layout was written for
      local ok, font = pcall(G.newFont, 11, "normal", k)
      if not ok then ok, font = pcall(G.newFont, 11) end
      if ok then self.font = font end
      local okS, small = pcall(G.newFont, 9, "normal", k)
      if not okS then okS, small = pcall(G.newFont, 9) end
      if okS then self.smallFont = small end
      self.fontK = k
    end
    return self.canvas
  end

  -- Render drawFn(G, w, h) into the canvas at density k (output pixels per logical unit).
  -- Errors are reported and the frame is kept, so a broken app never takes the game down.
  function S:render(drawFn, k)
    local canvas = self:ensure(density(k or self.k))
    if not canvas then return false end
    G.push("all")
    G.setCanvas(canvas)
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    G.clear(0.07, 0.08, 0.10, 1)
    if self.k ~= 1 then G.scale(self.k, self.k) end
    G.setColor(1, 1, 1, 1)
    if self.font then G.setFont(self.font) end
    local ok, err = pcall(drawFn, G, self.W, self.H)
    G.setCanvas()
    G.pop()
    if not ok then mod.log:warn("surface draw failed: %s", tostring(err)) end
    self.dirty = false
    return ok
  end

  -- the density a window rect wants: its scale times the screen's DPI
  function S:densityFor(rect)
    if not (G and rect) then return 1 end
    local dpi = G.getDPIScale and G.getDPIScale() or 1
    return density((rect.scale or 1) * dpi)
  end

  -- Blit the canvas into a window rect {x, y, w, h, scale}; a thin dark bezel keeps the
  -- surface edge readable over any game colour. One canvas pixel per screen pixel when the
  -- density matches the rect; a smooth resample in the frame after a resize when it does not.
  function S:blit(rect)
    if not (G and self.canvas and rect) then return end
    local s = (rect.scale or 1) / self.k
    G.push("all")
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", rect.x - 2, rect.y - 2, rect.w + 4, rect.h + 4)
    G.setColor(1, 1, 1, 1)
    local dpi = G.getDPIScale and G.getDPIScale() or 1
    local exact = math.abs(s * dpi - 1) < 1e-3 or self.k == 1
    if not exact then self.canvas:setFilter("linear", "linear") end
    G.draw(self.canvas, rect.x, rect.y, 0, s, s)
    if not exact then self.canvas:setFilter("nearest", "nearest") end
    G.pop()
  end

  -- Readback for the second display at an integer factor k (the display reports touches in
  -- those pixels; divide by k). The canvas is rendered at k itself, so no upscale pass.
  -- `pushSource` draws the frame and returns the canvas to read; `imageData` reads it at once
  -- (a blocking GPU readback); `requestPush` / `pollPush` read it without waiting.
  local function pushSource(self, k, drawFn)
    if not G then return nil end
    k = math.max(1, math.floor(k or 2))
    local want = (HD and HD.enabled) and math.min(k, HD.MAX_K) or 1
    if drawFn then self:render(drawFn, want) end
    if not self.canvas then return nil end
    local pw, ph = self.W * k, self.H * k
    local src = self.canvas
    if src:getPixelWidth() ~= pw then
      -- the canvas is at a lower density (HD off, or k above the cap): scale it up once
      if not self.pushCanvas or self.pushK ~= k then
        local ok, c = pcall(G.newCanvas, pw, ph, { dpiscale = 1 })
        if not ok then return nil end
        c:setFilter("nearest", "nearest")
        self.pushCanvas, self.pushK = c, k
      end
      G.push("all")
      G.setCanvas(self.pushCanvas)
      G.origin()
      G.setShader()
      G.setBlendMode("alpha")
      G.clear(0, 0, 0, 1)
      G.setColor(1, 1, 1, 1)
      local f = pw / src:getPixelWidth()
      G.draw(src, 0, 0, 0, f, f)
      G.setCanvas()
      G.pop()
      src = self.pushCanvas
    end
    return src, pw, ph
  end

  function S:imageData(k, drawFn)
    local src, pw, ph = pushSource(self, k, drawFn)
    if not src then return nil end
    local ok, data = pcall(src.newImageData, src)
    if not ok then return nil end
    return data, pw, ph
  end

  -- The second display without stalling the GPU: where the engine's LOVE can read a canvas
  -- back asynchronously (Android: requestImageData / pollImageData, as Kanto Gear does), the
  -- frame is drawn and its readback started here, and pollPush hands over the pixels a frame
  -- or two later. No new frame is drawn while one is being read (the canvas must not change
  -- under it); a readback stuck for STALE_S starts over on fresh canvases. Without the async
  -- calls it falls back to the blocking read and returns the pixels at once.
  S.STALE_S = 1.0
  function S:dropStale(now)
    if self.pending and now and now - self.pending.at > S.STALE_S then
      self.pending = nil
      self.canvas, self.pushCanvas = nil, nil
    end
  end

  function S:requestPush(k, drawFn, now)
    self:dropStale(now)
    if self.pending then return nil end
    local src, pw, ph = pushSource(self, k, drawFn)
    if not src then return nil end
    if src.requestImageData and src.pollImageData then
      local ok, started = pcall(src.requestImageData, src)
      if ok and started ~= false then
        self.pending = { src = src, w = pw, h = ph, at = now or 0 }
        return nil
      end
    end
    local ok, data = pcall(src.newImageData, src)
    if not ok then return nil end
    return data, pw, ph
  end

  function S:pollPush()
    local p = self.pending
    if not p then return nil end
    local ok, data = pcall(p.src.pollImageData, p.src)
    if not ok then
      self.pending = nil
      return nil
    end
    if not data then return nil end
    self.pending = nil
    return data, p.w, p.h
  end

  return S
end
