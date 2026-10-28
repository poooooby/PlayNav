-- Pokemon-Amie's words from the game's own English text archive (a/0/7/3), decoded into
-- the player's cache by the import (data/oras_recipe.lua `kind = "text"` rows). Every lookup
-- falls back to our own wording, so nothing here needs the card image; the minigames and their
-- picker always use ours (AT.OWN_FILES). Pure Lua: `G.assets`
-- is read lazily (Assets.text(id) -> { [0] = line, ... } or nil).
--
--   AT.get(key, vars)        one UI line by key (see LINE), variables filled, one line
--   AT.game(game, key, vars) a minigame line (see GAME_LINE), same treatment
--   AT.title(game, diff, five) the rank title the game awards
--   AT.puffName(id)          "Sweet Poké Puff" ... from file 81
--   AT.decorName(id)         a Décor item's name from file 110 (needs AT.setDecor)
--   AT.has(key)              true when the game's text is there (callers may pick art then)
--
-- Variables render as {MON} {PLAYER} {DECOR} {PUFF} {ITEM} {N}; a table value fills repeats in
-- order ("from {PLAYER}, {PLAYER}, and {PLAYER}" takes three names).

return function(G)
  local AT = {}

  AT.FILES = { main = "amie_main", decorate = "amie_decorate", games = "amie_games", labels = "ui_labels",
    berry = "amie_berry", head = "amie_head", tile = "amie_tile", puffs = "amie_puffs", decor = "amie_decor" }

  -- key = { file, line, our fallback }
  AT.LINE = {
    affection = { "main", 14, "Affection" }, fullness = { "main", 15, "Fullness" }, enjoyment = { "main", 16, "Enjoyment" },
    switch = { "main", 5, "Switch Pokémon!" },
    selectMon = { "main", 3, "Select the Pokémon you'd like to play with!" },
    egg = { "main", 4, "You can't play with an Egg, silly!" },
    giftPlayed = { "main", 10, "You played with {MON} a lot! Found {DECOR}!" },
    giftClose = { "main", 11, "You and {MON} are looking close! Found {DECOR}!" },
    giftForever = { "main", 19, "You'll be friends forever with {MON}! Found {DECOR}!" },
    visitorGift = { "main", 2, "You got {DECOR} from {PLAYER}, {PLAYER}, and {PLAYER}!" },
    pickWall = { "decorate", 0, "Pick a wallpaper or some Décor!" },
    whatDecor = { "decorate", 1, "What do you want to do with your Décor?" },
    putAnywhere = { "decorate", 2, "Put it wherever you'd like!" },
    decorTab = { "decorate", 5, "Décor" }, interior = { "decorate", 6, "Interior Items" },
    puffsTab = { "decorate", 7, "Poké Puffs" },
    chooseDecor = { "decorate", 8, "Choose a Poké Puff or a Décor item!" },
    askSetPuff = { "decorate", 9, "Do you want to set down a Poké Puff?" },
    puffGone = { "decorate", 10, "Once you use a Poké Puff, it'll disappear!" },
    askReturnPuff = { "decorate", 11, "Want to return your Poké Puff to the shelf?" },
    usedNoReturn = { "decorate", 12, "Used Poké Puffs can't be put back." },
    visitorPlaying = { "decorate", 13, "A visiting Pokémon has come to play, so you cannot put it back now!" },
    roomFull = { "decorate", 14, "You cannot put out any more Décor!" },
    visitorsLeave = { "decorate", 16, "If you place, swap, or remove Poké Puffs, the Pokémon visiting from nearby games will leave. Would you still like to proceed?" },
    gameBerry = { "games", 0, "Berry Picker" }, gameHead = { "games", 1, "Head It" }, gameTile = { "games", 2, "Tile Puzzle" },
    easy = { "games", 3, "Easy" }, normal = { "games", 4, "Normal" }, hard = { "games", 5, "Hard" }, unlimited = { "games", 6, "Unlimited" },
    whichGame = { "games", 7, "Which game do you want to play?" },
    selectDiff = { "games", 8, "Select a difficulty level." },
    needThree = { "games", 9, "You need three Pokémon in good condition." },
    play = { "labels", 77, "PLAY" }, decorate = { "labels", 78, "DECORATE" }, switchLabel = { "labels", 79, "SWITCH" },
    amie = { "labels", 86, "Pokémon-Amie" }, results = { "labels", 75, "RESULTS" },
  }

  -- per minigame: key = { line, fallback }; the rank titles by difficulty: { below five, five stars }
  AT.GAME_LINE = {
    berry = {
      ready = { 0, "READY" }, start = { 1, "START!" }, timesUp = { 3, "TIME'S UP" }, timeLeft = { 4, "Time Left: {N}" },
      highScore = { 12, "HIGH SCORE:" }, count = { 15, "Berries" }, playAgain = { 24, "Play Again" }, quit = { 25, "Quit" },
      howTo = { 48, "Pick Berries for your Pokémon!" }, missThree = { 49, "Miss three times, and it's game over!" },
      puffReceived = { 50, "Poké Puff Received!" }, puffsReceived = { 51, "Poké Puffs Received!" },
      nextRank = { 52, "You can now access the next rank!" }, jarFull = { 53, "You can't carry any more Poké Puffs!" },
      stamp = { 47, "HIGH SCORE" },
      titles = { easy = { 26, 32 }, normal = { 17, 23 }, hard = { 33, 39 }, unlimited = { 40, 46 } },
    },
    head = {
      highScore = { 0, "HIGH SCORE:" }, chances = { 2, "Chances:" }, timeLeft = { 3, "Time Left: {N}" }, fever = { 6, "FEVER" },
      miss = { 8, "MISS!" }, score = { 13, "SCORE:" }, headingPoints = { 14, "Heading Points" }, bonus = { 15, "BONUS:" },
      lastCombo = { 16, "Last Combo Record" }, bigYarn = { 17, "Big Yarn Bonus" }, combo = { 19, "{N}-HIT COMBO" },
      playAgain = { 21, "Play Again" }, quit = { 22, "Quit" }, howTo = { 51, "Tap Pokémon to knock back the balls of yarn!" },
      missThree = { 52, "Miss three balls of yarn, and it's game over!" }, total = { 53, "TOTAL:" },
      ready = { 54, "READY" }, start = { 55, "START!" },
      puffReceived = { 56, "Poké Puff received!" }, puffsReceived = { 57, "Poké Puffs received!" },
      nextRank = { 58, "You can now access the next rank!" }, jarFull = { 60, "You can't carry any more Poké Puffs!" },
      titles = { easy = { 23, 29 }, normal = { 30, 36 }, hard = { 37, 43 }, unlimited = { 44, 50 } },
    },
    tile = {
      howTo = { 0, "How to Play" }, tapTwo = { 1, "Tap two tiles to swap their positions." }, pressB = { 2, "Press the B Button to quit." },
      time = { 4, "Time:" }, highScore = { 9, "HIGH SCORE" }, new = { 15, "NEW" }, points = { 74, "{N} Points" },
      quitAsk = { 58, "Quit the puzzle?" }, yes = { 59, "Yes" }, no = { 60, "No" }, begin = { 61, "Begin" }, start = { 62, "START!" },
      viewPicture = { 63, "View Picture" }, playAgain = { 64, "Play Again" }, quit = { 65, "Quit" },
      next = { 70, "NEXT!" }, finished = { 71, "FINISHED!" }, timeRemaining = { 72, "Time Remaining:" },
      seconds = { 80, "{N} Seconds" }, puzzles = { 83, "{N} Puzzles" }, puzzleNo = { 93, "Puzzle No. {N}" }, timesUp = { 95, "TIME'S UP!" },
      tapTiles = { 124, "Tap tiles to swap their positions and complete the picture!" },
      complete = { 125, "Complete the picture within the time limit!" },
      puffReceived = { 126, "Poké Puff Received!" }, puffsReceived = { 127, "Poké Puffs Received!" },
      nextRank = { 128, "You can now access the next rank!" }, jarFull = { 129, "You can't carry any more Poké Puffs!" },
      titles = { easy = { 96, 102 }, normal = { 103, 109 }, hard = { 110, 116 }, unlimited = { 117, 123 } },
    },
  }

  -- our titles when the text is absent (Bulbapedia's list, the same words)
  AT.TITLE_FALLBACK = {
    berry = { easy = { "Berry Amateur", "Berry Superstar" }, normal = { "Berry Semipro", "Berry Master" },
      hard = { "Berry Pro", "Berry Grand Master" }, unlimited = { "Berry Elite", "Magnificent Berry Master" } },
    head = { easy = { "Header Amateur", "Header Hyper Master" }, normal = { "Header Semipro", "Eccentric Header Master" },
      hard = { "Header Pro", "Unbelievable Header Master" }, unlimited = { "Header Elite", "Ultimate Header Master" } },
    tile = { easy = { "Puzzle Amateur", "Puzzle Wizard" }, normal = { "Puzzle Semipro", "Puzzle Champion" },
      hard = { "Puzzle Pro", "Puzzle Hotshot" }, unlimited = { "Puzzle Elite", "Puzzle Legend" } },
  }

  -- file 81: tiers basic .. deluxe x sweet, mint, citrus, mocha, spice; then the six supremes
  local FLAVOR_INDEX = { sweet = 0, mint = 1, citrus = 2, mocha = 3, spice = 4 }
  local TIER_INDEX = { basic = 0, frosted = 1, fancy = 2, deluxe = 3 }
  local SUPREME_INDEX = { wish = 20, honor = 21, spring = 22, summer = 23, fall = 24, winter = 25 }
  function AT.puffLine(id)
    local flavor, tier = tostring(id):match("^puff/(%a+)_(%a+)$")
    if not flavor then return nil end
    if flavor == "supreme" then return SUPREME_INDEX[tier] end
    if FLAVOR_INDEX[flavor] and TIER_INDEX[tier] then return TIER_INDEX[tier] * 5 + FLAVOR_INDEX[flavor] end
    return nil
  end

  -- ------- raw access

  -- the minigames and their picker speak NaviPlay's own words (the fallbacks here), never the
  -- card image's; AT.ownText = false puts the game's text back (for side-by-side checks)
  AT.OWN_FILES = { berry = true, head = true, tile = true, games = true }
  AT.ownText = true

  local function lines(fileKey)
    if AT.ownText and AT.OWN_FILES[fileKey] then return nil end
    local A = G and G.assets
    local id = AT.FILES[fileKey]
    if not (A and A.text and id) then return nil end
    local ok, t = pcall(A.text, id)
    if ok and type(t) == "table" then return t end
    return nil
  end
  AT.lines = lines

  function AT.raw(fileKey, n)
    local t = lines(fileKey)
    local s = t and t[n]
    if type(s) == "string" and s ~= "" then return s end
    return nil
  end

  -- {KEY} -> vars.KEY; a table fills repeats in order; a missing value becomes ""
  function AT.fill(s, vars)
    if not vars then return s end
    local used = {}
    return (s:gsub("{(%u+)}", function(k)
      local v = vars[k]
      if type(v) == "table" then
        used[k] = (used[k] or 0) + 1
        v = v[used[k]] or v[#v]
      end
      if v == nil then return "" end
      return tostring(v)
    end))
  end

  -- the game breaks lines for its 320 px box; our boxes wrap themselves
  function AT.oneLine(s)
    return (tostring(s or ""):gsub("%s*\n%s*", " "))
  end

  -- "{N} Points" with n == 1 drops the plural s the game's own marker would drop
  local function plural(s, vars)
    if type(vars) == "table" and vars.N == 1 then
      s = s:gsub("(%a)s([!%.]?)$", "%1%2")
    end
    return s
  end

  function AT.has(key)
    local row = AT.LINE[key]
    return row ~= nil and AT.raw(row[1], row[2]) ~= nil
  end

  function AT.get(key, vars)
    local row = AT.LINE[key]
    if not row then return key end
    local s = AT.raw(row[1], row[2]) or row[3]
    return AT.oneLine(plural(AT.fill(s, vars), vars))
  end

  -- a line kept with its breaks (for a box that shows them)
  function AT.block(key, vars)
    local row = AT.LINE[key]
    if not row then return key end
    local s = AT.raw(row[1], row[2]) or row[3]
    return plural(AT.fill(s, vars), vars)
  end

  function AT.game(game, key, vars)
    local rows = AT.GAME_LINE[game]
    local row = rows and rows[key]
    if not row then return key end
    local s = AT.raw(game, row[1]) or row[2]
    return AT.oneLine(plural(AT.fill(s, vars), vars))
  end

  function AT.title(game, diff, five)
    local rows = AT.GAME_LINE[game]
    local t = rows and rows.titles and rows.titles[diff]
    local s = t and AT.raw(game, five and t[2] or t[1])
    if s then return s end
    local fb = AT.TITLE_FALLBACK[game] and AT.TITLE_FALLBACK[game][diff]
    return fb and (five and fb[2] or fb[1]) or ""
  end

  function AT.gameName(game)
    local key = ({ berry = "gameBerry", head = "gameHead", tile = "gameTile" })[game]
    return key and AT.get(key) or tostring(game)
  end

  function AT.diffLabel(diff)
    return AT.get(diff)
  end

  function AT.puffName(id, fallback)
    local n = AT.puffLine(id)
    return (n and AT.raw("puffs", n)) or fallback or nil
  end

  -- ------- Décor names (file 110: 34 wallpapers, then the items in catalogue order)

  local decorLine = {}
  function AT.setDecor(Decor)
    decorLine = {}
    local walls, items = 0, 0
    for _, row in ipairs(Decor and Decor.CATALOG or {}) do
      if row.kind == "wall" then
        decorLine[row.id] = walls
        decorLine["thumb/" .. row.id:gsub("^wall/", "")] = walls
        walls = walls + 1
      elseif row.kind == "cushion" or row.kind == "object" then
        decorLine[row.id] = 34 + items
        items = items + 1
      end
    end
  end

  function AT.decorName(id, fallback)
    local n = decorLine[id]
    return (n and AT.raw("decor", n)) or fallback or nil
  end

  return AT
end
