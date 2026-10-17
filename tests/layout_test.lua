-- Pure geometry and parsing: no engine, no love. Run from the engine root:
--   luajit mods/play_nav/tests/layout_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

-- load the layout module the way main.lua does, straight from source
local function loadFile(path)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end

local Layout = loadFile("mods/play_nav/src/layout.lua")

-- the shapes: Kanto Gear's 10:9 by default, the 3DS's 4:3 on request
T.eq(Layout.shape, "gear", "the default shape is Kanto Gear's")
T.eq(Layout.W .. "x" .. Layout.H, "256x230", "...256x230, about 10:9 like the Gear's 160x144")
T.eq(Layout.LH, 287.5, "...287.5 tall in the 320-wide training layout space")
T.eq(Layout.setShape("3ds"), true, "switching to 3DS changes the shape")
T.eq(Layout.W .. "x" .. Layout.H, "256x192", "...to 256x192")
T.eq(Layout.LH, 240, "...and the training layout's own 320x240")
T.eq(Layout.setShape("3ds"), false, "the same shape again is no change")
T.eq(Layout.setShape("nonsense"), true, "an unknown shape falls back to the Gear's")
T.eq(Layout.H, 230, "...230 tall")
do
  local lay = Layout.dual(603, 1294, { dpi = 1, reserveBottom = 0, fill = true })
  T.check(math.abs(lay.surface.w / lay.surface.h - 256 / 230) < 1e-6, "the split's touch screen keeps the Gear shape")
end
-- the geometry checks below were written for the 4:3 surface
Layout.setShape("3ds")
local Pointer = loadFile("mods/play_nav/src/pointer.lua")({
  log = { warn = function() end, info = function() end, error = function() end },
})

-- ------- fit

T.eq(Layout.fit(512, 384), 2, "an exact 2x fits at integer 2")
T.eq(Layout.fit(600, 384), 2, "extra width does not raise the integer scale")
T.eq(Layout.fit(1080, 800), 4, "1080 wide fits 4x (1024) by width")
T.check(Layout.fit(200, 150) < 1 and Layout.fit(200, 150) > 0,
  "a short margin gets a fractional scale rather than nothing")
T.eq(Layout.fit(0, 100), 0, "no width means no scale")

-- ------- portrait split (a 1080x2400 phone)

do
  local L = Layout.split(1080, 2400, { ratio = 0.55, safeBottom = 48 })
  T.eq(L.orientation, "portrait", "taller than wide is portrait")
  T.check(L.surface.scale >= 1 and L.surface.scale % 1 == 0, "phone surface uses an integer scale")
  T.check(L.surface.x >= 0 and L.surface.x + L.surface.w <= 1080, "surface stays inside the width")
  T.check(L.surface.y + L.surface.h <= 2400 - 48, "surface stays above the safe area")
  T.check(L.game.h <= L.surface.y, "the game rect ends above the surface")
  T.check(L.game.h >= 2400 * 0.5, "the game keeps roughly its share of the height")
  local lx, ly, inside = Layout.toLogical(L.surface, L.surface.x, L.surface.y)
  T.eq(lx, 0, "top-left of the surface maps to logical 0")
  T.eq(ly, 0, "...and 0")
  T.eq(inside, true, "...and is inside")
  local _, _, out = Layout.toLogical(L.surface, L.surface.x - 1, L.surface.y)
  T.eq(out, false, "one pixel left of the surface is outside")
  local cx, cy = Layout.toLogical(L.surface, L.surface.x + L.surface.w / 2,
    L.surface.y + L.surface.h / 2)
  T.eq(cx, 128, "the horizontal centre maps to 128")
  T.eq(cy, 96, "the vertical centre maps to 96")
end

-- ------- landscape split (Steam Deck 1280x800)

do
  local L = Layout.split(1280, 800, {})
  T.eq(L.orientation, "landscape", "wider than tall is landscape")
  T.check(L.surface.x >= L.game.w, "the surface sits right of the game")
  T.check(L.surface.x + L.surface.w <= 1280, "and inside the window")
  T.check(L.surface.scale >= 1, "a Deck fits at least 1x")
end

-- ------- the Gen 3 split, New 3DS XL style: the picture as large as it can be, the touch
-- screen at its height, under it (portrait) or right of it (landscape)

