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

-- textures inside Game Freak's packages (Amie PLAY's scene): the stored GARC entry (LZ, a
-- package of packages), walked by Bch.descend as the extract job does
local Lz = dofile("mods/play_nav/src/import/lz.lua")
local function unlz(s)
  local f = s:byte(1)
  if f == 0x10 or f == 0x11 then return Lz.decode(s) or s end
  return s
end
T.eq(Bch.package("BCH\0...."), nil, "a BCH is not a package")
for _, c in ipairs({ { "a010_1.entry", "3", "kumo_yoko_a2", 256, 128 }, { "a064_0.entry", "26", "awa_spring01", 128, 64 } }) do
  local entry = slurp(ref .. c[1])
  if not entry then
    print("bch_test: SKIP nested " .. c[3] .. " (no reference dump)")
  else
    local blob, why = Bch.descend(entry, c[2], unlz)
    T.check(blob and blob:sub(1, 4) == "BCH\0", c[3] .. ": the walk reaches a BCH (" .. tostring(why) .. ")")
    local t = blob and Bch.texture(blob, c[3])
    T.check(t ~= nil and t.w == c[4] and t.h == c[5], c[3] .. ": found by name, " .. c[4] .. "x" .. c[5])
    if t then
      local img = Bclim.decodeRaw(t.format, t.w, t.h, blob:sub(t.data + 1), #blob - t.data)
      T.check(img and img.rgba == slurp(ref .. c[3] .. ".rgba"), c[3] .. ": pixels identical to tools/bch.py (" .. tostring(t.format) .. ")")
    end
    T.eq(Bch.descend(entry, "999", unlz), nil, c[3] .. ": a missing index is nil")
  end
end

-- a CGFX (Tile Puzzle's stage a/0/1/8 entry 4, LZ): the photo frame and the picture mask
do
  local entry = slurp(ref .. "a018_4.entry")
  if not entry then
    print("bch_test: SKIP cgfx (no reference dump)")
  else
    local blob = unlz(entry)
    T.check(blob:sub(1, 4) == "CGFX", "a/0/1/8 4 is a CGFX")
    local list = Bch.cgfxTextures(blob)
    T.eq(list and #list, 4, "...four image textures (the materials' references skipped)")
    for _, c in ipairs({ { "pzl_mask", 128, 128 }, { "pzl_pmask", 64, 64 } }) do
      local t = Bch.texture(blob, c[1])
      T.check(t ~= nil and t.w == c[2] and t.h == c[3], c[1] .. ": found by name, " .. c[2] .. "x" .. c[3])
      if t then
        local img = Bclim.decodeRaw(t.format, t.w, t.h, blob:sub(t.data + 1), #blob - t.data)
        T.check(img and img.rgba == slurp(ref .. c[1] .. ".rgba"), c[1] .. ": pixels identical to tools/bch.py (" .. tostring(t.format) .. ")")
      end
    end
    T.eq(Bch.cgfxTextures("BCH\0"), nil, "a BCH is not a CGFX")
  end
end
T.finish()
