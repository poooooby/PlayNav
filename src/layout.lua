-- Pure geometry for the DS-style surface. No love access, so every function
-- here runs headless in the tests.
--
-- The surface is a logical 256-wide space, 256x230: Kanto Gear's phone shape (its 160x144
-- screen, 10:9). Layout.setShape("3ds") (256x192, the 3DS bottom screen) remains for the
-- geometry tests only; the mod always runs the Gear's shape. The layout decides where that space sits in the OS window and
-- at what scale, and converts window coordinates back into logical ones. Every app draws
-- to the height it is handed; the training screens' 320-wide layout space is
-- Layout.H / 0.8 tall (Layout.LH: 287.5 or 240).

local Layout = {}

Layout.SHAPES = { gear = 230, ["3ds"] = 192 }
Layout.W, Layout.H = 256, Layout.SHAPES.gear
Layout.shape = "gear"
Layout.LH = Layout.H / 0.8

-- switch the surface's shape; returns true when it changed
function Layout.setShape(shape)
  local h = Layout.SHAPES[shape] or Layout.SHAPES.gear
  if not Layout.SHAPES[shape] then shape = "gear" end
  if Layout.H == h and Layout.shape == shape then return false end
  Layout.shape, Layout.H, Layout.LH = shape, h, h / 0.8
  return true
end

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
--
-- `fill` (the overworld is live on the top screen: Super Training's home, no PlayNav layer on
-- top), Kanto Gear style: the engine draws the overworld across its whole playfield and
-- centres only the 240x160 frame (menus, text) at a whole-number scale, so the top gets every
-- unit the touch screen does not use.
--   portrait   the touch screen as wide as the window allows (4:3), sitting on the pad's
--              room; the playfield is everything above it, full width
--   landscape  the touch screen as without fill; the playfield is the whole column left of it
-- opts = { gameW, gameH, dpi, reserveBottom, margin, gap, x, y, fill, safe }
-- Returns { orientation, game = {x,y,w,h,scale} (the playfield handed to the engine),
-- picture = {x,y,w,h,scale} (where the 240x160 frame lands), surface = {x,y,w,h,scale} }.
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
  -- `safe` % of the window's foot left free first (BOTTOM SAFE AREA, as Layout.gear)
  local safe = math.max(0, math.min(50, tonumber(opts.safe) or 0))
  wh = math.max(1, wh - math.floor(wh * safe / 100))
  local fill = opts.fill == true
  local reserve = portrait and math.max(0, opts.reserveBottom or 0) or 0
  local availW = portrait and ww or (ww - margin * 2)
  local availH = wh - margin * 2 - reserve
  local aspect = Layout.W / Layout.H

  -- the touch screen's height beside / under a picture ph tall and pw wide: the picture's
  -- height at most, and what the room leaves
  local function surfaceH(pw, ph)
    local h
    if portrait then h = math.min(fill and math.huge or ph, availH - ph - gap, (availW - (fill and margin * 2 or 0)) / aspect)
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
  local game, surface, picture
  if portrait and fill then
    -- the touch screen on the pad's room; the playfield is all that is above it
    surface = { x = snap(ox + (ww - sw) / 2), y = snap(oy + wh - reserve - margin - sh), w = sw, h = sh, scale = sh / Layout.H }
    game = { x = ox, y = oy, w = ww, h = snap(math.max(ph, surface.y - gap - oy)) }
  elseif portrait then
    local top = oy + margin
    game = { x = snap(ox + (ww - pw) / 2), y = snap(top), w = pw, h = ph, scale = k / dpi }
    surface = { x = snap(ox + (ww - sw) / 2), y = snap(top + ph + gap), w = sw, h = sh, scale = sh / Layout.H }
  else
    local left, top = ox + margin, oy + margin
    game = { x = snap(left), y = snap(top), w = pw, h = ph, scale = k / dpi }
    surface = { x = snap(left + pw + gap), y = snap(top), w = sw, h = sh, scale = sh / Layout.H }
    if fill then game = { x = ox, y = oy, w = snap(surface.x - gap - ox), h = wh } end
  end
  if fill then
    -- where the engine's Display.fit puts the frame: the largest whole scale, centred
    local kk = math.max(1, math.floor(math.min(game.w * dpi / gw, game.h * dpi / gh) + 1e-9))
    local fw, fh = gw * kk / dpi, gh * kk / dpi
    picture = { x = snap(game.x + (game.w - fw) / 2), y = snap(game.y + (game.h - fh) / 2), w = fw, h = fh, scale = kk / dpi }
    game.scale = picture.scale
  else
    picture = game
  end
  return { orientation = portrait and "portrait" or "landscape", game = game, picture = picture, surface = surface,
    fill = fill }
end


