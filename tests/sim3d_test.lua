-- 3D SUPER TRAINING's play in the game's own space (src/training/sim3d.lua, N.GAME3D), headless:
-- the trainee on the game's sphere moving the game's units of arc a frame, its limits and edges,
-- the distance steps, a ball of the game's size and speed hitting a trainee standing still and
-- missing one that moves off, gone 300 from its start, a shot reaching a goal's box, and the 2D
-- world untouched once off.
-- Run from the engine root: luajit mods/play_nav/tests/sim3d_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/training_rules.lua")
local C = loadFile("mods/play_nav/data/training_courses.lua")
local GA = loadFile("mods/play_nav/data/training_attacks.lua")
local Sim = loadFile("mods/play_nav/src/training/sim.lua")(N)
loadFile("mods/play_nav/src/training/sim3d.lua")(Sim, N, Sim._in)
local G3 = N.GAME3D

local function lcg(seed)
  local s = seed or 1
  return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end
local function make(id)
  local course = C.byId[id]
  local sim = Sim.new(course, { anchors = C.anchors[course.goals.anchors], library = C.attacks,
    shotType = "black", level = course.level, still = true, gameAttacks = GA }, lcg(5))
  for _ = 1, 3.2 * 60 do sim:update(1 / 60) end
  sim.script, sim.balls, sim.spawnQueue = nil, {}, {}
  return sim
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- on: the trainee where the game starts it
local s = make("lv1_hp")
T.check(s:setGame3d(true), "3D play turns on (the game's attack data present)")
local p = s.player
T.check(near(p.el, 0) and near(p.az, 90) and near(p.dist, 240), "the trainee starts at elevation 0, azimuth 90, 240 out")
local k = 360 / (2 * math.pi * 240)
local ax, ay, az = Sim.sphere3(0, 90 + G3.ACTOR_SIDE * k, 240 - G3.ACTOR_IN)
T.check(near(p.x, ax, 1e-9) and near(p.y, ay + G3.ACTOR_UP, 1e-9) and near(p.z, az, 1e-9),
  ("its body 11.5 in, 2.5 aside, 3.5 up (%.2f, %.2f, %.2f)"):format(p.x, p.y, p.z))
T.check(near(p.ex, 0, 1e-9) and near(p.ey, G3.EYE_UP) and near(p.ez, 240, 1e-9), "the camera's eye on the sphere point, 4.5 up")

-- moving: the game's 2 x (1 + Speed x 0.001) units of arc a frame
s.mods.moveMult = 1
s:setMove(1, 0)
for _ = 1, 30 do s:update(1 / 30) end
local want = 90 - 2.2 * 30 * k
T.check(near(p.az, want, 0.05), ("a second to the right: azimuth %.2f (the game's %.2f)"):format(p.az, want))
for _ = 1, 30 * 4 do s:update(1 / 30) end
T.check(near(p.az, G3.AZ[1]) and p.edge == 2, ("held: stopped at azimuth 60, the right edge (%s)"):format(tostring(p.edge)))
s:setMove(0, 1)
for _ = 1, 30 * 5 do s:update(1 / 30) end
T.check(near(p.el, G3.EL[2]) and p.edge == 1, "up to elevation 45, the top edge")
s:setMove(0, -1)
for _ = 1, 30 * 5 do s:update(1 / 30) end
T.check(near(p.el, 0) and p.edge == 0, "down to the grass: the bottom only stops")
s:setMove(0, 0)

-- the distance steps
T.check(s:stepDistance(-1), "a step nearer")
for _ = 1, 40 do s:update(1 / 30) end
T.check(near(p.dist, 180), ("...the trainee 180 out (%.1f)"):format(p.dist))

