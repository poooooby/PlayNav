-- The Amie text helper: our fallbacks without the card, the game's lines with it, variable
-- filling, puff and Décor name indexes, rank titles.
-- Run from the engine root: luajit mods/play_nav/tests/amie_text_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local makeText = loadFile("mods/play_nav/src/amie/text.lua")

-- ------- without the card: every lookup is our own wording

do
  local G = {}
  local AT = makeText(G)
  T.eq(AT.get("needThree"), "You need three Pokémon in good condition.", "a UI line falls back")
  T.eq(AT.get("nope"), "nope", "an unknown key comes back as itself")
  T.check(not AT.has("affection"), "has() is false without the text")
  T.eq(AT.title("berry", "easy", false), "Berry Amateur", "rank titles fall back to Bulbapedia's")
  T.eq(AT.title("head", "unlimited", true), "Ultimate Header Master", "...five stars")
  T.eq(AT.game("head", "combo", { N = 5 }), "5-HIT COMBO", "a game line with a number")
  T.eq(AT.game("tile", "points", { N = 3 }), "3 Points", "plural")
  T.eq(AT.game("tile", "points", { N = 1 }), "1 Point", "...singular drops the s")
  T.eq(AT.gameName("tile"), "Tile Puzzle", "game names")
  T.eq(AT.diffLabel("unlimited"), "Unlimited", "difficulty words")
  T.eq(AT.puffName("puff/sweet_basic"), nil, "no puff name without the text")
  T.eq(AT.puffName("puff/sweet_basic", "ours"), "ours", "...the fallback argument")
  T.eq(AT.decorName("wall/fire"), nil, "no Décor name without the text")
end

-- ------- filling

do
  local AT = makeText({})
  T.eq(AT.fill("from {PLAYER}, {PLAYER}, and {PLAYER}!", { PLAYER = { "A", "B", "C" } }), "from A, B, and C!", "a list fills repeats in order")
  T.eq(AT.fill("{MON} found {DECOR}", { MON = "TORCHIC", DECOR = "a Leaf Cushion" }), "TORCHIC found a Leaf Cushion", "named values")
  T.eq(AT.fill("{MON} and {ITEM}", { MON = "X" }), "X and ", "a missing value is empty")
  T.eq(AT.oneLine("one\ntwo\n three"), "one two three", "line breaks join")
end

-- ------- the puff index (file 81: tiers x flavours, then the six supremes)

do
  local AT = makeText({})
  T.eq(AT.puffLine("puff/sweet_basic"), 0, "Sweet is line 0")
  T.eq(AT.puffLine("puff/spice_basic"), 4, "Spice 4")
  T.eq(AT.puffLine("puff/sweet_frosted"), 5, "Frosted Sweet 5")
  T.eq(AT.puffLine("puff/mocha_deluxe"), 18, "Deluxe Mocha 18")
  T.eq(AT.puffLine("puff/supreme_wish"), 20, "Wish 20 (the game's order)")
  T.eq(AT.puffLine("puff/supreme_honor"), 21, "Honor 21")
  T.eq(AT.puffLine("puff/supreme_fall"), 24, "our fall is the game's Autumn, 24")
  T.eq(AT.puffLine("puff/supreme_winter"), 25, "Winter 25")
  T.eq(AT.puffLine("puff/what_ever"), nil, "unknown ids have no line")
end

-- ------- with the text: a fake Assets.text

do
  local texts = {
    amie_main = { [2] = "You got [DECOR] from {PLAYER}, {PLAYER}, and\n{PLAYER}!", [14] = "Affection", [4] = "You can’t play with an Egg, silly!" },
    amie_puffs = { [0] = "Sweet Poké Puff", [20] = "Supreme Wish Poké Puff", [24] = "Supreme Autumn Poké Puff" },
    amie_head = { [6] = "FEVER", [19] = "{N}-HIT COMBO", [23] = "Header Amateur", [29] = "Header Hyper Master" },
    amie_tile = { [74] = "{N} Points" },
    amie_decor = { [0] = "Normal Wallpaper", [1] = "Fire Wallpaper", [34] = "Cocoa Treat Cushion", [35] = "Chocolate Treat Cushion" },
    amie_games = { [3] = "Easy" },
  }
  texts.amie_main[2] = "You got {DECOR} from {PLAYER}, {PLAYER}, and\n{PLAYER}!"
  local G = { assets = { text = function(id) return texts[id] end } }
  local AT = makeText(G)
  T.check(AT.has("affection"), "has() sees the text")
  T.eq(AT.get("affection"), "Affection", "a word from the text")
  T.eq(AT.get("egg"), "You can’t play with an Egg, silly!", "the game's apostrophe survives")
  T.eq(AT.get("visitorGift", { DECOR = "a Leaf Cushion", PLAYER = { "PIKACHU", "EEVEE", "TORCHIC" } }),
    "You got a Leaf Cushion from PIKACHU, EEVEE, and TORCHIC!", "the visitors' gift line fills three names on one line")
  T.eq(AT.get("needThree"), "You need three Pokémon in good condition.", "a line the fake lacks still falls back")
  T.eq(AT.game("head", "fever"), "FEVER", "a game word")
  T.eq(AT.game("head", "combo", { N = 7 }), "7-HIT COMBO", "...with a number")
  T.eq(AT.game("tile", "points", { N = 1 }), "1 Point", "...singular from the text too")
  T.eq(AT.title("head", "easy", false), "Header Amateur", "rank title from the text")
  T.eq(AT.title("head", "easy", true), "Header Hyper Master", "...five stars")
  T.eq(AT.title("head", "hard", false), "Header Pro", "...a missing line falls back")
  T.eq(AT.puffName("puff/sweet_basic"), "Sweet Poké Puff", "puff names")
  T.eq(AT.puffName("puff/supreme_wish"), "Supreme Wish Poké Puff", "...Wish")
  T.eq(AT.puffName("puff/supreme_fall"), "Supreme Autumn Poké Puff", "...our fall is Autumn")
  T.eq(AT.diffLabel("easy"), "Easy", "difficulty from the text")
  T.eq(AT.diffLabel("hard"), "Hard", "...else ours")
  local catalog = {
    { id = "thumb/normal", kind = "thumb" }, { id = "wall/normal", kind = "wall" },
    { id = "cushion/cocoa_treat_cushion", kind = "cushion" }, { id = "cushion/chocolate_treat_cushion", kind = "cushion" },
    { id = "thumb/fire", kind = "thumb" }, { id = "wall/fire", kind = "wall" },
  }
  AT.setDecor({ CATALOG = catalog })
  T.eq(AT.decorName("wall/normal"), "Normal Wallpaper", "wallpapers index from line 0")
  T.eq(AT.decorName("thumb/fire"), "Fire Wallpaper", "...a thumbnail shares its wallpaper's line")
  T.eq(AT.decorName("cushion/chocolate_treat_cushion"), "Chocolate Treat Cushion", "items index from line 34")
  T.eq(AT.decorName("object/nothing", "ours"), "ours", "unknown ids take the fallback")
end

T.finish("play_nav amie text")
