-- PlayNav's Kanto Gear store spec (src/gear_module.lua): well-formed against the
-- Gear's third-party module contract, without needing Kanto Gear or the engine.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local make = assert(loadfile("mods/play_nav/src/gear_module.lua"))()
local opened, shownNow = 0, false
local spec = make({
  open = function() opened = opened + 1 return true end,
  shown = function() return shownNow end,
})

T.eq(spec.id, "super_training", "the id")
T.check(spec.id:match("^[a-z][a-z0-9_]*$") ~= nil, "...in the hook's format")
T.check(type(spec.label) == "string" and #spec.label <= 20, "the label fits the Gear's limit")
T.eq(type(spec.category), "string", "the category")
T.check(type(spec.description) == "table" and #spec.description >= 1 and #spec.description <= 3,
  "1 to 3 description lines")

T.eq(#spec.icon.rows, 24, "the glove is 24 rows")
local clean = true
for _, row in ipairs(spec.icon.rows) do
  if #row ~= 24 then clean = false end
  for ch in row:gmatch("[^.o]") do
    if type(spec.icon.pal[ch]) ~= "string" or not spec.icon.pal[ch]:match("^%x%x%x%x%x%x$") then clean = false end
  end
end
T.check(clean, "...each row 24 wide, every colour a hex entry in the palette")

local ACCENTS = { blue = true, amber = true, red = true, green = true, slate = true }
T.check(ACCENTS[spec.accent] == true, "the accent is one the Gear knows")

T.eq(spec.available({ gen3 = true }), true, "available on a Gen 3 bind")
T.eq(spec.available({ gen3 = false }), false, "...not elsewhere")
T.eq(spec.available(nil), false, "...and never without a context")
T.eq(spec.open(), true, "open calls through")
T.eq(opened, 1, "...once")
T.eq(spec.shown(), false, "shown follows the surface")
shownNow = true
T.eq(spec.shown(), true, "...both ways")

local keys = { spec.label, spec.category }
for _, line in ipairs(spec.description) do keys[#keys + 1] = line end
for _, lang in ipairs({ "de", "es", "fr", "it", "ja" }) do
  local entries = spec.translations[lang]
  T.check(type(entries) == "table", lang .. " translations present")
  for _, key in ipairs(keys) do
    T.check(type(entries[key]) == "string" and entries[key] ~= "", lang .. " covers: " .. key)
  end
end

T.finish("play_nav gear module")
