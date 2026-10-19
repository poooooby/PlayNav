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
