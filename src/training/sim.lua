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
    s.still = params.still == true
    s.mods = params.mods or { pointMult = 1, shotSize = 1, lossMult = 1, gutsRate = 1, blockLen = 1, moveMult = 1, ballSpeedMult = 1 }
    s.shotType = params.shotType or "black"
    s.level = course.level or 1
    s.isSecret = course.secret ~= nil
    s.anchors = params.anchors or {}
    -- the balloon's shape per bot index (arena_draw.shapeFor): goals live on its cells
    s.shapes = params.shapes or {}
    s.library = params.library or {}
    -- the game's own attack scripts (data/training_attacks.lua): with them the balloons attack as
    -- the game's do; without (a test, an old data file) the course's hand-written script
    s.gameAttacks = params.gameAttacks
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
    self.bot = { national = b.national, species = b.species, art = b.art, mega = b.mega, target = b.score, damage = b.damage, damage2 = b.damage2,
      scale = 1, flinch = 0, aura = 0, mood = "normal", goalsScored = 0 }
    self.shape = self.shapes[self.botIndex]
    self.score = 0
    self.goals, self.balls, self.bits, self.spawnQueue = {}, {}, {}, {}
    self.barrier = nil
    self.groupIndex, self.groupGap, self.groupScored, self.chanceDone = 0, 0, 0, false
    self.scheduleT0 = self.t
    self.chancePending, self.clearPuffAt, self.shieldBrokeAt = nil, nil, nil
    self:startScript()
    if self.botIndex > 1 then
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
    -- (a balloon never grows past the sky's top, SKY_TOP, so its reach is fixed: up to the
    -- grown round balloon's top for the round one)
    if self.shape then return N.BOT.AIM_X, N.BOT.AIM_Y end
    return 1, math.max(1, N.BOT.SKY_TOP)
  end
  function Sim:aim(tx, ty)
    local ex, ey = self:aimExtent()
    self.player.aim.x = math.max(-ex, math.min(ex, tx))
    self.player.aim.y = math.max(0, math.min(ey, ty))
  end
  -- the balloon's centre height (a sprite balloon hovers higher)
  -- the balloon's half height at scale 1, in world units up
  local function botHalfH(self)
    return N.BOT.R * (self.shape and self.shape.halfH or 1) * Sim.ASPECT
  end
  -- the highest its top may reach: SKY_TOP (the top screen's top at the balloon's depth, under
  -- the HUD's band, on the widest screens too) less how far its sway lifts it
  function Sim:skyTop()
    local sway = not self.still and (self.course.sway or (N.BOT.SWAY and N.BOT.SWAY[self.isSecret and "secret" or self.level]))
    local _, _, _, _, hu = Sim.view()
    return N.BOT.SKY_TOP - (sway and math.abs(sway.ay or 0) * (160 / 240) / hu or 0)
  end
  -- the most it may inflate: from just above the grass (FEET_MIN) to skyTop, no more
  function Sim:growMax()
    return math.max(1, (self:skyTop() - N.BOT.FEET_MIN) / (2 * botHalfH(self)))
  end
  function Sim:botCY()
    local base = self.shape and N.BOT.SHAPE_CY or N.BOT.CY
    local bot = self.bot
    local s = bot and bot.scale or 1
    if s <= 1 then return base end
    -- grown, it rises about its feet; one that would pass the sky's top sinks toward the grass
    -- instead, so every goal stays on the screen (growMax caps the size)
    local hh = botHalfH(self)
    local cy = math.min(base + (s - 1) * hh, self:skyTop() - hh * s)
    return math.max(cy, math.min(base, N.BOT.FEET_MIN + hh * s))
  end
  function Sim:chanceUp()
    for _, g in ipairs(self.goals) do if g.kind == "chance" then return true end end
    return false
  end
  function Sim:pause(on) self.paused = on and true or false end

  -- the guard (DllSparring.cro 0x23d0-0x2594): raised while L / R (or the block button) is
  -- held, for at most its length; let go or run out, the cooldown before it can rise again.
  -- Not while stopped, hit or in the pause after a Charged Shot.
  function Sim:block()
    local p = self.player
    if self.phase ~= "play" or p.shield > 0 or p.shieldCd > 0 or p.stun > 0 or (p.lock or 0) > 0 then return false end
    p.shield = self.mods.blockS or (N.BLOCK.LEN * (self.mods.blockLen or 1))
    emit(self, "block_up")
    return true
  end

  -- the shield drops: it shatters (the pieces fly for SHATTER_S), the cooldown starts
  local function shieldDown(self, why)
    local p = self.player
    p.shield, p.breakT = 0, nil
    p.shieldCd = self.mods.blockS and N.BLOCK.COOLDOWN_F / N.CHARGE.FPS or N.BLOCK.COOLDOWN
    p.shatter = N.BLOCK.SHATTER_S
    emit(self, "block_down", { why = why })
  end

  function Sim:unblock()
    local p = self.player
    if p.shield <= 0 then return false end
    shieldDown(self, "released")
    return true
  end

  -- the game's charge (DllSparring.cro 0x2598-0x29ac): a press starts it whatever the meter
  -- holds; frames held from the press make it Charged (stage 1) then full (stage 2); held past
  -- FIZZLE_F it breaks and the Pokemon stops for STUN_F; a Charged Shot is followed by AFTER_F
  -- with no shot or charge (p.lock)
  local CF = N.CHARGE.FPS
  function Sim:pressFire()
    local p = self.player
    if self.phase ~= "play" or p.stun > 0 or (p.lock or 0) > 0 then return false end
    p.charging = true
    p.chargeT = 0
    p.rapidT = 0
    return true
  end

  -- 0 (a plain shot), 1 (Charged), 2 (full)
  function Sim:chargeStage()
    local p = self.player
    if not p.charging then return 0 end
    local f = p.chargeT * CF
    if f >= N.CHARGE.STAGE_F[2] then return 2 end
    if f >= N.CHARGE.STAGE_F[1] then return 1 end
    return 0
  end

  -- how far a Charged Shot has risen from stage 1 to full: 0..1 (nil before stage 1)
  function Sim:chargeRise()
    local p = self.player
    if not p.charging then return nil end
    local f = p.chargeT * CF
    if f < N.CHARGE.STAGE_F[1] then return nil end
    return math.min(1, (f - N.CHARGE.STAGE_F[1]) / (N.CHARGE.STAGE_F[2] - N.CHARGE.STAGE_F[1]))
  end

  -- the meter covers a plain shot (the game's ready flag, [r4+0x2a5]: the two rings)
  function Sim:shotReady()
    local species = N.SHOT[self.shotType] or N.SHOT.black
    return self.guts >= species.cost - 1e-9
  end

  function Sim:releaseFire()
    local p = self.player
    if not p.charging then return false end
    -- where this shot was aimed: the top screen marks it so the next one can be corrected
    p.lastShot = { x = p.aim.x, y = p.aim.y }
    local stage, rise = self:chargeStage(), self:chargeRise()
    p.charging = false
    if self.phase ~= "play" or p.stun > 0 or p.shield > 0 then return false end
    if self.shotType == N.SHOT.RAPID and stage >= 2 then
      p.burst = N.CHARGE.YELLOW_BURST
      p.firing = 0
      return true
    end
    -- too soon after the last shot (SHOT.REFIRE_S): the tap fires nothing
    if (p.refire or 0) > 0 then return false end
    self:fire(stage, nil, rise)
    if stage >= 1 then p.lock = N.CHARGE.AFTER_F / CF end
    p.refire = N.SHOT.REFIRE_S or 0
    return true
  end

  -- ------- shooting

  -- the live bit nearest the reticle on screen (the aim on the balloon's plane, ax / ay), when
  -- the reticle is within the bit's drawn disk plus the shot's radius; nil otherwise
  function Sim:bitUnder(ax, ay, shotR)
    local sx, sy = Sim.project(ax, ay, 1)
    local best, bestD = nil, nil
    for _, bit in ipairs(self.bits) do
      if not bit.dead and bit.hp > 0 then
        local bx, by, k = Sim.project(bit.x, bit.y, bit.z)
        local reach = (bit.r + (shotR or 0)) * V.NEAR.hw * k
        local d = (sx - bx) ^ 2 + (sy - by) ^ 2
        if d <= reach * reach and (not bestD or d < bestD) then best, bestD = bit, d end
      end
    end
    return best
  end

  -- the game's shot (DllSparring.cro 0x2f08-0x3180): the species' colour while the meter covers
  -- its cost (a Charged Shot's from table B), else the weak shot, free; the points are the
  -- shot's power - P x the colour's power, at least 1 - a Charged Shot's rising from x1 at
  -- stage 1 to x(1 + MULT_RISE) at full (`rise` 0..1); P unknown (a fake host): the level's base
  function Sim:fire(stage, spread, rise)
    local p = self.player
    stage = stage or 0
    local charged = stage >= 1
    local species = N.SHOT[self.shotType] or N.SHOT.black
    local cost = charged and species.chargedCost or species.cost
    local def, kind, weak = species, self.shotType, false
    if cost > self.guts + 1e-9 then
      def, kind, weak, cost = N.SHOT.weak, "weak", true, 0
      charged = false
    end
    self.guts = math.max(0, self.guts - cost)
    local points
    if self.mods.power then
      points = math.max(1, math.floor(self.mods.power * def.mult))
    else
      local base = self.isSecret and N.POINTS.BASE.secret or (N.POINTS.BASE[self.level] or N.POINTS.BASE[1])
      points = base * def.mult
    end
    if charged then points = points * (1 + N.CHARGE.MULT_RISE * (rise or 0)) end
    points = points * (self.mods.pointMult or 1)
    local r = def.r * (self.mods.shotSize or 1)
    local speed = def.speed * (N.SHOT.SPEED_SCALE or 1) * (charged and def.chargedSpeed or 1) * (self.mods.ballSpeedMult or 1)
    local ax = p.aim.x + (spread or 0)
    local ay = p.aim.y
    local x0, y0, z0 = p.x, (p.y or 0) + 0.15, p.z
    local dz = math.max(0.05, 1 - z0)
    local vx, vy = (ax - x0) / dz * speed, (ay - y0) / dz * speed
    -- the reticle over a bit (in front of the balloon) aims at the bit: the shot flies through
    -- it, as the shot otherwise crosses the bit's depth short of where the reticle shows it
    local bit = self:bitUnder(ax, ay, r)
    if bit then
      local bz = math.max(0.05, bit.z - z0)
      vx, vy = (bit.x - x0) / bz * speed, (bit.y - y0) / bz * speed
    end
    local shot = { x = x0, y = y0, z = z0, vz = speed, vx = vx, vy = vy,
      r = r, points = math.floor(points + 0.5), type = kind, stage = charged and stage or 0, weak = weak, energy = charged }
    self.shots[#self.shots + 1] = shot
    self.stats.shots = self.stats.shots + 1
    if shot.energy then self.stats.energyShots = (self.stats.energyShots or 0) + 1 end
    emit(self, weak and "weak_shot" or "shot_fired", { stage = shot.stage, type = shot.type, energy = shot.energy })
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
    -- (`still`: a test's balloon that does not sway)
    local sway = not self.still and (self.course.sway or (N.BOT.SWAY and N.BOT.SWAY[self.isSecret and "secret" or self.level]))
    if sway and self.phase ~= "countdown" then
      -- (its own clock, held while it stands frozen after a cleared group)
      local w = 2 * math.pi * (self.swayT or 0) / sway.period
      x = x + math.sin(w) * sway.ax * 0.6 / hw
      -- (fig8: up and down twice a sway, a figure of eight - Magnezone)
      y = y + math.sin(sway.fig8 and 2 * w or (w + math.pi / 2)) * sway.ay * (160 / 240) / hu
    end
    local bot = self.bot
    if bot and (bot.shake or 0) > 0 then
      local scale = N.BOT.SHAKE_SCALE and N.BOT.SHAKE_SCALE[self.isSecret and "secret" or self.level] or 1
      local k = bot.shake / N.BOT.SHAKE_S * scale
      local u = N.BOT.SHAKE_S - bot.shake
      x = x + math.sin(u * N.BOT.SHAKE_HZ * 2 * math.pi) * N.BOT.SHAKE_PX * k * 0.6 / hw
      y = y + math.sin(u * N.BOT.SHAKE_HZ * 4 * math.pi + 1) * N.BOT.SHAKE_PX * 0.2 * k * (160 / 240) / hu
    end
    -- the throw: it dips through the wind-up, snaps up as it lets go and holds there while the
    -- ball flies, then settles (N.BOT.WINDUP, game px)
    if bot then
      local W = self.course.windup or N.BOT.WINDUP
      local dy = 0
      if bot.windup then
        local u = math.min(1, bot.windup.t / math.max(0.05, bot.windup.len))
        if u < W.DIP_AT then dy = -W.DIP_PX * math.sin(math.pi / 2 * u / W.DIP_AT)
        else
          local v = (u - W.DIP_AT) / (1 - W.DIP_AT)
          dy = -W.DIP_PX + (W.DIP_PX + W.RISE_PX) * v * v
        end
      elseif (bot.thrown or 0) > 0 then
        local v = bot.thrown / W.HOLD_S
        dy = W.RISE_PX * math.min(1, v * 3)
      end
      if dy ~= 0 then y = y + dy * (160 / 240) / hu end
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

  local goalTimer
  local function wanderOf(self, goal)
    local W = N.GOALS.WANDER
    local a = goal.anchor and self.anchors[goal.anchor] or {}
    local speed = W.SPEED[self.isSecret and "secret" or self.level] or W.SPEED[1]
    local radius = W.RADIUS
    if a.motion then speed, radius = math.max(speed, W.MOTION_SPEED), W.MOTION_RADIUS end
    -- the shield's target roams the whole balloon
    if goal.kind == "marker" then return W.MARKER_SPEED or 0, math.huge end
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
    if goal.orbit then
      local o = goal.orbit
      local bx, by = self:botOffset()
      return bx + math.cos(o.a) * o.r, self:botCY() + by + (o.up + math.sin(o.a) * o.r) * Sim.ASPECT
    end
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

  -- the course's goal timer (N.GOALS.TIMER: white, gone, cycle seconds; Wooble's captures)
  function goalTimer(self)
    local T = N.GOALS.TIMER
    return (T and (T[self.course.id] or T[self.isSecret and "secret" or self.level] or T.default))
      or { white = N.GOALS.YELLOW_AT, gone = N.GOALS.GONE_AT, cycle = N.GOALS.GONE_AT + 1 }
  end
  Sim.goalTimer = goalTimer

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
    -- under a shield the balloon's goals are hidden and their timer held (the target is not)
    local shielded = self.barrier and self.barrier.script
    for _, g in ipairs(self.goals) do
      g.hidden = shielded and g.kind ~= "marker" or nil
      if not g.hidden then g.age = g.age + step end
      if g.orbit then g.orbit.a = g.orbit.a + g.orbit.w * step end
      local alive = true
      if g.kind == "white" and g.age >= goalTimer(self).white then
        g.kind = "fading"
        emit(self, "goal_yellow", { anchor = g.anchor })
      end
      if (g.kind == "fading") and g.age >= goalTimer(self).gone then
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
            -- it freezes, puffs air from its sides, and the red goal comes a moment later
            self.chancePending = N.GOALS.CHANCE_DELAY_S
            self.clearPuffAt = self.t
            self.chanceDone = true
            emit(self, "group_cleared", { chance = true })
            return
          end
          self.chanceDone = true
        end
        self.groupGap = self.groupGap + step
        -- a cleared group: the next GROUP_GAP_S later; one that ran out: on the course's own
        -- cycle from when it came (at least MIN_GAP_S after it went)
        local gap = N.GOALS.GROUP_GAP_S
        if (self.groupScored or 0) == 0 then
          local tm = goalTimer(self)
          gap = math.max(N.GOALS.MIN_GAP_S or 0.4, tm.cycle - tm.gone)
        end
        if self.groupGap >= gap then
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
    if not B or ball.w or ball.h or ball.kind == "bit" or ball.game then return ball end
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

  -- ------- the game's attack scripts (data/training_attacks.lua; DllSparring.cro's runner at
  -- 0xb048): each balloon loops its step list - a telegraph (the warning mark), a pose, the
  -- action (a volley, bits, a timed routine), its repeats, a recovery - its times in units the
  -- phase's rate takes off a frame; between steps the second form is checked (score left %),
  -- which swaps the list, rate and damage. A volley's shots leave their frames apart, each aimed
  -- (or not) on its own; a projectile flies straight with its wave and homing added each frame.

  local GA = N.ATTACK.GAME
  local FPS = 30
  local raiseShield

  -- this balloon's phase: the course's phase for the bot, the version's line for the finale
  function Sim:startScript()
    local D = self.gameAttacks
    self.script = nil
    if not (D and D.courses and D.phases) then return end
    local ids = D.courses[self.course.id]
    local b = self.course.bots and self.course.bots[1]
    if ids and b and D.phases[ids[1]] and D.phases[ids[1]].species ~= b.national then
      ids = D.courses[self.course.id .. "_omega"] or ids
    end
    local pid = ids and ids[self.botIndex]
    local ph = pid and D.phases[pid]
    if not ph then return end
    self.script = { phase = ph, form = false, list = ph.list, idx = 0, stage = "next", left = 0, reps = 0 }
  end

  -- the second form: on while the score left is at most its entry % and not at most its exit %
  local function formOn(self, ph)
    if ph.formIn ~= 0 then return false end
    local target = self.bot and self.bot.target or 1
    local left = math.max(0, target - self.score) / math.max(1, target) * 100
    return left <= ph.formInPct and not (left <= ph.formOutPct)
  end

  -- a shot of a volley, built when it leaves: aimed at where the trainee is now (per axis)
  local function gameBall(self, shot)
    local D = self.gameAttacks
    local P = D.projectiles[shot.p]
    if not P then return nil end
    local p = self.player
    local U = GA.UNIT
    local lx, ly = shot.dx * U, self:botCY() + shot.dy * U
    local tx = shot.aimX == 1 and p.x or lx
    local ty = shot.aimY == 1 and ((p.y or 0) + N.PLAYER.H / 2) or ly
    -- in the game's units: across, up, and the depth to the trainee; turned by the aim offsets
    local gx, gy, gz = (tx - lx) / U, (ty - ly) / U, GA.DEPTH
    local yaw, pitch = math.rad((shot.yaw or 0) * (GA.ANGLE_DEG or 1)), math.rad((shot.pitch or 0) * (GA.ANGLE_DEG or 1))
    gx, gz = gx * math.cos(yaw) + gz * math.sin(yaw), -gx * math.sin(yaw) + gz * math.cos(yaw)
    gy, gz = gy * math.cos(pitch) + gz * math.sin(pitch), -gy * math.sin(pitch) + gz * math.cos(pitch)
    local len = math.sqrt(gx * gx + gy * gy + gz * gz)
    if len < 1e-6 then return nil end
    -- (ATTACK.TEMPO: the balls' own motion - flight, wave, homing - runs this much faster than
    -- the game's, with the trainee's movement: a flat field wants quicker play than its 3D one)
    local tempo = N.ATTACK.TEMPO or 1
    local v = P.speed * FPS * (self.mods.botSpeedMult or 1) * tempo
    -- its hit size is its size as drawn when it reaches the trainee (GA.DRAWN), so what is seen
    -- to touch the trainee hits it and what is seen to pass does not
    -- (a wide or tall ball's long side STRETCHed further, so its shape reads; gsx / gsy are the
    -- sizes it is drawn and hit by)
    local K, pz = GA.DRAWN.PX_PER_UNIT * GA.DRAWN.GROW, p.z or N.PLAYER.Z
    local gsx, gsy = P.sx, P.sy
    if gsx > gsy * 1.01 then gsx = gsx * (GA.STRETCH or 1) elseif gsy > gsx * 1.01 then gsy = gsy * (GA.STRETCH or 1) end
    local hw, hh = gsx * K / lerp(V.NEAR.hw, V.FAR.hw, pz), gsy * K / lerp(V.NEAR.hu, V.FAR.hu, pz)
    local ball = { x = lx, y = ly, z = 1, bx = lx, by = ly, t0 = self.t, game = P,
      vx = gx / len * v * U, vy = gy / len * v * U, vz = -gz / len * v * GA.DEPTH_UNIT,
      r = math.max(hw, hh), kind = Sim.homes(P) and "homing" or (math.max(hw, hh) > 0.1 and "big" or "small") }
    ball.w, ball.h, ball.gsx, ball.gsy = hw * 2, hh * 2, gsx, gsy
    -- frames to the trainee's depth; its homing so far (steerHoming)
    ball.flightN = (1 - p.z) / math.max(1e-6, -ball.vz) * FPS
    ball.hox, ball.hoy, ball.tempo = 0, 0, tempo
    return ball
  end
  Sim.gameBall = gameBall

  -- a projectile's lateral offset after n frames: its wave, and its homing on the trainee now
  -- the homing kinds (the blue and black balls): both ways, or a strong pull one way; a weak
  -- pull one way only (Golem's pillars) is a regular ball stretched, flying straight (Wooble)
  function Sim.homes(P)
    local SK = N.ATTACK.HOMING.STRONG_K
    local hx, hy = P and (P.homeX or 0) or 0, P and (P.homeY or 0) or 0
    return (hx > 0 and hy > 0) or (hx > 0 and hx <= SK) or (hy > 0 and hy <= SK)
  end

  -- whether a ball at (x, y) on the trainee's depth hits it: a game ball's ellipse (its size as
  -- drawn) touching the trainee's box (R either side, H up from its feet); others by their box
  local function ballHits(self, b, x, y)
    local p = self.player
    local hw = (b.w or b.r * 2) / 2
    local hh = (b.h or b.r * 2) / 2
    local py = p.y or 0
    if b.game then
      local dx = math.max(0, math.abs(x - p.x) - N.PLAYER.R)
      local dy = math.max(0, py - y, y - (py + N.PLAYER.H))
      return (dx / hw) ^ 2 + (dy / hh) ^ 2 <= 1
    end
    return math.abs(x - p.x) <= hw + N.PLAYER.R and (y - hh) <= py + N.PLAYER.H and (y + hh) >= py
  end

  -- a projectile's wave after n frames (the game's 0x155ec)
  local function gameWave(b, n)
    local P, U = b.game, GA.UNIT
    n = n * (b.tempo or 1)   -- (its own clock: the game's frames at ATTACK.TEMPO)
    local ox = P.ampX * math.cos(P.phase + n * P.freqX) * (1 + n * P.growX) * U
    local oy = P.ampY * math.sin(P.phase + n * P.freqY) * (1 + n * P.growY) * U
    return ox, oy
  end
  local function gameOffset(self, b, n)
    local ox, oy = gameWave(b, n)
    return ox + (b.hox or 0), oy + (b.hoy or 0)
  end

  -- homing (Wooble 2026-10-23, skill over the game's pull): a homing ball steers toward where
  -- the trainee is now on each axis it homes, no faster than HOMING.SPEED (slower than the
  -- trainee moves), and flies straight over its last HOLD_S - a trainee standing still is met,
  -- one that moves away early enough outruns it; a wide ball homes across only (up or down
  -- escapes it), a tall one up and down only (across escapes it)
  -- the axes a homing ball steers on: a strong pull one way (k <= STRONG_K: the wide ball's
  -- across, the tall ball's up and down) is its only one - its weak other pull does not home;
  -- else every axis it pulls on (the round balls, both)
  local function homingAxes(P)
    local SK = N.ATTACK.HOMING.STRONG_K
    local hx, hy = P.homeX or 0, P.homeY or 0
    local sx, sy = hx > 0 and hx <= SK, hy > 0 and hy <= SK
    if sx or sy then return sx, sy end
    return hx > 0, hy > 0
  end
  Sim.homingAxes = homingAxes
  local function homingWant(self, b, n, bx, by)
    local p = self.player
    local wx, wy = gameWave(b, n)
    return p.x - (bx + wx), (p.y or 0) + N.PLAYER.H / 2 - (by + wy)
  end
  local function steerHoming(self, b, step)
    local P, H = b.game, N.ATTACK.HOMING
    if not Sim.homes(P) then return end
    local n = (self.t - b.t0) * FPS
    local k = b.tempo or 1
    if ((b.flightN or 60) - n) / FPS <= H.HOLD_S / k then return end
    local tx, ty = homingWant(self, b, n, b.bx, b.by)
    local d = H.SPEED * k * step
    local ax, ay = homingAxes(P)
    if ax then b.hox = b.hox + math.max(-d, math.min(d, tx - b.hox)) end
    if ay then b.hoy = b.hoy + math.max(-d, math.min(d, ty - b.hoy)) end
  end

  local function fireVolley(self, vid)
    local shots = self.gameAttacks.volleys and self.gameAttacks.volleys[vid]
    if not shots then return end
    local delay = 0
    for _, shot in ipairs(shots) do
      self.spawnQueue[#self.spawnQueue + 1] = { at = self.t + delay / FPS, shot = shot }
      delay = delay + (shot.next or 0)
    end
    emit(self, "attack_launch", { attack = "volley", volley = vid })
    return delay
  end

  -- the balloon's shield and the target that breaks it (a marker goal that roams its shape)
  function raiseShield(self, secs)
    if self.barrier then return end
    local S = N.ATTACK.SHIELD
    local own = S.COURSE and S.COURSE[self.course.id]
    if own then S = setmetatable(own, { __index = N.ATTACK.SHIELD }) end
    self.barrier = { t = 0, marker = "center", maxS = (secs or N.ATTACK.barrier.max_s) + (S.TAIL_S or 0), script = true }
    -- the target circles the balloon (screen angles: y down, so the world's is their negative)
    self.goals[#self.goals + 1] = { kind = "marker", age = 0, r = N.GOALS.MARKER_R, hits = 0,
      orbit = { a = math.rad(-S.START_DEG), w = math.rad(S.DEG_S), r = S.ORBIT_R, up = S.ORBIT_UP } }
    emit(self, "barrier_up")
  end

  local function spawnBits(self, n)
    local A = N.ATTACK.bit
    local alive = 0
    for _, bit in ipairs(self.bits) do if not bit.dead then alive = alive + 1 end end
    local rec = self.script.phase.bits and self.gameAttacks.bits and self.gameAttacks.bits[self.script.phase.bits]
    local own = GA.BITS and GA.BITS[self.course.id] or {}
    local xs = own.x or GA.BIT_X
    for _ = 1, math.min(n, GA.MAX_BITS - alive) do
      local slot = #self.bits + 1
      local x = xs[(slot - 1) % #xs + 1]
      -- each circles its own loop (clockwise on screen), all firing together
      self.bits[#self.bits + 1] = { id = slot, x = x, y = A.y, z = A.z, hp = A.hp, r = A.r, cx = x, cy = A.y,
        loopA = slot * 2.1, fireT = GA.BIT_FIRST_S, damage = rec and rec.damage, game = true,
        every = own.every and own.every[(slot - 1) % #own.every + 1] or GA.BIT_EVERY_F }
    end
    emit(self, "bits_spawned", { n = n })
  end

  function Sim:runScript(step)
    local sc = self.script
    local D = self.gameAttacks
    local ph = sc.phase
    local units = ((sc.form and ph.rateB) or ph.rate) * FPS * step
    sc.left = sc.left - units
    -- (a step of no time at all moves straight on; a list of only those waits a frame)
    local guard = 0
    while sc.left <= 0 and guard < 64 do
      guard = guard + 1
      local st = D.steps[(D.lists[sc.list] or {})[sc.idx]]
      if sc.stage == "next" then
        -- between steps: the second form (a new list, rate and damage), then the next step
        local f = formOn(self, ph)
        if f ~= sc.form then
          sc.form = f
          sc.list = f and ph.listB or ph.list
          self.bot.mood = f and (ph.damageB or 0) >= (ph.damage or 0) and "rage" or "normal"
          emit(self, "form_change", { form = f and "B" or "A" })
        end
        local list = D.lists[sc.list] or {}
        if #list == 0 then sc.left = 1e9; return end
        sc.idx = sc.idx % #list + 1
        st = D.steps[list[sc.idx]]
        sc.reps = st and st.repeats or 0
        if st and st.warn > 0 and st.cmd ~= 0 then
          sc.stage, sc.left = "warn", sc.left + st.warn
          if st.mark == 1 then
            self.bot.aura = st.warn / (((sc.form and ph.rateB) or ph.rate) * FPS)
            emit(self, "attack_telegraph", { attack = "volley" })
          end
        else
          sc.stage = "pose"
        end
      elseif sc.stage == "shield" then
        if self.barrier then sc.left = 0; return end
        sc.stage, sc.left = "recover", sc.left + math.max(0, st and st.recover or 0)
      elseif sc.stage == "warn" then
        sc.stage = "pose"
      elseif sc.stage == "pose" then
        if st and st.cmd ~= 0 then
          local own = GA.COURSE and GA.COURSE[self.course.id] or {}
          local key = (st.fire and st.fire >= 0) and st.fire
            or (st.cmd == 2 and own.shieldKey) or own.key
            or (GA.FIRE_KEY_COURSE and GA.FIRE_KEY_COURSE[self.course.id]) or GA.FIRE_KEY_U
          sc.stage, sc.left = "act", sc.left + key
          -- the balloon winds up for the throw (drawn: a dip, then up as it lets go)
          if st.cmd >= 84 then self.bot.windup = { t = 0, len = key / (((sc.form and ph.rateB) or ph.rate) * FPS) } end
        else
          -- a wait: its recovery and the idle pose played out
          local own = GA.COURSE and GA.COURSE[self.course.id]
          local pose = st and st.pose or 0
          local extra = (own and own.pose and own.pose[pose]) or (GA.WAIT_POSE_U and GA.WAIT_POSE_U[pose]) or 0
          sc.stage, sc.left = "recover", sc.left + (st and st.recover or 45) + extra
        end
      elseif sc.stage == "act" then
        if st.cmd >= 84 then
          local frames = fireVolley(self, st.cmd - 84)
          self.bot.windup, self.bot.thrown = nil, (self.course.windup or N.BOT.WINDUP).HOLD_S
          -- the recovery runs from the stream's last ball
          sc.left = sc.left + (frames or 0) * ((sc.form and ph.rateB) or ph.rate)
        elseif st.cmd == 3 then spawnBits(self, st.count)
        elseif st.cmd == 2 then
          -- the shield (Wooble: Graveler): up for at most `count` frames with a moving yellow
          -- target on it; the balloon takes no goal while it stands and its script waits until
          -- the target is hit or the time runs out
          raiseShield(self, st.count / FPS)
          sc.stage, sc.left = "shield", 0
        end
        if sc.stage == "shield" then
          -- (handled below, each frame)
        elseif sc.reps > 0 then
          sc.reps = sc.reps - 1
          sc.left = sc.left + math.max(1, st.repeatGap)
        else
          sc.stage, sc.left = "recover", sc.left + math.max(0, st.recover)
        end
      else
        sc.stage = "next"
      end
    end
  end

  local function tickBarrier(self, step)
    if self.barrier then
      self.barrier.t = self.barrier.t + step
      if self.barrier.t >= self.barrier.maxS then
        -- run out: it breaks up as when its target is hit, the target gone
        self.barrier = nil
        self.shieldBrokeAt = self.t
        emit(self, "barrier_down", { timed = true })
      end
    end
  end

  function Sim:updateAttacks(step)
    if self.script then
      tickBarrier(self, step)
      self:runScript(step)
      -- a volley's shots leave on their frames, built then (aimed at the trainee as it is)
      if #self.spawnQueue > 0 then
        local keep = {}
        for _, q in ipairs(self.spawnQueue) do
          if self.t >= q.at then
            local ball = q.ball or gameBall(self, q.shot)
            if ball then self.balls[#self.balls + 1] = ball end
          else keep[#keep + 1] = q end
        end
        self.spawnQueue = keep
      end
      return
    end
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
    tickBarrier(self, step)
  end

  -- ------- shots against bits and goals

  function Sim:hitGoal(goal, shot)
    local pts = shot.points
    if goal.kind == "chance" then pts = math.floor(pts * N.POINTS.CHANCE_MULT + 0.5) end
    if goal.kind == "marker" then
      -- the target hit: the shield shatters away (drawn from shieldBrokeAt)
      self.barrier = nil
      self.shieldBrokeAt = self.t
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
          -- where it crosses the bit's depth (a fast shot moves far in one step)
          local f = (bit.z - pz) / math.max(1e-6, sh.z - pz)
          local dx = sh.x - sh.vx * step * (1 - f) - bit.x
          local dy = sh.y - sh.vy * step * (1 - f) - bit.y
          if dx * dx + dy * dy <= (bit.r + sh.r) ^ 2 then
            bit.hp = bit.hp - 1
            alive = false
            if bit.hp <= 0 then
              self.stats.bitsPopped = self.stats.bitsPopped + 1
              bit.dead, bit.regenT, bit.poppedAt = true, N.ATTACK.bit.regen_s, self.t
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
          local shown = not g.hidden and not (g.kind == "marker" and g.orbit and g.age < N.ATTACK.SHIELD.FADE_IN_S)
          if not g.dead and shown then
            local gx, gy = self:goalPos(g)
            local rr = g.r + sh.r
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
    -- the balloon's own damage (the game's course data; its second form's once enraged), a
    -- bitbot's shot a share of it; without it, ours by the ball's kind and the level
    local bot = self.bot
    local loss
    local sc = self.script
    if ball.damage then
      -- a bitbot's own shot damage (the game's bit record)
      loss = math.max(1, math.floor(ball.damage * (self.mods.lossMult or 1)))
    elseif sc then
      -- the phase's damage, its second form's while that is on
      local ph = sc.phase
      loss = (sc.form and ph.damageB and ph.damageB > 0) and ph.damageB or ph.damage
      loss = math.max(1, math.floor(loss * (self.mods.lossMult or 1)))
    elseif bot and bot.damage then
      loss = (bot.mood == "rage" and bot.damage2) or bot.damage
      if ball.kind == "bit" then loss = loss * N.DAMAGE.BIT_SHARE end
      loss = math.max(1, math.floor(loss * (self.mods.lossMult or 1)))
    else
      local levelMult = self.isSecret and N.DAMAGE.LEVEL_MULT.secret or (N.DAMAGE.LEVEL_MULT[self.level] or 1)
      loss = (N.DAMAGE[ball.kind] or N.DAMAGE.small) * (self.mods.lossMult or 1) * levelMult
      if bot and bot.mood == "rage" then loss = loss * N.BOT.RAGE_DAMAGE end
    end
    if self.course.suddenDeath then loss = N.DAMAGE.SUDDEN_DEATH end
    loss = math.floor(loss + 0.5)
    local before = self.score
    self.score = math.max(0, self.score - loss)
    self.totalScore = math.max(0, self.totalScore - (before - self.score))
    -- knocked back (no moving or charging), then untouchable a moment
    p.stun = N.PLAYER.HIT_STUN_S
    p.safe = N.PLAYER.HIT_SAFE_F / N.CHARGE.FPS
    p.charging = false
    p.burst = 0
    self.stats.damageTaken = self.stats.damageTaken + (before - self.score)
    self.stats.playerHits = self.stats.playerHits + 1
    emit(self, "player_hit", { loss = before - self.score, ball = ball.kind, score = self.score })
  end

  -- a ball still on its way: the seconds until it reaches the trainee's depth, whether it
  -- would hit the trainee if the trainee stayed where it is (the hit test below, at its place
  -- then: a game ball's wave and homing laid over, a lob at its landing), and where it crosses
  -- that depth (x, y); nil when it is past,
  -- bounced, or never comes
  function Sim:ballEta(b)
    local p = self.player
    if b.bounced or b.z <= p.z then return nil end
    local t, x, y
    if b.lob then
      local L = b.lob
      t = math.max(0, L.T - L.t)
      x, y = L.tx, L.ty
    else
      local vz = b.vz or 0
      if vz >= -1e-6 then return nil end
      t = (b.z - p.z) / -vz
      if b.game then
        local n = (self.t + t - b.t0) * FPS
        local bx, by = b.bx + b.vx * t, b.by + b.vy * t
        local ox, oy = gameOffset(self, b, n)
        local P, H = b.game, N.ATTACK.HOMING
        if Sim.homes(P) then
          local k = b.tempo or 1
          local steer = math.max(0, math.min(t, ((b.flightN or 60) - (self.t - b.t0) * FPS) / FPS - H.HOLD_S / k))
          local d = H.SPEED * k * steer
          local tx, ty = homingWant(self, b, n, bx, by)
          local ax, ay = homingAxes(P)
          if ax then ox = ox + math.max(-d, math.min(d, tx - b.hox)) end
          if ay then oy = oy + math.max(-d, math.min(d, ty - b.hoy)) end
        end
        x, y = bx + ox, by + oy
      elseif b.ring then
        x, y = b.x, b.y
      else
        x, y = b.x + (b.vx or 0) * t, b.y + (b.vy or 0) * t
      end
    end
    local hits
    if b.lob then
      local hw, hh, py = (b.w or b.r * 2) / 2, (b.h or b.r * 2) / 2, p.y or 0
      hits = math.abs(x - p.x) <= hw + N.PLAYER.R and (y - hh) <= py + N.PLAYER.H and (y + hh) >= py
    else
      hits = ballHits(self, b, x, y)
    end
    return t, hits, x, y
  end

  function Sim:updateBalls(step)
    local p = self.player
    local keep = {}
    for _, b in ipairs(self.balls) do
      local pz = b.z
      if b.bounced then
        -- knocked back off the shield: away, up and back toward the balloon; it hits nothing
        b.x = b.x + b.vx * step
        b.y = b.y + b.vy * step
        b.z = b.z + b.vz * step
      elseif b.lob then
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
      elseif b.game then
        -- straight along its line, its wave and homing laid over (the game's 0x155ec)
        b.bx = b.bx + b.vx * step
        b.by = b.by + b.vy * step
        steerHoming(self, b, step)
        local ox, oy = gameOffset(self, b, (self.t - b.t0) * FPS)
        b.x, b.y = b.bx + ox, b.by + oy
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
      if not b.lob and not b.bounced then b.z = b.z + b.vz * step end
      local alive = true
      if not b.bounced and pz > p.z and b.z <= p.z then
        local overlap = ballHits(self, b, b.x, b.y)
        local overlapX, overlapY = overlap, overlap
        if overlapX and overlapY and (p.safe or 0) > 0 then
          -- untouchable a moment (just hit, or a ball just stopped): it breaks on the trainee
          -- all the same, harmless, rather than flying on into the camera
          alive = false
          emit(self, "ball_absorbed", { ball = b.kind })
        elseif overlapX and overlapY then
          alive = false
          if p.shield > 0 then
            -- a stopped ball: it bounces off, the shield breaks a moment later, and the trainee
            -- is untouchable a while
            self.stats.blocked = self.stats.blocked + 1
            p.safe = N.BLOCK.SAFE_F / N.CHARGE.FPS
            p.breakT = p.breakT or N.BLOCK.BREAK_F / N.CHARGE.FPS
            alive = true
            b.bounced, b.game = true, nil
            local side = (b.x >= p.x) and 1 or -1
            b.vx = side * (0.6 + 0.4 * self.rng())
            b.vy = 1.4
            b.vz = math.abs(b.vz or 0.8) * 0.9 + 0.3
            emit(self, "blocked", { ball = b.kind })
          else
            self:playerHit(b)
          end
        end
      end
      if b.z < -0.2 then alive = false end
      if b.bounced and (b.z > 1.4 or b.y > 3 or math.abs(b.x) > 3) then alive = false end
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
          bit.dead, bit.hp, bit.fireT, bit.poppedAt = false, A.hp, A.fire_every, nil
          emit(self, "bit_regen", { id = bit.id })
        end
        keptBits[#keptBits + 1] = bit
      elseif bit.hp > 0 then
        if bit.cx then
          bit.loopA = bit.loopA - 2 * math.pi / GA.BIT_LOOP_S * step
          bit.x = bit.cx + math.cos(bit.loopA) * GA.BIT_LOOP_R
          bit.y = bit.cy + math.sin(bit.loopA) * GA.BIT_LOOP_R
        end
        bit.fireT = bit.fireT - step
        if bit.fireT <= 0 then
          if bit.game then
            -- the game's: every BIT_EVERY_F, straight at where the trainee is now
            bit.fireT = (bit.every or GA.BIT_EVERY_F) / FPS
            local G = GA
            local speed = G.BIT_SPEED * FPS * G.DEPTH_UNIT * (N.ATTACK.TEMPO or 1)
            local t = math.max(1e-3, (bit.z - self.player.z) / speed)
            local vx = (self.player.x - bit.x) / t
            local vy = ((self.player.y or 0) + N.PLAYER.H / 2 - bit.y) / t
            self.balls[#self.balls + 1] = { x = bit.x, y = bit.y, z = bit.z, vx = vx, vy = vy, vz = -speed,
              r = G.BIT_R * G.SIZE_UNIT, kind = "bit", damage = bit.damage }
          else
            bit.fireT = A.fire_every
            local vx, vy = towardPlayer(self, bit.x, bit.y, N.ATTACK.small.speed)
            self.balls[#self.balls + 1] = { x = bit.x, y = bit.y, z = bit.z, vx = vx, vy = vy, vz = -N.ATTACK.small.speed,
              r = N.ATTACK.small.r, kind = "bit" }
          end
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
    if (p.lock or 0) > 0 then p.lock = math.max(0, p.lock - step) end
    if (p.refire or 0) > 0 then p.refire = math.max(0, p.refire - step) end
    if (p.smoke or 0) > 0 then p.smoke = math.max(0, p.smoke - step) end
    if (p.shatter or 0) > 0 then p.shatter = math.max(0, p.shatter - step) end
    if p.shield > 0 then
      p.shield = math.max(0, p.shield - step)
      -- a ball it stopped breaks it a moment later
      if p.breakT then
        p.breakT = p.breakT - step
        if p.breakT <= 0 or p.shield <= 0 then shieldDown(self, "blocked") end
      elseif p.shield <= 0 then
        shieldDown(self, "held")
      end
    end
    if (p.safe or 0) > 0 then p.safe = math.max(0, p.safe - step) end
    if p.shieldCd > 0 then p.shieldCd = math.max(0, p.shieldCd - step) end
    local canMove = p.stun <= 0 and p.burst <= 0
    if canMove then
      local v = N.PLAYER.SPEED * (self.mods.moveMult or 1) * (p.shield > 0 and N.BLOCK.MOVE_MULT or 1)
      -- "Those Long Shots Are No Long Shot!": the player is kept at the far end of the box
      -- across and up / down on the stand's plane; "Those Long Shots Are No Long Shot!" keeps
      -- the stand at the far end
      p.z = self.course.farPlayer and 0.04 or (N.PLAYER.Z or 0.1)
      p.x = math.max(-N.PLAYER.X_MAX, math.min(N.PLAYER.X_MAX, p.x + p.mx * v * step))
      -- (up and down as fast on the screen as across: a world unit up is fewer screen units
      -- than one across at the trainee's depth, NEAR hw / hu)
      p.y = math.max(0, math.min(N.PLAYER.Y_MAX or 0.7, (p.y or 0) + p.mz * v * (V.NEAR.hw / V.NEAR.hu) * step))
    end
    if p.charging and p.stun <= 0 then
      p.chargeT = p.chargeT + step
      if p.chargeT * CF >= N.CHARGE.FIZZLE_F then
        -- held too long: the charge fizzles into smoke and the Pokemon stops
        p.charging = false
        p.stun = N.CHARGE.STUN_F / CF
        p.smoke = p.stun
        emit(self, "overcharge")
      end
      -- (holding only charges, for every colour: a shot leaves on release, as in the game)
    end
    if p.burst > 0 then
      p.firing = p.firing - step
      if p.firing <= 0 then
        p.firing = N.SHOT.yellow.rapid
        p.burst = p.burst - 1
        self:fire(2, (self.rng() - 0.5) * 0.2, 1)
      end
    end
    -- the meter refills every frame (the game's per-frame amount from Def / Sp. Def, the EVs);
    -- a yellow shot's held touch stops it (it streams)
    if not (p.charging and self.shotType == N.SHOT.RAPID) then
      local rate = self.mods.gutsPerS or (N.GUTS.RATE * (self.mods.gutsRate or 1))
      self.guts = math.min(1, self.guts + rate * step)
    end
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
    if self.phase == "between" then
      -- the changeover between two balloons (N.BETWEEN; the clock stands still): the beaten one
      -- deflates onto the grass, the screen fades through black, the next lies there and
      -- inflates where it lies, 30 s go onto the clock, its name, then play
      local B, bt = N.BETWEEN, self.between
      bt.t = bt.t + step
      if not bt.swapped and bt.t >= B.SWAP_S then
        bt.swapped = true
        self:nextBot()
        emit(self, "next_bot", { index = self.botIndex })
      end
      if not bt.bonus and bt.t >= B.BONUS_S then
        bt.bonus = true
        local secs = self.course.extraBotSecs or N.CLOCK.EXTRA_BOT_S
        self.remaining = self.remaining + secs
        emit(self, "time_bonus", { secs = secs })
      end
      if bt.t >= B.PLAY_S then
        self.between = nil
        self.phase = "play"
        self:spawnGroup()
        emit(self, "play", { stage = self.botIndex })
      end
      return
    end
    if self.phase ~= "play" then return end
    -- the sway's clock: held while the balloon stands frozen for its red goal
    local frozen = self.chancePending or self:chanceUp()
    if not frozen then self.swayT = (self.swayT or 0) + step end
    if self.chancePending then
      self.chancePending = self.chancePending - step
      if self.chancePending <= 0 then self.chancePending = nil; self:spawnChance() end
    end
    self.remaining = self.remaining - step
    self:updatePlayer(step)
    self:updateAttacks(step)
    self:updateShots(step)
    self:updateBalls(step)
    self:updateGoals(step)
    local bot = self.bot
    -- it inflates with the score, its feet on the ground (Wooble's Graveler capture: about
    -- 1.56x its height at the target), easing to each new size
    local want = 1 + N.BOT.GROW_K * math.min(1, self.score / math.max(1, bot.target or 1))
    want = math.min(want, self:growMax())
    bot.scale = bot.scale + (want - bot.scale) * math.min(1, step * N.BOT.GROW_EASE)
    if bot.flinch > 0 then bot.flinch = math.max(0, bot.flinch - step) end
    if (bot.shake or 0) > 0 then bot.shake = math.max(0, bot.shake - step) end
    if bot.aura > 0 then bot.aura = math.max(0, bot.aura - step) end
    if bot.windup then bot.windup.t = bot.windup.t + step end
    if (bot.thrown or 0) > 0 then bot.thrown = math.max(0, bot.thrown - step) end
    -- (the game's script sets the mood from its second form; this only without it)
    if not self.script then
      if self.course.rageAt and self.score >= self.course.rageAt then bot.mood = "rage" end
      if self.course.calmAt and self.score >= self.course.calmAt then bot.mood = "calm" end
    end
    if self.score >= bot.target then
      emit(self, "bot_pop", { index = self.botIndex, remaining = self.remaining })
      if self.course.bots[self.botIndex + 1] then
        -- another balloon to come: the changeover (its attacks, balls and goals gone)
        self.phase = "between"
        self.between = { t = 0, scale = bot.scale }
        self.goals, self.balls, self.bits, self.spawnQueue, self.shots = {}, {}, {}, {}, {}
        self.barrier, self.chancePending = nil, nil
        bot.aura, bot.windup, bot.thrown, bot.shake = 0, nil, 0, 0
      else
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
    if self.phase ~= "play" and self.phase ~= "countdown" and self.phase ~= "between" then return false end
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
      ready = self:shotReady(),
      botScale = self.bot and self.bot.scale, aura = self.bot and self.bot.aura, mood = self.bot and self.bot.mood,
      stats = self.stats, countdown = self.countdown,
    }
  end

  return Sim
end
