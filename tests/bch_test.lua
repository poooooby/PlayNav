-- The BCH texture reader (src/import/bch.lua + bclim.lua's decodeRaw) against tools/bch.py on the
-- three effect textures the balloon's way out uses. Needs the reference dumps in the work tree
-- (oras-extract/bch_ref: <entry>.bch and <name>.rgba, written from tools/bch.py); skips without.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local home = os.getenv("USERPROFILE") or os.getenv("HOME") or "."
local ref = (os.getenv("ORAS_WORK") or (home .. "/Documents/oras-extract")) .. "/bch_ref/"
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
if not slurp(ref .. "240.bch") then
  print("bch_test: SKIP (no reference dumps)")
  return
end
local Bch = dofile("mods/play_nav/src/import/bch.lua")
local Bclim = dofile("mods/play_nav/src/import/bclim.lua")
T.eq(Bch.textures("nope"), nil, "not a BCH: nil")
for _, c in ipairs({ { 240, "etxm_streamline02f", 128, 512 }, { 240, "etxm_circle01m", 64, 64 }, { 155, "etxm_kumo01m", 128, 128 } }) do
  local blob = slurp(ref .. c[1] .. ".bch")
  local t = Bch.texture(blob, c[2])
  T.check(t ~= nil, c[2] .. ": found by name")
  if t then
    T.eq(t.w, c[3], c[2] .. ": width")
    T.eq(t.h, c[4], c[2] .. ": height")
    local img = Bclim.decodeRaw(t.format, t.w, t.h, blob:sub(t.data + 1), #blob - t.data)
    T.check(img and img.rgba == slurp(ref .. c[2] .. ".rgba"), c[2] .. ": pixels identical to tools/bch.py (" .. tostring(t.format) .. ")")
  end
end
T.finish()
