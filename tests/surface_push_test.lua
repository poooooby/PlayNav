-- The second display's readback (src/surface.lua): with the async calls (Android's LOVE:
-- requestImageData / pollImageData) the frame is drawn once, read without waiting and handed
-- over a poll later; no new frame is drawn while one is read; a stuck read starts over on
-- fresh canvases; without them the blocking read returns the pixels at once.
-- Run from the engine root: luajit mods/play_nav/tests/surface_push_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

-- a fake love.graphics whose canvases count readbacks
local function fakeLove(async)
  local stats = { canvases = 0, sync = 0, requests = 0, draws = 0 }
  local function newCanvas(w, h)
    stats.canvases = stats.canvases + 1
    local c = { w = w, h = h, ready = false }
    function c:getPixelWidth() return self.w end
    function c:setFilter() end
    function c:newImageData() stats.sync = stats.sync + 1; return { pixels = self.w } end
    if async then
      function c:requestImageData() stats.requests = stats.requests + 1; self.ready = false; return true end
      function c:pollImageData()
        if not self.ready then return nil end
        self.ready = false
        return { pixels = self.w, async = true }
      end
    end
    return c
  end
  local noop = function() end
  love = { graphics = setmetatable({ newCanvas = newCanvas, newFont = function() return {} end }, {
    __index = function() return noop end }) }
  return stats
end

local Layout = { W = 256, H = 192 }
local HD = { enabled = true, MAX_K = 4, density = function(k) return k end }
local mod = { log = { warn = function() end } }

do
  local stats = fakeLove(true)
  local S = loadFile("mods/play_nav/src/surface.lua")(mod, Layout, HD)
  local draws = 0
  local drawFn = function() draws = draws + 1 end
  local data = S:requestPush(3, drawFn, 0)
  T.eq(data, nil, "async: nothing handed back at the request")
  T.eq(stats.requests, 1, "async: one readback started")
  T.eq(stats.sync, 0, "async: no blocking read")
  T.eq(draws, 1, "async: the frame drawn once")
  T.eq(S:pollPush(), nil, "async: not ready yet")
  T.eq(S:requestPush(3, drawFn, 0.1), nil, "async: a second request while one is read...")
  T.eq(draws, 1, "...draws nothing (the canvas must not change under the read)")
  S.pending.src.ready = true
  local got, w, h = S:pollPush()
  T.check(got and got.async, "async: the pixels come through the poll")
  T.eq(w, 768, "async: at k = 3 (width)")
  T.eq(h, 576, "async: at k = 3 (height)")
  T.eq(S.pending, nil, "async: nothing pending after")
  S:requestPush(3, drawFn, 1)
  T.eq(draws, 2, "async: the next frame draws again")
  local before = stats.canvases
  S:dropStale(1.5)
  T.check(S.pending ~= nil, "a read under a second old is kept")
  S:dropStale(2.1)
  T.eq(S.pending, nil, "a stuck read is dropped")
  T.eq(S.canvas, nil, "...and the canvas starts over")
  S:requestPush(3, drawFn, 2.2)
  T.check(stats.canvases > before, "...on a fresh one")
end

do
  local stats = fakeLove(false)
  local S = loadFile("mods/play_nav/src/surface.lua")(mod, Layout, HD)
  local data, w = S:requestPush(2, function() end, 0)
  T.check(data ~= nil and w == 512, "no async calls: the blocking read hands the pixels back at once")
  T.eq(stats.sync, 1, "...one blocking read")
  T.eq(S.pending, nil, "...nothing pending")
end

T.finish()
