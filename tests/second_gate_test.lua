-- The second-display gate: NaviPlay's claim mutes downstream render.compose
-- mods (Kanto Gear) and the release hands the screen back. A fake bridge
-- records calls; the engine's own hook chain checks the wrap order.
-- Run from the engine root: luajit mods/play_nav/tests/second_gate_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local Gate = loadFile("mods/play_nav/src/second_gate.lua")

local function fakeBridge()
  local b = { pushes = 0, enabled = {}, queue = { "down,1,2", "up,1,2" } }
  b.usable = function() return true end
  b.available = function() return true end
  b.detected = function() return true end
  b.push = function() b.pushes = b.pushes + 1; return true end
  b.pollTouch = function() return table.remove(b.queue, 1) end
  b.setEnabled = function(on) b.enabled[#b.enabled + 1] = on end
  return b
end

-- ------- unclaimed: every call passes through

do
  local b = fakeBridge()
  local g = Gate.new(b)
  local p = g.proxy
  T.eq(p.detected(), true, "unclaimed: detected passes through")
  T.eq(p.push({}, 1, 1), true, "unclaimed: push passes through")
  T.eq(b.pushes, 1, "unclaimed: the bridge got the frame")
  T.eq(p.pollTouch(), "down,1,2", "unclaimed: touches pass through")
  p.setEnabled(true)
  T.eq(b.enabled[1], true, "unclaimed: setEnabled passes through")
  g:release()
  T.eq(#b.enabled, 1, "release while unclaimed does nothing")
end

-- ------- claimed: downstream sees no display, frames and touches stay out

do
  local b = fakeBridge()
  local g = Gate.new(b)
  local p = g.proxy      -- kept from an earlier frame, as Kanto Gear keeps it
  g:claim()
  T.eq(p.usable(), true, "claimed: usable still real")
  T.eq(p.available(), true, "claimed: available still real")
  T.eq(p.detected(), false, "claimed: detected is false")
  T.eq(p.push({}, 1, 1), true, "claimed: push reports shown")
  T.eq(b.pushes, 0, "claimed: no frame reaches the bridge")
  T.eq(p.pollTouch(), nil, "claimed: no touches downstream")
  T.eq(#b.queue, 2, "claimed: the queue is left for NaviPlay")
  p.setEnabled(true)
  T.eq(#b.enabled, 0, "claimed: setEnabled only recorded")
  g:release()
  T.eq(b.enabled[1], true, "release: enabled as the downstream mod asked")
  T.eq(p.detected(), true, "released: detected again")
  p.push({}, 1, 1)
  T.eq(b.pushes, 1, "released: frames reach the bridge")
end

do
  local b = fakeBridge()
  local g = Gate.new(b)
  g:claim()
  g:release()
  T.eq(b.enabled[1], false, "release with nobody downstream: display off, as before")
end

-- ------- the engine's hook chain: NaviPlay's wrap runs outside Kanto Gear's

do
  local Hooks = require("src.mods.Hooks")
  local hooks = Hooks.new()
  local b = fakeBridge()
  local g = Gate.new(b)
  local seen
  hooks:wrap("render.compose", function(next, renderer, ctx)
    seen = ctx.secondScreen
    ctx.secondScreen.setEnabled(true)
    ctx.secondScreen.push({}, 1, 1)
    return next()
  end, -1000, "kanto_gear")
  hooks:wrap("render.compose", function(next, renderer, ctx)
    if ctx and ctx.secondScreen then ctx.secondScreen = g.proxy end
    return next()
  end, 1000, "play_nav")
  g:claim()
  hooks:call("render.compose", function() return false end, {}, { secondScreen = b })
  T.eq(seen, g.proxy, "chain: Kanto Gear receives the proxy")
  T.eq(b.pushes, 0, "chain: its frame never reaches the bridge while claimed")
  g:release()
  hooks:call("render.compose", function() return false end, {}, { secondScreen = b })
  T.eq(b.pushes, 1, "chain: after release its frame is shown")
end

T.finish("play_nav second gate")
