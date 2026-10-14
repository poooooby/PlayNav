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

function M.texture(blob, name)
  local list, why = M.textures(blob)
  if not list then return nil, why end
  for _, t in ipairs(list) do
    if t.name == name then return t end
  end
  return nil, "no texture " .. tostring(name)
end

return M
