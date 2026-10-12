-- Pure geometry for the DS-style surface. No love access, so every function
-- here runs headless in the tests.
--
-- The surface is a logical 256x192 space (the real DS bottom screen). The
-- layout decides where that space sits in the OS window and at what scale,
-- and converts window coordinates back into logical ones.

local Layout = {}

Layout.W, Layout.H = 256, 192

local function floor(v) return math.floor(v + 0.0001) end

-- The scale that fits a 256x192 surface into (aw, ah): an integer when the
-- surface fits at 1x or more, so pixels stay crisp; fractional below that so
-- a very short margin still gets a working (if soft) surface.
function Layout.fit(aw, ah)
  if aw <= 0 or ah <= 0 then return 0 end
  local s = math.min(aw / Layout.W, ah / Layout.H)
  if s >= 1 then s = math.floor(s) end
  return s
end

local function clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end

-- Single-screen split. Portrait: the game keeps the top `ratio` of the
-- height, the surface takes the rest above the bottom safe area. Landscape:
-- the game keeps the left, the surface takes the right `landscapeShare`.
-- Returns { orientation, game = {x,y,w,h}, surface = {x,y,w,h,scale} }.
function Layout.split(ww, wh, opts)
  opts = opts or {}
  local safe = math.max(0, opts.safeBottom or 0)
  local margin = opts.margin or 4
  if wh >= ww then
    local ratio = clamp(opts.ratio or 0.55, 0.3, 0.85)
    local availW = ww - margin * 2
    local availH = math.max(24, wh - safe - floor(wh * ratio) - margin * 2)
    local s = Layout.fit(availW, availH)
    local sw, sh = floor(Layout.W * s), floor(Layout.H * s)
    local sx = floor((ww - sw) / 2)
    local sy = wh - safe - margin - sh
    return {
      orientation = "portrait",
      game = { x = 0, y = 0, w = ww, h = math.max(1, sy - margin) },
      surface = { x = sx, y = sy, w = sw, h = sh, scale = s },
    }
  end
  local share = clamp(opts.landscapeShare or 0.42, 0.25, 0.6)
  local availW = math.max(32, floor(ww * share) - margin * 2)
  local availH = math.max(24, wh - safe - margin * 2)
  local s = Layout.fit(availW, availH)
  local sw, sh = floor(Layout.W * s), floor(Layout.H * s)
  local sx = ww - margin - sw
  local sy = floor((wh - safe - sh) / 2)
  return {
    orientation = "landscape",
    game = { x = 0, y = 0, w = math.max(1, sx - margin), h = wh },
    surface = { x = sx, y = sy, w = sw, h = sh, scale = s },
  }
end

-- Place the surface inside an arbitrary free rectangle (the letterbox
-- margin under the Gen 3 picture). nil when the rectangle is too small to be
-- worth touching.
function Layout.inRect(rx, ry, rw, rh, opts)
  opts = opts or {}
  local margin = opts.margin or 4
  local safe = math.max(0, opts.safeBottom or 0)
  local availW, availH = rw - margin * 2, rh - safe - margin * 2
  if availW < 64 or availH < 48 then return nil end
  local s = Layout.fit(availW, availH)
  local sw, sh = floor(Layout.W * s), floor(Layout.H * s)
  local y
  if opts.anchor == "bottom" then
    y = ry + rh - safe - margin - sh
  else
    y = ry + floor((rh - safe - sh) / 2)
  end
  return {
    x = rx + floor((rw - sw) / 2),
    y = y,
    w = sw, h = sh, scale = s,
  }
end