-- a round ball (projectile 57) thrown at a trainee standing still hits; one that moves off is missed
local function throw(pid, move)
  local g = make("lv1_hp")
  g:setGame3d(true)
  g.player.safe = 0
  local b = g:gameBall3({ p = pid, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
  g.balls[1] = b
  local hit, frames = false, 0
  g:setMove(move or 0, 0)
  for i = 1, 30 * 6 do
    for _, e in ipairs(g:update(1 / 30)) do if e.kind == "player_hit" then hit = true end end
    if #g.balls == 0 then frames = i; break end
  end
  return hit, b, frames, g
end
local hit, b = throw(57)
local P = GA.projectiles[57]
T.check(hit, "a round ball meets a trainee standing still")
T.check(b.ex == P.sx and b.ey == P.sy and b.ez == P.sz, ("...its hitbox the game's semi-axes (%.1f, %.1f, %.1f)"):format(P.sx, P.sy, P.sz))
local v = math.sqrt(b.vx ^ 2 + b.vy ^ 2 + b.vz ^ 2)
T.check(near(v, P.speed, 1e-6), ("...its speed the game's %.2f a frame"):format(P.speed))
hit = throw(57, 1)
T.check(not hit, "...a trainee running off sideways from the throw is missed")
-- a ball that misses is gone 300 from where it left
local g = make("lv1_hp")
g:setGame3d(true)
local far = g:gameBall3({ p = 57, next = 0, dx = 0, dy = 0, yaw = 30, pitch = 0, aimX = 1, aimY = 1 })
g.balls[1] = far
local n = 0
while #g.balls > 0 and n < 400 do g:update(1 / 30); n = n + 1 end
T.check(near(n * GA.projectiles[57].speed, G3.DESPAWN, GA.projectiles[57].speed * 2),
  ("a ball turned wide is gone 300 from its start (%d frames)"):format(n))

-- a shot aimed at a goal reaches its box and scores
do
  local sh = make("lv1_hp")
  sh:setGame3d(true)
  sh:spawnGroup()
  local goal = sh.goals[1]
  T.check(goal ~= nil, "a goal to shoot at")
  if goal then
    local gx, gy = sh:goalPos(goal)
    sh.guts = 500
    sh:aim(gx, gy)
    sh.player.refire = 0
    sh:pressFire(); sh:update(1 / 30); sh:releaseFire()
    local s3 = sh.shots[1]
    T.check(s3 and s3.g3, "the shot flies in the game's space")
    T.check(s3 and near(s3.speed, G3.SHOT.black[1] * (1 + 100 * G3.SHOT_SPE_K) * (sh.mods.ballSpeedMult or 1), 1e-9),
      "...at the game's black shot speed")
    local scored = false
    for _ = 1, 30 * 3 do
      for _, e in ipairs(sh:update(1 / 30)) do if e.kind == "goal_hit" then scored = true end end
    end
    T.check(scored, "...and hits the goal's box")
    local X, Y, Z, half = sh:goalBox3(goal)
    T.check(half == G3.GOAL_HALF and near(Z, 0), ("the goal a box of half %d on the balloon's plane"):format(half))
  end
end

-- the balloon: its size and middle as the captures show it (SIZE_PX); unmeasured ones by their
-- phase's scale, floating at midY x scale or standing on the grass
do
  local F = 80 / math.tan(math.rad(G3.PLAY_FOVY) / 2)
  local unit = (160 / 240) * 240 / F
  local bl = make("lv2_spa")
  bl:setGame3d(true)
  bl:startScript()
  local m = G3.SIZE_PX[82]
  local _, cy = bl:botCentre3()
  T.check(near(bl:botR3() * 2, math.sqrt(m[1] * m[2]) * unit, 1e-6),
    ("Magneton: its mean side the capture's sqrt(%d x %d) px in game units"):format(m[1], m[2]))
  -- (its middle at screen y 90.5 of 240 through the play camera: ~56 game units up)
  T.check(cy > 50 and cy < 60, ("...its middle where the capture has it (y %.1f)"):format(cy))
  -- standing balloons are placed by their feet, on the grass
  local ax = make("lv1_atk")
  ax:setGame3d(true)
  ax:startScript()
  local _, acy = ax:botCentre3()
  local feet = acy - (ax.shape and ax.shape.halfH or 1) * ax:botR3()
  T.check(Sim.measured3(ax).stands and near(feet, G3.GROUND, 1e-6), ("Axew stands with its feet on the grass (%.1f)"):format(feet))
  local tall = 2 * (ax.shape and ax.shape.halfH or 1) * ax:botR3()
  T.check(near(tall, G3.SIZE_PX[610][2] * unit, 1e-6), ("...as tall as the game's Axew (%.1f)"):format(tall))
  -- a balloon with no size falls back to its phase's scale (Blastoise's row held back)
  local keep = G3.SIZE_PX[9]
  G3.SIZE_PX[9] = nil
  local bs = make("secret_04")
  bs:setGame3d(true)
  bs:startScript()
  local ph = bs.script.phase
  T.check(ph.species == 9 and near(bs:botR3() * 2, G3.BAL_SIZE * ph.scale, 1e-6), "an unsized balloon (Blastoise) by its phase's scale")
  G3.SIZE_PX[9] = keep
  -- every phase the courses use has a size (the Megas by their phase)
  local missing = {}
  for id, rec in pairs(GA.phases) do
    if not ((G3.SIZE_PHASE or {})[id] or G3.SIZE_PX[rec.species]) then missing[#missing + 1] = id .. ":" .. tostring(rec.species) end
  end
  T.check(#missing == 0, "every phase sized (" .. (#missing == 0 and "all" or table.concat(missing, " ")) .. ")")
end

-- the edge ripples: a disc 2.5 above the trainee for the top, 2.5 to its right / left for the
-- sides, each facing the side pushed
do
  local e = make("lv1_hp")
  e:setGame3d(true)
  local q = e.player
  local cx, cy, cz, ux, uy, uz, vx, vy, vz = e:edgeDisc3(1)
  T.check(near(cx, q.x) and near(cy, q.y + G3.EDGE_OFF) and near(cz, q.z) and near(uy, 0) and near(vy, math.sin(math.rad(G3.EDGE_TILT))),
    "the top ripple: a disc 2.5 over the trainee, tilted EDGE_TILT toward the camera")
  local rx, ry, rz, rux, ruy = e:edgeDisc3(2)
  local lx = e:edgeDisc3(4)
  T.check(near(rx, q.x + G3.EDGE_OFF) and near(ry, q.y) and near(rz, q.z) and near(lx, q.x - G3.EDGE_OFF)
    and near(ruy, 1), "the side ripples: upright discs 2.5 to its right (toward +x at the middle) and left")
end

-- the bitbots where the game has them: the middle one nearer the camera, the sides apart, each
-- on its loop
do
  local b = make("lv3_hp")
  b:setGame3d(true)
  local L = { id = 1, loopA = 0 }
  local M = { id = 2, loopA = math.pi / 2 }
  local _, _, lz = b:bitPos3(L)
  local mx, my, mz = b:bitPos3(M)
  local lx = b:bitPos3(L)
  T.check(mz > lz and near(mx, G3.BIT_SPOTS[2][1]) and near(my, G3.BIT_SPOTS[2][2] + G3.BIT_LOOP_R),
    "the middle bitbot nearer the camera, its loop about its spot")
  T.check(near(lx, G3.BIT_SPOTS[1][1] + G3.BIT_LOOP_R), "...the left one on its loop left of the middle")
end

-- the shield's target on the card's circle: top of the turn at (0, R sin 22.5 + R / 2, R cos 22.5),
-- on the sphere R about the balloon's foot, round once in 360 frames at spin 1
do
  local e = make("lv2_def")
  e:setGame3d(true)
  local bx = e:botCentre3()
  local g = { kind = "marker", age = 0, orbit = { spin = 1, theta0 = 0 } }
  local x, y, z = e:markerPos3(g)
  local R = G3.SHIELD_R
  T.check(near(x, bx, 1e-6) and near(y, R * math.sin(math.rad(22.5)) + R / 2, 1e-6) and near(z, R * math.cos(math.rad(22.5)), 1e-6),
    ("the shield's target starts over the cage's face (%.1f, %.1f, %.1f)"):format(x, y, z))
  g.age = 90 / 30
  local lx = e:markerPos3(g)
  g.age = 360 / 30
  local x2, y2, z2 = e:markerPos3(g)
  T.check(lx < bx and near(x2, x, 1e-6) and near(y2, y, 1e-6) and near(z2, z, 1e-6), "...a quarter turn takes it left (anticlockwise), a whole turn home")
  local _, _, _, half = e:goalBox3(g)
  T.check(half == G3.SHIELD_HIT, "...hit within 6")
end

-- a bitbot fires again only once its shot is gone: 30 frames after it lands, then a 30-frame
-- wind-up - the middle one's interval ~94 frames (the captures'), from the trainee standing still
do
  local e = make("lv2_spd")
  e:setGame3d(true)
  e.player.safe = 1e9
  e.bits = { { id = 2, x = 0, y = 0.5, z = 0.7, hp = 100, maxHp = 100, r = 0.1, cx = 0, cy = 0.5, loopA = 0, fireT = 0, game = true, every = 94 } }
  local fires = {}
  for _ = 1, 12 * 120 do
    for _, ev in ipairs(e:update(1 / 120) or {}) do if ev.kind == "bit_fire" then fires[#fires + 1] = ev.t end end
  end
  local gap = #fires >= 2 and (fires[2] - fires[1]) * 30 or 0
  T.check(gap > 85 and gap < 100, ("the middle bitbot fires every ~94 frames (%.1f)"):format(gap))
end

-- off: the 2D world as before
s:setGame3d(false)
T.check(s.game3d == nil and near(s.player.z, N.PLAYER.Z) and s.player.x == 0, "off: the flat world's trainee again")

T.finish("play_nav sim3d")
