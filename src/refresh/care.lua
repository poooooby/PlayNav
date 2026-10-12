-- Pokemon Refresh cleaning rules, pure Lua: which marks a battle leaves on
-- a Pokemon, which tool removes which mark, how rubbing wears a mark down,
-- and the small affection / enjoyment rewards for a clean or a cure. The
-- Amie stats themselves live in src/amie/rules.lua. No love, no engine.
--
-- Positions are in body space: x, y in -1..1 over the sprite's body
-- ellipse. The app maps them to pixels for whatever size it draws at.

local Care = {}

Care.MARKS = { "mud", "dust", "wet", "ruffled" }
Care.TOOLS = { "medicine", "comb", "brush", "towel", "dryer", "beans" }
Care.TOOL_FOR = { mud = "towel", dust = "brush", wet = "dryer", ruffled = "comb" }
Care.MARK_FOR = { towel = "mud", brush = "dust", dryer = "wet", comb = "ruffled" }
Care.FREQUENCY = { off = 0, low = 0.5, normal = 1, high = 1.6 }
Care.MAX = 255
Care.MAX_MARKS = 3

-- per-mark base chance; facts raise them
local BASE = { mud = 0.12, dust = 0.10, wet = 0.05, ruffled = 0.22 }
local RAISED = { mud = 0.55, dust = 0.50, wet = 0.60, ruffled = 0.22 }
-- decal radius in body units, by kind
local RADIUS = { mud = 0.22, dust = 0.16, wet = 0.14, ruffled = 0.18 }
-- how many decals one roll of a kind places
local COUNT = { mud = 2, dust = 3, wet = 2, ruffled = 1 }

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
Care.clamp = clamp

function Care.clamp255(v) return clamp(math.floor(v + 0.5), 0, Care.MAX) end

-- facts: { damaged, wild, grass, water, rain, foeTypes = { "WATER", ... } }
local function chanceFor(kind, facts)
  facts = facts or {}
  if kind == "mud" then return facts.damaged and RAISED.mud or BASE.mud end
  if kind == "dust" then return (facts.wild and facts.grass) and RAISED.dust or BASE.dust end
  if kind == "wet" then
    local foeWater = false
    for _, t in ipairs(facts.foeTypes or {}) do
      if tostring(t):upper() == "WATER" then foeWater = true end
    end
    return (facts.water or facts.rain or foeWater) and RAISED.wet or BASE.wet
  end
  return BASE.ruffled
end
Care.chanceFor = chanceFor

-- a point inside the unit ellipse, uniform by area
local function bodyPoint(rng)
  local a = rng() * 2 * math.pi
  local r = math.sqrt(rng()) * 0.85
  return math.cos(a) * r, math.sin(a) * r
end

-- Roll the marks a finished battle leaves. `frequency` is a Care.FREQUENCY
-- key or a number; `rng` returns [0, 1). At most MAX_MARKS kinds, the most
-- likely kinds kept when more than that come up.
function Care.roll(facts, frequency, rng)
  rng = rng or math.random
  local scale = type(frequency) == "number" and frequency or Care.FREQUENCY[frequency or "normal"] or 1
  if scale <= 0 then return {} end
  local hits = {}
  for _, kind in ipairs(Care.MARKS) do
    local p = clamp(chanceFor(kind, facts) * scale, 0, 0.95)
    if rng() < p then hits[#hits + 1] = { kind = kind, p = p } end
  end
  table.sort(hits, function(a, b) return a.p > b.p end)
  local marks = {}
  for i = 1, math.min(#hits, Care.MAX_MARKS) do
    local kind = hits[i].kind
    for _ = 1, COUNT[kind] do
      local x, y = bodyPoint(rng)
      marks[#marks + 1] = { kind = kind, x = x, y = y, r = RADIUS[kind], amount = 1, seed = rng() }
    end
  end
  return marks
end

-- Wear down every live mark the right tool touches. (x, y) is the stylus in
-- body space, `distance` the stroke length since the last call in body
-- units, `rate` how much amount one body-unit of stroke removes.
-- Returns the amount removed and a list of marks that just finished.
function Care.rub(marks, tool, x, y, distance, rate)
  local kind = Care.MARK_FOR[tool]
  if not kind or distance <= 0 then return 0, {} end
  rate = rate or 1.2
  local removed, finished = 0, {}
  for _, m in ipairs(marks) do
    if m.kind == kind and m.amount > 0 then
      local dx, dy = x - m.x, y - m.y
      if dx * dx + dy * dy <= (m.r * 1.35) ^ 2 then
        local before = m.amount
        m.amount = clamp(m.amount - distance * rate, 0, 1)
        removed = removed + (before - m.amount)
        if m.amount <= 0 then finished[#finished + 1] = m end
      end
    end
  end
  return removed, finished
end

function Care.allClean(marks)
  for _, m in ipairs(marks or {}) do
    if m.amount > 0 then return false end
  end
  return true
end

function Care.remaining(marks, kind)
  local n = 0
  for _, m in ipairs(marks or {}) do
    if m.amount > 0 and (kind == nil or m.kind == kind) then n = n + 1 end
  end
  return n
end

-- ------- rewards for care (added to the Amie meters)

Care.CLEAN_ENJOYMENT = 15
Care.CLEAN_AFFECTION = 2
function Care.rewardClean(meters)
  meters.enjoyment = Care.clamp255((meters.enjoyment or 0) + Care.CLEAN_ENJOYMENT)
  meters.affection = Care.clamp255((meters.affection or 0) + Care.CLEAN_AFFECTION)
end

Care.CURE_AFFECTION = 4
function Care.rewardCure(meters)
  meters.affection = Care.clamp255((meters.affection or 0) + Care.CURE_AFFECTION)
  meters.enjoyment = Care.clamp255((meters.enjoyment or 0) + 5)
end

-- what a Pokemon still needs: a short list the prompt and tray read
function Care.needs(marks, status)
  local out = {}
  local seen = {}
  for _, m in ipairs(marks or {}) do
    if m.amount > 0 and not seen[m.kind] then
      seen[m.kind] = true
      out[#out + 1] = m.kind
    end
  end
  if status then out[#out + 1] = "status" end
  return out
end

return Care
