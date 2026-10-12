-- SCRATCH: the free-touch demo and the scaffold a Pokemon-Amie style
-- minigame starts from. The lead party Pokemon icon chases the stylus
-- with eased motion, the stroke leaves a fading trail from the pointer
-- record path, and the readout shows what the pointer layer knows.

return function(mod, Pointer)
  local app = { id = "scratch", title = "SCRATCH", live = true }

  local W, H = 256, 178
  app.x, app.y = W / 2, H / 2          -- icon position (eased)
  app.tx, app.ty = W / 2, H / 2        -- target (last touch)
  app.follow = nil                     -- the record being followed
  app.trail = {}                       -- path kept after the finger lifts
  app.lastSpeed, app.lastPressure = 0, nil
  app.taps, app.swipes = 0, 0
  app.lastGesture = ""

  function app:pointer(ev, rec, game)
    if ev.phase == "pressed" then
      self.follow = rec
      self.tx, self.ty = ev.x, ev.y
      self.trail = {}
    elseif ev.phase == "moved" then
      if rec == self.follow then
        self.tx, self.ty = ev.x, ev.y
        self.lastSpeed = Pointer.speed(rec)
        self.lastPressure = rec.pressure
      end
    else
      if rec == self.follow then
        if Pointer.isTap(rec) then
          self.taps = self.taps + 1
          self.lastGesture = "TAP"
        else
          local dir, dist, speed = Pointer.swipe(rec)
          if dir then
            self.swipes = self.swipes + 1
            self.lastGesture = ("SWIPE %s %dpx %d/s"):format(dir:upper(), dist, speed)
          else
            self.lastGesture = ("STROKE %dpx"):format(rec.travel)
          end
        end
        self.trail = {}
        for i, p in ipairs(rec.path) do
          self.trail[i] = { x = p.x, y = p.y - self.tabH }
        end
        self.follow = nil
      end
    end
  end

  function app:update(dt)
    local k = math.min(1, dt * 16)
    self.x = self.x + (self.tx - self.x) * k
    self.y = self.y + (self.ty - self.y) * k
    if self.follow then
      self.lastSpeed = Pointer.speed(self.follow)
    else
      self.lastSpeed = self.lastSpeed * math.max(0, 1 - dt * 4)
    end
  end

  local function leadMon(game)
    local party = game and game.save and game.save.party
    local mon = party and party[1]
    if type(mon) ~= "table" or type(mon.species) ~= "string" then return nil end
    local maxHp = mon.stats and mon.stats.hp or mon.maxHp or mon.hp
    if type(mon.hp) ~= "number" or type(maxHp) ~= "number" or maxHp < 1 then return nil end
    return { species = mon.species, hp = math.max(0, math.min(mon.hp, maxHp)), maxHp = maxHp }
  end

  local function drawPath(G, points, yOffset, alphaScale)
    if #points < 2 then return end
    for i = 2, #points do
      local a, b = points[i - 1], points[i]
      local f = i / #points
      G.setColor(0.4, 0.8, 1, f * alphaScale)
      G.setLineWidth(1 + f * 3)
      G.line(a.x, a.y - yOffset, b.x, b.y - yOffset)
    end
    G.setLineWidth(1)
  end

  function app:draw(G, w, h)
    G.setColor(1, 1, 1, 0.05)
    for x = 0, w, 16 do G.rectangle("fill", x, 0, 1, h) end
    for y = 0, h, 16 do G.rectangle("fill", 0, y, w, 1) end

    if self.follow then
      drawPath(G, self.follow.path, self.tabH, 1)
    elseif #self.trail > 1 then
      drawPath(G, self.trail, 0, 0.5)
    end

    local drawn = false
    local game = mod.game
    local mon = leadMon(game)
    if mon and mod.ui and mod.ui.PokemonIcon then
      G.setColor(1, 1, 1, 1)
      local ok, result = pcall(mod.ui.PokemonIcon.draw, game, mon,
        math.floor(self.x - 8), math.floor(self.y - 8))
      drawn = ok and result == true
    end
    if not drawn then
      G.setColor(0.95, 0.8, 0.3, 1)
      G.circle("fill", self.x, self.y, 9, 24)
      G.setColor(0.2, 0.15, 0.05, 1)
      G.circle("fill", self.x - 3, self.y - 2, 1.5, 8)
      G.circle("fill", self.x + 3, self.y - 2, 1.5, 8)
    end

    G.setColor(1, 1, 1, 0.85)
    local rec = self.follow
    local line1 = rec
      and ("x %3d  y %3d  p %s"):format(rec.x, rec.y - self.tabH,
        rec.pressure and ("%.2f"):format(rec.pressure) or "--")
      or "touch and drag"
    G.print(line1, 4, h - 36)
    G.print(("speed %4d px/s   down %d"):format(self.lastSpeed, Pointer.count), 4, h - 24)
    G.print(("taps %d  swipes %d  %s"):format(self.taps, self.swipes, self.lastGesture), 4, h - 12)
  end

  return app
end
