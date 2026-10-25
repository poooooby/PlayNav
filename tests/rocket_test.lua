-- The Konami code's alley (src/training/rocket.lua), headless: the code's matcher, the dealer's
-- bags (Rules.ROCKET_LIST), a purchase and its refusals, and the session's side with a fake host
-- (the unlock, the way in, buying into the drawer, leaving).
-- Run from the engine root: luajit mods/play_nav/tests/rocket_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local ROOT = "mods/play_nav/"
local function loadFile(path) return assert(loadfile(ROOT .. path))() end
local N = loadFile("data/training_rules.lua")
local Rules = loadFile("src/training/rules.lua")(N, {})
local makeRocket = loadFile("src/training/rocket.lua")

-- ------- the bags

T.eq(#Rules.ROCKET_LIST, 12, "twelve dealer's bags: an R and an R+ per stat")
T.eq(#Rules.BAG_LIST, 26, "the game's 26 bags are as they were")
for _, id in ipairs(Rules.ROCKET_LIST) do
  local b = Rules.bag(id)
  T.check(b.kind == "stat" and b.rocket, id .. " is a stat bag of the dealer's")
  T.check(Rules.GAME_INDEX[id] == nil, id .. " is not one of the game's (no drop, no game text)")
end
local r, rp = Rules.bag("spe_r"), Rules.bag("spe_rp")
T.eq(r.ev, 32, "Speed R: +32"); T.eq(rp.ev, 64, "Speed R+: +64")
T.eq(r.hits, 25, "R: 25 hits"); T.eq(rp.hits, 50, "R+: 50 hits")
T.eq(r.price, 12500, "R: 12,500"); T.eq(rp.price, 25000, "R+: 25,000")
T.check(rp.glow and not r.glow, "only the R+ glows")
T.eq(Rules.bagArt("spe_r"), "training/rbag_spe", "R's picture")
T.eq(Rules.bagArt("spe_rp"), "training/rbag_spe_plus", "R+'s picture")
T.eq(Rules.bagArt("hp_s"), "training/sand_bag_01", "the game's bags keep their icons")
T.eq(r.label, "Speed Bag R", "its name")
-- a blank-bag find never turns one up
local seen = {}
for i = 0, 2599 do
  local id = Rules.pickBlackBag(function() return (i + 0.5) / 2600 end)
  if id then seen[id] = true end
end
for _, id in ipairs(Rules.ROCKET_LIST) do T.check(not seen[id], id .. " is never found in the blank bag") end
-- the caps still hold: an R+ on 230 Speed adds 22
do
  local evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 230 }
  T.eq(Rules.addEv(evs, "spe", rp.ev), 22, "an R+ stops at 252")
  evs = { hp = 252, atk = 252, def = 0, spa = 0, spd = 0, spe = 0 }
  T.eq(Rules.addEv(evs, "def", rp.ev), 6, "and at 510 in all")
end

-- ------- the code

local host = { money = function() return 0 end, playSe = function() end }
local store = { list = {} }
local Store = { bags = function() return store.list end, save = function() end }
local sess = { onChange = function() end, playSe = function() end, bagName = function(id) return Rules.bag(id).label end }
local Rk = makeRocket({ log = { warn = function() end } }, sess, { host = host, Rules = Rules, Store = Store })

local function enter(seq)
  local m = Rk.matcher()
  local done = 0
  for _, b in ipairs(seq) do if Rk.feed(m, b) then done = done + 1 end end
  return done
end
local K = { "up", "up", "down", "down", "left", "right", "left", "right", "b", "a", "start" }
T.eq(enter(K), 1, "the code")
T.eq(enter({ "up", "up", "up", "down", "down", "left", "right", "left", "right", "b", "a", "start" }), 1, "an extra up first still counts")
T.eq(enter({ "up", "up", "down", "down", "left", "right", "b", "a", "start" }), 0, "the short code (one left right) is not it")
T.eq(enter({ "up", "up", "down", "down", "left", "right", "left", "right", "left", "right", "b", "a", "start" }), 0, "an extra left right breaks it")
T.eq(enter({ "up", "down", "down", "left", "right", "left", "right", "b", "a", "start" }), 0, "one up short: nothing")
T.eq(enter({ "up", "up", "down", "down", "left", "right", "left", "right", "a", "b", "start" }), 0, "B and A swapped: nothing")
T.eq(enter({ "start" }), 0, "START alone: nothing")
local twice = {}
for _ = 1, 2 do for _, b in ipairs(K) do twice[#twice + 1] = b end end
T.eq(enter(twice), 2, "twice in a row: twice")
local broken = { "up", "up", "down", "down", "a" }
for _, b in ipairs(K) do broken[#broken + 1] = b end
T.eq(enter(broken), 1, "a wrong button, then the whole code: once")

-- ------- a purchase

local bags = {}
local ok, left = Rk.buy(15000, bags, "atk_r")
T.check(ok and left == 2500, "an R for 12,500 out of 15,000 leaves 2,500")
T.eq(#bags, 0, "Rk.buy changes nothing itself")
ok, left = Rk.buy(15000, bags, "atk_rp")
T.check(not ok and left == "money", "an R+ for 25,000 out of 15,000: refused for money")
for i = 1, 12 do bags[i] = "hp_s" end
ok, left = Rk.buy(999999, bags, "atk_r")
T.check(not ok and left == "full", "a full drawer: refused for room, whatever the money")
T.check(not Rk.buy(100, {}, "hp_s"), "the game's bags are not for sale")
T.eq(Rk.money(50000), "50,000", "money with commas")
T.eq(Rk.money(999999), "999,999", "six digits")
T.eq(Rk.money(500), "500", "three digits")
local last = nil
for _ = 1, 30 do
  local line = Rk.pick(Rk.LINES.sold, last)
  T.check(line ~= last, "a line is never the one just said")
  last = line
end

-- ------- the session's side: the unlock, the alley, buying, leaving

do
  local sounds, money = {}, 30000
  local fhost = {
    money = function() return money end,
    spendMoney = function(n) if money < n then return false end money = money - n; return true end,
    playSe = function(name) sounds[#sounds + 1] = name end,
  }
  store.list = {}
  local S = { onChange = function() end, bagName = function(id) return Rules.bag(id).label end }
  function S.playSe(ev, standIn) sounds[#sounds + 1] = ev end
  S.session = { mode = "core", anim = { hit = 0, t = 0 }, rec = {} }
  function S.goTo(mode) S.session.trans = { to = mode }; S.went = mode; return true end
  local R2 = makeRocket({ log = { warn = function() end } }, S, { host = fhost, Rules = Rules, Store = Store })
  -- the code through the logic steps' pressed buttons
  for _, b in ipairs(K) do S.konamiStep({ pressed = { [b] = true } }) end
  T.check(S.rocketUnlocked(), "the code unlocks the R")
  T.check(S.rocketBusy(), "the unlock plays (the home screen waits)")
  for _ = 1, 200 do S.tickRocket(S.session, 1 / 60) end
  T.check(not S.rocketBusy(), "and ends")
  local stung = false
  for _, s in ipairs(sounds) do if s == "rocket_sting" then stung = true end end
  T.check(stung, "with its sting")
  -- the code is not read off the home screen
  S.session.mode = "bags"
  S.session.rocketUnlocked = nil
  for _, b in ipairs(K) do S.konamiStep({ pressed = { [b] = true } }) end
  T.check(not S.rocketUnlocked(), "not in the bag drawer")
  S.session.mode = "rocket"
  S.rocketSwitched("rocket")
  local st = R2.state()
  T.eq(st.phase, "walk", "the alley starts with the walk")
  -- no scene: straight to him
  S.tickRocket(S.session, 0.1)
  for _ = 1, 80 do S.tickRocket(S.session, 1 / 30) end
  st = R2.state()
  T.eq(st.phase, "greet", "he greets")
  T.check(st.line ~= nil and st.dealer == 1, "in the light, talking")
  S.rocketTap("advance")   -- the line out at once
  S.rocketTap("advance")   -- on to the shop
  st = R2.state()
  T.eq(st.phase, "shop", "the shop opens")
  T.eq(st.id, Rules.ROCKET_LIST[1], "the first bag picked")
  -- down to an R+ and buy it: asked first
  local input = function(b) return { wasPressed = function(_, x) return x == b end } end
  for _ = 1, 6 do S.rocketInput(input("down")) end
  st = R2.state()
  T.eq(st.id, "hp_rp", "six down: the HP R+")
  T.check(st.top > 1, "the list scrolled")
  S.rocketInput(input("a"))
  T.eq(R2.state().confirm, true, "asked, Yes picked first")
  S.rocketInput(input("a"))
  T.eq(money, 5000, "25,000 spent")
  T.eq(store.list[1], "hp_rp", "the bag in the drawer")
  local saidSold = false
  for _, l in ipairs(Rk.LINES.sold) do if R2.state().line == l then saidSold = true end end
  T.check(saidSold, "a word after the sale")
  -- short of money: refused, nothing taken
  S.rocketInput(input("a")); S.rocketInput(input("a"))
  T.eq(money, 5000, "short: no money taken")
  T.eq(#store.list, 1, "short: no bag")
  -- No: nothing
  S.rocketInput(input("up"))
  S.rocketInput(input("a")); S.rocketInput(input("b"))
  T.eq(R2.state().confirm, nil, "B answers No")
  -- a full drawer
  for i = 2, 12 do store.list[i] = "hp_s" end
  money = 999999
  S.rocketInput(input("a")); S.rocketInput(input("a"))
  T.eq(R2.state().line, "Come back when you have room.", "a full drawer: come back with room")
  T.eq(money, 999999, "full: no money taken")
  -- leaving: his last word, then back
  S.rocketInput(input("b"))
  st = R2.state()
  T.eq(st.phase, "bye", "B: his goodbye")
  T.eq(st.line, "If anyone asks, you didn't get this from me.", "the goodbye")
  for _ = 1, 400 do S.tickRocket(S.session, 1 / 30) end
  T.eq(S.went, "core", "and back to the home screen")
end

T.finish("play_nav rocket")
