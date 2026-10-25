-- 3D SUPER TRAINING's camera (src/training/arena3d.lua), headless: the game's orbit (the
-- trainee's x / y onto azimuth 60..120 and elevation 0..45, its distance the radius), the
-- trainee on its sphere point ahead of the eye, the balloon's plane cast back exactly, nearer
-- drawn larger, the Poke Ball over the far stand above the balloon at the start, the ground
-- ellipse flat, the frustum handed to g3d agreeing with the projector, g3d loading without love.
-- Run from the engine root: luajit mods/play_nav/tests/arena3d_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local N = loadFile("mods/play_nav/data/training_rules.lua")
local Sim = loadFile("mods/play_nav/src/training/sim.lua")(N)
local mod = { path = "mods/play_nav", read = function(_, p) return readFile("mods/play_nav/" .. p) end }
local A3 = loadFile("mods/play_nav/src/training/arena3d.lua")(mod, { Sim = Sim, Rules = { N = N } })

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function sim(x, y, dist, z)
  return { t = 0, player = { x = x, y = y, dist = dist, z = z or N.PLAYER.Z } }
end

-- the orbit: the box's edges are the game's limits
do
  local az, el = A3.orbitAngles(N.PLAYER.X_MAX, 0)
  T.check(near(az, 60), "the trainee at the right edge: azimuth 60 (the game's limit)")
  az = A3.orbitAngles(-N.PLAYER.X_MAX, 0)
  T.check(near(az, 120), "...at the left edge: 120")
  az, el = A3.orbitAngles(0, N.PLAYER.Y_MAX)
  T.check(near(az, 90) and near(el, 45), "...at the top: elevation 45, straight in front")
  local x, y, z = A3.sphere(0, 90, 240)
  T.check(near(x, 0, 1e-9) and near(y, 0) and near(z, 240, 1e-9), "the game's start: (0, 0, 240) on its sphere")
  A3.update(sim(N.PLAYER.X_MAX, 0, 240))
  local _, _, r = A3.orbitNow()
  local ax = A3.camOffset()
  T.check(ax > 50 and r == 240, ("moved right, the trainee orbits to +x (%.0f)"):format(ax))
end

-- the balloon's plane: a point projected and cast back lands where it was
A3.update(sim(0.3, 0.4, 240))
local worst = 0
for _, p in ipairs({ { 0, 1 }, { -1.2, 0.3 }, { 1.5, 1.9 }, { 0.4, 0.05 } }) do
  local sx, sy = A3.project(p[1], p[2], 1)
  local x, y = A3.unprojectToPlane(sx, sy, 1)
  worst = math.max(worst, math.abs(x - p[1]), math.abs(y - p[2]))
end
T.check(worst < 1e-6, ("a point on the balloon's plane, projected and cast back, lands where it was (%.1e)"):format(worst))

-- right is right, up is up; the trainee's plane nearer and larger; nearer still at 180
A3.update(sim(0, 0, 240))
local cx, cy, kFar = A3.project(0, 1, 1)
local rx = A3.project(1, 1, 1)
local _, uy = A3.project(0, 1.5, 1)
T.check(rx > cx, "world +x is to the right on the screen")
T.check(uy < cy, "world +y is up on the screen")
local tx, ty, kNear = A3.project(0, 0, N.PLAYER.Z)
T.check(kNear > kFar, ("the trainee's plane is drawn larger (k %.2f vs %.2f)"):format(kNear, kFar))
T.check(near(kFar, 120 / 118 * A3.CAM.BAL_K, 0.05), ("the balloon's plane framed BAL_K of the 2D view at the middle distance (k %.3f)"):format(kFar))
T.check(tx < 120 and ty > 100, ("the trainee left of the middle and low, as the game's (%.0f, %.0f)"):format(tx, ty))
A3.update(sim(0, 0, 180, 1 - 0.9 * 180 / 240))
local _, _, kClose = A3.project(0, 1, 1)
T.check(kClose > kFar * 1.15, ("a step nearer, the balloon looks larger (k %.2f vs %.2f)"):format(kClose, kFar))

-- the Poke Ball over the far stand (0, 401, -886 in the model) above the balloon at the start
do
  A3.update(sim(0, 0, 240))
  local _, by = A3.project(0, N.BOT.SHAPE_CY + 0.3, 1)
  local bx2, pby = A3.projectModel(0, 401, -886)
  T.check(pby < by and pby > 0, ("the far Poke Ball shows above the balloon's top (y %.0f over %.0f)"):format(pby, by))
  T.check(math.abs(bx2 - 120) < 2, "...in the middle")
end

-- a shadow on the grass is flattened by the camera's slant
local _, _, erx, ery = A3.groundEllipse(0, 1, 0.2)
T.check(ery < erx, ("a ground ellipse lies flat (%.1f x %.1f)"):format(erx, ery))

-- the matrices handed to g3d put a model point where the projector does
do
  local V, Pm = A3.viewMatrix({}), A3.projectionMatrix({}, 0, 0, 240, 160)
  local function mul(M, x, y, z, w)
    return M[1] * x + M[2] * y + M[3] * z + M[4] * w, M[5] * x + M[6] * y + M[7] * z + M[8] * w,
      M[9] * x + M[10] * y + M[11] * z + M[12] * w, M[13] * x + M[14] * y + M[15] * z + M[16] * w
  end
  local bad = 0
  for _, p in ipairs({ { 0.5, 1.2, 1 }, { -0.7, 0, 0.1 }, { 1.1, 0.4, 0.6 } }) do
    local X, Y, Z = A3.toModel(p[1], p[2], p[3])
    local vx, vy, vz, vw = mul(V, X, Y, Z, 1)
    local cxp, cyp, _, cw = mul(Pm, vx, vy, vz, vw)
    local sx, sy = (cxp / cw + 1) / 2 * 240, (1 - cyp / cw) / 2 * 160
    local px, py = A3.project(p[1], p[2], p[3])
    bad = math.max(bad, math.abs(sx - px), math.abs(sy - py))
  end
  T.check(bad < 1e-6, ("g3d's frustum puts points where the projector does (%.1e px)"):format(bad))
end

-- g3d loads in the mod's way (no require), without love
do
  local lib, why = A3.g3d()
  T.check(lib ~= nil, "g3d loads from src/g3d (" .. tostring(why) .. ")")
  if lib then
    T.check(type(lib.newModel) == "function" and type(lib.camera) == "table" and type(lib.newMatrix) == "function",
      "...with its model, camera and matrices")
    T.check(lib.camera.up[2] == 1, "...y up")
  end
end

-- arena_draw's toScreen in 2D is untouched (the projector is Sim.project when 3D is off)
do
  local Draw = loadFile("mods/play_nav/src/training/arena_draw.lua")({ options = { get = function() return nil end } },
    { host = {}, Rules = { N = N }, Sim = Sim })
  T.check(Draw.in3d() == false, "with 3D off the arena is drawn through Sim.project")
  local x, y, z = Draw.toScreen(nil, 100, 60)
  T.check(x == 100 and y == 60 and z == 1, "...and the HUD's points stay where they were")
end

T.finish("play_nav arena3d")
