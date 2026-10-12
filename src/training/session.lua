-- The Super Training session: which Pokemon trains, the top-screen layer, the modes
-- (core, bags, courses, regimen, result), Core Training's bag hits and their effects,
-- and the award path of a regimen. The bottom apps call into here; the engine only ever
-- sees the layer. Pure rules live in rules.lua, the regimen in sim.lua.
--
-- T = session(mod, { host, Rules, Store, Items, Apps, Courses, Sim, busy, onChange })

return function(mod, deps)
  local host, Rules, Store, Items, Apps = deps.host, deps.Rules, deps.Store, deps.Items, deps.Apps
  local N = Rules.N
  local STAT_INDEX = { hp = 1, atk = 2, def = 3, spa = 4, spd = 5, spe = 6 }   -- the game's stat order
  local onChange = deps.onChange or function() end

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local busy = deps.busy or function() return false end
  local T = { session = nil, rng = math.random, Courses = deps.Courses, Sim = deps.Sim, previousApp = nil }

  local APP_FOR = { core = "training_core", bags = "training_bags", courses = "training_courses",
    regimen = "training_aim", result = "training_aim" }

  local function now() return host.now() end
  local function wall() return host.wallClock and host.wallClock() or os.time() end

  local function say(text, secs)
    local s = T.session
    if not s then return end
    s.message = text
    s.messageUntil = now() + (secs or 3)
    onChange()
  end
  T.say = say

  local function eligible(mon)
    return mon ~= nil and not host.isEgg(mon) and not host.isFainted(mon)
  end
  T.eligible = eligible

  local function monFields(mon)
    local key = host.monKey(mon)
    local species = host.speciesOf(mon)
    local national = host.national and host.national(mon) or species
    local types = host.typesOf and host.typesOf(species) or nil
    return {
      mon = mon, key = key, species = species, national = national,
      name = host.displayName(mon), level = host.level and host.level(mon) or 1,
      pic = host.frontPic(mon), icon = host.icon and host.icon(mon) or nil,
      evs = host.evsOf(mon), base = host.baseStats and host.baseStats(species) or nil,
      shot = Rules.shotType(national, types),
      rec = Store.mon(key),
    }
  end

  local function refreshedNow(rec)
    return rec ~= nil and tonumber(rec.refreshedUntil) ~= nil and rec.refreshedUntil > wall()
  end
  function T.refreshed()
    local s = T.session
    return s ~= nil and refreshedNow(s.rec)
  end

  -- ------- the top-screen layer

  local Layer = { isMenu = true }
  T.layer = Layer

  function Layer.handleInput(input)
    local s = T.session
    if not s then return end
    if s.mode == "core" then
      if input:wasPressed("a") then
        if s.rec.resting then T.wake() else T.hitBag("tap") end
      elseif input:wasPressed("b") or input:wasPressed("start") then
        T.finish()
      end
    elseif s.mode == "bags" or s.mode == "courses" then
      if input:wasPressed("b") then T.enterCore() end
    elseif s.mode == "regimen" then
      if T.onRegimenInput then T.onRegimenInput(input) end
    elseif s.mode == "result" then
      if input:wasPressed("a") or input:wasPressed("b") then T.leaveResult() end
    end
  end

  function Layer.update(dt) T.tick(dt) end

  local function drawText(text, x, y, opts)
    if host.Font and host.Font.draw then
      local ok = pcall(host.Font.draw, text, x, y, opts)
      if ok then return end
    end
    if love and love.graphics then
      love.graphics.setColor(0.1, 0.1, 0.1, 1)
      love.graphics.print(text, x, y)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- the text box's words wrapped to its rows and drawn smaller when they would run over
  local function drawBoxText(text)
    local TF = mod.textfit
    if TF and host.Font and host.Font.draw and TF.engine(host.Font, text, 18, 129, 204, 24, {}) then return end
    drawText(text, 18, 130, { maxWidth = 204 })
  end
  T.drawText = drawText

  local SHOT_RGB = { black = { 0.15, 0.15, 0.15 }, yellow = { 0.95, 0.85, 0.2 }, orange = { 0.95, 0.55, 0.15 },
    green = { 0.3, 0.75, 0.35 }, blue = { 0.3, 0.6, 0.95 } }
  T.SHOT_RGB = SHOT_RGB

  local function topArt(id)
    local A = T.assets
    if not (A and A.image and id) or mod.options:get("use_rom_art") == false then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end

  -- the regimen picked in the course list: its badge, heading, name, the game's description
  -- of it, what it gives and the times (the touch screen's START begins it)
  local function drawCourseCard(G2, s, c)
    local TF = mod.textfit
    G2.setColor(0.16, 0.2, 0.3, 1)
    G2.rectangle("fill", 0, 0, 240, 160)
    local open, why = T.canEnter(c)
    G2.setColor(1, 1, 1, 0.85)
    G2.rectangle("fill", 4, 4, 232, 16, 3, 3)
    drawText(T.levelHeading(c.level, c.secret), 8, 6, { maxWidth = 224 })
    local badge = topArt(open and c.bots[1].art or "training/locked") or topArt(c.bots[1].art)
    if badge then
      G2.setColor(1, 1, 1, open and 1 or 0.6)
      G2.draw(badge, 8, 30, 0, 52 / badge:getWidth(), 52 / badge:getHeight())
    end
    G2.setColor(1, 1, 1, 0.92)
    G2.rectangle("fill", 66, 24, 170, 76, 3, 3)
    local function fit(text, x, y, w, h)
      if TF and host.Font and host.Font.draw and TF.engine(host.Font, text, x, y, w, h, {}) then return end
      drawText(text, x, y, { maxWidth = w })
    end
    fit(T.courseName(c.id), 70, 26, 162, 14)
    G2.setColor(0.6, 0.65, 0.75, 1)
    G2.rectangle("fill", 70, 42, 162, 1)
    local blurb = T.courseBlurb(c.id)
    if blurb == "" then blurb = c.name or "" end
    fit(blurb, 70, 45, 162, 54)
    -- what it gives and the times, under the badge
    local target = Rules.medalTarget(c)
    local rec = T.courseRecord(c.id)
    local gain = c.stat and ("+%d %s"):format(Rules.courseEv(c, s.rec.pending), Rules.STAT_LABEL[c.stat] or c.stat) or "Items"
    local lines = { gain, ("Target %d:%02d"):format(math.floor(target / 60), target % 60) }
    if rec and rec.best then lines[#lines + 1] = ("Best %s"):format(T.Draw and T.Draw.clock(rec.best) or tostring(rec.best)) end
    if rec and rec.medal then lines[#lines + 1] = "Award!" end
    G2.setColor(1, 1, 1, 0.85)
    G2.rectangle("fill", 4, 102, 232, 18, 3, 3)
    fit(table.concat(lines, "    "), 8, 104, 224, 14)
    local msg
    if s.message and s.messageUntil and now() < s.messageUntil then msg = s.message
    elseif not open then
      msg = why == "not_fully_trained" and (T.gameLine("training_courses", 168) or "Only a Fully Trained POKeMON may enter.")
        or T.resultText("locked")
    else msg = "Tap START to begin.  B: back" end
    if host.Chrome and host.Chrome.stdFrame then
      pcall(host.Chrome.stdFrame, 2, 16, 26, 3)
    else
      G2.setColor(1, 1, 1, 0.9)
      G2.rectangle("fill", 12, 124, 216, 30, 3, 3)
    end
    drawBoxText(msg)
  end

  -- the Core Training card: the Pokemon, its bag, the EV total and a message line
  local function drawCore(G2, s)
    if s.mode == "courses" and s.picked and T.course then
      local c = T.course(s.picked)
      if c then return drawCourseCard(G2, s, c) end
    end
    G2.setColor(0.16, 0.2, 0.3, 1)
    G2.rectangle("fill", 0, 0, 240, 160)
    G2.setColor(0.2, 0.26, 0.38, 1)
    G2.rectangle("fill", 0, 92, 240, 68)
    G2.setColor(0.1, 0.8, 0.7, 0.35)
    G2.ellipse("fill", 72, 100, 44, 9)
    if s.pic and s.pic.image then
      local bounce = (s.anim.hit > 0) and 3 or 0
      G2.setColor(1, 1, 1, 1)
      drawPixel(s.pic.image, 72, 102 - bounce, 0, 1, 1, (s.pic.w or 64) / 2, (s.pic.h or 64))
    end
    -- the bag beside it
    local bag = s.rec.bag
    G2.setColor(0.25, 0.25, 0.3, 1)
    G2.rectangle("fill", 118, 44, 4, 20)
    if bag then
      local def = Rules.bag(bag.id)
      local rgb = (def and def.stat and T.STAT_RGB[def.stat]) or { 0.6, 0.6, 0.65 }
      G2.setColor(rgb[1], rgb[2], rgb[3], 1)
    else
      G2.setColor(0.12, 0.12, 0.14, 1)
    end
    G2.rectangle("fill", 108, 62, 24, 40, 6, 6)
    G2.setColor(1, 1, 1, 0.85)
    G2.rectangle("fill", 4, 4, 232, 16, 3, 3)
    local tag = s.rec.supremely and " [S]" or (s.rec.fully and " [F]" or "")
    drawText(("%s Lv%d%s"):format(s.name, s.level, tag), 8, 6, { maxWidth = 170 })
    local rgb = SHOT_RGB[s.shot] or SHOT_RGB.black
    G2.setColor(rgb[1], rgb[2], rgb[3], 1)
    G2.circle("fill", 226, 12, 5, 16)
    G2.setColor(1, 1, 1, 0.9)
    G2.circle("line", 226, 12, 5, 16)
    local total = Rules.evTotal(s.evs)
    local line
    if bag then
      local def = Rules.bag(bag.id)
      line = ("%s  %d/%d"):format(def and def.label or bag.id, bag.hits, bag.needed)
    else
      line = "No training bag set."
    end
    G2.setColor(1, 1, 1, 0.9)
    G2.rectangle("fill", 140, 28, 96, 30, 3, 3)
    drawText(("EVs %d/%d"):format(total, N.LIMITS.EV_TOTAL), 144, 30, { maxWidth = 90 })
    local status = s.rec.resting and "RESTING" or (refreshedNow(s.rec) and "REFRESHED" or
      (s.rec.pending and ("NEXT: " .. (Rules.EFFECT_LABEL[s.rec.pending] or s.rec.pending)) or ""))
    drawText(status, 144, 44, { maxWidth = 90 })
    local hint = (s.mode == "core" and "A: hit the bag   B: close") or (s.mode == "bags" and "Pick a bag.  B: back")
      or (s.mode == "courses" and "Pick a regimen.  B: back") or ""
    local msg = (s.message and s.messageUntil and now() < s.messageUntil) and s.message or (line .. "  " .. hint)
    if host.Chrome and host.Chrome.stdFrame then
      pcall(host.Chrome.stdFrame, 2, 16, 26, 3)
    else
      G2.setColor(1, 1, 1, 0.9)
      G2.rectangle("fill", 12, 124, 216, 30, 3, 3)
    end
    drawBoxText(msg)
  end

  T.STAT_RGB = { hp = { 0.95, 0.4, 0.45 }, atk = { 0.95, 0.6, 0.3 }, def = { 0.9, 0.8, 0.3 },
    spa = { 0.4, 0.6, 0.95 }, spd = { 0.4, 0.85, 0.5 }, spe = { 0.85, 0.5, 0.9 } }

  function Layer.draw()
    local s = T.session
    if not (s and love and love.graphics) then return end
    -- src/hd_top.lua draws the scene over the frame at window resolution; then only the
    -- backdrop goes into the engine's 240x160 canvas
    if Layer.hdLive then Layer.backdrop(love.graphics); return end
    Layer.drawScene(love.graphics)
  end

  function Layer.backdrop(G2)
    G2.setColor(0.16, 0.2, 0.3, 1)
    G2.rectangle("fill", 0, 0, 240, 160)
  end

  -- the top screen in 240x160 units (drawn by Layer.draw or, at window resolution, hd_top)
  function Layer.drawScene(G2)
    local s = T.session
    if not s then return end
    G2.push("all")
    if (s.mode == "regimen" or s.mode == "result") and T.drawTop then
      local ok, err = pcall(T.drawTop, G2, s)
      if not ok then mod.log:warn("training top draw failed: %s", tostring(err)) end
    else
      drawCore(G2, s)
    end
    G2.pop()
  end

  -- ------- lifecycle

  local function setMode(mode)
    local s = T.session
    if not s then return end
    s.mode = mode
    local app = APP_FOR[mode]
    if app and Apps:get(app) then Apps:setActive(app, mod.game) end
    onChange()
  end
  T.setMode = setMode
  T.wall = wall
  T.onChange = onChange

  -- prizes that did not fit in the bag earlier
  function T.retryPendingItems()
    local meta = Store.meta()
    local left = {}
    for _, p in ipairs(meta.pendingItems or {}) do
      local ok = false
      if Items and Items.give then ok = Items.give(p[1], p[2]) elseif host.giveItem then ok = host.giveItem(p[1], p[2]) end
      if not ok then left[#left + 1] = p end
    end
    meta.pendingItems = left
  end

  -- opens on `mon` (default: the first party member that can train)
  function T.open(mon)
    if T.session then return false, "open" end
    if busy() then return false, "busy" end
    if not mon then
      for _, p in ipairs(host.party()) do
        if eligible(p) then mon = p; break end
      end
    end
    if not mon then return false, "no_pokemon" end
    mon = host.resolve(mon) or mon
    if not eligible(mon) then return false, "fainted" end
    Store.migrate()
    local s = monFields(mon)
    s.mode = "core"
    s.startedAt = now()
    s.autoAt = now() + N.CORE.AUTO_HIT_S
    s.anim = { hit = 0, t = 0 }
    s.message, s.messageUntil = nil, nil
    T.session = s
    T.previousApp = Apps:active() and Apps:active().id or nil
    local ok, err = host.pushLayer(Layer)
    if not ok then mod.log:warn("could not push the training layer: %s", tostring(err)) end
    setMode("core")
    T.retryPendingItems()
    return true
  end

  function T.finish()
    local s = T.session
    if not s then return false end
    if s.mode == "regimen" and T.quitRegimen then T.quitRegimen() end
    Store.save()
    host.popLayer()
    T.session = nil
    if T.previousApp and Apps:get(T.previousApp) then Apps:setActive(T.previousApp, mod.game) end
    onChange()
    return true
  end

  function T.switchTo(mon)
    local s = T.session
    if not (s and mon) then return false end
    mon = host.resolve(mon) or mon
    if not eligible(mon) then say("That POKeMON can't train right now.", 2.5); return false, "fainted" end
    if host.monKey(mon) == s.key then return true end
    local f = monFields(mon)
    for k, v in pairs(f) do s[k] = v end
    s.autoAt = now() + N.CORE.AUTO_HIT_S
    onChange()
    return true
  end

  function T.enterCore() setMode("core"); return true end
  function T.enterBags() setMode("bags"); return true end
  function T.enterCourses()
    if T.session then T.session.picked = nil end
    setMode("courses")
    return true
  end

  -- ------- Core Training

  local function finishBag(s)
    local rec = s.rec
    local bag = rec.bag
    local def = bag and Rules.bag(bag.id)
    rec.bag = nil
    if not def then return end
    s.anim.burst = 0.7
    if def.kind == "stat" then
      local evs = host.evsOf(s.mon)
      local added = Rules.addEv(evs, def.stat, def.ev)
      host.setEvs(s.mon, evs)
      s.evs = evs
      if added > 0 then
        say(T.gameLine("training_bags", T.CORE_LINE.statUp + STAT_INDEX[def.stat])
          or ("%s's %s rose by %d!"):format(s.name, Rules.STAT_LABEL[def.stat], added), 3)
      else
        say(T.gameLine("training_courses", 145, { STAT = T.statWord(def.stat) })
          or ("%s's %s can't go any higher."):format(s.name, Rules.STAT_LABEL[def.stat]), 3)
      end
    elseif def.kind == "reset" then
      local evs = host.evsOf(s.mon)
      local before = Rules.resetEvs(evs)
      host.setEvs(s.mon, evs)
      s.evs = evs
      say(T.gameLine("training_bags", T.CORE_LINE.reset) or ("%s's base points were reset (%d cleared)."):format(s.name, before), 3)
    elseif def.kind == "soothing" then
      host.addFriendship(s.mon, def.amount or 20)
      say(T.gameLine("training_bags", T.CORE_LINE.friendship) or ("%s looks happier!"):format(s.name), 3)
    elseif def.effect == "refreshed" then
      rec.refreshedUntil = wall() + N.CORE.REFRESHED_S
      rec.resting = false
      say(T.gameLine("training_bags", T.CORE_LINE.refreshed_bag) or ("%s is raring to go!"):format(s.name), 3)
    else
      say(T.gameLine("training_bags", T.CORE_LINE[def.id] or -1) or ("%s is ready for the next regimen."):format(def.label), 3)
      rec.pending = def.effect
    end
    host.playSe("SE_SUCCESS")
    if Rules.isFullyTrained(s.evs) and not rec.fully then
      rec.fully = true
      rec.fullyAt = wall()
      say(T.resultText("fullyNow"), 4)
      host.playCry(s.mon)
    end
  end

  -- source = "tap" | "auto"
  function T.hitBag(source)
    local s = T.session
    if not s then return false, "closed" end
    local rec = s.rec
    if rec.resting then
      if source == "tap" then T.wake() end
      return false, "resting"
    end
    local bag = rec.bag
    if not bag then
      if source == "tap" then return T.tapBlackBag() end
      return false, "no_bag"
    end
    bag.hits = bag.hits + 1
    rec.hits = (rec.hits or 0) + 1
    s.anim.hit = 0.25
    host.playSe("SE_BALL_BOUNCE_1")
    if bag.hits >= bag.needed then finishBag(s) end
    Store.save()
    onChange()
    return true
  end

  function T.tapBlackBag()
    local s = T.session
    if not s then return false end
    local meta = Store.meta()
    meta.blackTaps = (meta.blackTaps or 0) + 1
    s.anim.hit = 0.25
    host.playSe("SE_BALL_BOUNCE_1")
    local id = Rules.rollBlackBag(meta.blackTaps, T.rng)
    if id then
      local ok = Rules.inventoryAdd(Store.bags(), id)
      if ok then
        meta.blackTaps = 0
        local def = Rules.bag(id)
        say(T.gameLine("training_bags", T.CORE_LINE.found, { BAG = T.bagName(id) }) or ("A %s dropped down!"):format(def and def.label or id), 3)
        host.playSe("SE_SUCCESS")
      else
        say(T.resultText("rackFull"), 3)
      end
    end
    Store.save()
    onChange()
    return true, id
  end

  function T.wake()
    local s = T.session
    if not s then return false end
    local rec = s.rec
    if not rec.resting then return false end
    rec.resting = false
    rec.refreshedUntil = wall() + N.CORE.REFRESHED_S
    if rec.bag then rec.bag.needed = Rules.bagHits(rec.bag.id, true) end
    say(T.gameLine("training_bags", T.CORE_LINE.refreshed) or ("%s got a second wind!"):format(s.name), 3)
    host.playCry(s.mon)
    Store.save()
    return true
  end

  -- the bag at `index` in the inventory goes on the stand; the one there comes back
  function T.attachBag(index)
    local s = T.session
    if not s then return false end
    local bags = Store.bags()
    local id = bags[index]
    local def = id and Rules.bag(id)
    if not def then return false, "unknown" end
    if s.rec.resting then
      say(T.gameLine("training_bags", T.CORE_LINE.resting) or ("%s is resting. Tap to wake it."):format(s.name), 3)
      return false, "resting"
    end
    if def.kind == "stat" and Rules.statRoom(s.evs, def.stat) == 0 then
      say(T.gameLine("training_bags", T.CORE_LINE.cappedBag, { STAT = T.statWord(def.stat), BAG = T.bagName(id) })
        or ("%s's %s can't go any higher."):format(s.name, Rules.STAT_LABEL[def.stat]), 3)
      return false, "capped"
    end
    -- the game discards the bag on the stand when a new one is set (its own prompt says so)
    table.remove(bags, index)
    s.rec.bag = { id = id, hits = 0, needed = Rules.bagHits(id, refreshedNow(s.rec)) }
    say(("%s set.  %d hits to go."):format(def.label, s.rec.bag.needed), 2.5)
    host.playSe("SE_SELECT")
    Store.save()
    onChange()
    return true
  end

  -- ------- the bag screen's words: the game's own from the player's card when extracted,
  -- else ours. {BAG} / {MON} are filled in.

  local function gameText(file, line)
    local A = T.assets
    local lines = A and A.text and A.text(file)
    local s = lines and lines[line]
    if type(s) == "string" and s ~= "" then return s end
    return nil
  end

  local function fill(s, bagName)
    local sess = T.session
    s = s:gsub("{BAG}", bagName or "bag")
    return (s:gsub("{MON}", sess and sess.name or "your POKeMON"))
  end

  function T.bagName(id)
    local i = Rules.GAME_INDEX[id]
    local name = i and gameText("training_bag_names", i)
    if name then return name end
    local def = Rules.bag(id)
    return def and def.label or tostring(id)
  end

  -- the description without the game's "◆ name" header line
  function T.bagDescription(id)
    local i = Rules.GAME_INDEX[id]
    local s = i and gameText("training_bags", Rules.TEXT_LINE.descBase + i)
    if s then
      s = s:gsub("^[^\n]*{BAG}[^\n]*\n", "")
      return fill(s, T.bagName(id))
    end
    return Rules.fallbackText(id)
  end

  local FALLBACK_UI = { use = "Use", discard = "Discard", back = "Back", yes = "Yes", no = "No",
    askUse = "Use the {BAG} for {MON}?", askDiscard = "Discard this {BAG}?",
    replaceEffect = "{MON} still has the effect of its last bag. A new bag replaces it. Use the {BAG}?",
    replaceBag = "{MON} is training with a bag already. It will be thrown away. Use the {BAG}?" }

  function T.uiText(key, bagId)
    local s = gameText("training_bags", Rules.TEXT_LINE[key] or -1) or FALLBACK_UI[key] or key
    -- the game breaks its lines for a 320 px box; ours wraps to its own width
    s = s:gsub("%s*\n%s*", " ")
    return fill(s, bagId and T.bagName(bagId) or nil)
  end

  -- a line of game text with its variables filled; nil when the text is not extracted
  -- vars = { MON, BAG, STAT, PLAYER, COURSE, ITEM, N }
  function T.gameLine(file, line, vars)
    local s = gameText(file, line)
    if not s then return nil end
    local sess = T.session
    vars = vars or {}
    s = s:gsub("%s*\n%s*", " ")
    s = s:gsub("{MON}", vars.MON or (sess and sess.name) or "your POKeMON")
    s = s:gsub("{BAG}", vars.BAG or "bag")
    s = s:gsub("{STAT}", vars.STAT or "stat")
    s = s:gsub("{PLAYER}", vars.PLAYER or (host.playerName and host.playerName()) or "you")
    s = s:gsub("{COURSE}", vars.COURSE or "a regimen")
    s = s:gsub("{ITEM}", vars.ITEM or "item")
    s = s:gsub("{N}", vars.N and tostring(vars.N) or "")
    return s
  end

  -- a/0/7/3 file 27 (text/training_bags): Core Training events
  T.CORE_LINE = { found = 6, resting = 11, refreshed = 12, statUp = 68, strength = 75, toughen_up = 76,
    swiftness = 77, big_shot = 78, double_up = 79, refreshed_bag = 80, reset = 81, friendship = 82,
    cappedBag = 92, allCapped = 94 }
  -- a/0/7/3 file 45 (text/training_courses): headings, names, blurbs, the result screen
  T.COURSE_LINE = { heading = { [1] = 1, [2] = 2, [3] = 3, secret = 4, secret2 = 5 }, name = 20, blurb = 75,
    possible = 59, increase = 60, bagsReceived = 61, itemsReceived = 62, statWord = 64,
    targetRemaining = 72, bestTime = 73, unlocked = 125, failed = 127, quit = 128, locked = 129,
    timeRemaining = 130, praise = { 132, 133, 134, 135 }, tryTarget = 136, targetHit = 137, award = 138,
    newBest = 139, statLine = { hp = 140, atk = 141, spa = 141, def = 142, spd = 142, spe = 143 },
    fullyNow = 150, supremelyNow = 153, rackFull = 163, results = 165, andResults = 166 }
  -- the game's word for a stat ("Sp. Atk"), else ours
  function T.statWord(stat)
    return gameText("training_courses", T.COURSE_LINE.statWord + (STAT_INDEX[stat] or 1)) or Rules.STAT_LABEL[stat] or stat
  end

  local RESULT_FALLBACK = {
    possible = "Possible base stat increase:", increase = "Base stat increase:",
    bagsReceived = "Training bags received:", itemsReceived = "Items received:",
    targetRemaining = "Target Time Remaining:", bestTime = "Best Time:", timeRemaining = "Time Remaining:",
    failed = "You failed to complete the Super-Training Regimen...", quit = "You bowed out of Super Training...",
    locked = "You cannot attempt that Super-Training Regimen just yet.",
    tryTarget = "Don't give up! Try to reach that target time!", targetHit = "You've achieved the target time!",
    award = "Award received!", newBest = "New best time!",
    rackFull = "You don't have enough space to keep any more training bags.",
    unlocked = "With that performance, you unlocked a new Super-Training Regimen. {COURSE} was unlocked!",
    fullyNow = "Amazing! Its base stats are all maxed! It is a Fully Trained POKeMON!",
    supremelyNow = "Fantastic! You have every last Award from your Super-Training Regimens! It's a Supremely Trained POKeMON!",
    results = "You faced the challenge of a Super-Training Regimen and got a reward in return!",
  }
  local PRAISE_FALLBACK = { "You did it! That's the spirit!", "Nice job! Knew you had it in you!",
    "Spectacular! To complete a regimen in so little time!", "A-a-amazing! That's a new record!" }

  -- a result-screen string by key (see T.COURSE_LINE), filled
  function T.resultText(key, vars)
    local line = T.COURSE_LINE[key]
    local s = type(line) == "number" and T.gameLine("training_courses", line, vars) or nil
    if s then return s end
    s = RESULT_FALLBACK[key] or key
    vars = vars or {}
    return (s:gsub("{COURSE}", vars.COURSE or "a regimen"))
  end

  -- the coach's praise: a new best, well under the target, under it, or a plain clear
  function T.praise(res)
    local i = 1
    if res.newBest and res.medal then i = 4
    elseif res.medal and res.remaining >= (res.target or 0) + 30 then i = 3
    elseif res.medal then i = 2 end
    return T.gameLine("training_courses", T.COURSE_LINE.praise[i]) or PRAISE_FALLBACK[i]
  end

  -- "{MON} made its shots more effective by training its Attack stat!"
  function T.statLine(stat)
    local line = T.COURSE_LINE.statLine[stat]
    return line and T.gameLine("training_courses", line, { STAT = T.statWord(stat) }) or nil
  end

  function T.courseName(id)
    local c = T.course and T.course(id)
    local s = c and c.order and gameText("training_courses", T.COURSE_LINE.name + c.order)
    return s or (c and c.name) or tostring(id)
  end

  function T.courseBlurb(id)
    local c = T.course and T.course(id)
    local s = c and c.order and T.gameLine("training_courses", T.COURSE_LINE.blurb + c.order)
    return s or ""
  end

  -- "Super Training Lv. 2" / "Secret Super Training Lv. 1"
  function T.levelHeading(level, secret)
    local line = secret and (secret > 6 and T.COURSE_LINE.heading.secret2 or T.COURSE_LINE.heading.secret) or T.COURSE_LINE.heading[level]
    local s = line and gameText("training_courses", line)
    if s then return s end
    if secret then return ("SECRET SUPER TRAINING Lv. %d"):format(secret > 6 and 2 or 1) end
    return ("SUPER TRAINING Lv. %d"):format(level or 1)
  end

  -- which question the game asks before setting this bag
  function T.useQuestion(id)
    local s = T.session
    local def = Rules.bag(id)
    if s and s.rec.bag then return "replaceBag" end
    if s and def and def.kind == "effect" and s.rec.pending and def.effect ~= "refreshed" then return "replaceEffect" end
    return "askUse"
  end

  function T.discardBag(index)
    local bags = Store.bags()
    local id = Rules.inventoryRemove(bags, index)
    if id then Store.save(); onChange() end
    return id
  end

  -- the stand's bag back into the inventory (progress is lost)
  function T.takeDownBag()
    local s = T.session
    if not (s and s.rec.bag) then return false end
    local ok, why = Rules.inventoryAdd(Store.bags(), s.rec.bag.id)
    if not ok then say(T.resultText("rackFull"), 3); return false, why end
    s.rec.bag = nil
    Store.save()
    onChange()
    return true
  end

  -- ------- ticking

  function T.tick(dt)
    local s = T.session
    if not s then return end
    s.anim.t = s.anim.t + dt
    if s.anim.hit > 0 then s.anim.hit = math.max(0, s.anim.hit - dt) end
    if (s.anim.burst or 0) > 0 then s.anim.burst = math.max(0, s.anim.burst - dt) end
    if s.message and s.messageUntil and now() >= s.messageUntil then
      s.message = nil
      onChange()
    end
    if s.mode == "regimen" and T.tickRegimen then
      T.tickRegimen(dt)
      return
    end
    if s.mode ~= "regimen" and s.mode ~= "result" and now() >= s.autoAt then
      s.autoAt = now() + N.CORE.AUTO_HIT_S
      if s.rec.resting then
        -- it keeps resting until tapped
      elseif T.rng() < N.CORE.REST_ODDS then
        s.rec.resting = true
        say(("%s is taking a rest..."):format(s.name), 3)
        Store.save()
      else
        T.hitBag("auto")
      end
    end
  end

  -- ------- what the apps and tests read

  function T.party()
    local out = {}
    local s = T.session
    for i, mon in ipairs(host.party()) do
      out[#out + 1] = { mon = mon, key = host.monKey(mon), name = host.displayName(mon),
        icon = host.icon and host.icon(mon) or nil, eligible = eligible(mon),
        active = s ~= nil and host.monKey(mon) == s.key, index = i }
    end
    return out
  end

  function T.state()
    local s = T.session
    if not s then return { mode = nil } end
    local rec = s.rec
    return {
      mode = s.mode, key = s.key, name = s.name, national = s.national, shot = s.shot,
      evs = s.evs, total = Rules.evTotal(s.evs),
      bag = rec.bag and { id = rec.bag.id, hits = rec.bag.hits, needed = rec.bag.needed } or nil,
      pending = rec.pending, resting = rec.resting, refreshed = refreshedNow(rec),
      fully = rec.fully == true, supremely = rec.supremely == true,
      bags = #Store.bags(), message = s.message, blackTaps = Store.meta().blackTaps,
      regimen = T.sim and T.sim.state and T.sim:state() or nil,
    }
  end

  return T
end
