-- Declared state machines over fields that already exist (`s.mode`, `st.phase`, ...).
--
-- A machine names its states and the transitions between them. `enter` writes the field as a
-- plain assignment would, so every reader keeps working; it also checks the declared edge and
-- keeps a short history. An undeclared edge or an unknown state is reported once and the
-- transition still happens: a missing declaration costs a log line, never behaviour.
--
--   local M = Fsm.define("amie.mode", {
--     states = { "home", "play", "decorate", "game" },
--     edges = { home = { "play", "decorate" }, play = { "home", "game" }, ["*"] = { "home" } },
--   })
--   M:enter(session, "mode", "play", "start")
--
-- An edge from "*" is allowed out of every state. A state may also be entered from nil (the
-- first write). Groups name sets of states that several places test ("active phases").
local Fsm = {}

Fsm.registry = {}
Fsm.HISTORY = 16
-- replaced by main with mod.log:warn
Fsm.warn = function() end

local Machine = {}
Machine.__index = Machine

local function set(list)
  local out = {}
  for _, v in ipairs(list or {}) do out[v] = true end
  return out
end

function Fsm.define(name, spec)
  local m = setmetatable({
    name = name,
    states = set(spec.states),
    order = spec.states or {},
    edges = {},
    groups = {},
    history = {},
    reported = {},
  }, Machine)
  for from, list in pairs(spec.edges or {}) do m.edges[from] = set(list) end
  for g, list in pairs(spec.groups or {}) do m.groups[g] = set(list) end
  Fsm.registry[name] = m
  return m
end

local function report(m, key, fmt, ...)
  if m.reported[key] then return end
  m.reported[key] = true
  m.violations = (m.violations or 0) + 1
  Fsm.warn("state machine %s: " .. fmt, m.name, ...)
end

-- true when `from` -> `to` is declared (or `from` is nil: the first write)
function Machine:allows(from, to)
  if from == nil then return true end
  if from == to then return true end
  local e = self.edges[from]
  if e and e[to] then return true end
  local any = self.edges["*"]
  return any ~= nil and any[to] == true
end

function Machine:enter(obj, field, to, why)
  local from = obj[field]
  if not self.states[to] then
    report(self, "state:" .. tostring(to), "unknown state %s", tostring(to))
  elseif not self:allows(from, to) then
    report(self, tostring(from) .. ">" .. tostring(to), "undeclared transition %s -> %s%s",
      tostring(from), tostring(to), why and (" (" .. tostring(why) .. ")") or "")
  end
  obj[field] = to
  local h = self.history
  h[#h + 1] = { from = from, to = to, why = why }
  if #h > Fsm.HISTORY then table.remove(h, 1) end
  return to
end

-- is obj[field] one of the named states or groups?
function Machine:is(obj, field, ...)
  local cur = obj[field]
  for i = 1, select("#", ...) do
    local want = select(i, ...)
    if cur == want then return true end
    local g = self.groups[want]
    if g and g[cur] then return true end
  end
  return false
end

function Machine:inGroup(group, state)
  local g = self.groups[group]
  return g ~= nil and g[state] == true
end

-- Mermaid text of the declared machine, states and edges in a fixed order
function Machine:describe()
  local lines = { "stateDiagram-v2" }
  local froms = {}
  for f in pairs(self.edges) do froms[#froms + 1] = f end
  table.sort(froms)
  for _, f in ipairs(froms) do
    local tos = {}
    for t in pairs(self.edges[f]) do tos[#tos + 1] = t end
    table.sort(tos)
    for _, t in ipairs(tos) do lines[#lines + 1] = ("  %s --> %s"):format(f == "*" and "[*]" or f, t) end
  end
  return table.concat(lines, "\n")
end

-- plain data for probes and agents: states, edges, groups, last transitions, violation count
function Fsm.snapshot()
  local out = {}
  for name, m in pairs(Fsm.registry) do
    local edges = {}
    for f, tos in pairs(m.edges) do
      local list = {}
      for t in pairs(tos) do list[#list + 1] = t end
      table.sort(list)
      edges[f] = list
    end
    local hist = {}
    for i, h in ipairs(m.history) do hist[i] = tostring(h.from) .. ">" .. h.to end
    out[name] = { states = m.order, edges = edges, history = hist, violations = m.violations or 0 }
  end
  return out
end

-- `enter` for code that may run without a machine (fake hosts): plain assignment then
function Fsm.enter(m, obj, field, to, why)
  if m then return m:enter(obj, field, to, why) end
  obj[field] = to
  return to
end

return Fsm
