-- The BCH model reader (src/import/bch.lua M.model, 3D SUPER TRAINING's stadium) against its
-- twin tools/bch.py model(): the stadium's 12 meshes (mesh 2 with u16 indices the address bit does not flag) (a/1/1/4 entry 75) - counts, textures,
-- priorities and the sums of every position, UV, colour and index - and its serialized form
-- loading back. Needs the work tree's references (python tools/bch.py model <romfs>/a/1/1/4 75
-- <oras-extract>/bch_ref); skips without them.
-- Run from the engine root: luajit mods/play_nav/tests/bch_model_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local REF = (os.getenv("ORAS_EXTRACT") or (os.getenv("USERPROFILE") or "") .. "/Documents/oras-extract") .. "/bch_ref/"
local blob, refSrc = readFile(REF .. "e75.bch"), readFile(REF .. "e75_model.lua")
if not (blob and refSrc) then
  print("skip: no " .. REF .. "e75.bch / e75_model.lua (python tools/bch.py model ...)")
  T.finish("play_nav bch model")
  return
end
local Bch = assert(load(readFile("mods/play_nav/src/import/bch.lua"), "@bch.lua"))()
local ref = assert(load(refSrc, "=ref", "t", {}))()

local m, why = Bch.model(blob)
T.check(m ~= nil, "the stadium model reads (" .. tostring(why) .. ")")
if not m then T.finish("play_nav bch model") return end
T.eq(m.name, ref.name, "its name")
T.eq(#m.meshes, #ref.meshes, "its mesh count")
local verts, tris = 0, 0
for i, r in ipairs(ref.meshes) do
  local me = m.meshes[i]
  local nv, nt = #me.pos / 3, #me.idx / 3
  verts, tris = verts + nv, tris + nt
  local sx, sy, sz, su, sv, sc, si = 0, 0, 0, 0, 0, 0, 0
  for k = 1, #me.pos, 3 do sx, sy, sz = sx + me.pos[k], sy + me.pos[k + 1], sz + me.pos[k + 2] end
  for k = 1, #me.uv, 2 do su, sv = su + me.uv[k], sv + me.uv[k + 1] end
  for _, c in ipairs(me.col or {}) do sc = sc + c end
  for _, v in ipairs(me.idx) do si = si + v end
  -- (the reference's sums are printed to 4-5 decimals)
  local function near(a, b, eps) return math.abs(a - b) <= 1e-4 + eps * math.abs(b) end
  local ok = me.texture == r.texture and me.priority == r.priority and me.skin == r.skin and nv == r.verts and nt == r.tris
    and near(sx, r.sum[1], 1e-6) and near(sy, r.sum[2], 1e-6) and near(sz, r.sum[3], 1e-6)
    and near(su, r.sum[4], 1e-6) and near(sv, r.sum[5], 1e-6) and near(sc, r.sum[6], 1e-6) and si == r.idx
  if not ok and os.getenv("BCH_DEBUG") then
    print(i - 1, me.texture, r.texture, me.priority, r.priority, nv, r.verts, nt, r.tris, sx - r.sum[1], sy - r.sum[2], sz - r.sum[3], su - r.sum[4], sv - r.sum[5], sc - r.sum[6], si - r.idx)
  end
  T.check(ok, ("mesh %d (%s) as the Python twin reads it (%d verts, %d tris)"):format(i - 1, tostring(me.texture), nv, nt))
end
T.eq(verts, 2877, "2877 vertices in all (the far stand's 1516 with u16 indices)")
T.eq(tris, 2546, "2546 triangles in all")

-- serialized and loaded back in an empty environment, as the cache holds it
local src = Bch.serializeModel(m)
local back = assert(load(src, "=model", "t", {}))()
T.eq(#back.meshes, #m.meshes, "the serialized model loads back")
T.check(math.abs(back.meshes[3].pos[1] - m.meshes[3].pos[1]) < 1e-2 and #back.meshes[3].idx == #m.meshes[3].idx,
  "...with its positions and indices")
T.check(#src < 400000, ("...in %d KB"):format(math.floor(#src / 1024)))

T.finish("play_nav bch model")