local function near(a, b) return math.abs(a - b) < 0.01 end
do
  -- a 1080x2400 phone with the engine's pad taking the bottom 700
  local L = Layout.dual(1080, 2400, { reserveBottom = 700 })
  T.eq(L.orientation, "portrait", "a phone is portrait")
  T.eq(L.game.scale, 4, "a 1080-wide phone shows the picture at 4x")
  T.eq(L.game.w, 960, "...960 wide")
  T.eq(L.game.y, 4, "...at the top")
  T.eq(L.game.x, 60, "...centred across")
  T.check(near(L.surface.h, L.game.h), "the touch screen is as tall as the picture (the XL's 240 / 240 rows)")
  T.check(near(L.surface.w, L.game.h * 256 / 192), "...at its own 4:3")
  T.check(L.surface.y >= L.game.y + L.game.h and L.surface.y - (L.game.y + L.game.h) <= 8, "...just under the picture")
  T.check(L.surface.y + L.surface.h <= 2400 - 700, "the pad's room stays free")
  T.check(near(L.surface.scale, L.surface.h / 192), "the surface scale is its height over 192")

  -- landscape: far left, from the top, side by side
  local W = Layout.dual(1280, 720, { reserveBottom = 300 })
  T.eq(W.orientation, "landscape", "a desktop window is landscape")
  T.eq(W.game.x, 4, "the picture sits at the far left")
  T.eq(W.game.y, 4, "...from the top")
  T.eq(W.surface.y, W.game.y, "the touch screen shares its top edge")
  T.check(W.game.x + W.game.w < W.surface.x, "...right of the picture, no overlap")
  T.check(W.surface.x + W.surface.w <= 1280, "...inside the window")
  T.eq(W.game.scale, 3, "720 tall: 3x (4x would leave the touch screen under 80% of the picture's height)")
  T.check(W.surface.h >= W.game.h * Layout.MIN_MATCH, "...which leaves it at least 80%")
  T.check(W.surface.h + W.surface.y <= 720, "the pad reserve is portrait only; landscape still fits")

  -- the Thor's 1920x1080 main screen in split mode
  local Th = Layout.dual(1920, 1080, {})
  T.eq(Th.game.scale, 4, "1920x1080: a 4x picture, 960x640")
  T.check(near(Th.surface.h, 640), "...with the touch screen 640 tall beside it")

  -- a high-DPI phone: the picture is a whole number of physical pixels
  local D = Layout.dual(412, 915, { dpi = 2.625, reserveBottom = 260 })
  T.check(near(D.game.w * 2.625, 960), "dpi 2.625: the picture is 960 physical pixels (4x)")
  T.check(near(D.game.x * 2.625, math.floor(D.game.x * 2.625 + 1e-6)), "...on a whole physical pixel")

  -- a squeezed window: the picture stays at 1x and the touch screen takes what is left
  local S = Layout.dual(260, 300, {})
  T.eq(S.game.scale, 1, "a tiny window keeps the picture at 1x")
  T.check(S.surface.h < S.game.h and S.surface.h > 0, "...and shrinks the touch screen rather than overlap")
  T.check(S.game.y + S.game.h <= S.surface.y, "...still no overlap")
  T.eq(Layout.dual(0, 100, {}), nil, "no window, no layout")

  -- fill (the overworld live on top, Kanto Gear style): the touch screen as wide as the window
  -- on the pad's room, the playfield everything above it
  local F = Layout.dual(540, 1200, { reserveBottom = 385, fill = true })
  T.eq(F.fill, true, "fill is reported")
  T.check(near(F.surface.w, 540 - 8), "fill: the touch screen spans the window, less its margins")
  T.check(near(F.surface.h, F.surface.w * 192 / 256), "...at 4:3")
  T.check(near(F.surface.y + F.surface.h, 1200 - 385 - 4), "...sitting on the pad's room")
  T.eq(F.game.x, 0, "the playfield starts at the left edge")
  T.eq(F.game.y, 0, "...and the top")
  T.eq(F.game.w, 540, "...full width")
  T.check(F.game.y + F.game.h <= F.surface.y, "...ending above the touch screen")
  T.check(F.game.h >= 160 * 2, "...tall enough for the 2x frame")
  T.eq(F.picture.w, 480, "the frame lands at 2x inside it")
  T.check(F.picture.y >= F.game.y and F.picture.y + F.picture.h <= F.game.y + F.game.h, "...centred within it")
  T.check(F.surface.w > L.surface.w * 540 / 1080 * 1.2 or F.surface.h > 320, "fill gives a bigger touch screen than the XL rule")
  -- a phone at 2.625 dpi: still on whole physical pixels
  local Fd = Layout.dual(412, 915, { dpi = 2.625, reserveBottom = 260, fill = true })
  T.check(near(Fd.picture.w * 2.625, math.floor(Fd.picture.w * 2.625 + 1e-6)), "fill at dpi 2.625: the frame is whole pixels")
  T.check(Fd.game.y + Fd.game.h <= Fd.surface.y and Fd.surface.y + Fd.surface.h <= 915 - 260, "...nothing overlaps, the pad keeps its room")
  -- landscape fill: the touch screen as before, the playfield the whole column left of it
  local Fl = Layout.dual(1200, 540, { fill = true })
  local Nl = Layout.dual(1200, 540, {})
  T.check(near(Fl.surface.x, Nl.surface.x) and near(Fl.surface.h, Nl.surface.h), "landscape fill keeps the touch screen")
  T.eq(Fl.game.h, 540, "...and the playfield is the full height")
  T.check(Fl.game.x + Fl.game.w <= Fl.surface.x, "...left of the touch screen")
  -- without fill the playfield is the picture itself
  T.eq(L.picture, L.game, "no fill: the playfield is the picture")
