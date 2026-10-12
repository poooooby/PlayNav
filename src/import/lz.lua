-- Nintendo LZ10 / LZ11 decompression, pure Lua (no bit library, no FFI), the
-- algorithm of src/import/gen5/Lz.lua in the engine and tools/garc_dump.py.
--
-- Written as a self-contained chunk so main.lua can either load it as a
-- sibling or splice its source into a mod.job worker script (jobs cannot
-- require).

local M = {}

M.MAX_BYTES = 8 * 1024 * 1024

-- Returns decompressed, true on success. Input that is not a valid LZ10/LZ11
-- stream (no 0x10/0x11 lead byte, zero size, or a stream that does not
-- decode cleanly) is returned unchanged with false and a reason, the same
-- rule tools/garc_dump.py applies: GARC entries whose first bytes merely
-- look like a header are raw files.
function M.decode(data, limit)
  local out, ok, why = M.try(data, limit)
  if ok then return out, true end
  return data, false, why
end

function M.try(data, limit)
  limit = limit or M.MAX_BYTES
  if type(data) ~= "string" or #data < 4 then return nil, false, "no header" end
  local kind = data:byte(1)
  if kind ~= 0x10 and kind ~= 0x11 then return nil, false, "not lz" end
  local b1, b2, b3 = data:byte(2, 4)
  local size = b1 + b2 * 256 + b3 * 65536
  local pos = 5
  if size == 0 and kind == 0x11 then
    if #data < 8 then return nil, false, "truncated extended size" end
    local c1, c2, c3, c4 = data:byte(5, 8)
    size = c1 + c2 * 256 + c3 * 65536 + c4 * 16777216
    pos = 9
  end
  if size <= 0 then return nil, false, "zero size" end
  if size > limit then return nil, false, ("decompressed size %d exceeds %d"):format(size, limit) end

  local out = {}          -- one byte string per slot
  local n = 0             -- bytes produced
  local len = #data
  local byte = string.byte
  while n < size do
    if pos > len then return nil, false, "truncated stream" end
    local flags = byte(data, pos)
    pos = pos + 1
    local mask = 128
    for _ = 1, 8 do
      if n >= size then break end
      if flags >= mask then
        flags = flags - mask
        if pos > len then return nil, false, "truncated match" end
        local b = byte(data, pos)
        pos = pos + 1
        local count, disp
        if kind == 0x10 then
          local x = byte(data, pos); pos = pos + 1
          if not x then return nil, false, "truncated match" end
          count = math.floor(b / 16) + 3
          disp = (b % 16) * 256 + x + 1
        else
          local indicator = math.floor(b / 16)
          if indicator == 0 then
            local x, y = byte(data, pos, pos + 1); pos = pos + 2
            if not y then return nil, false, "truncated match" end
            count = (b % 16) * 16 + math.floor(x / 16) + 0x11
            disp = (x % 16) * 256 + y + 1
          elseif indicator == 1 then
            local x, y, z = byte(data, pos, pos + 2); pos = pos + 3
            if not z then return nil, false, "truncated match" end
            count = (b % 16) * 4096 + x * 16 + math.floor(y / 16) + 0x111
            disp = (y % 16) * 256 + z + 1
          else
            local x = byte(data, pos); pos = pos + 1
            if not x then return nil, false, "truncated match" end
            count = indicator + 1
            disp = (b % 16) * 256 + x + 1
          end
        end
        if disp > n then return nil, false, "displacement before start" end
        local from = n - disp
        for i = 1, count do
          if n >= size then break end
          n = n + 1
          out[n] = out[from + i]
        end
      else
        if pos > len then return nil, false, "truncated literal" end
        n = n + 1
        out[n] = string.char(byte(data, pos))
        pos = pos + 1
      end
      mask = math.floor(mask / 2)
    end
  end
  -- concat in chunks: table.concat on a few million one-char strings is fine
  -- on LuaJIT but chunking keeps peak memory lower on a phone
  if n <= 65536 then return table.concat(out), true end
  local parts = {}
  for i = 1, n, 65536 do
    parts[#parts + 1] = table.concat(out, "", i, math.min(n, i + 65535))
  end
  return table.concat(parts), true
end

function M.isCompressed(data)
  if type(data) ~= "string" or #data < 4 then return false end
  local k = data:byte(1)
  return k == 0x10 or k == 0x11
end

return M
