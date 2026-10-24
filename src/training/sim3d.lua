-- 3D SUPER TRAINING's play in the game's own space (N.GAME3D, from DllSparring.cro), 1:1: on with
-- the option (Sim:setGame3d), the 2D view's flat world and tuning untouched otherwise. Units the
-- game's: the balloon at the origin, y up, 30 frames a second.
--
--   * the trainee: elevation / azimuth / distance on the game's sphere, moving the game's units of
--     arc a frame; its body (p.x, p.y, p.z, a point of the game's space) ACTOR_IN inside that
--     point, ACTOR_SIDE to its side, ACTOR_UP above; its hit shape a sphere of HIT_R; the camera's
--     eye (p.ex, p.ey, p.ez) on the sphere point
--   * an enemy ball: from the balloon (its middle and the volley's offset) toward the trainee's
--     body (the aim flags, the volley's yaw / pitch turning that about the origin), its record's
--     speed a frame, the game's wave and homing (trainee - ball) x t / (t + k), a hit when the
--     trainee's sphere touches its ellipsoid (the record's semi-axes), gone 300 from its start
--   * the balloon (its sprite standing in for its model): its phase's scale, growing to GROW x,
--     the game's sway; the balloon's side of the flat world (its goals, bitbots, the aim) laid on
--     the game's plane z 0 through it (Sim:toGame / fromGame), so goals keep the scripts' places
--     and the game's box sizes
--   * a shot: the game's table (speed a frame, size) x Speed / HP, flying as a lob from the
--     trainee's body to the aim on that plane, swept against the goals' boxes and the bitbots
--
-- Sim3d(Sim, N, I) with I = Sim._in (emit, GA, FPS) - adds Sim:setGame3d, Sim:toGame, ...

return function(Sim, N, I)
  local G3 = N.GAME3D
  local emit, GA, FPS = I.emit, I.GA, I.FPS
  local rad, sin, cos, sqrt, abs, max, min = math.rad, math.sin, math.cos, math.sqrt, math.abs, math.max, math.min

  local function sphere(el, az, r)
    local ce = cos(rad(el))
    return r * ce * cos(rad(az)), r * sin(rad(el)), r * ce * sin(rad(az))
  end
  Sim.sphere3 = sphere

  -- ------- on / off

  function Sim:setGame3d(on)
    local p = self.player
    if on and not self.gameAttacks then on = false end
    if on then
      if self.game3d then return true end
      self.game3d = true
      p.el, p.az = G3.EL[1], 90
      -- the distance steps (a far-player course keeps the far one)
      if self.course.farPlayer then
        p.distStep = #N.PLAYER.DIST
      else
        p.distStep = p.distStep or N.PLAYER.DIST_STEP0
      end
      p.dist = N.PLAYER.DIST[p.distStep]
      self.depthSteps = not self.course.farPlayer or nil
      -- (the flat world's balls and shots do not carry over)
      self.balls, self.shots, self.spawnQueue = {}, {}, {}
      self:place3()
      return true
    elseif self.game3d then
      self.game3d = nil
      self.balls, self.shots, self.spawnQueue = {}, {}, {}
      p.x, p.y, p.z, p.el, p.az = 0, 0, N.PLAYER.Z or 0.1, nil, nil
      self.depthSteps, p.dist, p.distStep = nil, nil, nil
    end
    return false
  end

  -- the trainee's body and the camera's eye from its elevation / azimuth / distance
  function Sim:place3()
    local p = self.player
    local r = p.dist or 240
    local k = 360 / (2 * math.pi * r)
    local x, y, z = sphere(p.el, p.az + G3.ACTOR_SIDE * k, r - G3.ACTOR_IN)
    p.x, p.y, p.z = x, y + G3.ACTOR_UP, z
    local ex, ey, ez = sphere(p.el, p.az, r)
    p.ex, p.ey, p.ez = ex, ey + G3.EYE_UP, ez
  end

  -- moving on the sphere (the game's 0x1ff8-0x2098): its units of arc a frame, the limits, the
  -- edge flags (1 the top, 2 the right, 4 the left; the bottom only stops), the distance closing
  function Sim:move3(step, canMove)
    local p = self.player
    local wantEl, wantAz = p.el, p.az
    if canMove then
      local v = G3.SPEED * (1 + 100 * G3.SPE_K) * (self.mods.moveMult or 1) * (p.shield > 0 and N.BLOCK.MOVE_MULT or 1)
      local k = 360 / (2 * math.pi * (p.dist or 240))
      wantEl = p.el + p.mz * v * k * FPS * step
      wantAz = p.az - p.mx * v * k * FPS * step
    end
    p.el = max(G3.EL[1], min(G3.EL[2], wantEl))
    p.az = max(G3.AZ[1], min(G3.AZ[2], wantAz))
    p.edge = 0
    if canMove then
      p.edge = ((wantEl > G3.EL[2] and p.mz > 0) and 1 or 0) + ((wantAz < G3.AZ[1] and p.mx > 0) and 2 or 0)
        + ((wantAz > G3.AZ[2] and p.mx < 0) and 4 or 0)
    end
    if p.dist and p.distStep then
      local want = N.PLAYER.DIST[p.distStep] or p.dist
      local rate = N.PLAYER.DIST_SPEED * FPS * (p.shield > 0 and 0.5 or 1) * step
      if p.dist < want then p.dist = min(want, p.dist + rate) elseif p.dist > want then p.dist = max(want, p.dist - rate) end
    end
    self:place3()
  end

  -- the edge's ripple (the game's effect #3, DllSparring.cro 0x1450c: spawned beside the trainee
  -- toward the edge pushed): its middle, EDGE_OFF from the trainee's body toward that side - up
  -- for the top (1), the trainee's right / left along the orbit for 2 / 4 - and two axes of its
  -- plane. Its facing is fitted to the captures: a side disc stands across the line of sight,
  -- turned EDGE_TURN degrees off it (the left one a thin slanted streak, the right a crescent); the
  -- top one lies level, tilted EDGE_TILT degrees toward the camera (a ~0.8 ellipse from the top).
  -- -> cx, cy, cz, ux, uy, uz, vx, vy, vz
  function Sim:edgeDisc3(edge)
    local p = self.player
    local a = rad(p.az or 90)
    -- (the trainee's right: lower azimuth; the horizontal way to the balloon)
    local rx, rz = sin(a), -cos(a)
    local ix, iz = -cos(a), -sin(a)
    local o = G3.EDGE_OFF
    if edge == 1 then
      local t = rad(G3.EDGE_TILT)
      return p.x, p.y + o, p.z, rx, 0, rz, ix * cos(t), sin(t), iz * cos(t)
    end
    local s = edge == 2 and 1 or -1
    local cx, cy, cz = p.x + rx * o * s, p.y, p.z + rz * o * s
    -- the horizontal way from it to the eye, turned
    local dx, dz = (p.ex or cx) - cx, (p.ez or cz) - cz
    local l = sqrt(dx * dx + dz * dz)
    if l < 1e-6 then dx, dz, l = -ix, -iz, 1 end
    dx, dz = dx / l, dz / l
    local tt = rad(G3.EDGE_TURN) * s
    dx, dz = dx * cos(tt) - dz * sin(tt), dx * sin(tt) + dz * cos(tt)
    return cx, cy, cz, 0, 1, 0, dx, 0, dz
  end

  -- ------- the balloon in the game's space (its sprite for its model)

  -- its phase's scale and sway (the attack data), its fill's growth
  local function phase(self) return self.script and self.script.phase or {} end
  -- a balloon measured in the captures (N.GAME3D.SIZE_PX by species, 400x240 px at the middle
  -- distance): its mean side sqrt(w x h) and its middle's height in game units, through the play
  -- camera (the eye 240 out at EYE_UP, looking at LOOK_Y, PLAY_FOVY)
  local sizeCache = {}
  local function measured(self)
    local sp = phase(self).species or (self.bot and self.bot.national)
    local m = sp and G3.SIZE_PX and G3.SIZE_PX[sp]
    if not m then return nil end
    local c = sizeCache[sp]
    if not c then
      local F = 80 / math.tan(rad(G3.PLAY_FOVY) / 2)
      local unit = (160 / 240) * 240 / F
      local pitch = math.atan((G3.LOOK_Y - G3.EYE_UP) / 240)
      -- (a screen y in 400x240 px -> the game's height on the balloon's plane)
      local function height(py) return G3.EYE_UP + 240 * math.tan(math.atan((80 - py * 160 / 240) / F) + pitch) end
      c = { size = sqrt(m[1] * m[2]) * unit, tall = m[2] * unit, cy = height(m[3]), stands = m[4] or nil }
      sizeCache[sp] = c
    end
    return c
  end
  Sim.measured3 = measured
  -- game units a bot radius, x its growth: a measured standing balloon as tall as the game's; a
  -- measured floating one its sprite's mean side, sqrt(w x h), the game's (a front sprite's
  -- proportions are not the model's); else BAL_SIZE x its phase's scale
  function Sim:botR3()
    local sh = self.shape
    local side = sh and sqrt((sh.halfW or 1) * (sh.halfH or 1)) or 1
    local grow = 1 + (G3.GROW - 1) * min(1, self.score / max(1, self.bot and self.bot.target or 1))
    self.bot.grow3 = (self.bot.grow3 or grow) + (grow - (self.bot.grow3 or grow)) * 0.2
    local m = measured(self)
    if m and m.stands then
      -- standing: as tall as the game's, its feet on the grass (its width the sprite's own shape)
      return m.tall * self.bot.grow3 / 2 / (sh and sh.halfH or 1)
    end
    local size = m and m.size or G3.BAL_SIZE * (phase(self).scale or 0.7)
    return size * self.bot.grow3 / 2 / side
  end
  -- the balloon's middle in the game's space: a measured one where the captures have it, a
  -- floating one (its phase's midY) its middle midY x scale above the grass, else its feet on the
  -- grass; the game's sway (x 12 sin 2t,
  -- y 6 sin t, degrees a frame) when its phase sways, our throw's dip and hit wobble over it
  function Sim:botCentre3()
    local R3 = self:botR3()
    local sh = self.shape
    local halfH = sh and sh.halfH or 1
    local ph = phase(self)
    local x, y = 0, G3.GROUND + halfH * R3
    local m = measured(self)
    if m and m.stands then
      -- standing: its feet on the grass (placed by its middle a sprite shaped unlike the model
      -- would float or sink), growing up from them
      y = G3.GROUND + halfH * R3
    elseif m then
      -- floating: its measured middle, rising with its growth from the grass
      y = G3.GROUND + (m.cy - G3.GROUND) * (self.bot.grow3 or 1)
    elseif (ph.midY or 0) > 0 then
      y = G3.GROUND + ph.midY * (ph.scale or 0.7) * (self.bot.grow3 or 1)
    end
    if phase(self).sway == 1 then
      local f = (self.swayT or 0) * FPS
      x = x + G3.SWAY[1] * sin(rad(G3.SWAY[2] * f))
      y = y + G3.SWAY[3] * sin(rad(G3.SWAY[4] * f))
    end
    local ox, oy = self:botOffset()
    local s3 = R3 / (N.BOT.R * (self.bot and self.bot.scale or 1))
    return x + ox * s3, y + oy / Sim.ASPECT * s3, 0, s3
  end
  -- a point of the balloon's side of the flat world (z 1: its goals, the aim) on the game's plane
  -- z 0, and back
  function Sim:toGame(x, y)
    local cx, cy, _, s3 = self:botCentre3()
    local bx, by = self:botOffset()
    local fx, fy = bx, self:botCY() + by
    return cx + (x - fx) * s3, cy + (y - fy) / Sim.ASPECT * s3, 0
  end
  function Sim:fromGame(X, Y)
    local cx, cy, _, s3 = self:botCentre3()
    local bx, by = self:botOffset()
    local fx, fy = bx, self:botCY() + by
    return fx + (X - cx) / s3, fy + (Y - cy) * Sim.ASPECT / s3
  end
  -- a goal's box: its middle and half size
  function Sim:goalBox3(g)
    local gx, gy = self:goalPos(g)
    local X, Y, Z = self:toGame(gx, gy)
    local half = (g.kind == "chance") and G3.GOAL_HALF_BIG or (g.kind == "marker" and 6 or G3.GOAL_HALF)
    return X, Y, Z, half
  end
  -- a bitbot: on its loop about its spot (BIT_SPOTS: the middle one nearer the camera)
  function Sim:bitPos3(bit)
    -- (its spot by its place in the row: 1 left, 2 middle, 3 right; its loop's angle the flat
    -- world's, clockwise on the screen)
    local S = G3.BIT_SPOTS[bit.id] or G3.BIT_SPOTS[2]
    local a = bit.loopA or 0
    return S[1] + cos(a) * G3.BIT_LOOP_R, S[2] + sin(a) * G3.BIT_LOOP_R, S[3]
  end

  -- ------- the enemy balls

  -- a volley's shot as the game builds it (0xf234 / 0x1634c)
  function Sim:gameBall3(shot)
    local P = self.gameAttacks.projectiles[shot.p]
    if not P then return nil end
    local p = self.player
    local cx, cy = self:botCentre3()
    local sx, sy, sz = cx + (shot.dx or 0), cy + (shot.dy or 0), 0
    local tx = shot.aimX == 1 and p.x or sx
    local ty = shot.aimY == 1 and p.y or sy
    local tz = p.z
    -- turned about the origin by its yaw (about y) and pitch (about x), degrees
    local yw, pt = rad(shot.yaw or 0), rad(shot.pitch or 0)
    tx, tz = tx * cos(yw) + tz * sin(yw), -tx * sin(yw) + tz * cos(yw)
    ty, tz = ty * cos(pt) - tz * sin(pt), ty * sin(pt) + tz * cos(pt)
    local dx, dy, dz = tx - sx, ty - sy, tz - sz
    local l = sqrt(dx * dx + dy * dy + dz * dz)
    if l < 1e-6 then return nil end
    local v = P.speed * (self.mods.botSpeedMult or 1)
    local hw, hh = P.sx, P.sy
    return { g3 = true, game = P, x = sx, y = sy, z = sz, sx0 = sx, sy0 = sy, sz0 = sz,
      vx = dx / l * v, vy = dy / l * v, vz = dz / l * v, t0 = self.t,
      ex = P.sx, ey = P.sy, ez = P.sz, r = max(hw, hh), w = hw * 2, h = hh * 2, gsx = P.sx, gsy = P.sy,
      kind = Sim.homes(P) and "homing" or (max(hw, hh) > 8 and "big" or "small") }
  end

  -- where a ball is n frames after it left (the game's 0x155ec): its line, its wave, its homing
  local function ballAt(self, b, n)
    local P, p = b.game, self.player
    local bx, by, bz = b.sx0 + b.vx * n, b.sy0 + b.vy * n, b.sz0 + b.vz * n
    local ox, oy = 0, 0
    if P then
      ox = P.ampX * cos(P.phase + n * P.freqX) * (1 + n * P.growX)
      oy = P.ampY * sin(P.phase + n * P.freqY) * (1 + n * P.growY)
      if (P.homeX or 0) > 0 then ox = ox + (p.x - bx) * n / (n + P.homeX) end
      if (P.homeY or 0) > 0 then oy = oy + (p.y - by) * n / (n + P.homeY) end
    end
    return bx + ox, by + oy, bz
  end
  -- the trainee's sphere against a ball's ellipsoid (0x15a38-0x15ac0); a bitbot's shot a sphere
  local function touches(self, b, x, y, z)
    local p = self.player
    local dx, dy, dz = x - p.x, y - p.y, z - p.z
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    if b.kind == "bit" then return d < G3.HIT_R + (b.r or 0) end
    if d < 1e-6 then return true end
    local R = G3.HIT_R
    local qx, qy, qz = p.x + dx / d * R - x, p.y + dy / d * R - y, p.z + dz / d * R - z
    return (qx / b.ex) ^ 2 + (qy / b.ey) ^ 2 + (qz / b.ez) ^ 2 <= 1
  end

  -- seconds until a ball passes nearest the trainee, whether it would hit it standing still, and
  -- where (x, y, z)
  function Sim:ballEta3(b)
    if not b.g3 or b.bounced or b.past then return nil end
    local p = self.player
    local n0 = (self.t - b.t0) * FPS
    local x, y, z = ballAt(self, b, n0)
    local rx, ry, rz = p.x - x, p.y - y, p.z - z
    local vv = b.vx * b.vx + b.vy * b.vy + b.vz * b.vz
    if vv < 1e-9 then return nil end
    local tc = (rx * b.vx + ry * b.vy + rz * b.vz) / vv
    if tc < 0 then return nil end
    local cx, cy, cz = ballAt(self, b, n0 + tc)
    return tc / FPS, touches(self, b, cx, cy, cz), cx, cy, cz
  end

  function Sim:updateBalls3(step)
    local p = self.player
    local keep = {}
    for _, b in ipairs(self.balls) do
      -- (only balls built in the game's space)
      local alive = b.g3 == true
      if not alive then
      elseif b.bounced then
        b.x, b.y, b.z = b.x + b.vx * FPS * step, b.y + b.vy * FPS * step, b.z + b.vz * FPS * step
        b.bt = (b.bt or 0) + step
        if b.bt > 1.5 then alive = false end
      else
        local n = (self.t - b.t0) * FPS
        if b.kind == "bit" then
          b.x, b.y, b.z = b.sx0 + b.vx * n, b.sy0 + b.vy * n, b.sz0 + b.vz * n
        else
          b.x, b.y, b.z = ballAt(self, b, n)
        end
        -- past the trainee once moving away from it
        local rx, ry, rz = b.x - p.x, b.y - p.y, b.z - p.z
        if not b.past and rx * b.vx + ry * b.vy + rz * b.vz > 0 then b.past, b.pastT = true, self.t end
        if touches(self, b, b.x, b.y, b.z) then
          if (p.safe or 0) > 0 then
            alive = false
            emit(self, "ball_absorbed", { ball = b.kind })
          elseif p.shield > 0 then
            self.stats.blocked = self.stats.blocked + 1
            p.safe = N.BLOCK.SAFE_F / N.CHARGE.FPS
            p.breakT = p.breakT or N.BLOCK.BREAK_F / N.CHARGE.FPS
            b.bounced, b.game = true, nil
            b.vx, b.vy, b.vz = -b.vx * 0.6 + (self.rng() - 0.5), abs(b.vy) + 1.2, -b.vz * 0.6
            emit(self, "blocked", { ball = b.kind })
          else
            alive = false
            self:playerHit(b)
          end
        end
        -- gone 300 from where it left (0x15ad4)
        local tx, ty, tz = b.vx * n, b.vy * n, b.vz * n
        if tx * tx + ty * ty + tz * tz >= G3.DESPAWN * G3.DESPAWN then alive = false end
      end
      if alive then keep[#keep + 1] = b end
    end
    self.balls = keep
    -- bitbots: on their loops, firing at the trainee now and then
    local A = N.ATTACK.bit
    local keptBits = {}
    for _, bit in ipairs(self.bits) do
      if bit.dead then
        bit.regenT = bit.regenT - step
        if bit.regenT <= 0 then
          bit.dead, bit.hp, bit.fireT, bit.poppedAt = false, A.hp, A.fire_every, nil
          emit(self, "bit_regen", { id = bit.id })
        end
        keptBits[#keptBits + 1] = bit
      elseif bit.hp > 0 then
        if bit.cx then
          bit.loopA = bit.loopA - 2 * math.pi / GA.BIT_LOOP_S * step
          bit.x = bit.cx + cos(bit.loopA) * GA.BIT_LOOP_R
          bit.y = bit.cy + sin(bit.loopA) * GA.BIT_LOOP_R
        end
        bit.fireT = bit.fireT - step
        if bit.fireT <= 0 then
          bit.fireT = (bit.every or GA.BIT_EVERY_F) / FPS
          local x, y, z = self:bitPos3(bit)
          local dx, dy, dz = p.x - x, p.y - y, p.z - z
          local l = max(1e-6, sqrt(dx * dx + dy * dy + dz * dz))
          local v = G3.BIT_SPEED
          self.balls[#self.balls + 1] = { g3 = true, x = x, y = y, z = z, sx0 = x, sy0 = y, sz0 = z,
            vx = dx / l * v, vy = dy / l * v, vz = dz / l * v, t0 = self.t, r = G3.BIT_SHOT_R,
            ex = G3.BIT_SHOT_R, ey = G3.BIT_SHOT_R, ez = G3.BIT_SHOT_R, kind = "bit", damage = bit.damage }
          emit(self, "bit_fire", { id = bit.id })
        end
        keptBits[#keptBits + 1] = bit
      end
    end
    self.bits = keptBits
  end

  -- ------- the trainee's shots

  -- a flat shot (its points and kind already the sim's) made the game's: from the trainee's body
  -- to the aim on the balloon's plane, the table's speed and size, a lob over its line
  function Sim:shot3(shot)
    local p = self.player
    local T = (shot.stage or 0) >= 1 and G3.SHOT_CHARGED or G3.SHOT
    local rec = T[shot.type] or T.black
    local ax, ay, az = self:toGame(p.aim.x, p.aim.y)
    local x0, y0, z0 = p.x, p.y + 1, p.z
    local dx, dy, dz = ax - x0, ay - y0, az - z0
    local L = max(1, sqrt(dx * dx + dy * dy + dz * dz))
    shot.g3 = true
    shot.x, shot.y, shot.z = x0, y0, z0
    shot.ox, shot.oy, shot.oz, shot.dx, shot.dy, shot.dz, shot.L = x0, y0, z0, dx, dy, dz, L
    shot.s = 0
    shot.speed = rec[1] * (1 + 100 * G3.SHOT_SPE_K) * (self.mods.ballSpeedMult or 1)
    shot.r = rec[2] * (1 + 100 * G3.SHOT_HP_K) * (self.mods.shotSize or 1)
    return shot
  end

  -- a segment from (x0..) to (x1..) against a box (middle c, half h, grown by r): where along it
  -- (0..1) it first enters, or nil
  local function segBox(x0, y0, z0, x1, y1, z1, cx, cy, cz, h)
    local tmin, tmax = 0, 1
    local o = { x0 - cx, y0 - cy, z0 - cz }
    local d = { x1 - x0, y1 - y0, z1 - z0 }
    for i = 1, 3 do
      if abs(d[i]) < 1e-9 then
        if abs(o[i]) > h then return nil end
      else
        local t1, t2 = (-h - o[i]) / d[i], (h - o[i]) / d[i]
        if t1 > t2 then t1, t2 = t2, t1 end
        tmin, tmax = max(tmin, t1), min(tmax, t2)
        if tmin > tmax then return nil end
      end
    end
    return tmin
  end

  function Sim:updateShots3(step)
    local keep = {}
    for _, sh in ipairs(self.shots) do
      local px, py, pz = sh.x, sh.y, sh.z
      sh.s = sh.s + sh.speed * FPS * step
      local u = sh.s / sh.L
      local lob = u < 1 and G3.LOB * 4 * u * (1 - u) or 0
      sh.x, sh.y, sh.z = sh.ox + sh.dx * u, sh.oy + sh.dy * u + lob, sh.oz + sh.dz * u
      local alive = true
      -- bitbots first (spheres)
      for _, bit in ipairs(self.bits) do
        if alive and bit.hp > 0 and not bit.dead then
          local bx, by, bz = self:bitPos3(bit)
          local t = segBox(px, py, pz, sh.x, sh.y, sh.z, bx, by, bz, G3.BIT_R + sh.r)
          if t then
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
      if alive then
        -- the goals' boxes, swept (0xa1e0); while the barrier stands its marker first
        local order = self.goals
        if self.barrier then
          order = {}
          for _, g in ipairs(self.goals) do if g.kind == "marker" then order[#order + 1] = g end end
          for _, g in ipairs(self.goals) do if g.kind ~= "marker" then order[#order + 1] = g end end
        end
        local hit, best = nil, nil
        for _, g in ipairs(order) do
          local shown = not g.hidden and not (g.kind == "marker" and g.orbit and g.age < N.ATTACK.SHIELD.FADE_IN_S)
          if not g.dead and shown then
            local gx, gy, gz, half = self:goalBox3(g)
            local t = segBox(px, py, pz, sh.x, sh.y, sh.z, gx, gy, gz, half + sh.r)
            if t and (not best or t < best) then best, hit = t, g end
          end
        end
        if hit then
          alive = false
          if self.barrier and hit.kind ~= "marker" then
            emit(self, "shot_absorbed")
            self.stats.misses = self.stats.misses + 1
          else
            self:hitGoal(hit, sh)
          end
        elseif u >= 1.3 then
          alive = false
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

  return Sim
end
