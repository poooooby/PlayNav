-- Affection benefits in battle (X/Y, ORAS):
--   level 2+  1.2x experience
--   level 3+  endure a knockout at 1 HP: 10%, 15% at level 4, 20% at 200+, 25% at level 5
--   level 4+  shake off a status at the end of the turn, 20%
--   200+      the foe's accuracy drops 10 points (moves that cannot miss never reach the hook)
--   level 5   critical-hit chance doubled
-- and the game's lines at level 4+ that change nothing (Bulbapedia "Affection", the X / Y / ORAS
-- wording): a super-effective hit, the HP bar turning red, an HP item used on it, asleep
-- Everything goes through the engine's public hooks and events; nothing is
-- patched. Skipped in link, facility and tutorial battles, before any extra
-- RNG draw, so a link battle never desyncs.
--
-- deps = { Rules, Store, host, enabled = fn() -> bool }

local unpack = unpack or table.unpack

return function(mod, deps)
  local Rules, Store, host = deps.Rules, deps.Store, deps.host
  local N = Rules.N.BENEFITS
  local B = { installed = false, stats = { exp = 0, crit = 0, dodge = 0, endure = 0, cure = 0 },
    -- how often the engine reached each hook (applied or not): the drivers' proof of wiring
    calls = { exp = 0, crit = 0, accuracy = 0, damage = 0, turn = 0 } }

  local function enabled()
    if deps.enabled then return deps.enabled() ~= false end
    return true
  end

  local function skip(st)
    if type(st) ~= "table" then return true end
    if st.link or st.safari or st.facility or st.trainerTower or st.battleTower or st.eReader
        or st.pokedude or st.oldManTutorial then return true end
    local k = st.kinds
    if type(k) == "table" and (k.frontier or k.recordedLink or k.firstBattle or k.tutorial or k.unionRoom or k.spectate) then
      return true
    end
    return false
  end

  local function isPlayer(st, b)
    if type(b) ~= "table" or b.side ~= "player" then return false end
    local half = tonumber(st and st.playerHalf) or 6
    return (tonumber(b.partyIndex) or 1) <= half
  end

  local function keyOf(mon)
    if type(mon) ~= "table" then return nil end
    return ("%s:%s"):format(tostring(mon.personality or "?"), tostring(mon.otId or "?"))
  end

  -- affection points of a party / battler mon from the mod save
  local function affectionOf(mon)
    local key = keyOf(mon)
    if not key then return 0 end
    local all = Store.mons()
    local m = all[key]
    return type(m) == "table" and (m.affection or 0) or 0
  end
  B.affectionOf = affectionOf

  local function levelOf(mon) return Rules.level(affectionOf(mon)) end

  local function nameOf(mon)
    if host and host.displayName then
      local ok, n = pcall(host.displayName, mon)
      if ok and type(n) == "string" then return n end
    end
    return "The Pokemon"
  end

  local function trainerName(st)
    local n = st and st.playerName
    if type(n) == "string" and n ~= "" then return n end
    return "its Trainer"
  end

  local function adapter()
    local ok, Battle = pcall(require, "src.core.game3.battle")
    if ok and type(Battle) == "table" then return Battle._adapter end
    return nil
  end

  local function say(text)
    if B.sayHook then return B.sayHook(text) end   -- the tests read the lines here
    local ad = adapter()
    if ad and ad.say then
      local ok, err = pcall(ad.say, ad, text)
      if not ok then mod.log:warn("amie benefits: message failed: %s", tostring(err)) end
    end
  end

  local function rngOf(ctx)
    if type(ctx.rng) == "function" then return ctx.rng end
    local ad = adapter()
    if ad and ad.rng then
      local ok, fn = pcall(ad.rng, ad)
      if ok and type(fn) == "function" then return fn end
    end
    return function(lo, hi) return math.random(lo, hi) end
  end

  local function endurePct(points)
    local lv = Rules.level(points)
    if lv >= 5 then return N.ENDURE_PCT[5] end
    if points >= 200 then return N.ENDURE_PCT_200 end
    return N.ENDURE_PCT[lv] or 0
  end
  B.endurePct = endurePct

  -- a battler's status as the engine spells it ("SLP" or "SLEEP", ...) -> the game's code
  local STATUS_CODE = { SLEEP = "SLP", POISON = "PSN", TOXIC = "TOX", BURN = "BRN", FREEZE = "FRZ",
    FROZEN = "FRZ", PARALYSIS = "PAR", PARALYZE = "PAR" }
  local function statusCode(status)
    if not status then return nil end
    local s = tostring(status):upper()
    return STATUS_CODE[s] or s:sub(1, 3)
  end
  B.statusCode = statusCode

  local STATUS_TEXT = {
    BRN = "%s blew on its burn and made it better so that %s wouldn't worry!",
    PSN = "%s managed to expel the poison so that %s wouldn't worry!",
    TOX = "%s managed to expel the poison so that %s wouldn't worry!",
    SLP = "%s shook itself awake so that %s wouldn't worry!",
    FRZ = "%s melted the ice with its fiery determination so that %s wouldn't worry!",
    PAR = "%s gathered all its energy to break through its paralysis so that %s wouldn't worry!",
  }

  local pendingText = {}  -- printed at the start of the next turn
  -- printed when the next move starts or the turn ends: after the game's own lines for the hit
  -- or the item ("It's super effective!", the HP restored), before the foe's "used ...!"
  local soonText = {}

  -- level 4's flavour lines (B.FLAVOR_LEVEL); the HP bar is red under 10 of its 48 pixels (Gen 3)
  B.FLAVOR_LEVEL = 4
  B.LINES = {
    super = "That's it! I knew you could do it!",
    pinch = "%s is in a bit of a pinch. It looks like it might cry...",
    healed = "%s is thrilled to bits!",
    asleep = "%s is fast asleep... Zzz... Zzz...",
  }
  local function inRed(hp, max)
    hp, max = tonumber(hp) or 0, tonumber(max) or 0
    return hp > 0 and max > 0 and math.floor(hp * 48 / max) < 10
  end
  B.inRed = inRed
  local function fond(mon) return levelOf(mon) >= B.FLAVOR_LEVEL end

  function B.install()
    if B.installed or not (mod.hooks and mod.events) then return false end
    B.installed = true

    mod.hooks:wrap("exp.gain", function(next, ctx)
      B.calls.exp = B.calls.exp + 1
      local amount = next()
      if not enabled() or type(ctx) ~= "table" or skip(ctx.battle) then return amount end
      if levelOf(ctx.mon) >= N.EXP_LEVEL then
        B.stats.exp = B.stats.exp + 1
        return math.floor((tonumber(amount) or 0) * N.EXP_MULT)
      end
      return amount
    end)

    mod.hooks:wrap("battle.crit", function(next, ctx)
      B.calls.crit = B.calls.crit + 1
      local hit = next()
      if hit or not enabled() or type(ctx) ~= "table" then return hit end
      local st = ctx.battle
      if skip(st) or (st and st.pokedude) or not isPlayer(st, ctx.attacker) then return hit end
      if levelOf(ctx.attacker.mon) < N.CRIT_LEVEL then return hit end
      local okR, RulesG3 = pcall(require, "src.core.game3.battle.rules")
      local CHANCE = okR and RulesG3.crit and RulesG3.crit.CHANCE or { [0] = 16, [1] = 8, [2] = 4, [3] = 3, [4] = 2 }
      -- the attacker's crit stage (high-crit move, Focus Energy, Scope Lens...): the engine's hook
      -- does not pass it, so ask the engine's own rule, as its roll does
      local stage = tonumber(ctx.stage)
      if not stage and okR and RulesG3.crit and RulesG3.crit.stage then
        local okS, s = pcall(RulesG3.crit.stage, ctx.attacker, ctx.moveNum or ctx.moveId, ctx.highCrit)
        if okS then stage = tonumber(s) end
      end
      local den = CHANCE[stage or 0] or 16
      if den <= 2 then return true end
      -- a second draw with odds (1/den) / (1 - 1/den) brings the total to 2/den
      local rng = rngOf(ctx)
      local v = rng(0, den - 2)
      if v == 0 then
        B.stats.crit = B.stats.crit + 1
        pendingText[#pendingText + 1] = ("%s is so in sync with %s's wishes that it landed a critical hit!")
          :format(nameOf(ctx.attacker.mon), trainerName(st))
        return true
      end
      return hit
    end)

    mod.hooks:wrap("battle.accuracy", function(next, ctx)
      B.calls.accuracy = B.calls.accuracy + 1
      if enabled() and type(ctx) == "table" then
        local st = ctx.battle
        if not skip(st) and isPlayer(st, ctx.target) and not isPlayer(st, ctx.user)
            and affectionOf(ctx.target.mon) >= N.DODGE_AFFECTION then
          local eff = ctx.move and tonumber(ctx.move.effect)
          if eff ~= 17 and eff ~= 78 then
            ctx.accuracy = math.max(0, (tonumber(ctx.accuracy) or 100) - N.DODGE_POINTS)
            local hit = next()
            if not hit then
              B.stats.dodge = B.stats.dodge + 1
              say(("%s read %s's mind and avoided the move!"):format(nameOf(ctx.target.mon), trainerName(st)))
            end
            return hit
          end
        end
      end
      return next()
    end)

    mod.hooks:wrap("battle.damage", function(next, ctx)
      B.calls.damage = B.calls.damage + 1
      local dmg, info = next()
      if not enabled() or type(ctx) ~= "table" then return dmg, info end
      local st = ctx.battle
      local target = ctx.target
      if skip(st) or not isPlayer(st, target) or type(info) == "table" and info.failed then return dmg, info end
      if (tonumber(target.substituteHP) or 0) > 0 then return dmg, info end
      local hp = target.mon and tonumber(target.mon.hp) or 0
      local d = tonumber(dmg) or 0
      if hp <= 1 or d < hp then return dmg, info end
      local pct = endurePct(affectionOf(target.mon))
      if pct <= 0 then return dmg, info end
      local rng = rngOf(ctx)
      if rng(0, 99) < pct then
        B.stats.endure = B.stats.endure + 1
        target._amieEndure = true
        return hp - 1, info
      end
      return dmg, info
    end)

    mod.events:on("battle.damage_dealt", function(ev)
      local target = ev and ev.target
      if type(target) == "table" and target._amieEndure then
        target._amieEndure = nil
        say(("%s toughed it out to show its best side to %s!"):format(nameOf(target.mon), trainerName(ev.battle)))
      end
      if not enabled() or type(ev) ~= "table" or skip(ev.battle) then return end
      local st, user = ev.battle, ev.user
      -- a super-effective hit by a fond Pokemon
      if isPlayer(st, user) and not isPlayer(st, target) and (tonumber(ev.effectiveness) or 10) > 10
          and (tonumber(ev.damage) or 0) > 0 and fond(user.mon) then
        soonText[#soonText + 1] = B.LINES.super
      end
      -- a fond Pokemon's HP bar turning red
      if isPlayer(st, target) and type(target.mon) == "table" and fond(target.mon) then
        local mon = target.mon
        local before = (tonumber(mon.hp) or 0) + (tonumber(ev.damage) or 0)
        if inRed(mon.hp, mon.maxHp) and not inRed(before, mon.maxHp) then
          soonText[#soonText + 1] = B.LINES.pinch:format(nameOf(mon))
        end
      end
    end)

    -- an HP item used on a fond Pokemon in battle: the engine has no event for it, so its battle
    -- item use is wrapped (once); "heal" is its result for an HP-restoring item
    local okI, BattleItems = pcall(require, "src.core.game3.battle.items")
    if okI and type(BattleItems) == "table" and type(BattleItems.use) == "function" and not BattleItems._amieWrapped then
      local use = BattleItems.use
      BattleItems._amieWrapped = true
      BattleItems.use = function(st, adapterArg, bag, session, itemId, partySlot, ...)
        local res = { use(st, adapterArg, bag, session, itemId, partySlot, ...) }
        if res[1] == "heal" and enabled() and not skip(st) then
          local party = session and session.party
          local mon = type(party) == "table" and partySlot and party[partySlot]
          if type(mon) == "table" and fond(mon) then soonText[#soonText + 1] = B.LINES.healed:format(nameOf(mon)) end
        end
        return unpack(res, 1, table.maxn(res))
      end
    end

    local function flushSoon()
      if #soonText == 0 then return end
      local list = soonText
      soonText = {}
      for _, t in ipairs(list) do say(t) end
    end
    B.flushSoon = flushSoon
    mod.events:on("battle.move_used", flushSoon)

    mod.events:on("battle.turn_ended", function(ev)
      B.calls.turn = B.calls.turn + 1
      flushSoon()
      if not enabled() then return end
      local st = ev and ev.battle
      if skip(st) or (st and st.over) then return end
      local ad = adapter()
      if not (ad and ad.clearStatus) then return end
      local battlers = {}
      if type(st.battlers) == "table" then
        for id = 0, 3 do if st.battlers[id] then battlers[#battlers + 1] = st.battlers[id] end end
      elseif st.player then
        battlers[1] = st.player
      end
      for _, b in ipairs(battlers) do
        local status = b.status or (b.mon and b.mon.status)
        if isPlayer(st, b) and status and (b.mon and (tonumber(b.mon.hp) or 0) > 0)
            and levelOf(b.mon) >= N.CURE_LEVEL then
          local okRoll, v = pcall(ad.roll, ad, 0, 99)
          if okRoll and type(v) == "number" and v < N.CURE_PCT then
            local code = statusCode(status)
            -- the five major conditions only: affection never shakes off confusion
            pcall(ad.clearStatus, ad, b)
            B.stats.cure = B.stats.cure + 1
            local text = STATUS_TEXT[code] or "%s shook off its condition so that %s wouldn't worry!"
            pendingText[#pendingText + 1] = text:format(nameOf(b.mon), trainerName(st))
          end
        end
      end
    end)

    local function flush()
      if #pendingText == 0 then return end
      local list = pendingText
      pendingText = {}
      for _, t in ipairs(list) do say(t) end
    end
    mod.events:on("battle.turn_started", flush)
    -- a fond Pokemon asleep: the game's line once each time it falls asleep
    mod.events:on("battle.turn_started", function(ev)
      local st = ev and ev.battle
      if not enabled() or skip(st) then return end
      local list = {}
      if type(st.battlers) == "table" then
        for id = 0, 3 do if st.battlers[id] then list[#list + 1] = st.battlers[id] end end
      elseif st.player then
        list[1] = st.player
      end
      for _, b in ipairs(list) do
        local status = b.status or (b.mon and b.mon.status)
        local asleep = statusCode(status) == "SLP"
        if not asleep then
          b._amieSleepSaid = nil
        elseif isPlayer(st, b) and not b._amieSleepSaid and fond(b.mon) then
          b._amieSleepSaid = true
          say(B.LINES.asleep:format(nameOf(b.mon)))
        end
      end
    end)
    mod.events:on("battle.started", function() pendingText, soonText = {}, {} end)
    mod.events:on("battle.ended", function() pendingText, soonText = {}, {} end)
    return true
  end

  return B
end
