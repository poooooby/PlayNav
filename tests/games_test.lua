-- The minigame ladder: ratings, rewards, participants, unlocks and gifts.
-- Run from the engine root: luajit mods/play_nav/tests/games_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/amie_rules.lua")
local Rules = loadFile("mods/play_nav/src/amie/rules.lua")(N)

-- fakes: a save with meters per key, a party, a host
local saved = { mons = {}, puffs = {}, games = nil, visitors = { gifts = {} } }
local Store = {
  meters = function(key)
    saved.mons[key] = saved.mons[key] or Rules.newMeters()
    return saved.mons[key]
  end,
  saveMons = function() end, puffs = function() return saved.puffs end, savePuffs = function() end,
  games = function()
    saved.games = saved.games or { berry = { unlocked = 1, best = {} }, head = { unlocked = 1, best = {} }, tile = { unlocked = 1, best = {} } }
    return saved.games
  end,
  saveGames = function() end,
  visitors = function() return saved.visitors end, saveVisitors = function() end,
}
local party = {
  { personality = 1, otId = 1, hp = 10 },
  { personality = 2, otId = 1, hp = 10 },
  { personality = 3, otId = 1, hp = 0 },
  { personality = 4, otId = 1, hp = 10, status = "PSN" },
  { personality = 5, otId = 1, hp = 10 },
  { personality = 6, otId = 1, hp = 10 },
}
local host = {
  party = function() return party end,
  monKey = function(m) return m.personality .. ":" .. m.otId end,
  isEgg = function() return false end,
  statusOf = function(m) return m.status end,
}
local C = loadFile("mods/play_nav/src/amie/games/common.lua")({ log = { info = function() end } },
  { Rules = Rules, Store = Store, host = host, session = {} })

-- ------- ratings

T.eq(C.rate("berry", "easy", 0), 0, "no berries, no stars")
T.eq(C.rate("berry", "easy", 4), 0, "four berries is still none")
T.eq(C.rate("berry", "easy", 5), 1, "five berries is one star")
T.eq(C.rate("berry", "easy", 29), 4, "29 berries is four")
T.eq(C.rate("berry", "easy", 30), 4.5, "30 is four and a half")
T.eq(C.rate("berry", "easy", 40), 5, "40 is five")
T.eq(C.rate("berry", "unlimited", 70), 4.5, "unlimited 70 is four and a half")
T.eq(C.rate("head", "normal", 50), 3, "Head It normal 50 points is three stars")
T.eq(C.rate("head", "hard", 349), 4.5, "...hard 349 is four and a half")
T.eq(C.rate("head", "unlimited", 800), 5, "...unlimited 800 is five")
T.eq(C.rate("tile", "easy", 61), 0, "a Tile Puzzle over a minute is no stars")
T.eq(C.rate("tile", "easy", 60), 1, "...a minute flat is one")
T.eq(C.rate("tile", "easy", 31), 3, "...31 s is three")
T.eq(C.rate("tile", "easy", 30), 4, "...30 s is four")
T.eq(C.rate("tile", "easy", 16), 4.5, "...16 s is four and a half")
T.eq(C.rate("tile", "easy", 15), 5, "...15 s is five")
T.eq(C.rate("tile", "hard", 50), 5, "...hard 50 s is five")
T.eq(C.rate("tile", "hard", 121), 1, "...hard 2m01s is one")
T.eq(C.rate("tile", "hard", 120), 2, "...hard 2m flat is two")
T.eq(C.rate("tile", "unlimited", 1), 0, "one unlimited puzzle is no stars")
T.eq(C.rate("tile", "unlimited", 2), 1, "two is one star")
T.eq(C.rate("tile", "unlimited", 17), 5, "17 is five")
T.eq(C.title("berry", "easy", 4.5), "Berry Amateur", "titles below five stars")
T.eq(C.name("berry"), "Berry Picker", "game names fall back to ours")
T.eq(C.diffLabel("hard"), "HARD", "...difficulty labels too")
T.eq(C.line("head", "fever", nil, "FEVER"), "FEVER", "...and HUD words")
do
  -- the session's text helper (the game's words) is consulted first
  local sess = select(2, debug.getupvalue(C.title, 1)) and nil
  local fakeText = {
    title = function(game, diff, five) if game == "berry" and diff == "easy" then return five and "FIVE" or "FOUR" end end,
    gameName = function(game) return game == "berry" and "Berry Picker (text)" or nil end,
    has = function(key) return key == "easy" end, get = function(key) return "Easy" end,
    game = function(game, key, vars) return key == "fever" and "FEVER (text)" or key end,
  }
  C._setText(fakeText)
  T.eq(C.title("berry", "easy", 5), "FIVE", "a rank title from the text")
  T.eq(C.title("berry", "easy", 3), "FOUR", "...below five")
  T.eq(C.title("head", "easy", 3), "Header Amateur", "...a game the text lacks falls back")
  T.eq(C.name("berry"), "Berry Picker (text)", "a game name from the text")
  T.eq(C.name("head"), "Head It", "...else ours")
  T.eq(C.diffLabel("easy"), "Easy", "a difficulty from the text")
  T.eq(C.diffLabel("hard"), "HARD", "...else ours")
  T.eq(C.line("head", "fever", nil, "x"), "FEVER (text)", "a HUD word from the text")
  C._setText(nil)
  T.eq(C.title("berry", "easy", 5), "Berry Superstar", "back to ours")
