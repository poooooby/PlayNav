-- 3D AMIE's stage without the card (src/amie/stage3d.lua): the game's stage rebuilt to its
-- measure (collision02, in its units: the Pokemon at the origin, y up) from NaviPlay's own
-- pictures and ones drawn here - a lawn disc rising to a lip, the dotted sky cylinder going from
-- light blue at the foot to navy, a rainbow, a ring of cumulus, bands of small clouds and a
-- cylinder of bubbles. Built once, in an update step (its pictures are drawn into canvases).
--   scene = Stand(St, R, Assets)

local sqrt, sin, cos, pi, floor = math.sqrt, math.sin, math.cos, math.pi, math.floor

-- the card stage's measures (tools/bch.py model a/1/0/1 0)
local M = {
  FLOOR_R = 468, LIP_R = 499.5, LIP_Y = 95.7, FLOOR_UV = 3.87, LIP_RGB = { 0.67, 0.73, 0.54 },
  SKY_R = 468, SKY_TILES_U = 320, SKY_TILE_Y = 12.2,
  -- the sky's colour by height: y, r, g, b, a
  SKY = { { 3, 0.67, 0.78, 1, 0 }, { 62, 0.67, 0.78, 1, 1 }, { 334, 0.12, 0.36, 1, 1 }, { 660, 0.01, 0.08, 0.46, 1 },
    { 876, 0, 0.07, 0.44, 1 }, { 1637, 0, 0.06, 0.43, 1 } },
  CUMULUS = { r = 446.5, y0 = 2, y1 = 331, tiles = 5, foot = { 0.82, 0.88, 1 } },
  -- the small clouds: bands of one row each (y0, y1, colour, alpha)
  CLOUDS = { r = 453.4, tiles = 8, bands = { { 194, 366, 1, 1, 1, 1 }, { 459, 546, 0.52, 0.72, 1, 0.5 },
    { 625, 826, 0.52, 0.72, 1, 0.5 }, { 895, 1096, 0.45, 0.6, 0.9, 0.45 }, { 1147, 1348, 0.4, 0.5, 0.8, 0.4 } } },
  BUBBLES = { r = 443.6, y0 = 10, y1 = 1634, tiles_u = 9, tiles_v = 5.6, fade = 47, alpha = 0.7, topAlpha = 0.5 },
  -- the rainbow: one quad, its ends on the circle r 461.5
  RAINBOW = { x0 = 48, z0 = -459, x1 = 309, z1 = -343, y0 = 172, y1 = 459 },
  SEGS = 48,
}

-- ------- pictures, drawn once into canvases and read back

local function picture(w, h, draw)
  local G = love.graphics
  local c = G.newCanvas(w, h, { dpiscale = 1 })
  G.push("all")
  G.setCanvas(c)
  G.origin()
  G.clear(0, 0, 0, 0)
  draw(G, w, h)
  G.pop()
  local img = G.newImage(c:newImageData())
  c:release()
  img:setFilter("linear", "linear")
  return img
end

-- a circle drawn at each wrapped place, so the picture tiles
local function wrapped(G, w, h, x, y, r, mode)
  for dx = -1, 1 do
    for dy = -1, 1 do G.circle(mode or "fill", x + dx * w, y + dy * h, r, 24) end
  end
end

