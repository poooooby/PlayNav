-- Super Training's words, NaviPlay's own: every line the screens ask the game's text for
-- (T.gameLine / gameText in src/training/session.lua), keyed by the same file and line, so
-- nothing is read from the card image. Variables: {MON} {BAG} {STAT} {PLAYER} {COURSE} {N}.
-- A line left out falls back to the code's own wording (the bag descriptions: Rules.fallbackText).

local W = {}

-- the bags, in Rules.GAME_ORDER
W.training_bag_names = {
  "HP Bag S", "HP Bag M", "HP Bag L",
  "Attack Bag S", "Attack Bag M", "Attack Bag L",
  "Defense Bag S", "Defense Bag M", "Defense Bag L",
  "Sp. Atk Bag S", "Sp. Atk Bag M", "Sp. Atk Bag L",
  "Sp. Def Bag S", "Sp. Def Bag M", "Sp. Def Bag L",
  "Speed Bag S", "Speed Bag M", "Speed Bag L",
  "Power Bag", "Guard Bag", "Dash Bag", "Big Shot Bag", "Double Bag", "Second Wind Bag",
  "Fresh Start Bag", "Comfort Bag",
}

-- Core Training: the bag prompts, the coach, what a cleared bag did
W.training_bags = {
  [6] = "A {BAG} came tumbling down!",
  [7] = "Hang the {BAG} up for {MON}?",
  [8] = "Throw this {BAG} away?",
  [9] = "{MON} still has its last bag's boost. Hanging the {BAG} swaps it out. Go ahead?",
  [10] = "{MON} already has a bag up, and that one will be tossed. Hang the {BAG} instead?",
  [11] = "{MON} is catching its breath...",
  [12] = "{MON} had a good rest and is fired up again!",
  [13] = "Use", [14] = "Discard", [15] = "Back", [16] = "Yes", [17] = "No",
  -- the coach's cheers, three per group (HP / Big Shot; Attack, Sp. Atk / Power; Defense,
  -- Sp. Def / Guard; Speed / Dash; Double; Second Wind; Fresh Start; Comfort)
  [45] = "Keep swinging! Every hit counts!", [46] = "Steady breathing... and punch!",
  [47] = "That's it! Build that stamina!",
  [48] = "Put your weight behind it!", [49] = "Harder! Show that bag who's boss!",
  [50] = "Aim for the center and let it fly!",
  [51] = "Plant your feet and hold your ground!", [52] = "Shake it off and go again!",
  [53] = "Solid! Nothing gets past you!",
  [54] = "Quick feet, quick hands!", [55] = "Faster! Don't let it settle!",
  [56] = "In and out, like the wind!",
  [57] = "Double the effort, double the gains!", [58] = "Two at a time? You've got this!",
  [59] = "Twice the sweat, twice the reward!",
  [60] = "Feel that energy? Ride it!", [61] = "You're on a roll now!",
  [62] = "Nothing can slow you down today!",
  [63] = "Clean slate, clean punches!", [64] = "Starting over is part of the plan!",
  [65] = "New beginnings, same fighting spirit!",
  [66] = "Easy does it... nice and gentle.", [67] = "Take it slow. You're doing great.",
  [68] = "Relax those shoulders and enjoy it!",
  -- a stat bag cleared (HP, Attack, Defense, Sp. Atk, Sp. Def, Speed)
  [69] = "{MON}'s HP training paid off!", [70] = "{MON}'s Attack training paid off!",
  [71] = "{MON}'s Defense training paid off!", [72] = "{MON}'s Sp. Atk training paid off!",
  [73] = "{MON}'s Sp. Def training paid off!", [74] = "{MON}'s Speed training paid off!",
  -- an effect bag cleared (Power, Guard, Dash, Big Shot, Double)
  [75] = "{MON} will score more for every goal in its next regimen!",
  [76] = "{MON} will shrug off hits better in its next regimen!",
  [77] = "{MON} will move faster in its next regimen!",
  [78] = "{MON} will fire bigger shots in its next regimen!",
  [79] = "{MON} will gain twice as much from its next regimen!",
  [80] = "{MON} feels great! Its next bag will go down in half the hits!",
  [81] = "{MON}'s training was wiped clean. A fresh start!",
  [82] = "{MON} looks really happy to be training with you!",
  -- the finishing move
  [83] = "Here comes the finisher!", [84] = "Time for the big one!", [85] = "Let's wrap this up!",
  [92] = "{MON} can't push its {STAT} any higher, so the {BAG} won't help.",
  [94] = "{MON} has trained every stat as far as it can go!",
  [95] = "{MON} is resting. Wake it up first!",
}

