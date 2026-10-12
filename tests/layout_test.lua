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

-- ------- the Gen 3 stack: picture and surface never overlap, both scale with the window

do
  local L = Layout.stack(1080, 2400, { safeBottom = 48 })
  T.eq(L.orientation, "portrait", "a phone is portrait")
  T.eq(L.game.scale, 4, "a 1080-wide phone shows the picture at 4x")
  T.eq(L.game.w, 960, "...960 wide")
  T.eq(L.surface.scale, 4, "...and the surface at 4x")
  T.check(L.game.y + L.game.h <= L.surface.y, "the picture ends above the surface")
  T.check(L.surface.y + L.surface.h <= 2400 - 48, "the surface stays above the safe area")
  T.check(L.game.y > 0 and L.game.y < 600, "the pair is centred, not pinned to the top")
  local D = Layout.stack(432, 768, {})
  T.eq(D.game.scale, 1, "a 432x768 window shows the picture at 1x")
  T.eq(D.surface.scale, 1, "...and the surface at 1x")
  T.check(D.game.y + D.game.h < D.surface.y, "...stacked without overlap")
  T.check(D.game.y >= 4 and D.surface.y + D.surface.h <= 768, "...inside the window")
  local P = Layout.stack(720, 1280, {})
  T.eq(P.game.scale, 3, "720 wide gives a 3x picture")
  T.eq(P.surface.scale, 2, "...with a 2x surface under it")
  local S = Layout.stack(250, 420, {})
  T.eq(S.game.scale, 1, "a tiny window keeps the picture at 1x")
  T.check(S.surface.scale > 0 and S.surface.scale < 1, "...and shrinks the surface below 1x rather than overlapping")
  T.check(S.game.y + S.game.h <= S.surface.y, "...still no overlap")
  local W = Layout.stack(1280, 720, {})
  T.eq(W.orientation, "landscape", "a desktop window is landscape")
  T.eq(W.game.scale, 3, "720 tall gives a 3x picture (4x would leave no room for the surface)")
  T.check(W.game.x + W.game.w <= W.surface.x, "the surface sits right of the picture")
  T.check(W.surface.scale >= 1, "...at 1x or more")
  local Tall = Layout.stack(1440, 3200, { maxGameShare = 0.4 })
  T.check(Tall.game.h <= 3200 * 0.4 + 1, "the game share caps the picture height")
end

-- ------- sharing the room: balance modes and fixed scales

do
  local E = Layout.stack(1080, 2400, { balance = "equal" })
  T.eq(E.game.scale, 4, "EQUAL on a 1080x2400 phone: picture 4x")
  T.eq(E.surface.scale, 4, "...and surface 4x")
  local E2 = Layout.stack(720, 1280, { balance = "equal" })
  T.eq(E2.game.scale, 2, "EQUAL on 720x1280 drops both to 2x (3x + 3x would not fit)")
  T.eq(E2.surface.scale, 2, "...surface 2x")
  local G = Layout.stack(720, 1280, { balance = "game" })
  T.eq(G.game.scale, 3, "GAME on 720x1280 keeps the 3x picture")
  T.eq(G.surface.scale, 2, "...surface 2x in the rest")
  local Gd = Layout.stack(432, 768, { balance = "game" })
  T.eq(Gd.game.scale, 1, "GAME on the dev window: 1x picture (the width allows no more)")
  local Tc = Layout.stack(720, 1280, { balance = "touch" })
  T.eq(Tc.surface.scale, 2, "TOUCH on 720x1280: the surface at its largest, 2x")
  T.eq(Tc.game.scale, 3, "...and the picture still 3x since it fits")
  local Tl = Layout.stack(1280, 720, { balance = "touch" })
  T.eq(Tl.surface.scale, 3, "TOUCH on 1280x720: a 3x surface")
  T.eq(Tl.game.scale, 2, "...leaves a 2x picture")
  local D3 = Layout.stack(1080, 2400, { balance = "ds3" })
  T.eq(D3.game.scale, 4, "3DS on a 1080x2400 phone: picture 4x")
  T.eq(D3.surface.scale, 3, "...over a 3x surface")
  local D3f = Layout.stack(1080, 2400, { balance = "ds3_flip" })
  T.eq(D3f.game.scale, 3, "3DS flipped: picture 3x")
  T.eq(D3f.surface.scale, 4, "...under a 4x surface")
  local D3l = Layout.stack(1280, 720, { balance = "ds3" })
  T.eq(D3l.game.scale, 3, "3DS on 1280x720: picture 3x")
  T.eq(D3l.surface.scale, 2, "...beside a 2x surface")
  local D3lf = Layout.stack(1280, 720, { balance = "ds3_flip" })
  T.eq(D3lf.game.scale, 2, "3DS flipped on 1280x720: picture 2x")
  T.eq(D3lf.surface.scale, 3, "...beside a 3x surface")
  local D3s = Layout.stack(432, 768, { balance = "ds3" })
  T.eq(D3s.game.scale, 1, "3DS on the dev window falls back to 1x and 1x")
  T.eq(D3s.surface.scale, 1, "...since one step up does not fit")
  local F = Layout.stack(1080, 2400, { gameScale = 2 })
  T.eq(F.game.scale, 2, "a fixed GAME SCALE 2 is honoured")
  T.eq(F.surface.scale, 4, "...and the surface takes the largest that fits")
  local F2 = Layout.stack(1080, 2400, { gameScale = 2, surfaceScale = 3 })
  T.eq(F2.surface.scale, 3, "both fixed: surface 3x")
  local F3 = Layout.stack(1080, 2400, { gameScale = 9 })
  T.eq(F3.game.scale, 4, "a GAME SCALE too big for the window is clamped")
  local F4 = Layout.stack(1280, 720, { surfaceScale = 2 })
  T.eq(F4.surface.scale, 2, "a fixed TOUCH SCALE 2 is honoured")
  T.eq(F4.game.scale, 3, "...and the picture fills the rest at 3x")
  local F5 = Layout.stack(432, 768, { surfaceScale = 4 })
  T.eq(F5.surface.scale, 1, "a TOUCH SCALE too big is clamped to what fits beside a 1x picture")
  T.eq(F5.game.scale, 1, "...with the picture at 1x")
  for _, L in ipairs({ E, E2, G, Gd, Tc, Tl, D3, D3f, D3l, D3lf, D3s, F, F2, F3, F4, F5 }) do
    if L.orientation == "portrait" then
      T.check(L.game.y + L.game.h <= L.surface.y, "no overlap in portrait for " .. L.balance)
    else
      T.check(L.game.x + L.game.w <= L.surface.x, "no overlap in landscape for " .. L.balance)
    end
  end
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
