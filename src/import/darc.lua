-- darc archives: the packs inside Alpha Sapphire's UI archive entries, holding a screen's
-- layouts (blyt/*.bclyt), animations (anim/*.bclan) and textures (timg/*.bclim). Pure Lua,
-- no requires: the extract job compiles it from source.
--
-- Darc.files(blob) -> { [name] = { start, stop } } (1-based, inclusive) for every file,
-- keyed by its bare name ("upper.bclyt"), plus an ordered list in `.order`; nil, why.

local Darc = {}

local function u16(s, p) return s:byte(p) + s:byte(p + 1) * 256 end
local function u32(s, p) return s:byte(p) + s:byte(p + 1) * 256 + s:byte(p + 2) * 65536 + s:byte(p + 3) * 16777216 end

-- the first darc in the blob (an archive entry may carry a small header before it)
function Darc.find(blob)
  local at = blob:find("darc", 1, true)
  return at
end

function Darc.files(blob, at)
  at = at or Darc.find(blob)
  if not at or blob:sub(at, at + 3) ~= "darc" then return nil, "no darc" end
  local base = at - 1                    -- 0-based offset of the darc
  local tableOff = u32(blob, at + 16)
  local t = base + tableOff + 1          -- 1-based start of the entry table
  local count = u32(blob, t + 8)         -- the root entry's size is the entry count
  local names = t + count * 12
  local out = { order = {} }
  for i = 0, count - 1 do
    local e = t + i * 12
    local nameWord = u32(blob, e)
    local isDir = math.floor(nameWord / 16777216) ~= 0
    local p = names + nameWord % 16777216
    local chars = {}
    while p + 1 <= #blob do
      local c = u16(blob, p)
      if c == 0 then break end
      chars[#chars + 1] = c < 128 and string.char(c) or "?"
      p = p + 2
    end
    local name = table.concat(chars)
    if not isDir and name ~= "" then
      local start = base + u32(blob, e + 4) + 1
      local size = u32(blob, e + 8)
      out[name] = { start = start, stop = start + size - 1 }
      out.order[#out.order + 1] = name
    end
  end
  return out
end

return Darc
