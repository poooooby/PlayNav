-- HEAD IT: balls of yarn fall over one, two, then three of the player's
-- Pokemon; tap a Pokemon when the ball is in the sweet spot above its head
-- for 3 points, early or late for 1. Combos, Fever, the tenth-hit bonuses
-- and the big ball at the end follow Bulbapedia "Head It".

return function(mod, Pointer, G, Games, Rules, host)

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "game_head", title = "HEAD IT", live = true }

  function app:wantsSurface()
    local s = G.session
    return s ~= nil and s.mode == "game" and s.game and s.game.id == "head" or false
  end

  local W, H = 256, 178
  local LANE_X = { 64, 128, 192 }
  local MON_Y = 158
  local SWEET_Y = 108          -- the top of the head at 2x
  local SWEET, OK = 10, 26
  local SPEED = { easy = 55, normal = 70, hard = 85, unlimited = 85 }
  local BASE_GAP = { easy = 1.5, normal = 1.2, hard = 1.0, unlimited = 1.0 }
  local MIN_GAP = { easy = 0.9, normal = 0.7, hard = 0.55, unlimited = 0.5 }
  local FEVER_AT = { easy = 5, normal = 15, hard = 15, unlimited = 15 }
  local COLORS = { "rose", "gold", "sky" }
  local TINT = { rose = { 1, 0.6, 0.8 }, gold = { 1, 0.9, 0.4 }, sky = { 0.5, 0.7, 1 }, violet = { 0.7, 0.45, 0.9 }, big = { 0.95, 0.95, 0.95 } }

  local st = nil
  local particles = {}

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local function spawn(kind, x, y, n)
    for _ = 1, n or 1 do
      particles[#particles + 1] = { kind = kind, x = x + (math.random() - 0.5) * 20, y = y,
        vx = (math.random() - 0.5) * 60, vy = -40 - math.random() * 30, life = 0.6, age = 0 }
    end
  end

  local function lanesNow()
    if st.diff == "unlimited" then
      local phase = math.floor(st.t / st.loopLen * 3) % 3
      return phase + 1
    end
    if st.t < 20 then return 1 end
    if st.t < 40 then return 2 end
    return 3
  end

  local function finish()
    st.phase = "over"
    st.final = st.score + st.longest + (st.bigBonus or 0)
    st.result = G.endGame(st.final, false, true)
  end

  function app:start(game)
    st = { diff = game.diff, participants = game.participants, phase = "countdown", t = 0, count = 3,
      score = 0, combo = 0, longest = 0, fever = false, misses = 0, lives = (game.diff == "unlimited") and 3 or nil,
      balls = {}, nextBall = 0.8, lanes = 1, lastLanes = 1, loopLen = 45 + math.random() * 30,
      bigDropped = false, bigBonus = 0, result = nil, hitFlash = {} }
    particles = {}
    game.hud = ("HEAD IT  %s"):format(Games.DIFF_LABEL[game.diff])
  end

  function app:quit()
    if st and st.phase ~= "over" then st = nil; G.endGame(nil, true) end
  end

  function app.forceEnd(score)
    if st and st.phase == "play" then st.score = score or st.score; finish() end
  end

  local function colorFor(lanes)
    if st.diff == "unlimited" then return COLORS[lanes] end
    return COLORS[lanes]
  end

  local function spawnBall(lanes)
    local lane = math.random(1, lanes)
    local color = colorFor(lanes)
    local speed = SPEED[st.diff] * (color == "sky" and 1.3 or 1)
    local kind = "normal"
    local r = math.random()
    if st.diff ~= "easy" and r < 0.1 then kind = "fast"; color = "violet"; speed = speed * 1.6
    elseif r > 0.92 then kind = "slow"; speed = speed * 0.6 end
    st.balls[#st.balls + 1] = { lane = lane, y = -40, speed = speed, color = color, kind = kind, hit = false }
  end

  local function addPoints(n)
    st.score = math.min(999, st.score + n)
  end

  local function registerHit(ball, sweet)
    ball.hit = true
    st.combo = st.combo + 1
    st.longest = math.max(st.longest, st.combo)
    local base = sweet and 3 or 1
    if st.fever then base = base * 2 end
    addPoints(base)
    local c = st.combo
    if c % 10 == 0 then
      if c % 100 == 0 then addPoints(100)
      elseif c % 50 == 0 then addPoints(50)
      else addPoints(10) end
    end
    if not st.fever and st.combo >= FEVER_AT[st.diff] then st.fever = true end
    st.gap = math.max(MIN_GAP[st.diff], (st.gap or BASE_GAP[st.diff]) - 0.03)
    host.playSe(sweet and "SE_PIN" or "SE_SELECT")
    st.hitFlash[ball.lane] = sweet and "sweet" or "ok"
    st.flashT = 0.4
    spawn(sweet and "star" or "puff", LANE_X[ball.lane], SWEET_Y, sweet and 3 or 2)
    local mon = st.participants[ball.lane] and st.participants[ball.lane].mon
    if st.combo % 10 == 0 and mon then host.playCry(mon) end
  end

  local function missBall()
    st.combo = 0
    st.missAt = st.t
    st.fever = false
    st.gap = BASE_GAP[st.diff]
    st.misses = st.misses + 1
    host.playSe("SE_NOT_EFFECTIVE")
    if st.lives and st.misses >= 3 then finish() end
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (st and s and s.mode == "game") then return end
    if st.phase == "over" then
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) and st.t > 1.0 then G.leaveGame() end
      return
    end
    if st.phase ~= "play" or ev.phase ~= "pressed" then return end
    -- which lane was tapped
    local lane
    for i = 1, st.lanes do
      if math.abs(ev.x - LANE_X[i]) <= 32 and ev.y >= 60 then lane = i end
    end
    if not lane then return end
    st.hop = { lane = lane, t = 0.25 }
    -- the lowest live ball in that lane close to the head
    local best, bestDy
    for _, b in ipairs(st.balls) do
      if b.lane == lane and not b.hit then
        local dy = b.y - SWEET_Y
        if dy >= -OK - 10 and (not bestDy or math.abs(dy) < math.abs(bestDy)) then best, bestDy = b, dy end
      end
    end
    if not best then return end
    if best.big then
      if bestDy < -8 then return end           -- the big ball cannot be hit early
      best.hit = true
      st.bigBonus = (math.abs(bestDy) <= 8) and 50 or 10
      host.playSe("SE_SUCCESS")
      spawn("star", LANE_X[lane], SWEET_Y, 6)
      finish()
      return
    end
    if math.abs(bestDy) <= SWEET then registerHit(best, true)
    elseif math.abs(bestDy) <= OK then registerHit(best, false) end
  end

  function app:update(dt)
    local s = G.session
    if not (st and s and s.mode == "game") then app.live = false; return end
    app.live = true
    st.t = st.t + dt
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + dt
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vy = p.vy + 80 * dt
      if p.age >= p.life then table.remove(particles, i) end
    end
    if st.hop then st.hop.t = st.hop.t - dt; if st.hop.t <= 0 then st.hop = nil end end
    if st.flashT then st.flashT = st.flashT - dt; if st.flashT <= 0 then st.flashT = nil; st.hitFlash = {} end end
    if st.phase == "countdown" then
      st.count = 3 - math.floor(st.t)
      if st.t >= 3 then st.phase = "play"; st.t = 0; st.gap = BASE_GAP[st.diff]; host.playSe("SE_SUCCESS") end
      return
    end
    if st.phase ~= "play" then return end
    local timed = st.diff ~= "unlimited"
    if timed and st.t >= 60 and not st.bigDropped then
      st.bigDropped = true
      st.balls[#st.balls + 1] = { lane = math.random(1, 3), y = -60, speed = SPEED[st.diff] * 0.8, color = "big", kind = "big", big = true, hit = false }
    end
    st.lanes = timed and (st.t >= 60 and 3 or lanesNow()) or lanesNow()
    if st.lanes ~= st.lastLanes then st.lastLanes = st.lanes; st.gap = BASE_GAP[st.diff] end
    if not st.bigDropped then
      st.nextBall = st.nextBall - dt
      if st.nextBall <= 0 then
        spawnBall(st.lanes)
        st.nextBall = st.gap or BASE_GAP[st.diff]
      end
    end
    for i = #st.balls, 1, -1 do
      local b = st.balls[i]
      b.y = b.y + b.speed * dt
      if b.hit then
        b.fade = (b.fade or 0) + dt
        if b.fade > 0.3 then table.remove(st.balls, i) end
      elseif b.y > MON_Y + 10 then
        table.remove(st.balls, i)
        if b.big then finish(); return end
        missBall()
        if st.phase == "over" then return end
      end
    end
    if st.bigDropped and #st.balls == 0 and st.phase == "play" then finish(); return end
    s.game.hud = ("HEAD IT  %s   %d pts  combo %d%s%s"):format(Games.DIFF_LABEL[st.diff], st.score, st.combo,
      st.fever and "  FEVER" or "", st.lives and ("  misses %d/3"):format(st.misses) or ("  %ds"):format(math.max(0, math.ceil(60 - st.t))))
  end

  -- ------- drawing

  local YARN_ART = { rose = "yarn/pink", gold = "yarn/yellow", sky = "yarn/blue", violet = "yarn/purple", big = "game/yarn_big" }

  local function drawBall(G2, b)
    local x = LANE_X[b.lane]
    local img = art(YARN_ART[b.color])
    local a = b.hit and math.max(0, 1 - (b.fade or 0) / 0.3) or 1
    local squash = b.kind == "slow" and 0.8 or 1
    if img then
      G2.setColor(1, 1, 1, a)
      local iw, ih = img:getDimensions()
      local k = b.big and 1.1 or 0.55
      G2.draw(img, x, b.y, 0, k * (b.kind == "slow" and 1.2 or 1), k * squash, iw / 2, ih * 0.6)
    else
      local c = TINT[b.color] or TINT.rose
      G2.setColor(c[1], c[2], c[3], a)
      G2.ellipse("fill", x, b.y, b.big and 22 or 14, (b.big and 22 or 14) * squash, 20)
      G2.setColor(0, 0, 0, 0.3 * a)
      G2.ellipse("line", x, b.y, b.big and 22 or 14, (b.big and 22 or 14) * squash, 20)
    end
  end

  local function drawIcon(G2, mon, x, y, scale, hop)
    local ic = host.icon and host.icon(mon)
    y = y - (hop or 0)
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
    local s = G.session
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local bg = art("game/head_bg")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local bl = app.bleed or 0
      local sc = math.max(w / bw, (h + bl) / bh)
      G2.draw(bg, (w - bw * sc) / 2, -bl + (h + bl - bh * sc) / 2, 0, sc, sc)
    else
      G2.setColor(0.55, 0.78, 0.98, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(0.42, 0.75, 0.42, 1)
      G2.rectangle("fill", 0, MON_Y, w, h - MON_Y)
    end
    if not st then return end
    local cloud = art("game/cloud")
    if cloud then
      G2.setColor(1, 1, 1, 0.9)
      local off = (Pointer.now() * 6) % (w + 120)
      G2.draw(cloud, off - 120, 18, 0, 0.6, 0.6)
      G2.draw(cloud, (off + 150) % (w + 120) - 120, 40, 0, 0.45, 0.45)
    end
    if st.fever then
      local rb = art("game/rainbow")
      if rb then
        G2.setColor(1, 1, 1, 0.8)
        G2.draw(rb, w / 2, 60, 0, 0.6, 0.6, 200, 85)
      else
        for i, c in ipairs({ { 1, 0.3, 0.3 }, { 1, 0.7, 0.2 }, { 1, 1, 0.3 }, { 0.3, 0.9, 0.4 }, { 0.3, 0.5, 1 } }) do
          G2.setColor(c[1], c[2], c[3], 0.6)
          G2.setLineWidth(3)
          G2.arc("line", "open", w / 2, 110, 110 - i * 4, math.pi, 2 * math.pi, 40)
        end
        G2.setLineWidth(1)
      end
    end
    -- lanes, sweet-spot stars on Easy / Normal, the Pokemon
    for i = 1, 3 do
      local x = LANE_X[i]
      local active = i <= st.lanes
      local mon = st.participants[i] and st.participants[i].mon
      if active then
        if st.diff == "easy" or st.diff == "normal" then
          local star = art("star/white")
          G2.setColor(1, 1, 0.7, 0.9)
          if star then G2.draw(star, x, SWEET_Y, 0, 0.8, 0.8, 10, 10) else G2.circle("line", x, SWEET_Y, 6, 10) end
        end
        local hop = (st.hop and st.hop.lane == i) and math.sin(st.hop.t / 0.25 * math.pi) * 12 or 0
        drawIcon(G2, mon, x, MON_Y, 2, hop)
        local fl = st.hitFlash[i]
        if fl then
          G2.setColor(1, 1, 1, 1)
          if app.smallFont then G2.setFont(app.smallFont) end
          G2.printf(fl == "sweet" and "+3" or "+1", x - 20, SWEET_Y - 26, 40, "center")
          if app.font then G2.setFont(app.font) end
        end
      else
        G2.setColor(1, 1, 1, 0.35)
        drawIcon(G2, mon, x, MON_Y, 2, 0)
      end
    end
    for _, b in ipairs(st.balls) do drawBall(G2, b) end
    for _, p in ipairs(particles) do
      local f = 1 - p.age / p.life
      if p.kind == "star" then G2.setColor(1, 0.95, 0.4, f) else G2.setColor(1, 1, 1, f * 0.7) end
      G2.circle("fill", p.x, p.y, p.kind == "star" and 3 or 4, 8)
    end
    -- the HUD: the score in the game's digits; Chances as yarn on Unlimited, else the clock
    local onArt = Games.drawHudBox(G2, art, 4, 4, 150, 22)
    G2.setColor(1, 1, 1, 1)
    if app.smallFont then G2.setFont(app.smallFont) end
    Games.drawNumber(G2, art, st.score, 12, 7, 16, "left")
    if onArt then G2.setColor(0.15, 0.15, 0.2, 1) end
    if st.lives then
      local chance = { art("game/chance_blue"), art("game/chance_pink"), (art("game/chance_orange")) }
      if chance[1] and chance[2] and chance[3] then
        G2.printf(Games.line("head", "chances", nil, "Chances:"), 60, 9, 48, "right")
        for i = 1, 3 do
          local img = chance[i]
          G2.setColor(1, 1, 1, (i <= 3 - st.misses) and 1 or 0.25)
          G2.draw(img, 116 + (i - 1) * 13, 15, 0, 12 / img:getWidth(), 12 / img:getHeight(), img:getWidth() / 2, img:getHeight() / 2)
        end
      else
        G2.printf(("miss %d/3"):format(st.misses), 60, 9, 90, "right")
      end
    else
      local left = math.max(0, math.ceil(60 - st.t))
      G2.printf(Games.line("head", "timeLeft", { N = left }, ("Time Left: %d"):format(left)), 60, 9, 90, "right")
    end
    if st.combo >= 2 and st.phase == "play" then
      G2.setColor(0.1, 0.15, 0.4, 1)
      G2.printf(Games.line("head", "combo", { N = st.combo }, ("%d-HIT COMBO"):format(st.combo)), 8, 28, 150, "left")
    end
    if st.fever and st.phase == "play" then
      G2.setColor(1, 0.85, 0.2, 1)
      if app.font then G2.setFont(app.font) end
      G2.printf(Games.line("head", "fever", nil, "FEVER"), 0, 40, w, "center")
      if app.smallFont then G2.setFont(app.smallFont) end
    end
    if st.missAt and st.t - st.missAt < 0.8 and st.phase == "play" then
      G2.setColor(1, 0.3, 0.3, 1)
      if app.font then G2.setFont(app.font) end
      G2.printf(Games.line("head", "miss", nil, "MISS!"), 0, 64, w, "center")
      if app.smallFont then G2.setFont(app.smallFont) end
    end
    if app.font then G2.setFont(app.font) end
    if st.phase == "countdown" then
      G2.setColor(0, 0, 0, 0.4)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(1, 1, 1, 1)
      G2.printf(st.count > 0 and Games.line("head", "ready", nil, "READY") or Games.line("head", "start", nil, "START!"), 0, h / 2 - 10, w, "center")
    elseif st.phase == "over" and st.result then
      Games.drawResult(G2, w, h, st.result, app, art,
        ("%s %d   %s %d\n%s %d   %s %d"):format(
          Games.line("head", "headingPoints", nil, "Heading Points"), st.score,
          Games.line("head", "lastCombo", nil, "Last Combo Record"), st.longest,
          Games.line("head", "bigYarn", nil, "Big Yarn Bonus"), st.bigBonus or 0,
          Games.line("head", "total", nil, "TOTAL:"), st.final or 0))
    end
  end

  -- for the driver and tests
  function app.debugState() return st end

  function app:releaseAll() end
  app.leave = app.releaseAll
  return app
end
