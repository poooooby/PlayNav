-- 3D AMIE's cameras (src/amie/stage3d.lua), headless: the species' camera from data/amie_cameras.lua
-- (the card's a/0/8/9 presets), the entry ease, the stage's origin on the sprite's feet, the top
-- screen looking up, the stage's animation, and the camera data itself.
-- Run from the engine root: luajit mods/play_nav/tests/amie_stage3d_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local ROOT = "mods/play_nav/"
local function loadFile(path) return assert(loadfile(ROOT .. path))() end
local cams = loadFile("data/amie_cameras.lua")
local mod = { log = { warn = function() end, info = function() end } }
local St = loadFile("src/amie/stage3d.lua")(mod, { cameras = cams })

-- the data: every National Dex number to 721, four presets of six
local n = 0
for k, v in pairs(cams) do if type(k) == "number" then n = n + 1; T.eq(#v, 24, "dex " .. k .. " has four presets") end end
T.eq(n, 721, "721 species")
T.eq(cams[1][7], -2, "Bulbasaur's preset 1 eye x (the card's -2, 70, 294)")
T.eq(cams[1][9], 294, "...its z")
T.eq(cams[380][11], 82, "Latias' preset 1 interest y 82")

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- entry: the average of presets 0 and 1, easing into preset 1
St.enter(380)
St.setFoot(160, 267.5, 287.5)
St.placeCameras()
T.check(near(St.cam.ez, (523 + 371) / 2), ("on entry the eye is between presets 0 and 1 (z %.1f)"):format(St.cam.ez))
St.update(St.ENTER_S + 0.1)
St.placeCameras()
T.check(near(St.cam.ex, 27) and near(St.cam.ey, 116) and near(St.cam.ez, 371), "after the ease, preset 1")
T.check(near(St.cam.iy, 82), "...looking at its interest")

-- the stage's origin (the game's Pokemon) on the sprite's feet, whatever the species
for _, dex in ipairs({ 1, 6, 380, 9999 }) do
  St.enter(dex)
  St.update(5)
  St.setFoot(160, 267.5, 287.5)
  St.placeCameras()
  local x, y = St.project(0, 0, 0)
  T.check(near(x, 160, 1e-3) and near(y, 267.5, 1e-3), ("dex %d: the origin at the feet (%.2f, %.2f)"):format(dex, x, y))
  -- the stage's floor edge further back is higher on the screen, the sky above that
  local _, yFar = St.project(0, 0, -400)
  local _, ySky = St.project(0, 300, -460)
  T.check(yFar < y and ySky < yFar, ("dex %d: the far lawn above the feet, the sky above that"):format(dex))
end
-- a species with no record: the default camera
St.enter(9999); St.update(5); St.placeCameras()
T.eq(St.cam.ez, St.DEFAULT[3], "no record: the default camera")

-- the top screen: the same eye, tilted up - the lower camera's interest sits below its middle
St.enter(380); St.update(5); St.placeCameras()
local _, ty = St.projectTop(St.cam.ix, St.cam.iy, St.cam.iz)
T.check(ty > 80 + 20, ("the top camera looks up: the interest at y %.1f, below the frame's middle 80"):format(ty))
local _, skyY = St.projectTop(0, 600, -468)
T.check(skyY > -200 and skyY < 160, ("the sky cylinder high up shows on the top screen (y %.1f)"):format(skyY))

-- the stage's animation: the small clouds drift, the cumulus sway, the bubbles rise
local scene = { pieces = { { anim = "drift", uv = { 0, 0 } }, { anim = "sway", uv = { 0, 0 } }, { anim = "rise", uv = { 0, 0 } } } }
St.update(250 / 30)    -- 250 frames on (plus the earlier updates)
St.animate(scene)
T.check(scene.pieces[1].uv[1] < 0 and scene.pieces[1].uv[1] > -1, "the small clouds have drifted")
T.check(scene.pieces[2].uv[1] >= 0 and scene.pieces[2].uv[1] <= St.ANIM.SWAY + 1e-9, "the cumulus sway within 0..0.05")
T.check(scene.pieces[3].uv[2] < 0 and scene.pieces[3].uv[2] > -1, "the bubbles have risen")

T.finish("play_nav amie stage3d")
