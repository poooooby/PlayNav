-- The package excludes every test and tool: .modkitignore must list each file under tests/
-- and tools/ by its exact path (modkit matches whole paths, not folders).
-- Run from the engine root: luajit mods/play_nav/tests/release_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local ignored = {}
for line in io.lines("mods/play_nav/.modkitignore") do
  line = line:gsub("%s+$", "")
  if line ~= "" and not line:match("^#") then ignored[line] = true end
end
local p = io.popen('git -C mods/play_nav ls-files tests tools')
local missing = {}
for f in p:lines() do
  if not ignored[f] then missing[#missing + 1] = f end
end
p:close()
T.eq(#missing, 0, "every test and tool is kept out of the package (" .. table.concat(missing, ", ") .. ")")
T.check(ignored["CLAUDE.md"], "CLAUDE.md stays out")
T.finish("play_nav release")
