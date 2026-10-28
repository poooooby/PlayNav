-- NaviPlay in Kanto Gear's Silph Store: the specs for the Gear's third-party module
-- hook (kanto_gear exports.modules.register, api 1), one an app: Super Training (the
-- default) and Pokemon-Amie (`deps.app = "amie"`). Everything the store shows is
-- NaviPlay's own: the engine-drawn icons (the Gear's 24x24 pal/rows pixel format; `o`
-- is the Gear's outline), the words, the translations, and the callbacks main.lua
-- passes in - `open` (the press: the app's session, or the NAVIPLAY import screen) and
-- `shown` (true while NaviPlay's surface is up, so the Gear stands down).

-- every generation the Gear runs on (its ctx: { edition, generation = 1 | 2 | 3, gen3 })
local function available(ctx)
  return ctx ~= nil and (ctx.gen3 == true or ctx.generation == 1 or ctx.generation == 2 or ctx.generation == 3)
end

local function amie(deps)
  return {
    id = "pokemon_amie",
    label = "POKEAMIE",
    category = "FRIENDSHIP",
    description = {
      "BOND WITH YOUR POKEMON.",
      "PET, FEED AND PLAY MINIGAMES.",
      "POWERED BY THE NAVIPLAY MOD.",
    },
    -- a Poke Puff: cherry, pink frosting in tiers, a speckled cake cup
    icon = { pal = { a = "ffe0ec", b = "f8a0c4", c = "e070a0", d = "b04878",
      r = "e83848", h = "ffffff", s = "a82030", g = "58a838",
      t = "f8e0a8", u = "e0b068", v = "b07838" }, rows = {
      "........................",
      "...........og...........",
      "..........ogo...........",
      ".........orrro..........",
      "........orhrrso.........",
      "........orrrrso.........",
      ".......ooossssooo.......",
      ".....oaaabbbbbbbco......",
      "....oaabbbbbbbbbcco.....",
      "....obbbbbbbbbbbccdo....",
      "...oaaccccccccccccdo....",
      "..oaaabbbbbbbbbbbbbco...",
      ".oaabbbbbbbbbbbbbbbccdo.",
      ".obbbbbbbbbbbbbbbbbccdo.",
      ".odcccccccccccccccccddo.",
      "..ooooooooooooooooooo...",
      "..otttuttttuttttutttvo..",
      "..ottutttuttttutttuvvo..",
      "...otttuttttuttttuvvo...",
      "...ottutttuttttuttvvo...",
      "....otttuttttuttuvvo....",
      "....ouuuuuuuuuuuuvvo....",
      ".....oooooooooooooo.....",
      "........................",
    } },
    accent = "amber",
    available = available,
    shown = deps.shown,
    open = deps.open,
    translations = {
      de = {
        ["POKEAMIE"] = "POKéMON AMI",
        ["FRIENDSHIP"] = "FREUNDSCHAFT",
        ["BOND WITH YOUR POKEMON."] = "Schließe Freundschaft mit deinen Pokémon.",
        ["PET, FEED AND PLAY MINIGAMES."] = "Streicheln, füttern und Minispiele spielen.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Eine NaviPlay-App.",
      },
      es = {
        ["POKEAMIE"] = "POKé RECREO",
        ["FRIENDSHIP"] = "AMISTAD",
        ["BOND WITH YOUR POKEMON."] = "Estrecha lazos con tus Pokémon.",
        ["PET, FEED AND PLAY MINIGAMES."] = "Acarícialos, dales de comer y juega a minijuegos.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Una aplicación de NaviPlay.",
      },
      fr = {
        ["POKEAMIE"] = "POKéMON RÉCRÉ",
        ["FRIENDSHIP"] = "AMITIÉ",
        ["BOND WITH YOUR POKEMON."] = "Tisse des liens avec tes Pokémon.",
        ["PET, FEED AND PLAY MINIGAMES."] = "Caresse-les, nourris-les et joue à des mini-jeux.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Une application NaviPlay.",
      },
      it = {
        ["POKEAMIE"] = "POKé IO E TE",
        ["FRIENDSHIP"] = "AMICIZIA",
        ["BOND WITH YOUR POKEMON."] = "Stringi amicizia con i tuoi Pokémon.",
        ["PET, FEED AND PLAY MINIGAMES."] = "Accarezzali, nutrili e gioca ai minigiochi.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Un'app di NaviPlay.",
      },
      ja = {
        ["POKEAMIE"] = "ポケパルレ",
        ["FRIENDSHIP"] = "なかよし",
        ["BOND WITH YOUR POKEMON."] = "ポケモンと なかよくなろう。",
        ["PET, FEED AND PLAY MINIGAMES."] = "なでたり ポフレをあげたり ミニゲームで遊ぼう。",
        ["POWERED BY THE NAVIPLAY MOD."] = "NaviPlay提供のアプリ。",
      },
    },
  }
end

return function(deps)
  if deps and deps.app == "amie" then return amie(deps) end
  return {
    id = "super_training",
    label = "SUPER TRAINING",
    category = "TRAINING",
    description = {
      "EV SUPER TRAINING.",
      "PUNCH BAGS AND POP BALLOON BOTS.",
      "POWERED BY THE NAVIPLAY MOD.",
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
    available = available,
    shown = deps.shown,
    open = deps.open,
    translations = {
      de = {
        ["SUPER TRAINING"] = "SUPERTRAINING",
        ["TRAINING"] = "TRAINING",
        ["EV SUPER TRAINING."] = "EV-SUPERTRAINING.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Schlage Sandsäcke und lass Ballon-Bots platzen.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Eine NaviPlay-App.",
      },
      es = {
        ["SUPER TRAINING"] = "SUPERENTRENAMIENTO",
        ["TRAINING"] = "ENTRENAMIENTO",
        ["EV SUPER TRAINING."] = "SUPERENTRENAMIENTO DE EV.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Golpea sacos de boxeo y revienta robots globo.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Una aplicación de NaviPlay.",
      },
      fr = {
        ["SUPER TRAINING"] = "SUPER-ENTRAÎNEMENT",
        ["TRAINING"] = "ENTRAÎNEMENT",
        ["EV SUPER TRAINING."] = "SUPER-ENTRAÎNEMENT des EV.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Frappe les sacs de frappe et éclate les robots ballons.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Une application NaviPlay.",
      },
      it = {
        ["SUPER TRAINING"] = "SUPERALLENAMENTO",
        ["TRAINING"] = "ALLENAMENTO",
        ["EV SUPER TRAINING."] = "SUPERALLENAMENTO EV.",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "Colpisci i sacchi da allenamento e fai scoppiare i robot palloncino.",
        ["POWERED BY THE NAVIPLAY MOD."] = "Un'app di NaviPlay.",
      },
      ja = {
        ["SUPER TRAINING"] = "スーパートレーニング",
        ["TRAINING"] = "トレーニング",
        ["EV SUPER TRAINING."] = "努力値スーパートレーニング。",
        ["PUNCH BAGS AND POP BALLOON BOTS."] = "サンドバッグを叩いて、風船ロボットを割ろう。",
        ["POWERED BY THE NAVIPLAY MOD."] = "NaviPlay提供のアプリ。",
      },
    },
  }
end
