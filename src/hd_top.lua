-- The top screen at window resolution. PlayNav's top-screen layers (Pokemon-Amie,
-- Super Training) are Gen 3 UI-stack layers: the engine draws them into its 240x160 canvas
-- and blits that at a whole-number scale, which shrinks the ORAS art onto a coarse grid.
--
-- Gen 3's render.hud runs after the frame is on the window, with the rect the 240x160
-- picture landed in (viewport.gameX / gameY / gameWidth / gameHeight). When one of our
-- layers is the top of the stack, this draws that layer's scene again right there, under a
-- transform from 240x160 to the rect: the same drawing code, sampled at screen pixels. No
-- canvas, no capture. The layer module gets `hdLive = true` after a frame drawn this way, and
-- its own draw (inside the engine's pass) then paints only a backdrop; on any error the flag
-- clears and the next frame is the plain low-resolution draw again.
--
-- A layer opts in with `drawScene(G2)` (the scene in 240x160 units) and `backdrop(G2)`.
-- On the Game Boy games the frame is 160x144: the layers' 240-unit space covers it as
-- deps.frame (src/gen.lua profile.frame: 240 x 216 units, y -28 .. 188), the same scale across
-- and down, and a layer always gets it as its extent there.
-- deps: { HD, ids = { [layerId] = true }, frame, gb }

return function(mod, deps)
  local HD, ids = deps.HD, deps.ids or {}
  local M = { W = 240, H = 160, last = nil, failures = 0 }
  local frame = deps.frame or { x = 0, y = 0, w = 240, h = 160 }
  local gb = deps.gb == true
  M.frame = frame

  -- the engine's UI stack: M.Stack (main sets it from the game host, which required it);
  -- package.loaded is not the engine's inside the mod's sandbox
  local function stackTop()
    local Stack = M.Stack
    if not Stack and not gb then
      local ok, m = pcall(require, "src.ui.game3.stack")
      Stack = ok and type(m) == "table" and m or nil
      M.Stack = Stack
    end
    if not (Stack and Stack.top) then return nil end
    local ok, top = pcall(Stack.top)
    return ok and top or nil
  end

  -- the module of ours on top of the stack, or nil
  function M.topLayer()
    local top = stackTop()
    if top and ids[top.id] and type(top.mod) == "table" and top.mod.drawScene then return top.mod, top.id end
    return nil
  end

  -- the top layer paints the whole playfield (its `fillTop()` says so): main lays the top
  -- screen out as it does for the live overworld, and draw() hands the layer the playfield as
  -- `layer.extent` in 240x160 units. Only while this overlay draws (HD on, no failures), since
  -- the engine's own draw of a layer covers the 240x160 frame alone.
  -- M.playfield: main sets it, () -> { x, y, w, h } in window units or nil
  function M.wantsFill()
    if not (HD and HD.enabled and M.failures < 3) then return false end
    local layer = M.topLayer()
    if not (layer and layer.fillTop) then return false end
    local ok, v = pcall(layer.fillTop)
    return ok and v == true
  end

  local function standDown()
    if M.last then M.last.hdLive = false end
    M.last = nil
  end
  M.standDown = standDown

  -- render.hud: viewport = { gameX, gameY, gameWidth, gameHeight, scale }
  function M.draw(viewport)
    local G = love and love.graphics
    -- M.why: why the last frame was not drawn this way (for drivers and bug reports)
    if not (G and HD and HD.enabled and viewport and M.failures < 3) then
      M.why = not (HD and HD.enabled) and "hd off" or (not viewport and "no viewport" or "failures")
      standDown(); return false
    end
    local layer = M.topLayer()
    if not layer then M.why = "not our layer"; standDown(); return false end
    local gx, gy = viewport.gameX or 0, viewport.gameY or 0
    local gw, gh = viewport.gameWidth or 0, viewport.gameHeight or 0
    if gw < 1 or gh < 1 then M.why = "no game rect"; standDown(); return false end
    M.why = nil
    if M.last and M.last ~= layer then M.last.hdLive = false end
    local pf = M.playfield and M.wantsFill() and M.playfield() or nil
    local sx, sy = gw / frame.w, gh / frame.h
    G.push("all")
    G.origin()
    G.setShader()
    G.setBlendMode("alpha")
    if pf then
      G.setScissor(pf.x, pf.y, pf.w, pf.h)
      layer.extent = { x = frame.x + (pf.x - gx) / sx, y = frame.y + (pf.y - gy) / sy, w = pf.w / sx, h = pf.h / sy }
    else
      G.setScissor(gx, gy, gw, gh)
      layer.extent = gb and frame or nil
    end
    -- the touch screen inset over this screen (Kanto Gear's OVERLAY layout), in the layer's
    -- units: a filling layer keeps what matters out from under it (M.inset: main sets it,
    -- () -> { x, y, w, h } in window units or nil)
    local ins = pf and M.inset and M.inset() or nil
    layer.inset = ins and { x = frame.x + (ins.x - gx) / sx, y = frame.y + (ins.y - gy) / sy,
      w = ins.w / sx, h = ins.h / sy } or nil
    G.translate(gx - frame.x * sx, gy - frame.y * sy)
    G.scale(sx, sy)
    G.setColor(1, 1, 1, 1)
    local ok, err = pcall(layer.drawScene, G)
    G.pop()
    layer.extent, layer.inset = nil, nil
    if ok then
      layer.hdLive = true
      M.last = layer
      M.failures = 0
      return true
    end
    M.failures = M.failures + 1
    layer.hdLive = false
    M.last = nil
    mod.log:warn("top screen hd draw failed (%s); drawing it the plain way", tostring(err))
    return false
  end

  return M
end
