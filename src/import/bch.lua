-- The textures in a 3DS BCH model / effect file (version 0x21 in X / Y / OR / AS): found by
-- name, with their size, PICA format and where their data starts. Pure Lua, arithmetic only;
-- the extract job compiles it from source and decodes the pixels with bclim.lua's decodeRaw.
-- Twin of tools/bch.py.
--
-- M.textures(blob) -> { { name, w, h, format, data = 0-based offset }, ... } | nil, why
-- M.texture(blob, name) -> one of those | nil, why

local M = {}

local floor = math.floor

local function u32(s, p)
  local a, b, c, d = s:byte(p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- the PICA texture formats by number (texture unit register 0x8e), as bclim.lua names them
M.FORMATS = { [0] = "RGBA8", "RGB8", "RGBA5551", "RGB565", "RGBA4", "LA8", "HILO8", "L8", "A8", "LA4",
  "L4", "A4", "ETC1", "ETC1A4" }

local function cstring(s, p)
  local e = s:find("\0", p + 1, true)
  if not e then return nil end
  return s:sub(p + 1, e - 1)
end

-- a GPU command list -> { [register] = first value }
local function commands(s, at, words)
  local regs = {}
  local i, stop = at, at + words * 4
  while i + 8 <= stop do
    local param, hdr = u32(s, i), u32(s, i + 4)
    local reg = hdr % 65536
    local extra = floor(hdr / 1048576) % 2048
    local consec = hdr >= 2147483648
    local vals = { param }
    for k = 1, extra do vals[#vals + 1] = u32(s, i + 4 + 4 * k) end
    for k, v in ipairs(vals) do
      local r = reg + (consec and (k - 1) or 0)
      if regs[r] == nil then regs[r] = v end
    end
    i = i + 8 + 4 * extra
    if extra % 2 == 1 then i = i + 4 end
  end
  return regs
end

function M.textures(blob)
  if type(blob) ~= "string" or blob:sub(1, 4) ~= "BCH\0" then return nil, "not a BCH" end
  local main, strings, gpu, data = u32(blob, 8), u32(blob, 12), u32(blob, 16), u32(blob, 20)
  local tableOff, count = u32(blob, main + 0x24), u32(blob, main + 0x28)
  local out = {}
  for k = 0, count - 1 do
    local e = main + u32(blob, main + tableOff + k * 4)
    local regs = commands(blob, gpu + u32(blob, e), u32(blob, e + 4))
    local dim = regs[0x82] or 0
    out[#out + 1] = {
      name = cstring(blob, strings + u32(blob, e + 0x1c)),
      w = floor(dim / 65536), h = dim % 65536,
      format = M.FORMATS[regs[0x8e] or -1],
      data = data + (regs[0x85] or 0),
    }
  end
  return out
end

local function s32(s, p)
  local v = u32(s, p)
  return v >= 2147483648 and v - 4294967296 or v
end

-- The textures in a CGFX (NintendoWare's 3D scene format; Amie's Tile Puzzle stages, a/0/1/8
-- entries 3-8): every image texture object ("TXOB" with its pixels; the references a
-- material holds carry none) -> the same rows as M.textures. Fields after the magic: name
-- (self-relative), height, width at +20 / +24, the format at +48, the image at +52 (self-
-- relative) holding height, width, size, data (self-relative at +12). Twin of tools/bch.py.
function M.cgfxTextures(blob)
  if type(blob) ~= "string" or blob:sub(1, 4) ~= "CGFX" then return nil, "not a CGFX" end
  local out, seen = {}, {}
  local p = 1
  while true do
    local at = blob:find("TXOB", p, true)
    if not at then break end
    p = at + 4
    local o = at - 1
    if o + 68 <= #blob then
      local h, w = u32(blob, o + 20), u32(blob, o + 24)
      local fmt = M.FORMATS[u32(blob, o + 48)]
      local ip = o + 52 + s32(blob, o + 52)
      if fmt and w >= 8 and w <= 2048 and h >= 8 and h <= 2048 and ip > o and ip + 16 <= #blob
        and u32(blob, ip) == h and u32(blob, ip + 4) == w then
        local name = cstring(blob, o + 8 + s32(blob, o + 8))
        if name and not seen[name] then
          seen[name] = true
          out[#out + 1] = { name = name, w = w, h = h, format = fmt, data = ip + 12 + s32(blob, ip + 12) }
        end
      end
    end
  end
  return out
end

function M.texture(blob, name)
  local list, why
  if type(blob) == "string" and blob:sub(1, 4) == "CGFX" then list, why = M.cgfxTextures(blob)
  else list, why = M.textures(blob) end
  if not list then return nil, why end
  for _, t in ipairs(list) do
    if t.name == name then return t end
  end
  return nil, "no texture " .. tostring(name)
end

-- ------- models (3D SUPER TRAINING's stadium, a/1/1/4 entry 75): twin of tools/bch.py model()

-- a little-endian IEEE float32 at 0-based p
local function f32(s, p)
  local v = u32(s, p)
  if v == 0 or v == 2147483648 then return 0 end
  local sign = v >= 2147483648 and -1 or 1
  local e = floor(v / 8388608) % 256
  local m = v % 8388608
  if e == 0 then return sign * m * 2 ^ -149 end
  if e == 255 then return 0 end
  return sign * math.ldexp(1 + m / 8388608, e - 127)
end
local function u16(s, p)
  local a, b = s:byte(p + 1, p + 2)
  return a + b * 256
end
local function s16(s, p)
  local v = u16(s, p)
  return v >= 32768 and v - 65536 or v
end

-- a GPU command list -> { [register] = { every value written, in order } }
local function commandsAll(s, at, words)
  local regs = {}
  local i, stop = at, at + words * 4
  while i + 8 <= stop do
    local param, hdr = u32(s, i), u32(s, i + 4)
    local reg = hdr % 65536
    local extra = floor(hdr / 1048576) % 2048
    local consec = hdr >= 2147483648
    for k = 0, extra do
      local v = k == 0 and param or u32(s, i + 4 + 4 * k)
      local r = reg + (consec and k or 0)
      local list = regs[r]
      if not list then list = {}; regs[r] = list end
      list[#list + 1] = v
    end
    i = i + 8 + 4 * extra
    if extra % 2 == 1 then i = i + 4 end
  end
  return regs
end
local function first(regs, r) local l = regs[r]; return l and l[1] or 0 end

-- the vertex shader inputs' meanings by input register (what 0x2bb / 0x2bc map each loaded
-- attribute to), and the attribute types (s8, u8, s16, f32)
local ATTR_NAMES = { [0] = "pos", "normal", "tangent", "color", "uv0", "uv1", "uv2", "bone", "weight" }
local ATTR_SIZE = { [0] = 1, 1, 2, 4 }

-- the inverse of an affine 3x4 (rows { a, b, c, t })
local function invert34(m)
  local a, b, c, tx = m[1][1], m[1][2], m[1][3], m[1][4]
  local d, e, f, ty = m[2][1], m[2][2], m[2][3], m[2][4]
  local g, h, i, tz = m[3][1], m[3][2], m[3][3], m[3][4]
  local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
  if math.abs(det) < 1e-12 then return { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 } } end
  local inv = {
    { (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det },
    { (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det },
    { (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det },
  }
  local out = {}
  for r = 1, 3 do
    local row = inv[r]
    out[r] = { row[1], row[2], row[3], -(row[1] * tx + row[2] * ty + row[3] * tz) }
  end
  return out
end

-- one attribute value: n components of type t (0 s8, 1 u8, 2 s16, 3 f32) at 0-based p
local function readAttr(s, p, t, n, out)
  local size = ATTR_SIZE[t]
  for k = 0, n - 1 do
    local q = p + k * size
    local v
    if t == 3 then v = f32(s, q)
    elseif t == 2 then v = s16(s, q)
    elseif t == 1 then v = s:byte(q + 1)
    else v = s:byte(q + 1); if v >= 128 then v = v - 256 end end
    out[k + 1] = v
  end
  return out
end

-- A model's meshes in model space: per mesh its material's texture, render priority,
-- positions (moved by the bone's bind pose), UVs, vertex colours (0..1, or nil) and triangle
-- indices (0-based). Offsets as tools/bch.py model() documents (BCH 0x21, SPICA's H3D).
-- -> { name, meshes = { { texture, priority, pos = { x, y, z, ... }, uv = { u, v, ... },
--      col = { r, g, b, a, ... } | nil, idx = { ... } } } } | nil, why
function M.model(blob, index)
  if type(blob) ~= "string" or blob:sub(1, 4) ~= "BCH\0" then return nil, "not a BCH" end
  local main, strings, gpu, data = u32(blob, 8), u32(blob, 12), u32(blob, 16), u32(blob, 20)
  local function name(off) return cstring(blob, strings + off) end
  local mdl = main + u32(blob, main + u32(blob, main) + 4 * (index or 0))
  local out = { name = name(u32(blob, mdl + 0x84)), meshes = {} }
  local matTab, matN = u32(blob, mdl + 0x34), u32(blob, mdl + 0x38)
  local texOf = {}
  for k = 0, matN - 1 do texOf[k] = name(u32(blob, main + matTab + k * 0x2c + 0x1c)) end
  local boneTab, boneN = u32(blob, mdl + 0x70), u32(blob, mdl + 0x74)
  local worlds = {}
  for k = 0, boneN - 1 do
    local e = main + boneTab + k * 0x64
    local inv = {}
    for r = 0, 2 do
      inv[r + 1] = {}
      for c = 0, 3 do inv[r + 1][c + 1] = f32(blob, e + 0x2c + 4 * (r * 4 + c)) end
    end
    worlds[k] = invert34(inv)
  end
  local meshTab, meshN = u32(blob, mdl + 0x40), u32(blob, mdl + 0x44)
  local vals = {}
  -- every mesh's vertex buffer start (data-relative) and the first index buffer's: a buffer runs
  -- to the next start, so a mesh's vertex count is its span over its stride - more than 256
  -- vertices take u16 indices, whether or not 0x227's bit 31 says so (the stadium's
  -- spa_stadium00 mesh: 1516 vertices, u16, the bit clear)
  local bounds = {}
  do
    local seen, firstIb = {}, nil
    for k = 0, meshN - 1 do
      local e = main + meshTab + k * 0x38
      local r = commandsAll(blob, gpu + u32(blob, e + 8), u32(blob, e + 0xc))
      local vb = first(r, 0x203)
      if not seen[vb] then seen[vb] = true; bounds[#bounds + 1] = vb end
      local subTab, subN = u32(blob, e + 0x10), u32(blob, e + 0x14)
      for sIdx = 0, subN - 1 do
        local se = main + subTab + sIdx * 0x34
        local sr = commandsAll(blob, gpu + u32(blob, se + 0x2c), u32(blob, se + 0x30))
        for _, a in ipairs(sr[0x227] or {}) do
          a = a % 2147483648
          if not firstIb or a < firstIb then firstIb = a end
        end
      end
    end
    if firstIb and not seen[firstIb] then bounds[#bounds + 1] = firstIb end
    table.sort(bounds)
  end
  local function spanEnd(start)
    for _, x in ipairs(bounds) do if x > start then return x end end
    return #blob - data
  end
  for k = 0, meshN - 1 do
    local e = main + meshTab + k * 0x38
    local mat, prio = u16(blob, e), u16(blob, e + 6)
    local regs = commandsAll(blob, gpu + u32(blob, e + 8), u32(blob, e + 0xc))
    local fmtLo, r202 = first(regs, 0x201), first(regs, 0x202)
    local types, counts = {}, {}
    for a = 0, 11 do
      local nib
      if a < 8 then nib = floor(fmtLo / 16 ^ a) % 16 else nib = floor(r202 / 16 ^ (a - 8)) % 16 end
      types[a], counts[a] = nib % 4, floor(nib / 4) + 1
    end
    local permLo, permHi = first(regs, 0x2bb), first(regs, 0x2bc)
    local meaning = {}
    for a = 0, 11 do
      local v = a < 8 and floor(permLo / 16 ^ a) % 16 or floor(permHi / 16 ^ (a - 8)) % 16
      meaning[a] = ATTR_NAMES[v] or "user"
    end
    local boff = first(regs, 0x203)
    local orderLo, r205 = first(regs, 0x204), first(regs, 0x205)
    local stride, count = floor(r205 / 65536) % 256, floor(r205 / 268435456)
    local layout, at = {}, 0
    for slot = 0, count - 1 do
      local a = slot < 8 and floor(orderLo / 16 ^ slot) % 16 or floor((r205 % 65536) / 16 ^ (slot - 8)) % 16
      if a >= 12 then
        at = at + 4 * (a - 11)
      else
        local t, n = types[a], counts[a]
        local size = ATTR_SIZE[t]
        at = floor((at + size - 1) / size) * size
        layout[#layout + 1] = { meaning[a], t, n, at }
        at = at + size * n
      end
    end
    -- the sub meshes: their bone lists and index buffers (0x227 address, bit 31 = u16; 0x228 count)
    local subTab, subN = u32(blob, e + 0x10), u32(blob, e + 0x14)
    local idx, vbone, nverts, skin = {}, {}, 0, 0
    local vcount = stride > 0 and floor((spanEnd(boff) - boff) / stride) or 0
    for sIdx = 0, subN - 1 do
      local se = main + subTab + sIdx * 0x34
      -- skinning: 0 none, 1 rigid (vertices in their bone's space), 2 smooth (model space)
      skin = math.max(skin, blob:byte(se + 1))
      local nb = u16(blob, se + 2)
      local bones = {}
      for i = 0, math.min(nb, 20) - 1 do bones[i] = u16(blob, se + 4 + 2 * i) end
      local sregs = commandsAll(blob, gpu + u32(blob, se + 0x2c), u32(blob, se + 0x30))
      local addrs, cnts = sregs[0x227] or {}, sregs[0x228] or {}
      for d = 1, math.min(#addrs, #cnts) do
        local wide = addrs[d] >= 2147483648 or vcount > 256
        local base = data + addrs[d] % 2147483648
        for i = 0, cnts[d] - 1 do
          local v = wide and u16(blob, base + 2 * i) or blob:byte(base + i + 1)
          idx[#idx + 1] = v
          if v + 1 > nverts then nverts = v + 1 end
          if vbone[v] == nil then vbone[v] = bones end
        end
      end
    end
    local pos, uv, col = {}, {}, nil
    for v = 0, nverts - 1 do
      local x, y, z, u, w = 0, 0, 0, 0, 0
      local cr, cg, cb, ca, bi = nil, nil, nil, nil, 0
      for _, L in ipairs(layout) do
        local p = data + boff + v * stride + L[4]
        readAttr(blob, p, L[2], L[3], vals)
        if L[1] == "pos" then x, y, z = vals[1], vals[2], vals[3]
        elseif L[1] == "uv0" then u, w = vals[1], vals[2]
        elseif L[1] == "color" and L[2] == 1 then cr, cg, cb, ca = vals[1] / 255, vals[2] / 255, vals[3] / 255, (vals[4] or 255) / 255
        elseif L[1] == "bone" then bi = vals[1] end
      end
      local bl = vbone[v] or { [0] = 0 }
      local bone = bl[bi] or bl[0] or 0
      local W = skin == 1 and worlds[bone] or nil
      if W then
        x, y, z = W[1][1] * x + W[1][2] * y + W[1][3] * z + W[1][4],
          W[2][1] * x + W[2][2] * y + W[2][3] * z + W[2][4],
          W[3][1] * x + W[3][2] * y + W[3][3] * z + W[3][4]
      end
      local n = #pos
      pos[n + 1], pos[n + 2], pos[n + 3] = x, y, z
      uv[#uv + 1], uv[#uv + 2] = u, w
      if cr then
        col = col or {}
        local c = #col
        col[c + 1], col[c + 2], col[c + 3], col[c + 4] = cr, cg, cb, ca
      end
    end
    out.meshes[#out.meshes + 1] = { texture = texOf[mat], priority = prio, skin = skin, pos = pos, uv = uv, col = col, idx = idx }
  end
  return out
end

-- ------- CGFX models (NintendoWare: Amie PLAY's stage, a/1/0/1 entry 0): twin of tools/cgfx.py

-- a CGFX dictionary ("DICT") at 0-based p -> { { name, at }, ... } (at: the entry's object)
local function cgfxDict(s, p)
  if s:sub(p + 1, p + 4) ~= "DICT" then return {} end
  local out = {}
  for i = 0, u32(s, p + 8) - 1 do
    local e = p + 0x1c + i * 16
    out[#out + 1] = { name = cstring(s, e + 8 + s32(s, e + 8)), at = e + 12 + s32(s, e + 12) }
  end
  return out
end
-- a count at p and a self-relative pointer to a table of self-relative pointers at p + 4
local function cgfxList(s, p)
  local n = u32(s, p)
  if n == 0 then return {} end
  local t = p + 4 + s32(s, p + 4)
  local out = {}
  for i = 0, n - 1 do out[i + 1] = t + 4 * i + s32(s, t + 4 * i) end
  return out
end
-- the DATA block's dictionaries by kind (0 models, 1 textures, ...) -> dictionary
local function cgfxData(s, kind)
  local d = u16(s, 6)
  if s:sub(d + 1, d + 4) ~= "DATA" then return {} end
  if u32(s, d + 8 + 8 * kind) == 0 then return {} end
  local q = d + 12 + 8 * kind
  return cgfxDict(s, q + s32(s, q))
end

local GL_TYPE = { [0x1400] = 0, [0x1401] = 1, [0x1402] = 2, [0x1406] = 3 }
local CGFX_USAGE = { [0] = "pos", "normal", "tangent", "color", "uv0" }

-- A CGFX file's first model, its meshes unskinned in model space: per mesh its name, its
-- material's texture, the material's render layer (+0x20: 0 opaque, 1 translucent, 2
-- subtractive, 3 additive) as `priority`, positions (+ the shape's offset), UVs, vertex
-- colours (0..1, or nil) and triangle indices (0-based) - the same tables as M.model's.
-- A mesh is named after its material. Offsets (from each object's start): model meshes +0xB4, materials +0xBC (dict), shapes
-- +0xC4; a mesh's shape +0x18, material +0x1C; a shape's position offset +0x20, sub-meshes
-- +0x2C, vertex buffers +0x38; an interleaved buffer (type 0x40000002) its length +0x14, data
-- +0x18, stride +0x24, attributes +0x28 (usage +4, GL type +0x24, elements +0x28, scale
-- +0x2C, offset +0x30); a sub-mesh's faces +0xC, a face's descriptors +0 (format +0, size +8,
-- data +0xC; 0x1403 u16 indices, else u8). A material's texture is the name its texture
-- reference points to (a self-relative pointer in its first 0x800 bytes naming a texture).
function M.cgfxModel(blob)
  if type(blob) ~= "string" or blob:sub(1, 4) ~= "CGFX" then return nil, "not a CGFX" end
  local s = blob
  local models = cgfxData(s, 0)
  if #models == 0 then return nil, "no model" end
  local cm = models[1].at
  local texNames = {}
  for _, t in ipairs(cgfxData(s, 1)) do texNames[t.name] = true end
  local mats = {}
  if u32(s, cm + 0xbc) > 0 then mats = cgfxDict(s, cm + 0xc0 + s32(s, cm + 0xc0)) end
  local matTex, matLayer = {}, {}
  for i, m in ipairs(mats) do
    matLayer[i - 1] = u32(s, m.at + 0x20)
    for p = m.at, math.min(m.at + 0x800, #s - 4) - 1, 4 do
      local t = p + s32(s, p)
      if t >= 0 and t < #s then
        local name = cstring(s, t)
        if name and texNames[name] then matTex[i - 1] = name; break end
      end
    end
  end
  local shapes = cgfxList(s, cm + 0xc4)
  local out = { name = models[1].name, meshes = {} }
  local vals = {}
  for _, me in ipairs(cgfxList(s, cm + 0xb4)) do
    local sh = shapes[u32(s, me + 0x18) + 1]
    local mi = u32(s, me + 0x1c)
    -- (meshes carry no names of their own: the material's)
    local name = mats[mi + 1] and mats[mi + 1].name or nil
    local ox, oy, oz = f32(s, sh + 0x20), f32(s, sh + 0x24), f32(s, sh + 0x28)
    local pos, uv, col = {}, {}, nil
    for _, vb in ipairs(cgfxList(s, sh + 0x38)) do
      if u32(s, vb) == 0x40000002 then
        local length, raw, stride = u32(s, vb + 0x14), vb + 0x18 + s32(s, vb + 0x18), u32(s, vb + 0x24)
        local attrs = {}
        for _, a in ipairs(cgfxList(s, vb + 0x28)) do
          attrs[#attrs + 1] = { use = CGFX_USAGE[u32(s, a + 4)], t = GL_TYPE[u32(s, a + 0x24)] or 1,
            n = u32(s, a + 0x28), scale = f32(s, a + 0x2c), off = u32(s, a + 0x30) }
        end
        for v = 0, floor(length / stride) - 1 do
          local x, y, z, u, w = 0, 0, 0, 0, 0
          local cr
          local cg, cb, ca
          for _, A in ipairs(attrs) do
            if A.use then
              readAttr(s, raw + v * stride + A.off, A.t, A.n, vals)
              local k = A.scale
              if A.use == "pos" then x, y, z = vals[1] * k, vals[2] * k, vals[3] * k
              elseif A.use == "uv0" then u, w = vals[1] * k, vals[2] * k
              elseif A.use == "color" then
                cr, cg, cb, ca = vals[1] * k, vals[2] * k, vals[3] * k, A.n >= 4 and vals[4] * k or 1
              end
            end
          end
          local n = #pos
          pos[n + 1], pos[n + 2], pos[n + 3] = x + ox, y + oy, z + oz
          uv[#uv + 1], uv[#uv + 2] = u, w
          if cr then
            col = col or {}
            local c = #col
            col[c + 1], col[c + 2], col[c + 3], col[c + 4] = cr, cg, cb, ca
          end
        end
      end
    end
    local idx = {}
    for _, sm in ipairs(cgfxList(s, sh + 0x2c)) do
      for _, face in ipairs(cgfxList(s, sm + 0xc)) do
        for _, fd in ipairs(cgfxList(s, face)) do
          local wide = u32(s, fd) == 0x1403
          local size, raw = u32(s, fd + 8), fd + 0xc + s32(s, fd + 0xc)
          if wide then
            for i = 0, floor(size / 2) - 1 do idx[#idx + 1] = u16(s, raw + 2 * i) end
          else
            for i = 0, size - 1 do idx[#idx + 1] = s:byte(raw + i + 1) end
          end
        end
      end
    end
    out.meshes[#out.meshes + 1] = { name = name, texture = matTex[mi], priority = matLayer[mi] or 0, skin = 0,
      pos = pos, uv = uv, col = col, idx = idx }
  end
  return out
end

-- the model as Lua source (a table constructor the main thread loads in an empty environment)
function M.serializeModel(m)
  local parts = { "return { name = ", ("%q"):format(m.name or ""), ", meshes = {\n" }
  local function list(t, fmt)
    local s = {}
    for i = 1, #t do s[i] = (fmt):format(t[i]) end
    return "{" .. table.concat(s, ",") .. "}"
  end
  for _, me in ipairs(m.meshes) do
    parts[#parts + 1] = ("{ texture = %q, priority = %d, skin = %d,\n pos = %s,\n uv = %s,\n idx = %s"):format(
      me.texture or "", me.priority or 0, me.skin or 0, list(me.pos, "%.3f"), list(me.uv, "%.5f"), list(me.idx, "%d"))
    if me.name then parts[#parts + 1] = (",\n name = %q"):format(me.name) end
    if me.col then parts[#parts + 1] = (",\n col = %s"):format(list(me.col, "%.3f")) end
    parts[#parts + 1] = " },\n"
  end
  parts[#parts + 1] = "} }\n"
  return table.concat(parts)
end

-- Game Freak's package (X / Y / OR / AS: 'PC' Pokemon, 'GR' field, 'MM', 'AD' ...): a
-- two-letter tag, a u16 count, then count + 1 u32 offsets (the last is the end) -> the
-- files as strings, or nil when s is not one. Twin of tools/bch.py's package().
function M.package(s)
  if type(s) ~= "string" or #s < 8 then return nil end
  local a, b = s:byte(1, 2)
  if not (a >= 65 and a <= 90 and b >= 65 and b <= 90) then return nil end
  local n = s:byte(3) + s:byte(4) * 256
  if n == 0 or n > 4096 or 4 + 4 * (n + 1) > #s then return nil end
  local offs = {}
  for i = 0, n do offs[i] = u32(s, 4 + 4 * i) end
  if offs[0] < 4 + 4 * (n + 1) or offs[n] > #s then return nil end
  local files = {}
  for i = 0, n - 1 do
    if offs[i] > offs[i + 1] then return nil end
    files[i] = s:sub(offs[i] + 1, offs[i + 1])
  end
  return files
end

-- The file at `path` ("26", "0/11": package indexes, 0-based, as tools/bch.py find prints
-- them after the GARC sub entry) inside blob, opening an LZ wrapper at every level with unlz
-- (string -> string). -> the inner blob | nil, why
function M.descend(blob, path, unlz)
  unlz = unlz or function(s) return s end
  for idx in tostring(path or ""):gmatch("%d+") do
    blob = unlz(blob)
    local files = M.package(blob)
    if not files then return nil, "not a package before " .. idx end
    blob = files[tonumber(idx)]
    if not blob then return nil, "no file " .. idx end
  end
  return unlz(blob)
end

return M
