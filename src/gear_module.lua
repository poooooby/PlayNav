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
      "EV SUPER TRAINING.",
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
        ["EV SUPER TRAINING."] = "EV-SUPERTRAINING.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Schlage Sandsäcke und lass Ballon-Bots platzen.",
        ["POWERED BY THE PLAYNAV MOD."] = "Eine PlayNav-App.",
      },
      es = {
        ["SUPER TRAINING"] = "SUPERENTRENAMIENTO",
        ["TRAINING"] = "ENTRENAMIENTO",
        ["EV SUPER TRAINING."] = "SUPERENTRENAMIENTO DE EV.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Golpea sacos de boxeo y revienta robots globo.",
        ["POWERED BY THE PLAYNAV MOD."] = "Una aplicación de PlayNav.",
      },
      fr = {
        ["SUPER TRAINING"] = "SUPER-ENTRAÎNEMENT",
        ["TRAINING"] = "ENTRAÎNEMENT",
        ["EV SUPER TRAINING."] = "SUPER-ENTRAÎNEMENT des EV.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Frappe les sacs de frappe et éclate les robots ballons.",
        ["POWERED BY THE PLAYNAV MOD."] = "Une application PlayNav.",
      },
      it = {
        ["SUPER TRAINING"] = "SUPERALLENAMENTO",
        ["TRAINING"] = "ALLENAMENTO",
        ["EV SUPER TRAINING."] = "SUPERALLENAMENTO EV.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Colpisci i sacchi da allenamento e fai scoppiare i robot palloncino.",
        ["POWERED BY THE PLAYNAV MOD."] = "Un'app di PlayNav.",
      },
      ja = {
        ["SUPER TRAINING"] = "スーパートレーニング",
        ["TRAINING"] = "トレーニング",
        ["EV SUPER TRAINING."] = "努力値スーパートレーニング。",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "サンドバッグを叩いて、風船ロボットを割ろう。",
        ["POWERED BY THE PLAYNAV MOD."] = "PlayNav提供のアプリ。",
      },
    },
  }
end
