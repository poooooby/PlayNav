-- The pointer stream: the part of this mod a Pokemon-Amie style minigame
-- will build on. Every LOVE / second-screen event updates a per-pointer
-- record the moment it arrives (nothing is sampled once per tick), so a
-- stylus drag reads as the continuous path it is.
--
-- Coordinates here are already logical surface units (0..256, 0..192).

return function(mod)
  local P = {
    records = {},
    listeners = {},
    history = 64,      -- path points kept per pointer
    count = 0,         -- pointers currently down
  }

  local function now()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
  end
  P.now = now

  local function emit(self, ev, rec)
    for _, fn in ipairs(self.listeners) do
      local ok, err = pcall(fn, ev, rec)
      if not ok then mod.log:warn("pointer listener failed: %s", tostring(err)) end
    end
  end

  function P:on(fn)
    self.listeners[#self.listeners + 1] = fn
    return fn
  end

  function P:off(fn)
    for i = #self.listeners, 1, -1 do
      if self.listeners[i] == fn then table.remove(self.listeners, i) end
    end
  end

  function P:get(id) return self.records[id] end

  function P:each() return pairs(self.records) end

  function P:any() return next(self.records) ~= nil end

  function P:begin(id, x, y, source, pressure)
    if self.records[id] then self:cancel(id) end
    local t = now()
    local rec = {
      id = id, source = source or "touch",
      x = x, y = y, px = x, py = y,
      startX = x, startY = y,
      downAt = t, lastAt = t, upAt = nil,
      pressure = pressure,
      vx = 0, vy = 0,
      travel = 0, moves = 0,
      path = { { x = x, y = y, t = t } },
    }
    self.records[id] = rec
    self.count = self.count + 1
    emit(self, { phase = "pressed", id = id, x = x, y = y, dx = 0, dy = 0,
      pressure = pressure, source = rec.source }, rec)
    return rec
  end

  function P:move(id, x, y, pressure)
    local rec = self.records[id]
    if not rec then return nil end
    local t = now()
    local dt = t - rec.lastAt
    local dx, dy = x - rec.x, y - rec.y
    rec.px, rec.py = rec.x, rec.y
    rec.x, rec.y = x, y
    if pressure ~= nil then rec.pressure = pressure end
    rec.travel = rec.travel + math.sqrt(dx * dx + dy * dy)
    rec.moves = rec.moves + 1
    if dt > 0 then
      -- exponential moving average with a ~50 ms time constant: smooth
      -- enough to read as a velocity, quick enough to follow a flick
      local a = math.min(1, dt / 0.05)
      rec.vx = rec.vx + (dx / dt - rec.vx) * a
      rec.vy = rec.vy + (dy / dt - rec.vy) * a
    end
    rec.lastAt = t
    local path = rec.path
    path[#path + 1] = { x = x, y = y, t = t }
    if #path > self.history then table.remove(path, 1) end
    emit(self, { phase = "moved", id = id, x = x, y = y, dx = dx, dy = dy,
      pressure = rec.pressure, source = rec.source }, rec)
    return rec
  end

  local function close(self, id, phase, x, y)
    local rec = self.records[id]
    if not rec then return nil end
    if x and y and (x ~= rec.x or y ~= rec.y) then
      rec.px, rec.py = rec.x, rec.y
      rec.x, rec.y = x, y
    end
    rec.upAt = now()
    self.records[id] = nil
    self.count = math.max(0, self.count - 1)
    emit(self, { phase = phase, id = id, x = rec.x, y = rec.y, dx = 0, dy = 0,
      pressure = rec.pressure, source = rec.source }, rec)
    return rec
  end

  function P:finish(id, x, y) return close(self, id, "released", x, y) end

  -- cancel one pointer, or every live pointer when id is nil (focus loss)
  function P:cancel(id)
    if id ~= nil then return close(self, id, "cancelled") end
    local ids = {}
    for key in pairs(self.records) do ids[#ids + 1] = key end
    for _, key in ipairs(ids) do close(self, key, "cancelled") end
  end

  -- Velocity decays while a finger rests, so a held-still stylus reads as
  -- still rather than keeping its last flick forever.
  function P:update()
    local t = now()
    for _, rec in pairs(self.records) do
      if t - rec.lastAt > 0.08 then
        rec.vx, rec.vy = rec.vx * 0.7, rec.vy * 0.7
        if math.abs(rec.vx) < 1 then rec.vx = 0 end
        if math.abs(rec.vy) < 1 then rec.vy = 0 end
      end
    end
  end

  -- ------- gesture helpers (pure functions over a record)

  function P.duration(rec) return (rec.upAt or now()) - rec.downAt end

  function P.speed(rec) return math.sqrt(rec.vx * rec.vx + rec.vy * rec.vy) end

  function P.strokeLength(rec) return rec.travel end

  -- a short press that barely moved
  function P.isTap(rec, maxTravel, maxSecs)
    return rec.travel <= (maxTravel or 8) and P.duration(rec) <= (maxSecs or 0.4)
  end

  -- held in place for at least `secs`
  function P.isHold(rec, secs, maxTravel)
    return P.duration(rec) >= (secs or 0.5) and rec.travel <= (maxTravel or 8)
  end

  -- direction of the whole stroke when it is long and quick enough:
  -- "left" | "right" | "up" | "down", plus distance and speed
  function P.swipe(rec, minDist, minSpeed)
    local dx, dy = rec.x - rec.startX, rec.y - rec.startY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < (minDist or 24) then return nil end
    local secs = math.max(1e-3, P.duration(rec))
    local speed = dist / secs
    if speed < (minSpeed or 80) then return nil end
    local dir
    if math.abs(dx) >= math.abs(dy) then
      dir = dx > 0 and "right" or "left"
    else
      dir = dy > 0 and "down" or "up"
    end
    return dir, dist, speed
  end

  -- "action,x,y" from the second-screen bridge -> action, x, y (numbers)
  function P.parse(str)
    if type(str) ~= "string" then return nil end
    local action, x, y = str:match("^%s*(%a+)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*$")
    if not action then return nil end
    return action:lower(), tonumber(x), tonumber(y)
  end

  return P
end
