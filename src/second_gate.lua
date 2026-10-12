-- Who gets the second display. The engine hands every render.compose wrapper
-- the SecondScreen bridge in ctx.secondScreen (Kanto Gear takes it from
-- there every frame). PlayNav wraps render.compose first and passes the
-- proxy below instead. While PlayNav claims the screen, the proxy tells
-- downstream mods the display is gone (detected() false), swallows their
-- frames and leaves the touch queue to PlayNav. Released, it passes every
-- call through, and the display is enabled as the downstream mod last asked,
-- so it repaints there at once. Pure: no love calls.

local Gate = {}
Gate.__index = Gate

function Gate.new(real)
  local g = setmetatable({ real = real, claimed = false, wantedEnabled = nil }, Gate)
  local function pass(name, ...)
    local fn = real and real[name]
    if fn then return fn(...) end
  end
  g.proxy = {
    usable = function(...) return pass("usable", ...) end,
    available = function(...) return pass("available", ...) end,
    detected = function(...)
      if g.claimed then return false end
      return pass("detected", ...)
    end,
    push = function(...)
      if g.claimed then return true end
      return pass("push", ...)
    end,
    pollTouch = function(...)
      if g.claimed then return nil end
      return pass("pollTouch", ...)
    end,
    setEnabled = function(on, ...)
      g.wantedEnabled = on and true or false
      if g.claimed then return end
      return pass("setEnabled", on, ...)
    end,
  }
  return g
end

function Gate:claim()
  self.claimed = true
end

-- hands the display back: enabled as the downstream mod last asked (off when
-- nothing downstream ever asked, as before)
function Gate:release()
  if not self.claimed then return end
  self.claimed = false
  local fn = self.real and self.real.setEnabled
  if fn then pcall(fn, self.wantedEnabled or false) end
end

return Gate
