-- 3D SUPER TRAINING (option training_3d): the regimen's arena as a real 3D scene behind the
-- same sprites. The sim, its rules and hitboxes are untouched; only the view changes:
--
--   * the game's orbit: the trainee on its sphere about the balloon, the camera riding it
--     (CAM; the sim's flat world mapped onto the stadium model's), the balloon's plane
--     framed about as large as the 2D view frames it, so aiming reads the same;
--   * A3.project(x, y, z) -> screen x, y (240x160 units) and k (px per world unit across / 118),
--     the shape of Sim.project's, so arena_draw's sprites, shadows, goals and the HUD's reticle
--     and popups take their places and sizes from the camera; A3.unprojectToPlane casts the
--     camera's ray back onto a plane of the world (aiming);
--   * the stadium is drawn by g3d (src/g3d, vendored) into a canvas of its own with a depth
--     buffer (the window has none), the card's model when extracted (Assets.model
--     "st3d/stadium"), else a drawn stand-in (arena3d_stand.lua), and blitted under the sprites.
--
-- The projection is a plain pinhole worked here in Lua; g3d draws with the same view matrix
-- and an off-centre frustum built from the same focal length, so the stadium and the sprites
-- agree to the pixel. A3.available() probes the device once (shader, depth canvas) and the
-- caller falls back to the 2D view when it fails.
--
-- A3 = arena3d(mod, { Sim, Rules, Assets })

