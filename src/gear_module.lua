-- PlayNav in Kanto Gear's Silph Store: the spec for the Gear's third-party module
-- hook (kanto_gear exports.modules.register, api 1). Everything the store shows is
-- PlayNav's own: the engine-drawn boxing glove (the Gear's 24x24 pal/rows pixel
-- format), the words, the translations, and the callbacks main.lua passes in -
-- `open` (the press: the Super Training session, or the PLAYNAV import screen) and
-- `shown` (true while PlayNav's surface is up, so the Gear stands down).
return function(deps)
  return {
    id = "super_training",
    label = "SUPER TRAINING",
    category = "TRAINING",
    description = {
      "EV TRAINING FROM X AND Y.",
      "PUNCH BAGS AND POP BALLOON BOTS.",
      "POWERED BY THE PLAYNAV MOD.",
    },
    -- the boxing glove: red mitt, thumb lobe, white laced cuff
    icon = { pal = { a = "fcded6", b = "f47c64", c = "e04838", d = "a82818",
      e = "ffffff", f = "c0c6d4", g = "8890a0" }, rows = {
      "........................",
      "........................",
      "......oooooooo..........",
      ".....oabbbbbbco.........",
      "....oaabbbbbbbco........",
      "...oaaabbbbbbbbco.......",
      "..oaabbbbbbbbbbbco......",
      "..oabbbbbbbbbbbcco......",
      ".oabbbbbbbbbbbbccco.....",
      ".obbbbbbbbbbbbbccco.....",
      ".obbbbbbbbbbbbbcccoo....",
      ".obbcccccccccccccdoooo..",
      ".obcccccccccccccddbbo...",
      ".occccccccccccccddbcco..",
      ".occccccccccccccddccdo..",
      "..occccccccccccccdddo...",
      "..odccccccccccccdddoo...",
      "...odddddddddddddddo....",
      "....oooooooooooooooo....",
      ".....oeeeeeeeeeeefo.....",
      ".....oegeegeegeeffo.....",
      ".....oeeeeeeeeeeffo.....",
      "......oooooooooooo......",
      "........................",
    } },
    accent = "red",
    available = function(ctx) return ctx ~= nil and ctx.gen3 == true end,
    shown = deps.shown,
    open = deps.open,
    translations = {
      de = {
        ["SUPER TRAINING"] = "SUPERTRAINING",
        ["TRAINING"] = "TRAINING",
        ["EV TRAINING FROM X AND Y."] = "EV-TRAINING AUS X UND Y.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "SANDSÄCKE UND BALLON-BOTS.",
        ["POWERED BY THE PLAYNAV MOD."] = "LÄUFT ÜBER DEN PLAYNAV-MOD.",
      },
      es = {
        ["SUPER TRAINING"] = "SUPERENTRENAMIENTO",
        ["TRAINING"] = "ENTRENAMIENTO",
        ["EV TRAINING FROM X AND Y."] = "EVS COMO EN X E Y.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "SACOS Y ROBOTS GLOBO.",
        ["POWERED BY THE PLAYNAV MOD."] = "FUNCIONA CON EL MOD PLAYNAV.",
      },
      fr = {
        ["SUPER TRAINING"] = "SUPER ENTRAINEMENT",
        ["TRAINING"] = "ENTRAINEMENT",
        ["EV TRAINING FROM X AND Y."] = "EV COMME DANS X ET Y.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "SACS ET ROBOTS BALLONS.",
        ["POWERED BY THE PLAYNAV MOD."] = "VIA LE MOD PLAYNAV.",
      },
      it = {
        ["SUPER TRAINING"] = "SUPERALLENAMENTO",
        ["TRAINING"] = "ALLENAMENTO",
        ["EV TRAINING FROM X AND Y."] = "ALLENA GLI EV COME IN X E Y.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "SACCHI E ROBOT PALLONE.",
        ["POWERED BY THE PLAYNAV MOD."] = "TRAMITE LA MOD PLAYNAV.",
      },
      ja = {
        ["SUPER TRAINING"] = "スパトレ",
        ["TRAINING"] = "トレーニング",
        ["EV TRAINING FROM X AND Y."] = "XYのスパトレをさいげん。",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "サンドバッグとバルーンボット。",
        ["POWERED BY THE PLAYNAV MOD."] = "PLAYNAV MODでうごく。",
      },
    },
  }
end
