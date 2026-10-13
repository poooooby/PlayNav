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

T.finish("play_nav lytfile")
