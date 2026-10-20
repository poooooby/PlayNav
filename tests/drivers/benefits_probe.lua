-- Driver: each of Pokemon-Amie's battle benefits on screen, a shot of each line as the game
-- shows it. The lead (Torchic) is at 255 affection; the affection rolls are forced through
-- the benefits' own seam (B.forceRoll) and the dodge by its accuracy cut, so each one happens
-- on cue. One wild battle a benefit:
--   b1 a super-effective hit ("That's it! I knew you could do it!"), a critical hit in sync,
--      and the boosted Exp. Points when the foe faints
--   b2 the foe's move avoided ("read ...'s mind")
--   b3 a knockout endured at 1 HP ("toughed it out"), the HP bar red ("in a bit of a pinch")
--   b4 a Potion in battle ("thrilled to bits")
--   b5 asleep ("fast asleep... Zzz"), then shaken awake at the turn's end
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/benefits_probe.lua love .

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 960, tonumber(os.getenv("SHOT_H")) or 640, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  pcall(Map.load, nil, game, "EM_ROUTE101", { x = 10, y = 10, facing = "down" })
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 20)
    Party.giveMon(s, C:require("species", "SPECIES_MARILL"), 18)
  end
  U.wait(60)
  waitFor(function() return game.phase == "field" end, 1200)
  -- the engine's on-screen pad off for the shots
  do
    local okTC, TC = pcall(require, "src.core.TouchControls")
    if okTC and type(TC) == "table" then
      local draw0 = love.draw
      love.draw = function(...)
        if TC.enabled ~= false then TC.enabled = false end
        return draw0(...)
      end
    end
  end
  local X = game.mods.exports.play_nav
  local A = X.amie
  local B = A.benefits
  local lead = s.party[1]
  local key = A.monKey(lead)
  local m = A.store.meters(key)
  local aff0 = m.affection
  m.affection = 255
  A.store.saveMons()
  log("lead", lead.species, "affection", m.affection, "level", A.rules.level(m.affection))
  pcall(function()
    local Bag = require("src.core.game3.bag")
    Bag.add(s.bag, C:require("items", "ITEM_POTION"), 3)
  end)

  local BattleAPI = require("src.battle.game3.BattleAPI")
  local bapi = BattleAPI.new(game)
  local intent = 0
  local function snap() return bapi:snapshot() end
  local function submit(sn, t)
    intent = intent + 1
    t.id, t.revision = intent, sn.revision
    return bapi:submit(t)
  end
  local function battleState()
    local Battle = require("src.core.game3.battle")
    local ad = Battle._adapter
    return ad and ad._st, ad
  end
  local function slotOf(sn, name)
    for _, mv in ipairs(sn.moves or {}) do
      if tostring(mv.name):upper():find(name, 1, true) then return mv.slot end
    end
    return 1
  end

  -- the lines to catch, by a piece of their text: watched every frame, each shot once it has
  -- been up long enough to finish printing (some lines go by without waiting for A)
  local seen, upFor = {}, {}
  local PRINTED_S = 2.5   -- the text prints on the clock, not by frames
  local function catch(sn, wanted)
    local text = table.concat(sn.message or {}, " ")
    local low = text:lower()
    -- while a line is up it is shot every quarter second into one file, so the file keeps the
    -- most printed frame; caught once the line has gone or after PRINTED_S
    local now = love.timer.getTime()
    for name, piece in pairs(wanted) do
      if not seen[name] then
        local up = upFor[name]
        if low:find(piece:lower(), 1, true) then
          if not up then up = { t = now, last = 0, n = 0 }; upFor[name] = up end
          if now - up.last >= 0.25 then
            up.last = now
            if U.shot(game, ("%s/%s.png"):format(dir, name)) then up.n = up.n + 1 end
            up.text = text
          end
          if now - up.t >= PRINTED_S then seen[name] = true end
        elseif up and up.n > 0 then
          seen[name] = true
        end
        if seen[name] then log(("shot %s (%d frames): %s"):format(name, up and up.n or 0, up and up.text or text)) end
      end
    end
  end

  -- one wild battle: plan.turn(sn, st, ad, n) -> an intent table for the menu (or nil: fight
  -- with plan.move); ends when the battle does
  local function battle(name, species, level, plan)
    log("== " .. name)
    local okB, errB = pcall(function()
      local BattleBridge = require("src.core.game3.battle_bridge")
      local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = C:require("species", species), level = level }, {})
      if not ok then error(tostring(err)) end
    end)
    if not okB then log("  could not start:", tostring(errB)); return end
    local turns, started, idle = 0, false, 0
    for _ = 1, 9000 do
      U.wait(1)
      local sn = snap()
      local p = sn and sn.prompt
      if sn then started = true; catch(sn, plan.lines) end
      -- a battle with nothing asked of it for a while is waiting on a key
      idle = (sn and not p) and idle + 1 or 0
      if idle > 400 then idle = 0; U.tap(game, "a") end
      if p == "advance" then
        -- held until a line being watched has printed
        local holding = false
        for name in pairs(plan.lines) do if upFor[name] and not seen[name] then holding = true end end
        if not holding then U.tap(game, "a"); U.wait(3) end
      elseif p == "menu" then
        turns = turns + 1
        local st, ad = battleState()
        if turns == 1 then
          log("  moves:", (function()
            local t = {}
            for _, mv in ipairs(sn.moves or {}) do t[#t + 1] = mv.slot .. "=" .. tostring(mv.name) end
            return table.concat(t, " ")
          end)())
        end
        local t = plan.turn and plan.turn(sn, st, ad, turns)
        if t and t.kind == "menu" then submit(sn, t)
        else submit(sn, { kind = "menu", choice = "fight" }) end
      elseif p == "moves" then
        submit(sn, { kind = "move", slot = slotOf(sn, plan.move and plan.move(turns) or "EMBER") })
      elseif p == "target" then
        submit(sn, { kind = "target", target = sn.target or 1 })
      elseif not sn and started then
        break
      end
    end
    U.wait(40)
    B.forceRoll = nil
    -- the lead back to full for the next
    lead.hp = lead.maxHp
    lead.status = nil
  end

  -- each foe drops to level 2 before it is knocked out, so the Exp. never levels the lead up
  -- (a level-up's evolution or new move would hold up the next battle)
  local function heal() lead.hp, lead.status = lead.maxHp, nil end

  -- b1: Ember on a Bug (super effective), a forced crit (level 5's second chance), the Exp.
  heal()
  battle("b1 super effective, critical hit, Exp.", "SPECIES_CASCOON", 60, {
    lines = { b1_super_effective = "I knew you could do it", b1_critical_hit = "landed a critical hit",
      b1_exp_boosted = "exp. points" },
    turn = function(sn, st, ad, n)
      -- the crit forced until its line has shown (an engine crit or a miss leaves ours out)
      local done = (seen.b1_critical_hit and seen.b1_super_effective) or n > 8
      B.forceRoll = (not done) and function(lo) return lo end or nil
      -- after the lines, the foe goes quickly
      if done and st and st.enemy and st.enemy.mon then st.enemy.mon.hp, st.enemy.mon.level = 1, 2 end
    end,
    move = function() return "EMBER" end,
  })
  log("  exp boosts so far:", B.stats.exp, "crits:", B.stats.crit)

  -- b2: the foe's move misses the fond Pokemon (its accuracy cut by all of it, for the shot)
  heal()
  local NB = A.rules.N.BENEFITS
  local dodge0 = NB.DODGE_POINTS
  battle("b2 avoided", "SPECIES_ZIGZAGOON", 12, {
    lines = { b2_avoided = "avoided the move" },
    turn = function(sn, st, ad, n)
      if n > 8 then seen.b2_avoided = seen.b2_avoided or false end
      local done = seen.b2_avoided ~= nil
      NB.DODGE_POINTS = done and dodge0 or 100
      if done and st and st.enemy and st.enemy.mon then st.enemy.mon.hp, st.enemy.mon.level = 1, 2 end
    end,
    move = function() return seen.b2_avoided ~= nil and "EMBER" or "SAND" end,
  })
  NB.DODGE_POINTS = dodge0

  -- b3: at 30% HP against a strong foe: the knockout endured at 1 HP, the bar turning red
  heal()
  lead.hp = math.max(2, math.floor(lead.maxHp * 0.3))
  battle("b3 endured, pinch", "SPECIES_MIGHTYENA", 35, {
    lines = { b3_toughed_it_out = "toughed it out", b3_pinch = "bit of a pinch" },
    turn = function(sn, st, ad, n)
      local done = seen.b3_toughed_it_out and seen.b3_pinch or n > 10
      if not done then
        -- until it lands: 30% HP again, the foe's accuracy left whole, the endure roll forced
        B.forceRoll = function(lo) return lo end
        NB.DODGE_POINTS = 0
        if st and st.player and st.player.mon then
          st.player.mon.hp = math.max(2, math.floor(st.player.mon.maxHp * 0.3))
        end
      else
        B.forceRoll = nil
        NB.DODGE_POINTS = dodge0
        -- the lines seen: the lead back up, the foe down
        if st and st.player and st.player.mon then st.player.mon.hp = st.player.mon.maxHp end
        if st and st.enemy and st.enemy.mon then st.enemy.mon.hp, st.enemy.mon.level = 1, 2 end
      end
    end,
    move = function() return (seen.b3_toughed_it_out and seen.b3_pinch) and "EMBER" or "SAND" end,
  })

  NB.DODGE_POINTS = dodge0

  -- b4: a Potion on the fond Pokemon in battle (the bag's own item code, as the bag screen calls it)
  heal()
  battle("b4 Potion", "SPECIES_ZIGZAGOON", 5, {
    lines = { b4_thrilled = "thrilled to bits" },
    turn = function(sn, st, ad, n)
      if n == 1 and st and ad then
        st.player.mon.hp = math.floor(st.player.mon.maxHp / 2)
        local okU, res = pcall(function()
          local BattleItems = require("src.core.game3.battle.items")
          -- quiet, as the bag screen uses it: its own lines are not pushed over the menu
          local quiet = setmetatable({ say = function() end, sayText = function() end, pushEvent = function() end },
            { __index = ad })
          return BattleItems.use(st, quiet, s.bag, s, C:require("items", "ITEM_POTION"), 1, 0)
        end)
        log("  potion:", tostring(okU), tostring(res))
      elseif n >= 3 and st and st.enemy and st.enemy.mon then
        st.enemy.mon.hp, st.enemy.mon.level = 1, 2
      end
    end,
    move = function(n) return n <= 2 and "SAND" or "EMBER" end,
  })

  -- b5: put to sleep: the game's line as the turn starts; shaken awake at the turn's end
  heal()
  battle("b5 asleep, shaken awake", "SPECIES_ZIGZAGOON", 5, {
    lines = { b5_fast_asleep = "fast asleep... zzz", b5_shook_awake = "shook itself awake" },
    turn = function(sn, st, ad, n)
      if n == 1 and st and ad then
        ad:applyStatus(st.player, "SLP", nil, { force = true, turns = 3 })
        B.forceRoll = function(lo) return lo end
      elseif n >= 3 then
        B.forceRoll = nil
        if st and st.enemy and st.enemy.mon then st.enemy.mon.hp, st.enemy.mon.level = 1, 2 end
      end
    end,
    move = function(n) return n <= 2 and "SAND" or "EMBER" end,
  })

  local missing = {}
  for _, name in ipairs({ "b1_super_effective", "b1_critical_hit", "b1_exp_boosted", "b2_avoided", "b3_toughed_it_out",
    "b3_pinch", "b4_thrilled", "b5_fast_asleep", "b5_shook_awake" }) do
    if not seen[name] then missing[#missing + 1] = name end
  end
  log("benefits counted:", "exp", B.stats.exp, "crit", B.stats.crit, "dodge", B.stats.dodge, "endure", B.stats.endure,
    "cure", B.stats.cure)
  log("not caught:", #missing == 0 and "none" or table.concat(missing, " "))
  m.affection = aff0
  A.store.saveMons()
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
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
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