-- the regimens' tags and the score
W.training_coach = {
  [50] = " Balloon",
  [111] = "SCORE:",
}

-- the regimen screens: headings, the courses, the results
local C = {
  [1] = "Super Training Lv. 1", [2] = "Super Training Lv. 2", [3] = "Super Training Lv. 3",
  [4] = "Secret Super Training Lv. 1", [5] = "Secret Super Training Lv. 2",
  [9] = "Lv. ?", [10] = "Lv. 1", [11] = "Lv. 2", [12] = "Lv. 3",
  [13] = "Secret", [14] = "Secret", [15] = "Secret", [16] = "Secret", [17] = "Secret",
  [59] = "Possible stat gain:", [60] = "Stat gain:", [61] = "Bags received:", [62] = "Items received:",
  [65] = "HP", [66] = "Attack", [67] = "Defense", [68] = "Sp. Atk", [69] = "Sp. Def", [70] = "Speed",
  [72] = "Target time left:", [73] = "Best time:",
  [125] = "You unlocked a new regimen: {COURSE}",
  [127] = "Not this time... The balloon held out.",
  [128] = "You stepped out of the regimen.",
  [129] = "That regimen isn't open yet.",
  [130] = "Time left:",
  [132] = "You did it! Great work out there!",
  [133] = "Under the target! Nicely done!",
  [134] = "Way under the target! What a run!",
  [135] = "Incredible! That's a new record!",
  [136] = "So close! Beat the target time next round!",
  [137] = "You beat the target time!",
  [138] = "You earned a medal!",
  [139] = "A new best time!",
  [140] = "{MON} built up its stamina by training its {STAT}!",
  [141] = "{MON}'s shots hit harder after training its {STAT}!",
  [142] = "{MON} can take more hits after training its {STAT}!",
  [143] = "{MON} got quicker on its feet by training its {STAT}!",
  [145] = "{MON}'s {STAT} can't go any higher.",
  [149] = "Keep it up! Train every stat to the max to become Fully Trained!",
  [150] = "Every stat is maxed out! {MON} is Fully Trained!",
  [153] = "A medal from every regimen! {MON} is Supremely Trained!",
  [163] = "Your bag rack is full, so this one couldn't be kept.",
  [165] = "You took on the regimen and earned a reward!",
  [166] = "And the results are...",
  [167] = "Training Bags:\n{N}",
  [168] = "Only a Fully Trained Pokemon may enter.",
}

