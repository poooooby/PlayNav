-- The ds_touch -> play_nav carry-over: save data copied once over the fresh defaults, the
-- old bucket kept, options copied only where the player set nothing under the new id.
-- Run from the engine root: luajit mods/play_nav/tests/rename_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local logs = {}
local fakeMod = { id = "play_nav", log = { info = function(_, ...) logs[#logs + 1] = string.format(...) end, warn = function() end } }
local M = loadFile("mods/play_nav/src/rename.lua")(fakeMod, "ds_touch")

-- save data
do
  local modData = {
    ds_touch = { schema = 2, mons = { ["1:2"] = { affection = 200 } }, puffs = { "puff/basic_sweet" }, training = { schema = 1 } },
    play_nav = { schema = 2, puffs = { "a", "b", "c" } },   -- the defaults written at load
  }
  T.check(M.saveData(modData), "the old bucket is copied")
  T.eq(modData.play_nav.mons["1:2"].affection, 200, "affection carried over")
  T.eq(#modData.play_nav.puffs, 1, "the old puff jar wins over the fresh one")
  T.eq(modData.play_nav.training.schema, 1, "training carried over")
  T.eq(modData.play_nav.renamedFrom, "ds_touch", "marked done")
  T.check(modData.ds_touch ~= nil, "the old bucket stays")
  modData.play_nav.puffs = { "x", "y" }
  T.check(not M.saveData(modData), "a second load does not copy again")
  T.eq(#modData.play_nav.puffs, 2, "...so later progress is kept")
  local fresh = { ds_touch = { schema = 2 } }
  T.check(M.saveData(fresh) and fresh.play_nav.schema == 2, "no new bucket yet: one is made")
  T.check(not M.saveData({ play_nav = { schema = 2 } }), "a save that never had ds_touch is left alone")
  T.check(not M.saveData(nil), "no modData: nothing")
end

-- options
do
  local opts = { ds_touch = { display = "split", split_ratio = 50, dev_scratch = true }, play_nav = { display = "off" } }
  T.eq(M.options(opts), 2, "two options copied")
  T.eq(opts.play_nav.display, "off", "a choice made under the new id is kept")
  T.eq(opts.play_nav.split_ratio, 50, "an old choice fills the gap")
  T.eq(M.options(opts), 0, "nothing more the second time")
  T.eq(M.options({}), 0, "no old options: nothing")
end

T.finish("play_nav rename")
