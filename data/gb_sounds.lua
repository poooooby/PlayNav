-- PlayNav's engine sound stand-ins on the Game Boy games. Amie and Super Training name the
-- Gen 3 effect they stand in with (host.playSe("SE_SELECT"), the haptics key on the same
-- names); on Gen 1 / 2 the host plays the effect here instead, by the game's own label
-- (data.audio.sfx). A list = the first the game has. Missing = silent (its haptic still felt).

return {
  gen1 = {
    SE_SELECT = "Press_AB",
    SE_SUCCESS = "Get_Item1",
    SE_PIN = "Tink",
    SE_NOT_EFFECTIVE = "Not_Very_Effective",
    SE_FAILURE = "Denied",
    SE_BALL_BOUNCE_1 = "Collision",
    SE_SHOP = "Purchase",
    SE_SHINY = "Shooting_Star",
    SE_M_SCARY_FACE = "Battle_2F",
    SE_M_REFLECT = "Battle_2C",
    SE_M_DOUBLE_TEAM = "Teleport_Exit1",
    SE_ICE_BREAK = "Battle_29",
    SE_EXP = "Level_Up",
    SE_BALLOON_RED = "Ball_Poof",
  },
  gen2 = {
    SE_SELECT = "Sfx_ReadText2",
    SE_SUCCESS = "Sfx_Item",
    SE_PIN = "Sfx_Tally",
    SE_NOT_EFFECTIVE = "Sfx_NotVeryEffective",
    SE_FAILURE = "Sfx_Wrong",
    SE_BALL_BOUNCE_1 = "Sfx_BallBounce",
    SE_SHOP = "Sfx_Transaction",
    SE_SHINY = "Sfx_Shine",
    SE_M_SCARY_FACE = "Sfx_MeanLook",
    SE_M_REFLECT = "Sfx_Protect",
    SE_M_DOUBLE_TEAM = "Sfx_WarpFrom",
    SE_ICE_BREAK = "Sfx_GlassTing",
    SE_EXP = "Sfx_ExpBar",
    SE_BALLOON_RED = "Sfx_BallPoof",
  },
}