end
T.eq(C.title("tile", "unlimited", 5), "Puzzle Legend", "...and at five")

-- ------- rewards

do
  local r = C.parseReward("4Fa+2D")
  T.eq(#r, 2, "two reward parts")
  T.eq(r[1].tier, "fancy", "...fancy")
  T.eq(r[1].n, 4, "...four of them")
  T.eq(r[2].tier, "deluxe", "...and deluxe")
  local rng = function() return 0 end
  local ids = C.rewardList("berry", "easy", 5, rng)
  T.eq(#ids, 6, "five stars on easy is six puffs")
  T.eq(ids[1], "puff/sweet_basic", "...basics first")
  T.eq(ids[6], "puff/sweet_frosted", "...then frosted")
  local high = function() return 0.99 end
  ids = C.rewardList("head", "unlimited", 5, high)
  T.eq(#ids, 6, "five stars on unlimited is six puffs")
  T.eq(ids[5], "puff/supreme_summer", "...Head It gives Supreme Summer")
  ids = C.rewardList("tile", "unlimited", 5, high)
  T.eq(ids[6], "puff/supreme_winter", "...Tile Puzzle gives Supreme Winter")
  ids = C.rewardList("berry", "unlimited", 5, high)
  T.eq(ids[6], "puff/supreme_fall", "...Berry Picker gives Supreme Autumn")
  ids = C.rewardList("head", "unlimited", 5, rng)
  T.eq(ids[5], "puff/supreme_spring", "...and any game's Unlimited can give Supreme Spring")
  ids = C.rewardList("tile", "hard", 0, rng)
  T.eq(#ids, 3, "zero stars on hard Tile Puzzle still gives three")
  T.eq(ids[3], "puff/sweet_fancy", "...one of them fancy")
end

-- ------- participants

do
  Store.meters("1:1").enjoyment = 100
  Store.meters("2:1").enjoyment = 90
  Store.meters("5:1").enjoyment = 10
  Store.meters("6:1").enjoyment = 10
  local list, why = C.participants("1:1")
  T.check(list ~= nil, "three healthy Pokemon play")
  T.eq(list[1].key, "1:1", "the active one leads")
  T.eq(list[2].key, "5:1", "...then the least enjoyed")
  T.eq(list[3].key, "6:1", "...ties in party order")
  party[5].hp = 0
  party[6].hp = 0
  list, why = C.participants("1:1")
  T.eq(list, nil, "with two fainted there are too few")
  T.eq(why, "need three healthy Pokemon", "...and the reason says so")
  party[5].hp, party[6].hp = 10, 10
  list = C.participants("9:9")
  T.eq(list[1].key, "1:1", "an unknown active key falls back to the first healthy one")
end

-- ------- finishing a game

do
  T.eq(C.unlocked("berry"), 1, "only easy is open at first")
  T.eq(C.isUnlocked("berry", "normal"), false, "...normal is locked")
  Store.meters("1:1").fullness = 200
  local list = C.participants("1:1")
  local res = C.finish("berry", "easy", 20, list, function() return 0 end)
  T.eq(res.stars, 4, "20 berries on easy is four stars")
  T.eq(#res.puffs, 5, "...five puffs")
  T.eq(#saved.puffs, 5, "...in the jar")
  T.eq(res.unlockedNew, "normal", "...and normal unlocks")
  T.eq(C.unlocked("berry"), 2, "the record says so")
  T.eq(res.gifts[1], "D", "unlocking normal owes a set D gift")
  T.eq(#saved.visitors.gifts, 1, "...recorded as pending")
  T.eq(Store.meters("1:1").fullness, 90, "the active Pokemon lost 110 fullness")
  T.eq(Store.meters("5:1").enjoyment, 90, "...and a participant gained 80 enjoyment")
  T.eq(C.best("berry", "easy"), 4, "the best rating is kept")
  res = C.finish("berry", "easy", 2, list)
  T.eq(res.unlockedNew, nil, "a poor run unlocks nothing new")
  T.eq(C.best("berry", "easy"), 4, "...and keeps the best")
  res = C.finish("head", "easy", 300, list)
  T.eq(res.fiveStar, true, "300 points on easy Head It is five stars")
  T.eq(res.gifts[1], "D", "...unlocking normal owes set D")
  T.eq(res.gifts[2], "A", "...and the five stars owe set A")
  T.eq(res.newHigh, true, "...and is a new high score")
  T.eq(C.highScore("head", "easy"), 300, "the high score is kept per difficulty")
  res = C.finish("head", "easy", 120, list)
  T.eq(res.newHigh, false, "a lower score is no new high")
  T.eq(C.highScore("head", "easy"), 300, "...and keeps the best")
  T.eq(C.highScore("berry", "easy"), 20, "Berry Picker's HIGH SCORE is its berries")
  T.eq(C.highScore("tile", "easy"), 0, "a timed Tile Puzzle keeps times, not a high score")
  res = C.finish("tile", "unlimited", 17, list)
  T.eq(res.stars, 5, "17 unlimited puzzles is five stars")
  T.eq(res.unlockedNew, nil, "nothing above unlimited")
  T.eq(res.gifts[1], "E", "five stars on unlimited owes set E")
  -- Tile Puzzle's three best times
  res = C.finish("tile", "easy", 48.7, list)
  T.eq(res.rank, 1, "a first easy puzzle is the best time")
  T.eq(res.times[1], 48, "...kept in whole seconds")
  res = C.finish("tile", "easy", 60, list)
  T.eq(res.rank, 2, "a slower one is second")
  res = C.finish("tile", "easy", 30, list)
  T.eq(res.rank, 1, "a faster one goes to the top")
  T.eq(table.concat(res.times, ","), "30,48,60", "...the list in order")
  res = C.finish("tile", "easy", 90, list)
  T.eq(res.rank, nil, "a fourth-best time is not kept")
  T.eq(#C.times("tile", "easy"), 3, "...three are kept")
  res = C.finish("tile", "easy", 48, list)
  T.eq(res.rank, 3, "a tie goes below the older one")
  T.eq(table.concat(C.times("tile", "easy"), ","), "30,48,48", "...and the slowest falls off")
  T.eq(table.concat(C.times("tile", "unlimited"), ","), "17", "unlimited keeps the most puzzles")
end

T.finish("play_nav games")