-- the courses: name (line 20 + order) and blurb (line 75 + order)
local COURSES = {
  [2] = { "Zap Magnemite for Sp. Atk!", "Magnemite's shots curve toward you. Line up each goal and fire away." },
  [3] = { "Pump Up HP with Wailmer!", "Wailmer is big and easygoing. Keep your shots steady and you'll be fine." },
  [4] = { "Sharpen Attack on Axew!", "Axew throws a spread of shots. Score fast, then slide out of the way." },
  [5] = { "Toughen Sp. Def vs. Tentacool!", "Tentacool takes it easy. A good place to practice blocking!" },
  [6] = { "Race Noibat for Speed!", "Noibat scatters its shots. Keep moving and pick your moments." },
  [7] = { "Rock-Solid Defense with Geodude!", "Geodude takes its time. Stand your ground and return fire." },
  [8] = { "Lock On to Magneton!", "Magneton's shots hunt you down. Keep moving and keep scoring." },
  [9] = { "Find Relicanth's Soft Spots!", "Watch for the red goal. Hitting it is worth a big bonus!" },
  [10] = { "Out-Hustle Fraxure!", "Fraxure scatters shots wide. Find the gaps and strike between them." },
  [11] = { "Dodge Tentacruel's Bitbots!", "Tentacruel sends bitbots out. Knock them down before they swarm you." },
  [12] = { "Rapid Fire at Aerodactyl!", "Aerodactyl bobs up and down. Quick shots beat waiting for the perfect one." },
  [13] = { "Crack Graveler's Shield!", "Graveler's throws come in heavy. Block, then hit back." },
  [14] = { "Outlast Magnezone's Barrage!", "Magnezone attacks in waves. Block well and save your Energy Shot." },
  [15] = { "Take On Mighty Wailord!", "Wailord throws giant balls. Get clear of them or block in time!" },
  [16] = { "Stand Firm Against Haxorus!", "Haxorus throws hard and fast. Stay sharp from start to finish." },
  [17] = { "Push Through the Dragalge Fleet!", "A whole fleet of shots comes your way. Keep your guard up." },
  [18] = { "Ride Out Noivern's Gale!", "Noivern sweeps across the arena. Lead your shots and stay light on your feet." },
  [19] = { "Smash Through Golem's Wall!", "Golem has a stubborn defense. Keep chipping away at it." },
  [20] = { "Double Trouble!", "Two balloons, one after the other. Pace yourself for the second." },
  [21] = { "Grass Cup: Venusaur Rising", "Venusaur leads the Grass Cup, with bitbots at its side." },
  [22] = { "Fire Cup: Charizard Rising", "Charizard leads the Fire Cup. Expect fast, fiery throws." },
  [23] = { "Water Cup: Blastoise Rising", "Blastoise leads the Water Cup. Expect anything!" },
  [24] = { "Chase the Runaway Goals!", "These goals don't like being hit. Catch them before they slip away." },
  [25] = { "Mind the Second-Half Twist!", "It starts calm, then everything changes. Save something for the end." },
  [26] = { "Lightning Opening!", "The first seconds are the toughest. Survive them and the rest is yours." },
  [27] = { "Long-Range Showdown!", "You start far back and the goals won't sit still. Aim carefully." },
  [28] = { "Scatterbug's Big Comeback!", "Scatterbug, then Spewpa, then Vivillon. Three rounds, one clock." },
  [29] = { "Bitbot Storm!", "Bitbots everywhere! Clear a path and keep the balloon in your sights." },
  [30] = { "Bring Down Hydreigon!", "Deino grows into Hydreigon over three rounds, and there's no room for mistakes." },
  [31] = { "Clash of the Champions!", "A whole evolution line, all the way to its Mega form. The ultimate test!" },
}
for order, row in pairs(COURSES) do
  C[20 + order] = row[1]
  C[75 + order] = row[2]
end
W.training_courses = C

-- the balloons' species names, by National Dex number
W.species = {
  [3] = "Venusaur", [6] = "Charizard", [9] = "Blastoise", [72] = "Tentacool", [73] = "Tentacruel",
  [74] = "Geodude", [75] = "Graveler", [76] = "Golem", [81] = "Magnemite", [82] = "Magneton",
  [142] = "Aerodactyl", [246] = "Larvitar", [247] = "Pupitar", [248] = "Tyranitar", [304] = "Aron", [305] = "Lairon", [306] = "Aggron", [320] = "Wailmer",
  [321] = "Wailord", [369] = "Relicanth", [407] = "Roserade", [462] = "Magnezone", [475] = "Gallade",
  [476] = "Probopass", [610] = "Axew", [611] = "Fraxure", [612] = "Haxorus", [618] = "Stunfisk",
  [633] = "Deino", [634] = "Zweilous", [635] = "Hydreigon", [664] = "Scatterbug", [665] = "Spewpa",
  [666] = "Vivillon", [681] = "Aegislash", [691] = "Dragalge", [697] = "Tyrantrum", [699] = "Aurorus",
  [714] = "Noibat", [715] = "Noivern",
}

return W
