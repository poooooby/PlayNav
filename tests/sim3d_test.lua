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

-- the balloon: its phase's scale, its feet on the grass
do
  local bl = make("lv2_spa")
  bl:setGame3d(true)
  bl:startScript()
  local ph = bl.script.phase
  local _, cy = bl:botCentre3()
  local R3 = bl:botR3()
  T.check(near(cy, G3.GROUND + ph.midY * ph.scale, 1e-6),
    ("Magneton floats: its middle midY %d x scale above the grass"):format(ph.midY))
  T.check(R3 > 0 and near(R3 * 2, G3.BAL_SIZE * (ph.scale or 0.7), 1e-6),
    ("...its size the phase's scale %.2f x %d"):format(ph.scale or 0, G3.BAL_SIZE))
  local gr = make("lv1_atk")
  gr:setGame3d(true)
  gr:startScript()
  local gph = gr.script.phase
  local _, gcy = gr:botCentre3()
  local halfH = gr.shape and gr.shape.halfH or 1
  T.check((gph.midY or 0) == 0 and near(gcy - halfH * gr:botR3(), G3.GROUND, 1e-6),
    "Axew (midY 0) stands on the grass")
end

-- off: the 2D world as before
s:setGame3d(false)
T.check(s.game3d == nil and near(s.player.z, N.PLAYER.Z) and s.player.x == 0, "off: the flat world's trainee again")

T.finish("play_nav sim3d")