-- Single-screen stack for a game whose picture is W x H at an integer scale
-- (Gen 3: 240x160). Lays the picture above the surface in portrait and left
-- of it in landscape, centres the pair in the free space, and never lets
-- them overlap at any window size. How the room is shared:
--   balance = "auto"   the largest picture that still leaves a 1x surface (default)
--             "equal"  the same integer scale for both (the DS look)
--             "ds3"    the picture one scale step above the surface (the 3DS look)
--             "ds3_flip" the surface one step above the picture
--             "game"   the largest picture; the surface takes what is left, even below 1x
--             "touch"  the largest surface; the picture takes what is left
--   gameScale / surfaceScale  fixed integer scales; clamped so the pair still fits,
--             the other side filling the rest
-- opts = { gameW, gameH, safeBottom, margin, gap, maxGameShare, balance, gameScale, surfaceScale }
-- Returns { orientation, game = {x,y,w,h,scale}, surface = {x,y,w,h,scale} }.
function Layout.stack(ww, wh, opts)
  opts = opts or {}
  local gw, gh = opts.gameW or 240, opts.gameH or 160
  local safe = math.max(0, opts.safeBottom or 0)
  local margin = opts.margin or 4
  local gap = opts.gap or 8
  local share = clamp(opts.maxGameShare or 0.6, 0.3, 0.9)
  local balance = opts.balance or "auto"
  if ww < 1 or wh < 1 then return nil end
  local portrait = wh >= ww
  -- the picture may touch the side edges; the margin keeps it off the top
  -- and bottom (and off the sides in landscape, where width is the scarce axis)
  local availW = portrait and ww or (ww - margin * 2)
  local availH = portrait and (wh - safe - margin * 2) or (wh - safe)

  -- the surface scale left over by a picture at scale k (0 when nothing fits)
  local function surfaceFor(k)
    local pw, ph = gw * k, gh * k
    if portrait then return Layout.fit(availW, availH - ph - gap) end
    return Layout.fit(availW - pw - gap, availH)
  end
  -- the picture scale left over by a surface at scale sc
  local function gameFor(sc)
    local sw, sh = Layout.W * sc, Layout.H * sc
    local k
    if portrait then k = math.floor(math.min(availW / gw, (availH - sh - gap) / gh))
    else k = math.floor(math.min((availW - sw - gap) / gw, availH / gh)) end
    return math.max(0, k)
  end
  local kMax = math.max(1, portrait and math.floor(availW / gw) or math.floor(availH / gh))
  local sMax = math.max(1, math.floor(math.min(availW / Layout.W, availH / Layout.H)))

  local k, s
  local wantK = tonumber(opts.gameScale)
  local wantS = tonumber(opts.surfaceScale)
  if wantK and wantK >= 1 then
    k = math.min(math.floor(wantK), kMax)
    while k > 1 and surfaceFor(k) <= 0 do k = k - 1 end
    s = surfaceFor(k)
    if wantS and wantS >= 1 then s = math.min(math.floor(wantS), s >= 1 and math.floor(s) or 0) end
    if s <= 0 then s = surfaceFor(k) end
  elseif wantS and wantS >= 1 then
    s = math.min(math.floor(wantS), sMax)
    while s > 1 and gameFor(s) < 1 do s = s - 1 end
    k = math.max(1, gameFor(s))
    if gameFor(s) < 1 then s = surfaceFor(1) end
  elseif balance == "equal" or balance == "ds3" or balance == "ds3_flip" then
    local picked = false
    if balance == "ds3" then
      for n = math.min(kMax - 1, sMax), 1, -1 do
        if surfaceFor(n + 1) >= n then k, s = n + 1, n; picked = true; break end
      end
    elseif balance == "ds3_flip" then
      for n = math.min(sMax - 1, kMax), 1, -1 do
        if gameFor(n + 1) >= n then k, s = n, n + 1; picked = true; break end
      end
    end
    if not picked then
      local n = math.min(kMax, sMax)
      while n > 1 and surfaceFor(n) < n do n = n - 1 end
      k = n
      s = surfaceFor(n) >= n and n or surfaceFor(n)
    end
  elseif balance == "game" then
    k = kMax
    while k > 1 and surfaceFor(k) <= 0 do k = k - 1 end
    s = surfaceFor(k)
  elseif balance == "touch" then
    s = sMax
    while s > 1 and gameFor(s) < 1 do s = s - 1 end
    k = math.max(1, gameFor(s))
    if gameFor(s) < 1 then s = surfaceFor(1) end
  else
    local best
    for cand = kMax, 1, -1 do
      local pw, ph = gw * cand, gh * cand
      local within = portrait and (ph <= availH * share) or (not portrait and pw <= availW * share)
      if within or cand == 1 then
        local sc = surfaceFor(cand)
        if sc > 0 then
          if sc >= 1 then best = { k = cand, s = sc }; break end
          if not best then best = { k = cand, s = sc } end
        end
      end
    end
    if not best then best = { k = 1, s = surfaceFor(1) } end
    k, s = best.k, best.s
  end
  if not s or s < 0 then s = 0 end

  local pw, ph = gw * k, gh * k
  local sw, sh = floor(Layout.W * s), floor(Layout.H * s)
  local game, surface
  if portrait then
    local total = ph + gap + sh
    local top = margin + math.max(0, floor((availH - total) / 2))
    game = { x = floor((ww - pw) / 2), y = top, w = pw, h = ph, scale = k }
    surface = { x = floor((ww - sw) / 2), y = top + ph + gap, w = sw, h = sh, scale = s }
  else
    local total = pw + gap + sw
    local left = margin + math.max(0, floor((availW - total) / 2))
    game = { x = left, y = floor((wh - safe - ph) / 2), w = pw, h = ph, scale = k }
    surface = { x = left + pw + gap, y = floor((wh - safe - sh) / 2), w = sw, h = sh, scale = s }
  end
  return { orientation = portrait and "portrait" or "landscape", game = game, surface = surface,
    balance = balance }
end

-- Window (or pushed-frame) coordinates to logical surface coordinates.
-- Returns lx, ly, inside.
function Layout.toLogical(rect, x, y)
  if not rect or not rect.scale or rect.scale <= 0 then return nil, nil, false end
  local lx = (x - (rect.x or 0)) / rect.scale
  local ly = (y - (rect.y or 0)) / rect.scale
  return lx, ly, lx >= 0 and ly >= 0 and lx < Layout.W and ly < Layout.H
end

return Layout