local function hash(i, k) return (sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end

local function lawn()
  return picture(128, 128, function(G, w, h)
    G.setColor(0.26, 0.62, 0.12, 1)
    G.rectangle("fill", 0, 0, w, h)
    for i = 1, 40 do
      G.setColor(0.2 + 0.1 * hash(i, 1), 0.55 + 0.12 * hash(i, 2), 0.1, 0.5)
      wrapped(G, w, h, w * hash(i, 3), h * hash(i, 4), 3 + 6 * hash(i, 5))
    end
    for i = 1, 6 do
      G.setColor(0.55, 0.85, 0.3, 0.35)
      wrapped(G, w, h, w * hash(i, 6), h * hash(i, 7), 9 + 9 * hash(i, 8))
    end
  end)
end

local function dots()
  return picture(32, 32, function(G, w, h)
    G.setColor(0.86, 0.9, 0.98, 1)
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(1, 1, 1, 1)
    wrapped(G, w, h, w / 2, h / 2, 6.5)
  end)
end

local function rainbow()
  return picture(256, 128, function(G, w, h)
    local bands = { { 0.93, 0.33, 0.33 }, { 0.98, 0.62, 0.42 }, { 0.98, 0.9, 0.36 }, { 0.6, 0.9, 0.32 },
      { 0.62, 0.95, 0.9 }, { 0.42, 0.8, 0.98 }, { 0.68, 0.55, 0.88 } }
    local outer, inner = 127, 48
    local step = (outer - inner) / #bands
    for i, c in ipairs(bands) do
      G.setColor(c[1], c[2], c[3], 1)
      G.arc("fill", w / 2, h, outer - (i - 1) * step, pi, 2 * pi, 64)
    end
    -- the middle cut out
    G.setBlendMode("replace")
    G.setColor(0, 0, 0, 0)
    G.arc("fill", w / 2, h, inner, pi, 2 * pi, 64)
    G.setBlendMode("alpha")
  end)
end

local function bubbles()
  return picture(256, 256, function(G, w, h)
    for i = 1, 9 do
      local x, y, r = 20 + (w - 40) * hash(i, 11), 20 + (h - 40) * hash(i, 12), 7 + 11 * hash(i, 13)
      G.setColor(0.85, 0.95, 1, 0.18)
      G.circle("fill", x, y, r, 32)
      G.setLineWidth(1.6)
      G.setColor(0.95, 0.85, 1, 0.75)
      G.circle("line", x, y, r, 32)
      G.setColor(1, 1, 1, 0.95)
      G.circle("fill", x - r * 0.4, y - r * 0.4, r * 0.22, 16)
    end
  end)
end

local function puffs(rows)
  return picture(256, 128, function(G, w, h)
    for i = 1, rows do
      local cx, cy = w * (i - 0.5) / rows, h * 0.6
      for k = 1, 7 do
        G.setColor(1, 1, 1, 1)
        G.circle("fill", cx + (k - 4) * 9 + 4 * hash(i * 7 + k, 1), cy - 10 * hash(i * 7 + k, 2), 10 + 6 * hash(i * 7 + k, 3), 24)
      end
    end
  end)
end

-- ------- geometry (triangles for g3d: x, y, z, u, v, nx, ny, nz, r, g, b, a)

local function vert(out, x, y, z, u, v, r, g, b, a)
  out[#out + 1] = { x, y, z, u, v, 0, 1, 0, r, g, b, a }
end
local function quad(out, a, b, c, d)
  out[#out + 1] = a; out[#out + 1] = b; out[#out + 1] = c
  out[#out + 1] = a; out[#out + 1] = c; out[#out + 1] = d
end

-- a band of a cylinder (radius r, from y0 to y1), its texture repeated tiles times round and
-- from v0 to v1 up; colour rows c0 at the foot, c1 at the top ({ r, g, b, a })
local function band(out, r, y0, y1, tiles, v0, v1, c0, c1, segs)
  segs = segs or M.SEGS
  for i = 0, segs - 1 do
    local a0, a1 = 2 * pi * i / segs, 2 * pi * (i + 1) / segs
    local u0, u1 = tiles * i / segs, tiles * (i + 1) / segs
    local x0, z0, x1, z1 = r * cos(a0), r * sin(a0), r * cos(a1), r * sin(a1)
    quad(out,
      { x0, y0, z0, u0, 1 - v0, 0, 1, 0, c0[1], c0[2], c0[3], c0[4] },
      { x1, y0, z1, u1, 1 - v0, 0, 1, 0, c0[1], c0[2], c0[3], c0[4] },
      { x1, y1, z1, u1, 1 - v1, 0, 1, 0, c1[1], c1[2], c1[3], c1[4] },
      { x0, y1, z0, u0, 1 - v1, 0, 1, 0, c1[1], c1[2], c1[3], c1[4] })
  end
end

return function(St, R, Assets)
  local lib = R.g3d()
  local pieces = {}
  local function add(verts, img, pass, name, anim)
    pieces[#pieces + 1] = { model = lib.newModel(verts, img), pass = pass, name = name, anim = anim,
      uv = anim and { 0, 0 } or nil }
  end
  local function art(id)
    local img = Assets and Assets.image and Assets.image(id) or nil
    if img then img:setWrap("repeat", "repeat"); img:setFilter("linear", "linear") end
    return img
  end

  -- the lawn: a disc, then the lip rising round it
  do
    local img = lawn()
    img:setWrap("repeat", "repeat")
    local v = {}
    local k = M.FLOOR_UV / M.FLOOR_R
    local W = { 1, 1, 1, 1 }
    for i = 0, M.SEGS - 1 do
      local a0, a1 = 2 * pi * i / M.SEGS, 2 * pi * (i + 1) / M.SEGS
      local x0, z0 = M.FLOOR_R * cos(a0), M.FLOOR_R * sin(a0)
      local x1, z1 = M.FLOOR_R * cos(a1), M.FLOOR_R * sin(a1)
      vert(v, 0, 0, 0, 0.5, 0.5, 1, 1, 1, 1)
      vert(v, x0, 0, z0, 0.5 + x0 * k, 0.5 + z0 * k, 1, 1, 1, 1)
      vert(v, x1, 0, z1, 0.5 + x1 * k, 0.5 + z1 * k, 1, 1, 1, 1)
      local X0, Z0 = M.LIP_R * cos(a0), M.LIP_R * sin(a0)
      local X1, Z1 = M.LIP_R * cos(a1), M.LIP_R * sin(a1)
      local L = M.LIP_RGB
      quad(v,
        { x0, 0, z0, 0.5 + x0 * k, 0.5 + z0 * k, 0, 1, 0, W[1], W[2], W[3], 1 },
        { x1, 0, z1, 0.5 + x1 * k, 0.5 + z1 * k, 0, 1, 0, W[1], W[2], W[3], 1 },
        { X1, M.LIP_Y, Z1, 0.5 + X1 * k, 0.5 + Z1 * k, 0, 1, 0, L[1], L[2], L[3], 1 },
        { X0, M.LIP_Y, Z0, 0.5 + X0 * k, 0.5 + Z0 * k, 0, 1, 0, L[1], L[2], L[3], 1 })
    end
    add(v, img, 2, "floor")
  end

  -- the sky cylinder, row by row of its colour
  do
    local img = dots()
    img:setWrap("repeat", "repeat")
    local v = {}
    for i = 1, #M.SKY - 1 do
      local a, b = M.SKY[i], M.SKY[i + 1]
      band(v, M.SKY_R, a[1], b[1], M.SKY_TILES_U, a[1] / M.SKY_TILE_Y, b[1] / M.SKY_TILE_Y,
        { a[2], a[3], a[4], a[5] }, { b[2], b[3], b[4], b[5] })
    end
    add(v, img, 3, "sky")
  end

  -- the rainbow in the quad's upper half, as the card's (its v runs -1..1; past the picture's
  -- edge nothing)
  do
    local img = rainbow()
    pcall(img.setWrap, img, "clampzero", "clampzero")
    local B = M.RAINBOW
    local v = {}
    quad(v,
      { B.x0, B.y0, B.z0, 0, 2, 0, 1, 0, 1, 1, 1, 1 }, { B.x1, B.y0, B.z1, 1, 2, 0, 1, 0, 1, 1, 1, 1 },
      { B.x1, B.y1, B.z1, 1, 0, 0, 1, 0, 1, 1, 1, 1 }, { B.x0, B.y1, B.z0, 0, 0, 0, 1, 0, 1, 1, 1, 1 })
    add(v, img, 3, "rainbow")
  end

  -- the cumulus ring along the foot, swaying
  do
    local C = M.CUMULUS
    local img = art("scene/cumulus") or puffs(1)
    local v = {}
    band(v, C.r, C.y0, C.y1, C.tiles, 0, 1, { C.foot[1], C.foot[2], C.foot[3], 1 }, { 1, 1, 1, 1 })
    add(v, img, 3, "cumulus", "sway")
  end

  -- the small clouds, drifting
  do
    local C = M.CLOUDS
    local img = art("scene/cloud") or puffs(2)
    local v = {}
    for _, b in ipairs(C.bands) do
      local c = { b[3], b[4], b[5], b[6] }
      band(v, C.r, b[1], b[2], C.tiles, 0, 1, c, c)
    end
    add(v, img, 3, "clouds", "drift")
  end

  -- the bubbles, rising
  do
    local B = M.BUBBLES
    local img = bubbles()
    img:setWrap("repeat", "repeat")
    local v = {}
    local span = B.y1 - B.y0
    local vf = (B.fade - B.y0) / span * B.tiles_v
    band(v, B.r, B.y0, B.fade, B.tiles_u, 0, vf, { 1, 1, 1, 0 }, { 1, 1, 1, B.alpha })
    band(v, B.r, B.fade, B.y1, B.tiles_u, vf, B.tiles_v, { 1, 1, 1, B.alpha }, { 1, 1, 1, B.topAlpha })
    add(v, img, 3, "bubbles", "rise")
  end

  return { clear = St.CLEAR, pieces = pieces, standIn = true }
end
