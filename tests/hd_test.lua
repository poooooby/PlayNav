-- NaviPlay's high-resolution drawing: the density rules, the pixel-art filter choice, the
-- art filters, and the top-screen overlay standing down when it should. A fake
-- love.graphics records what would be drawn.
-- Run from the engine root: luajit mods/play_nav/tests/hd_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

-- ------- headless: no love at all

do
  local saved = love
  love = nil
  local HD = loadFile("mods/play_nav/src/hd.lua")
  T.eq(HD.outputScale(), 1, "headless: output scale is 1")
  T.eq(HD.sharpShader(), nil, "headless: no shader")
  HD.drawPixel(nil, 0, 0)
  T.check(true, "headless: drawPixel is a no-op")
  love = saved
end

-- ------- a fake graphics table

local calls, transform, canvas = {}, { sx = 1, tx = 0, ty = 0 }, nil
local stackTop = nil
local fakeShader = { send = function() end }
love = {
  graphics = {
    transformPoint = function(x, y) return transform.tx + x * transform.sx, transform.ty + y * transform.sx end,
    getCanvas = function() return canvas end,
    getDPIScale = function() return 1 end,
    newShader = function() return fakeShader end,
    getShader = function() return nil end,
    setShader = function(sh) calls[#calls + 1] = { "shader", sh } end,
    draw = function(img, ...) calls[#calls + 1] = { "draw", img, ... } end,
    push = function() end, pop = function() end, origin = function() end,
    setBlendMode = function() end, setScissor = function(...) calls[#calls + 1] = { "scissor", ... } end,
    translate = function(x, y) calls[#calls + 1] = { "translate", x, y } end,
    scale = function(x, y) calls[#calls + 1] = { "scale", x, y } end,
    setColor = function() end,
  },
}
local HD = loadFile("mods/play_nav/src/hd.lua")

-- ------- density

T.eq(HD.density(1, 1), 1, "x1 at 1 dpi stays 1")
T.eq(HD.density(1, 3), 3, "a x1 rect on a 3x screen draws at 3")
T.eq(HD.density(2, 1), 2, "a x2 rect at 2")
T.eq(HD.density(1.35, 2), 2.75, "quantised to quarter steps")
T.eq(HD.density(3, 3), HD.MAX_K, "capped")
T.eq(HD.density(0.5, 1), 1, "never below 1")
HD.enabled = false
T.eq(HD.density(3, 1), 1, "HD off: always 1")
HD.enabled = true

-- ------- the filter for pixel art

T.eq(HD.modeFor(1), "nearest", "whole pixels: nearest")
T.eq(HD.modeFor(3), "nearest", "x3: nearest")
T.eq(HD.modeFor(2.7), "sharp", "fractional: the sharp shader")
T.eq(HD.modeFor(0.5), "linear", "shrunk: linear")
HD.enabled = false
T.eq(HD.modeFor(2.7), "nearest", "HD off: nearest")
HD.enabled = true

local function fakeImage(pw, w)
  local img = { filter = { "nearest", "nearest" } }
  function img:getWidth() return w end
  function img:getPixelWidth() return pw end
  function img:getPixelDimensions() return pw, pw end
  function img:getFilter() return self.filter[1], self.filter[2] end
  function img:setFilter(a, b) self.filter = { a, b } end
  return img
end

do
  canvas = {}  -- drawing into the surface canvas: units are pixels
  transform.sx = 3
  local img = fakeImage(64, 64)
  calls = {}
  HD.drawPixel(img, 10, 20, 0, 1, 1)
  T.eq(#calls, 1, "x3: one plain draw, no shader")
  T.eq(calls[1][1], "draw", "...a draw")
  T.eq(calls[1][3], 10, "love.graphics.draw's arguments pass through")
  calls = {}
  HD.drawPixel(img, 10, 20, 0, 0.9, 0.9)
  T.eq(calls[1][1], "shader", "2.7 px per texel: the shader goes on")
  T.eq(calls[2][1], "draw", "...the draw")
  T.eq(calls[3][1], "shader", "...and comes off")
  T.eq(img.filter[1], "nearest", "the image's filter is restored")
  local quad = { getViewport = function() return 0, 0, 32, 32 end }
  calls = {}
  HD.drawPixel(img, quad, 5, 6, 0, 1, 1)
  T.eq(calls[1][3], quad, "a quad is passed through")
  T.eq(calls[1][4], 5, "...with its position")
  -- a 256 px canvas holding a 64 px sprite: texels per unit 4
  calls = {}
  HD.drawPixel(fakeImage(256, 64), 0, 0, 0, 1, 1)
  T.eq(calls[1][1], "draw", "a 4x-texel canvas at x3 is 0.75 px per texel: a linear shrink, no shader")
  transform.sx = 1
  canvas = nil
end

do
  local img = fakeImage(40, 40)
  img.getMipmapCount = function() return 6 end
  local mip
  img.setMipmapFilter = function(_, f) mip = f end
  HD.prepareArt(img)
  T.eq(img.filter[1], "linear", "ORAS art is linear")
  T.eq(mip, "linear", "...trilinear through its mipmaps")
  HD.enabled = false
  HD.prepareArt(img)
  T.eq(img.filter[1], "nearest", "HD off: nearest, as before")
  HD.enabled = true
end

-- ------- the top-screen overlay

package.loaded["src.ui.game3.stack"] = { top = function() return stackTop end }
local warned = 0
local mod = { log = { warn = function() warned = warned + 1 end } }
local Top = loadFile("mods/play_nav/src/hd_top.lua")(mod, { HD = HD, ids = { play_nav_amie = true } })
local drawn = 0
local layer = { drawScene = function() drawn = drawn + 1 end }
local vp = { gameX = 10, gameY = 20, gameWidth = 480, gameHeight = 320, scale = 2 }

stackTop = { id = "play_nav_amie", mod = layer }
calls = {}
T.check(Top.draw(vp), "our layer on top: drawn")
T.eq(drawn, 1, "...the scene once")
T.check(layer.hdLive, "...and the layer knows (its own draw paints only the backdrop)")
local sawScale
for _, c in ipairs(calls) do if c[1] == "scale" then sawScale = c end end
T.eq(sawScale and sawScale[2], 2, "240 units onto 480 px")
T.eq(sawScale and sawScale[3], 2, "160 onto 320")

stackTop = { id = "start_menu", mod = {} }
T.check(not Top.draw(vp), "another layer above: stands down")
T.check(not layer.hdLive, "...and the layer draws itself fully again")

stackTop = { id = "play_nav_amie", mod = layer }
HD.enabled = false
T.check(not Top.draw(vp), "HD off: not drawn")
T.check(not layer.hdLive, "...the plain draw")
HD.enabled = true

-- a layer that paints the whole playfield: it gets the playfield as an extent in 240x160 units
local seen
layer.drawScene = function() drawn = drawn + 1; seen = layer.extent end
local fills = true
layer.fillTop = function() return fills end
Top.playfield = function() return { x = 0, y = 0, w = 540, h = 404 } end
T.check(Top.wantsFill(), "fillTop true, HD on: the top screen fills")
T.check(Top.draw(vp), "...drawn")
T.check(seen ~= nil, "...with an extent")
T.eq(seen and seen.x, -5, "...from 5 units left of the frame (10 px at 2x)")
T.eq(seen and seen.y, -10, "...and 10 above it")
T.eq(seen and seen.w, 270, "...270 units across (540 px)")
T.eq(seen and seen.h, 202, "...202 down")
T.eq(layer.extent, nil, "...cleared after the draw")
fills = false
T.check(not Top.wantsFill(), "fillTop false: no fill")
Top.draw(vp)
T.eq(seen, nil, "...and no extent")
fills = true
HD.enabled = false
T.check(not Top.wantsFill(), "HD off: never fills (the engine's own draw covers the frame only)")
HD.enabled = true
layer.fillTop = nil
Top.playfield = nil

layer.drawScene = function() error("boom") end
T.check(not Top.draw(vp), "an error: not drawn")
T.check(not layer.hdLive, "...the next frame is the plain draw")
T.eq(warned, 1, "...reported once")

-- ------- text that fits its box (src/textfit.lua)

do
  local TF = loadFile("mods/play_nav/src/textfit.lua")
  -- a fake font: every char 6 units wide, lines wrap on words
  local function wrap(t, width)
    local lines, cur = {}, ""
    for word in t:gmatch("%S+") do
      local try = cur == "" and word or (cur .. " " .. word)
      if #try * 6 <= width or cur == "" then cur = try else lines[#lines + 1] = cur; cur = word end
    end
    lines[#lines + 1] = cur
    return lines
  end
  local s, lines = TF.layout(wrap, 12, "short", 188, 14)
  T.eq(s, 1, "a short line keeps full size")
  T.eq(#lines, 1, "...one line")
  local long = "TORCHIC has had enough petting for now."
  s, lines = TF.layout(wrap, 12, long, 188, 14)
  T.check(s < 1, "a line too long for one row shrinks (" .. s .. ")")
  T.eq(#lines, 1, "...until it fits one row")
  s, lines = TF.layout(wrap, 12, long, 188, 26)
  T.eq(s, 1, "two rows of room: full size")
  T.eq(#lines, 2, "...wrapped to two")
  s = TF.layout(wrap, 12, string.rep("word ", 200), 100, 14)
  T.eq(s, TF.MIN_SCALE, "never below the minimum scale")
end

T.finish("play_nav hd")