-- Split screen as Kanto Gear lays out its COMBINED SCREEN, so the two mods share one look:
-- the window cut into the game's part and the touch screen's by a share (stacked: the touch
-- screen 36% of the height under the game; side: 34% of the width right of it; `size` 20..80
-- overrides), a gap of 1% of the shorter side (at least 2), `safe` % taken off the foot first,
-- `swapped` trading the two parts; the touch screen fitted into its part at one scale and
-- centred, the game's part handed to the engine, which centres the 240x160 frame in it at a
-- whole scale. THEME:windowLayout and THEME:fitRect adapted from Kanto Gear (MIT,
-- (c) 2026 AverageConsumer, github.com/AverageConsumer/kanto-gear). OVERLAY: the game has the
-- whole window and the touch screen floats over it in `corner` (top_left / top_right /
-- bottom_left / bottom_right), `gap` in from the edges, 42% of the height tall (`size`
-- overrides) and at most 38% of the width, in the Gear's 160:144 box; a swap is not taken
-- there (the game stays the full window). Positions land on whole physical pixels (`dpi`);
-- `reserveBottom` (window units) is kept free under both parts.
-- FULLSCREEN (Kanto Gear's FULLSCREEN SWAP): the game and the touch screen each the whole
-- window, one shown at a time (the caller picks), no safe area.
-- opts = { layout = "auto" | "stacked" | "side" | "overlay" | "fullscreen", corner, size, safe, swapped, dpi,
--   reserveBottom, gameW, gameH, x, y }
-- Returns { orientation, game, picture, surface } as Layout.dual does.
function Layout.fitRect(rect, width, height)
  local scale = math.min(rect.w / width, rect.h / height)
  local w, h = width * scale, height * scale
  return { x = math.floor(rect.x + (rect.w - w) / 2), y = math.floor(rect.y + (rect.h - h) / 2),
    w = w, h = h, scale = scale }
end

function Layout.gear(ww, wh, opts)
  opts = opts or {}
  if ww < 1 or wh < 1 then return nil end
  local gw, gh = opts.gameW or 240, opts.gameH or 160
  local dpi = (opts.dpi and opts.dpi > 0) and opts.dpi or 1
  local ox, oy = opts.x or 0, opts.y or 0
  local mode = opts.layout
  if mode == "large" then mode = "overlay" end
  if mode ~= "stacked" and mode ~= "side" and mode ~= "overlay" and mode ~= "fullscreen" then
    mode = ww >= wh and "side" or "stacked"
  end
  local height = wh - math.max(0, opts.reserveBottom or 0)
  local safe = mode == "fullscreen" and 0 or math.max(0, math.min(50, tonumber(opts.safe) or 0))
  height = math.max(1, height - math.floor(height * safe / 100))
  local width = ww
  local gap = math.max(2, math.floor(math.min(width, height) * 0.01))
  local requested = tonumber(opts.size)
  local function share(fallback) return math.max(20, math.min(80, requested or fallback)) / 100 end
  local game, gear
  if mode == "fullscreen" then
    game = { x = 0, y = 0, w = width, h = height }
    gear = { x = 0, y = 0, w = width, h = height }
  elseif mode == "stacked" then
    local gearH = math.floor((height - gap) * share(36))
    game = { x = 0, y = 0, w = width, h = height - gearH - gap }
    gear = { x = 0, y = game.h + gap, w = width, h = gearH }
  elseif mode == "side" then
    local gearW = math.floor((width - gap) * share(34))
    game = { x = 0, y = 0, w = width - gearW - gap, h = height }
    gear = { x = game.w + gap, y = 0, w = gearW, h = height }
  else
    local gearH = math.floor(height * share(42))
    local gearW = math.min(math.floor(width * (requested and share(42) or 0.38)), math.floor(gearH * 160 / 144))
    local corner = opts.corner or "bottom_right"
    local left = corner == "top_left" or corner == "bottom_left"
    local top = corner == "top_left" or corner == "top_right"
    game = { x = 0, y = 0, w = width, h = height }
    gear = { x = left and gap or width - gearW - gap, y = top and gap or height - gearH - gap, w = gearW, h = gearH }
  end
  if opts.swapped and mode ~= "overlay" and mode ~= "fullscreen" then game, gear = gear, game end
  local function snap(v) return math.floor(v * dpi + 1e-6) / dpi end
  game = { x = snap(ox + game.x), y = snap(oy + game.y), w = snap(game.w), h = snap(game.h) }
  local fit = Layout.fitRect(gear, Layout.W, Layout.H)
  local surface = { x = snap(ox + fit.x), y = snap(oy + fit.y), w = fit.w, h = fit.h, scale = fit.scale }
  -- where the engine's Display.fit puts the frame: the largest whole scale, centred
  local kk = math.max(1, math.floor(math.min(game.w * dpi / gw, game.h * dpi / gh) + 1e-9))
  local fw, fh = gw * kk / dpi, gh * kk / dpi
  local picture = { x = snap(game.x + (game.w - fw) / 2), y = snap(game.y + (game.h - fh) / 2), w = fw, h = fh,
    scale = kk / dpi }
  game.scale = picture.scale
  return { orientation = (mode == "stacked" or (mode == "overlay" and wh >= ww)) and "portrait" or "landscape",
    game = game, picture = picture, surface = surface, fill = true, mode = mode, overlay = mode == "overlay" }
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
