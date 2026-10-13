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

-- Split screen, one layout, New 3DS XL style: the game picture (the top screen) as large as
-- it can be, the touch screen beside or under it at the same height (the XL's two screens are
-- both 240 rows: 400x240 over 320x240).
--   portrait   the picture at the top, the touch screen just under it, both centred across;
--              `reserveBottom` (the engine's touch pad) stays free below
--   landscape  the picture at the far left, the touch screen right of it, both from the top
-- The picture's scale is a whole number of physical pixels (`dpi` = pixels per window unit),
-- as the engine's Display.fit draws it; the touch screen may be any size. A step smaller
-- picture is taken when the touch screen would otherwise drop below MIN_MATCH of its height.
-- opts = { gameW, gameH, dpi, reserveBottom, margin, gap, x, y }
-- Returns { orientation, game = {x,y,w,h,scale}, surface = {x,y,w,h,scale} }.
Layout.MIN_MATCH = 0.8
function Layout.dual(ww, wh, opts)
  opts = opts or {}
  if ww < 1 or wh < 1 then return nil end
  local gw, gh = opts.gameW or 240, opts.gameH or 160
  local dpi = (opts.dpi and opts.dpi > 0) and opts.dpi or 1
  local margin = opts.margin or 4
  local gap = opts.gap or 8
  local ox, oy = opts.x or 0, opts.y or 0
  local portrait = wh >= ww
  local reserve = portrait and math.max(0, opts.reserveBottom or 0) or 0
  local availW = portrait and ww or (ww - margin * 2)
  local availH = wh - margin * 2 - reserve
  local aspect = Layout.W / Layout.H

  -- the touch screen's height beside / under a picture ph tall and pw wide: the picture's
  -- height at most, and what the room leaves
  local function surfaceH(pw, ph)
    local h
    if portrait then h = math.min(ph, availH - ph - gap, availW / aspect)
    else h = math.min(ph, availH, (availW - pw - gap) / aspect) end
    return math.max(0, h)
  end

  local kMax = math.floor(math.min(availW * dpi / gw, math.max(0, availH) * dpi / gh) + 1e-9)
  local k, sh = nil, 0
  for cand = math.max(1, kMax), 1, -1 do
    local pw, ph = gw * cand / dpi, gh * cand / dpi
    local h = surfaceH(pw, ph)
    if h >= ph * Layout.MIN_MATCH or cand == 1 then
      k, sh = cand, h
      break
    end
  end
  local pw, ph = gw * k / dpi, gh * k / dpi
  local sw = sh * aspect
  -- on whole physical pixels
  local function snap(v) return math.floor(v * dpi + 1e-6) / dpi end
  local game, surface
  if portrait then
    local top = oy + margin
    game = { x = snap(ox + (ww - pw) / 2), y = snap(top), w = pw, h = ph, scale = k / dpi }
    surface = { x = snap(ox + (ww - sw) / 2), y = snap(top + ph + gap), w = sw, h = sh, scale = sh / Layout.H }
  else
    local left, top = ox + margin, oy + margin
    game = { x = snap(left), y = snap(top), w = pw, h = ph, scale = k / dpi }
    surface = { x = snap(left + pw + gap), y = snap(top), w = sw, h = sh, scale = sh / Layout.H }
  end
  return { orientation = portrait and "portrait" or "landscape", game = game, surface = surface }
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
