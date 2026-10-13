-- The 3DS layout formats the games' screens are built from, read from the bytes the extract
-- copied into the cache (recipe kind "files"): BCLYT (a screen's pane tree, materials and
-- groups) and BCLAN (one animation clip). Pure Lua, no love: the parse is tested headless.
--
-- F.layout(bytes) -> layout | nil, why
--   layout = { W, H, textures = { name... }, materials = { { name, black, white, maps, srt } },
--     root = pane, byName = { [name] = pane }, groups = { [name] = { pane names } } }
--   pane = { kind = "pan" | "pic" | "txt" | "wnd" | "bnd", name, visible, influence, origin,
--     alpha, t = { x, y }, rz, s = { x, y }, w, h, children, parent,
--     pic: colors { tl, tr, bl, br } (0-255 rgba), mat (material index, 1-based), uv { 8 numbers }
--     txt: text (the layout's own string), textPos, lineAlign, fontW, fontH, top, bottom (colours)
--     wnd: content { colors, mat, uv }, frames { { mat, flip } }, inflation { l, r, t, b } }
-- F.clip(bytes) -> clip | nil, why
--   clip = { name, frames, loop, from, to, groups = { names }, bind, textures = { names },
--     panes = { [pane] = { [prop] = keys } }, materials = { [material] = { [prop] = keys } } }
--   keys: { { frame, value, slope }... } (step keys carry no slope).
--   Pane props: tx ty tz rx ry rz sx sy w h (CLPA), "c<corner>.<channel>" and alpha (CLVC),
--   visible (CLVI); material props: "ts<map>.<0..4>" (CLTS tx ty rot sx sy), "tp<map>" (CLTP,
--   an index into clip.textures), "mc<n>" (CLMC).

local F = {}

local function u8(s, p) return s:byte(p) end
local function u16(s, p) return s:byte(p) + s:byte(p + 1) * 256 end
local function s16(s, p) local v = u16(s, p); return v >= 32768 and v - 65536 or v end
local function u32(s, p) return s:byte(p) + s:byte(p + 1) * 256 + s:byte(p + 2) * 65536 + s:byte(p + 3) * 16777216 end
local function f32(s, p)
  local b1, b2, b3, b4 = s:byte(p, p + 3)
  local sign = b4 >= 128 and -1 or 1
  local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
  local mant = (b3 % 128) * 65536 + b2 * 256 + b1
  if exp == 0 then return sign * mant * 2 ^ -149 end
  if exp == 255 then return mant == 0 and sign * math.huge or 0 end
  return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end
local function cstr(s, p, n)
  local raw = n and s:sub(p, p + n - 1) or s:sub(p)
  local z = raw:find("\0", 1, true)
  return z and raw:sub(1, z - 1) or raw
end
local function rgba(s, p) return { s:byte(p), s:byte(p + 1), s:byte(p + 2), s:byte(p + 3) } end
local function utf16(s, p, n)
  local out = {}
  for i = 0, n - 1 do
    local c = u16(s, p + i * 2)
    if c == 0 then break end
    if c < 128 then out[#out + 1] = string.char(c)
    elseif c < 2048 then out[#out + 1] = string.char(192 + math.floor(c / 64), 128 + c % 64)
    else out[#out + 1] = string.char(224 + math.floor(c / 4096), 128 + math.floor(c / 64) % 64, 128 + c % 64) end
  end
  return table.concat(out)
end
F.f32 = f32

-- sections of a CLYT / CLAN: iterate (magic, start of the section, its data start, size)
local function sections(b, magic)
  if type(b) ~= "string" or b:sub(1, 4) ~= magic then return nil, "not " .. magic end
  local hsize, fsize = u16(b, 7), u32(b, 13)
  local p, stop = hsize + 1, math.min(#b, fsize)
  return function()
    if p + 8 > stop + 1 then return nil end
    local tag, size = b:sub(p, p + 3), u32(b, p + 4)
    if size == 0 then return nil end
    local at = p
    p = p + size
    return tag, at, at + 8, size
  end
end

local KIND = { pan1 = "pan", pic1 = "pic", txt1 = "txt", wnd1 = "wnd", bnd1 = "bnd" }

local function uvs(b, p)
  local out = {}
  for i = 0, 7 do out[i + 1] = f32(b, p + i * 4) end
  return out
end

function F.layout(b)
  local iter, why = sections(b, "CLYT")
  if not iter then return nil, why end
  local L = { textures = {}, materials = {}, byName = {}, groups = {}, groupOrder = {} }
  local stack, last = {}, nil
  for tag, at, d in iter do
    if tag == "lyt1" then
      L.W, L.H = f32(b, d + 4), f32(b, d + 8)
    elseif tag == "txl1" then
      local n = u32(b, d)
      for i = 0, n - 1 do
        L.textures[i + 1] = cstr(b, d + 4 + u32(b, d + 4 + i * 4))
      end
    elseif tag == "mat1" then
      local n = u32(b, d)
      for i = 0, n - 1 do
        local m = at + u32(b, d + 4 + i * 4)
        local flags = u32(b, m + 48)
        local nmap, nsrt = flags % 4, math.floor(flags / 4) % 4
        local mat = { name = cstr(b, m, 20), black = rgba(b, m + 20), white = rgba(b, m + 24), maps = {}, srt = {} }
        local q = m + 52
        for t = 1, nmap do
          mat.maps[t] = { tex = u16(b, q) + 1, wrapS = u8(b, q + 2) % 4, wrapT = u8(b, q + 3) % 4 }
          q = q + 4
        end
        for t = 1, nsrt do
          mat.srt[t] = { f32(b, q), f32(b, q + 4), f32(b, q + 8), f32(b, q + 12), f32(b, q + 16) }
          q = q + 20
        end
        L.materials[i + 1] = mat
      end
    elseif KIND[tag] then
      local flags, origin = u8(b, d), u8(b, d + 1)
      local pane = { kind = KIND[tag], name = cstr(b, d + 4, 16), visible = flags % 2 == 1,
        influence = math.floor(flags / 2) % 2 == 1, origin = origin, alpha = u8(b, d + 2),
        t = { f32(b, d + 28), f32(b, d + 32) }, rz = f32(b, d + 48), s = { f32(b, d + 52), f32(b, d + 56) },
        w = f32(b, d + 60), h = f32(b, d + 64), children = {} }
      if tag == "pic1" then
        pane.colors = { rgba(b, d + 68), rgba(b, d + 72), rgba(b, d + 76), rgba(b, d + 80) }
        pane.mat = u16(b, d + 84) + 1
        if u8(b, d + 86) > 0 then pane.uv = uvs(b, d + 88) end
      elseif tag == "txt1" then
        local strLen = u16(b, d + 70)
        pane.mat = u16(b, d + 72) + 1
        pane.textPos, pane.lineAlign = u8(b, d + 76), u8(b, d + 77)
        local so = u32(b, d + 80)
        pane.top, pane.bottom = rgba(b, d + 84), rgba(b, d + 88)
        pane.fontW, pane.fontH = f32(b, d + 92), f32(b, d + 96)
        pane.text = strLen > 0 and utf16(b, at + so, strLen / 2) or ""
      elseif tag == "wnd1" then
        pane.inflation = { f32(b, d + 68), f32(b, d + 72), f32(b, d + 76), f32(b, d + 80) }
        local nframes = u8(b, at + 92)
        local co, fo = u32(b, at + 96), u32(b, at + 100)
        local c = at + co
        pane.content = { colors = { rgba(b, c), rgba(b, c + 4), rgba(b, c + 8), rgba(b, c + 12) }, mat = u16(b, c + 16) + 1 }
        if u8(b, c + 18) > 0 then pane.content.uv = uvs(b, c + 20) end
        pane.frames = {}
        for i = 0, nframes - 1 do
          local f = at + u32(b, at + fo + i * 4)
          pane.frames[i + 1] = { mat = u16(b, f) + 1, flip = u8(b, f + 2) }
        end
      end
      local parent = stack[#stack]
      if parent then
        pane.parent = parent
        parent.children[#parent.children + 1] = pane
      else
        L.root = pane
      end
      L.byName[pane.name] = pane
      last = pane
    elseif tag == "pas1" then
      stack[#stack + 1] = last
    elseif tag == "pae1" then
      stack[#stack] = nil
    elseif tag == "grp1" then
      local name, n = cstr(b, d, 16), u16(b, d + 16)
      local panes = {}
      for i = 0, n - 1 do panes[i + 1] = cstr(b, d + 20 + i * 16, 16) end
      L.groups[name] = panes
      L.groupOrder[#L.groupOrder + 1] = name
    end
  end
  if not (L.root and L.W) then return nil, "no panes" end
  return L
end

local PA = { "tx", "ty", "tz", "rx", "ry", "rz", "sx", "sy", "w", "h" }
local CORNER = { "tl", "tr", "bl", "br" }
local CHANNEL = { "r", "g", "b", "a" }
local function vcName(i)
  if i == 16 then return "alpha" end
  return "c" .. CORNER[math.floor(i / 4) + 1] .. "." .. CHANNEL[i % 4 + 1]
end

function F.clip(b)
  local iter, why = sections(b, "CLAN")
  if not iter then return nil, why end
  local C = { textures = {}, panes = {}, materials = {}, groups = {} }
  for tag, at, d in iter do
    if tag == "pat1" then
      local ng = u16(b, d + 2)
      local noff, goff = u32(b, d + 4), u32(b, d + 8)
      C.name = cstr(b, at + noff)
      for i = 0, ng - 1 do C.groups[i + 1] = cstr(b, at + goff + i * 20, 16) end
      C.from, C.to = s16(b, d + 12), s16(b, d + 14)
      C.bind = u8(b, d + 16) ~= 0
    elseif tag == "pai1" then
      C.frames, C.loop = u16(b, d), u8(b, d + 2) ~= 0
      local ntex, nent, entoff = u16(b, d + 4), u16(b, d + 6), u32(b, d + 8)
      for i = 0, ntex - 1 do C.textures[i + 1] = cstr(b, d + 12 + u32(b, d + 12 + i * 4)) end
      for e = 0, nent - 1 do
        local eo = at + u32(b, at + entoff + e * 4)
        local name, ninfo, kind = cstr(b, eo, 20), u8(b, eo + 20), u8(b, eo + 21)
        local into = kind == 1 and C.materials or C.panes
        local props = into[name] or {}
        into[name] = props
        for i = 0, ninfo - 1 do
          local io = eo + u32(b, eo + 24 + i * 4)
          local itag, ntgt = b:sub(io, io + 3), u8(b, io + 4)
          for t = 0, ntgt - 1 do
            local to = io + u32(b, io + 8 + t * 4)
            local idx, target, curve = u8(b, to), u8(b, to + 1), u8(b, to + 2)
            local nkeys, koff = u16(b, to + 4), u32(b, to + 8)
            local keys = {}
            for k = 0, nkeys - 1 do
              if curve == 2 then
                local kp = to + koff + k * 12
                keys[k + 1] = { f32(b, kp), f32(b, kp + 4), f32(b, kp + 8) }
              else
                local kp = to + koff + k * 8
                keys[k + 1] = { f32(b, kp), u16(b, kp + 4) }
              end
            end
            local prop
            if itag == "CLPA" then prop = PA[target + 1]
            elseif itag == "CLVC" then prop = vcName(target)
            elseif itag == "CLVI" then prop = "visible"
            elseif itag == "CLTS" then prop = "ts" .. idx .. "." .. target
            elseif itag == "CLTP" then prop = "tp" .. idx
            elseif itag == "CLMC" then prop = "mc" .. target
            end
            if prop then props[prop] = { keys = keys, step = curve ~= 2 } end
          end
        end
      end
    end
  end
  if not C.frames then return nil, "no pai1" end
  return C
end

-- a track's value at frame f: hermite keys ease between neighbours (two keys on one frame
-- jump), step keys hold
function F.eval(track, f)
  local keys = track.keys
  local n = #keys
  if n == 0 then return nil end
  if f <= keys[1][1] then return keys[1][2] end
  if track.step then
    local v = keys[1][2]
    for i = 2, n do
      if keys[i][1] <= f then v = keys[i][2] else break end
    end
    return v
  end
  for i = 1, n - 1 do
    local a, c = keys[i], keys[i + 1]
    if f < c[1] then
      local span = c[1] - a[1]
      if span <= 0 then return c[2] end
      local t = (f - a[1]) / span
      local t2, t3 = t * t, t * t * t
      return (2 * t3 - 3 * t2 + 1) * a[2] + (t3 - 2 * t2 + t) * (a[3] or 0) * span
        + (-2 * t3 + 3 * t2) * c[2] + (t3 - t2) * (c[3] or 0) * span
    end
  end
  return keys[n][2]
end

return F
