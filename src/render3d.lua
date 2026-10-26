-- A 3D scene drawn by g3d (src/g3d, vendored) into a canvas of its own with a depth buffer (the
-- window has none), then placed as a picture: 3D SUPER TRAINING's stadium and 3D AMIE's stage.
--
--   local R = Render3d(mod, { name, camera = { view = fn(out), projection = fn(out, ex, ey, ew, eh) },
--     state = fn() -> cull mode | nil, skip(piece) | nil })
--   R.available()               probes the device once (g3d, the shader, a depth canvas)
--   R.g3d()                     the g3d library (models: lib.newModel(verts, image))
--   R.draw(G2, scene, ex, ey, ew, eh, view)   the scene over that rect (units of the current
--                               transform): the picture R.prepare last rendered for this size,
--                               placed over the rect it was rendered for; never rendered yet,
--                               the rect is filled with the scene's sky colour this once (the
--                               next update renders it); view { x, y, w, h } is noted on it
--   R.prepare(scene, setup)     renders each size drawn in the last second now, in the update
--                               step, outside any canvas; setup(target) puts the camera where
--                               the draw will (target.vx..vh: the view noted)
--   R.stats                     { prepared, placed, inline (rendered in the draw: 0), waiting
--                               (the sky colour while a size awaits its first render) }
--
-- A scene is { clear = { r, g, b } | nil, pieces = { { model, pass = 1 | 2 | 3, uv = { u, v } |
-- nil, ... } } }: pass 1 far away with no depth (a sky), 2 solid (depth written, alpha below 0.5
-- discarded), 3 see-through (depth tested, not written), each pass in list order.
--
-- Switching to a canvas in the middle of drawing into another left the rest of the frame drawn
-- small in a corner on Android (the AYN Thor), so owners prepare in an update step the ENGINE
-- calls outside its draw (a layer's update - not PlayNav's tick, which runs from render.hud,
-- inside the draw) and the draw only places the picture.

