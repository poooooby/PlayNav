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
-- deps: { HD, ids = { [layerId] = true } }

return function(mod, deps)
  local HD, ids = deps.HD, deps.ids or {}
  local M = { W = 240, H = 160, last = nil, failures = 0 }

  local function stackTop()
    local Stack = package.loaded["src.ui.game3.stack"]
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

  local function standDown()
    if M.last then M.last.hdLive = false end
    M.last = nil
  end
  M.standDown = standDown

  -- render.hud: viewport = { gameX, gameY, gameWidth, gameHeight, scale }
  function M.draw(viewport)
    local G = love and love.graphics
    if not (G and HD and HD.enabled and viewport and M.failures < 3) then standDown(); return false end
    local layer = M.topLayer()
    if not layer then standDown(); return false end
    local gx, gy = viewport.gameX or 0, viewport.gameY or 0
    local gw, gh = viewport.gameWidth or 0, viewport.gameHeight or 0
    if gw < 1 or gh < 1 then standDown(); return false end
    if M.last and M.last ~= layer then M.last.hdLive = false end
    G.push("all")
    G.origin()
    G.setShader()
    G.setBlendMode("alpha")
    G.setScissor(gx, gy, gw, gh)
    G.translate(gx, gy)
    G.scale(gw / M.W, gh / M.H)
    G.setColor(1, 1, 1, 1)
    local ok, err = pcall(layer.drawScene, G)
    G.pop()
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
