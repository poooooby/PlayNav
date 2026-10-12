-- Affection benefits in battle (X/Y, ORAS):
--   level 2+  1.2x experience
--   level 3+  endure a knockout at 1 HP: 10%, 15% at level 4, 20% at 200+, 25% at level 5
--   level 4+  shake off a status at the end of the turn, 20%
--   200+      the foe's accuracy drops 10 points (moves that cannot miss never reach the hook)
--   level 5   critical-hit chance doubled
-- Everything goes through the engine's public hooks and events; nothing is
-- patched. Skipped in link, facility and tutorial battles, before any extra
-- RNG draw, so a link battle never desyncs.
--
-- deps = { Rules, Store, host, enabled = fn() -> bool }

return function(mod, deps)
  local Rules, Store, host = deps.Rules, deps.Store, deps.host
  local N = Rules.N.BENEFITS
  local B = { installed = false, stats = { exp = 0, crit = 0, dodge = 0, endure = 0, cure = 0 } }

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

  local STATUS_TEXT = {
    BRN = "%s blew on its burn and made it better so that %s wouldn't worry!",
    PSN = "%s managed to expel the poison so that %s wouldn't worry!",
    TOX = "%s managed to expel the poison so that %s wouldn't worry!",
    SLP = "%s shook itself awake so that %s wouldn't worry!",
    FRZ = "%s melted the ice with its fiery determination so that %s wouldn't worry!",
    PAR = "%s gathered all its energy to break through its paralysis so that %s wouldn't worry!",
  }

  local pendingText = {}  -- printed at the start of the next turn

  function B.install()
    if B.installed or not (mod.hooks and mod.events) then return false end
    B.installed = true

    mod.hooks:wrap("exp.gain", function(next, ctx)
      local amount = next()
      if not enabled() or type(ctx) ~= "table" or skip(ctx.battle) then return amount end
      if levelOf(ctx.mon) >= N.EXP_LEVEL then
        B.stats.exp = B.stats.exp + 1
        return math.floor((tonumber(amount) or 0) * N.EXP_MULT)
      end
      return amount
    end)

    mod.hooks:wrap("battle.crit", function(next, ctx)
      local hit = next()
      if hit or not enabled() or type(ctx) ~= "table" then return hit end
      local st = ctx.battle
      if skip(st) or (st and st.pokedude) or not isPlayer(st, ctx.attacker) then return hit end
      if levelOf(ctx.attacker.mon) < N.CRIT_LEVEL then return hit end
      local okR, RulesG3 = pcall(require, "src.core.game3.battle.rules")
      local CHANCE = okR and RulesG3.crit and RulesG3.crit.CHANCE or { [0] = 16, [1] = 8, [2] = 4, [3] = 3, [4] = 2 }
      local den = CHANCE[tonumber(ctx.stage) or 0] or 16
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
    end)

    mod.events:on("battle.turn_ended", function(ev)
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
            local code = tostring(status):upper():sub(1, 3)
            pcall(ad.clearStatus, ad, b)
            b.confusionTurns = nil
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
    mod.events:on("battle.started", function() pendingText = {} end)
    mod.events:on("battle.ended", function() pendingText = {} end)
    return true
  end

  return B
end
