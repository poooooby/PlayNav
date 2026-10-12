-- The window-to-surface pointer path, driven the way main.lua drives it on
-- Gen 1: through Game's own touch handlers, the real Input and TouchControls
-- singletons and the input.pointer hook. Run from the engine root:
--   luajit mods/play_nav/tests/pointer_stream_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")

local function fakeGame(loader, data)
  return setmetatable({ input = Input, mods = loader, data = data,
    stack = { states = { {} } } }, { __index = Game })
end

local run = T.sdk.loadMod("mods/play_nav", { generation = 1 })
T.eq(#run.errors, 0, "the mod loads clean (" .. tostring(run.errors[1]) .. ")")
-- the manifest claims Gen 3 only; this Gen 1 window path then has nothing to drive
if run.mod and run.mod.state == "wrong_generation" then
  T.check(true, "skipped: play_nav declares Gen 3 only, so the Gen 1 pointer path is not loaded")
  T.finish("play_nav pointer stream")
  return
end

local X = run.loader.exports.play_nav
local test = X._test
local Pointer = X.pointer
local Apps = X.apps
local game = fakeGame(run.loader, run.data)

Input:init()
TouchControls:init()
test.setGame(game)
test.setMode("split")
-- a 2x surface sitting at window (100, 500): logical (lx, ly) is at
-- (100 + 2*lx, 500 + 2*ly)
local RECT = { x = 100, y = 500, w = 512, h = 384, scale = 2 }
test.setRect(RECT)
local function win(lx, ly) return RECT.x + lx * RECT.scale, RECT.y + ly * RECT.scale end

-- a passive app so dispatch can be observed without side effects
local seen = {}
Apps:register({
  id = "probe", title = "PROBE",
  draw = function() end,
  pointer = function(_, ev, rec) seen[#seen + 1] = { phase = ev.phase, x = ev.x, y = ev.y, id = ev.id, rec = rec } end,
})
Apps:setActive("probe")

local function wipe() for i = #seen, 1, -1 do seen[i] = nil end end

-- ------- a touch that begins on the surface is consumed and tracked

do
  wipe()
  local wx, wy = win(64, 50 + Apps.TAB_H)
  Game.touchpressed(game, 1, wx, wy, 0, 0, 0.8)
  local rec = Pointer:get(1)
  T.check(rec ~= nil, "a touch inside the surface opens a record")
  T.eq(rec.x, 64, "logical x is derived from the surface rect")
  T.eq(rec.y, 50 + Apps.TAB_H, "logical y too")
  T.eq(rec.pressure, 0.8, "pressure rides along")
  T.eq(seen[1] and seen[1].phase, "pressed", "the active app sees pressed")
  T.eq(seen[1].y, 50, "...in app space (tab strip subtracted)")

  Game.touchmoved(game, 1, wx + 20, wy + 10, 20, 10, 0.8)
  T.eq(rec.x, 74, "a move updates the record immediately")
  T.eq(rec.y, 55 + Apps.TAB_H, "...on both axes")
  T.eq(#rec.path, 2, "the path grows per event, not per tick")
  T.eq(seen[2].phase, "moved", "the app sees moved")

  Game.touchreleased(game, 1, wx + 20, wy + 10, 0, 0, 0.8)
  T.eq(Pointer:get(1), nil, "release closes the record")
  T.eq(seen[3].phase, "released", "the app sees released")
  T.eq(game.modPointers and game.modPointers[1], nil, "the engine record is gone too")
end

-- ------- a touch on the top screen passes through untouched

do
  wipe()
  Game.touchpressed(game, 2, 10, 10, 0, 0, 1)
  T.eq(Pointer:get(2), nil, "a touch outside the surface opens nothing")
  T.eq(#seen, 0, "...and reaches no app")
  Game.touchmoved(game, 2, RECT.x + 10, RECT.y + 10)
  T.eq(Pointer:get(2), nil, "wandering onto the surface mid-drag does not capture it")
  Game.touchreleased(game, 2, RECT.x + 10, RECT.y + 10)
  T.eq(#seen, 0, "...ever")
end

-- ------- two fingers stay separate

do
  wipe()
  Game.touchpressed(game, "a", win(20, 40))
  Game.touchpressed(game, "b", win(200, 140))
  Game.touchmoved(game, "a", win(30, 40))
  T.eq(Pointer:get("a").x, 30, "finger a moved")
  T.eq(Pointer:get("b").x, 200, "finger b did not")
  T.eq(Pointer.count, 2, "two pointers are down")
  Game.touchreleased(game, "b", win(200, 140))
  Game.touchreleased(game, "a", win(30, 40))
  T.eq(Pointer.count, 0, "both lifted")
end

-- ------- focus loss cancels a live surface pointer

do
  wipe()
  Game.touchpressed(game, 7, win(50, 60))
  Game.focus(game, false)
  T.eq(Pointer:get(7), nil, "focus loss closes the record")
  T.eq(seen[#seen].phase, "cancelled", "...as cancelled")
end

-- ------- the mouse reaches the surface the same way

do
  wipe()
  local mx, my = win(10, 20 + Apps.TAB_H)
  Game.mousepressed(game, mx, my, 1, false)
  local rec = Pointer:get("mouse")
  T.check(rec ~= nil, "a real mouse press on the surface is tracked")
  T.eq(rec and rec.source, "mouse", "...and reports source mouse")
  Game.mousemoved(game, mx + 4, my + 4, 4, 4, false)
  Game.mousereleased(game, mx + 4, my + 4, 1, false)
  T.eq(Pointer:get("mouse"), nil, "release closes it")
  T.eq(seen[#seen].phase, "released", "the app saw the lifecycle")
end

-- ------- the tab strip switches apps and swallows that touch

do
  wipe()
  local n = #Apps.list
  local cell = 256 / n
  -- press on the first tab (refresh)
  Game.touchpressed(game, 9, win(cell / 2, 4))
  T.eq(Apps:active().id, "play", "pressing the first tab activates play")
  Game.touchmoved(game, 9, win(cell / 2, 60))
  Game.touchreleased(game, 9, win(cell / 2, 60))
  Apps:setActive("probe")
  T.eq(#seen, 0, "a tab touch never reaches the app body")
end

-- ------- second-screen events feed the same records

do
  wipe()
  test.setPushK(3)
  test.feedSecond("down", 300, 300)
  local rec = Pointer:get("screen2")
  T.check(rec ~= nil, "a second-screen down opens a record")
  T.eq(rec.x, 100, "pushed-frame pixels divide by the push scale")
  T.eq(rec.y, 100, "...on y too")
  T.eq(test.feedSecond("move", 0, 0), true, "a move while down is accepted")
  test.feedSecond("up", 330, 300)
  T.eq(Pointer:get("screen2"), nil, "up closes it")
  T.eq(test.feedSecond("move", 1, 1), false, "a move with no pointer down is ignored")
end

-- ------- mode off: nothing is captured

do
  wipe()
  test.setMode("off")
  Game.touchpressed(game, 11, win(64, 64))
  T.eq(Pointer:get(11), nil, "with the surface off, touches pass through")
  Game.touchreleased(game, 11, win(64, 64))
  test.setMode("split")
end

run.release()
T.finish("play_nav pointer stream")
