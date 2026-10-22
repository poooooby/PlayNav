-- Which bytes of the card image a recipe row depends on, as a key into
-- data/oras_fingerprints.lua: a whole RomFS file for the sound kinds (a
-- stream is decoded whole; the sound archive is read in many ranges), else
-- the one GARC entry / sub-entry blob the row is cut from, as read (before
-- LZ). Shared by src/import/extract.lua and tools/oras_fingerprints.lua.

local F = {}

F.WHOLE = { stream = true, sfx = true, song = true }

function F.key(item)
  if F.WHOLE[item.kind] then return item.archive end
  return ("%s:%d:%d"):format(item.archive, item.entry or 0, item.sub or 0)
end

-- the reason a row carries when its bytes differ; extract.lua counts these
F.DIFFERS = "fingerprint: differs from Alpha Sapphire (USA) Rev 2"
F.MISSING = "fingerprint: none recorded for this row"

return F
