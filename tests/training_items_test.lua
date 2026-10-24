-- Super Training's items (src/training/items.lua, data/training_items.lua) and the prize ids
-- (src/training/host.lua itemId), headless: another mod's copy of one of ours wins - a stone
-- by its plain id, a Wing by its later Feather name - and keeps its own use; the bag text is
-- in Gen 3's own shape; an engine item name resolves through the game's version.
-- Run from the engine root: luajit mods/play_nav/tests/training_items_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local data = loadFile("mods/play_nav/data/training_items.lua")

-- the bag text: at most three lines of at most 19 letters (Emerald's own width)
do
  local bad = {}
  for _, def in ipairs(data) do
    local n = 0
    for line in (def.description .. "\n"):gmatch("(.-)\n") do
      n = n + 1
      -- (letters, not bytes: "é" is two)
      local len = #line:gsub("[\128-\191]", "")
      if len > 19 then bad[#bad + 1] = def.slug .. ": " .. line end
    end
    if n > 3 then bad[#bad + 1] = def.slug .. ": " .. n .. " lines" end
  end
  T.check(#bad == 0, "every description fits the bag's three lines of 19 " .. table.concat(bad, "; "))
end

-- a fake registry with another mod's items in it
local function makeItems(others)
  local reg = { items = {} }
  function reg:get(id) return self.items[id] end
  -- (as the engine's: a second record under an id is refused)
  function reg:register(id, rec)
    if self.items[id] then error("items already registered: " .. id) end
    self.items[id] = rec
  end
  for id, index in pairs(others or {}) do reg.items[id] = { id = id, index = index } end
  local wrapped
  local given = {}
  local mod = {
    generation = 3, content = { items = reg },
    hooks = { wrap = function(_, name, fn) if name == "item.use" then wrapped = fn end end },
    log = { info = function() end, warn = function() end },
  }
  local host = {
    canGiveItem = function() return true end,
    giveItem = function(index, qty) given[#given + 1] = index; return true end,
  }
  local Rules = { N = { ITEMS = { WING_EV = 1 } }, STAT_LABEL = {} }
  local copy = {}
  for i, d in ipairs(data) do local c = {}; for k, v in pairs(d) do c[k] = v end; copy[i] = c end
  local I = loadFile("mods/play_nav/src/training/items.lua")(mod, { host = host, Rules = Rules, data = copy })
  I.install()
  return I, wrapped, given
end

-- alone: our own copies
do
  local I = makeItems()
  T.eq(I.index("health-wing"), 400, "alone, the Health Wing is ours (400)")
  T.eq(I.index("dusk-stone"), 407, "...the Dusk Stone ours (407)")
end

-- National Dex's stones, a Wing by its Gen 9 name, another by its old one
do
  local I, use, given = makeItems({ DUSK_STONE = 902, HEALTH_FEATHER = 950, SWIFT_WING = 951 })
  T.eq(I.index("dusk-stone"), 902, "another mod's DUSK_STONE wins")
  T.eq(I.index("health-wing"), 950, "...its HEALTH_FEATHER stands for our Health Wing")
  T.eq(I.index("swift-wing"), 951, "...its SWIFT_WING (taken first: ours refused) for our Swift Wing")
  T.eq(I.index("muscle-wing"), 401, "...the rest stay ours")
  T.check(I.give("health-wing", 1) and given[#given] == 950, "a prize Health Wing is that mod's item")
  -- its use is that mod's: our hook passes it on; our own copy still ours
  local passed = false
  use(function() passed = true; return true end, nil, nil, 950, 1, nil)
  T.check(passed, "...used, that mod's item goes to that mod (our hook passes it on)")
  passed = false
  use(function() passed = true; return true end, nil, nil, 400, 1, nil)
  T.check(not passed, "...our own Health Wing (400) is still ours to use")
end

-- a prize named by the engine ("ITEM_STARDUST") resolves through the game's version
do
  local Host = loadFile("mods/play_nav/src/training/host.lua")
  local H = Host({ game = {} }, { available = function() return true end })
  if H.Constants and H.Constants.of then
    H.gameVersion = function() return "emerald" end
    T.eq(H.itemId("ITEM_STARDUST"), 108, "ITEM_STARDUST is item 108 in Emerald (mod.game is not a version)")
    T.eq(H.itemId("ITEM_HARD_STONE"), 204, "...ITEM_HARD_STONE 204")
    H.gameVersion = function() return "firered" end
    T.eq(H.itemId("ITEM_STARDUST"), 108, "...and in FireRed")
  else
    T.check(true, "the engine's constants are not loadable here")
  end
end

T.finish("play_nav training items")
