-- Driver: the alley dealer's bags at work (src/training/rocket.lua, Rules.ROCKET_LIST). Buys five
-- in the shop, then, as a player does, hangs each from the drawer (a tap on its slot, Use, Yes)
-- and punches it clear with taps on the bag (the game's hit lock and finishing move on), and
-- reads the Pokemon back from the engine:
--   Speed R      +32 in 25 hits, the Speed stat recalculated
--   Speed R+     with a second wind: its 50 hits in 25 taps (punches count double), +64
--   Attack R+    on 230 Attack: stops at 252 (+22)
--   Defense R    on 500 in all: stops at 510 (+10), Fully Trained
--   Sp. Def R    with no room left: the drawer refuses to hang it
-- Shots of the bags on the stand (the R+ glowing), a finishing move, the drawer.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/rocket_bags_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 1280, tonumber(os.getenv("SHOT_H")) or 720, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
    if os.getenv("PROBE_FALLBACK") == "1" and Xk and Xk._test and Xk._test.forceRom then Xk._test.forceRom(false) end
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local s0 = Runtime.getSession()
  if s0 and #(s0.party or {}) == 0 then
    Party.giveMon(s0, C:require("species", "SPECIES_TORCHIC"), 30)
    Party.giveMon(s0, C:require("species", "SPECIES_ZIGZAGOON"), 10)
  end
  U.wait(30)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  loader.modOptions.play_nav.display_mode = "combined"
  if X.import then
    waitFor(function() return X.import.state() ~= "running" and X.import.state() ~= "finishing" end, 60 * 120)
  end
  local TR = X.training
  local T = TR.session
  local Rk = T.rocket
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function win(ax, ay)
    local r = X.state().rect
    if not r then return -1, -1 end
    local tab = X.state().tabHeight or 0
    return r.x + ax * r.scale, r.y + (ay + tab) * r.scale
  end
  local tid = 0
  local function tapRect(r)
    tid = tid + 1
    local x, y = win(r.x + r.w / 2, r.y + r.h / 2)
    love.touchpressed(tid, x, y, 0, 0, 1); U.wait(2); love.touchreleased(tid, x, y, 0, 0, 1); U.wait(3)
  end
  -- every canvas switched to inside love.draw (Android draws the rest of the frame wrong after
  -- one), by the innermost of PlayNav's files that asked
  local byFile, inDraw = {}, false
  -- the picture being asked for when ui_art draws one (Assets.image wrapped below)
  local asking, artIds, coreWhere = nil, {}, nil
  do
    local A = X.training.session.assets
    if A and A.image then
      local img = A.image
      A.image = function(id, ...) local prev = asking; asking = id; local r = img(id, ...); asking = prev; return r end
    end
  end
  do
    local origDraw, origSet = love.draw, love.graphics.setCanvas
    love.draw = function(...) inDraw = true; local r = { pcall(origDraw, ...) }; inDraw = false
      if not r[1] then error(r[2], 0) end end
    love.graphics.setCanvas = function(...)
      if inDraw and select("#", ...) > 0 and (...) ~= nil then
        local tb = debug.traceback("", 2)
        local file = tb:match("play_nav[/\\]([%w_/\\]+%.lua)") or "(not PlayNav)"
        byFile[file] = (byFile[file] or 0) + 1
        if file:find("ui_art", 1, true) and asking then artIds[asking] = true end
        if file:find("core_app", 1, true) and not coreWhere then coreWhere = tb:match("core_app%.lua:%d+[^\n]*") end
      end
      return origSet(...)
    end
  end
  local function canvasLog()
    local parts = {}
    for f, n in pairs(byFile) do parts[#parts + 1] = f .. " " .. n end
    table.sort(parts)
    log("canvases switched to inside love.draw, by file: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    local ids = {}
    for id in pairs(artIds) do ids[#ids + 1] = id end
    table.sort(ids)
    local egg = 0
    for _, id in ipairs(ids) do if id:find("^rocket/") or id:find("^training/rbag") then egg = egg + 1 end end
    log(("ui_art pictures made inside love.draw: %d, the egg's: %d (%s)"):format(#ids, egg, table.concat(ids, " ")))
    if coreWhere then log("core_app's: " .. coreWhere) end
  end
  local fails = 0
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log(ok and "ok  " or "FAIL", what)
  end

  local ok, err = pcall(function()
    log("open:", TR.open())
    U.wait(20)
    local s = T.session
    local mon = s0.party[1]
    local want = { "spe_r", "spe_rp", "atk_rp", "def_r", "spd_r" }
    -- PROBE_COLD=1: the bags already in the drawer (bought in an earlier session), no code
    -- entered this time: their pictures must still never be made in a draw
    local cold = os.getenv("PROBE_COLD") == "1"
    if cold then
      local bags = TR.store.bags()
      for i = #bags, 1, -1 do bags[i] = nil end
      for _, id in ipairs(want) do bags[#bags + 1] = id end
      log("cold: the drawer holds", table.concat(bags, ","), "unlocked:", T.rocketUnlocked())
    else
    -- the code, the alley, the shop: five bags bought
    for _, b in ipairs(Rk.KONAMI) do U.tap(game, b); U.wait(4) end
    waitFor(function() return not T.rocketBusy() end, 3000)
    T.goTo("rocket")
    waitFor(function() return s.mode == "rocket" and not s.trans end, 3000)
    T.rocketTap("advance"); U.wait(2)
    waitFor(function() local st = Rk.state(); return st and st.phase == "greet" end, 3000)
    T.rocketTap("advance"); T.rocketTap("advance"); U.wait(5)
    s0.money = 200000
    for _, id in ipairs(want) do
      local r = s.rocket
      for i, sid in ipairs(Rk.STOCK) do if sid == id then r.sel = i end end
      T.rocketTap("buy"); T.rocketTap("yes"); U.wait(2)
    end
    log("bought:", table.concat(TR.store.bags(), ","), "money left", s0.money)
    check(#TR.store.bags() == 5 and s0.money == 200000 - 87500, "five bags in the drawer for 87,500")
    T.rocketTap("back"); U.wait(2); T.rocketTap("advance")
    waitFor(function() return s.mode == "core" and not s.trans end, 3000)
    end
    U.wait(10)
    local core = X.apps:get("training_core")
    local drawer = X.apps:get("training_bags")

    local function evs() return TR.host.evsOf(mon) end
    local function setEvs(t)
      local e = evs()
      for k, v in pairs(t) do e[k] = v end
      TR.host.setEvs(mon, e)
      s.evs = TR.host.evsOf(mon)
    end
    -- hang the drawer's bag `id` with taps: open the drawer, its slot, Use, Yes
    local function hang(id)
      tapRect(core.geometry().BAGS)
      waitFor(function() return s.mode == "bags" end, 300)
      U.wait(30)
      local idx
      for i, b in ipairs(TR.store.bags()) do if b == id then idx = i end end
      if not idx then log("no", id, "in the drawer"); return false end
      local g = drawer.geometry()
      tapRect(g.slotRect(idx)); U.wait(8)
      tapRect(g.button(1, 3)); U.wait(8)
      tapRect(g.button(1, 2)); U.wait(8)
      waitFor(function() return s.mode == "core" end, 600)
      U.wait(20)
      return s.rec.bag ~= nil and s.rec.bag.id == id
    end
    -- taps on the bag until it is cleared, each after the hit lock; the finishing move played out
    local function punch(label, shootFinish)
      local taps = 0
      while s.rec.bag and taps < 120 do
        waitFor(function() return (s.anim.lock or 0) <= 0 and not s.anim.finish end, 600)
        tapRect(core.geometry().BAG)
        taps = taps + 1
      end
      if shootFinish then
        waitFor(function() return s.anim.finish and s.anim.finish.t > 1.2 end, 600)
        shot(label .. "_finish")
      end
      waitFor(function() return not s.anim.finish end, 3000)
      U.wait(10)
      return taps
    end

    -- Speed R: +32 in 25 hits
    s.rec.secondWind, s.rec.resting = nil, nil
    local spd0, e0 = mon.speed, evs().spe
    check(hang("spe_r"), "Speed Bag R hangs from the drawer")
    check(s.rec.bag and s.rec.bag.needed == 25, "it needs 25 hits (" .. tostring(s.rec.bag and s.rec.bag.needed) .. ")")
    shot("b01_speed_r_hung")
    local taps = punch("b02_speed_r", true)
    log(("Speed R: %d taps, Speed EVs %d -> %d, Speed %d -> %d"):format(taps, e0, evs().spe, spd0, mon.speed))
    check(evs().spe == e0 + 32, "Speed R gave +32")
    check(mon.speed > spd0, "the Speed stat went up with it")
    shot("b03_speed_r_done")

    -- Speed R+ with a second wind: 25 hits for +64
    s.rec.secondWind, s.rec.resting = true, nil
    e0 = evs().spe
    check(hang("spe_rp"), "Speed Bag R+ hangs")
    check(s.rec.bag and s.rec.bag.needed == 50, "it needs 50 hits (" .. tostring(s.rec.bag and s.rec.bag.needed) .. ")")
    shot("b04_speed_rp_hung")
    taps = punch("b05_speed_rp", false)
    log(("Speed R+: %d taps, Speed EVs %d -> %d"):format(taps, e0, evs().spe))
    check(taps <= 26, "with a second wind each punch counts double: about 25 taps")
    check(evs().spe == e0 + 64, "Speed R+ gave +64")

    -- Attack R+ on 230 Attack: stops at 252
    s.rec.secondWind, s.rec.resting = nil, nil
    setEvs({ atk = 230 })
    check(hang("atk_rp"), "Attack Bag R+ hangs on 230 Attack")
    check(s.rec.bag and s.rec.bag.needed == 50, "it needs 50 hits")
    taps = punch("b06_attack_rp", false)
    log(("Attack R+: %d taps, Attack EVs 230 -> %d"):format(taps, evs().atk))
    check(evs().atk == 252, "Attack stops at 252 (+22)")

    -- Defense R on 500 in all: stops at 510, Fully Trained
    s.rec.secondWind, s.rec.resting = nil, nil
    local e = evs()
    local rest = 500 - (e.spe + e.atk)
    setEvs({ hp = rest, def = 0, spa = 0, spd = 0 })
    local tot = 0
    for _, v in pairs(evs()) do tot = tot + v end
    log("EVs before Defense R:", tot)
    check(hang("def_r"), "Defense Bag R hangs")
    taps = punch("b07_defense_r", false)
    tot = 0
    for _, v in pairs(evs()) do tot = tot + v end
    log(("Defense R: %d taps, Defense EVs -> %d, total %d, fully trained %s"):format(taps, evs().def, tot, tostring(s.rec.fully)))
    check(evs().def == 10 and tot == 510, "Defense stops at 510 in all (+10)")
    check(s.rec.fully == true, "the Pokemon is Fully Trained")

    -- Sp. Def R with no room left: refused
    s.rec.secondWind, s.rec.resting = nil, nil
    local said = nil
    local say = T.say
    T.say = function(text, secs) said = text; return say(text, secs) end
    local hung = hang("spd_r")
    T.say = say
    log("Sp. Def R on a full Pokemon: hung", hung, "said:", tostring(said))
    check(not hung, "a bag for a stat with no room is refused")
    check(TR.store.bags()[1] == "spd_r", "and stays in the drawer")
    shot("b08_refused")
    -- the drawer with it (and an R+ for the glow)
    TR.store.bags()[2] = "hp_rp"
    tapRect(core.geometry().BAGS)
    U.wait(40)
    shot("b09_drawer")
  end)
  if not ok then log("FAIL", tostring(err)); fails = fails + 1 end
  canvasLog()
  log(("DONE, %d failures"):format(fails))
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
