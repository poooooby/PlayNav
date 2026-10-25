-- 3D AMIE (option amie_3d): PLAY's stage in 3D behind the same Pokemon sprite. The game's own
-- stage when the card's art is extracted - the CGFX model collision02 (a/1/0/1 entry 0, Amie's
-- 3D archive): a floor disc, a dotted sky cylinder, a rainbow, a ring of cumulus, a ring of small
-- clouds and a cylinder of bubbles, the clouds drifting and the bubbles rising by its material
-- animation - else a drawn stand-in built to the same measure from PlayNav's own pictures.
--
--   * the touch screen: the game's camera for the Pokemon's species (data/amie_cameras.lua,
--     its presets 0..3 from a/0/8/9), easing on entry from the average of presets 0 and 1 to
--     preset 1 as the game's script does; the stage's origin (where the game's Pokemon stands)
--     is shifted onto the sprite's feet (a lens shift: the camera's direction and distance
--     stay the game's), so PLAY's placement, petting and zoom are unchanged; the zoom draws the
--     visible part again, sharp;
--   * the top screen: the same stage through a camera at the same eye tilted up (the game's
--     upper screen looks up the sky cylinder: the dots, the small clouds, the rainbow, the
--     cumulus tops along its foot).
--
-- The field of view of both and the upper camera's tilt are fitted to Wooble's capture
-- (Play-Wake-Pet-Feed-MiniGameMenu.mp4), not read from the game.
--
-- Drawn by src/render3d.lua: rendered by St.prepare from the Amie layer's update (outside the
-- engine's draw; play.lua G.prepareStage) and only placed in the draw.
--   St = stage3d(mod, { Render3d, cameras, Assets })

return function(mod, deps)
  local St = { assets = deps.Assets, on = false, failed = false, why = nil }
  local CAMS = deps.cameras or {}
  local sqrt, sin, cos, rad, tan, floor = math.sqrt, math.sin, math.cos, math.rad, math.tan, math.floor

  --   FOVY      the touch screen's vertical field (degrees, over its 240 rows): fitted, 32
  --   TOP       the top screen: its field (over its 240 rows) and tilt up from the lower camera
  --   ENTER_S   the entry ease (presets 0 + 1 averaged -> preset 1)
  --   NEAR/FAR  the depth range (the sky cylinder is 468 across, the far cameras ~1000 out)
  --   DEFAULT   a camera for a species with no record (Bulbasaur's preset 1)
  St.FOVY = 32
  St.TOP = { FOVY = 22, PITCH = 27 }
  St.ENTER_S = 1.2
  St.NEAR, St.FAR = 4, 6000
  St.DEFAULT = { -2, 70, 294, 0, 33, 3 }
  -- the stage's material animation (collision02, 1000 frames at 30 a second): the small clouds
  -- drift once round in U, the cumulus sway 0 <-> 0.05 every 100 frames, the bubbles rise in V
  St.ANIM = { FRAMES = 1000, FPS = 30, SWAY = 0.05, SWAY_F = 100 }
  St.CLEAR = { 0.8, 0.89, 1 }

  -- ------- the cameras

  local function presets(national)
    local p = CAMS[national or 0]
    if type(p) ~= "table" or #p < 12 then return nil end
    return p
  end
  -- preset k (0-based) of a record: eye x, y, z, interest x, y, z
  local function preset(p, k)
    local o = k * 6
    return p[o + 1], p[o + 2], p[o + 3], p[o + 4], p[o + 5], p[o + 6]
  end

  -- one camera: its eye and look-at, the view rows (g3d's layout), focal length and centre
  local function newCam() return { m = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }, F = 200, CX = 160, CY = 120 } end
  local low, top = newCam(), newCam()

  local function lookAt(c, ex, ey, ez, tx, ty, tz)
    local zx, zy, zz = ex - tx, ey - ty, ez - tz
    local l = sqrt(zx * zx + zy * zy + zz * zz)
    zx, zy, zz = zx / l, zy / l, zz / l
    local xx, xy, xz = zz, 0, -zx
    l = sqrt(xx * xx + xz * xz)
    xx, xz = xx / l, xz / l
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
    local m = c.m
    m[1], m[2], m[3], m[4] = xx, xy, xz, -(xx * ex + xy * ey + xz * ez)
    m[5], m[6], m[7], m[8] = yx, yy, yz, -(yx * ex + yy * ey + yz * ez)
    m[9], m[10], m[11], m[12] = zx, zy, zz, -(zx * ex + zy * ey + zz * ez)
  end

  -- a point of the stage -> the camera's screen x, y and its distance in front of the eye
  local function project(c, X, Y, Z)
    local m = c.m
    local vx = m[1] * X + m[2] * Y + m[3] * Z + m[4]
    local vy = m[5] * X + m[6] * Y + m[7] * Z + m[8]
    local d = -(m[9] * X + m[10] * Y + m[11] * Z + m[12])
    if d < 1e-3 then d = 1e-3 end
    return c.CX + vx * c.F / d, c.CY - vy * c.F / d, d
  end
  St.project = function(X, Y, Z) return project(low, X, Y, Z) end
  St.projectTop = function(X, Y, Z) return project(top, X, Y, Z) end

  local function viewMatrix(c)
    return function(out)
      local m = c.m
      for i = 1, 12 do out[i] = m[i] end
      out[13], out[14], out[15], out[16] = 0, 0, 0, 1
      return out
    end
  end
  local function projectionMatrix(c)
    return function(out, ex, ey, ew, eh)
      local n, f = St.NEAR, St.FAR
      local l, r = (ex - c.CX) / c.F * n, (ex + ew - c.CX) / c.F * n
      local t, b = (c.CY - ey) / c.F * n, (c.CY - (ey + eh)) / c.F * n
      out[1], out[2], out[3], out[4] = 2 * n / (r - l), 0, (r + l) / (r - l), 0
      out[5], out[6], out[7], out[8] = 0, 2 * n / (t - b), (t + b) / (t - b), 0
      out[9], out[10], out[11], out[12] = 0, 0, -(f + n) / (f - n), -2 * f * n / (f - n)
      out[13], out[14], out[15], out[16] = 0, 0, -1, 0
      return out
    end
  end

  -- the eye and look-at now: the species' entry view easing into its play view
  local cam = { national = nil, t = 0, ex = 0, ey = 70, ez = 294, ix = 0, iy = 33, iz = 3 }
  St.cam = cam
  local footX, footY, frameB = 160, 220, 240   -- the sprite's feet and the screen's foot (scene units)

  -- a new visit (St.enter) or another Pokemon: the ease starts over
  function St.enter(national)
    cam.national, cam.t = national, 0
  end
  function St.setFoot(x, y, bottom) footX, footY, frameB = x, y, bottom or frameB end

  local function placeLow()
    local p = presets(cam.national)
    local e0x, e0y, e0z, i0x, i0y, i0z
    local e1x, e1y, e1z, i1x, i1y, i1z
    if p then
      local ax, ay, az, bx, by, bz = preset(p, 0)
      e1x, e1y, e1z, i1x, i1y, i1z = preset(p, 1)
      e0x, e0y, e0z = (ax + e1x) / 2, (ay + e1y) / 2, (az + e1z) / 2
      i0x, i0y, i0z = (bx + i1x) / 2, (by + i1y) / 2, (bz + i1z) / 2
    else
      local D = St.DEFAULT
      e1x, e1y, e1z, i1x, i1y, i1z = D[1], D[2], D[3], D[4], D[5], D[6]
      e0x, e0y, e0z, i0x, i0y, i0z = e1x, e1y, e1z, i1x, i1y, i1z
    end
    local u = math.min(1, cam.t / St.ENTER_S)
    u = u * u * (3 - 2 * u)
    cam.ex, cam.ey, cam.ez = e0x + (e1x - e0x) * u, e0y + (e1y - e0y) * u, e0z + (e1z - e0z) * u
    cam.ix, cam.iy, cam.iz = i0x + (i1x - i0x) * u, i0y + (i1y - i0y) * u, i0z + (i1z - i0z) * u
    lookAt(low, cam.ex, cam.ey, cam.ez, cam.ix, cam.iy, cam.iz)
    -- the field over the 3DS screen's 240 rows; the stage's origin onto the sprite's feet
    low.F = 120 / tan(rad(St.FOVY) / 2)
    low.CX, low.CY = 0, 0
    local ox, oy = project(low, 0, 0, 0)
    low.CX, low.CY = footX - ox, footY - oy
  end

  -- the top screen: the same eye, tilted up by TOP.PITCH, the game's 400x240 view (5:3) fitted
  -- to the area it fills (topRect, its last draw's: 240x160 units, can reach past the frame) -
  -- its width on a wider area, so the rainbow keeps the view's bottom right corner on a wide
  -- screen, its height on a taller one - about the area's middle
  local topRect = { 0, 0, 240, 160 }
  St.ASPECT = 400 / 240
  local function placeTop()
    local fx, fy, fz = cam.ix - cam.ex, cam.iy - cam.ey, cam.iz - cam.ez
    local l = sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / l, fy / l, fz / l
    local hl = sqrt(fx * fx + fz * fz)
    local pitch = math.atan2(fy, hl) + rad(St.TOP.PITCH)
    local tx = cam.ex + fx / hl * cos(pitch) * 100
    local tz = cam.ez + fz / hl * cos(pitch) * 100
    local ty = cam.ey + sin(pitch) * 100
    lookAt(top, cam.ex, cam.ey, cam.ez, tx, ty, tz)
    local tv = tan(rad(St.TOP.FOVY) / 2)
    local ex, ey, ew, eh = topRect[1], topRect[2], topRect[3], topRect[4]
    if ew / eh > St.ASPECT then top.F = (ew / 2) / (tv * St.ASPECT) else top.F = (eh / 2) / tv end
    top.CX, top.CY = ex + ew / 2, ey + eh / 2
  end

  -- both cameras where the next draw puts them (the tests ask too)
  function St.placeCameras() placeLow(); placeTop() end

  -- ------- the stage's material animation, its clock the game's frames

  local clockF = 0
  local animate
  function St.update(dt)
    clockF = (clockF + (dt or 0) * St.ANIM.FPS) % (St.ANIM.FRAMES * 2)
    cam.t = cam.t + (dt or 0)
  end
  function St.animate(scene) return animate(scene) end
  function animate(scene)
    local A = St.ANIM
    local f = clockF % A.FRAMES
    for _, piece in ipairs(scene.pieces) do
      local kind, uv = piece.anim, piece.uv
      if kind == "drift" then uv[1] = -(f / A.FRAMES)
      elseif kind == "sway" then uv[1] = A.SWAY * (1 - cos(math.pi * clockF / A.SWAY_F)) / 2
      -- (v is turned over for LOVE: the game's rise in V is a fall in ours)
      elseif kind == "rise" then uv[2] = -(f / A.FRAMES) end
    end
  end

  -- ------- the renderers (one per screen: their cameras differ)

  local Rl, Rt = nil, nil
  local function renderers()
    if Rl then return Rl, Rt end
    local make = deps.Render3d
    Rl = make(mod, { name = "3D AMIE stage", camera = { view = viewMatrix(low), projection = projectionMatrix(low) } })
    Rt = make(mod, { name = "3D AMIE sky", camera = { view = viewMatrix(top), projection = projectionMatrix(top) } })
    return Rl, Rt
  end
  function St.available()
    if St.failed then return false, St.why end
    local R = renderers()
    local ok, why = R.available()
    if not ok then St.why = why end
    return ok, why
  end

  -- ------- the scene: the card's stage or the stand-in, built once (in an update step: the
  -- stand-in draws its pictures into canvases)

  local scene = nil
  function St.resetScene() scene = nil end
  St.ORDER = { collision02_skyw = 1, collision02_rainbow = 2, collision02_kumo = 3, collision02_kumo3 = 4,
    collision02_shabon = 5 }
  St.ANIM_OF = { collision02_kumo3 = "drift", collision02_kumo = "sway", collision02_shabon = "rise" }

  local function cardScene(R, model, Assets)
    local pieces = {}
    for _, me in ipairs(model.meshes) do
      if #me.idx >= 3 then
        local img = Assets.image("amie3d/" .. tostring(me.texture))
        if img then
          -- (the rainbow's v runs -1..1: repeated, a second rainbow shows that the game has not)
          if me.name == "collision02_rainbow" then img:setWrap("clamp", "clamp") else img:setWrap("repeat", "repeat") end
          img:setFilter("linear", "linear")
        end
        local anim = St.ANIM_OF[me.name]
        pieces[#pieces + 1] = { model = R.modelMesh(me, img), pass = (me.priority or 0) == 0 and 2 or 3,
          name = me.name, order = St.ORDER[me.name] or 0, anim = anim, uv = anim and { 0, 0 } or nil }
      end
    end
    if #pieces == 0 then return nil end
    table.sort(pieces, function(a, b) return a.order < b.order end)
    return { clear = St.CLEAR, pieces = pieces, card = true }
  end

  function St.scene()
    if scene then return scene end
    local R = renderers()
    local A = St.assets
    local model = A and A.model and A.model("amie3d/stage")
    if model then
      local ok, s = pcall(cardScene, R, model, A)
      if ok and s then scene = s; return scene end
      if mod.log then mod.log:warn("3D AMIE: the card's stage did not build (%s); using the drawn one", tostring(s)) end
    end
    local Stand = St.stand
    if not Stand then
      local src = mod:read("src/amie/stage3d_stand.lua")
      Stand = assert(load(src, "@" .. (mod.path or "play_nav") .. "/src/amie/stage3d_stand.lua"))()
      St.stand = Stand
    end
    local ok, s = pcall(Stand, St, R, A)
    if ok and s then scene = s else
      St.failed, St.why = true, "the drawn stage did not build (" .. tostring(s) .. ")"
      if mod.log then mod.log:warn("3D AMIE: %s; PLAY stays 2D", St.why) end
    end
    return scene
  end

  -- ------- update and draw

  -- in an update step: both screens' pictures, with the cameras as the draw will have them; ex,
  -- ey, ew, eh the touch screen's visible rect the draw will ask for (PLAY's view, already eased
  -- this update), so the picture placed is the one for this frame
  local lowRect = { 0, 0, 0, 0 }
  local function setLow(tg)
    if lowRect[3] > 0 then tg.ex, tg.ey, tg.ew, tg.eh = lowRect[1], lowRect[2], lowRect[3], lowRect[4] end
  end
  function St.prepare(ex, ey, ew, eh)
    if not St.available() then return false end
    local sc = St.scene()
    if not sc then return false end
    lowRect[1], lowRect[2], lowRect[3], lowRect[4] = ex or 0, ey or 0, ew or 0, eh or 0
    animate(sc)
    placeLow()
    placeTop()
    local R, T = renderers()
    R.prepare(sc, setLow)
    T.prepare(sc)
    return true
  end

  -- PLAY's stage over the visible rect ex, ey, ew, eh (scene units, under PLAY's view); false
  -- when it cannot be drawn (the caller draws its 2D scene)
  function St.drawLower(G2, ex, ey, ew, eh)
    if not (scene and St.available()) then return false end
    local R = renderers()
    return R.draw(G2, scene, ex, ey, ew, eh)
  end
  -- the top screen's sky over its extent (240x160 units)
  function St.drawTop(G2, ex, ey, ew, eh)
    if not (scene and St.available()) then return false end
    topRect[1], topRect[2], topRect[3], topRect[4] = ex, ey, ew, eh
    local _, T = renderers()
    return T.draw(G2, scene, ex, ey, ew, eh)
  end
  function St.stats()
    local R, T = renderers()
    return R.stats, T.stats
  end

  return St
end