end

-- ------- margin placement (Gen 3)

do
  local r = Layout.inRect(0, 1200, 1080, 1200, { safeBottom = 40 })
  T.check(r ~= nil, "a tall bottom margin hosts the surface")
  T.check(r.y >= 1200 and r.y + r.h <= 2400 - 40, "it sits inside the margin above the safe area")
  T.eq(Layout.inRect(0, 0, 50, 20, {}), nil, "a sliver is refused")
end

-- ------- second-screen string parsing

do
  local a, x, y = Pointer.parse("move,120,80")
  T.eq(a, "move", "action parses")
  T.eq(x, 120, "x parses")
  T.eq(y, 80, "y parses")
  local a2, x2 = Pointer.parse(" DOWN , 3 , 4 ")
  T.eq(a2, "down", "whitespace and case are tolerated")
  T.eq(x2, 3, "...and the numbers still parse")
  T.eq(Pointer.parse("garbage"), nil, "a non-event string is nil")
  T.eq(Pointer.parse(nil), nil, "nil is nil")
end

-- ------- pointer records and gestures

do
  local seen = {}
  Pointer:on(function(ev, rec) seen[#seen + 1] = ev.phase end)
  local rec = Pointer:begin("f1", 10, 10, "touch", 0.5)
  T.eq(Pointer.count, 1, "one pointer down")
  T.eq(rec.pressure, 0.5, "pressure is kept")
  Pointer:move("f1", 20, 10)
  Pointer:move("f1", 40, 10)
  T.eq(rec.travel, 30, "travel sums the moves")
  T.eq(#rec.path, 3, "the path keeps every point")
  T.check(rec.vx >= 0, "velocity points along the drag")
  local rec2 = Pointer:begin("f2", 100, 100)
  Pointer:move("f2", 100, 90)
  T.eq(rec.x, 40, "a second pointer does not disturb the first")
  Pointer:finish("f2", 100, 90)
  T.eq(Pointer:get("f2"), nil, "a released pointer leaves no record")
  T.eq(Pointer.count, 1, "...and the count drops")
  T.eq(Pointer.isTap(rec), false, "a 30px drag is not a tap")
  Pointer:finish("f1", 40, 10)
  T.eq(seen[#seen], "released", "release is delivered to listeners")
  local tapRec = Pointer:begin("t", 5, 5)
  Pointer:move("t", 6, 5)
  Pointer:finish("t", 6, 5)
  T.eq(Pointer.isTap(tapRec), true, "a short, still press is a tap")
  Pointer:begin("c1", 0, 0)
  Pointer:begin("c2", 1, 1)
  Pointer:cancel()
  T.eq(Pointer:any(), false, "cancel with no id clears every pointer")
  T.eq(seen[#seen], "cancelled", "...delivering cancelled")
  local sw = Pointer:begin("s", 10, 50)
  Pointer:move("s", 60, 50)
  Pointer:move("s", 120, 52)
  local dir, dist = Pointer.swipe(sw, 24, 0)
  T.eq(dir, "right", "a long stroke to the right is a right swipe")
  T.check(dist > 100, "...with its distance")
  Pointer:finish("s")
end

T.finish("play_nav layout")
