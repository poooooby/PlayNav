-- The drawn stand-in stadium for 3D SUPER TRAINING when the card's model is not extracted
-- (fallback assets), built to the card's stadium's measure (a/1/1/4 e75, model units, the
-- pitch's middle the origin): the grass, the lined pitch (x +-274, z +-511), a round stand -
-- its front wall from r 840, the seats full of a dotted crowd rising back to r 1150 - under the
-- roof's ring (r 880..1166), the sky's dome, and the eight Poke Ball emblems on their ring
-- (r 886, y 401) - the one over the far end shows above the balloon. Its textures are drawn by
-- the engine into canvases once.
--
-- Stand(A3, g3d) -> { clear = { r, g, b }, pieces = { { model, pass = 1 sky | 2 solid | 3 see-through } } }

local G = love.graphics

local S = {
  GROUND = { y = -14, r = 1700 },
  PITCH = { x = 274, z = 511, y = -6.7 },
  STAND = { r0 = 840, wall = 70, r1 = 1150, top = 300 },
  ROOF = { r0 = 880, r1 = 1166, y0 = 276, y1 = 364 },
  BALL = { r = 886, y = 401, w = 47, h = 31 },
  SKY = { r = 1686 },
  SEGS = 64,
}

local function texture(w, h, draw)
  local c = G.newCanvas(w, h, { dpiscale = 1 })
  G.push("all")
  G.setCanvas(c)
  G.origin()
  G.setScissor()
  G.setShader()
  G.setBlendMode("alpha")
  G.clear(0, 0, 0, 0)
  draw(w, h)
  G.pop()
  c:setWrap("repeat", "repeat")
  c:setFilter("linear", "linear")
  return c
end

local function rand(seed)
  local s = seed
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 2147483648
  end
end

local TEX = {}
local function textures()
  if TEX.grass then return TEX end
  TEX.grass = texture(64, 64, function(w, h)
    G.setColor(0.24, 0.55, 0.25, 1); G.rectangle("fill", 0, 0, w, h)
    G.setColor(0.28, 0.62, 0.28, 1); G.rectangle("fill", 0, 0, w, h / 2)
    local r = rand(7)
    for _ = 1, 120 do
      G.setColor(0.2 + 0.1 * r(), 0.5 + 0.15 * r(), 0.22, 0.5)
      G.rectangle("fill", r() * w, r() * h, 1, 2)
    end
  end)
  -- the pitch: mown stripes, a white border, halfway line and circle, a box at each end
  TEX.pitch = texture(256, 512, function(w, h)
    for i = 0, 15 do
      if i % 2 == 0 then G.setColor(0.33, 0.68, 0.3, 1) else G.setColor(0.28, 0.6, 0.27, 1) end
      G.rectangle("fill", 0, i * h / 16, w, h / 16)
    end
    G.setColor(1, 1, 1, 0.92)
    G.setLineWidth(4)
    G.rectangle("line", 6, 6, w - 12, h - 12)
    G.line(6, h / 2, w - 6, h / 2)
    G.circle("line", w / 2, h / 2, 34, 48)
    G.rectangle("line", w / 2 - 60, 6, 120, 52)
    G.rectangle("line", w / 2 - 60, h - 58, 120, 52)
  end)
  TEX.crowd = texture(256, 128, function(w, h)
    G.setColor(0.2, 0.24, 0.32, 1); G.rectangle("fill", 0, 0, w, h)
    local r = rand(11)
    local COLS = { { 0.95, 0.3, 0.3 }, { 0.3, 0.6, 0.95 }, { 0.98, 0.85, 0.3 }, { 0.95, 0.95, 0.95 },
      { 0.4, 0.85, 0.5 }, { 0.95, 0.55, 0.2 }, { 0.75, 0.45, 0.9 } }
    for row = 0, 15 do
      local y = row * h / 16
      G.setColor(0.32, 0.36, 0.46, 1); G.rectangle("fill", 0, y + h / 16 - 2, w, 2)
      for x = 2, w, 5 do
        if r() < 0.82 then
          local c = COLS[1 + math.floor(r() * #COLS)]
          G.setColor(c[1] * (0.8 + 0.2 * r()), c[2] * (0.8 + 0.2 * r()), c[3] * (0.8 + 0.2 * r()), 1)
          G.circle("fill", x + r(), y + 3 + r() * 2, 2, 6)
        end
      end
    end
  end)
  TEX.wall = texture(64, 32, function(w, h)
    G.setColor(0.12, 0.45, 0.5, 1); G.rectangle("fill", 0, 0, w, h)
    G.setColor(0.6, 0.92, 0.88, 1); G.rectangle("fill", 0, h * 0.15, w, h * 0.15)
    G.setColor(0.95, 0.35, 0.4, 1); G.rectangle("fill", 0, h * 0.7, w, h * 0.12)
  end)
  TEX.roof = texture(64, 32, function(w, h)
    G.setColor(0.86, 0.88, 0.9, 1); G.rectangle("fill", 0, 0, w, h)
    G.setColor(0.65, 0.68, 0.72, 1); G.rectangle("fill", 0, h * 0.75, w, h * 0.25)
  end)
  TEX.sky = texture(256, 256, function(w, h)
    for y = 0, h - 1 do
      local t = y / (h - 1)
      G.setColor(0.25 + 0.5 * t, 0.5 + 0.38 * t, 0.9 + 0.08 * t, 1)
      G.rectangle("fill", 0, y, w, 1)
    end
    local r = rand(3)
    for _ = 1, 14 do
      local cx, cy, cr = r() * w, h * (0.45 + 0.4 * r()), 10 + 16 * r()
      for k = 0, 3 do
        G.setColor(1, 1, 1, 0.16)
        G.circle("fill", cx + (k - 1.5) * cr * 0.7, cy + math.sin(k) * 3, cr * (0.8 + 0.2 * (k % 2)), 20)
      end
    end
  end)
  -- the Poke Ball emblem
  TEX.ball = texture(64, 64, function(w, h)
    G.setColor(0.1, 0.1, 0.12, 1); G.circle("fill", 32, 32, 31, 48)
    G.setColor(0.92, 0.2, 0.22, 1); G.arc("fill", 32, 32, 28, math.pi, 2 * math.pi, 32)
    G.setColor(0.97, 0.97, 0.97, 1); G.arc("fill", 32, 32, 28, 0, math.pi, 32)
    G.setColor(0.1, 0.1, 0.12, 1); G.rectangle("fill", 4, 29, 56, 6); G.circle("fill", 32, 32, 10, 24)
    G.setColor(0.97, 0.97, 0.97, 1); G.circle("fill", 32, 32, 6, 20)
  end)
  return TEX
end

local function vert(t, x, y, z, u, v, shade)
  local s = shade or 1
  t[#t + 1] = { x, y, z, u, v, 0, 1, 0, s, s, s, 1 }
end
local function quad(t, a, b, c, d, shade)
  vert(t, a[1], a[2], a[3], a[4], a[5], shade); vert(t, b[1], b[2], b[3], b[4], b[5], shade); vert(t, c[1], c[2], c[3], c[4], c[5], shade)
  vert(t, a[1], a[2], a[3], a[4], a[5], shade); vert(t, c[1], c[2], c[3], c[4], c[5], shade); vert(t, d[1], d[2], d[3], d[4], d[5], shade)
end
-- a point of a ring of radius r at angle a (radians, 0 = +z), height y
local function ring(a, r, y) return math.sin(a) * r, y, math.cos(a) * r end

return function(A3, g3d)
  local T = textures()
  local pieces = {}
  local function add(verts, tex, pass)
    pieces[#pieces + 1] = { model = g3d.newModel(verts, tex), pass = pass }
  end
  local n = S.SEGS

  -- the sky: a dome (drawn first, with no depth)
  do
    local v = {}
    local R = S.SKY.r
    for i = 0, n - 1 do
      local a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
      local u0, u1 = i / n * 3, (i + 1) / n * 3
      for b = 0, 7 do
        local e0, e1 = b / 8 * math.pi / 2, (b + 1) / 8 * math.pi / 2
        local x00, y00, z00 = ring(a0, R * math.cos(e0), R * math.sin(e0) - 100)
        local x10, y10, z10 = ring(a1, R * math.cos(e0), R * math.sin(e0) - 100)
        local x11, y11, z11 = ring(a1, R * math.cos(e1), R * math.sin(e1) - 100)
        local x01, y01, z01 = ring(a0, R * math.cos(e1), R * math.sin(e1) - 100)
        quad(v, { x00, y00, z00, u0, 1 - b / 8 }, { x10, y10, z10, u1, 1 - b / 8 },
          { x11, y11, z11, u1, 1 - (b + 1) / 8 }, { x01, y01, z01, u0, 1 - (b + 1) / 8 })
      end
    end
    add(v, T.sky, 1)
  end

  -- the grass and the pitch
  do
    local v, gr, gy = {}, S.GROUND.r, S.GROUND.y
    quad(v, { -gr, gy, gr, -gr / 64, gr / 64 }, { gr, gy, gr, gr / 64, gr / 64 }, { gr, gy, -gr, gr / 64, -gr / 64 }, { -gr, gy, -gr, -gr / 64, -gr / 64 })
    add(v, T.grass, 2)
    local P, p = S.PITCH, {}
    quad(p, { -P.x, P.y, P.z, 0, 1 }, { P.x, P.y, P.z, 1, 1 }, { P.x, P.y, -P.z, 1, 0 }, { -P.x, P.y, -P.z, 0, 0 })
    add(p, T.pitch, 2)
  end

  -- the stand: its front wall, the seats rising back, the roof's ring, and the Poke Balls
  do
    local St, Ro = S.STAND, S.ROOF
    local seats, wall, roof, balls = {}, {}, {}, {}
    for i = 0, n - 1 do
      local a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
      local u0, u1 = i / n * 24, (i + 1) / n * 24
      local w0x, w0y, w0z = ring(a0, St.r0, S.GROUND.y)
      local w1x, w1y, w1z = ring(a1, St.r0, S.GROUND.y)
      local t0x, t0y, t0z = ring(a0, St.r0, St.wall)
      local t1x, t1y, t1z = ring(a1, St.r0, St.wall)
      quad(wall, { w0x, w0y, w0z, u0, 1 }, { w1x, w1y, w1z, u1, 1 }, { t1x, t1y, t1z, u1, 0 }, { t0x, t0y, t0z, u0, 0 }, 0.85)
      local b0x, b0y, b0z = ring(a0, St.r1, St.top)
      local b1x, b1y, b1z = ring(a1, St.r1, St.top)
      quad(seats, { t0x, t0y, t0z, u0, 1 }, { t1x, t1y, t1z, u1, 1 }, { b1x, b1y, b1z, u1, 0 }, { b0x, b0y, b0z, u0, 0 })
      -- the roof: a ring from above the back row out over the seats, and its face
      local r0x, r0y, r0z = ring(a0, Ro.r1, Ro.y1)
      local r1x, r1y, r1z = ring(a1, Ro.r1, Ro.y1)
      local f0x, f0y, f0z = ring(a0, Ro.r0, Ro.y1)
      local f1x, f1y, f1z = ring(a1, Ro.r0, Ro.y1)
      local g0x, g0y, g0z = ring(a0, Ro.r0, Ro.y0)
      local g1x, g1y, g1z = ring(a1, Ro.r0, Ro.y0)
      quad(roof, { r0x, r0y, r0z, u0, 0 }, { r1x, r1y, r1z, u1, 0 }, { f1x, f1y, f1z, u1, 1 }, { f0x, f0y, f0z, u0, 1 }, 0.95)
      quad(roof, { f0x, f0y, f0z, u0, 0 }, { f1x, f1y, f1z, u1, 0 }, { g1x, g1y, g1z, u1, 1 }, { g0x, g0y, g0z, u0, 1 }, 0.8)
      -- the back wall up to the roof
      quad(roof, { b0x, b0y, b0z, u0, 1 }, { b1x, b1y, b1z, u1, 1 }, { r1x, r1y, r1z, u1, 0 }, { r0x, r0y, r0z, u0, 0 }, 0.7)
    end
    for k = 0, 7 do
      local a = math.pi + k * math.pi / 4
      local cx, cy, cz = ring(a, S.BALL.r, S.BALL.y)
      -- facing the middle: its right is the ring's tangent
      local tx, tz = math.cos(a), -math.sin(a)
      local B = S.BALL
      quad(balls, { cx - tx * B.w, cy - B.h, cz - tz * B.w, 0, 1 }, { cx + tx * B.w, cy - B.h, cz + tz * B.w, 1, 1 },
        { cx + tx * B.w, cy + B.h, cz + tz * B.w, 1, 0 }, { cx - tx * B.w, cy + B.h, cz - tz * B.w, 0, 0 })
    end
    add(seats, T.crowd, 2)
    add(wall, T.wall, 2)
    add(roof, T.roof, 2)
    add(balls, T.ball, 2)
  end

  return { clear = { 0.55, 0.78, 0.97 }, pieces = pieces }
end
