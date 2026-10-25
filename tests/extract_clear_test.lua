-- CLEAR EXTRACTED ART (src/import/extract.lua E.clear): every file the import wrote goes,
-- the manifest first, and the cache reads as incomplete afterwards. A fake mod.cache.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local files = {}
local deletes = {}
local cache = {
  read = function(_, rel) return files[rel] end,
  write = function(_, rel, bytes) files[rel] = bytes return true end,
  delete = function(_, rel)
    deletes[#deletes + 1] = rel
    if files[rel] == nil then return false end
    files[rel] = nil
    return true
  end,
}
local logs = {}
local mod = {
  cache = cache,
  job = { cancel = function() end, available = function() return true end },
  log = { info = function(_, ...) logs[#logs + 1] = string.format(...) end, warn = function() end },
  imports = { info = function() return { size = 1 } end },
}

local recipe = {
  version = 7, source = { md5 = "abc", import = "oras_cci" },
  assets = {
    { id = "ui/btn_play" },                                  -- an image (CLIM)
    { id = "fx/streamline02f", kind = "bch" },               -- an image (BCH texture)
    { id = "text/amie_main", kind = "text" },
    { id = "bgm/sp_menu", kind = "stream" },
    { id = "se/sp_001", kind = "sfx" },
    { id = "lyt/st_aim", kind = "files" },
    { id = "st3d/stadium", kind = "model" },                 -- a 3D model (BCH)
  },
}
local refreshed = 0
local assets = { refresh = function() refreshed = refreshed + 1 end }

local make = assert(loadfile("mods/play_nav/src/import/extract.lua"))()
local E = make(mod, { recipe = recipe, assets = assets })

-- a complete cache, as a finished run leaves it
files["oras/manifest.lua"] = 'return { version = 7, source = { md5 = "abc" }, assets = { ["ui/btn_play"] = { w = 1, h = 1 } } }'
files["oras/png/ui/btn_play.png"] = "png"
files["oras/png/fx/streamline02f.png"] = "png"
files["oras/raw/ui/btn_play.rgba"] = "leftover"
files["oras/text/amie_main.lua"] = "return {}"
files["oras/bgm/sp_menu.wav"] = "wav"
files["oras/bgm/sp_menu.lua"] = "return {}"
files["oras/se/sp_001.wav"] = "wav"
files["oras/lyt/st_aim/lower.bclyt"] = "lyt"
files["oras/lyt/st_aim/lower_active.bclan"] = "clan"
files["oras/lyt/st_aim/index.lua"] = 'return { "lower.bclyt", "lower_active.bclan" }'
files["oras/model/st3d_stadium.lua"] = "return { meshes = {} }"
files["unrelated/keep.txt"] = "mine"

T.eq(E.cacheComplete(), true, "a finished cache counts as complete")
local removed = E.clear()
T.eq(deletes[1], "oras/manifest.lua", "the manifest goes first")
T.eq(removed, 12, "every file the import wrote is removed")
local left = {}
for rel in pairs(files) do left[#left + 1] = rel end
T.eq(#left, 1, "only files the import did not write remain")
T.eq(files["unrelated/keep.txt"], "mine", "...untouched")
T.eq(E.cacheComplete(), false, "the cache reads as incomplete afterwards")
T.check(E.state == "idle" or E.state == "absent", "the extractor is ready to begin again (" .. tostring(E.state) .. ")")
T.eq(refreshed >= 1, true, "the loaded art is dropped")

-- clearing an empty cache is harmless
deletes = {}
T.eq(E.clear(), 0, "a second clear removes nothing")
T.eq(E.cacheComplete(), false, "...and stays incomplete")

-- a layout pack from before the index existed: its files stay (re-extraction overwrites)
files["oras/manifest.lua"] = 'return { version = 7, source = { md5 = "abc" }, assets = {} }'
files["oras/lyt/st_aim/lower.bclyt"] = "lyt"
E.clear()
T.eq(files["oras/manifest.lua"], nil, "an older cache still loses its manifest")

T.finish("play_nav extract clear")
