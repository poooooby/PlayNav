-- Declared state machines (src/fsm.lua): edges, unknown states, warn-once, history, groups,
-- the plain-assignment fallback, and that the session choke points stay the only writers.
-- Run from the engine root: luajit mods/play_nav/tests/fsm_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local Fsm = loadFile("mods/play_nav/src/fsm.lua")
local warnings = {}
Fsm.warn = function(fmt, ...) warnings[#warnings + 1] = fmt:format(...) end

local M = Fsm.define("test.mode", {
  states = { "a", "b", "c" },
  edges = { a = { "b" }, b = { "c" }, ["*"] = { "a" } },
  groups = { live = { "b", "c" } },
})

local o = {}
M:enter(o, "mode", "a", "first")
T.eq(o.mode, "a", "first write from nil is allowed")
T.eq(#warnings, 0, "no warning for a declared first write")
M:enter(o, "mode", "b"); M:enter(o, "mode", "c"); M:enter(o, "mode", "a")
T.eq(#warnings, 0, "declared edges and the wildcard stay quiet")
T.eq(o.mode, "a", "the field is a plain value")

M:enter(o, "mode", "c", "skip")
T.eq(o.mode, "c", "an undeclared edge still transitions")
T.eq(#warnings, 1, "an undeclared edge warns")
M:enter(o, "mode", "a"); M:enter(o, "mode", "c")
T.eq(#warnings, 1, "the same edge warns once")
M:enter(o, "mode", "zzz")
T.eq(o.mode, "zzz", "an unknown state still transitions")
T.eq(#warnings, 2, "an unknown state warns")
T.eq(M.violations, 2, "violations are counted")

M:enter(o, "mode", "a")
M:enter(o, "mode", "b")
T.check(M:is(o, "mode", "b"), "is() by state")
T.check(M:is(o, "mode", "live"), "is() by group")
T.check(not M:is(o, "mode", "a", "c"), "is() false for other states")
T.check(M:inGroup("live", "c") and not M:inGroup("live", "a"), "inGroup")

for _ = 1, 40 do M:enter(o, "mode", "a") end
T.eq(#M.history, Fsm.HISTORY, "history is a ring")
T.check(Fsm.snapshot()["test.mode"].violations == 2, "snapshot reports violations")
T.check(M:describe():find("a --> b", 1, true) and M:describe():find("[*] --> a", 1, true), "describe lists edges")

local plain = {}
Fsm.enter(nil, plain, "mode", "x")
T.eq(plain.mode, "x", "no machine: plain assignment")

-- every raw write to an adopted field goes through its choke point
local function count(path, pattern)
  local f = assert(io.open(path, "rb"))
  local n = 0
  for line in f:lines() do
    if line:find(pattern) and not line:find("^%s*%-%-") then n = n + 1 end
  end
  f:close()
  return n
end
T.eq(count("mods/play_nav/src/amie/session.lua", "s%.mode%s*=[^=]"), 1,
  "amie session writes s.mode only in the no-machine fallback")

T.finish("play_nav fsm")
