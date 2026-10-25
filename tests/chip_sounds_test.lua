-- PlayNav's own sound effects (data/chip_sounds.lua) on the chip synth (src/chipsynth.lua):
-- every effect Super Training's and Pokemon-Amie's maps name is made, each at its peak, the
-- steady ones four seconds long. Set CHIP_OUT=<dir> to also write the WAVs for a listen. Run
-- from the engine root:
--   luajit mods/play_nav/tests/chip_sounds_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function module(path)
  local f = assert(io.open("mods/play_nav/" .. path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))()
end
local Synth = module("src/chipsynth.lua")
local out = os.getenv("CHIP_OUT")

local effects = module("data/chip_sounds.lua")
local wanted = {}
local function want(v)
  if type(v) == "string" and v:match("^se/") then wanted[v] = true
  elseif type(v) == "table" then for _, x in pairs(v) do want(x) end end
end
for _, v in pairs(module("data/training_sounds.lua")) do want(v) end
for k, v in pairs(module("data/amie_sounds.lua")) do if k ~= "EVIDENCE" then want(v) end end
for id in pairs(wanted) do T.check(effects[id] ~= nil, id .. " has a sound of PlayNav's own") end
local STEADY = { ["se/sp_024"] = true, ["se/sp_034"] = true, ["se/sp_041"] = true, ["se/kw_addscore"] = true,
  ["se/rk_rain"] = true }
for id, def in pairs(effects) do
  local buf, n = Synth.effect(def)
  local peak = 0
  for i = 1, n do peak = math.max(peak, math.abs(buf[i])) end
  T.check(math.abs(peak - (def.peak or 0.75)) < 1e-6, ("%s: at its peak (%.2f)"):format(id, peak))
  local secs = n / Synth.RATE
  if STEADY[id] then T.check(secs >= 3.99, ("%s: four steady seconds (%.2f)"):format(id, secs))
  else T.check(secs > 0.02 and secs < 4, ("%s: a short effect (%.2f s)"):format(id, secs)) end
  if out then
    local f = io.open(out .. "/" .. id:gsub("^se/", "se_") .. ".wav", "wb")
    if f then f:write(Synth.wavMono(buf, n)); f:close() end
  end
end

T.finish("play_nav chip sounds")
