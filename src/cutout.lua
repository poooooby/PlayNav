-- Where the Gen 3 picture goes. Game3 fits its 240x160 frame into whatever
-- rectangle src/render/Playfield.cutout reports (the touch skin's viewport
-- when a skin is active, else nil and the engine's own centring). While the
-- surface splits a single screen, the mod hands the engine the picture area
-- of the stacked layout instead, so picture and surface never overlap and
-- both follow the window size. engine_internals: one module function wrapped.

return function(mod)
  local okPF, Playfield = pcall(require, "src.render.Playfield")
  local C = {
    pf = (okPF and type(Playfield) == "table") and Playfield or nil,
    rect = nil,
    wrapped = false,
    original = nil,
  }
  if not C.pf then
    mod.log:warn("Playfield unavailable (%s); the Gen 3 picture keeps the engine's placement", tostring(Playfield))
  end

  local function wrap()
    if C.wrapped or not C.pf then return end
    local pf = C.pf
    local w = rawget(pf, "__dsCutout")
    if w then
      C.original = w.original
      w.owner = C
    else
      w = { original = pf.cutout, owner = C }
      rawset(pf, "__dsCutout", w)
      C.original = w.original
      pf.cutout = function(sw, sh, ...)
        local o = w.owner
        local r = o and o.rect
        if r and type(sw) == "number" and type(sh) == "number" then
          -- the rect is in window units; the renderer asks in physical pixels (sw, sh = the
          -- framebuffer), Display.fit in units: answer in the caller's own measure
          local x, y, rw, rh = r.x, r.y, r.w, r.h
          local G = love and love.graphics
          if G and G.getDimensions then
            local okD, uw, uh = pcall(G.getDimensions)
            if okD and uw and uh and uw > 0 and uh > 0 then
              local fx, fy = sw / uw, sh / uh
              x, y, rw, rh = x * fx, y * fy, rw * fx, rh * fy
            end
          end
          if x + rw > sw then rw = sw - x end
          if y + rh > sh then rh = sh - y end
          if rw >= 1 and rh >= 1 then return x, y, rw, rh, false, false end
        end
        return w.original(sw, sh, ...)
      end
    end
    C.wrapped = true
  end

  -- rect = { x, y, w, h } in window space, or nil to hand placement back
  function C:set(rect)
    if rect then wrap() end
    if not self.wrapped then return false end
    local old = self.rect
    if rect == nil and old == nil then return true end
    if rect and old and rect.x == old.x and rect.y == old.y and rect.w == old.w and rect.h == old.h then return true end
    self.rect = rect and { x = rect.x, y = rect.y, w = rect.w, h = rect.h } or nil
    return true
  end

  function C:active() return self.rect ~= nil end

  return C
end
