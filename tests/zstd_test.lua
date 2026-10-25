-- src/import/zstd.lua: Azahar's compressed images (.zcci). A small Z3DS file built here from raw
-- and RLE blocks checks the container, the seek table and reads across frames; with the player's
-- dump present (ORAS_ZCCI / ORAS_CCI, else the usual Downloads paths) sampled frames of the real
-- .zcci are decompressed and compared with the plain card image (ORAS_ZCCI_STEP, default 64: every
-- 64th frame; 1 checks all 2 GiB, ~75 s).
--   luajit mods/play_nav/tests/zstd_test.lua

local here = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]") or "mods/play_nav"
local Z = dofile(here .. "/src/import/zstd.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. name .. (detail and (" (" .. tostring(detail) .. ")") or "")) end
end

local function le(v, n)
  local t = {}
  for i = 1, n do t[i] = string.char(v % 256); v = math.floor(v / 256) end
  return table.concat(t)
end

-- a zstd frame of the given blocks: { "raw", bytes } / { "rle", byte, count }
local function frame(blocks)
  local parts = { le(0xFD2FB528, 4), string.char(0x00), string.char(0x50) } -- no FCS, window 1 MiB
  for i, b in ipairs(blocks) do
    local last = i == #blocks and 1 or 0
    if b[1] == "raw" then
      parts[#parts + 1] = le(last + 0 * 2 + #b[2] * 8, 3) .. b[2]
    else
      parts[#parts + 1] = le(last + 1 * 2 + b[3] * 8, 3) .. string.char(b[2])
    end
  end
  return table.concat(parts)
end

-- a Z3DS image of the frames (each with its decompressed size)
local function z3ds(frames, inner)
  local body, entries, total = {}, {}, 0
  for _, f in ipairs(frames) do
    body[#body + 1] = f.bytes
    entries[#entries + 1] = le(#f.bytes, 4) .. le(f.size, 4)
    total = total + f.size
  end
  local tbl = table.concat(entries) .. le(#frames, 4) .. string.char(0) .. le(0x8F92EAB1, 4)
  body[#body + 1] = le(0x184D2A5E, 4) .. le(#tbl, 4) .. tbl
  local data = table.concat(body)
  local meta = string.rep("\0", 0x10)
  local hdr = "Z3DS" .. inner .. string.char(1, 0) .. le(0x20, 2) .. le(#meta, 4) .. le(#data, 8) .. le(total, 8)
  return hdr .. meta .. data
end

do
  local a = string.rep("ab", 50) -- 100
  local plain = a .. string.rep("\7", 300) .. "tail!" .. string.rep("z", 1000) .. "end"
  local frames = {
    { bytes = frame({ { "raw", a }, { "rle", 7, 300 } }), size = 400 },
    { bytes = frame({ { "raw", "tail!" }, { "rle", ("z"):byte(), 1000 } }), size = 1005 },
    { bytes = frame({ { "raw", "end" } }), size = 3 },
  }
  local file = z3ds(frames, "NCSD")
  local function raw(off, len) return file:sub(off + 1, off + len) end
  check("isZ3ds", Z.isZ3ds(raw))
  check("not Z3DS", not Z.isZ3ds(function() return "NCSD" end))
  local read, size, inner = Z.wrap(raw)
  check("wrapped", read ~= nil, size)
  check("size", size == #plain, size)
  check("inner", inner == "NCSD", inner)
  check("whole", read(0, size) == plain)
  check("inside one frame", read(10, 50) == plain:sub(11, 60))
  check("across frames", read(390, 30) == plain:sub(391, 420))
  check("across three frames", read(399, 1007) == plain:sub(400, 1406))
  check("last byte", read(size - 1, 1) == "d")
  check("past the end refused", not pcall(read, size - 1, 2))
  check("frame alone", Z.frame(frames[2].bytes) == "tail!" .. string.rep("z", 1000))
  -- a seek table that does not add up
  local bad = z3ds({ { bytes = frames[1].bytes, size = 401 } }, "NCSD")
  local r2 = Z.wrap(function(off, len) return bad:sub(off + 1, off + len) end)
  local ok = pcall(r2, 0, 401)
  check("frame size checked", not ok)
end

-- the real image, when the dump is here
do
  local dl = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
  local name = "Pokemon Alpha Sapphire (USA) (En,Ja,Fr,De,Es,It,Ko) (Rev 2)"
  local zp = os.getenv("ORAS_ZCCI") or (dl .. "/Downloads/" .. name .. "/" .. name .. ".zcci")
  local cp = os.getenv("ORAS_CCI") or (dl .. "/Downloads/" .. name .. "/" .. name .. ".cci")
  local zf, cf = io.open(zp, "rb"), io.open(cp, "rb")
  if not (zf and cf) then
    print("skip: the real .zcci / .cci not found (ORAS_ZCCI / ORAS_CCI)")
  else
    local function opener(f) return function(off, len) f:seek("set", off); return f:read(len) end end
    local read, size, inner = Z.wrap(opener(zf), { keep = 2 })
    check("real: wrapped", read ~= nil, size)
    check("real: inner NCSD", inner == "NCSD", inner)
    check("real: size is the card's", size == cf:seek("end"), size)
    local CH, step = 262144, tonumber(os.getenv("ORAS_ZCCI_STEP") or "64")
    local cread = opener(cf)
    local bad, n = 0, 0
    local t0 = os.clock()
    for k = 0, math.floor(size / CH) - 1, step do
      n = n + 1
      if read(k * CH, CH) ~= cread(k * CH, CH) then bad = bad + 1; print("  frame differs: " .. k) end
    end
    local dt = os.clock() - t0
    check("real: sampled frames equal the card image", bad == 0, bad .. " of " .. n)
    check("real: a range across frames", read(CH * 100 - 1000, 5000) == cread(CH * 100 - 1000, 5000))
    print(("  %d frames, %.1f MB/s"):format(n, n * CH / 1e6 / math.max(dt, 1e-6)))
  end
  if zf then zf:close() end
  if cf then cf:close() end
end

print(("%d/%d checks passed%s  (play_nav zstd)"):format(pass, pass + fail, fail > 0 and (", " .. fail .. " FAILURES") or ""))
if fail > 0 then os.exit(1) end
