-- Which game PlayNav is running on, read once at load: the generation (mod.generation, 1 / 2 /
-- 3), the version ("red" ... "crystal", "ruby" ... "leafgreen") and what follows from it - the
-- top screen's frame, the stats Super Training trains and whether there is a total EV cap.
-- main picks every generation-specific piece (hosts, layers, display path, START menu, battle
-- hooks, items) from this one profile, so nothing of Gen 3's runs on Gen 1 or 2.
--
-- Gen 1 / 2 keep Stat Exp (0..65535 a stat, no total) where Gen 3 keeps EVs: Super Training
-- works in EVs of 0..252 there too, written back as Stat Exp = EV^2 (252 -> 63504, the stat's
-- full +63; src/refresh/host_gb.lua), with no 510 total, and with one Special stat for Sp. Atk
-- and Sp. Def (the games' single Special Stat Exp).

local Gen = {}

Gen.STATS3 = { "hp", "atk", "def", "spa", "spd", "spe" }
Gen.STATS_GB = { "hp", "atk", "def", "spe", "spc" }

local FAMILY = {
  red = "gen1", blue = "gen1", yellow = "gen1", green = "gen1",
  gold = "gen2", silver = "gen2", crystal = "gen2",
  firered = "frlg", leafgreen = "frlg", emerald = "emerald", ruby = "rs", sapphire = "rs",
}

-- the profile for a generation and version (pure; Gen.detect reads them from the engine)
function Gen.profile(gen, version)
  gen = tonumber(gen) or 3
  version = version and tostring(version):lower() or nil
  local p = { gen = gen, version = version, family = version and FAMILY[version] or nil }
  if gen == 3 then
    p.frameW, p.frameH = 240, 160
    p.stats = Gen.STATS3
    p.evTotal = 510
    p.special = false
  else
    p.frameW, p.frameH = 160, 144
    p.stats = Gen.STATS_GB
    p.evTotal = nil
    p.special = true
    p.family = p.family or (gen == 1 and "gen1" or "gen2")
  end
  p.gb = gen ~= 3
  -- the top screen's frame in PlayNav's 240-unit-wide space: the layers draw in 240x160
  -- units; a Game Boy frame (160x144) is 240 units across and 216 tall, the 240x160 band in
  -- its middle (y -28 .. 188)
  if gen == 3 then
    p.frame = { x = 0, y = 0, w = 240, h = 160 }
  else
    local h = 240 * p.frameH / p.frameW
    p.frame = { x = 0, y = (160 - h) / 2, w = 240, h = h }
  end
  return p
end

-- the running game's version string, or nil (src/core/GameVersion; the Gen 3 session's
-- version on Gen 3)
local function versionNow(mod, gen)
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and type(GV) == "table" and GV.get then
    local okV, v = pcall(GV.get)
    if okV and type(v) == "string" and v ~= "" then return v end
  end
  local game = mod and mod.game
  local save = game and game.save
  local v = save and save.version
  if type(v) == "string" then return v end
  return nil
end

function Gen.detect(mod)
  local gen = tonumber(mod and mod.generation) or 3
  return Gen.profile(gen, versionNow(mod, gen))
end

return Gen
