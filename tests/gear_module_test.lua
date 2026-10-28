-- NaviPlay's Kanto Gear store specs (src/gear_module.lua): Super Training and Pokemon-Amie,
-- each well-formed against the Gear's third-party module contract, without needing Kanto
-- Gear or the engine.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local make = assert(loadfile("mods/play_nav/src/gear_module.lua"))()
local ACCENTS = { blue = true, amber = true, red = true, green = true, slate = true }

local function checkSpec(app, id)
  local opened, shownNow = 0, false
  local spec = make({
    app = app,
    open = function() opened = opened + 1 return true end,
    shown = function() return shownNow end,
  })
  local p = id .. ": "
  T.eq(spec.id, id, p .. "the id")
  T.check(spec.id:match("^[a-z][a-z0-9_]*$") ~= nil, p .. "...in the hook's format")
  T.check(type(spec.label) == "string" and spec.label ~= "" and #spec.label <= 20, p .. "the label fits the Gear's limit")
  T.check(type(spec.category) == "string" and spec.category ~= "", p .. "the category")
  T.check(type(spec.description) == "table" and #spec.description >= 1 and #spec.description <= 3,
    p .. "1 to 3 description lines")

  T.eq(#spec.icon.rows, 24, p .. "the icon is 24 rows")
  local clean, painted = true, 0
  for _, row in ipairs(spec.icon.rows) do
    if #row ~= 24 then clean = false end
    for ch in row:gmatch("[^.o]") do
      painted = painted + 1
      if type(spec.icon.pal[ch]) ~= "string" or not spec.icon.pal[ch]:match("^%x%x%x%x%x%x$") then clean = false end
    end
  end
  T.check(clean, p .. "...each row 24 wide, every colour a hex entry in the palette")
  T.check(painted > 100, p .. "...and it has a picture")

  T.check(ACCENTS[spec.accent] == true, p .. "the accent is one the Gear knows")

  T.eq(spec.available({ gen3 = true }), true, p .. "available on a Gen 3 bind")
  T.eq(spec.available({ gen3 = false, generation = 1 }), true, p .. "...on Gen 1")
  T.eq(spec.available({ gen3 = false, generation = 2 }), true, p .. "...and Gen 2")
  T.eq(spec.available({ gen3 = false }), false, p .. "...not on a bind without a generation")
  T.eq(spec.available(nil), false, p .. "...and never without a context")
  T.eq(spec.open(), true, p .. "open calls through")
  T.eq(opened, 1, p .. "...once")
  T.eq(spec.shown(), false, p .. "shown follows the surface")
  shownNow = true
  T.eq(spec.shown(), true, p .. "...both ways")

  local keys = { spec.label, spec.category }
  for _, line in ipairs(spec.description) do keys[#keys + 1] = line end
  for _, lang in ipairs({ "de", "es", "fr", "it", "ja" }) do
    local entries = spec.translations[lang]
    T.check(type(entries) == "table", p .. lang .. " translations present")
    for _, key in ipairs(keys) do
      T.check(type(entries[key]) == "string" and entries[key] ~= "", p .. lang .. " covers: " .. key)
    end
  end
  return spec
end

local training = checkSpec(nil, "super_training")
local amie = checkSpec("amie", "pokemon_amie")
T.eq(checkSpec("training", "super_training").label, training.label, "app \"training\" is Super Training too")
T.check(training.id ~= amie.id, "the two apps have their own ids")
T.check(training.label ~= amie.label, "...and their own labels")

T.finish("play_nav gear module")
