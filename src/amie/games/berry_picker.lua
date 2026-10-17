-- BERRY PICKER: one to three of the player's Pokemon pop up under the berry
-- pile and show the berry they want; drag the right one from the pile to
-- them before their patience runs out. 60 seconds on Easy / Normal / Hard,
-- three misses on Unlimited. Rules: Bulbapedia "Berry Picker".

return function(mod, Pointer, G, Games, Rules, host)

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "game_berry", title = "BERRY", live = true }

  function app:wantsSurface()
    local s = G.session
    return s ~= nil and s.mode == "game" and s.game and s.game.id == "berry" or false
  end

  local W, H = 256, 178
  local SLOT_X = { 60, 128, 196 }
  local SLOT_Y = 150
  -- the screen's shape: the Pokemon stand at the bottom of a taller screen (Kanto Gear's);
  -- the pile stays at the top. 150 on the 3DS shape's 178 rows.
  local function setShape(h) SLOT_Y = 150 + math.max(0, (h or H) - H) end
  app.setShape = setShape
  local PILE = { y = 34 }   -- the pile sits high enough that a want bubble under it stays clear
  local BERRY_KINDS = { -- recipe ids in difficulty order: Razz, Bluk, Pinap, Wepear, Magost, Durin, Nomel
    "berry/01", "berry/02", "berry/03", "berry/04", "berry/05", "berry/06", "berry/07" }
  local KINDS_FOR = { easy = 3, normal = 5, hard = 7, unlimited = 5 }
  local BERRY_COLOR = { { 0.9, 0.3, 0.4 }, { 0.5, 0.3, 0.6 }, { 0.95, 0.8, 0.3 }, { 0.5, 0.8, 0.3 },
    { 0.95, 0.6, 0.6 }, { 0.3, 0.5, 0.3 }, { 0.9, 0.9, 0.5 } }

  local st = nil      -- the running game
  local drag = nil    -- { kind, x, y, id }
  local particles = {}

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local function spawn(kind, x, y, n)
    for _ = 1, n or 1 do
      particles[#particles + 1] = { kind = kind, x = x + (math.random() - 0.5) * 12, y = y,
        vy = -30 - math.random() * 20, life = 0.8, age = 0 }
    end
  end

  -- the rotation of how many Pokemon ask at once
  local function rotationFor(diff)
    if diff == "unlimited" then
      return { { n = 1, count = 5 }, { n = 2, count = 10 }, { n = 3, count = 15 },
        { n = 1, count = 5 }, { n = 2, count = 15 }, { n = 3, count = 30 },
        { n = 2, count = 10 }, { n = 3, count = 20 }, { n = 1, count = 5 }, { n = 3, count = math.huge } }
    end
    return { { n = 1, count = 10 }, { n = 2, count = 15 }, { n = 3, count = math.huge } }
  end

  local function activeSlots(n)
    if n == 1 then return { 2 } end
    if n == 2 then return { 1, 3 } end
    return { 1, 2, 3 }
  end

  local function patienceFor()
    local diff = st.diff
    if diff == "unlimited" then
      if st.served < 110 then return 3 end
      return math.max(1.2, 3 - (st.served - 110) * 0.02)
    end
    if diff == "hard" and st.rot.n == 2 then return math.max(2, 3 - st.servedInRot * 0.08) end
    return 3
  end

  -- a want nobody else on screen is asking for
  local function pickWant(exclude)
    for _ = 1, 20 do
      local k = math.random(1, st.kinds)
      local clash = false
      for _, sl in pairs(st.slots) do if sl.visible and sl.want == k and sl ~= exclude then clash = true end end
      if not clash then return k end
    end
    return math.random(1, st.kinds)
  end

  local function showSlot(i)
    local sl = st.slots[i]
    sl.visible = true
    sl.want = pickWant(sl)
    sl.patience = patienceFor()
    sl.left = sl.patience
    sl.shownAt = st.t
    sl.hideTimer = 0
  end

  local function advanceRotation()
    st.servedInRot = st.servedInRot + 1
    if st.servedInRot >= st.rot.count and st.rotIndex < #st.rotation then
      st.rotIndex = st.rotIndex + 1
      st.rot = st.rotation[st.rotIndex]
      st.servedInRot = 0
      for i = 1, 3 do st.slots[i].visible = false; st.slots[i].hideTimer = 0.4 end
    end
  end

  local function miss(i)
    local sl = st.slots[i]
    sl.visible = false
    sl.hideTimer = 1.0
    sl.react = { kind = "miss", t = 0.6 }
    st.misses = st.misses + 1
    host.playSe("SE_NOT_EFFECTIVE")
    advanceRotation()
  end

  local function finish()
    st.phase = "over"
    st.result = G.endGame(st.score, false, true)
  end

  function app:start(game)
    st = { diff = game.diff, participants = game.participants, phase = "countdown", t = 0, count = 3,
      timer = 60, score = 0, misses = 0, lives = (game.diff == "unlimited") and 3 or nil,
      kinds = KINDS_FOR[game.diff] or 3, rotation = rotationFor(game.diff), rotIndex = 1, servedInRot = 0,
      served = 0, slots = {}, result = nil }
    st.rot = st.rotation[1]
    for i = 1, 3 do
      st.slots[i] = { mon = game.participants[i] and game.participants[i].mon, visible = false, hideTimer = 0.3 + i * 0.2 }
    end
    drag = nil
    particles = {}
    game.hud = ("BERRY PICKER  %s"):format(Games.DIFF_LABEL[game.diff])
  end

  function app:quit()
    if st and st.phase ~= "over" then st = nil; G.endGame(nil, true) end
  end

  -- the driver ends a run early with a chosen score
  function app.forceEnd(score)
    if st and st.phase == "play" then st.score = score or st.score; finish() end
  end

  local function pilePos(k)
    local n = st.kinds
    local x0 = W / 2 - (n - 1) * 15
    return x0 + (k - 1) * 30, PILE.y + ((k % 2 == 0) and 10 or 0)
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (st and s and s.mode == "game") then return end
    if st.phase == "over" then
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) and st.t > 1.0 then G.leaveGame() end
      return
    end
    if st.phase ~= "play" then return end
    if ev.phase == "pressed" then
      for k = 1, st.kinds do
        local px, py = pilePos(k)
        if (ev.x - px) ^ 2 + (ev.y - py) ^ 2 <= 15 ^ 2 then
          drag = { kind = k, x = ev.x, y = ev.y, id = ev.id }
          return
        end
      end
    elseif ev.phase == "moved" then
      if drag and drag.id == ev.id then drag.x, drag.y = ev.x, ev.y end
    else
      if not (drag and drag.id == ev.id) then return end
      local d = drag
      drag = nil
      if ev.phase ~= "released" then return end
      for i, sl in ipairs(st.slots) do
        if sl.visible and math.abs(d.x - SLOT_X[i]) <= 28 and math.abs(d.y - (SLOT_Y - 20)) <= 34 then
          if sl.want == d.kind then
            local quick = (st.t - sl.shownAt) <= 1.5
            st.score = st.score + 1
            st.served = st.served + 1
            sl.visible = false
            sl.hideTimer = 0.5
            sl.react = { kind = quick and "quick" or "slow", t = 0.7 }
            host.playSe(quick and "SE_PIN" or "SE_SELECT")
            spawn("note", SLOT_X[i], SLOT_Y - 50, 1)
            if st.score % 10 == 0 then host.playCry(sl.mon); sl.cry = 1.0 end
            advanceRotation()
          else
            miss(i)
          end
          return
        end
      end
    end
  end

  function app:update(dt)
    local s = G.session
    if not (st and s and s.mode == "game") then app.live = false; return end
    app.live = true
    st.t = st.t + dt
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + dt
      p.y = p.y + p.vy * dt
      if p.age >= p.life then table.remove(particles, i) end
    end
    if st.phase == "countdown" then
      st.count = 3 - math.floor(st.t)
      if st.t >= 3 then st.phase = "play"; st.t = 0; host.playSe("SE_SUCCESS") end
      return
    end
    if st.phase ~= "play" then return end
    if st.diff ~= "unlimited" then
      st.timer = st.timer - dt
      if st.timer <= 0 then st.timer = 0; finish(); return end
    elseif st.misses >= 3 then
      finish()
      return
    end
    local want = activeSlots(st.rot.n)
    local active = {}
    for _, i in ipairs(want) do active[i] = true end
    for i, sl in ipairs(st.slots) do
      if sl.react then sl.react.t = sl.react.t - dt; if sl.react.t <= 0 then sl.react = nil end end
      if sl.cry then sl.cry = sl.cry - dt; if sl.cry <= 0 then sl.cry = nil end end
      if active[i] then
        if sl.visible then
          sl.left = sl.left - dt
          if sl.left <= 0 then miss(i) end
        else
          sl.hideTimer = (sl.hideTimer or 0) - dt
          if sl.hideTimer <= 0 then showSlot(i) end
        end
      elseif sl.visible then
        sl.visible = false
      end
    end
    s.game.hud = ("BERRY PICKER  %s   %d berries%s"):format(Games.DIFF_LABEL[st.diff], st.score,
      st.lives and ("   misses %d/3"):format(st.misses) or ("   %ds"):format(math.ceil(st.timer)))
  end

  -- ------- drawing

  local function drawBerry(G2, k, x, y, scale)
    local img = art(BERRY_KINDS[k])
    scale = scale or 1
    if img then
      G2.setColor(1, 1, 1, 1)
      local iw, ih = img:getDimensions()
      G2.draw(img, x, y, 0, scale, scale, iw / 2, ih / 2)
    else
      local c = BERRY_COLOR[k] or { 1, 1, 1 }
      G2.setColor(c[1], c[2], c[3], 1)
      G2.circle("fill", x, y, 9 * scale, 14)
      G2.setColor(0.3, 0.6, 0.3, 1)
      G2.rectangle("fill", x - 1, y - 13 * scale, 2, 6 * scale)
    end
  end

  local function drawIcon(G2, mon, x, y, scale)
    local ic = host.icon and host.icon(mon)
    if ic and ic.image and ic.quads then
      G2.setColor(1, 1, 1, 1)
      local f = math.floor(Pointer.now() * 4) % (ic.frames or 1)
      drawPixel(ic.image, ic.quads[f] or ic.quads[0], x, y, 0, scale, scale, (ic.w or 32) / 2, ic.h or 32)
    else
      G2.setColor(0.9, 0.75, 0.3, 1)
      G2.circle("fill", x, y - 14 * scale, 12 * scale, 16)
    end
  end

  function app:draw(G2, w, h)
    setShape(h)
    local s = G.session
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local bg = art("game/berry_bg")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local bl = app.bleed or 0
      local sc = math.max(w / bw, (h + bl) / bh)
      G2.draw(bg, (w - bw * sc) / 2, -bl + (h + bl - bh * sc) / 2, 0, sc, sc)
    else
      G2.setColor(0.6, 0.85, 1, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(0.35, 0.7, 0.35, 1)
      G2.rectangle("fill", 0, 120, w, h - 120)
    end
    if not st then return end
    -- the heap of berries
    local pile = art("game/berry_tree")
    if pile then
      G2.setColor(1, 1, 1, 1)
      G2.draw(pile, w / 2, PILE.y + 22, 0, 0.42, 0.42, 160, 150)
    else
      G2.setColor(0.45, 0.3, 0.15, 1)
      G2.ellipse("fill", w / 2, PILE.y + 18, 90, 22)
    end
    for k = 1, st.kinds do
      local px, py = pilePos(k)
      drawBerry(G2, k, px, py, 1)
    end
    -- grass and the Pokemon
    local grass = art("game/berry_grass")
    if grass then
      G2.setColor(1, 1, 1, 1)
      G2.draw(grass, 0, SLOT_Y - 20, 0, w / 320, 1)
    end
    for i, sl in ipairs(st.slots) do
      local x = SLOT_X[i]
      if sl.visible then
        local rise = math.min(1, (st.t - sl.shownAt) * 6)
        local y = SLOT_Y + (1 - rise) * 24
        drawIcon(G2, sl.mon, x, y, 2)
        -- the want bubble with a patience ring, between the Pokemon's head and the pile
        local bub = art("game/want_bubble")
        local bx, by = x, y - 74
        if bub then
          G2.setColor(1, 1, 1, 1)
          G2.draw(bub, bx, by, 0, 0.72, 0.72, 30, 40)
        else
          G2.setColor(1, 1, 1, 0.95)
          G2.circle("fill", bx, by, 19, 20)
        end
        drawBerry(G2, sl.want, bx, by - 4, 0.9)
        local f = math.max(0, sl.left / sl.patience)
        G2.setColor(f > 0.35 and 0.3 or 0.9, f > 0.35 and 0.8 or 0.3, 0.3, 1)
        G2.arc("line", "open", bx, by, 20, -math.pi / 2, -math.pi / 2 + f * 2 * math.pi, 24)
      end
      if sl.react then
        local id = sl.react.kind == "quick" and "game/note_red" or (sl.react.kind == "slow" and "game/note_yellow" or nil)
        local img = id and art(id)
        if img then
          G2.setColor(1, 1, 1, math.min(1, sl.react.t * 2))
          G2.draw(img, x, SLOT_Y - 70 - (0.7 - sl.react.t) * 20, 0, 0.8, 0.8, 20, 20)
        else
          G2.setColor(sl.react.kind == "miss" and 0.9 or 0.3, sl.react.kind == "miss" and 0.3 or 0.8, 0.3, math.min(1, sl.react.t * 2))
          G2.printf(sl.react.kind == "miss" and "X" or "OK", x - 20, SLOT_Y - 78, 40, "center")
        end
      end
    end
    for _, p in ipairs(particles) do
      G2.setColor(1, 1, 1, 1 - p.age / p.life)
      G2.circle("fill", p.x, p.y, 2, 6)
    end
    if drag then drawBerry(G2, drag.kind, drag.x, drag.y, 1.2) end
    -- the HUD: berries picked in the game's digits, the clock or the misses beside them
    local onArt = Games.drawHudBox(G2, art, 4, 4, 122, 22)
    G2.setColor(1, 1, 1, 1)
    if app.smallFont then G2.setFont(app.smallFont) end
    Games.drawNumber(G2, art, st.score, 12, 7, 16, "left")
    if onArt then G2.setColor(0.15, 0.15, 0.2, 1) end
    local right = st.lives and ("miss %d/3"):format(st.misses)
      or Games.line("berry", "timeLeft", { N = math.ceil(st.timer) }, ("Time Left: %d"):format(math.ceil(st.timer)))
    G2.printf(right, 44, 9, 78, "right")
    if app.font then G2.setFont(app.font) end
    if st.phase == "countdown" then
      G2.setColor(0, 0, 0, 0.4)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(1, 1, 1, 1)
      G2.printf(st.count > 0 and Games.line("berry", "ready", nil, "READY") or Games.line("berry", "start", nil, "START!"), 0, h / 2 - 10, w, "center")
    elseif st.phase == "over" and st.result then
      Games.drawResult(G2, w, h, st.result, app, art,
        ("%s: %d"):format(Games.line("berry", "count", nil, "Berries"), st.score))
    end
  end

  -- for the driver and tests
  function app.debugState() return st end

  function app:releaseAll() drag = nil end
  app.leave = app.releaseAll
  return app
end
