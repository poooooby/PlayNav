-- The regimen half of the Super Training session: starting a course, ticking the
-- simulation, pad input on the top layer, the award path when it ends (EVs, medals, bags,
-- secret prizes, Fully / Supremely Trained), the result card and leaving it. Extends the
-- session table built by session.lua.
--
-- regimen(mod, T, { host, Rules, Store, Items, Courses, Sim, Draw })

return function(mod, T, deps)
  local host, Rules, Store, Items = deps.host, deps.Rules, deps.Store, deps.Items
  local Courses, Sim, Draw = deps.Courses, deps.Sim, deps.Draw
  local N = Rules.N
  T.Courses, T.Sim, T.Draw = Courses, Sim, Draw
  T.exitOffset = Draw and Draw.exitOffset   -- the beaten balloon's way out (hud.pose)
  -- the arena's view on a wide area (arena_draw D.view): a scene point on the screen, and z
  function T.toScreen(x, y)
    if Draw and Draw.toScreen then return Draw.toScreen(T, x, y) end
    return x, y, 1
  end
  -- framed back, the HUD's brackets are stretched to fit the area (hud fitAdjust 5m); aiming,
  -- mapped onto the brackets in the frame's units, goes through that stretch and back under
  -- the view to the scene. -> the bracket fit (kx, ky, middle) or nil when the view is plain
  function T.bracketFit()
    local e = T.topExtent
    if not (e and Draw and Draw.view) then return nil end
    local z = Draw.view(T)
    if z >= 1 then return nil end
    return e.w / 240, e.h / 160, e.x + e.w / 2, e.y + e.h / 2
  end
  function T.aimToScene(x, y)
    local kx, ky, mx, my = T.bracketFit()
    if not kx then return x, y end
    local z, px, py = Draw.view(T)
    local fx, fy = mx + (x - 120) * kx, my + (y - 80) * ky
    return px + (fx - px) / z, py + (fy - py) / z
  end
  function T.sceneToAim(x, y)
    local kx, ky, mx, my = T.bracketFit()
    if not kx then return x, y end
    local fx, fy, z = T.toScreen(x, y)
    return 120 + (fx - mx) / kx, 80 + (fy - my) / ky
  end

  function T.courseList() return Courses and Courses.courses or {} end
  function T.course(id) return Courses and Courses.byId and Courses.byId[id] or nil end

  function T.canEnter(course)
    local s = T.session
    return Rules.canEnter(course, Store.cleared(), T.courseList(), s and s.rec.fully)
  end

  function T.courseRecord(id)
    local s = T.session
    if not s then return nil end
    local m = Store.mon(s.key)
    return m.courses and m.courses[id] or nil
  end

  -- the course's record, any Pokemon's: { best, key, species, name } | nil
  function T.courseBest(id) return Store.records()[id] end
  -- cleared by any Pokemon
  function T.isCleared(id) return Store.cleared()[id] == true end
  -- a species' party icon (a record holder no longer in the party)
  function T.speciesIcon(species) return host.iconSpecies and host.iconSpecies(species) or nil end

  -- ------- start

  -- the game's show around a regimen: the fade in, the intro on the top screen (the sim's
  -- countdown runs as long as it does), the balloon's exit and Success! before the results.
  -- The flow test and the probe's bulk runs turn it off: straight in, straight to the result.
  T.REGIMEN_SHOW = true

  function T.startCourse(id)
    local s = T.session
    if not s then return false, "closed" end
    local course = T.course(id)
    if not course then return false, "unknown" end
    local ok, why = T.canEnter(course)
    if not ok then
      T.say(why == "not_fully_trained" and (T.gameLine("training_courses", 168) or "Only a Fully Trained POKeMON may enter.")
        or T.resultText("locked"), 3)
      return false, why
    end
    if s.rec.resting then
      T.say(T.gameLine("training_bags", 95) or ("%s is resting. Tap to wake it."):format(s.name), 3)
      return false, "resting"
    end
    if T.REGIMEN_SHOW and not s.trans then
      s.trans = { to = "regimen", from = s.mode, course = id, t = 0 }
      T.playSe("start_course", "SE_SELECT")
      T.onChange()
      return true
    end
    return T.beginCourse(id)
  end

  -- the regimen itself (after the fade, or at once without the show)
  function T.beginCourse(id)
    local s = T.session
    local course = s and T.course(id)
    if not course then return false, "unknown" end
    local mods = Rules.modifiers(s.evs, s.rec.pending, { pokerus = host.hasPokerus(s.mon) })
    -- a second wind lasts one regimen: double the points, then it is spent
    if s.rec.secondWind then
      mods.pointMult = mods.pointMult * Rules.N.CORE.REFRESHED_HITS_DIV
      mods.secondWind = true
      s.rec.secondWind = nil
    end
    -- each bot's balloon is its Pokemon's sprite; the goals live on that shape
    local shapes = {}
    if Draw and Draw.shapeFor then
      for i, b in ipairs(course.bots) do
        local ok, shape = pcall(Draw.shapeFor, b)
        shapes[i] = ok and shape or nil
      end
    end
    T.sim = Sim.new(course, {
      mods = mods, shotType = s.shot, level = course.level,
      anchors = Courses.anchors[course.goals.anchors], library = Courses.attacks, shapes = shapes,
    }, T.rng)
    s.course = course
    s.result = nil
    s.outro = nil
    s.padHeld = false
    s.anim.events = {}
    if T.REGIMEN_SHOW and T.hud then
      -- the clock waits for the intro (the game's screen or the engine's plays it)
      T.hud.begin(T.sim, s)
      if T.hud.P or T.hud.engine then T.sim.countdown = T.hud.INTRO_S end
    end
    T.setMode("regimen")
    if not T.REGIMEN_SHOW then T.playSe("start_course", "SE_SELECT") end
    return true
  end

  -- ------- ticking and input

  -- the Emerald stand-ins for what the capture did not show (data/training_sounds.lua has the
  -- game's own effects for the rest)
  local SE = { goal_hit = "SE_BALL_BOUNCE_1", player_hit = "SE_NOT_EFFECTIVE", bot_pop = "SE_SUCCESS",
    blocked = "SE_SELECT", bit_pop = "SE_BALL_BOUNCE_2", chance_goal = "SE_EXP", overcharge = "SE_FAILURE",
    barrier_up = "SE_SELECT", attack_telegraph = "SE_SELECT" }

  -- one event's haptic (src/haptics.lua): a goal hit pulses (harder charged), a hit taken
  -- knocks, the balloon popping and the clear burst; the stand-in sound's own is skipped
  local HAPTIC = { goal_hit = "medium", player_hit = "hurt", bot_pop = "big", bit_pop = "light",
    blocked = "light", chance_goal = "strong", clear = "success", shot_fired = "tick",
    play = "strong", timeout = "bad" }

  -- felt as they change, frame by frame: each charge stage a held shot reaches (the full one
  -- strong), the energy meter filling for the Energy Shot, and a tick for each of the last
  -- five seconds on the clock
  local function stateHaptics(s, sim)
    local H = mod.haptics
    if not H then return end
    local stage = sim.chargeStage and sim:chargeStage() or 0
    local last = s.hapticStage or 0
    if stage > last then
      H.pulse(stage >= #N.CHARGE.STAGE_S and "strong" or "light")
    end
    s.hapticStage = stage
    local full = (sim.guts or 0) >= (N.GUTS.FULL_AT or 1)
    if full and not s.hapticGutsFull then H.pattern("happy") end
    s.hapticGutsFull = full
    if sim.phase == "play" and sim.remaining then
      local sec = math.ceil(sim.remaining)
      if sec <= 5 and sec >= 1 and sec ~= s.hapticSec then H.pulse("tick") end
      s.hapticSec = sec
    end
  end
  local function eventHaptic(e)
    local H = mod.haptics
    local what = H and HAPTIC[e.kind]
    if not what then return end
    if e.kind == "goal_hit" and ((e.stage or 1) >= 2 or e.energy) then what = "strong" end
    if H.PATTERNS[what] then H.pattern(what) else H.pulse(what) end
    if SE[e.kind] then H.skipNextSound() end
  end

  -- one event's sound: the game's effect where the capture showed it, else the stand-in
  local function eventSound(e, cleared)
    eventHaptic(e)
    local charged = (e.stage or 1) >= 2 or e.energy
    if e.kind == "play" then
      T.playSe("play")
    elseif e.kind == "shot_fired" then
      T.playSe(charged and "charged_shot" or "shot")
    elseif e.kind == "goal_hit" then
      T.playSe(charged and "charged_hit" or "goal_hit", SE.goal_hit)
    elseif e.kind == "goals_spawned" then
      T.playSe("goals_spawned")
    elseif e.kind == "attack_telegraph" then
      -- the wind-up loops until the throw
      local s = T.session
      if s and not s.warnSound then s.warnSound = T.playSe("attack_warn", SE.attack_telegraph) or true end
    elseif e.kind == "attack_launch" then
      local s = T.session
      if s and type(s.warnSound) == "table" then s.warnSound.stop() end
      if s then s.warnSound = nil end
      T.playSe("attack_launch")
    elseif e.kind == "clear" then
      T.playSe("clear")
    elseif e.kind == "bot_pop" and cleared then
      -- the clearing pop is the clear's own sound
    elseif SE[e.kind] then
      host.playSe(SE[e.kind])
    end
  end

  -- a ball in the air toward the trainee: the game's flight sound loops while any is
  local function flightSound(s, sim)
    local n = 0
    for _, b in ipairs(sim.balls or {}) do if not b.dead then n = n + 1 end end
    local on = n > 0 and sim.phase == "play"
    if on and not s.flightSound then
      s.flightSound = T.playSe("ball_flight") or true
    elseif not on and s.flightSound then
      if type(s.flightSound) == "table" then s.flightSound.stop() end
      s.flightSound = nil
    end
  end

  -- every looping sound stops (the regimen ends or is left)
  local function stopLoops(s)
    for _, k in ipairs({ "chargeSound", "flightSound", "warnSound" }) do
      if type(s[k]) == "table" then s[k].stop() end
      s[k] = nil
    end
  end
  T.stopRegimenLoops = stopLoops

  -- the press and the charging hum follow the sim's charge (whichever input started it)
  local function chargeSound(s, sim)
    local on = sim.player and sim.player.charging and sim.phase == "play"
    if on and not s.chargeSound then
      T.playSe("press")
      s.chargeSound = T.playSe("charging") or true
    elseif not on and s.chargeSound then
      if type(s.chargeSound) == "table" then s.chargeSound.stop() end
      s.chargeSound = nil
    end
  end
  T.chargeSound = chargeSound

  function T.tickRegimen(dt)
    local s = T.session
    local sim = T.sim
    if not (s and sim) then return end
    chargeSound(s, sim)
    flightSound(s, sim)
    stateHaptics(s, sim)
    if sim.phase ~= "play" and s.warnSound then
      if type(s.warnSound) == "table" then s.warnSound.stop() end
      s.warnSound = nil
    end
    -- the end's show: the result waits for it
    if s.outro then
      s.outro.t = s.outro.t + dt
      if T.hud then T.hud.update(dt, {}) end
      if s.outro.t >= (T.hud and T.hud.OUTRO.END or 0) then
        local outcome = s.outro.outcome
        s.outro = nil
        T.endRegimen(outcome)
      end
      T.onChange()
      return
    end
    local events = sim:update(dt)
    local ended = nil
    local cleared = false
    for _, e in ipairs(events) do if e.kind == "clear" then cleared = true end end
    for _, e in ipairs(events) do
      eventSound(e, cleared)
      if e.kind == "clear" then
        ended = { clear = true, remaining = e.remaining, total = e.total }
      elseif e.kind == "timeout" then
        ended = { timeout = true, total = e.total }
      end
    end
    if T.hud and T.REGIMEN_SHOW then T.hud.update(dt, events) end
    if ended then
      if T.REGIMEN_SHOW and T.hud and (T.hud.P or T.hud.engine) then
        s.outro = { t = 0, outcome = ended }
      else
        T.endRegimen(ended)
      end
    end
    if #events > 0 then
      local ring = s.anim.events
      for _, e in ipairs(events) do ring[#ring + 1] = e end
      while #ring > 24 do table.remove(ring, 1) end
    end
    T.onChange()
  end

  function T.onRegimenInput(input)
    local s = T.session
    local sim = T.sim
    if not (s and sim) or s.outro then return end
    local dx = (input:isDown("right") and 1 or 0) - (input:isDown("left") and 1 or 0)
    local dz = (input:isDown("up") and 1 or 0) - (input:isDown("down") and 1 or 0)
    sim:setMove(dx, dz)
    if input:wasPressed("l") or input:wasPressed("r") then sim:block() end
    -- A fires at the reticle for pad-only play; held = charge
    if input:isDown("a") then
      if not s.padHeld then s.padHeld = true; sim:pressFire() end
    elseif s.padHeld then
      s.padHeld = false
      sim:releaseFire()
    end
    if input:wasPressed("b") then T.quitRegimen() end
  end

  -- ------- the end of a regimen

  -- { item = "ITEM_X" } or { training = "<slug>" } -> { name, index, given }
  function T.giveItemSpec(spec)
    local index, name
    if spec.training then
      index = Items and Items.index(spec.training) or nil
      local def = index and Items.def(index)
      name = def and def.name or spec.training
    elseif spec.item then
      index = host.itemId and host.itemId(spec.item) or nil
      name = index and host.itemName and host.itemName(index) or spec.item
    end
    if not index then return { name = name or "?", given = false } end
    local given = false
    if Items and Items.give then given = Items.give(index, 1) == true
    elseif host.giveItem then given = host.giveItem(index, 1) == true end
    if not given then
      local meta = Store.meta()
      meta.pendingItems[#meta.pendingItems + 1] = { index, 1 }
    end
    return { name = name or tostring(index), index = index, given = given }
  end

  -- outcome = { clear = true, remaining, total } | { timeout = true, total }
  function T.endRegimen(outcome)
    local s = T.session
    local course = s and s.course
    if not (s and course) then return nil end
    if T.liveMon then T.liveMon(s) end
    local rec = s.rec
    local res = { courseId = course.id, courseName = T.courseName(course.id), clear = outcome.clear == true,
      remaining = math.max(0, outcome.remaining or 0), total = outcome.total or 0, secret = course.secret ~= nil,
      target = Rules.medalTarget(course) }
    -- what was enterable before, to announce what this clear opens
    local before = {}
    for _, c in ipairs(T.courseList()) do before[c.id] = T.canEnter(c) and true or false end
    local pokerus = host.hasPokerus(s.mon)
    local pending = rec.pending
    rec.pending = nil   -- a bag's effect is spent by taking part
    res.usedEffect = pending
    if res.clear then
      if course.stat then
        local evs = host.evsOf(s.mon)
        res.evWanted = Rules.courseEv(course, pending)
        res.ev = Rules.addEv(evs, course.stat, res.evWanted)
        res.stat = course.stat
        host.setEvs(s.mon, evs)
        s.evs = evs
      end
      local crec = Store.courseRecord(s.key, course.id)
      res.medal = Rules.medal(course, res.remaining)
      -- the course record is the save's, across the party; each Pokemon keeps its own best too
      local records = Store.records()
      local cur = records[course.id]
      res.newBest = cur == nil or cur.best == nil or res.remaining > cur.best
      if res.newBest then
        records[course.id] = { best = res.remaining, key = s.key, name = s.name,
          species = host.speciesOf and host.speciesOf(s.mon) or nil }
      end
      if crec.best == nil or res.remaining > crec.best then crec.best = res.remaining end
      if res.medal then crec.medal = true end
      crec.clears = (crec.clears or 0) + 1
      res.firstClear = not Store.cleared()[course.id]
      Store.cleared()[course.id] = true
      res.bag = Rules.rollClearBag(course, res.remaining, T.rng, { pokerus = pokerus })
      if course.secret then
        local prize = Rules.rollSecretPrize(course, res.remaining, T.rng, { newBest = res.newBest })
        if prize then res.item = T.giveItemSpec(prize) end
      end
      host.playSe("SE_SUCCESS")
    else
      res.bag = Rules.rollSupportBag(T.rng, { pokerus = pokerus })
      host.playSe("SE_FAILURE")
    end
    if res.bag then
      local ok = Rules.inventoryAdd(Store.bags(), res.bag)
      res.bagKept = ok == true
    end
    if Rules.isFullyTrained(s.evs) and not rec.fully then
      rec.fully = true
      rec.fullyAt = T.wall()
      res.fully = true
    end
    if not rec.supremely and Rules.allMedals(rec, T.courseList()) then
      rec.supremely = true
      res.supremely = true
    end
    res.unlocked = {}
    for _, c in ipairs(T.courseList()) do
      if not before[c.id] and T.canEnter(c) then res.unlocked[#res.unlocked + 1] = c.id end
    end
    if #res.unlocked > 0 then
      res.unlockText = T.resultText("unlocked", { COURSE = T.courseName(res.unlocked[1]) })
    end
    res.praise = T.praise(res)
    res.statText = res.stat and T.statLine(res.stat) or nil
    s.result = res
    T.lastResult = res
    Store.save()
    T.setMode("result")
    if T.REGIMEN_SHOW and T.results then T.results.begin(s) end
    if res.clear then host.playCry(s.mon) end
    return res
  end

  -- the next line of the results (a tap or A); past the last, back to the picker
  function T.resultNext()
    local s = T.session
    if not s or s.trans then return false end
    local Rs = T.results
    if Rs and Rs.list and (Rs.top or Rs.bottom or Rs.engine) then return Rs.next() end
    return T.leaveResult()
  end

  function T.leaveResult()
    local s = T.session
    if not s then return false end
    T.sim = nil
    s.course = nil
    T.setMode(T.Courses and "courses" or "core")
    return true
  end

  function T.quitRegimen()
    local s = T.session
    if not s then return false end
    stopLoops(s)
    T.sim = nil
    s.course = nil
    s.result = nil
    s.outro = nil
    T.setMode("courses")
    return true
  end

  -- a driver's shortcut
  function T.forceEnd(outcome)
    if not T.sim then return false end
    local ok = T.sim:forceEnd(outcome)
    if ok then T.tickRegimen(0) end
    return ok
  end

  -- ------- the top screen while a regimen runs

  function T.drawTop(G2, s)
    if not Draw then return end
    if s.mode == "result" then
      if not (T.results and T.results.list and T.results.drawTop(G2, s)) then Draw.drawResult(G2, s, T) end
    else
      Draw.draw(G2, T.sim, s, T)
    end
  end

  return T
end
