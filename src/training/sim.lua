-- The Super-Training Regimen, simulated: a Balloon Bot on the far plane with goals on
-- its body, the player's Pokemon on the near plane, Energy Shots flying out, the bot's
-- balls flying in, bit balloons, barriers, the guts circle, charging, the clock. Pure:
-- it takes the numbers table, a course row, the modifiers and an rng, and answers
-- `update(dt)` with the events of that slice. No love, no engine.
--
-- Arena space: x in [-1, 1] left to right, z in [0, 1] from the player's plane to the
-- bot's, y in [0, 1] up from the floor. Sim.project maps it to the 240x160 top screen.
--
-- Sim = sim(N); sim = Sim.new(course, { mods, shotType, level, anchors, library }, rng)

return function(N)
  local Sim = {}
  Sim.__index = Sim
  local STEP = 1 / 120

  -- ------- projection and aiming

  local function lerp(a, b, t) return a + (b - a) * t end

  -- the view (N.VIEW): hw / fy / hu at the trainee's depth, then at the balloon's
  local V = N.VIEW or { NEAR = { hw = 118, fy = 150, hu = 70 }, FAR = { hw = 70, fy = 92, hu = 44 } }
  function Sim.view()
    return V.NEAR.hw, V.NEAR.fy, V.NEAR.hu, V.FAR.hw, V.FAR.hu, V.FAR.fy
  end

  -- (x, y, z) -> screen x, screen y, scale factor at that depth
  function Sim.project(x, y, z)
    local hw = lerp(V.NEAR.hw, V.FAR.hw, z)
    local fy = lerp(V.NEAR.fy, V.FAR.fy, z)
    local hu = lerp(V.NEAR.hu, V.FAR.hu, z)
    return 120 + x * hw, fy - y * hu, hw / V.NEAR.hw
  end
  -- a screen point back onto the balloon's plane (z = 1)
  function Sim.unproject(sx, sy)
    return (sx - 120) / V.FAR.hw, (V.FAR.fy - sy) / V.FAR.hu
  end
  -- at the bot's depth a world unit is hw px across and hu px up: a goal on the balloon's
  -- sprite stretches its height by this so it lands where the sprite is drawn
  Sim.ASPECT = V.FAR.hw / V.FAR.hu

  -- the aiming pad (a circle in app space) covers the whole bot plane
  -- (ex, ey): the aim reach, x in -ex..ex and y in 0..ey (default 1, 1: the round balloon)
  function Sim.aimFromPad(ax, ay, pad, ex, ey)
    ex, ey = ex or 1, ey or 1
    local u = math.max(-1, math.min(1, (ax - pad.cx) / pad.r))
    local v = math.max(-1, math.min(1, (pad.cy - ay) / pad.r))
    return u * ex, ey * (0.5 + 0.5 * v)
  end

  function Sim.padFromAim(tx, ty, pad, ex, ey)
    ex, ey = ex or 1, ey or 1
    return pad.cx + tx / ex * pad.r, pad.cy - (ty / ey - 0.5) * 2 * pad.r
  end

  local KINDS = { small_rapid = true, big = true, ring = true, homing = true, cross = true, wave_tall = true,
    wave_wide = true, barrier = true, bits = true, lob = true }
  Sim.KINDS = KINDS

  -- ------- validation (the courses test calls it for every row)

  function Sim.validate(course, Courses)
    if type(course) ~= "table" then return false, "no course" end
    if type(course.bots) ~= "table" or #course.bots == 0 then return false, course.id .. ": no bots" end
    for i, b in ipairs(course.bots) do
      if not (tonumber(b.national) and tonumber(b.score) and b.score > 0) then
        return false, ("%s: bot %d needs national and score"):format(course.id, i)
      end
    end
    local goals = course.goals
    if type(goals) ~= "table" then return false, course.id .. ": no goals" end
    local family = Courses and Courses.anchors and Courses.anchors[goals.anchors]
    if not family then return false, course.id .. ": unknown anchor family " .. tostring(goals.anchors) end
    if type(goals.groups) ~= "table" or #goals.groups == 0 then return false, course.id .. ": no goal groups" end
    for _, group in ipairs(goals.groups) do
      for _, name in ipairs(group) do
        if not family[name] then return false, course.id .. ": unknown anchor " .. tostring(name) end
      end
    end
    if goals.chance and goals.chance.anchor and not family[goals.chance.anchor] then
      return false, course.id .. ": unknown chance anchor " .. tostring(goals.chance.anchor)
    end
    local script = course.attacks
    if type(script) == "string" then script = Courses and Courses.attacks and Courses.attacks[script] end
    if type(script) ~= "table" then return false, course.id .. ": unknown attack script " .. tostring(course.attacks) end
    for _, e in ipairs(script) do
      if not KINDS[e.kind] then return false, course.id .. ": unknown attack kind " .. tostring(e.kind) end
      if e.kind == "barrier" and e.marker and not family[e.marker] then
        return false, course.id .. ": barrier marker " .. tostring(e.marker)
      end
    end
    return true
  end

  -- ------- construction

  local function compile(spec, library, horizon)
    if type(spec) == "string" then spec = library and library[spec] end
    local out = {}
    for _, e in ipairs(spec or {}) do
      local function copy(t)
        local c = {}
        for k, v in pairs(e) do
          if k ~= "at" and k ~= "every" and k ~= "from" and k ~= "until" then c[k] = v end
        end
        c.t = t
        return c
      end
      if e.at then out[#out + 1] = copy(e.at) end
      if e.every and e.every > 0 then
        local t = e.from or e.every
        local last = e["until"] or horizon
        while t <= last do
          out[#out + 1] = copy(t)
          t = t + e.every
        end
      end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
  end
  Sim.compile = compile

  function Sim.new(course, params, rng)
    params = params or {}
    local s = setmetatable({}, Sim)
    s.course = course
    s.rng = rng or math.random
    s.mods = params.mods or { pointMult = 1, shotSize = 1, lossMult = 1, gutsRate = 1, blockLen = 1, moveMult = 1, ballSpeedMult = 1 }
    s.shotType = params.shotType or "black"
    s.level = course.level or 1
    s.isSecret = course.secret ~= nil
    s.anchors = params.anchors or {}
    -- the balloon's shape per bot index (arena_draw.shapeFor): goals live on its cells
    s.shapes = params.shapes or {}
    s.library = params.library or {}
    s.time = course.time or N.CLOCK.TIME
    s.remaining = s.time
    s.phase = "countdown"
    s.countdown = N.CLOCK.COUNTDOWN_S
    s.t = 0
    s.score, s.totalScore = 0, 0
    s.botIndex = 0
    s.player = { x = 0, y = 0, z = N.PLAYER.Z or 0.1, mx = 0, mz = 0, stun = 0, shield = 0, shieldCd = 0, charging = false, chargeT = 0,
      firing = 0, burst = 0, rapidT = 0, aim = { x = 0, y = 0.5 } }
    s.guts = N.GUTS.START
    s.goals, s.shots, s.balls, s.bits, s.spawnQueue = {}, {}, {}, {}, {}
    s.barrier = nil
    s.groupIndex, s.groupGap, s.groupScored, s.chanceDone = 0, 0, 0, false
    s.schedule = compile(course.attacks, s.library, s.time)
    s.scheduleIdx = 1
    s.pendingAttack = nil
    s.events = {}
    s.stats = { shots = 0, hits = 0, misses = 0, damageTaken = 0, goalsScored = 0, blocked = 0, playerHits = 0, bitsPopped = 0 }
    s.acc = 0
    s.paused = false
    s:nextBot()
    -- the reticle starts on the balloon's centre
    s.player.aim.y = s:botCY()
    return s
  end

  local function emit(s, kind, data)
    data = data or {}
    data.kind = kind
    data.t = s.t
    s.events[#s.events + 1] = data
  end

  function Sim:nextBot()
    self.botIndex = self.botIndex + 1
    local b = self.course.bots[self.botIndex]
    if not b then return false end
    self.bot = { national = b.national, species = b.species, art = b.art, mega = b.mega, target = b.score,
      scale = 1, flinch = 0, aura = 0, mood = "normal", goalsScored = 0 }
    self.shape = self.shapes[self.botIndex]
    self.score = 0
    self.goals, self.balls, self.bits, self.spawnQueue = {}, {}, {}, {}
    self.barrier = nil
    self.groupIndex, self.groupGap, self.groupScored, self.chanceDone = 0, 0, 0, false
    self.scheduleT0 = self.t
    if self.botIndex > 1 then
      self.remaining = self.remaining + (self.course.extraBotSecs or N.CLOCK.EXTRA_BOT_S)
      self.schedule = compile(self.course.attacks, self.library, self.time)
      self.scheduleIdx = 1
      self.pendingAttack = nil
    end
    return true
  end

  -- ------- inputs

  function Sim:setMove(dx, dz) self.player.mx = math.max(-1, math.min(1, dx or 0)); self.player.mz = math.max(-1, math.min(1, dz or 0)) end
  -- how far the aim reaches: the whole sprite balloon, or the round balloon's plane
  function Sim:aimExtent()
    if self.shape then return N.BOT.AIM_X, N.BOT.AIM_Y end
    return 1, 1
  end
  function Sim:aim(tx, ty)
    local ex, ey = self:aimExtent()
    self.player.aim.x = math.max(-ex, math.min(ex, tx))
    self.player.aim.y = math.max(0, math.min(ey, ty))
  end
  -- the balloon's centre height (a sprite balloon hovers higher)
  function Sim:botCY() return self.shape and N.BOT.SHAPE_CY or N.BOT.CY end
  function Sim:pause(on) self.paused = on and true or false end

  function Sim:block()
    local p = self.player
    if self.phase ~= "play" or p.shieldCd > 0 or p.stun > 0 then return false end
    p.shield = N.BLOCK.LEN * (self.mods.blockLen or 1)
    p.shieldCd = N.BLOCK.COOLDOWN
    emit(self, "block_up")
    return true
  end

  function Sim:pressFire()
    local p = self.player
    if self.phase ~= "play" or p.stun > 0 then return false end
    p.charging = true
    p.chargeT = 0
    p.rapidT = 0
    return true
  end

  function Sim:chargeStage()
    local p = self.player
    if not p.charging then return 0 end
    local stage = 0
    for i, t in ipairs(N.CHARGE.STAGE_S) do if p.chargeT >= t then stage = i end end
    return stage
  end

  function Sim:releaseFire()
    local p = self.player
    if not p.charging then return false end
    -- where this shot was aimed: the top screen marks it so the next one can be corrected
    p.lastShot = { x = p.aim.x, y = p.aim.y }
    local stage = math.max(1, self:chargeStage())
    p.charging = false
    if self.phase ~= "play" or p.stun > 0 or p.shield > 0 then return false end
    if self.shotType == N.SHOT.RAPID and stage >= 3 then
      p.burst = N.CHARGE.YELLOW_BURST
      p.firing = 0
      return true
    end
    self:fire(stage)
    return true
  end

  -- ------- shooting

  -- the energy meter decides the ball: full -> the species' Energy Shot, otherwise a plain
  -- black ball worth less the emptier the meter, and a weak ball when it is nearly dry
  function Sim:fire(stage, spread)
    local p = self.player
    local species = N.SHOT[self.shotType] or N.SHOT.black
    local g = self.guts
    local def, kind, weak = species, self.shotType, false
    local mult
    if g >= N.GUTS.FULL_AT then
      mult = species.mult
    elseif g < N.GUTS.WEAK_BELOW then
      def, kind, weak = N.SHOT.weak, "weak", true
      mult = N.SHOT.weak.mult
    else
      def, kind = N.SHOT.black, "black"
      local f = (g - N.GUTS.WEAK_BELOW) / math.max(1e-6, N.GUTS.FULL_AT - N.GUTS.WEAK_BELOW)
      mult = N.SHOT.weak.mult + (N.SHOT.black.mult - N.SHOT.weak.mult) * f
    end
    self.guts = math.max(0, self.guts - species.cost)
    stage = stage or 1
    local base = self.isSecret and N.POINTS.BASE.secret or (N.POINTS.BASE[self.level] or N.POINTS.BASE[1])
    local points = base * mult * (N.CHARGE.MULT[stage] or 1) * (self.mods.pointMult or 1)
    local r = def.r * (N.CHARGE.SIZE[stage] or 1) * (self.mods.shotSize or 1)
    local speed = def.speed * (self.mods.ballSpeedMult or 1)
    local ax = p.aim.x + (spread or 0)
    local ay = p.aim.y
    local x0, y0, z0 = p.x, (p.y or 0) + 0.15, p.z
    local dz = math.max(0.05, 1 - z0)
    local shot = { x = x0, y = y0, z = z0, vz = speed, vx = (ax - x0) / dz * speed, vy = (ay - y0) / dz * speed,
      r = r, points = math.floor(points + 0.5), type = kind, stage = stage, weak = weak, energy = kind == self.shotType }
    self.shots[#self.shots + 1] = shot
    self.stats.shots = self.stats.shots + 1
    if shot.energy then self.stats.energyShots = (self.stats.energyShots or 0) + 1 end
    emit(self, weak and "weak_shot" or "shot_fired", { stage = stage, type = shot.type, energy = shot.energy })
    return shot
  end

  -- ------- goals

  local function anchorPos(self, name)
    local a = self.anchors[name] or { x = 0, y = 0 }
    local R = N.BOT.R * self.bot.scale
    local ox, oy = 0, 0
    if a.motion then
      local ph = self.t * 2 * math.pi / (a.motion.period or 1.5)
      ox = (a.motion.ax or 0) * math.sin(ph) * R
      oy = (a.motion.ay or 0) * math.cos(ph) * R
    end
    if self.course.fleeing then
      -- "Follow Those Fleeing Goals!": every goal drifts around the balloon
      ox = ox + math.sin(self.t * 1.7 + (a.x or 0) * 3) * 0.35 * R
      oy = oy + math.cos(self.t * 1.3 + (a.y or 0) * 3) * 0.25 * R
    elseif self.course.roaming then
      -- "constantly moving goals": a slower, smaller wander
      ox = ox + math.sin(self.t * 1.1 + (a.x or 0) * 2) * 0.2 * R
      oy = oy + math.cos(self.t * 0.9 + (a.y or 0) * 2) * 0.15 * R
    end
    local bx, by = self:botOffset()
    return a.x * R + ox + bx, self:botCY() + a.y * R + oy + by
  end

  -- the whole balloon's drift: its level's sway (a slow loop, measured in the game's top-screen
  -- pixels and turned into world units at the bot's depth), the shake after a goal, and the
  -- course's own bob (Aerodactyl soars up and down)
  function Sim:botOffset()
    local x, y = 0, 0
    local _, _, _, hw, hu = Sim.view()
    local sway = N.BOT.SWAY and N.BOT.SWAY[self.isSecret and "secret" or self.level]
    if sway and self.phase ~= "countdown" then
      local w = 2 * math.pi * (self.t - (self.swayT0 or 0)) / sway.period
      x = x + math.sin(w) * sway.ax * 0.6 / hw
      y = y + math.sin(w + math.pi / 2) * sway.ay * (160 / 240) / hu
    end
    local bot = self.bot
    if bot and (bot.shake or 0) > 0 then
      local k = bot.shake / N.BOT.SHAKE_S
      x = x + math.sin(self.t * 23) * N.BOT.SHAKE_PX * k * 0.6 / hw
      y = y + math.sin(self.t * 17 + 1) * N.BOT.SHAKE_PX * k * (160 / 240) / hu
    end
    local m = self.course.motion
    if m and m.bob then
      y = y + math.sin(self.t * 2 * math.pi / (m.bob.period or 2)) * (m.bob.ay or 0.2) * N.BOT.R
    end
    return x, y
  end
  Sim.anchorPos = anchorPos

  -- ------- goals on the balloon's shape
  --
  -- shape = { cell = size in bot-local units, cells = { [i] = { [j] = true } }, list = { {i, j} } }:
  -- the cells of the Pokemon's sprite (eroded so a goal's centre sits well inside), cell
  -- (i, j) centred on ((i + 0.5) * cell, (j + 0.5) * cell), y up. A goal stands on a cell and
  -- walks to neighbouring ones, never across empty space, so it is always on the sprite.

  local function walkable(shape, i, j)
    local col = shape.cells[i]
    return col ~= nil and col[j] == true
  end
  Sim.walkable = walkable

  local function cellCenter(shape, i, j) return (i + 0.5) * shape.cell, (j + 0.5) * shape.cell end

  -- the walkable cell nearest a bot-local point, avoiding cells other goals stand on
  local function nearestCell(self, x, y, avoid)
    local shape = self.shape
    local best, bi, bj = math.huge, nil, nil
    for _, c in ipairs(shape.list) do
      local cx, cy = cellCenter(shape, c[1], c[2])
      local d = (cx - x) ^ 2 + (cy - y) ^ 2
      if avoid then
        for _, o in ipairs(self.goals) do
          if o.ci and (o.lx - cx) ^ 2 + (o.ly - cy) ^ 2 < avoid ^ 2 then d = d + 100 end
        end
      end
      if d < best then best, bi, bj = d, c[1], c[2] end
    end
    return bi, bj
  end

  local function wanderOf(self, goal)
    local W = N.GOALS.WANDER
    local a = goal.anchor and self.anchors[goal.anchor] or {}
    local speed = W.SPEED[self.isSecret and "secret" or self.level] or W.SPEED[1]
    local radius = W.RADIUS
    if a.motion then speed, radius = math.max(speed, W.MOTION_SPEED), W.MOTION_RADIUS end
    if self.course.fleeing then speed, radius = math.max(speed, W.FLEE_SPEED), math.huge
    elseif self.course.roaming then speed, radius = math.max(speed, W.ROAM_SPEED), math.huge end
    return speed, radius
  end

  -- put a new goal on the shape at its anchor's spot
  function Sim:placeGoal(goal)
    if not self.shape or #self.shape.list == 0 then return goal end
    local a = goal.anchor and self.anchors[goal.anchor] or { x = 0, y = 0 }
    -- anchors were laid out for a round balloon one radius wide; spread them over the
    -- sprite's own extent so "left", "head" and "tail" land on those parts of it
    local sx, sy = self.shape.halfW or 1, self.shape.halfH or 1
    local i, j = nearestCell(self, (a.x or 0) * sx, (a.y or 0) * sy, (goal.r or N.GOALS.R) * 2.6)
    if not i then return goal end
    goal.ci, goal.cj = i, j
    goal.lx, goal.ly = cellCenter(self.shape, i, j)
    goal.hx, goal.hy = goal.lx, goal.ly
    goal.ni, goal.nj = i, j
    goal.wait = self.rng() * N.GOALS.WANDER.PAUSE_S
    return goal
  end

  -- a fresh destination: a walkable cell within the goal's range of its spot
  local function crowded(self, g, x, y)
    local gap = (g.r or N.GOALS.R) * 2.6
    for _, o in ipairs(self.goals) do
      if o ~= g and o.ci then
        if (o.lx - x) ^ 2 + (o.ly - y) ^ 2 < gap ^ 2 then return true end
        if o.di then
          local dx, dy = cellCenter(self.shape, o.di, o.dj)
          if (dx - x) ^ 2 + (dy - y) ^ 2 < gap ^ 2 then return true end
        end
      end
    end
    return false
  end

  local function pickDestination(self, g, radius)
    local list = self.shape.list
    for _ = 1, 24 do
      local c = list[math.floor(self.rng() * #list) + 1]
      local cx, cy = cellCenter(self.shape, c[1], c[2])
      if (cx - g.hx) ^ 2 + (cy - g.hy) ^ 2 <= radius ^ 2 and not crowded(self, g, cx, cy) then
        g.di, g.dj = c[1], c[2]
        return
      end
    end
    g.di, g.dj = nearestCell(self, g.hx, g.hy)
  end

  -- the neighbour one step closer to the destination (no corner cutting across empty cells)
  local function stepToward(shape, g)
    local tx, ty = cellCenter(shape, g.di, g.dj)
    local cx, cy = cellCenter(shape, g.ci, g.cj)
    local best = (cx - tx) ^ 2 + (cy - ty) ^ 2 - 1e-9
    local bi, bj = nil, nil
    for di = -1, 1 do
      for dj = -1, 1 do
        if (di ~= 0 or dj ~= 0) then
          local i, j = g.ci + di, g.cj + dj
          local ok = walkable(shape, i, j)
          if ok and di ~= 0 and dj ~= 0 then ok = walkable(shape, g.ci + di, g.cj) and walkable(shape, g.ci, g.cj + dj) end
          if ok then
            local nx, ny = cellCenter(shape, i, j)
            local d = (nx - tx) ^ 2 + (ny - ty) ^ 2
            if d < best then best, bi, bj = d, i, j end
          end
        end
      end
    end
    return bi, bj
  end

  function Sim:moveGoals(step)
    local shape = self.shape
    if not shape then return end
    for _, g in ipairs(self.goals) do
      if g.ci then
        local speed, radius = wanderOf(self, g)
        local nx, ny = cellCenter(shape, g.ni, g.nj)
        local dx, dy = nx - g.lx, ny - g.ly
        local d = math.sqrt(dx * dx + dy * dy)
        local move = speed * step
        if d > move then
          g.lx, g.ly = g.lx + dx / d * move, g.ly + dy / d * move
        else
          g.lx, g.ly = nx, ny
          g.ci, g.cj = g.ni, g.nj
          if g.wait and g.wait > 0 then
            g.wait = g.wait - step
          else
            if not g.di or (g.di == g.ci and g.dj == g.cj) then pickDestination(self, g, radius) end
            local i, j = stepToward(shape, g)
            if i then
              g.ni, g.nj = i, j
            else
              -- arrived, or boxed in: rest a moment and choose somewhere else
              g.di, g.dj = nil, nil
              g.wait = self.rng() * N.GOALS.WANDER.PAUSE_S
            end
          end
        end
      end
    end
  end

  function Sim:goalPos(goal)
    if goal.ci then
      local R = N.BOT.R * self.bot.scale
      local bx, by = self:botOffset()
      return goal.lx * R + bx, self:botCY() + goal.ly * R * Sim.ASPECT + by
    end
    if goal.anchor then return anchorPos(self, goal.anchor) end
    return goal.x or 0, goal.y or self:botCY()
  end

  function Sim:spawnGroup()
    local groups = self.course.goals.groups
    if #groups == 0 then return end
    self.groupIndex = self.groupIndex % #groups + 1
    local group = groups[self.groupIndex]
    local max = self.course.goals.max or #group
    local n = 0
    self.groupScored = 0
    self.chanceDone = false
    for _, name in ipairs(group) do
      if n >= max then break end
      self.goals[#self.goals + 1] = self:placeGoal({ anchor = name, kind = "white", age = 0, r = N.GOALS.R, hits = 0 })
      n = n + 1
    end
    self.groupSize = n
    emit(self, "goals_spawned", { n = n, group = self.groupIndex })
  end

  function Sim:spawnChance()
    local c = self.course.goals.chance or {}
    self.goals[#self.goals + 1] = self:placeGoal({ anchor = c.anchor or (self.course.goals.groups[1] or {})[1], kind = "chance", age = 0,
      r = N.GOALS.CHANCE_R, hits = 0, life = c.secs or N.GOALS.CHANCE_S })
    self.chanceDone = true
    emit(self, "chance_goal")
  end

  local function liveGoals(self)
    local white, chance = 0, 0
    for _, g in ipairs(self.goals) do
      if g.kind == "white" or g.kind == "fading" then white = white + 1
      elseif g.kind == "chance" then chance = chance + 1 end
    end
    return white, chance
  end

  function Sim:updateGoals(step)
    self:moveGoals(step)
    local keep = {}
    for _, g in ipairs(self.goals) do
      g.age = g.age + step
      local alive = true
      if g.kind == "white" and g.age >= N.GOALS.YELLOW_AT then
        g.kind = "fading"
        emit(self, "goal_yellow", { anchor = g.anchor })
      end
      if (g.kind == "fading") and g.age >= N.GOALS.GONE_AT then
        alive = false
        emit(self, "goal_expired", { anchor = g.anchor })
      elseif g.kind == "chance" and g.age >= (g.life or N.GOALS.CHANCE_S) then
        alive = false
        emit(self, "chance_expired")
      elseif g.kind == "marker" and not self.barrier then
        alive = false
      end
      if alive then keep[#keep + 1] = g end
    end
    self.goals = keep
    local white, chance = liveGoals(self)
    if white == 0 then
      if chance == 0 then
        if not self.chanceDone and self.groupSize and self.groupScored >= self.groupSize then
          -- the red goal: after every second cleared group (measured), else by the course's odds
          self.groupsCleared = (self.groupsCleared or 0) + 1
          local every = N.GOALS.CHANCE_EVERY
          local odds = (self.course.goals.chance and self.course.goals.chance.odds) or N.GOALS.CHANCE_ODDS
          local due
          if every and every > 0 then due = self.groupsCleared % every == 0 else due = self.rng() < odds end
          if due then
            self:spawnChance()
            return
          end
          self.chanceDone = true
        end
        self.groupGap = self.groupGap + step
        if self.groupGap >= N.GOALS.GROUP_GAP_S then
          self.groupGap = 0
          self:spawnGroup()
        end
      end
    end
  end

  -- ------- attacks

  -- a round ball's size for the level (N.ATTACK.BALL): its kind's radius times SIZE, capped
  local function sizeBall(self, ball)
    local B = N.ATTACK.BALL
    if not B or ball.w or ball.h or ball.kind == "bit" then return ball end
    local lv = self.isSecret and "secret" or self.level
    ball.r = math.min(ball.r * (B.SIZE[lv] or 1), (B.CAP[lv] or 1) * B.SPRITE_R)
    return ball
  end

  local function queue(self, delay, ball)
    self.spawnQueue[#self.spawnQueue + 1] = { at = self.t + delay, ball = sizeBall(self, ball) }
  end

  local function towardPlayer(self, x0, y0, speed)
    local p = self.player
    local dz = 1 - p.z
    return (p.x - x0) / dz * speed, ((p.y or 0) + 0.15 - y0) / dz * speed
  end

  function Sim:launch(e)
    local A = N.ATTACK
    local kind = e.kind
    local cx, cy = 0, self:botCY()
    local spd = (self.mods.botSpeedMult or 1)
    if self.bot.mood == "rage" then spd = spd * N.BOT.RAGE_SPEED
    elseif self.bot.mood == "calm" then spd = spd * N.BOT.CALM_SPEED end
    if kind == "small_rapid" then
      local n = e.n or 3
      local speed = A.small.speed * spd * (e.fast and 1.5 or 1)
      for i = 1, n do
        local vx, vy = towardPlayer(self, cx, cy, speed)
        queue(self, (i - 1) * (e.gap or A.small.gap), { x = cx, y = cy, z = 1, vx = vx, vy = vy, vz = -speed, r = A.small.r, kind = "small" })
      end
    elseif kind == "lob" then
      -- up off the top of the screen and down on where the trainee is now (n of them, spread)
      local p = self.player
      local n = e.n or 1
      for i = 1, n do
        local off = (i - (n + 1) / 2) * 0.45
        local tx = math.max(-N.PLAYER.X_MAX, math.min(N.PLAYER.X_MAX, p.x + off))
        queue(self, (i - 1) * 0.35, { x = cx, y = cy, z = 1, vx = 0, vy = 0, vz = 0, r = A.lob.r, kind = "lob",
          lob = { t = 0, T = A.lob.flight / spd, x0 = cx, y0 = cy, tx = tx, ty = (p.y or 0) + N.PLAYER.H / 2, tz = p.z,
            peak = A.lob.peak } })
      end
    elseif kind == "big" then
      local vx, vy = towardPlayer(self, cx, cy, A.big.speed * spd)
      queue(self, 0, { x = cx, y = cy, z = 1, vx = vx, vy = vy, vz = -A.big.speed * spd, r = A.big.r, kind = "big" })
    elseif kind == "ring" then
      local n = A.ring.n
      for i = 1, n do
        local a = (i - 1) / n * 2 * math.pi
        queue(self, 0, { x = cx, y = cy, z = 1, vx = 0, vy = 0, vz = -A.ring.speed * spd, r = A.ring.r, kind = "ring",
          ring = { angle = a, r = A.ring.r_ring or A.ring.ring_r, spin = A.ring.spin, cx = cx, cy = cy } })
      end
    elseif kind == "homing" then
      local n = e.n or 1
      for i = 1, n do
        local sx = cx + (i - (n + 1) / 2) * 0.3
        queue(self, (i - 1) * 0.3, { x = sx, y = cy, z = 1, vx = 0, vy = towardPlayer(self, sx, cy, A.homing.speed * spd) and select(2, towardPlayer(self, sx, cy, A.homing.speed * spd)) or 0,
          vz = -A.homing.speed * spd, r = A.homing.r, kind = "homing", homing = true,
          w = e.tall and 0.1 or nil, h = e.tall and 0.6 or nil })
      end
    elseif kind == "cross" then
      local arms = A.cross.arms
      local len = A.cross.arm_len
      local speed = A.cross.speed * spd
      for i = 1, 3 do
        local d = (i - 2) * len
        queue(self, 0, { x = cx + d, y = cy, z = 1, vx = 0, vy = ((self.player.y or 0) + 0.15 - cy) * speed, vz = -speed, r = A.cross.r, kind = "cross" })
        if i ~= 2 then
          queue(self, 0, { x = cx, y = cy + d, z = 1, vx = 0, vy = ((self.player.y or 0) + 0.15 - cy - d) * speed, vz = -speed, r = A.cross.r, kind = "cross" })
        end
      end
    elseif kind == "wave_tall" then
      local cols = A.wave_tall.cols
      local gapAt = math.floor(self.rng() * cols) + 1
      for i = 1, cols do
        if i ~= gapAt then
          local x = -0.8 + (i - 0.5) * (1.6 / cols)
          queue(self, 0, { x = x, y = 0.3, z = 1, vx = 0, vy = 0, vz = -A.wave_tall.speed * spd, r = 0.12, w = 0.24, h = 0.8, kind = "wave" })
        end
      end
    elseif kind == "wave_wide" then
      local side = self.rng() < 0.5 and -1 or 1
      queue(self, 0, { x = side * 0.3, y = 0.15, z = 1, vx = 0, vy = 0, vz = -A.wave_wide.speed * spd, r = 0.2, w = A.wave_wide.w, h = 0.3, kind = "wave" })
    elseif kind == "barrier" then
      if not self.barrier then
        self.barrier = { t = 0, marker = e.marker or "center", maxS = A.barrier.max_s }
        self.goals[#self.goals + 1] = self:placeGoal({ anchor = self.barrier.marker, kind = "marker", age = 0, r = N.GOALS.MARKER_R, hits = 0 })
        emit(self, "barrier_up")
      end
    elseif kind == "bits" then
      local n = e.n or 2
      for i = 1, n do
        local x = (i - (n + 1) / 2) * 0.5
        self.bits[#self.bits + 1] = { id = #self.bits + 1, x = x, y = A.bit.y, z = A.bit.z, hp = A.bit.hp, r = A.bit.r,
          fireT = A.bit.fire_every * (0.5 + 0.5 * self.rng()) }
      end
      emit(self, "bits_spawned", { n = n })
    end
  end

  function Sim:updateAttacks(step)
    local rel = self.t - (self.scheduleT0 or 0)
    local e = self.schedule[self.scheduleIdx]
    local cadence = 1
    if self.bot.mood == "rage" then cadence = N.BOT.RAGE_CADENCE elseif self.bot.mood == "calm" then cadence = N.BOT.CALM_CADENCE end
    while e and rel >= e.t * cadence do
      self.scheduleIdx = self.scheduleIdx + 1
      if not self.pendingAttack then
        self.pendingAttack = { entry = e, launchAt = self.t + N.ATTACK.TELEGRAPH_S }
        self.bot.aura = N.ATTACK.TELEGRAPH_S
        emit(self, "attack_telegraph", { attack = e.kind })
      else
        -- stack it right after the one in flight
        self.pendingAttack.queueNext = self.pendingAttack.queueNext or {}
        self.pendingAttack.queueNext[#self.pendingAttack.queueNext + 1] = e
      end
      e = self.schedule[self.scheduleIdx]
    end
    local pa = self.pendingAttack
    if pa and self.t >= pa.launchAt then
      self:launch(pa.entry)
      emit(self, "attack_launch", { attack = pa.entry.kind })
      local nextE = pa.queueNext and table.remove(pa.queueNext, 1)
      if nextE then
        self.pendingAttack = { entry = nextE, launchAt = self.t + N.ATTACK.TELEGRAPH_S, queueNext = pa.queueNext }
        self.bot.aura = N.ATTACK.TELEGRAPH_S
      else
        self.pendingAttack = nil
      end
    end
    -- queued balls
    if #self.spawnQueue > 0 then
      local keep = {}
      for _, q in ipairs(self.spawnQueue) do
        if self.t >= q.at then self.balls[#self.balls + 1] = q.ball else keep[#keep + 1] = q end
      end
      self.spawnQueue = keep
    end
    if self.barrier then
      self.barrier.t = self.barrier.t + step
      if self.barrier.t >= self.barrier.maxS then
        self.barrier = nil
        emit(self, "barrier_down", { timed = true })
      end
    end
  end

  -- ------- shots against bits and goals

  function Sim:hitGoal(goal, shot)
    local pts = shot.points
    if goal.kind == "chance" then pts = math.floor(pts * N.POINTS.CHANCE_MULT + 0.5) end
    if goal.kind == "marker" then
      self.barrier = nil
      emit(self, "barrier_down", { timed = false })
      pts = 0
    end
    goal.hits = goal.hits + 1
    if goal.kind == "white" or goal.kind == "fading" then
      goal.dead = true
      self.groupScored = self.groupScored + 1
    elseif goal.kind == "chance" then
      goal.age = 0
    end
    if pts > 0 then
      self.score = self.score + pts
      self.totalScore = self.totalScore + pts
      self.bot.goalsScored = self.bot.goalsScored + 1
      self.stats.goalsScored = self.stats.goalsScored + 1
      self.bot.flinch = N.BOT.FLINCH_S
      self.bot.shake = N.BOT.SHAKE_S or 0
    end
    self.stats.hits = self.stats.hits + 1
    emit(self, "goal_hit", { points = pts, goal = goal.kind, anchor = goal.anchor, score = self.score,
      stage = shot and shot.stage, energy = shot and shot.energy })
  end

  function Sim:updateShots(step)
    local keep = {}
    for _, sh in ipairs(self.shots) do
      local pz = sh.z
      sh.x = sh.x + sh.vx * step
      sh.y = sh.y + sh.vy * step
      sh.z = sh.z + sh.vz * step
      local alive = true
      -- bits first
      for _, bit in ipairs(self.bits) do
        if alive and bit.hp > 0 and not bit.dead and pz < bit.z and sh.z >= bit.z then
          local dx, dy = sh.x - bit.x, sh.y - bit.y
          if dx * dx + dy * dy <= (bit.r + sh.r) ^ 2 then
            bit.hp = bit.hp - 1
            alive = false
            if bit.hp <= 0 then
              self.stats.bitsPopped = self.stats.bitsPopped + 1
              bit.dead, bit.regenT = true, N.ATTACK.bit.regen_s
              emit(self, "bit_pop", { id = bit.id })
            else
              emit(self, "bit_hit", { id = bit.id, hp = bit.hp })
            end
          end
        end
      end
      if alive and sh.z >= 1 then
        alive = false
        -- where it crosses the bot plane
        local f = (1 - pz) / math.max(1e-6, sh.z - pz)
        local hx = sh.x - sh.vx * step * (1 - f)
        local hy = sh.y - sh.vy * step * (1 - f)
        local hit = nil
        -- while the barrier stands its marker is tested first (a goal may share its spot)
        local order = self.goals
        if self.barrier then
          order = {}
          for _, g in ipairs(self.goals) do if g.kind == "marker" then order[#order + 1] = g end end
          for _, g in ipairs(self.goals) do if g.kind ~= "marker" then order[#order + 1] = g end end
        end
        for _, g in ipairs(order) do
          if not g.dead then
            local gx, gy = self:goalPos(g)
            local rr = g.r * self.bot.scale + sh.r
            if (hx - gx) ^ 2 + (hy - gy) ^ 2 <= rr * rr then
              if self.barrier and g.kind ~= "marker" then
                hit = "absorbed"
              else
                hit = g
              end
              break
            end
          end
        end
        if hit == "absorbed" then
          emit(self, "shot_absorbed")
          self.stats.misses = self.stats.misses + 1
        elseif hit then
          self:hitGoal(hit, sh)
        else
          self.stats.misses = self.stats.misses + 1
          emit(self, "shot_missed")
        end
      end
      if alive then keep[#keep + 1] = sh end
    end
    self.shots = keep
    if #self.goals > 0 then
      local kept = {}
      for _, g in ipairs(self.goals) do if not g.dead then kept[#kept + 1] = g end end
      self.goals = kept
    end
  end

  -- ------- the bot's balls against the player

  function Sim:playerHit(ball)
    local p = self.player
    local levelMult = self.isSecret and N.DAMAGE.LEVEL_MULT.secret or (N.DAMAGE.LEVEL_MULT[self.level] or 1)
    local loss = (N.DAMAGE[ball.kind] or N.DAMAGE.small) * (self.mods.lossMult or 1) * levelMult
    if self.bot and self.bot.mood == "rage" then loss = loss * N.BOT.RAGE_DAMAGE end
    if self.course.suddenDeath then loss = N.DAMAGE.SUDDEN_DEATH end
    loss = math.floor(loss + 0.5)
    local before = self.score
    self.score = math.max(0, self.score - loss)
    self.totalScore = math.max(0, self.totalScore - (before - self.score))
    p.stun = N.PLAYER.HIT_STUN_S
    p.charging = false
    p.burst = 0
    self.stats.damageTaken = self.stats.damageTaken + (before - self.score)
    self.stats.playerHits = self.stats.playerHits + 1
    emit(self, "player_hit", { loss = before - self.score, ball = ball.kind, score = self.score })
  end

  function Sim:updateBalls(step)
    local p = self.player
    local keep = {}
    for _, b in ipairs(self.balls) do
      local pz = b.z
      if b.lob then
        -- along its arc; past the landing it keeps falling forward
        local L = b.lob
        L.t = L.t + step
        local u = L.t / L.T
        b.x = L.x0 + (L.tx - L.x0) * math.min(1, u)
        b.y = L.y0 + (L.ty - L.y0) * u + L.peak * 4 * u * (1 - u)
        b.z = 1 + (L.tz - 0.001 - 1) * u
        pz = (L.t - step) / L.T
        pz = 1 + (L.tz - 0.001 - 1) * pz
      elseif b.ring then
        b.ring.angle = b.ring.angle + b.ring.spin * step
        b.x = b.ring.cx + math.cos(b.ring.angle) * b.ring.r
        b.y = b.ring.cy + math.sin(b.ring.angle) * b.ring.r
      else
        if b.homing then
          local want = (p.x - b.x)
          b.vx = b.vx + math.max(-1, math.min(1, want)) * N.ATTACK.homing.turn * step
          local wantY = ((p.y or 0) + N.PLAYER.H / 2 - b.y)
          b.vy = (b.vy or 0) + math.max(-1, math.min(1, wantY)) * N.ATTACK.homing.turn * step
        end
        b.x = b.x + b.vx * step
        b.y = b.y + b.vy * step
      end
      if not b.lob then b.z = b.z + b.vz * step end
      local alive = true
      if pz > p.z and b.z <= p.z then
        local hw = (b.w or b.r * 2) / 2
        local hh = (b.h or b.r * 2) / 2
        local overlapX = math.abs(b.x - p.x) <= hw + N.PLAYER.R
        local py = p.y or 0
        local overlapY = (b.y - hh) <= py + N.PLAYER.H and (b.y + hh) >= py
        if overlapX and overlapY then
          alive = false
          if p.shield > 0 then
            self.stats.blocked = self.stats.blocked + 1
            emit(self, "blocked", { ball = b.kind })
          else
            self:playerHit(b)
          end
        end
      end
      if b.z < -0.2 then alive = false end
      if alive then keep[#keep + 1] = b end
    end
    self.balls = keep
    -- bits fire now and then
    local A = N.ATTACK.bit
    local keptBits = {}
    for _, bit in ipairs(self.bits) do
      if bit.dead then
        -- "give 'em enough time, and they'll regenerate on you"
        bit.regenT = bit.regenT - step
        if bit.regenT <= 0 then
          bit.dead, bit.hp, bit.fireT = false, A.hp, A.fire_every
          emit(self, "bit_regen", { id = bit.id })
        end
        keptBits[#keptBits + 1] = bit
      elseif bit.hp > 0 then
        bit.fireT = bit.fireT - step
        if bit.fireT <= 0 then
          bit.fireT = A.fire_every
          local vx, vy = towardPlayer(self, bit.x, bit.y, N.ATTACK.small.speed)
          self.balls[#self.balls + 1] = { x = bit.x, y = bit.y, z = bit.z, vx = vx, vy = vy, vz = -N.ATTACK.small.speed,
            r = N.ATTACK.small.r, kind = "bit" }
          emit(self, "bit_fire", { id = bit.id })
        end
        keptBits[#keptBits + 1] = bit
      end
    end
    self.bits = keptBits
  end

  -- ------- the player

  function Sim:updatePlayer(step)
    local p = self.player
    if p.stun > 0 then p.stun = math.max(0, p.stun - step) end
    if p.shield > 0 then p.shield = math.max(0, p.shield - step) end
    if p.shieldCd > 0 then p.shieldCd = math.max(0, p.shieldCd - step) end
    local canMove = p.stun <= 0 and p.burst <= 0
    if canMove then
      local v = N.PLAYER.SPEED * (self.mods.moveMult or 1)
      -- "Those Long Shots Are No Long Shot!": the player is kept at the far end of the box
      -- across and up / down on the stand's plane; "Those Long Shots Are No Long Shot!" keeps
      -- the stand at the far end
      p.z = self.course.farPlayer and 0.04 or (N.PLAYER.Z or 0.1)
      p.x = math.max(-N.PLAYER.X_MAX, math.min(N.PLAYER.X_MAX, p.x + p.mx * v * step))
      p.y = math.max(0, math.min(N.PLAYER.Y_MAX or 0.7, (p.y or 0) + p.mz * v * step))
    end
    if p.charging and p.stun <= 0 then
      p.chargeT = p.chargeT + step
      if p.chargeT >= N.CHARGE.OVER_S then
        p.charging = false
        p.stun = N.CHARGE.STUN_S
        emit(self, "overcharge")
      end
      -- (holding only charges, for every colour: a shot leaves on release, as in the game)
    end
    if p.burst > 0 then
      p.firing = p.firing - step
      if p.firing <= 0 then
        p.firing = N.SHOT.yellow.rapid
        p.burst = p.burst - 1
        self:fire(3, (self.rng() - 0.5) * 0.2)
      end
    end
    self.guts = math.min(1, self.guts + N.GUTS.RATE * (self.mods.gutsRate or 1) * step)
  end

  -- ------- one fixed step

  function Sim:step(step)
    self.t = self.t + step
    if self.phase == "countdown" then
      self.countdown = self.countdown - step
      if self.countdown <= 0 then
        self.phase = "play"
        self.scheduleT0 = self.t
        self.swayT0 = self.t
        self:spawnGroup()
        emit(self, "play")
      end
      return
    end
    if self.phase ~= "play" then return end
    self.remaining = self.remaining - step
    self:updatePlayer(step)
    self:updateAttacks(step)
    self:updateShots(step)
    self:updateBalls(step)
    self:updateGoals(step)
    local bot = self.bot
    bot.scale = math.min(N.BOT.SCALE_MAX, 1 + N.BOT.GROWTH * bot.goalsScored)
    if bot.flinch > 0 then bot.flinch = math.max(0, bot.flinch - step) end
    if (bot.shake or 0) > 0 then bot.shake = math.max(0, bot.shake - step) end
    if bot.aura > 0 then bot.aura = math.max(0, bot.aura - step) end
    if self.course.rageAt and self.score >= self.course.rageAt then bot.mood = "rage" end
    if self.course.calmAt and self.score >= self.course.calmAt then bot.mood = "calm" end
    if self.score >= bot.target then
      emit(self, "bot_pop", { index = self.botIndex, remaining = self.remaining })
      if not self:nextBot() then
        self.phase = "clear"
        emit(self, "clear", { remaining = self.remaining, total = self.totalScore })
      end
      return
    end
    if self.remaining <= 0 then
      self.remaining = 0
      self.phase = "timeout"
      emit(self, "timeout", { total = self.totalScore })
    end
  end

  -- advances by dt in fixed substeps; returns and clears the events
  function Sim:update(dt)
    if not self.paused then
      self.acc = self.acc + math.min(0.1, math.max(0, dt or 0))
      while self.acc >= STEP do
        self.acc = self.acc - STEP
        self:step(STEP)
        if self.phase == "clear" or self.phase == "timeout" then break end
      end
    end
    local ev = self.events
    self.events = {}
    return ev
  end

  -- a driver's shortcut: end the regimen now
  function Sim:forceEnd(outcome)
    if self.phase ~= "play" and self.phase ~= "countdown" then return false end
    if outcome and outcome.clear then
      if outcome.remaining then self.remaining = outcome.remaining end
      self.phase = "clear"
      emit(self, "clear", { remaining = self.remaining, total = self.totalScore, forced = true })
    else
      self.remaining = 0
      self.phase = "timeout"
      emit(self, "timeout", { total = self.totalScore, forced = true })
    end
    return true
  end

  function Sim:state()
    local goals = {}
    for _, g in ipairs(self.goals) do
      local gx, gy = self:goalPos(g)
      goals[#goals + 1] = { kind = g.kind, anchor = g.anchor, x = gx, y = gy, r = g.r * self.bot.scale, age = g.age }
    end
    return {
      phase = self.phase, t = self.t, remaining = self.remaining, score = self.score, total = self.totalScore,
      target = self.bot and self.bot.target, botIndex = self.botIndex, bots = #self.course.bots,
      guts = self.guts, charge = self:chargeStage(), charging = self.player.charging,
      player = { x = self.player.x, y = self.player.y, z = self.player.z, stun = self.player.stun, shield = self.player.shield, shieldCd = self.player.shieldCd },
      goals = goals, shots = #self.shots, balls = #self.balls, bits = #self.bits, barrier = self.barrier ~= nil,
      liveBits = (function() local n = 0; for _, b in ipairs(self.bits) do if not b.dead then n = n + 1 end end; return n end)(),
      energy = self.guts >= N.GUTS.FULL_AT,
      botScale = self.bot and self.bot.scale, aura = self.bot and self.bot.aura, mood = self.bot and self.bot.mood,
      stats = self.stats, countdown = self.countdown,
    }
  end

  return Sim
end
