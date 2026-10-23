-- Super Training's music as the game's own songs (src/training/music.lua M.GAME_SONGS): per
-- game, the song each track plays. FireRed / LeafGreen and Emerald play the same songs:
-- Emerald carries FireRed's whole soundtrack as MUS_RG_*. Ruby and Sapphire play Hoenn songs
-- the two share. The title (sp_gamestart) is the regimen's song from its start. The picker
-- (sp_menu) is not here: it plays the card image's track, else assets/stmenu.ogg
-- (src/assets.lua A.ownMusic), on PlayNav's own player.

local FRLG = {
  ["bgm/sp_gamestart"] = "TRAINER_TOWER",
  ["bgm/sp_stage"] = "TRAINER_TOWER",    -- a regimen: Trainer Tower's timed challenge
  ["bgm/sp_stage_02"] = "VS_GYM_LEADER", -- a secret regimen
  ["bgm/sp_clear"] = "VICTORY_TRAINER",
  ["bgm/sp_gameover"] = "SLOW_PALLET",
}

local function named(set, prefix)
  local out = {}
  for id, song in pairs(set) do out[id] = prefix .. song end
  return out
end

return {
  frlg = named(FRLG, "MUS_"),
  emerald = named(FRLG, "MUS_RG_"),
  rs = {
    ["bgm/sp_gamestart"] = "MUS_B_TOWER",
    ["bgm/sp_stage"] = "MUS_B_TOWER",
    ["bgm/sp_stage_02"] = "MUS_VS_GYM_LEADER",
    ["bgm/sp_clear"] = "MUS_VICTORY_TRAINER",
    ["bgm/sp_gameover"] = "MUS_OLDALE",
  },
}
