-- Zstandard (RFC 8878) frame decoder, pure Lua, plus Azahar's compressed 3DS images (.zcci /
-- .zcxi / .zcia): a "Z3DS" header, then a zstd seekable stream (independent frames and a seek
-- table in a skippable frame at its end). `M.wrap(read)` turns a raw read(offset, length) of
-- such a file into a read of the image inside it, decompressing only the frames a range covers,
-- so the card readers (ctr.lua and the rest) run on it unchanged. Runs inside a mod.job worker
-- (no require, no ffi): the module arrives as a source string like lz.lua.

local byte, char, sub, concat = string.byte, string.char, string.sub, table.concat
local floor = math.floor
local unpack = unpack or table.unpack

local M = {}

local P2 = {}
for i = 0, 40 do P2[i] = 2 ^ i end

local function u32(s, p)
  local a, b, c, d = byte(s, p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function highbit(v) -- index of the highest set bit, v >= 1
  local n = 0
  while v >= 2 do v = floor(v / 2); n = n + 1 end
  return n
end

-- n (<= 32) bits of the string s from bit position p (0 = bit 0 of byte i0), little-endian
-- bit order; bits before i0 / past the end read as zero
local function bitsAt(s, i0, last, p, n)
  if n == 0 then return 0 end
  local q = floor(p / 8)
  local i = i0 + q
  local v = 0
  local m = 1
  for k = i, i + 4 do
    if k >= i0 and k <= last then v = v + byte(s, k) * m end
    m = m * 256
  end
  -- p may be negative: shift the window up by whole bytes so the division stays exact
  return floor(v / P2[p - q * 8]) % P2[n]
end

-- ---------------------------------------------------------------------------------------
-- FSE

-- Reads a normalized-count table description at byte i of s. Returns probs (0-based),
-- accuracy log, the byte just past it.
local function readNCount(s, i, maxSym)
  local last = #s
  local pos = 0
  local function peek(n) return bitsAt(s, i, last, pos, n) end
  local al = peek(4) + 5
  pos = 4
  local remaining = P2[al] + 1
  local threshold = P2[al]
  local nbBits = al + 1
  local probs = {}
  local sym = 0
  local prev0 = false
  while remaining > 1 and sym <= maxSym do
    if prev0 then
      local n0 = sym
      while peek(2) == 3 do n0 = n0 + 3; pos = pos + 2 end
      n0 = n0 + peek(2); pos = pos + 2
      while sym < n0 do probs[sym] = 0; sym = sym + 1 end
      if sym > maxSym then break end
    end
    local max = 2 * threshold - 1 - remaining
    local count
    local low = peek(nbBits - 1)
    if low < max then
      count = low
      pos = pos + nbBits - 1
    else
      count = peek(nbBits)
      if count >= threshold then count = count - max end
      pos = pos + nbBits
    end
    count = count - 1
    remaining = remaining - (count < 0 and -count or count)
    probs[sym] = count
    sym = sym + 1
    prev0 = count == 0
    while remaining < threshold do nbBits = nbBits - 1; threshold = threshold / 2 end
  end
  if remaining ~= 1 then error("zstd: bad FSE table description", 0) end
  for k = sym, maxSym do probs[k] = 0 end
  return probs, al, i + floor((pos + 7) / 8)
end

-- Decoding table from probs: { sym = {}, nb = {}, base = {}, al }
local function buildFse(probs, al, maxSym)
  local size = P2[al]
  local sym, nb, base = {}, {}, {}
  local high = size - 1
  local nextS = {}
  for s = 0, maxSym do
    local p = probs[s] or 0
    if p == -1 then
      sym[high] = s; high = high - 1; nextS[s] = 1
    else
      nextS[s] = p
    end
  end
  local step = floor(size / 2) + floor(size / 8) + 3
  local mask = size - 1
  local pos = 0
  for s = 0, maxSym do
    local p = probs[s] or 0
    for _ = 1, p do
      sym[pos] = s
      repeat pos = (pos + step) % size until pos <= high
    end
  end
  if pos ~= 0 then error("zstd: bad FSE spread", 0) end
  for u = 0, mask do
    local s = sym[u]
    local ns = nextS[s]
    nextS[s] = ns + 1
    local b = al - highbit(ns)
    nb[u] = b
    base[u] = ns * P2[b] - size
  end
  return { sym = sym, nb = nb, base = base, al = al }
end

local function rleFse(s) return { sym = { [0] = s }, nb = { [0] = 0 }, base = { [0] = 0 }, al = 0 } end

-- ---------------------------------------------------------------------------------------
-- backward bitstreams (Huffman streams, FSE weights, sequences): s[i0..last], read from the
-- end; returns a reader { s, i0, last, p }

local function backStream(s, i0, last)
  local lb = byte(s, last)
  if not lb or lb == 0 then error("zstd: bad bitstream end", 0) end
  return { s = s, i0 = i0, last = last, p = (last - i0) * 8 + highbit(lb) }
end

local function readBack(b, n)
  if n == 0 then return 0 end
  local p = b.p - n
  b.p = p
  return bitsAt(b.s, b.i0, b.last, p, n)
end

-- ---------------------------------------------------------------------------------------
-- Huffman

local function huffWeights(s, i)
  local h = byte(s, i)
  local w = {}
  if h >= 128 then
    local n = h - 127
    for k = 0, n - 1 do
      local bb = byte(s, i + 1 + floor(k / 2))
      w[k] = k % 2 == 0 and floor(bb / 16) or bb % 16
    end
    return w, n, i + 1 + floor((n + 1) / 2)
  end
  -- FSE-compressed weights, two interleaved states
  local probs, al, j = readNCount(s, i + 1, 255)
  if al > 6 then error("zstd: Huffman weights accuracy too high", 0) end
  local t = buildFse(probs, al, 255)
  local stop = i + h
  local b = backStream(s, j, stop)
  local s1 = readBack(b, al)
  local s2 = readBack(b, al)
  local n = 0
  local tsym, tnb, tbase = t.sym, t.nb, t.base
  while true do
    w[n] = tsym[s1]; n = n + 1
    s1 = tbase[s1] + readBack(b, tnb[s1])
    if b.p < 0 then w[n] = tsym[s2]; n = n + 1; break end
    w[n] = tsym[s2]; n = n + 1
    s2 = tbase[s2] + readBack(b, tnb[s2])
    if b.p < 0 then w[n] = tsym[s1]; n = n + 1; break end
    if n > 255 then error("zstd: too many Huffman weights", 0) end
  end
  return w, n, stop + 1
end

-- { maxBits, sym = {}, nb = {} } indexed by the next maxBits bits
local function buildHuff(w, n)
  local sum = 0
  for k = 0, n - 1 do if w[k] > 0 then sum = sum + P2[w[k] - 1] end end
  if sum == 0 then error("zstd: empty Huffman tree", 0) end
  local maxBits = highbit(sum) + 1
  local rest = P2[maxBits] - sum
  local lastW = highbit(rest) + 1
  if P2[lastW - 1] ~= rest then error("zstd: bad Huffman tree", 0) end
  w[n] = lastW
  n = n + 1
  local count = {}
  for k = 0, maxBits do count[k] = 0 end
  for k = 0, n - 1 do count[w[k]] = count[w[k]] + 1 end
  local start = {}
  local acc = 0
  for wt = 1, maxBits do start[wt] = acc; acc = acc + count[wt] * P2[wt - 1] end
  local sym, nb = {}, {}
  for k = 0, n - 1 do
    local wt = w[k]
    if wt > 0 then
      local len = P2[wt - 1]
      local st = start[wt]
      local bits = maxBits + 1 - wt
      for u = st, st + len - 1 do sym[u] = k; nb[u] = bits end
      start[wt] = st + len
    end
  end
  return { maxBits = maxBits, sym = sym, nb = nb }
end

-- decodes `count` literals of one stream s[i0..last] into lit from index o
local function huffStream(h, s, i0, last, lit, o, count)
  local b = backStream(s, i0, last)
  local mb, hsym, hnb = h.maxBits, h.sym, h.nb
  local p = b.p
  for k = o, o + count - 1 do
    local v = bitsAt(s, i0, last, p - mb, mb)
    lit[k] = hsym[v]
    p = p - hnb[v]
  end
  if p ~= 0 then error("zstd: Huffman stream size mismatch", 0) end
end

-- ---------------------------------------------------------------------------------------
-- sequences

local LL_BASE, LL_BITS = {}, {}
do
  local b = { 16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536 }
  local n = { 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
  for c = 0, 15 do LL_BASE[c] = c; LL_BITS[c] = 0 end
  for k = 1, #b do LL_BASE[15 + k] = b[k]; LL_BITS[15 + k] = n[k] end
end
local ML_BASE, ML_BITS = {}, {}
do
  local b = { 35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539 }
  local n = { 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
  for c = 0, 31 do ML_BASE[c] = c + 3; ML_BITS[c] = 0 end
  for k = 1, #b do ML_BASE[31 + k] = b[k]; ML_BITS[31 + k] = n[k] end
end

local function zeroBased(t) local r = {}; for k = 1, #t do r[k - 1] = t[k] end; return r end
local LL_DEF = buildFse(zeroBased({ 4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1 }), 6, 35)
local ML_DEF = buildFse(zeroBased({ 1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1 }), 6, 52)
local OF_DEF = buildFse(zeroBased({ 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  -1, -1, -1, -1, -1 }), 5, 31)

local function seqTable(mode, s, i, def, maxSym, maxAl, prev)
  if mode == 0 then return def, i end
  if mode == 1 then return rleFse(byte(s, i)), i + 1 end
  if mode == 2 then
    local probs, al, j = readNCount(s, i, maxSym)
    if al > maxAl then error("zstd: sequence table accuracy too high", 0) end
    return buildFse(probs, al, maxSym), j
  end
  if not prev then error("zstd: repeat table with none before", 0) end
  return prev, i
end

-- ---------------------------------------------------------------------------------------
-- frames

-- One compressed block s[i..e] appended to out (a byte table, n bytes so far). st carries
-- the frame's Huffman / FSE tables and repeat offsets between blocks.
local function compressedBlock(s, i, e, out, n, st)
  -- literals
  local b0 = byte(s, i)
  local ltype = b0 % 4
  local sf = floor(b0 / 4) % 4
  local lit = {}
  local nLit
  if ltype < 2 then
    local hs
    if sf == 0 or sf == 2 then nLit = floor(b0 / 8); hs = 1
    elseif sf == 1 then nLit = floor(b0 / 16) + byte(s, i + 1) * 16; hs = 2
    else nLit = floor(b0 / 16) + byte(s, i + 1) * 16 + byte(s, i + 2) * 4096; hs = 3 end
    i = i + hs
    if ltype == 0 then
      local k = 0
      while k < nLit do
        local m = nLit - k
        if m > 4096 then m = 4096 end
        local bs = { byte(s, i + k, i + k + m - 1) }
        for q = 1, m do lit[k + q - 1] = bs[q] end
        k = k + m
      end
      i = i + nLit
    else
      local v = byte(s, i)
      for k = 0, nLit - 1 do lit[k] = v end
      i = i + 1
    end
  else
    local hs, bitsEach, streams
    if sf == 0 then hs, bitsEach, streams = 3, 10, 1
    elseif sf == 1 then hs, bitsEach, streams = 3, 10, 4
    elseif sf == 2 then hs, bitsEach, streams = 4, 14, 4
    else hs, bitsEach, streams = 5, 18, 4 end
    local h = 0
    for k = hs - 1, 0, -1 do h = h * 256 + byte(s, i + k) end
    h = floor(h / 16)
    nLit = h % P2[bitsEach]
    local cSize = floor(h / P2[bitsEach]) % P2[bitsEach]
    i = i + hs
    local stop = i + cSize - 1
    if ltype == 2 then
      local w, nw, j = huffWeights(s, i)
      st.huf = buildHuff(w, nw)
      i = j
    elseif not st.huf then
      error("zstd: treeless literals with no table", 0)
    end
    if streams == 1 then
      huffStream(st.huf, s, i, stop, lit, 0, nLit)
    else
      local z1 = byte(s, i) + byte(s, i + 1) * 256
      local z2 = byte(s, i + 2) + byte(s, i + 3) * 256
      local z3 = byte(s, i + 4) + byte(s, i + 5) * 256
      local a = i + 6
      local seg = floor((nLit + 3) / 4)
      huffStream(st.huf, s, a, a + z1 - 1, lit, 0, seg); a = a + z1
      huffStream(st.huf, s, a, a + z2 - 1, lit, seg, seg); a = a + z2
      huffStream(st.huf, s, a, a + z3 - 1, lit, 2 * seg, seg); a = a + z3
      huffStream(st.huf, s, a, stop, lit, 3 * seg, nLit - 3 * seg)
    end
    i = stop + 1
  end

  -- sequences
  local nSeq = byte(s, i)
  if nSeq == 0 then
    i = i + 1
  elseif nSeq < 128 then
    i = i + 1
  elseif nSeq < 255 then
    nSeq = (nSeq - 128) * 256 + byte(s, i + 1); i = i + 2
  else
    nSeq = byte(s, i + 1) + byte(s, i + 2) * 256 + 0x7F00; i = i + 3
  end
  local lp = 0
  if nSeq > 0 then
    local modes = byte(s, i)
    i = i + 1
    st.ll, i = seqTable(floor(modes / 64) % 4, s, i, LL_DEF, 35, 9, st.ll)
    st.of, i = seqTable(floor(modes / 16) % 4, s, i, OF_DEF, 31, 8, st.of)
    st.ml, i = seqTable(floor(modes / 4) % 4, s, i, ML_DEF, 52, 9, st.ml)
    local b = backStream(s, i, e)
    local sb, si0, slast = s, i, e
    local p = b.p
    local llT, ofT, mlT = st.ll, st.of, st.ml
    local llS, llNb, llBase = llT.sym, llT.nb, llT.base
    local ofS, ofNb, ofBase = ofT.sym, ofT.nb, ofT.base
    local mlS, mlNb, mlBase = mlT.sym, mlT.nb, mlT.base
    p = p - llT.al; local sLL = bitsAt(sb, si0, slast, p, llT.al)
    p = p - ofT.al; local sOF = bitsAt(sb, si0, slast, p, ofT.al)
    p = p - mlT.al; local sML = bitsAt(sb, si0, slast, p, mlT.al)
    local r1, r2, r3 = st.r1, st.r2, st.r3
    for q = 1, nSeq do
      local ofc, mlc, llc = ofS[sOF], mlS[sML], llS[sLL]
      local ov
      if ofc > 0 then p = p - ofc; ov = P2[ofc] + bitsAt(sb, si0, slast, p, ofc) else ov = 1 end
      local mlb = ML_BITS[mlc]
      local ml = ML_BASE[mlc]
      if mlb > 0 then p = p - mlb; ml = ml + bitsAt(sb, si0, slast, p, mlb) end
      local llb = LL_BITS[llc]
      local ll = LL_BASE[llc]
      if llb > 0 then p = p - llb; ll = ll + bitsAt(sb, si0, slast, p, llb) end
      -- offsets: 1..3 are the repeat offsets (shifted by one with no literals)
      local off
      if ov > 3 then
        off = ov - 3; r3 = r2; r2 = r1; r1 = off
      else
        local idx = ov - 1 + (ll == 0 and 1 or 0)
        if idx == 0 then
          off = r1
        elseif idx == 1 then
          off = r2; r2 = r1; r1 = off
        elseif idx == 2 then
          off = r3; r3 = r2; r2 = r1; r1 = off
        else
          off = r1 - 1; if off == 0 then off = 1 end
          r3 = r2; r2 = r1; r1 = off
        end
      end
      if q < nSeq then
        local nb = llNb[sLL]; p = p - nb; sLL = llBase[sLL] + bitsAt(sb, si0, slast, p, nb)
        nb = mlNb[sML]; p = p - nb; sML = mlBase[sML] + bitsAt(sb, si0, slast, p, nb)
        nb = ofNb[sOF]; p = p - nb; sOF = ofBase[sOF] + bitsAt(sb, si0, slast, p, nb)
      end
      -- execute: literals, then the match
      for k = 0, ll - 1 do out[n + 1 + k] = lit[lp + k] end
      n = n + ll
      lp = lp + ll
      if off > n then error("zstd: match offset past the start", 0) end
      local from = n - off
      for k = 1, ml do out[n + k] = out[from + k] end
      n = n + ml
    end
    if p ~= 0 then error("zstd: sequence stream size mismatch", 0) end
    st.r1, st.r2, st.r3 = r1, r2, r3
  end
  for k = lp, nLit - 1 do n = n + 1; out[n] = lit[k] end
  return n
end

local function bytesToString(out, n)
  local parts = {}
  local k = 1
  while k <= n do
    local e = k + 4095
    if e > n then e = n end
    parts[#parts + 1] = char(unpack(out, k, e))
    k = e + 1
  end
  return concat(parts)
end

-- Decodes the one zstd frame in s (skippable frames give ""). Returns the bytes.
function M.frame(s)
  local magic = u32(s, 1)
  if magic >= 0x184D2A50 and magic <= 0x184D2A5F then return "" end
  if magic ~= 0xFD2FB528 then error("zstd: not a frame", 0) end
  local d = byte(s, 5)
  local fcsFlag = floor(d / 64)
  local single = floor(d / 32) % 2 == 1
  local checksum = floor(d / 4) % 2 == 1
  local dictFlag = d % 4
  local i = 6
  if not single then i = i + 1 end
  i = i + ({ [0] = 0, 1, 2, 4 })[dictFlag]
  local fcsSize = ({ [0] = single and 1 or 0, 2, 4, 8 })[fcsFlag]
  i = i + fcsSize
  local out, n = {}, 0
  local st = { r1 = 1, r2 = 4, r3 = 8 }
  while true do
    local h = byte(s, i) + byte(s, i + 1) * 256 + byte(s, i + 2) * 65536
    i = i + 3
    local last = h % 2 == 1
    local btype = floor(h / 2) % 4
    local size = floor(h / 8)
    if btype == 0 then
      local k = 0
      while k < size do
        local m = size - k
        if m > 4096 then m = 4096 end
        local bs = { byte(s, i + k, i + k + m - 1) }
        for q = 1, m do out[n + q] = bs[q] end
        n = n + m
        k = k + m
      end
      i = i + size
    elseif btype == 1 then
      local v = byte(s, i)
      for k = 1, size do out[n + k] = v end
      n = n + size
      i = i + 1
    elseif btype == 2 then
      n = compressedBlock(s, i, i + size - 1, out, n, st)
      i = i + size
    else
      error("zstd: reserved block type", 0)
    end
    if last then break end
  end
  if checksum then i = i + 4 end
  return bytesToString(out, n)
end

-- ---------------------------------------------------------------------------------------
-- Azahar's Z3DS container over a zstd seekable stream

local SEEK_MAGIC = 0x8F92EAB1

-- true when the raw file starts with Azahar's compressed-image header
function M.isZ3ds(read)
  local ok, h = pcall(read, 0, 4)
  return ok and h == "Z3DS"
end

-- Returns read'(offset, length) over the image inside, its size, and the inner format's magic
-- ("NCSD" / "NCCH" / "CIA" ...); or nil, reason.
function M.wrap(read, opts)
  opts = opts or {}
  local h = read(0, 0x20)
  if sub(h, 1, 4) ~= "Z3DS" then return nil, "not a Z3DS image" end
  local inner = sub(h, 5, 8):gsub("%z+$", "")
  local hdrSize = byte(h, 11) + byte(h, 12) * 256
  local metaSize = u32(h, 13)
  local cSize = u32(h, 17) + u32(h, 21) * 4294967296
  local dSize = u32(h, 25) + u32(h, 29) * 4294967296
  local base = hdrSize + metaSize
  local foot = read(base + cSize - 9, 9)
  if u32(foot, 6) ~= SEEK_MAGIC then return nil, "compressed image: no seek table" end
  local nFrames = u32(foot, 1)
  local desc = byte(foot, 5)
  local entry = floor(desc / 128) % 2 == 1 and 12 or 8
  local tLen = nFrames * entry
  local t = read(base + cSize - 9 - tLen, tLen)
  local cOff, dOff, dLen = {}, {}, {}
  local c, dd = base, 0
  for k = 1, nFrames do
    local q = (k - 1) * entry + 1
    local cs, ds = u32(t, q), u32(t, q + 4)
    cOff[k], dOff[k], dLen[k] = c, dd, ds
    c, dd = c + cs, dd + ds
  end
  cOff[nFrames + 1] = c
  if dd ~= dSize then return nil, "compressed image: seek table does not add up" end

  -- a few frames kept (the readers often read small pieces of one frame in a row)
  local KEEP = opts.keep or 6
  local cache, order = {}, {}
  local function frameAt(k)
    local f = cache[k]
    if f then return f end
    f = M.frame(read(cOff[k], cOff[k + 1] - cOff[k]))
    if #f ~= dLen[k] then error(("zstd: frame %d is %d bytes, the table says %d"):format(k, #f, dLen[k]), 0) end
    cache[k] = f
    order[#order + 1] = k
    if #order > KEEP then cache[table.remove(order, 1)] = nil end
    return f
  end
  local function find(off) -- the frame holding byte off (0-based)
    local lo, hi = 1, nFrames
    while lo < hi do
      local mid = floor((lo + hi + 1) / 2)
      if dOff[mid] <= off then lo = mid else hi = mid - 1 end
    end
    return lo
  end
  local function zread(offset, length)
    if length <= 0 then return "" end
    if offset < 0 or offset + length > dSize then error("read past the end of the image", 0) end
    local parts = {}
    local k = find(offset)
    local pos, left = offset, length
    while left > 0 do
      while dLen[k] == 0 do k = k + 1 end
      local f = frameAt(k)
      local a = pos - dOff[k]
      local m = dLen[k] - a
      if m > left then m = left end
      parts[#parts + 1] = sub(f, a + 1, a + m)
      pos, left = pos + m, left - m
      k = k + 1
    end
    return #parts == 1 and parts[1] or concat(parts)
  end
  return zread, dSize, inner
end

return M