return function(mod, deps)
  local Sim, Rules = deps.Sim, deps.Rules
  local N = Rules.N
  local A3 = { assets = deps.Assets, failed = false, why = nil }

  -- ------- the orbit (the game's, DllSparring.cro): the trainee on a sphere about the balloon -
  -- elevation 0..45 degrees, azimuth 60..120 (90 straight in front), the radius its distance
  -- step (180 / 240 / 300) - and the camera riding that point, looking at the balloon. Units
  -- are the stadium model's (a/1/1/4 e75: the pitch's middle the origin, its grass at y -6.7).
  --
  -- The sim's world stays flat (x across, y up, z from the trainee's plane to the balloon's):
  -- the trainee's x / y give its azimuth / elevation; a point on the balloon's plane (z 1) is
  -- laid flat about the balloon, facing the camera (S model units a world unit across, SY of
  -- that up); a point on the trainee's plane about the trainee (ST a world unit); between them
  -- the two are blended by depth (u), so a ball flies from the balloon onto the trainee.
  --
  --   FOVY       the camera's vertical field (degrees): the game's own camera's (e77, 37.85; 3:2)
  --   EYE_H      the eye above the trainee's sphere point (the game's target lift 4.5)
  --   TARGET_Y   the height it looks at over the balloon
  --   BAL_Y      the balloon's middle (the sim's resting CY) in the model
  --   BAL_K      the balloon's plane drawn this large against the 2D view at the middle distance
  --   AHEAD, LEFT, BELOW  where the trainee stands from the eye (the game puts its model 11.5
  --              ahead, 2.5 left, 1 below; ours is a sprite on a board, its feet the point)
  --   TRAINEE_K  the trainee's plane drawn this large against the 2D view
  --   GROUND     the grass's height (the model's white lines)
  --   NEAR, FAR  the depth drawn
  -- (fitted to Wooble's capture magneton-2 at the start: the Poke Ball over the balloon, at screen
  -- y ~28 / 160, the balloon's middle ~67, the trainee left of the middle, low)
  A3.CAM = { FOVY = 37.85, EYE_H = 4.5, TARGET_Y = 31, BAL_Y = 45, BAL_K = 0.82,
    AHEAD = 30, LEFT = 6.3, BELOW = 4.5, TRAINEE_K = 1.3, GROUND = -6.7, SY = 0.625,
    AZ = { 60, 120 }, EL = { 0, 45 }, NEAR = 1, FAR = 6000 }
  -- the intro's camera (a/1/1/4 e77, a CGFX camera animation of 90 frames): its eye and the point
  -- it looks at, eased into the play camera as the intro settles
  A3.INTRO = { EYE0 = { 0, 53.708, 544.479 }, EYE1 = { 0, 46.399, 358.572 },
    AIM0 = { 0, 80.545, -5 }, AIM1 = { 0, 115.276, -5 } }

  local rad, sin, cos, sqrt = math.rad, math.sin, math.cos, math.sqrt
  local shader                   -- the stadium's shader (A3.available)
  -- the view matrix's rows (g3d's layout) and the eye
  local m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12 = 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0
  local eyeX, eyeY, eyeZ = 0, 0, 240
  local F, PY = 172, 80          -- focal length (240x160 units) and the axis's screen height
  local CX = 120                 -- ...and its screen x
  -- The area the arena fills (240x160 units, set each frame by the drawer: the playfield, which
  -- can reach past the GBA frame's whole-number scale), and the game's screen shape (400x240):
  -- the camera shows the game's whole view contained in the area, about its middle - the
  -- game's width on a taller area, its height on a wider one - whatever the frame's scale.
  local VIEW = { x = 0, y = 0, w = 240, h = 160 }
  A3.ASPECT = 400 / 240
  function A3.setView(ex, ey, ew, eh)
    VIEW.x, VIEW.y, VIEW.w, VIEW.h = ex or 0, ey or 0, ew or 240, eh or 160
  end
  local tvNow = math.tan(rad(37.81) / 2)
  local function fitView(fovy)
    local tv = math.tan(rad(fovy) / 2)
    tvNow = tv
    CX, PY = VIEW.x + VIEW.w / 2, VIEW.y + VIEW.h / 2
    F = math.min((VIEW.w / 2) / (tv * A3.ASPECT), (VIEW.h / 2) / tv)
  end
  -- the view's middle (240x160 units) and the units one of the game's 400x240 px spans there
  function A3.viewCentre() return CX, PY end
  function A3.unitsPerGamePx() return 2 * F * tvNow / 240 end
  -- the mapping's state: the trainee's anchor (A), the camera's right (R, horizontal), the
  -- scales on the two planes, the balloon plane's foot, the trainee's flat x / y / z
  local Ax, Ay, Az, Rx, Rz = 0, 0, 200, 1, 0
  local S, ST, GY = 160, 20, -60
  local px0, py0, pz0 = 0, 0, 0.1
  local azNow, elNow, rNow = 90, 0, 240

  -- the look-at view matrix (as g3d's matrices:setViewMatrix, y up)
  local function lookAt(ex, ey, ez, tx, ty, tz)
    local zx, zy, zz = ex - tx, ey - ty, ez - tz
    local l = sqrt(zx * zx + zy * zy + zz * zz)
    zx, zy, zz = zx / l, zy / l, zz / l
    local xx, xy, xz = zz, 0, -zx
    l = sqrt(xx * xx + xz * xz)
    xx, xz = xx / l, xz / l
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
    m1, m2, m3, m4 = xx, xy, xz, -(xx * ex + xy * ey + xz * ez)
    m5, m6, m7, m8 = yx, yy, yz, -(yx * ex + yy * ey + yz * ez)
    m9, m10, m11, m12 = zx, zy, zz, -(zx * ex + zy * ey + zz * ez)
    eyeX, eyeY, eyeZ = ex, ey, ez
  end

  -- the game's sphere point (degrees): x = r cos el cos az, y = r sin el, z = r cos el sin az
  function A3.sphere(el, az, r)
    local ce = cos(rad(el))
    return r * ce * cos(rad(az)), r * sin(rad(el)), r * ce * sin(rad(az))
  end
  -- the trainee's flat x / y -> its azimuth / elevation (the sim's box onto the game's limits)
  function A3.orbitAngles(x, y)
    local C = A3.CAM
    local az = 90 - (x / N.PLAYER.X_MAX) * (C.AZ[2] - C.AZ[1]) / 2
    local el = C.EL[1] + (y / (N.PLAYER.Y_MAX or 1.25)) * (C.EL[2] - C.EL[1])
    return az, el
  end

  -- the camera and the mapping for the trainee at flat (x, y, z) at distance r; intro (optional)
  -- 0 the game's intro camera .. 1 the play camera
  local function place(x, y, z, r, intro)
    local C = A3.CAM
    local az, el = A3.orbitAngles(x, y)
    azNow, elNow, rNow = az, el, r
    local sx, sy, sz = A3.sphere(el, az, r)
    local ex, ey, ez = sx, sy + C.EYE_H, sz
    local tx, ty, tz = 0, C.TARGET_Y, 0
    fitView(C.FOVY)
    -- the play camera fixes the mapping
    lookAt(ex, ey, ez, tx, ty, tz)
    Rx, Rz = m1, m3
    Ax = ex - m9 * C.AHEAD - m1 * C.LEFT - m5 * C.BELOW
    Ay = ey - m10 * C.AHEAD - m2 * C.LEFT - m6 * C.BELOW
    Az = ez - m11 * C.AHEAD - m3 * C.LEFT - m7 * C.BELOW
    ST = C.TRAINEE_K * 118 * C.AHEAD / F
    -- the balloon's plane: as large as the 2D view frames it from the middle distance
    local r0 = N.PLAYER.DIST and N.PLAYER.DIST[N.PLAYER.DIST_STEP0] or 240
    local d0 = sqrt(r0 * r0 + (C.EYE_H - C.BAL_Y) ^ 2)
    S = C.BAL_K * 120 * d0 / F
    GY = C.BAL_Y - (N.BOT.SHAPE_CY or 1.04) * S * C.SY
    px0, py0, pz0 = x, y, z
    -- the intro: the game's own camera eased into this one
    if intro and intro < 1 then
      local I, k = A3.INTRO, math.max(0, intro)
      local w = k * k * (3 - 2 * k)
      local e0x = I.EYE0[1] + (I.EYE1[1] - I.EYE0[1]) * k
      local e0y = I.EYE0[2] + (I.EYE1[2] - I.EYE0[2]) * k
      local e0z = I.EYE0[3] + (I.EYE1[3] - I.EYE0[3]) * k
      local a0x = I.AIM0[1] + (I.AIM1[1] - I.AIM0[1]) * k
      local a0y = I.AIM0[2] + (I.AIM1[2] - I.AIM0[2]) * k
      local a0z = I.AIM0[3] + (I.AIM1[3] - I.AIM0[3]) * k
      lookAt(e0x + (ex - e0x) * w, e0y + (ey - e0y) * w, e0z + (ez - e0z) * w,
        a0x + (tx - a0x) * w, a0y + (ty - a0y) * w, a0z + (tz - a0z) * w)
    end
  end
  A3.place = function(x, y) place(x or 0, y or 0, N.PLAYER.Z or 0.1, 240) end
  A3.place(0, 0)

  -- the game's play in its own space (the sim's game3d, src/training/sim3d.lua): the camera is
  -- the game's - its eye on the trainee's sphere point (the sim's p.ex / ey / ez), looking at
  -- (0, LOOK_Y, 0) - its field PLAY_FOVY; points are the game's; the intro's camera (e77) eases in
  A3.game = nil   -- the sim played in the game's space this frame, else nil
  local function placeGame(sim, intro)
    local G3, p = N.GAME3D, sim.player
    fitView(G3.PLAY_FOVY)
    azNow, elNow, rNow = p.az or 90, p.el or 0, p.dist or 240
    local ex, ey, ez, tx, ty, tz = p.ex, p.ey, p.ez, 0, G3.LOOK_Y, 0
    if intro and intro < 1 then
      local I, k = A3.INTRO, math.max(0, intro)
      local w = k * k * (3 - 2 * k)
      local e0x = I.EYE0[1] + (I.EYE1[1] - I.EYE0[1]) * k
      local e0y = I.EYE0[2] + (I.EYE1[2] - I.EYE0[2]) * k
      local e0z = I.EYE0[3] + (I.EYE1[3] - I.EYE0[3]) * k
      local a0x = I.AIM0[1] + (I.AIM1[1] - I.AIM0[1]) * k
      local a0y = I.AIM0[2] + (I.AIM1[2] - I.AIM0[2]) * k
      local a0z = I.AIM0[3] + (I.AIM1[3] - I.AIM0[3]) * k
      ex, ey, ez = e0x + (ex - e0x) * w, e0y + (ey - e0y) * w, e0z + (ez - e0z) * w
      tx, ty, tz = a0x + (tx - a0x) * w, a0y + (ty - a0y) * w, a0z + (tz - a0z) * w
    end
    lookAt(ex, ey, ez, tx, ty, tz)
  end

  -- the regimen's ending (a cleared course's last balloon): a fixed camera low in front of it,
  -- looking up past it at the far roof - fitted to the end-reg-ref capture (the emblems' and the
  -- roof edge's places, the balloon's axis down the middle, the grown Axew's head at y 168 of
  -- 480: 0.93 px rms; the stadium is 8-fold round, so the turn that sets it in front of the
  -- balloon). The eye is under the grass (the fit's: 2-4 px off with it held above), so the
  -- stadium is drawn with back faces culled meanwhile (CULL), as the game does: the ground's
  -- underside not drawn
  A3.ENDING = { EYE = { 33.7, -25.7, 193.9 }, AIM = { -3.0, 83.1, -16.8 }, FOVY = 37.81, CULL = "back" }
  local ending = false
  function A3.setEnding(on) ending = on and true or false end
  function A3.inEnding() return ending end

  -- follow the trainee: once a frame with the frame's sim (and the HUD's pose: its intro camera)
  function A3.update(sim, pose)
    local p = sim and sim.player
    if not p then return end
    if ending then
      local E = A3.ENDING
      A3.game = sim.game3d and sim or nil
      fitView(E.FOVY)
      -- the game's view sits on the area's foot (any room left over is sky above it, as the
      -- capture looks up into the sky; centred, a taller area showed the crowd and grass under
      -- the roof that the game never shows)
      PY = VIEW.y + VIEW.h - F * tvNow
      lookAt(E.EYE[1], E.EYE[2], E.EYE[3], E.AIM[1], E.AIM[2], E.AIM[3])
      return
    end
    local cam = pose and pose.cam
    if sim.game3d then
      A3.game = sim
      placeGame(sim, cam and (cam.k or 0) or nil)
      return
    end
    A3.game = nil
    local r = p.dist or (N.PLAYER.DIST and N.PLAYER.DIST[N.PLAYER.DIST_STEP0]) or 240
    place(p.x or 0, p.y or 0, p.z or N.PLAYER.Z or 0.1, r, cam and (cam.k or 0) or nil)
  end
  function A3.orbitNow() return azNow, elNow, rNow end
  function A3.camOffset() return Ax, Ay, Az end

  -- a world point (the sim's flat x, y, z) -> the stadium model's (x, y, z), and the scale
  -- across there (model units a world unit)
  local function toModel(x, y, z)
    local u = (1 - z) / math.max(1e-3, 1 - pz0)
    local bx, by, bz = x * S * Rx, GY + y * S * A3.CAM.SY, x * S * Rz
    local dx, dy = x - px0, y - py0
    local tx, ty, tz = Ax + dx * ST * Rx, Ay + dy * ST * A3.CAM.SY, Az + dx * ST * Rz
    return bx + (tx - bx) * u, by + (ty - by) * u, bz + (tz - bz) * u, S + (ST - S) * u
  end
  A3.toModel = toModel

  -- a point of the model -> screen x, y (240x160 units) and its distance in front of the eye
  local function projectModel(X, Y, Z)
    local vx = m1 * X + m2 * Y + m3 * Z + m4
    local vy = m5 * X + m6 * Y + m7 * Z + m8
    local d = -(m9 * X + m10 * Y + m11 * Z + m12)
    if d < 1e-3 then d = 1e-3 end
    local f = F / d
    return CX + vx * f, PY - vy * f, d
  end
  A3.projectModel = projectModel

  -- world (x, y, z) -> screen x, y and k: px per world unit across there / 118 (Sim.project's k)
  -- (in the game's space the points are the game's: k = px a game unit / 118)
  function A3.project(x, y, z)
    if A3.game then
      local sx, sy, d = projectModel(x, y, z)
      return sx, sy, F / d / 118
    end
    local X, Y, Z, s = toModel(x, y, z)
    local sx, sy, d = projectModel(X, Y, Z)
    return sx, sy, F / d * s / 118
  end
  -- a point of the balloon's side of the flat world (z 1: its middle, goals, the aim) on the screen
  function A3.projectBalloon(x, y)
    local g = A3.game
    if g then
      local X, Y, Z = g:toGame(x, y)
      local sx, sy, d = projectModel(X, Y, Z)
      return sx, sy, F / d / 118
    end
    return A3.project(x, y, 1)
  end

  -- the camera's ray through screen (sx, sy) meets the balloon's plane (z 1) at world (x, y)
  -- (in the game's space: the game's plane z 0 through the balloon, as the flat world's x, y)
  function A3.unprojectToPlane(sx, sy)
    local dx, dy = (sx - CX) / F, -(sy - PY) / F
    local wx = m1 * dx + m5 * dy - m9
    local wy = m2 * dx + m6 * dy - m10
    local wz = m3 * dx + m7 * dy - m11
    if A3.game then
      if math.abs(wz) < 1e-9 then return nil end
      local t = -eyeZ / wz
      return A3.game:fromGame(eyeX + wx * t, eyeY + wy * t)
    end
    -- the plane through the balloon (0, GY, 0) spanned by R and up: its normal (Rz, 0, -Rx)
    local nx, nz = Rz, -Rx
    local den = wx * nx + wz * nz
    if math.abs(den) < 1e-9 then return nil end
    local t = -(eyeX * nx + eyeZ * nz) / den
    local X, Y, Z = eyeX + wx * t, eyeY + wy * t, eyeZ + wz * t
    return (X * Rx + Z * Rz) / S, (Y - GY) / (S * A3.CAM.SY)
  end

  -- the grass under a world point (its x, z): screen y (the balloon's shadow, the shield's foot)
  function A3.floorY(x, z)
    if A3.game then
      local X = A3.game:toGame(x, 0)
      local _, y = projectModel(X, N.GAME3D.GROUND, 0)
      return y
    end
    local X, _, Z = toModel(x, 0, z)
    local _, y = projectModel(X, A3.CAM.GROUND, Z)
    return y
  end

  -- an ellipse lying on the grass about (x, 0, z), half width rw (world units)
  function A3.groundEllipse(x, z, rw)
    local X, _, Z, s = toModel(x, 0, z)
    local G = A3.CAM.GROUND
    local cx, cy = projectModel(X, G, Z)
    local r = rw * s
    local lx = projectModel(X - r * Rx, G, Z - r * Rz)
    local rx = projectModel(X + r * Rx, G, Z + r * Rz)
    local _, ny = projectModel(X - r * Rz, G, Z + r * Rx)
    local _, fy = projectModel(X + r * Rz, G, Z - r * Rx)
    return cx, cy, math.abs(rx - lx) / 2, math.max(0.5, math.abs(fy - ny) / 2)
  end

  -- the view matrix (g3d layout) and an off-centre frustum for the screen rect ex, ey, ew, eh
  -- (240x160 units) drawn by a canvas: the same camera as A3.project
  function A3.viewMatrix(out)
    out[1], out[2], out[3], out[4] = m1, m2, m3, m4
    out[5], out[6], out[7], out[8] = m5, m6, m7, m8
    out[9], out[10], out[11], out[12] = m9, m10, m11, m12
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
  end
  function A3.projectionMatrix(out, ex, ey, ew, eh)
    local n, f = A3.CAM.NEAR, A3.CAM.FAR
    local l, r = (ex - CX) / F * n, (ex + ew - CX) / F * n
    local t, b = (PY - ey) / F * n, (PY - (ey + eh)) / F * n
    out[1], out[2], out[3], out[4] = 2 * n / (r - l), 0, (r + l) / (r - l), 0
    out[5], out[6], out[7], out[8] = 0, 2 * n / (t - b), (t + b) / (t - b), 0
    out[9], out[10], out[11], out[12] = 0, 0, -(f + n) / (f - n), -2 * f * n / (f - n)
    out[13], out[14], out[15], out[16] = 0, 0, -1, 0
    return out
  end

  -- ------- g3d (loaded once, from this mod's src/g3d; a mod cannot require its own files)

  local g3d, g3dWhy = nil, nil
  function A3.g3d()
    if g3d or g3dWhy then return g3d, g3dWhy end
    local function use(name, lib)
      local path = "src/g3d/" .. name .. ".lua"
      local src = mod.read and mod:read(path)
      if not src then error(path .. " is missing") end
      local chunk, err = load(src, "@" .. (mod.path or "play_nav") .. "/" .. path)
      if not chunk then error(err) end
      return chunk(lib)
    end
    local ok, lib = pcall(function()
      local src = mod:read("src/g3d/init.lua")
      local chunk = assert(load(src, "@" .. (mod.path or "play_nav") .. "/src/g3d/init.lua"))
      return chunk(use, nil)
    end)
    if ok and type(lib) == "table" then g3d = lib else g3dWhy = tostring(lib) end
    return g3d, g3dWhy
  end

  -- the stadium's shader: g3d's vertex shader and ours for the pixels: alpha below `alphaCut`
  -- discarded (the grass tufts, the crowd's gaps), the texture times the vertex colour
  local FRAG = [[
    uniform float alphaCut;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
      vec4 c = Texel(tex, uv) * color;
      if (c.a < alphaCut) discard;
      return c;
    }
  ]]

  -- ------- the device: a shader and a depth buffer, probed once

  local depthFmt
  local function makeDepth(w, h)
    local G = love.graphics
    for _, fmt in ipairs({ "depth24", "depth16", "depth24stencil8", "depth32f" }) do
      local ok, c = pcall(G.newCanvas, w, h, { format = fmt, readable = false, dpiscale = 1 })
      if ok and c then return c, fmt end
      ok, c = pcall(G.newCanvas, w, h, { format = fmt, dpiscale = 1 })
      if ok and c then return c, fmt end
    end
    return nil, nil
  end

  local probed = nil
  function A3.available()
    if probed ~= nil then return probed, A3.why end
    local G = love and love.graphics
    if not (G and G.newCanvas and G.newShader and G.setDepthMode and G.newMesh) then
      probed, A3.why = false, "no 3D drawing on this LOVE"
      return probed, A3.why
    end
    local lib, why = A3.g3d()
    if not lib then
      probed, A3.why = false, "g3d did not load (" .. tostring(why) .. ")"
      return probed, A3.why
    end
    local vert = mod:read("src/g3d/g3d.vert")
    local ok, sh = pcall(G.newShader, FRAG, vert)
    if not (ok and sh) then
      probed, A3.why = false, "the 3D shader did not compile (" .. tostring(sh) .. ")"
      return probed, A3.why
    end
    shader = sh
    local d, fmt = makeDepth(4, 4)
    depthFmt = fmt or "auto"
    if d then d:release() end
    probed = true
    return probed, nil
  end
  function A3.depthFormat() return depthFmt end

  -- ------- the scene: the card's stadium or the stand-in, built once

  local scene = nil
  function A3.resetScene() scene = nil end
  local function buildScene()
    local lib = A3.g3d()
    local A = A3.assets
    local model = A and A.model and A.model("st3d/stadium")
    if model and A3.cardScene then
      local ok, s = pcall(A3.cardScene, A3, lib, model, A)
      if ok and s then return s end
      if mod.log then mod.log:warn("3D SUPER TRAINING: the card's stadium did not build (%s); using the drawn one", tostring(s)) end
    end
    local Stand = A3.stand
    if not Stand then
      local src = mod:read("src/training/arena3d_stand.lua")
      Stand = assert(load(src, "@" .. (mod.path or "play_nav") .. "/src/training/arena3d_stand.lua"))()
      A3.stand = Stand
    end
    return Stand(A3, lib)
  end
  function A3.scene()
    if not scene then scene = buildScene() end
    return scene
  end

  -- ------- drawing the stadium into its canvas and onto the screen

  local color, depth, cw, ch = nil, nil, 0, 0
  local viewM, projM = {}, {}
  -- (reused each frame: setCanvas' table, the sky's fallback colour)
  local canvasArg, SKY = {}, { 0.45, 0.7, 0.95 }
  local hasCanvasFlag = nil
  function A3.lastSize() return cw, ch end

  -- the stadium under the sprites, over the screen rect ex, ey, ew, eh (240x160 units, in the
  -- current transform); true when drawn
  function A3.drawStadium(G2, ex, ey, ew, eh)
    local G = love.graphics
    if not A3.available() then return false end
    local sc = A3.scene()
    if not sc then return false end
    local lib = A3.g3d()
    -- the canvas at the rect's size in pixels (dpiscale 1: one texel a pixel)
    local x0, y0 = G2.transformPoint(ex, ey)
    local x1, y1 = G2.transformPoint(ex + ew, ey + eh)
    local dpi = G.getDPIScale and G.getDPIScale() or 1
    local w = math.max(16, math.floor(math.abs(x1 - x0) * dpi + 0.5))
    local h = math.max(16, math.floor(math.abs(y1 - y0) * dpi + 0.5))
    if w ~= cw or h ~= ch or not color then
      if color then color:release() end
      if depth then depth:release() end
      color = G.newCanvas(w, h, { dpiscale = 1 })
      color:setFilter("linear", "linear")
      depth = makeDepth(w, h)
      cw, ch = w, h
    end
    local cam = lib.camera
    A3.viewMatrix(cam.viewMatrix)
    A3.projectionMatrix(cam.projectionMatrix, ex, ey, ew, eh)
    G.push("all")
    G.setScissor()
    G.origin()
    canvasArg[1] = color
    if depth then canvasArg.depthstencil, canvasArg.depth = depth, nil
    else canvasArg.depthstencil, canvasArg.depth = nil, true end
    G.setCanvas(canvasArg)
    local sky = sc.clear or SKY
    G.clear(sky[1], sky[2], sky[3], 1, true, true)
    -- (in the ending the eye is under the grass: the card's stadium culls back faces, as the
    -- game; the drawn stand-in, wound both ways, keeps them and leaves its floor out instead)
    local skipFloor = ending and sc.standIn
    G.setMeshCullMode((ending and not sc.standIn) and A3.ENDING.CULL or "none")
    G.setBlendMode("alpha")
    G.setColor(1, 1, 1, 1)
    -- the shader and the camera's matrices once a frame (g3d's model:draw sends all three and
    -- swaps the shader per piece); a model matrix only when a piece's differs
    G.setShader(shader)
    shader:send("viewMatrix", cam.viewMatrix)
    shader:send("projectionMatrix", cam.projectionMatrix)
    if hasCanvasFlag == nil then hasCanvasFlag = shader:hasUniform("isCanvasEnabled") end
    if hasCanvasFlag then shader:send("isCanvasEnabled", true) end
    local lastM = nil
    -- far away first, with no depth (the sky's size would spend the depth buffer's precision),
    -- then the solid pieces, then the see-through ones (the game's render priority 256)
    for pass = 1, 3 do
      if pass == 1 then G.setDepthMode("always", false)
      elseif pass == 2 then G.setDepthMode("lequal", true)
      else G.setDepthMode("lequal", false) end
      shader:send("alphaCut", pass == 2 and 0.5 or 0.02)
      local pieces = sc.pieces
      for i = 1, #pieces do
        local piece = pieces[i]
        if piece.pass == pass and not (skipFloor and piece.floor) then
          local m = piece.model
          if m.matrix ~= lastM then shader:send("modelMatrix", m.matrix); lastM = m.matrix end
          G.draw(m.mesh)
        end
      end
    end
    G.setDepthMode()
    G.pop()
    G2.setColor(1, 1, 1, 1)
    G2.draw(color, ex, ey, 0, ew / w, eh / h)
    return true
  end

  -- ------- the card's stadium (a/1/1/4 entry 75, read by src/import/bch.lua M.model)

  -- drawn as stored (the game loads it with no transform: DllSparring.cro 0x7d4c-0x805c)
  A3.CARD = { CLEAR = { 0.55, 0.76, 0.96 } }

  -- one mesh as a g3d model: its triangles expanded, its texture repeated, its baked vertex
  -- colours kept; the 3DS's texture origin is bottom left, so v is turned over
  local function cardMesh(lib, me, image)
    local verts = {}
    local pos, uv, col, idx = me.pos, me.uv, me.col, me.idx
    for i = 1, #idx do
      local v = idx[i]
      local p, t, c = v * 3, v * 2, v * 4
      local r, g, b, a = 1, 1, 1, 1
      if col then r, g, b, a = col[c + 1], col[c + 2], col[c + 3], col[c + 4] end
      verts[i] = { pos[p + 1], pos[p + 2], pos[p + 3], uv[t + 1], 1 - uv[t + 2], 0, 1, 0, r, g, b, a }
    end
    return lib.newModel(verts, image)
  end

  -- the stadium's pieces from the extracted model and its textures (Assets "st3d/<texture>"):
  -- the sky first with no depth, the solid ones, then the game's render priority 256 (clouds,
  -- the dark pitch markings, a grass layer) see-through; the flags (rigid, posed only by the
  -- stadium's animation) are left out
  function A3.cardScene(_, lib, model, Assets)
    local pieces = {}
    for _, me in ipairs(model.meshes) do
      if me.skin ~= 1 and #me.idx >= 3 then
        local img = Assets.image("st3d/" .. tostring(me.texture))
        if img then
          img:setWrap("repeat", "repeat")
          img:setFilter("linear", "linear")
        end
        local pass = (me.texture == "spa_sky00") and 1 or ((me.priority or 0) >= 256 and 3 or 2)
        pieces[#pieces + 1] = { model = cardMesh(lib, me, img), pass = pass, texture = me.texture }
      end
    end
    if #pieces == 0 then return nil end
    return { clear = A3.CARD.CLEAR, pieces = pieces, card = true }
  end

  -- where the beaten balloon leaves the stadium: the Poke Ball over the far stand (model units)
  A3.EXIT = { x = 0, y = 401, z = -886 }

  return A3
end
