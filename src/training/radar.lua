-- The Effort-o-Meter: a hexagon radar with the species' base stats inside (green) and the
-- EVs outside (yellow), in the Super Training order HP, Attack, Defense, Speed, Sp. Def,
-- Sp. Atk clockwise from the top (the original's layout). The maths are pure so the tests
-- can check them; drawing needs love.graphics.

local Radar = {}

Radar.ORDER = { "hp", "atk", "def", "spe", "spd", "spa" }
Radar.LABELS = { hp = "HP", atk = "ATK", def = "DEF", spe = "SPE", spd = "SPD", spa = "SPA" }

-- the six corner points of a hexagon of radius r at (cx, cy), first at the top, clockwise
function Radar.corners(cx, cy, r)
  local pts = {}
  for i = 0, 5 do
    local a = -math.pi / 2 + i * math.pi / 3
    pts[#pts + 1] = cx + math.cos(a) * r
    pts[#pts + 1] = cy + math.sin(a) * r
  end
  return pts
end

-- the polygon for six values (table keyed by stat) scaled by `max`, clamped 0..1
function Radar.points(cx, cy, r, values, max)
  local pts = {}
  for i, k in ipairs(Radar.ORDER) do
    local v = math.max(0, math.min(1, (tonumber(values and values[k]) or 0) / (max or 1)))
    local a = -math.pi / 2 + (i - 1) * math.pi / 3
    pts[#pts + 1] = cx + math.cos(a) * r * v
    pts[#pts + 1] = cy + math.sin(a) * r * v
  end
  return pts
end

-- EVs sit outside the base stats: each axis is base/baseMax of the inner ring plus
-- ev/evMax of the outer band; returns the two polygons
function Radar.layers(cx, cy, r, base, evs, baseMax, evMax, innerShare)
  innerShare = innerShare or 0.5
  local inner = Radar.points(cx, cy, r * innerShare, base, baseMax)
  local outer = {}
  for i, k in ipairs(Radar.ORDER) do
    local b = math.max(0, math.min(1, (tonumber(base and base[k]) or 0) / (baseMax or 1)))
    local e = math.max(0, math.min(1, (tonumber(evs and evs[k]) or 0) / (evMax or 1)))
    local v = b * innerShare + e * (1 - innerShare)
    local a = -math.pi / 2 + (i - 1) * math.pi / 3
    outer[#outer + 1] = cx + math.cos(a) * r * v
    outer[#outer + 1] = cy + math.sin(a) * r * v
  end
  return inner, outer
end

local function polygonOk(pts)
  -- love needs three distinct points; a collapsed polygon is skipped
  local n = #pts / 2
  if n < 3 then return false end
  local x0, y0 = pts[1], pts[2]
  for i = 2, n do
    if math.abs(pts[i * 2 - 1] - x0) > 0.01 or math.abs(pts[i * 2] - y0) > 0.01 then return true end
  end
  return false
end

-- opts = { base, evs, baseMax = 255, evMax = 252, font, labels = true, totalEv, totalMax }
function Radar.draw(G, cx, cy, r, opts)
  opts = opts or {}
  local baseMax, evMax = opts.baseMax or 255, opts.evMax or 252
  G.setColor(0.1, 0.12, 0.16, 0.9)
  G.polygon("fill", Radar.corners(cx, cy, r))
  G.setColor(0.35, 0.4, 0.5, 0.6)
  G.polygon("line", Radar.corners(cx, cy, r))
  G.polygon("line", Radar.corners(cx, cy, r * 0.5))
  local c = Radar.corners(cx, cy, r)
  for i = 1, 6 do G.line(cx, cy, c[i * 2 - 1], c[i * 2]) end
  local inner, outer = Radar.layers(cx, cy, r, opts.base, opts.evs, baseMax, evMax, 0.5)
  if polygonOk(outer) then
    G.setColor(0.98, 0.85, 0.25, 0.85)
    G.polygon("fill", outer)
  end
  if polygonOk(inner) then
    G.setColor(0.3, 0.8, 0.45, 0.95)
    G.polygon("fill", inner)
  end
  G.setColor(1, 1, 1, 0.9)
  G.polygon("line", Radar.corners(cx, cy, r))
  if opts.labels ~= false and opts.font then
    G.setFont(opts.font)
    for i, k in ipairs(Radar.ORDER) do
      local a = -math.pi / 2 + (i - 1) * math.pi / 3
      local lx, ly = cx + math.cos(a) * (r + 9), cy + math.sin(a) * (r + 7)
      local label = Radar.LABELS[k]
      local w = opts.font:getWidth(label)
      G.setColor(1, 1, 1, 0.95)
      G.print(label, math.floor(lx - w / 2), math.floor(ly - 5))
    end
  end
  G.setColor(1, 1, 1, 1)
end

-- the vertical total bar beside the radar: fill fraction of totalMax
function Radar.drawTotal(G, x, y, w, h, total, totalMax)
  G.setColor(0.1, 0.12, 0.16, 0.9)
  G.rectangle("fill", x, y, w, h, 2, 2)
  local f = math.max(0, math.min(1, (total or 0) / (totalMax or 510)))
  local fh = math.floor((h - 2) * f)
  if fh > 0 then
    if f >= 1 then G.setColor(0.3, 0.9, 0.5, 1) else G.setColor(0.4, 0.8, 0.45, 1) end
    G.rectangle("fill", x + 1, y + h - 1 - fh, w - 2, fh, 1, 1)
  end
  G.setColor(1, 1, 1, 0.8)
  G.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 2, 2)
  G.setColor(1, 1, 1, 1)
end

return Radar