return function(mod, opts)
  local R = { failed = false, why = nil, stats = { prepared = 0, placed = 0, inline = 0, waiting = 0 } }
  local name = opts.name or "3D"
  local camera = opts.camera
  local state = opts.state

  -- ------- g3d (loaded once, from this mod's src/g3d; a mod cannot require its own files)

  local g3d, g3dWhy = nil, nil
  function R.g3d()
    if g3d or g3dWhy then return g3d, g3dWhy end
    local function use(file, lib)
      local path = "src/g3d/" .. file .. ".lua"
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

  -- g3d's vertex shader and ours for the pixels: alpha below `alphaCut` discarded (grass tufts,
  -- the crowd's gaps), the texture (its coordinates shifted by `uvShift`: drifting clouds) times
  -- the vertex colour
  local FRAG = [[
    uniform float alphaCut;
    uniform vec2 uvShift;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
      vec4 c = Texel(tex, uv + uvShift) * color;
      if (c.a < alphaCut) discard;
      return c;
    }
  ]]

  -- ------- the device: a shader and a depth buffer, probed once

  local shader, depthFmt
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
  function R.available()
    if probed ~= nil then return probed, R.why end
    local G = love and love.graphics
    if not (G and G.newCanvas and G.newShader and G.setDepthMode and G.newMesh) then
      probed, R.why = false, "no 3D drawing on this LOVE"
      return probed, R.why
    end
    local lib, why = R.g3d()
    if not lib then
      probed, R.why = false, "g3d did not load (" .. tostring(why) .. ")"
      return probed, R.why
    end
    local vert = mod:read("src/g3d/g3d.vert")
    local ok, sh = pcall(G.newShader, FRAG, vert)
    if not (ok and sh) then
      probed, R.why = false, "the 3D shader did not compile (" .. tostring(sh) .. ")"
      return probed, R.why
    end
    shader = sh
    local d, fmt = makeDepth(4, 4)
    depthFmt = fmt or "auto"
    if d then d:release() end
    probed = true
    return probed, nil
  end
  function R.depthFormat() return depthFmt end

  -- ------- targets: one colour + depth pair per size, two sizes kept (a scene can be drawn both
  -- into a low-resolution picture and onto the window; alternating must not rebuild canvases)

  local targets = {}   -- w * 65536 + h -> { color, depth, used, seen, ex.., prepared }
  local current = nil  -- the last target drawn
  local maxTex = nil   -- the GPU's largest texture side (capped at 4096)
  local prepId = 0     -- R.prepare's count: a target rendered by the latest has .prepared == it
  local canvasArg, SKY, ZERO = {}, { 0.45, 0.7, 0.95 }, { 0, 0 }
  local hasCanvasFlag = nil
  function R.lastSize() if current then return current.w, current.h end return 0, 0 end

  local renderInto

  -- a uniform sent only when its value differs from the one the shader already holds (a
  -- shader keeps its uniforms; each Shader:send of a table makes ~0.4 KB of Lua garbage in
  -- LOVE 11, and the scene sent ~16 a frame)
  local held = {}
  local function sendIf(name, v)
    local h = held[name]
    if type(v) == "table" then
      local same = h ~= nil
      if same then
        for i = 1, #v do if h[i] ~= v[i] then same = false; break end end
      end
      if same then return end
      h = h or {}
      for i = 1, #v do h[i] = v[i] end
      held[name] = h
    else
      if h == v then return end
      held[name] = v
    end
    shader:send(name, v)
  end

  function R.draw(G2, scene, ex, ey, ew, eh, view)
    local G = love.graphics
    if not (scene and R.available()) then return false end
    -- the canvas at the rect's size in pixels (dpiscale 1: one texel a pixel); units -> pixels by
    -- the window's DPI on the window, the canvas' own inside one (as hd.outputScale)
    local x0, y0 = G2.transformPoint(ex, ey)
    local x1, y1 = G2.transformPoint(ex + ew, ey + eh)
    local outer = G.getCanvas and G.getCanvas() or nil
    if type(outer) == "table" then outer = outer[1] end
    local dpi
    if outer and outer.getDPIScale then dpi = outer:getDPIScale() or 1
    else dpi = G.getDPIScale and G.getDPIScale() or 1 end
    local w = math.max(16, math.floor(math.abs(x1 - x0) * dpi + 0.5))
    local h = math.max(16, math.floor(math.abs(y1 - y0) * dpi + 0.5))
    -- never past the GPU's largest texture (an oversized target left the viewport wrong for the
    -- rest of the frame on a phone)
    if not maxTex then
      local ok, lim = pcall(G.getSystemLimits)
      maxTex = ok and lim and lim.texturesize or 4096
      maxTex = math.min(maxTex, 4096)
    end
    if w > maxTex or h > maxTex then
      local k = maxTex / math.max(w, h)
      w, h = math.max(16, math.floor(w * k)), math.max(16, math.floor(h * k))
    end
    local now = love.timer and love.timer.getTime() or 0
    local key = w * 65536 + h
    local tg = targets[key]
    if not tg then
      if mod.log then
        local winW, winH = G.getDimensions()
        mod.log:info("%s canvas %dx%d px (rect %.1fx%.1f units, dpi %.3f, %s, window %dx%d)", name, w, h,
          math.abs(x1 - x0), math.abs(y1 - y0), dpi, outer and "in a canvas" or "on the window", winW, winH)
      end
      local n, oldest, oldKey = 0, math.huge, nil
      for k2, t in pairs(targets) do
        n = n + 1
        if t.used < oldest then oldest, oldKey = t.used, k2 end
      end
      if n >= 2 and oldKey then
        local t = targets[oldKey]
        if t.color then t.color:release() end
        if t.depth then t.depth:release() end
        targets[oldKey] = nil
      end
      local color = G.newCanvas(w, h, { dpiscale = 1 })
      color:setFilter("linear", "linear")
      tg = { color = color, depth = makeDepth(w, h), w = w, h = h }
      targets[key] = tg
    end
    tg.used, tg.seen = now, now
    tg.ex, tg.ey, tg.ew, tg.eh = ex, ey, ew, eh
    if view then tg.vx, tg.vy, tg.vw, tg.vh = view.x, view.y, view.w, view.h end
    current = tg
    -- never rendered here: a canvas switched to in the middle of drawing (inside the engine's
    -- frame canvas, or PlayNav's touch screen's) left the rest of the frame drawn small in a
    -- corner on Android
    if not tg.rw then
      local sky = scene.clear or SKY
      G2.setColor(sky[1], sky[2], sky[3], 1)
      G2.rectangle("fill", ex, ey, ew, eh)
      R.stats.waiting = R.stats.waiting + 1
      return true
    end
    R.stats.placed = R.stats.placed + 1
    G2.setColor(1, 1, 1, 1)
    G2.draw(tg.color, tg.rx, tg.ry, 0, tg.rw / w, tg.rh / h)
    return true
  end

  -- the scene into a target's canvases through the owner's camera as it is now, for the rect it
  -- notes (tg.ex..); the rect rendered is kept (tg.rx..) for the draw to place it over
  function renderInto(tg, scene)
    local G = love.graphics
    local lib = R.g3d()
    local cam = lib.camera
    camera.view(cam.viewMatrix)
    camera.projection(cam.projectionMatrix, tg.ex, tg.ey, tg.ew, tg.eh)
    tg.rx, tg.ry, tg.rw, tg.rh = tg.ex, tg.ey, tg.ew, tg.eh
    local cull, skip = nil, nil
    if state then cull, skip = state(scene) end
    G.push("all")
    G.setScissor()
    G.origin()
    canvasArg[1] = tg.color
    if tg.depth then canvasArg.depthstencil, canvasArg.depth = tg.depth, nil
    else canvasArg.depthstencil, canvasArg.depth = nil, true end
    G.setCanvas(canvasArg)
    local sky = scene.clear or SKY
    G.clear(sky[1], sky[2], sky[3], 1, true, true)
    G.setMeshCullMode(cull or "none")
    G.setBlendMode("alpha")
    G.setColor(1, 1, 1, 1)
    -- the shader and the camera's matrices once a frame (g3d's model:draw sends all three and
    -- swaps the shader per piece); a model matrix / shift only when a piece's differs
    G.setShader(shader)
    sendIf("viewMatrix", cam.viewMatrix)
    sendIf("projectionMatrix", cam.projectionMatrix)
    if hasCanvasFlag == nil then hasCanvasFlag = shader:hasUniform("isCanvasEnabled") end
    if hasCanvasFlag then sendIf("isCanvasEnabled", true) end
    for pass = 1, 3 do
      if pass == 1 then G.setDepthMode("always", false)
      elseif pass == 2 then G.setDepthMode("lequal", true)
      else G.setDepthMode("lequal", false) end
      sendIf("alphaCut", pass == 2 and 0.5 or 0.02)
      local pieces = scene.pieces
      for i = 1, #pieces do
        local piece = pieces[i]
        if piece.pass == pass and not (skip and skip(piece)) then
          local m = piece.model
          sendIf("modelMatrix", m.matrix)
          sendIf("uvShift", piece.uv or ZERO)
          G.draw(m.mesh)
        end
      end
    end
    G.setDepthMode()
    G.pop()
  end

  function R.prepare(scene, setup)
    if not (scene and R.available()) then return false end
    local now = love.timer and love.timer.getTime() or 0
    prepId = prepId + 1
    for _, tg in pairs(targets) do
      if tg.seen and now - tg.seen < 1 and tg.ew then
        if setup then setup(tg) end
        renderInto(tg, scene)
        tg.prepared = prepId
        R.stats.prepared = R.stats.prepared + 1
      end
    end
    return true
  end

  -- one mesh of an extracted model (src/import/bch.lua's tables) as a g3d model: its triangles
  -- expanded, its baked vertex colours kept; the 3DS's texture origin is bottom left, so v is
  -- turned over
  function R.modelMesh(me, image)
    local lib = R.g3d()
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

  return R
end
