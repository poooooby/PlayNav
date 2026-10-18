-- The layout reader (src/lytfile.lua) and player (src/lytplayer.lua) against the regimen's
-- screens the extract copied into this machine's cache; skips cleanly without them (CI never
-- has game files). Run from the engine root:
--   luajit mods/play_nav/tests/lytfile_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local function loadFile(path)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end

local F = loadFile("mods/play_nav/src/lytfile.lua")
local Player = loadFile("mods/play_nav/src/lytplayer.lua")
Player.setFiles(F)

-- the float reader on known bit patterns
T.eq(F.f32(string.char(0, 0, 128, 63), 1), 1, "1.0")
T.eq(F.f32(string.char(0, 0, 200, 195), 1), -400, "-400.0")
T.eq(F.f32(string.char(0, 0, 0, 0), 1), 0, "0.0")
T.eq(F.eval({ keys = { { 0, 0, 0 }, { 10, 10, 0 } } }, 5), 5, "hermite with flat slopes halfway")
T.eq(F.eval({ keys = { { 0, 1 }, { 4, 0 } }, step = true }, 3), 1, "a step key holds")
T.eq(F.eval({ keys = { { 0, 0, 0 }, { 6, 255, 0 }, { 6, 0, 0 } } }, 7), 0, "two keys on a frame jump")

-- window frames (NW4C): the header af is four 140x18 quarters of one texture, the right ones
-- mirrored by their material (srt -1); the drawer j has 32x36 corners, bands between them
-- and 32-wide sides
do
  local R, inner = Player.windowRects(280, 36, 4, { { 140, 18 }, { 140, 18 }, { 140, 18 }, { 140, 18 } })
  T.check(R[1].w == 140 and R[1].h == 18 and R[2].x == 140 and R[2].h == 18 and R[4].x == 140 and R[4].y == 18,
    "a 280x36 four-frame window is four 140x18 quarters")
  local uv = Player.frameUV(R[2], 140, 18, -1, 1)
  T.check(uv[1] == 1 and uv[3] == 0, "the right quarter's texture is mirrored (u 1 -> 0)")
  local uvL = Player.frameUV(R[1], 140, 18, 1, 1)
  T.check(uvL[1] == 0 and uvL[3] == 1, "...the left one is not")
  local J, jin = Player.windowRects(320, 202, 8, { { 32, 36 }, { 32, 36 }, { 32, 36 }, { 32, 36 }, { 2, 2 }, { 2, 2 }, { 32, 36 }, { 32, 36 } })
  T.check(J[7].x == 32 and J[7].w == 256 and J[7].h == 36, "the top band runs between the corners, 36 tall")
  T.check(J[8].y == 166 and J[8].h == 36, "...the bottom band along the foot")
  T.check(J[5].w == 32 and J[5].y == 36 and J[5].h == 130 and J[6].x == 288, "the sides are 32 wide between the bands")
  T.check(jin.x == 32 and jin.y == 36 and jin.w == 256 and jin.h == 130, "the content fills the middle")
  local tile = Player.frameUV(J[7], 32, 36, 1, 1)
  T.eq(tile[3], 8, "a band tiles its texture (256 across a 32-wide texture: u to 8)")
  -- a pinwheel's long corner keeps the texture at its own size at the outer end
  local P4 = Player.windowRects(230, 50, 4, { { 16, 24 }, { 16, 24 }, { 16, 24 }, { 16, 24 } })
  local uvRB = Player.frameUV(P4[4], 16, 24, 1, -1)
  T.check(P4[4].w == 214 and uvRB[3] == 1 and uvRB[1] < 0, "a stretched corner is anchored at its outer edge")
end

