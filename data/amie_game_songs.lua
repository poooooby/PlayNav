-- Pokemon-Amie's minigame music as the game's own songs (src/training/music.lua M.GAME_SONGS,
-- main's amieMusic): per game, the song each minigame plays. FireRed / LeafGreen and Emerald
-- play the same songs (Emerald carries FireRed's as MUS_RG_*: its own link minigames play them);
-- Ruby and Sapphire play Hoenn songs the two share. Berry Picker's quicker renders are the
-- same song.

local FRLG = {
  ["bgm/kw_game01"] = "BERRY_PICK",       -- Berry Picker: Dodrio Berry Picking's
  ["bgm/kw_game01_fast"] = "BERRY_PICK",
  ["bgm/kw_game01_faster"] = "BERRY_PICK",
  ["bgm/kw_game02"] = "POKE_JUMP",        -- Head It: Pokemon Jump's
  ["bgm/kw_game03"] = "TEACHY_TV_SHOW",   -- Tile Puzzle
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
    ["bgm/kw_game01"] = "MUS_CONTEST",
    ["bgm/kw_game01_fast"] = "MUS_CONTEST",
    ["bgm/kw_game01_faster"] = "MUS_CONTEST",
    ["bgm/kw_game02"] = "MUS_CYCLING",
    ["bgm/kw_game03"] = "MUS_TRICK_HOUSE",
  },
  -- the Game Boy games (src/refresh/host_gb.lua)
  gen1 = {
    ["bgm/kw_game01"] = "Music_GameCorner",
    ["bgm/kw_game01_fast"] = "Music_GameCorner",
    ["bgm/kw_game01_faster"] = "Music_GameCorner",
    ["bgm/kw_game02"] = "Music_BikeRiding",
    ["bgm/kw_game03"] = "Music_Celadon",
  },
  gen2 = {
    ["bgm/kw_game01"] = "Music_BugCatchingContest",
    ["bgm/kw_game01_fast"] = "Music_BugCatchingContest",
    ["bgm/kw_game01_faster"] = "Music_BugCatchingContest",
    ["bgm/kw_game02"] = "Music_Bicycle",
    ["bgm/kw_game03"] = "Music_NationalPark",
  },
}
