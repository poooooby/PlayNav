-- Two engine_internals jobs against src/core/TouchControls:
--
-- 1. Hide the built-in virtual pad while the surface owns the bottom of a
--    single screen. The pad draws full-window after every render hook and
--    takes first refusal on touches, so left alone it sits on top of the
--    surface. `enabled = false` stops both its drawing and its input; the
--    engine re-reads options on changes, so it is re-asserted every frame.
--
-- 2. On Gen 3, which has no input.pointer seam, route touches to the
--    surface by wrapping the TouchControls methods Game3 feeds every touch
--    through. A touch that begins on the surface is owned for its lifetime
--    and never reaches the pad; everything else passes to the original.

return function(mod)
  local ok, TC = pcall(require, "src.core.TouchControls")
  local H = {
    tc = (ok and type(TC) == "table") and TC or nil,
    hidden = false,
    prevEnabled = nil,
    warned = false,
  }
  if not H.tc then
    mod.log:warn("TouchControls unavailable (%s); the built-in pad cannot be hidden",
      tostring(TC))
  end

  function H:apply(active, game)
    local tc = self.tc
    if not tc then
      if active and not self.warned then
        self.warned = true
        mod.log:warn("turn the touch controls off in the launcher if the pad overlaps the surface")
      end
      return
    end
    if active then
      if not self.hidden then
        self.prevEnabled = tc.enabled
        self.hidden = true
      end
      if tc.enabled ~= false then
        tc.enabled = false
        pcall(tc.reset, tc)
      end
    elseif self.hidden then
      self.hidden = false
      local restored = false
      if game and type(game.options) == "table" and tc.applyOptions then
        restored = pcall(tc.applyOptions, tc, game.options)
      end
      if not restored then tc.enabled = self.prevEnabled end
    end
  end

  -- handler(phase, id, x, y, pressure) -> true when the surface took it
  function H:wrapTouch(handler)
    local tc = self.tc
    if not tc then return false end
    local w = rawget(tc, "__dsTouch")
    if not w then
      w = {
        press = tc.touchpressed, move = tc.touchmoved,
        release = tc.touchreleased, reset = tc.reset,
        owned = {}, handler = nil,
      }
      rawset(tc, "__dsTouch", w)
      tc.touchpressed = function(self_, id, x, y, ...)
        if id == "mouse" then w.sawMouse = true end
        local h = w.handler
        if h and h("pressed", id, x, y) then
          w.owned[id] = true
          return true
        end
        return w.press(self_, id, x, y, ...)
      end
      tc.touchmoved = function(self_, id, x, y, ...)
        if w.owned[id] then
          local h = w.handler
          if h then h("moved", id, x, y) end
          return true
        end
        return w.move(self_, id, x, y, ...)
      end
      tc.touchreleased = function(self_, id, x, y, ...)
        if w.owned[id] then
          w.owned[id] = nil
          local h = w.handler
          if h then h("released", id, x, y) end
          return true
        end
        return w.release(self_, id, x, y, ...)
      end
      tc.reset = function(self_, ...)
        if next(w.owned) then
          local h = w.handler
          for id in pairs(w.owned) do
            if h then h("cancelled", id, 0, 0) end
          end
          w.owned = {}
        end
        return w.reset(self_, ...)
      end
    end
    w.handler = handler
    return true
  end

  function H:unwrapTouch()
    local tc = self.tc
    local w = tc and rawget(tc, "__dsTouch")
    if w then w.handler = nil end
  end

  -- Gen 3 ignores a plain desktop mouse unless POKEPORT_TOUCH routes it
  -- through TouchControls. Wrap the Game3 class handlers so a left-button
  -- press that lands on the surface drives it too; once the touch route has
  -- been seen carrying the mouse (that env var is on), this path steps back
  -- so one click never arrives twice.
  function H:wrapMouse(handler)
    local ok, Game3 = pcall(require, "src.core.Game3")
    if not (ok and type(Game3) == "table" and Game3.mousepressed) then return false end
    local w = rawget(Game3, "__dsMouse")
    if not w then
      local tcw = self.tc and rawget(self.tc, "__dsTouch")
      w = { press = Game3.mousepressed, move = Game3.mousemoved, release = Game3.mousereleased,
        down = false, handler = nil }
      rawset(Game3, "__dsMouse", w)
      local function touchHasMouse()
        local t = self.tc and rawget(self.tc, "__dsTouch")
        return t and t.sawMouse
      end
      Game3.mousepressed = function(self_, x, y, button, istouch, ...)
        local r = w.press(self_, x, y, button, istouch, ...)
        if not istouch and button == 1 and not touchHasMouse() and w.handler then
          w.down = w.handler("pressed", x, y) == true
        end
        return r
      end
      Game3.mousemoved = function(self_, x, y, dx, dy, istouch, ...)
        local r = w.move(self_, x, y, dx, dy, istouch, ...)
        if w.down and not istouch and w.handler then w.handler("moved", x, y) end
        return r
      end
      Game3.mousereleased = function(self_, x, y, button, istouch, ...)
        local r = w.release(self_, x, y, button, istouch, ...)
        if w.down and not istouch and button == 1 and w.handler then
          w.down = false
          w.handler("released", x, y)
        end
        return r
      end
    end
    w.handler = handler
    return true
  end

  return H
end
