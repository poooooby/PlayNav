-- PlayNav's own copy of the minigames' layouts and clips (data/lyt/*.lua, tools/lyt_data.lua)
-- against the files the extract copied into this machine's cache: the same panes, sizes,
-- colours, groups and keyframes (to 7 figures), every text pane empty. The files load on
-- their own; the comparison skips cleanly without the cache. Run from the engine root:
--   luajit mods/play_nav/tests/lyt_data_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local F = dofile("mods/play_nav/src/lytfile.lua")
local CACHE = "mod_cache/play_nav/oras/lyt/"

local function read(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- a and b equal as data, numbers to 7 significant figures; text panes are empty in b
local function same(a, b, path, skip)
  if type(a) == "number" and type(b) == "number" then
    local d = math.abs(a - b)
    return d <= 1e-6 * math.max(1, math.abs(a)), path
  end
  if type(a) ~= "table" or type(b) ~= "table" then return a == b, path end
  for k, v in pairs(a) do
    if not skip[k] then
      if k == "text" and type(v) == "string" then
        if b[k] ~= "" then return false, path .. ".text" end
      else
        local ok, where = same(v, b[k], path .. "." .. tostring(k), skip)
        if not ok then return false, where end
      end
    end
  end
  return true
end

local SKIP = { parent = true, byName = true }
local packs, compared = 0, 0
for name in io.popen('ls "mods/play_nav/data/lyt"'):lines() do
  local pack = name:match("^(.-)%.lua$")
  if pack then
    packs = packs + 1
    local ok, d = pcall(dofile, "mods/play_nav/data/lyt/" .. name)
    T.check(ok and type(d) == "table" and d.layouts and d.clips, pack .. " loads")
    if ok and type(d) == "table" and read(CACHE .. pack .. "/index.lua") then
      for file, L in pairs(d.layouts) do
        local b = read(CACHE .. pack .. "/" .. file)
        if b then
          local ok2, where = same(assert(F.layout(b)), L, file, SKIP)
          T.check(ok2, pack .. "/" .. file .. " matches the card's" .. (ok2 and "" or (" (" .. tostring(where) .. ")")))
          compared = compared + 1
        end
      end
      for file, C in pairs(d.clips) do
        local b = read(CACHE .. pack .. "/" .. file)
        if b then
          local ok2, where = same(assert(F.clip(b)), C, file, SKIP)
          if not ok2 then T.check(false, pack .. "/" .. file .. " (" .. tostring(where) .. ")") end
          compared = compared + 1
        end
      end
    end
  end
end
T.check(packs >= 15, "the minigames' packs are there (" .. packs .. ")")
print(("compared %d files with the cache%s"):format(compared, compared == 0 and " (no cache: skipped)" or ""))
T.finish("play_nav lyt data")