local dir = os.getenv("PLAYNAV_CACHE") or "mod_cache/play_nav/oras/lyt/"
local function read(p)
  local f = io.open(dir .. p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local upper = read("st_hud/upper.bclyt")
if not upper then
  print("SKIP lytfile_test (files): no extracted layouts at " .. dir)
  T.finish("play_nav lytfile")
  return
end

local L = assert(F.layout(upper))
T.eq(L.W, 400, "upper is 400 wide")
T.eq(L.H, 240, "and 240 tall")
T.check(L.byName["4y"] and L.byName["4y"].kind == "txt", "the balloon's name is a text pane")
T.eq(L.byName["4y"].textPos, 3, "left and middle")
T.check(L.groups.da and L.groups.da[1] == "7d", "group da is the Start banner")
local m = L.materials[L.byName["5a"].mat]
T.eq(L.textures[m.maps[1].tex], "bg_00.bclim", "the frame corner's texture")

local start = assert(F.clip(read("st_hud/upper_game_start.bclan")))
T.eq(start.frames, 41, "game_start runs 41 frames")
T.check(start.bind and start.groups[1] == "da", "it drives group da and its children")
T.eq(F.eval(start.panes["7b"].alpha, 20), 255, "Start is up at frame 20")
T.eq(F.eval(start.panes["7b"].alpha, 40), 0, "and gone at 40")

local P = Player.new(L, { clip = function(n) local b = read("st_hud/upper_" .. n .. ".bclan"); return b and F.clip(b) end })
T.check(P:play("gauge_l_0_in"), "the caption strip's clip plays")
P:advance(20)
local x, y, w = P:box("4i")
T.check(math.abs(x) < 1 and math.abs(y) < 1 and math.abs(w - 266) < 1, ("the strip sits at the top left (%.1f, %.1f, %.1f)"):format(x, y, w))
P.stretchY = (160 / 0.6) / 240
local _, ys = P:box("4i")
T.check(ys >= -0.5 and ys < 4, ("stretched to 160 it stays on screen (y %.1f)"):format(ys))
local _, yb, _, hb = P:box("5a")
-- (in the game's own layout the frame hangs 10 past the foot; stretched, about the same)
local foot = 240 * P.stretchY
T.check(yb + hb >= foot and yb + hb <= foot + 12, ("the bottom frame reaches the foot (%.1f of %.1f)"):format(yb + hb, foot))

local lower = read("st_aim/lower.bclyt")
local A = lower and F.layout(lower)
T.check(A and A.W == 320, "the aim screen is 320 wide")
if A then
  local mat = A.materials[A.byName["10"].mat]
  T.eq(mat.white[3], 121, "the field's material carries its white colour (0, 86, 121)")
  T.eq(mat.srt[1][4], 12, "and tiles the + twelve across")
end

local rl = read("st_menu/result_lower.bclyt")
local R = rl and F.layout(rl)
T.check(R and R.byName["4r"] and #R.byName["4r"].frames == 4, "the time window has four corner frames")

-- Pokemon-Amie's DECORATE (a/1/4/4) and room (a/0/2/6): the panes src/amie/decorate.lua and
-- home.lua drive, where the game has them (recipe version 26; skipped on an older cache)
local cz = read("amie_deco/customize.bclyt")
if cz then
  local Cz = assert(F.layout(cz))
  T.eq(Cz.W, 320, "customize is the 320x240 lower screen")
  local function centre(Lx, name)
    local p = Player.new(Lx, {})
    local x, y, w, h = p:box(name)
    return x + w / 2, y + h / 2
  end
  local sx, sy = centre(Cz, "6v")
  T.check(math.abs(sx - 195) < 0.5 and math.abs(sy - 119) < 0.5, ("seat 6v at (195, 119): %.1f, %.1f"):format(sx, sy))
  local px, py = centre(Cz, "ad")
  T.check(math.abs(px - 160) < 0.5 and math.abs(py - 116) < 0.5, ("the puff's spot ad at (160, 116): %.1f, %.1f"):format(px, py))
  local up = assert(F.clip(read("amie_deco/customize_goodsFolder_up.bclan")))
  T.eq(F.eval(up.panes.v.ty, 5), 157, "goodsFolder_up lifts the drawer 157")
  local Cp = Player.new(Cz, { clip = function(n) local b = read("amie_deco/customize_" .. n .. ".bclan"); return b and F.clip(b) end })
  Cp:play("bg_move_left")
  Cp:advance(8)
  T.check(math.abs((Cp:box("72")) + 320) < 0.5, "bg_move_left slides the wallpaper a screen to the left")
  -- a clip the game made on one sample pane, played on another (Berry Picker's pick-up pop)
  local nb = read("berry_nuts/nuts.bclyt")
  if nb then
    local Np = Player.new(assert(F.layout(nb)), { clip = function(n) local b = read("berry_nuts/nuts_" .. n .. ".bclan"); return b and F.clip(b) end })
    local _, _, w0 = Np:box("5")
    Np:play("kinomi_catch", { as = "5" })
    Np:advance(2)
    local _, _, w1 = Np:box("5")
    local _, _, w3 = Np:box("3")
    T.check(w1 > w0 * 1.15, ("kinomi_catch played on berry 5 grows it (%.1f -> %.1f)"):format(w0, w1))
    T.check(math.abs(w3 - 32) < 0.5, "...not its sample pane 3")
  end
  local kl = read("amie_room/kawaii_lower.bclyt")
  local K = kl and F.layout(kl)
  T.check(K and K.byName["1t"] and K.byName["5z"], "kawaii_lower has the puff (1t) and the frame (5z)")
  local fall = assert(F.clip(read("amie_room/kawaii_lower_okashi_fall.bclan")))
  T.eq(fall.frames, 11, "okashi_fall runs 11 frames")
  T.eq(F.eval(fall.panes["1t"].ty, 10), 24, "...and lands the puff on its spot (24 above the middle)")
else
  print("SKIP lytfile_test (Amie): no amie_deco layouts at " .. dir)
end

T.finish("play_nav lytfile")
