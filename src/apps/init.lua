-- The app registry: which consumer owns the surface right now, a tab strip
-- to switch between them, and the dispatch of pointer events into the active
-- app in app-local coordinates (the tab strip height subtracted).
--
-- App contract (all optional but draw):
--   id, title                      -- registry key and tab label
--   draw(G, w, h)                  -- in app space (w x h, below the tabs)
--   update(dt, game)               -- once per rendered frame
--   pointer(ev, rec, game)         -- ev in app space; rec is the live record
--   live -> bool                   -- true keeps the surface redrawing
--   leave(game)                    -- called when another app takes over
--   releaseAll(game)               -- let go of every held button

return function(mod, Pointer, Layout)
  local Apps = { list = {}, byId = {}, activeId = nil, TAB_H = 14 }

  function Apps:register(app)
    assert(type(app) == "table" and type(app.id) == "string" and app.id ~= "",
      "an app needs a string id")
    assert(type(app.draw) == "function", ("app %s needs draw(G, w, h)"):format(app.id))
    app.title = app.title or app.id:upper()
    app.tabH = self.TAB_H
    if not self.byId[app.id] then self.list[#self.list + 1] = app end
    self.byId[app.id] = app
    return app
  end

  function Apps:get(id) return self.byId[id] end

  function Apps:active()
    local app = self.activeId and self.byId[self.activeId]
    if app then return app end
    return self.list[1]
  end

  -- main.lua sets this to mark the surface dirty on a switch
  Apps.onChange = nil

  function Apps:setActive(id, game)
    if not self.byId[id] or id == self.activeId then return false end
    local old = self:active()
    if old and old.leave then pcall(old.leave, old, game) end
    self.activeId = id
    if self.onChange then pcall(self.onChange, id) end
    return true
  end

  function Apps:cycle(game)
    local n = #self.list
    if n == 0 then return end
    local current = self:active()
    local cur = 1
    for i, app in ipairs(self.list) do
      if app == current then cur = i end
    end
    self:setActive(self.list[cur % n + 1].id, game)
  end

  function Apps:tabAt(x, y, w)
    if y >= self.TAB_H or y < 0 or #self.list == 0 then return nil end
    local cell = w / #self.list
    local i = math.floor(x / cell) + 1
    if i < 1 or i > #self.list then return nil end
    return i
  end

  function Apps:update(dt, game)
    local app = self:active()
    if app and app.update then
      local ok, err = pcall(app.update, app, dt, game)
      if not ok then mod.log:warn("app %s update failed: %s", app.id, tostring(err)) end
    end
  end

  function Apps:live()
    local app = self:active()
    return app ~= nil and app.live == true
  end

  -- an app with `hideTabs` (a session screen that switches apps itself) gets no strip at
  -- all: it keeps its coordinates (app y 0 is surface y TAB_H) and paints its backdrop up
  -- into the strip's rows itself (`app.bleed`, see Apps:draw)
  local function drawTabs(self, G, w)
    local n = #self.list
    if n == 0 then return end
    local active = self:active()
    if active and active.hideTabs then return end
    local cell = w / n
    for i, app in ipairs(self.list) do
      local x = math.floor((i - 1) * cell)
      if app == active then
        G.setColor(0.18, 0.55, 0.85, 1)
      else
        G.setColor(0.13, 0.15, 0.2, 1)
      end
      G.rectangle("fill", x, 0, math.ceil(cell), self.TAB_H)
      G.setColor(1, 1, 1, app == active and 1 or 0.6)
      G.printf(app.title, x, 1, math.ceil(cell), "center")
    end
    G.setColor(0.25, 0.3, 0.4, 1)
    G.rectangle("fill", 0, self.TAB_H - 1, w, 1)
  end

  function Apps:draw(G, w, h)
    drawTabs(self, G, w)
    local app = self:active()
    if not app then
      G.setColor(1, 1, 1, 0.7)
      G.printf("No apps registered", 0, h / 2 - 6, w, "center")
      return
    end
    G.push("all")
    G.translate(0, self.TAB_H)
    G.setColor(1, 1, 1, 1)
    -- rows above the app's y 0 it may paint (its backdrop) when no strip is drawn
    app.bleed = app.hideTabs and self.TAB_H or 0
    if app.bleed > 0 then
      G.setColor(0.07, 0.08, 0.10, 1)
      G.rectangle("fill", 0, -app.bleed, w, app.bleed)
      G.setColor(1, 1, 1, 1)
    end
    local ok, err = pcall(app.draw, app, G, w, h - self.TAB_H)
    G.pop()
    if not ok then
      G.setColor(1, 0.4, 0.4, 1)
      G.printf(("%s: %s"):format(app.id, tostring(err)), 4, self.TAB_H + 4, w - 8, "left")
    end
  end

  -- ev: { phase, id, x, y, dx, dy, pressure, source } in surface space
  function Apps:pointer(ev, rec, game)
    -- the tab strip takes presses on its rows; a screen without it (hideTabs: Amie, the
    -- PLAYNAV gate) draws its own things there (header arrows, the PlayNav strip) and gets them
    local current = self:active()
    if ev.phase == "pressed" and ev.y < self.TAB_H and not (current and current.hideTabs) then
      local i = self:tabAt(ev.x, ev.y, Layout.W)
      if i then self:setActive(self.list[i].id, game) end
      rec.onTab = true
      return
    end
    if rec.onTab then return end
    local app = self:active()
    if not (app and app.pointer) then return end
    rec.ax, rec.ay = rec.x, rec.y - self.TAB_H
    local localEv = {
      phase = ev.phase, id = ev.id, source = ev.source, pressure = ev.pressure,
      x = ev.x, y = ev.y - self.TAB_H, dx = ev.dx, dy = ev.dy,
    }
    local ok, err = pcall(app.pointer, app, localEv, rec, game)
    if not ok then mod.log:warn("app %s pointer failed: %s", app.id, tostring(err)) end
  end

  -- every app lets go of whatever it holds (focus loss, mode change)
  function Apps:releaseAll(game)
    for _, app in ipairs(self.list) do
      if app.releaseAll then pcall(app.releaseAll, app, game) end
    end
  end

  return Apps
end
