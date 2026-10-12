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

  -- ------- start

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
    local mods = Rules.modifiers(s.evs, s.rec.pending, { pokerus = host.hasPokerus(s.mon) })
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
    s.padHeld = false
    s.anim.events = {}
    T.setMode("regimen")
    host.playSe("SE_SELECT")
    return true
  end

  -- ------- ticking and input

  local SE = { goal_hit = "SE_BALL_BOUNCE_1", player_hit = "SE_NOT_EFFECTIVE", bot_pop = "SE_SUCCESS",
    blocked = "SE_SELECT", bit_pop = "SE_BALL_BOUNCE_2", chance_goal = "SE_EXP", overcharge = "SE_FAILURE",
    barrier_up = "SE_SELECT", attack_telegraph = "SE_SELECT" }

  function T.tickRegimen(dt)
    local s = T.session
    local sim = T.sim
    if not (s and sim) then return end
    local events = sim:update(dt)
    for _, e in ipairs(events) do
      if SE[e.kind] then host.playSe(SE[e.kind]) end
      if e.kind == "clear" then
        T.endRegimen({ clear = true, remaining = e.remaining, total = e.total })
      elseif e.kind == "timeout" then
        T.endRegimen({ timeout = true, total = e.total })
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
    if not (s and sim) then return end
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
      res.newBest = crec.best == nil or res.remaining > crec.best
      if res.newBest then crec.best = res.remaining end
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
    if res.clear then host.playCry(s.mon) end
    return res
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
    T.sim = nil
    s.course = nil
    s.result = nil
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
    if s.mode == "result" then Draw.drawResult(G2, s, T) else Draw.draw(G2, T.sim, s, T) end
  end

  return T
end
