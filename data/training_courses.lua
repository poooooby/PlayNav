-- The 30 Super-Training Regimens: 18 regular (Lv1-3, six stats) and 12 secret (Lv4-8).
-- Verified fields (Bulbapedia "Super Training", the JP course list at
-- pente.koro-pokemon.com/xy/supatore-list, atwiki pkmnomegaralphas): the Balloon Bot
-- species and the score that pops each, the EVs per level (4/8/12), the medal target in
-- seconds left (150 Lv1, 120 Lv2/3, 90 secret, 120 for the Scatterbug and Hydreigon
-- circuits), the prize items of the secret courses, the goal counts and notable attacks
-- the JP guides describe. Course names are translations of the JP names (the English
-- names of the regular courses are not on record; the secret names are Bulbapedia's).
-- Placeholders (see data/training_rules.lua EVIDENCE): goal anchor positions, attack
-- timings, chance-goal odds, prize weights.
--
-- Row fields: id, level, stat / ev (regular) or secret = n (secret), name, bots =
-- { { national, species?, score, art? } }, goals = { anchors, max, groups, chance },
-- attacks = script name or list, prizes = { bag = "stat" | "support" }, items (secret),
-- flags: suddenDeath, rageAt, calmAt, source.

local anchors = {
  -- bot-local units, 1 = the bot's radius; `motion` sways the goal with the balloon
  whale = {
    head = { x = 0, y = 0.75 }, belly = { x = 0, y = -0.15 }, left = { x = -0.7, y = 0.1 },
    right = { x = 0.7, y = 0.1 }, tail = { x = 0.6, y = -0.6, motion = { ax = 0.2, ay = 0.05, period = 1.8 } },
    fin = { x = -0.5, y = -0.55 },
  },
  biped = {
    head = { x = 0, y = 0.8 }, body = { x = 0, y = 0.1 }, left = { x = -0.65, y = 0.2, motion = { ax = 0.15, ay = 0.1, period = 1.4 } },
    right = { x = 0.65, y = 0.2, motion = { ax = 0.15, ay = 0.1, period = 1.4 } }, legs = { x = 0, y = -0.65 },
    back = { x = 0.3, y = 0.5 },
  },
  magnet = {
    center = { x = 0, y = 0 }, top = { x = 0, y = 0.75 }, bottom = { x = 0, y = -0.7 },
    left = { x = -0.75, y = 0.1, motion = { ax = 0.1, ay = 0.25, period = 1.2 } },
    right = { x = 0.75, y = 0.1, motion = { ax = 0.1, ay = 0.25, period = 1.2 } },
  },
  jelly = {
    head = { x = 0, y = 0.6 }, body = { x = 0, y = 0 },
    tentacle_l = { x = -0.5, y = -0.5, motion = { ax = 0.3, ay = 0.1, period = 1.0 } },
    tentacle_r = { x = 0.5, y = -0.5, motion = { ax = 0.3, ay = 0.1, period = 1.0 } },
  },
  bat = {
    head = { x = 0, y = 0.5 }, body = { x = 0, y = -0.2 },
    wing_l = { x = -0.7, y = 0.2, motion = { ax = 0.1, ay = 0.35, period = 0.8 } },
    wing_r = { x = 0.7, y = 0.2, motion = { ax = 0.1, ay = 0.35, period = 0.8 } },
  },
  rock = {
    top = { x = 0, y = 0.75 }, left = { x = -0.6, y = 0.2 }, right = { x = 0.6, y = 0.2 },
    center = { x = 0, y = 0 }, bottom = { x = 0, y = -0.6 },
  },
}

-- named attack scripts: { at = s } once, { every = s, from = s, until = s } repeating
local attacks = {
  lv1_calm = { { every = 14, from = 10, kind = "big" } },
  lv1_homing = { { every = 12, from = 8, kind = "homing", n = 1 } },
  lv1_scatter = { { every = 12, from = 8, kind = "small_rapid", n = 3 } },
  lv2_homing = { { every = 9, from = 6, kind = "homing", n = 2 }, { every = 20, from = 16, kind = "big" },
    { every = 16, from = 13, kind = "lob" } },
  lv2_scatter = { { every = 8, from = 6, kind = "small_rapid", n = 5 }, { every = 18, from = 14, kind = "cross" },
    { every = 16, from = 11, kind = "lob" } },
  lv2_block = { { at = 5, kind = "barrier", marker = "center" }, { every = 10, from = 12, kind = "big" },
    { every = 22, from = 30, kind = "small_rapid", n = 4 }, { every = 16, from = 14, kind = "lob" } },
  lv2_bits = { { at = 4, kind = "bits", n = 2 }, { every = 10, from = 10, kind = "homing", n = 1 },
    { every = 15, from = 20, kind = "ring" }, { every = 16, from = 12, kind = "lob" } },
  lv2_fast = { { every = 11, from = 10, kind = "small_rapid", n = 3, fast = true }, { every = 16, from = 18, kind = "big" }, { every = 15, from = 12, kind = "lob" } },
  lv2_chance = { { every = 12, from = 10, kind = "big" }, { every = 20, from = 20, kind = "small_rapid", n = 3 }, { every = 16, from = 14, kind = "lob" } },
  lv3_waves = { { every = 8, from = 6, kind = "homing", n = 2 }, { every = 14, from = 12, kind = "wave_tall" },
    { every = 14, from = 19, kind = "wave_wide" }, { every = 12, from = 9, kind = "lob", n = 2 } },
  lv3_giant = { { at = 3, kind = "bits", n = 3 }, { every = 9, from = 8, kind = "big" }, { every = 13, from = 14, kind = "small_rapid", n = 4 }, { every = 12, from = 10, kind = "lob", n = 2 } },
  lv3_haxorus = { { every = 15, from = 6, kind = "small_rapid", n = 6 }, { every = 15, from = 11, kind = "ring" },
    { every = 15, from = 16, kind = "cross" }, { every = 12, from = 9, kind = "lob", n = 2 } },
  lv3_army = { { at = 3, kind = "bits", n = 3 }, { every = 10, from = 8, kind = "homing", n = 2 }, { every = 12, from = 14, kind = "cross" }, { every = 12, from = 10, kind = "lob", n = 2 } },
  lv3_swift = { { every = 7, from = 5, kind = "small_rapid", n = 4, fast = true }, { every = 15, from = 12, kind = "big" },
    { every = 12, from = 10, kind = "lob", n = 2 } },
  lv3_defense = { { at = 4, kind = "barrier", marker = "center" }, { every = 9, from = 10, kind = "big" },
    { every = 13, from = 16, kind = "wave_wide" }, { every = 12, from = 11, kind = "lob", n = 2 } },
  secret_mixed = { { every = 7, from = 4, kind = "small_rapid", n = 5 }, { every = 11, from = 8, kind = "homing", n = 2 },
    { every = 13, from = 12, kind = "ring" }, { every = 17, from = 15, kind = "cross" }, { every = 12, from = 10, kind = "lob", n = 2 } },
  secret_bits = { { at = 2, kind = "bits", n = 3 }, { every = 6, from = 5, kind = "small_rapid", n = 6 },
    { every = 10, from = 9, kind = "homing", n = 3 }, { every = 25, from = 20, kind = "bits", n = 2 } },
  secret_fleeing = { { every = 8, from = 5, kind = "homing", n = 2 }, { every = 12, from = 10, kind = "wave_tall" } },
  secret_finale = { { at = 3, kind = "bits", n = 2 }, { every = 8, from = 5, kind = "small_rapid", n = 6 },
    { every = 10, from = 9, kind = "ring" }, { every = 12, from = 12, kind = "cross" },
    { every = 30, from = 20, kind = "barrier", marker = "center" }, { every = 15, from = 14, kind = "wave_wide" } },
}

local STAT_ORDER = { "hp", "atk", "def", "spa", "spd", "spe" }
local SRC = { "bulbapedia:Super Training", "pente.koro-pokemon.com/xy/supatore-list", "atwiki pkmnomegaralphas" }

-- the game's course order (the name list in the ORAS text archive a/0/7/3 file 44, 0-based):
-- Scatterbug and Spewpa tutorials, then per level Sp. Atk, HP, Atk, Sp. Def, Spe, Def, then
-- the twelve secret courses. The course icons (a/0/2/8 entry 1), the names (file 45 line
-- 20 + order) and the blurbs (file 45 line 75 + order) all follow it. Regular names below
-- are the game's English ones (file 44); the JP titles were the first draft.
local ICON_ORDER = { spa = 0, hp = 1, atk = 2, spd = 3, spe = 4, def = 5 }

local function regular(level, stat, name, bot, score, goals, attackScript, extra)
  local row = {
    id = ("lv%d_%s"):format(level, stat), level = level, stat = stat, ev = level * 4, name = name,
    order = 2 + (level - 1) * 6 + ICON_ORDER[stat],
    bots = { { national = bot[1], species = bot[2], score = score,
      art = ("training/stage_poke_%02d"):format(2 + (level - 1) * 6 + ICON_ORDER[stat]) } },
    medal = (level == 1) and 150 or 120,
    goals = goals, attacks = attackScript, prizes = { bag = "stat" }, source = SRC,
  }
  for k, v in pairs(extra or {}) do row[k] = v end
  return row
end

local function secret(n, level, name, bots, items, goals, attackScript, extra)
  local row = {
    id = ("secret_%02d"):format(n), secret = n, level = level, name = name, bots = bots,
    order = 19 + n,
    medal = 90, extraBotSecs = 30, goals = goals, attacks = attackScript,
    prizes = { bag = "support" }, items = items, source = SRC,
  }
  for k, v in pairs(extra or {}) do row[k] = v end
  -- one course icon per course, the first bot's; circuits share it
  for _, b in ipairs(bots) do b.art = b.art or ("training/stage_poke_%02d"):format(19 + n) end
  for _, b in ipairs(row.alphaBots or {}) do b.art = b.art or ("training/stage_poke_%02d"):format(19 + n) end
  return row
end

local function g(family, max, groups, chanceOdds, chanceAnchor)
  return { anchors = family, max = max, groups = groups,
    chance = { odds = chanceOdds or 0.5, anchor = chanceAnchor or groups[1][1] } }
end

-- prize rows: { item = "ITEM_X" } (an engine item name) or { training = "<slug>" } (one of
-- data/training_items.lua); w = weight, minRemaining = seconds left needed, bestOnly = a
-- new best time only (ORAS Wiki: evolution stones only on a new top score)
local function stone(name) return { item = name, w = 1, bestOnly = true, minRemaining = 90 } end
local function plain(name, w) return { item = name, w = w or 3 } end
local function wing(slug, w) return { training = slug, w = w or 3 } end
local CUP = function(stoneName)
  return { stone(stoneName), plain("ITEM_HARD_STONE"), plain("ITEM_STARDUST"), wing("pretty-wing", 2), plain("ITEM_SODA_POP", 2) }
end

local courses = {
  -- ------- Lv1 (+4)
  regular(1, "hp", "Raise Your HP with Wailmer!", { 320, "SPECIES_WAILMER" }, 500,
    g("whale", 2, { { "head", "belly" } }, 0.3, "belly"), "lv1_calm"),
  regular(1, "atk", "Boost Attack with Axew!", { 610 }, 300,
    g("biped", 2, { { "head", "body" }, { "left", "right" } }, 0.3), "lv1_scatter"),
  regular(1, "def", "Strengthen Defense with Geodude!", { 74, "SPECIES_GEODUDE" }, 400,
    g("rock", 5, { { "top", "left", "right", "center", "bottom" } }, 0.3, "center"), "lv1_calm"),
  regular(1, "spa", "Hone Sp. Atk with Magnemite!", { 81, "SPECIES_MAGNEMITE" }, 300,
    g("magnet", 2, { { "center", "left" }, { "center", "right" } }, 0.3, "center"), "lv1_homing"),
  regular(1, "spd", "Build Up Sp. Def with Tentacool!", { 72, "SPECIES_TENTACOOL" }, 200,
    g("jelly", 2, { { "head", "tentacle_l" }, { "body", "tentacle_r" } }, 0.3, "body"), "lv1_calm"),
  regular(1, "spe", "Speed Up with the Noibat Regimen!", { 714 }, 200,
    g("bat", 1, { { "head" }, { "wing_l" }, { "body" }, { "wing_r" } }, 0.3, "body"), "lv1_scatter"),
  -- ------- Lv2 (+8)
  regular(2, "hp", "Hit Relicanth\'s Weak Points!", { 369, "SPECIES_RELICANTH" }, 2500,
    g("whale", 3, { { "head", "belly", "left" }, { "right", "tail", "fin" } }, 1.0, "belly"), "lv2_chance"),
  regular(2, "atk", "Let Loose to Get Fraxure!", { 611 }, 1500,
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 0.4), "lv2_scatter"),
  regular(2, "def", "Break Down Graveler\'s Barrier!", { 75, "SPECIES_GRAVELER" }, 1500,
    g("rock", 5, { { "top", "left", "right", "center", "bottom" } }, 0.4, "center"), "lv2_block"),
  -- three goals at a time, upper right / lower left / lower right then again (live read of the
  -- game, 2026-10-12; oras-extract/live_st/spatk_lv2.jsonl)
  regular(2, "spa", "Home In on Magneton!", { 82, "SPECIES_MAGNETON" }, 1500,
    g("magnet", 3, { { "right", "left", "bottom" }, { "top", "left", "right" } }, 0.4, "top"), "lv2_homing"),
  regular(2, "spd", "Watch Out for Tentacruel\'s Bitbots!", { 73, "SPECIES_TENTACRUEL" }, 1000,
    g("jelly", 1, { { "tentacle_l" }, { "tentacle_r" }, { "head" }, { "body" } }, 0.4, "body"), "lv2_bits"),
  regular(2, "spe", "Hammer Aerodactyl with High-Speed Shots!", { 142, "SPECIES_AERODACTYL" }, 1000,
    g("bat", 1, { { "head" }, { "wing_l" }, { "body" }, { "wing_r" } }, 0.4, "body"), "lv2_fast",
    { motion = { bob = { ay = 0.3, period = 2.2 } } }),   -- "A Balloon Bot that soars up in the sky!"
  -- ------- Lv3 (+12)
  regular(3, "hp", "Shoot Back! Get the Giant Wailord!", { 321, "SPECIES_WAILORD" }, 4000,
    g("whale", 3, { { "head", "belly", "left" }, { "right", "tail", "fin" } }, 0.6, "belly"), "lv3_giant", { chanceLong = true }),
  regular(3, "atk", "Catch \'Em! Haxorus\'s Furious Attacks!", { 612 }, 2500,
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 1.0), "lv3_haxorus"),
  regular(3, "def", "Break It! Golem\'s Defensive Line!", { 76, "SPECIES_GOLEM" }, 2500,
    g("rock", 5, { { "top", "left", "right", "center", "bottom" } }, 0.5, "center"), "lv3_defense"),
  -- three goals at a time, spread wide (live read, spatk_lv3.jsonl)
  regular(3, "spa", "Shake Off That Uncanny Magnezone!", { 462 }, 2500,
    g("magnet", 3, { { "left", "right", "top" }, { "left", "bottom", "right" } }, 0.5, "center"), "lv3_waves"),
  regular(3, "spd", "Kick Hard! Get the Dragalge Corps!", { 691 }, 2000,
    g("jelly", 1, { { "tentacle_l" }, { "body" }, { "tentacle_r" }, { "head" } }, 0.5, "body"), "lv3_army"),
  regular(3, "spe", "Catch It! Noivern\'s Wild Wind!", { 715 }, 2000,
    g("bat", 1, { { "head" }, { "wing_l" }, { "body" }, { "wing_r" } }, 0.5, "body"), "lv3_swift"),
  -- ------- secret (no EVs; items)
  secret(1, 4, "The Troubles Keep on Coming?!",
    { { national = 699, score = 1800 }, { national = 697, score = 1800 } },
    { wing("health-wing"), wing("muscle-wing"), wing("resist-wing"), wing("genius-wing"), wing("clever-wing"),
      wing("swift-wing"), wing("pretty-wing", 2), plain("ITEM_FRESH_WATER", 2) },
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 0.5), "secret_mixed"),
  secret(2, 5, "The Leaf Stone Cup Begins!", { { national = 3, species = "SPECIES_VENUSAUR", score = 4000 } },
    CUP("ITEM_LEAF_STONE"), g("biped", 3, { { "head", "left", "right" }, { "body", "back", "legs" } }, 0.5), "secret_bits"),
  secret(3, 5, "The Fire Stone Cup Begins!", { { national = 6, species = "SPECIES_CHARIZARD", score = 4000 } },
    CUP("ITEM_FIRE_STONE"), g("biped", 3, { { "head", "left", "right" }, { "body", "back", "legs" } }, 0.5), "secret_mixed"),
  secret(4, 5, "The Water Stone Cup Begins!", { { national = 9, species = "SPECIES_BLASTOISE", score = 4000 } },
    CUP("ITEM_WATER_STONE"), g("biped", 3, { { "head", "left", "right" }, { "body", "back", "legs" } }, 0.5), "secret_mixed"),
  secret(5, 5, "Follow Those Fleeing Goals!", { { national = 618, score = 4800 } },
    CUP("ITEM_THUNDER_STONE"), g("rock", 2, { { "left", "right" }, { "top", "bottom" }, { "center", "left" } }, 0.4, "center"),
    "secret_fleeing", { fleeing = true }),
  secret(6, 6, "Watch Out! That's One Tricky Second Half!", { { national = 681, score = 4800 } },
    { { training = "dusk-stone", w = 1, bestOnly = true, minRemaining = 90 }, plain("ITEM_HARD_STONE"), plain("ITEM_STARDUST"),
      wing("pretty-wing", 2), plain("ITEM_SODA_POP", 2) },
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 0.5), "secret_mixed", { rageAt = 2400 }),
  secret(7, 6, "An Opening of Lightning-Quick Attacks!", { { national = 407, score = 4800 } },
    { { training = "shiny-stone", w = 1, bestOnly = true, minRemaining = 90 }, plain("ITEM_HARD_STONE"), plain("ITEM_STARDUST"),
      wing("pretty-wing", 2), plain("ITEM_SODA_POP", 2) },
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 0.5), "secret_mixed", { calmAt = 2400 }),
  secret(8, 6, "Those Long Shots Are No Long Shot!", { { national = 475, score = 5600 } },
    { { training = "dawn-stone", w = 1, bestOnly = true, minRemaining = 90 }, plain("ITEM_HARD_STONE"), plain("ITEM_STARDUST"),
      wing("pretty-wing", 2), plain("ITEM_SODA_POP", 2) },
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 0.5), "secret_fleeing", { farPlayer = true }),
  secret(9, 7, "Scatterbug Lugs Back!",
    { { national = 664, score = 1200 }, { national = 665, score = 2400 }, { national = 666, score = 3600 } },
    { plain("ITEM_PP_UP", 1), wing("muscle-wing"), wing("genius-wing"), wing("swift-wing"), wing("pretty-wing", 2), plain("ITEM_LEMONADE", 2) },
    g("bat", 1, { { "head" }, { "wing_l" }, { "body" }, { "wing_r" } }, 0.5, "body"), "secret_mixed", { medal = 120 }),
  secret(10, 7, "A Barrage of Bitbots!", { { national = 476, score = 7200 } },
    { plain("ITEM_PP_UP", 1), wing("health-wing"), wing("resist-wing"), wing("clever-wing"), wing("pretty-wing", 2), plain("ITEM_LEMONADE", 2) },
    g("magnet", 3, { { "center", "left", "right" }, { "top", "bottom", "center" } }, 0.5, "center"), "secret_bits",
    { roaming = true }),   -- "constantly moving goals while dodging a merciless barrage"
  secret(11, 7, "Drag Down Hydreigon!",
    { { national = 633, score = 1600 }, { national = 634, score = 2400 }, { national = 635, score = 4800 } },
    { plain("ITEM_PP_UP", 1), stone("ITEM_SUN_STONE"), stone("ITEM_MOON_STONE"), plain("ITEM_STARDUST"), wing("pretty-wing", 2),
      plain("ITEM_LEMONADE", 2) },
    g("biped", 3, { { "head", "left", "right" }, { "body", "legs", "back" } }, 0.5), "secret_mixed", { medal = 120, suddenDeath = true }),
  secret(12, 8, "The Battle for the Best!",
    { { national = 304, species = "SPECIES_ARON", score = 1600 }, { national = 305, species = "SPECIES_LAIRON", score = 2400 },
      { national = 306, species = "SPECIES_AGGRON", score = 3200 }, { national = 306, species = "SPECIES_AGGRON", score = 5600, mega = true } },
    { plain("ITEM_PP_MAX", 1), plain("ITEM_PP_UP", 2), stone("ITEM_LEAF_STONE"), stone("ITEM_WATER_STONE"),
      stone("ITEM_THUNDER_STONE"), stone("ITEM_FIRE_STONE"), wing("pretty-wing", 2), plain("ITEM_MOOMOO_MILK", 2) },
    g("rock", 5, { { "top", "left", "right", "center", "bottom" } }, 0.5, "center"), "secret_finale",
    -- the line is the version's (GARC a/1/1/7 row 31: Omega Ruby phases 43-45 / 32, the Aron
    -- line; Alpha Sapphire 40-42 / 31, the Larvitar line, same targets and damage)
    { alphaBots = { { national = 246, species = "SPECIES_LARVITAR", score = 1600 },
      { national = 247, species = "SPECIES_PUPITAR", score = 2400 },
      { national = 248, species = "SPECIES_TYRANITAR", score = 3200 },
      { national = 248, species = "SPECIES_TYRANITAR", score = 5600, mega = true } } }),
}

