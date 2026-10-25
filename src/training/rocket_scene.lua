-- The Konami code's alley (src/training/rocket.lua) on the touch screen: a dark, wet alley built
-- here in 3D (no card art: brick walls with a few windows, a drainpipe, a bin and crates, wet
-- asphalt with puddles, a street lamp throwing a cone of light, a skyline and a night sky at the
-- far end). The camera walks in from the alley's mouth toward the lamp with a head bob and stops;
-- the dealer (assets/r-deal.png) is drawn under the lamp as a sprite, the rain over everything.
--
-- Drawn by src/render3d.lua: Al.prepare renders the picture from the training layer's update
-- (outside the engine's draw) and Al.draw only places it. Without a 3D device the same camera
-- paints a flat version (Al.drawFlat).
--   Al = rocket_scene(mod, { Render3d })

return function(mod, deps)
  local Al = { failed = false, why = nil }
  local sqrt, sin, cos, tan, rad, pi, floor = math.sqrt, math.sin, math.cos, math.tan, math.rad, math.pi, math.floor
  local min, max = math.min, math.max

  -- the alley, in metres (y up, the camera looking down -z)
  --   W         the walls' x (either side); Z0 / Z1 their ends; H their height
  --   LAMP      the post's foot, the bulb under the hood, the pool of light on the ground
  --   DEALER    where he stands (his feet), his height
  --   WALK      the eye from / to, the time it takes, the stride (a step a stride), the bob
  --   LOOK      where the eye looks at the start / once there
  Al.W, Al.Z0, Al.Z1, Al.H = 2.4, 6, -30, 11
  --   NEON      a sign on the right wall (pink, flickering)
  Al.LAMP = { x = -1.95, z = -16, top = 3.35, bx = -1.25, by = 3.05, poolX = -1.05, poolR = 1.9 }
  Al.DEALER = { x = -0.95, z = -15.4, h = 1.85 }
  Al.NEON = { z0 = -22.4, z1 = -20.6, y0 = 3.1, y1 = 3.5 }
  Al.WALK = { from = { 0.35, 1.62, 4 }, to = { 0.3, 1.6, -10.9 }, S = 4.6, STRIDE = 0.78, BOB = 0.045, SWAY = 0.025 }
  Al.LOOK = { from = { 0, 1.5, -26 }, to = { -0.7, 1.55, -15.8 } }
  Al.FOVY = 52
  Al.NEAR, Al.FAR = 0.05, 200
  Al.CLEAR = { 0.03, 0.035, 0.07 }

  -- ------- the camera (g3d's row layout, a focal length and a centre in the draw's units)

  local cam = { m = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }, F = 200, CX = 128, CY = 96 }
  local eye = { 0, 1.6, 4 }
  Al.cam, Al.eye = cam, eye

  local function lookAt(c, ex, ey, ez, tx, ty, tz, roll)
    local zx, zy, zz = ex - tx, ey - ty, ez - tz
    local l = sqrt(zx * zx + zy * zy + zz * zz)
    zx, zy, zz = zx / l, zy / l, zz / l
    local xx, xy, xz = zz, 0, -zx
    l = sqrt(xx * xx + xz * xz)
    xx, xz = xx / l, xz / l
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
    if roll and roll ~= 0 then
      local c1, s1 = cos(roll), sin(roll)
      xx, xy, xz, yx, yy, yz = xx * c1 + yx * s1, xy * c1 + yy * s1, xz * c1 + yz * s1,
        yx * c1 - xx * s1, yy * c1 - xy * s1, yz * c1 - xz * s1
    end
    local m = c.m
    m[1], m[2], m[3], m[4] = xx, xy, xz, -(xx * ex + xy * ey + xz * ez)
    m[5], m[6], m[7], m[8] = yx, yy, yz, -(yx * ex + yy * ey + yz * ez)
    m[9], m[10], m[11], m[12] = zx, zy, zz, -(zx * ex + zy * ey + zz * ez)
  end

  -- a point of the alley -> screen x, y (the draw's units) and its distance in front of the eye
  local function project(X, Y, Z)
    local m = cam.m
    local vx = m[1] * X + m[2] * Y + m[3] * Z + m[4]
    local vy = m[5] * X + m[6] * Y + m[7] * Z + m[8]
    local d = -(m[9] * X + m[10] * Y + m[11] * Z + m[12])
    if d < 1e-3 then return nil, nil, d end
    return cam.CX + vx * cam.F / d, cam.CY - vy * cam.F / d, d
  end
  Al.project = project

  local function viewMatrix(out)
    local m = cam.m
    for i = 1, 12 do out[i] = m[i] end
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
  end
  local function projectionMatrix(out, ex, ey, ew, eh)
    local n, f = Al.NEAR, Al.FAR
    local l, r = (ex - cam.CX) / cam.F * n, (ex + ew - cam.CX) / cam.F * n
    local t, b = (cam.CY - ey) / cam.F * n, (cam.CY - (ey + eh)) / cam.F * n
    out[1], out[2], out[3], out[4] = 2 * n / (r - l), 0, (r + l) / (r - l), 0
    out[5], out[6], out[7], out[8] = 0, 2 * n / (t - b), (t + b) / (t - b), 0
    out[9], out[10], out[11], out[12] = 0, 0, -(f + n) / (f - n), -2 * f * n / (f - n)
    out[13], out[14], out[15], out[16] = 0, 0, -1, 0
    return out
  end

  -- the walk: u 0..1 eased out (a stride slows to a stop); the bob follows the strides taken
  local walkT = 0
  function Al.reset() walkT = 0 end
  function Al.setWalk(t) walkT = max(0, t or 0) end
  function Al.walkU()
    local u = min(1, walkT / Al.WALK.S)
    return 1 - (1 - u) ^ 3
  end
  -- metres walked so far (the footsteps: one a stride)
  function Al.walked()
    local a, b = Al.WALK.from, Al.WALK.to
    return math.abs(b[3] - a[3]) * Al.walkU()
  end

  -- the eye and look-at for the walk now, fitted to the rect (draw units) the picture fills
  local rect = { 0, 0, 256, 192 }
  local function place()
    local W, L = Al.WALK, Al.LOOK
    local u = Al.walkU()
    local ex = W.from[1] + (W.to[1] - W.from[1]) * u
    local ey = W.from[2] + (W.to[2] - W.from[2]) * u
    local ez = W.from[3] + (W.to[3] - W.from[3]) * u
    -- the head bobs with each stride and sways with every other, dying away as the walk stops
    local phase = Al.walked() / W.STRIDE * pi
    local live = 1 - u ^ 4
    ey = ey + W.BOB * math.abs(sin(phase)) * live
    ex = ex + W.SWAY * sin(phase / 2) * live
    local k = u * u * (3 - 2 * u)
    local tx = L.from[1] + (L.to[1] - L.from[1]) * k
    local ty = L.from[2] + (L.to[2] - L.from[2]) * k
    local tz = L.from[3] + (L.to[3] - L.from[3]) * k
    eye[1], eye[2], eye[3] = ex, ey, ez
    lookAt(cam, ex, ey, ez, tx, ty, tz, 0.008 * sin(phase / 2) * live)
    local ew, eh = rect[3], rect[4]
    cam.F = (eh / 2) / tan(rad(Al.FOVY) / 2)
    cam.CX, cam.CY = rect[1] + ew / 2, rect[2] + eh / 2
  end
  Al.place = place
  function Al.setRect(ex, ey, ew, eh) rect[1], rect[2], rect[3], rect[4] = ex, ey, ew, eh end

  -- ------- the light: the lamp's warm pool and a little cold sky from the far end

  -- the light falls off steeply (a tight pool, black between); the neon tints the far right;
  -- grime: every vertex a little darker or lighter than the next
  local LIGHT = { amb = { 0.03, 0.03, 0.055 }, lamp = { 1.0, 0.7, 0.36 }, reach = 1.9, power = 2.8, fall = 1.7,
    sky = { 0.03, 0.04, 0.08 }, neon = { 1.3, 0.16, 0.72 }, neonReach = 2.4 }
  Al.LIGHT = LIGHT
  local function grime(x, y, z)
    local h = (sin(x * 31.7 + y * 17.3 + z * 7.1) * 43758.5453) % 1
    return 0.62 + 0.45 * h
  end
  local function lit(x, y, z, r, g, b)
    local L = Al.LAMP
    local dx, dy, dz = x - L.bx, (y - L.by) * 0.6, z - L.z
    local i = LIGHT.power / (1 + (dx * dx + dy * dy + dz * dz) / (LIGHT.reach * LIGHT.reach)) ^ LIGHT.fall
    local Ne = Al.NEON
    local nz = z - (Ne.z0 + Ne.z1) / 2
    local nd = ((x - Al.W) ^ 2 + (y - (Ne.y0 + Ne.y1) / 2) ^ 2 + nz * nz) / (LIGHT.neonReach * LIGHT.neonReach)
    local n = 0.9 / (1 + nd) ^ 1.6
    local far = min(1, max(0, (-z - 20) / 10))
    local g0 = grime(x, y, z)
    local cr = (LIGHT.amb[1] + LIGHT.lamp[1] * i + LIGHT.neon[1] * n + LIGHT.sky[1] * far) * g0
    local cg = (LIGHT.amb[2] + LIGHT.lamp[2] * i + LIGHT.neon[2] * n + LIGHT.sky[2] * far) * g0
    local cb = (LIGHT.amb[3] + LIGHT.lamp[3] * i + LIGHT.neon[3] * n + LIGHT.sky[3] * far) * g0
    return min(1, r * cr), min(1, g * cg), min(1, b * cb)
  end
  Al.lit = lit
  -- the lamp's flicker at time t: mostly steady, now and then a stutter (1 = full)
  function Al.flicker(t)
    t = t or 0
    local k = floor(t * 9)
    local h = (sin(k * 12.9898) * 43758.5453) % 1
    if h > 0.93 then return 0.45 end
    if h > 0.88 then return 0.75 end
    return 1
  end

  -- ------- pictures, drawn once into canvases (in the update step) and read back

  local function hash(i, k) return (sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end
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
    img:setWrap("repeat", "repeat")
    return img
  end
  Al.picture = picture

  -- brick: 16 courses of 7, every other half a brick over, each brick its own shade, soot and
  -- damp blotches over them, the mortar dark
  local function brick()
    return picture(128, 128, function(G, w, h)
      G.setColor(0.16, 0.14, 0.13, 1)
      G.rectangle("fill", 0, 0, w, h)
      local rows, cols = 16, 7
      local bh, bw = h / rows, w / cols
      for r = 0, rows - 1 do
        local off = (r % 2) * bw / 2
        for c = -1, cols do
          local i = r * 11 + c
          local t = hash(i, 1)
          G.setColor(0.42 + 0.16 * t, 0.2 + 0.08 * t, 0.15 + 0.05 * hash(i, 2), 1)
          G.rectangle("fill", c * bw + off + 0.8, r * bh + 0.8, bw - 1.6, bh - 1.6)
          G.setColor(1, 1, 1, 0.06)
          G.rectangle("fill", c * bw + off + 0.8, r * bh + 0.8, bw - 1.6, 1)
        end
      end
      for i = 1, 26 do
        G.setColor(0, 0, 0, 0.1 + 0.12 * hash(i, 3))
        local x, y, rr = w * hash(i, 4), h * hash(i, 5), 4 + 14 * hash(i, 6)
        for dx = -1, 1 do for dy = -1, 1 do G.circle("fill", x + dx * w, y + dy * h, rr, 20) end end
      end
      -- damp running down, soot in streaks, a few chipped bricks
      for i = 1, 14 do
        local x = w * hash(i, 30)
        G.setColor(0, 0, 0, 0.18 + 0.15 * hash(i, 31))
        G.rectangle("fill", x, 0, 1.5 + 4 * hash(i, 32), h)
      end
      for i = 1, 8 do
        G.setColor(0.55, 0.5, 0.45, 0.25)
        G.rectangle("fill", w * hash(i, 33), h * hash(i, 34), 4 + 6 * hash(i, 35), 3)
      end
    end)
  end

  -- graffiti: a few spray tags and drips, on clear ground (a decal)
  local function graffiti()
    return picture(256, 128, function(G, w, h)
      local cols = { { 0.75, 0.15, 0.55 }, { 0.2, 0.65, 0.75 }, { 0.85, 0.8, 0.25 }, { 0.92, 0.92, 0.95 } }
      G.setLineJoin("bevel")
      for t = 1, 5 do
        local c = cols[1 + (t - 1) % #cols]
        local x0, y0 = 20 + 200 * hash(t, 40), 30 + 60 * hash(t, 41)
        local pts = {}
        for k = 0, 9 do
          pts[#pts + 1] = x0 + k * (5 + 4 * hash(t * 10 + k, 42))
          pts[#pts + 1] = y0 + 18 * sin(k * 1.7 + t) * hash(t * 10 + k, 43)
        end
        G.setColor(c[1], c[2], c[3], 0.85)
        G.setLineWidth(3 + 3 * hash(t, 44))
        G.line(pts)
        -- drips
        for k = 1, 3 do
          local dx = pts[1 + 2 * floor(9 * hash(t * 7 + k, 45))]
          G.setLineWidth(1.2)
          G.line(dx, y0 + 8, dx, y0 + 14 + 22 * hash(t * 7 + k, 46))
        end
      end
    end)
  end

  -- a soft vertical streak (the lamp's reflection on the wet ground): bright down its middle
  local function streak()
    return picture(32, 64, function(G, w, h)
      for i = 1, 16 do
        local k = i / 16
        G.setColor(1, 1, 1, 0.07)
        G.rectangle("fill", w / 2 - w / 2 * k, 0, w * k, h)
      end
    end)
  end

  -- wet asphalt: dark grain, a few cracks
  local function asphalt()
    return picture(128, 128, function(G, w, h)
      G.setColor(0.2, 0.2, 0.22, 1)
      G.rectangle("fill", 0, 0, w, h)
      for i = 1, 500 do
        local t = hash(i, 7)
        G.setColor(0.12 + 0.2 * t, 0.12 + 0.2 * t, 0.14 + 0.2 * t, 0.5)
        G.rectangle("fill", w * hash(i, 8), h * hash(i, 9), 1.5, 1.5)
      end
      G.setColor(0.07, 0.07, 0.08, 0.8)
      G.setLineWidth(1)
      G.line(10, 20, 30, 34, 36, 60, 60, 66)
      G.line(80, 90, 98, 96, 120, 118)
    end)
  end

  -- a puddle: a soft-edged pool, lighter streaks across it
  local function puddle()
    return picture(64, 64, function(G, w, h)
      for i = 14, 1, -1 do
        G.setColor(0.6, 0.66, 0.78, 0.06)
        G.ellipse("fill", w / 2, h / 2, 2 + i * 2.1, 1.6 + i * 2, 32)
      end
      G.setColor(1, 1, 1, 0.25)
      G.rectangle("fill", 18, 28, 26, 1.5)
      G.rectangle("fill", 24, 34, 14, 1)
    end)
  end

  -- a window: a frame and four panes (the colour is the vertex colour's: lit or dark)
  local function window()
    return picture(32, 48, function(G, w, h)
      G.setColor(0.25, 0.25, 0.27, 1)
      G.rectangle("fill", 0, 0, w, h)
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", 3, 3, w / 2 - 4.5, h / 2 - 4.5)
      G.rectangle("fill", w / 2 + 1.5, 3, w / 2 - 4.5, h / 2 - 4.5)
      G.rectangle("fill", 3, h / 2 + 1.5, w / 2 - 4.5, h / 2 - 4.5)
      G.rectangle("fill", w / 2 + 1.5, h / 2 + 1.5, w / 2 - 4.5, h / 2 - 4.5)
    end)
  end

  -- the skyline: block silhouettes along the bottom, a few lit windows, clear above
  local function skyline()
    return picture(256, 128, function(G, w, h)
      local x = 0
      local i = 0
      while x < w do
        i = i + 1
        local bw = 18 + 30 * hash(i, 10)
        local top = h * (0.15 + 0.5 * hash(i, 11))
        G.setColor(0.05, 0.05, 0.08, 1)
        G.rectangle("fill", x, top, bw + 1, h - top)
        for wy = top + 5, h - 6, 7 do
          for wx = x + 3, x + bw - 5, 6 do
            if hash(wx * 3 + wy, 12) > 0.82 then
              G.setColor(0.95, 0.78, 0.4, 1)
              G.rectangle("fill", wx, wy, 2.5, 3)
            end
          end
        end
        x = x + bw
      end
    end)
  end

  local function white()
    return picture(4, 4, function(G, w, h) G.setColor(1, 1, 1, 1); G.rectangle("fill", 0, 0, w, h) end)
  end

  -- ------- geometry (g3d's triangles: x, y, z, u, v, nx, ny, nz, r, g, b, a)

  local function vtx(x, y, z, u, v, r, g, b, a) return { x, y, z, u, v, 0, 1, 0, r, g, b, a or 1 } end
  local function quad(out, a, b, c, d)
    out[#out + 1] = a; out[#out + 1] = b; out[#out + 1] = c
    out[#out + 1] = a; out[#out + 1] = c; out[#out + 1] = d
  end
  -- a lit vertex: its colour from the light where it stands
  local function lv(x, y, z, u, v, r, g, b, a)
    local cr, cg, cb = lit(x, y, z, r, g, b)
    return vtx(x, y, z, u, v, cr, cg, cb, a)
  end

  -- a wall at x (facing the middle), in cells of `cell` metres, its texture `tu` x `tv` metres
  local function wall(out, x, cell, tu, tv)
    for z = Al.Z1, Al.Z0 - cell, cell do
      for y = 0, Al.H - cell, cell do
        local z1, y1 = z + cell, y + cell
        quad(out,
          lv(x, y, z, z / tu, y / tv, 1, 1, 1), lv(x, y, z1, z1 / tu, y / tv, 1, 1, 1),
          lv(x, y1, z1, z1 / tu, y1 / tv, 1, 1, 1), lv(x, y1, z, z / tu, y1 / tv, 1, 1, 1))
      end
    end
  end

  -- an upright rect on a wall at x (z from z0 to z1, y from y0 to y1)
  local function onWall(out, x, z0, z1, y0, y1, r, g, b, glow)
    local function c(xx, yy, zz)
      if glow then return r, g, b end
      return lit(xx, yy, zz, r, g, b)
    end
    local r1, g1, b1 = c(x, y0, z0)
    local r2, g2, b2 = c(x, y0, z1)
    local r3, g3, b3 = c(x, y1, z1)
    local r4, g4, b4 = c(x, y1, z0)
    quad(out, vtx(x, y0, z0, 0, 1, r1, g1, b1), vtx(x, y0, z1, 1, 1, r2, g2, b2),
      vtx(x, y1, z1, 1, 0, r3, g3, b3), vtx(x, y1, z0, 0, 0, r4, g4, b4))
  end

  -- a box (x0..x1, y0..y1, z0..z1), lit, every side but the floor
  local function box(out, x0, x1, y0, y1, z0, z1, r, g, b, glow)
    local function V(x, y, z, u, v)
      if glow then return vtx(x, y, z, u, v, r, g, b, type(glow) == "number" and glow or 1) end
      return lv(x, y, z, u, v, r, g, b)
    end
    quad(out, V(x0, y0, z1, 0, 1), V(x1, y0, z1, 1, 1), V(x1, y1, z1, 1, 0), V(x0, y1, z1, 0, 0))   -- front
    quad(out, V(x1, y0, z0, 0, 1), V(x0, y0, z0, 1, 1), V(x0, y1, z0, 1, 0), V(x1, y1, z0, 0, 0))   -- back
    quad(out, V(x0, y0, z0, 0, 1), V(x0, y0, z1, 1, 1), V(x0, y1, z1, 1, 0), V(x0, y1, z0, 0, 0))   -- left
    quad(out, V(x1, y0, z1, 0, 1), V(x1, y0, z0, 1, 1), V(x1, y1, z0, 1, 0), V(x1, y1, z1, 0, 0))   -- right
    quad(out, V(x0, y1, z1, 0, 1), V(x1, y1, z1, 1, 1), V(x1, y1, z0, 1, 0), V(x0, y1, z0, 0, 0))   -- top
  end

  -- a flat ellipse on the ground (a puddle, a manhole)
  local function disc(out, cx, cz, rx, rz, y, r, g, b, a, glow)
    local n = 20
    for i = 0, n - 1 do
      local a0, a1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
      local x0, z0 = cx + rx * cos(a0), cz + rz * sin(a0)
      local x1, z1 = cx + rx * cos(a1), cz + rz * sin(a1)
      local function V(x, z, u, v)
        if glow then return vtx(x, y, z, u, v, r, g, b, a) end
        local cr, cg, cb = lit(x, 0.3, z, r, g, b)
        return vtx(x, y, z, u, v, cr, cg, cb, a)
      end
      out[#out + 1] = V(cx, cz, 0.5, 0.5)
      out[#out + 1] = V(x0, z0, 0.5 + 0.5 * cos(a0), 0.5 + 0.5 * sin(a0))
      out[#out + 1] = V(x1, z1, 0.5 + 0.5 * cos(a1), 0.5 + 0.5 * sin(a1))
    end
  end

  -- ------- the renderer and the scene (built once, in the update step)

  local R = nil
  local function renderer()
    if R then return R end
    R = deps.Render3d(mod, { name = "the alley", camera = { view = viewMatrix, projection = projectionMatrix } })
    return R
  end
  function Al.available()
    if Al.failed then return false, Al.why end
    if not deps.Render3d then return false, "no renderer" end
    local ok, why = renderer().available()
    if not ok then Al.why = why end
    return ok, why
  end

  local scene = nil
  function Al.resetScene() scene = nil end

  local function build()
    local lib = renderer().g3d()
    local pieces = {}
    local function add(verts, img, pass, name)
      if #verts >= 3 then pieces[#pieces + 1] = { model = lib.newModel(verts, img), pass = pass, name = name } end
    end
    local plain = white()
    local W, L = Al.W, Al.LAMP

    -- the sky: a wall of gradient far behind (pass 1, no depth): black overhead, a dull sodium
    -- haze over the city at the horizon
    do
      local v = {}
      local zS = -150
      quad(v, vtx(-200, -10, zS, 0, 1, 0.1, 0.06, 0.08), vtx(200, -10, zS, 1, 1, 0.1, 0.06, 0.08),
        vtx(200, 22, zS, 1, 0, 0.03, 0.03, 0.06), vtx(-200, 22, zS, 0, 0, 0.03, 0.03, 0.06))
      quad(v, vtx(-200, 22, zS, 0, 1, 0.03, 0.03, 0.06), vtx(200, 22, zS, 1, 1, 0.03, 0.03, 0.06),
        vtx(200, 160, zS, 1, 0, 0, 0, 0.01), vtx(-200, 160, zS, 0, 0, 0, 0, 0.01))
      add(v, plain, 1, "sky")
    end

    -- the skyline across the street at the far end (its gaps cut away), dim
    do
      local v = {}
      local z = -46
      quad(v, vtx(-34, -0.5, z, 0, 1, 0.45, 0.45, 0.55), vtx(34, -0.5, z, 3, 1, 0.45, 0.45, 0.55),
        vtx(34, 26, z, 3, 0, 0.45, 0.45, 0.55), vtx(-34, 26, z, 0, 0, 0.45, 0.45, 0.55))
      add(v, skyline(), 2, "skyline")
    end

    -- the ground: wet asphalt in small cells (the pool of light is tight), the street beyond
    do
      local v = {}
      local cell = 0.4
      for z = Al.Z1, Al.Z0 - cell, cell do
        for x = -W, W - 1e-6, cell do
          local x1, z1 = min(W, x + cell), z + cell
          quad(v, lv(x, 0, z1, x / 1.6, z1 / 1.6, 0.7, 0.7, 0.78), lv(x1, 0, z1, x1 / 1.6, z1 / 1.6, 0.7, 0.7, 0.78),
            lv(x1, 0, z, x1 / 1.6, z / 1.6, 0.7, 0.7, 0.78), lv(x, 0, z, x / 1.6, z / 1.6, 0.7, 0.7, 0.78))
        end
      end
      for z = -46, Al.Z1 - 2, 2 do
        quad(v, lv(-34, 0, z + 2, -34 / 3, (z + 2) / 3, 0.5, 0.5, 0.55), lv(34, 0, z + 2, 34 / 3, (z + 2) / 3, 0.5, 0.5, 0.55),
          lv(34, 0, z, 34 / 3, z / 3, 0.5, 0.5, 0.55), lv(-34, 0, z, -34 / 3, z / 3, 0.5, 0.5, 0.55))
      end
      add(v, asphalt(), 2, "ground")
    end

    -- the walls, in half-metre cells
    do
      local v = {}
      wall(v, -W, 0.5, 1.6, 1.2)
      wall(v, W, 0.5, 1.6, 1.2)
      add(v, brick(), 2, "walls")
    end

    -- windows: dark, one dimly lit behind a blind
    do
      local v = {}
      local e = 0.012
      onWall(v, -W + e, -5.2, -6.4, 4.2, 6.0, 0.3, 0.32, 0.4)
      onWall(v, -W + e, -22.6, -23.8, 4.6, 6.4, 0.25, 0.27, 0.35)
      onWall(v, W - e, -12.4, -11.2, 4.8, 6.6, 0.5, 0.33, 0.16, true)
      onWall(v, W - e, -25.8, -24.6, 3.2, 5.0, 0.25, 0.27, 0.35)
      onWall(v, -W + e, -13.4, -14.6, 6.4, 8.2, 0.28, 0.3, 0.38)
      add(v, window(), 2, "windows")
    end

    local METAL = { 0.32, 0.33, 0.36 }
    -- the drainpipe, the dumpster and its bags, the crates, a steel door, the fire escape, the
    -- cables overhead, the lamp post with its arm and hood, the bulb, the neon sign
    do
      local v = {}
      box(v, W - 0.18, W - 0.03, 0, 10.5, -8.3, -8.12, 0.45, 0.47, 0.5)
      box(v, 1.25, 2.35, 0, 1.12, -13.3, -11.7, 0.2, 0.32, 0.22)
      box(v, 1.18, 2.4, 1.12, 1.2, -13.38, -11.62, 0.16, 0.26, 0.18)
      box(v, 0.85, 1.25, 0, 0.42, -11.6, -11.0, 0.1, 0.1, 0.12)
      box(v, 0.95, 1.4, 0, 0.32, -14.2, -13.5, 0.1, 0.1, 0.12)
      box(v, 1.45, 2.3, 0, 0.8, -20.2, -19.4, 0.52, 0.36, 0.22)
      box(v, 1.6, 2.3, 0.8, 1.45, -20.0, -19.5, 0.48, 0.33, 0.2)
      box(v, W - 0.06, W - 0.01, 0, 2.1, -17.2, -16.2, 0.36, 0.37, 0.4)
      -- the fire escape on the left wall: two landings, their rails, a ladder between
      for _, y in ipairs({ 3.6, 6.4 }) do
        box(v, -W, -W + 0.85, y - 0.06, y, -9.2, -4.2, METAL[1], METAL[2], METAL[3])
        box(v, -W + 0.8, -W + 0.85, y + 0.85, y + 0.9, -9.2, -4.2, METAL[1], METAL[2], METAL[3])
        for z = -9.2, -4.2, 1.0 do
          box(v, -W + 0.8, -W + 0.85, y, y + 0.9, z - 0.025, z + 0.025, METAL[1], METAL[2], METAL[3])
        end
      end
      box(v, -W + 0.2, -W + 0.24, 0.9, 6.4, -8.8, -8.76, METAL[1], METAL[2], METAL[3])
      box(v, -W + 0.2, -W + 0.24, 0.9, 6.4, -8.3, -8.26, METAL[1], METAL[2], METAL[3])
      for y = 1.2, 6.2, 0.35 do box(v, -W + 0.2, -W + 0.24, y, y + 0.03, -8.8, -8.26, METAL[1], METAL[2], METAL[3]) end
      -- the cables
      box(v, -W, W, 5.8, 5.83, -10.02, -9.99, 0.05, 0.05, 0.05, 1)
      box(v, -W, W, 6.6, 6.63, -18.02, -17.99, 0.05, 0.05, 0.05, 1)
      -- the lamp
      box(v, L.x - 0.07, L.x + 0.07, 0, L.top, L.z - 0.07, L.z + 0.07, 0.3, 0.32, 0.34)
      box(v, L.x - 0.05, L.bx + 0.05, L.top - 0.12, L.top - 0.04, L.z - 0.05, L.z + 0.05, 0.3, 0.32, 0.34)
      box(v, L.bx - 0.28, L.bx + 0.28, L.by + 0.05, L.by + 0.17, L.z - 0.22, L.z + 0.22, 0.12, 0.12, 0.13, 1)
      box(v, L.bx - 0.15, L.bx + 0.15, L.by - 0.03, L.by + 0.05, L.z - 0.12, L.z + 0.12, 1, 0.92, 0.7, 1)
      -- the neon: a dark plate, the pink tube
      local Ne = Al.NEON
      box(v, W - 0.08, W - 0.02, Ne.y0 - 0.12, Ne.y1 + 0.12, Ne.z0 - 0.12, Ne.z1 + 0.12, 0.06, 0.06, 0.07, 1)
      box(v, W - 0.12, W - 0.08, Ne.y0, Ne.y1, Ne.z0, Ne.z1, 1, 0.3, 0.72, 1)
      -- the manhole
      disc(v, 0.45, -6.2, 0.48, 0.48, 0.006, 0.4, 0.4, 0.42, 1)
      add(v, plain, 2, "props")
    end

    -- see-through: graffiti on both walls, the puddles (the one under the lamp shining), the
    -- lamp's streak on the wet ground, then the cone of light
    do
      local v = {}
      local e = 0.02
      onWall(v, -W + e, -6.6, -10.8, 0.3, 2.4, 0.9, 0.9, 0.9)
      onWall(v, W - e, -27.5, -23.5, 0.4, 2.2, 0.9, 0.9, 0.9)
      add(v, graffiti(), 3, "graffiti")
      local p = {}
      disc(p, 0.7, -8.8, 0.95, 0.5, 0.01, 0.7, 0.75, 0.9, 0.55)
      disc(p, L.poolX + 0.15, L.z + 0.5, 1.2, 0.65, 0.01, 0.9, 0.7, 0.4, 0.55, true)
      disc(p, 1.1, -21, 0.8, 0.45, 0.01, 0.6, 0.66, 0.8, 0.45)
      add(p, puddle(), 3, "puddles")
      local s = {}
      local sx, z0, z1 = L.bx + 0.2, L.z + 0.4, L.z + 6.5
      quad(s, vtx(sx - 0.35, 0.015, z1, 0, 1, 1, 0.75, 0.4, 0), vtx(sx + 0.35, 0.015, z1, 1, 1, 1, 0.75, 0.4, 0),
        vtx(sx + 0.25, 0.015, z0, 1, 0, 1, 0.8, 0.45, 0.55), vtx(sx - 0.25, 0.015, z0, 0, 0, 1, 0.8, 0.45, 0.55))
      add(s, streak(), 3, "reflection")
      local c = {}
      local n, r0, r1 = 16, 0.16, L.poolR
      for i = 0, n - 1 do
        local a0, a1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
        quad(c,
          vtx(L.poolX + r1 * cos(a0), 0.02, L.z + r1 * sin(a0), 0, 1, 1, 0.8, 0.45, 0.04),
          vtx(L.poolX + r1 * cos(a1), 0.02, L.z + r1 * sin(a1), 1, 1, 1, 0.8, 0.45, 0.04),
          vtx(L.bx + r0 * cos(a1), L.by, L.z + r0 * sin(a1), 1, 0, 1, 0.88, 0.58, 0.3),
          vtx(L.bx + r0 * cos(a0), L.by, L.z + r0 * sin(a0), 0, 0, 1, 0.88, 0.58, 0.3))
      end
      add(c, plain, 3, "cone")
    end

    return { clear = Al.CLEAR, pieces = pieces }
  end

  function Al.scene()
    if scene or Al.failed then return scene end
    local ok, s = pcall(build)
    if ok and s then scene = s else
      Al.failed, Al.why = true, "the alley did not build (" .. tostring(s) .. ")"
      if mod.log then mod.log:warn("Super Training: %s; drawn flat", Al.why) end
    end
    return scene
  end

  -- ------- update and draw

  -- in an update step: the picture for the rect the draw last asked for, the camera where the
  -- draw will have it
  local function setup(tg)
    Al.setRect(tg.ex, tg.ey, tg.ew, tg.eh)
    place()
  end
  function Al.prepare()
    if not Al.available() then return false end
    local sc = Al.scene()
    if not sc then return false end
    return renderer().prepare(sc, setup)
  end

  -- the dealer's sprite (assets/r-deal.png, loaded once)
  local dealerImg = nil
  local function dealer()
    if dealerImg ~= nil then return dealerImg or nil end
    dealerImg = false
    local ok, img = pcall(function()
      local bytes = mod.read and mod:read("assets/r-deal.png")
      if not bytes then return nil end
      local i = love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(bytes, "r-deal.png")))
      i:setFilter("nearest", "nearest")
      return i
    end)
    if ok and img then dealerImg = img end
    return dealerImg or nil
  end
  Al.dealerImage = dealer

  -- a soft disc of added light (a fan mesh, no canvas)
  local glowMesh = nil
  local function glow(G2, x, y, r, cr, cg, cb, a)
    if not glowMesh then
      local v = { { 0, 0, 0.5, 0.5, 1, 1, 1, 1 } }
      for i = 0, 24 do
        local t = 2 * pi * i / 24
        v[#v + 1] = { cos(t), sin(t), 0, 0, 1, 1, 1, 0 }
      end
      glowMesh = G2.newMesh(v, "fan", "static")
    end
    G2.push()
    G2.setBlendMode("add")
    G2.setColor(cr, cg, cb, a)
    G2.draw(glowMesh, x, y, 0, r, r)
    G2.setBlendMode("alpha")
    G2.pop()
  end

  -- where the dealer stands on screen: his feet, his height (draw units)
  function Al.dealerAt()
    local D = Al.DEALER
    local x, y, d = project(D.x, 0, D.z)
    if not x then return nil end
    return x, y, D.h * cam.F / d
  end

  -- the rain: slanted streaks falling through the rect, brighter in the lamp's light
  local RAIN = { N = 90, SPEED = 1.6, LEN = 0.07, SLANT = 0.18 }
  Al.RAIN = RAIN
  local function rain(G2, ex, ey, ew, eh, t, lampX, lampY)
    G2.setLineWidth(math.max(0.6, eh / 300))
    for i = 1, RAIN.N do
      local sx = hash(i, 21)
      local sp = RAIN.SPEED * (0.7 + 0.6 * hash(i, 22))
      local yy = (hash(i, 23) + t * sp) % 1.15 - 0.1
      local x = ex + ((sx + yy * RAIN.SLANT) % 1) * ew
      local y = ey + yy * eh
      local len = RAIN.LEN * eh * (0.6 + 0.8 * hash(i, 24))
      local a = 0.18 + 0.12 * hash(i, 25)
      if lampX then
        local dx, dy = (x - lampX) / (ew * 0.25), (y - lampY) / (eh * 0.45)
        a = a + 0.45 * math.max(0, 1 - (dx * dx + dy * dy))
      end
      G2.setColor(0.75, 0.8, 0.95, a)
      G2.line(x, y, x - len * RAIN.SLANT, y - len)
    end
  end

  -- raindrops landing on the ground ahead: small rings opening and fading
  local function splashes(G2, t)
    G2.setLineWidth(0.6)
    for i = 1, 26 do
      local period = 0.5 + 0.6 * hash(i, 60)
      local u = ((t + hash(i, 61) * period) % period) / period
      local cyc = floor((t + hash(i, 61) * period) / period)
      local x = -Al.W + 2 * Al.W * hash(i * 31 + cyc, 62)
      local z = eye[3] - 1.5 - 9 * hash(i * 17 + cyc, 63)
      local sx, sy, d = project(x, 0.01, z)
      if sx then
        local k = cam.F / d
        G2.setColor(0.7, 0.75, 0.9, 0.35 * (1 - u))
        G2.ellipse("line", sx, sy, (0.05 + 0.12 * u) * k, (0.02 + 0.04 * u) * k, 12)
      end
    end
  end

  -- the edges and corners darkened (a mesh: clear in the middle, black at the rim)
  local vigMesh = nil
  local function vignette(G2, ex, ey, ew, eh)
    if not vigMesh then
      -- (the last band, at the rim's darkness, reaches past the corners: they lie at sqrt(2))
      local v, rings = {}, { { 0.0, 0 }, { 0.55, 0 }, { 0.85, 0.45 }, { 1.25, 0.9 }, { 2.2, 0.9 } }
      local n = 24
      for r = 1, #rings - 1 do
        local a, b = rings[r], rings[r + 1]
        for i = 0, n - 1 do
          local t0, t1 = 2 * pi * i / n, 2 * pi * (i + 1) / n
          local function P(ring, th) return { ring[1] * cos(th), ring[1] * sin(th), 0, 0, 0, 0, 0, ring[2] } end
          v[#v + 1] = P(a, t0); v[#v + 1] = P(b, t0); v[#v + 1] = P(b, t1)
          v[#v + 1] = P(a, t0); v[#v + 1] = P(b, t1); v[#v + 1] = P(a, t1)
        end
      end
      vigMesh = G2.newMesh(v, "triangles", "static")
    end
    -- (the rim runs a little past the rect: the touch screen's own edge cuts it)
    G2.setColor(1, 1, 1, 1)
    G2.draw(vigMesh, ex + ew / 2, ey + eh / 2, 0, ew / 2 * 1.05, eh / 2 * 1.05)
  end

  -- the flat version (no 3D): the same camera's alley as filled polygons, far to near
  local function poly(G2, pts)
    local out = {}
    for i = 1, #pts, 3 do
      local x, y = project(pts[i], pts[i + 1], pts[i + 2])
      if not x then return end
      out[#out + 1] = x; out[#out + 1] = y
    end
    if #out >= 6 then pcall(G2.polygon, "fill", out) end
  end
  function Al.drawFlat(G2, ex, ey, ew, eh)
    Al.setRect(ex, ey, ew, eh)
    place()
    G2.setColor(Al.CLEAR[1], Al.CLEAR[2], Al.CLEAR[3], 1)
    G2.rectangle("fill", ex, ey, ew, eh)
    local W, near = Al.W, eye[3] - 0.3
    for z = Al.Z1, near - 1, 1 do
      local z1 = min(near, z + 1)
      local cr, cg, cb = lit(0, 0, z + 0.5, 0.8, 0.8, 0.85)
      G2.setColor(cr * 0.5, cg * 0.5, cb * 0.5, 1)
      poly(G2, { -W, 0, z, W, 0, z, W, 0, z1, -W, 0, z1 })
      cr, cg, cb = lit(-W, 2, z + 0.5, 0.55, 0.3, 0.24)
      G2.setColor(cr, cg, cb, 1)
      poly(G2, { -W, 0, z, -W, 0, z1, -W, Al.H, z1, -W, Al.H, z })
      cr, cg, cb = lit(W, 2, z + 0.5, 0.5, 0.27, 0.22)
      G2.setColor(cr, cg, cb, 1)
      poly(G2, { W, 0, z, W, 0, z1, W, Al.H, z1, W, Al.H, z })
    end
    local L = Al.LAMP
    local x0, y0 = project(L.x, 0, L.z)
    local x1, y1 = project(L.x, L.top, L.z)
    if x0 and x1 then
      G2.setColor(0.3, 0.32, 0.34, 1)
      G2.setLineWidth(max(1, (y0 - y1) * 0.03))
      G2.line(x0, y0, x1, y1)
    end
  end

  -- the alley over ex, ey, ew, eh (draw units): the picture, the lamp's glow, the dealer
  -- (alpha 0..1), the rain (clock t)
  function Al.draw(G2, ex, ey, ew, eh, dealerA, t)
    local ok = false
    if Al.available() and scene then ok = renderer().draw(G2, scene, ex, ey, ew, eh) end
    if not ok then
      Al.drawFlat(G2, ex, ey, ew, eh)
    else
      Al.setRect(ex, ey, ew, eh)
      place()
    end
    t = t or 0
    local fl = Al.flicker(t)
    -- steam from the manhole, drifting up and fading
    do
      local mx, my, md = project(0.45, 0, -6.2)
      if mx then
        local k = cam.F / md
        for i = 1, 7 do
          local u = (t * 0.22 + hash(i, 50)) % 1
          local px = mx + (sin(t * 0.7 + i) * 0.25 + (hash(i, 51) - 0.5) * 0.4) * k
          local py = my - u * 2.4 * k
          G2.setColor(0.55, 0.55, 0.6, 0.1 * (1 - u) * min(1, u * 5))
          G2.circle("fill", px, py, (0.25 + 0.5 * u) * k, 20)
        end
      end
    end
    local L = Al.LAMP
    local bx, by, bd = project(L.bx, L.by, L.z)
    if bx then
      local k = cam.F / bd
      glow(G2, bx, by, 1.4 * k, 1, 0.75, 0.4, 0.4 * fl)
      glow(G2, bx, by, 0.4 * k, 1, 0.9, 0.65, 0.85 * fl)
    end
    -- the neon's pink glow, buzzing on and off
    do
      local Ne = Al.NEON
      local nx, ny, nd = project(Al.W - 0.1, (Ne.y0 + Ne.y1) / 2, (Ne.z0 + Ne.z1) / 2)
      if nx then
        local on = ((sin(t * 37) > -0.6) and (floor(t * 1.3) % 5 ~= 0)) and 1 or 0.25
        glow(G2, nx, ny, 1.3 * cam.F / nd, 1, 0.25, 0.65, 0.4 * on)
      end
    end
    local img = dealer()
    if img and (dealerA or 0) > 0 then
      local fx, fy, h = Al.dealerAt()
      if fx then
        local iw, ih = img:getDimensions()
        local k = h / ih
        -- his shadow on the wet ground
        G2.setColor(0, 0, 0, 0.45 * dealerA)
        G2.ellipse("fill", fx, fy, iw * k * 0.36, iw * k * 0.08, 24)
        -- lit warm from above (with the lamp's flicker), the rest of him in the dark
        local lk = 0.55 + 0.35 * fl
        G2.setColor(lk, lk * 0.85, lk * 0.7, dealerA)
        local HD = mod.hd
        if HD and HD.drawPixel then HD.drawPixel(img, fx, fy, 0, k, k, iw / 2, ih)
        else G2.draw(img, fx, fy, 0, k, k, iw / 2, ih) end
      end
    end
    rain(G2, ex, ey, ew, eh, t, bx, by)
    splashes(G2, t)
    -- the flicker's dip, and the dark closing in from the edges
    if fl < 1 then
      G2.setColor(0, 0, 0, (1 - fl) * 0.35)
      G2.rectangle("fill", ex, ey, ew, eh)
    end
    vignette(G2, ex, ey, ew, eh)
    G2.setColor(1, 1, 1, 1)
    return ok
  end

  function Al.stats() return R and R.stats or nil end

  return Al
end