-- the points a hit costs, per balloon, from the game's course data (GARC a/1/1/7 course rows ->
-- a/1/1/8 phase records: u16 +0 species, +2 target, +0xc damage, +0x24 the second form's;
-- DllSparring.cro loads them at 0x8300, a ball's hit takes the phase's number at 0xf44c). Each
-- course's balloons in order; { damage, second form } for Aegislash / Roserade. The finale's
-- Aron line is version-exclusive (this card's row has the Larvitar line, 800 / 1200 / 1600 / 2500
-- as well; the Aron line's phases 43-45 and 32 hold the same).
local GAME_DAMAGE = {
  lv1_hp = { 40 }, lv1_atk = { 50 }, lv1_def = { 30 }, lv1_spa = { 40 }, lv1_spd = { 30 }, lv1_spe = { 30 },
  lv2_hp = { 150 }, lv2_atk = { 200 }, lv2_def = { 120 }, lv2_spa = { 100 }, lv2_spd = { 120 }, lv2_spe = { 120 },
  lv3_hp = { 450 }, lv3_atk = { 600 }, lv3_def = { 300 }, lv3_spa = { 250 }, lv3_spd = { 300 }, lv3_spe = { 300 },
  secret_01 = { 1200, 2000 }, secret_02 = { 2000 }, secret_03 = { 2000 }, secret_04 = { 2000 },
  secret_05 = { 1500 }, secret_06 = { { 1200, 2500 } }, secret_07 = { { 1200, 2500 } }, secret_08 = { 2000 },
  secret_09 = { 800, 1500, 2500 }, secret_10 = { 2000 }, secret_11 = { 65535, 65535, 65535 },
  secret_12 = { 800, 1200, 1600, 2500 },
}
for _, c in ipairs(courses) do
  for _, list in ipairs({ c.bots, c.alphaBots or {} }) do
    for i, b in ipairs(list) do
      local d = GAME_DAMAGE[c.id] and GAME_DAMAGE[c.id][i]
      if type(d) == "table" then b.damage, b.damage2 = d[1], d[2] else b.damage = d end
    end
  end
end

-- a course's balloons for the GBA game being played: the final course's line follows the 3DS
-- pair (Ruby / FireRed / Emerald -> Omega Ruby's Aron line, Sapphire / LeafGreen -> Alpha
-- Sapphire's Larvitar line)
local ALPHA = { sapphire = true, leafgreen = true }
local function alpha(version) return ALPHA[tostring(version or ""):lower()] == true end
local function botsFor(course, version)
  if course and course.alphaBots and alpha(version) then return course.alphaBots end
  return course and course.bots
end

local byId = {}
for _, c in ipairs(courses) do byId[c.id] = c end

-- the Lv1 balloons' own idle motion in the game's top-screen pixels (Wooble's captures
-- 2026-10-23; N.BOT.SWAY's form: ax across, ay up and down, every period s): mostly a small
-- vertical bob, Axew all but still, Tentacool drifting slowly, Noibat swaying side to side
local SWAY = {
  lv1_hp = { ax = 0, ay = 6, period = 4.0 },
  lv1_atk = { ax = 1, ay = 0.5, period = 6.8 },
  lv1_def = { ax = 0, ay = 5, period = 3.3 },
  lv1_spa = { ax = 0.75, ay = 4.75, period = 2.35 },
  lv1_spd = { ax = 2, ay = 11, period = 12 },
  lv1_spe = { ax = 5, ay = 4, period = 6.6 },
  -- Lv2 (the s2 captures): Relicanth a loose circle, Fraxure / Graveler a small bob, Magneton
  -- a lopsided sway, Tentacruel sinking slowly, Aerodactyl soaring up and down
  lv2_hp = { ax = 2.8, ay = 3.5, period = 5.5 },
  lv2_atk = { ax = 0, ay = 2, period = 2.8 },
  lv2_def = { ax = 1.5, ay = 1.3, period = 3.2 },
  lv2_spa = { ax = 2.5, ay = 2, period = 3.95 },
  lv2_spd = { ax = 0, ay = 3, period = 14 },
  lv2_spe = { ax = 0, ay = 9.5, period = 5.4 },
}
for id, sway in pairs(SWAY) do if byId[id] then byId[id].sway = sway end end

-- a balloon's own throw (N.BOT.WINDUP's form; a negative DIP climbs, a negative RISE ends below):
-- Fraxure dips a little and stretches up; Graveler leaps up off the top of the screen and drops
-- back to throw; Aerodactyl climbs, then dives as it throws and glides low a while
local WINDUP = {
  lv2_atk = { DIP_PX = 4, RISE_PX = 14, DIP_AT = 0.4, HOLD_S = 1.5 },
  lv2_def = { DIP_PX = -80, RISE_PX = 0, DIP_AT = 0.85, HOLD_S = 0.3 },
  lv2_spe = { DIP_PX = -20, RISE_PX = -45, DIP_AT = 0.75, HOLD_S = 4 },
}
for id, w in pairs(WINDUP) do if byId[id] then byId[id].windup = w end end
-- Aerodactyl's soaring is its sway now
if byId.lv2_spe then byId.lv2_spe.motion = nil end

return { version = 1, anchors = anchors, attacks = attacks, courses = courses, byId = byId, STAT_ORDER = STAT_ORDER,
  botsFor = botsFor, alpha = alpha }
