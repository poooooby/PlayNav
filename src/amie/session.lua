-- Pokemon-Amie: the session. One Pokemon at a time owns both screens: the
-- top-screen layer (pushed on the Gen 3 UI stack, which pauses the field)
-- and whichever surface app the mode needs. Modes:
--   home    the Amie room: the Pokemon wanders; tap it for DECORATE / PLAY / SWITCH
--   play    the close-up: petting, Poke Puffs, hit, high-five, and the games picker
--           (s.tool "games": three badges, four difficulties, on the same screen)
--   decorate  wallpaper, cushions, objects and the puff set out for visitors
--   game    a minigame is running; s.game = { id, diff, participants }
-- A battle never opens a session and drops nothing: Poke Puffs come from the minigames.
-- The stat rules live in src/amie/rules.lua, the per-species spots in
-- src/amie/petting.lua, the save data in src/amie/store.lua.
--
-- deps = { host, Rules, Petting, Store, Apps, onChange = fn() }

return function(mod, deps)
  local host, Rules, Petting, Store, Apps = deps.host, deps.Rules, deps.Petting, deps.Store, deps.Apps
  local onChange = deps.onChange or function() end

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local N = Rules.N

  local G = { session = nil, previousApp = nil, rng = math.random, events = {} }
  G.Rules, G.Petting, G.Store = Rules, Petting, Store

  local function say(text, secs)
    local s = G.session
    if not s then return end
    s.message = text
    s.messageUntil = host.now() + (secs or 2.5)
    s.log[#s.log + 1] = text
    if #s.log > 6 then table.remove(s.log, 1) end
    onChange()
  end
  G.say = say

  -- a line of the game's own text when it is extracted (G.text, src/amie/text.lua), else ours
  local TX_FALLBACK = { needThree = "You need three healthy Pokemon to play.", egg = "You can't play with an Egg!",
    switch = "SWITCH", selectMon = "Pick a Pokemon to switch to.", affection = "Affection", fullness = "Fullness",
    enjoyment = "Enjoyment", play = "PLAY", decorate = "DECORATE", switchLabel = "SWITCH" }
  function G.tx(key, vars, fallback)
    if G.text then return G.text.get(key, vars) end
    return fallback or TX_FALLBACK[key] or key
  end

  -- things the apps may want to animate: { kind = "dance", cries = n } etc.
  local function emit(ev)
    G.events[#G.events + 1] = ev
    if #G.events > 16 then table.remove(G.events, 1) end
  end
  function G.takeEvents()
    local out = G.events
    G.events = {}
    return out
  end

  -- every affection change passes here so milestones fire once
  local function affectionChanged(s, before)
    local after = s.meters.affection or 0
    if after == before then return end
    local cries = Rules.danceCrossed(before, after)
    if cries then emit({ kind = "dance", cries = cries }) end
    s.meters.gifts = s.meters.gifts or {}
    for _, t in ipairs(Rules.giftsCrossed(before, after)) do
      if not s.meters.gifts[t] then
        s.meters.gifts[t] = true
        local pending = Store.visitors().gifts
        pending[#pending + 1] = { kind = "milestone", affection = t, key = s.key, name = s.name }
        Store.saveVisitors()
        emit({ kind = "gift", affection = t })
      end
    end
  end

  -- ------- persistence

  local function persist()
    local s = G.session
    if not s then return end
    s.meters.lastCareAt = host.wallClock()
    Store.saveMons()
    Store.savePuffs()
  end
  G.persist = persist

  -- the Pokemon the out-of-session rules (steps, battles) apply to
  function G.activeKey()
    local meta = Store.meta()
    if meta.activeKey then return meta.activeKey end
    local lead = host.leadMon and host.leadMon()
    return lead and host.monKey(lead) or nil
  end

  function G.setActiveKey(key)
    local meta = Store.meta()
    meta.activeKey = key
    Store.saveMeta()
  end

  -- ------- the top-screen layer (240x160, Gen 3 UI stack contract)

  local Layer = { isMenu = true }
  G.layer = Layer

  -- the pad as a tap: a press and release at an app point, through the app's own touch code
  -- (a tap's record: no travel, no time held), so a button does exactly what a tap does
  function G.padTap(app, x, y)
    if not (app and app.pointer and x and y) then return false end
    local rec = { travel = 0, downAt = 0, upAt = 0, x = x, y = y, vx = 0, vy = 0 }
    pcall(app.pointer, app, { phase = "pressed", id = "pad", x = x, y = y }, rec)
    pcall(app.pointer, app, { phase = "released", id = "pad", x = x, y = y }, rec)
    return true
  end

  function Layer.handleInput(input)
    local s = G.session
    if not s then return end
    if s.mode == "home" then
      if input:wasPressed("a") then G.enterPlay()
      elseif input:wasPressed("b") or input:wasPressed("start") then G.finish() end
    elseif s.mode == "decorate" then
      -- the drawer folds, a held item goes back, else the room (src/amie/decorate.lua)
      if input:wasPressed("b") then
        if G.decorateBack then G.decorateBack() else G.enterHome(false) end
      elseif input:wasPressed("left") or input:wasPressed("right") then
        -- left / right: the wallpapers, or the drawer's pages while it is open
        local deco = Apps:get("decorate")
        local st = deco and deco.state and deco.state()
        if st and not st.held then
          local right = input:wasPressed("right")
          local what = (st.mode == "drawer") and (right and "pageRight" or "pageLeft") or (right and "wallRight" or "wallLeft")
          G.padTap(deco, deco.tapPoint(what))
        end
      end
    elseif s.mode == "game" then
      -- the game's own pad first (its buttons, Head It's Pokemon, Tile Puzzle's cursor), else B quits
      local ga = G.gameApp
      if ga and ga.padInput and ga.padInput(input) then return end
      if input:wasPressed("b") and ga and ga.quit then ga:quit() end
    else
      -- PLAY's own pad (src/amie/play.lua: the picker's D-pad / A / B, the strip's D-pad)
      if G.playInput and G.playInput(input) then return end
      if input:wasPressed("b") or input:wasPressed("start") then G.back() end
    end
  end

  function Layer.update(dt)
    G.tick(dt)
    -- 3D AMIE: PLAY's stage rendered here, outside the engine's draw (src/amie/play.lua)
    if G.prepareStage then G.prepareStage(dt) end
  end

  local HEART = { 0.95, 0.35, 0.5 }

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

  local function drawHeart(G2, x, y, r, filled)
    if filled then G2.setColor(HEART[1], HEART[2], HEART[3], 1) else G2.setColor(0.75, 0.75, 0.8, 1) end
    G2.circle("fill", x - r * 0.5, y - r * 0.3, r * 0.55, 12)
    G2.circle("fill", x + r * 0.5, y - r * 0.3, r * 0.55, 12)
    G2.polygon("fill", x - r * 1.0, y - r * 0.1, x + r * 1.0, y - r * 0.1, x, y + r * 1.0)
  end

  -- the three meters the game names, a word and five icons each (its own icons when extracted)
  local METER_ROWS = { { "affection", "ui/icon_heart", HEART }, { "fullness", "ui/icon_full", { 0.95, 0.65, 0.25 } },
    { "enjoyment", "ui/icon_note", { 0.35, 0.65, 0.95 } } }
  local function topIcon(id)
    local A = G.assets
    if not (A and A.image) or A.enabled == false then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end
  local function drawMeters(G2, s)
    for r, row in ipairs(METER_ROWS) do
      local y = 24 + (r - 1) * 24
      G2.setColor(1, 1, 1, 0.85)
      G2.rectangle("fill", 4, y, 68, 23, 3, 3)
      drawText(G.tx(row[1]), 7, y + 1, { maxWidth = 62 })
      local level = Rules.level(s.meters[row[1]])
      local img = topIcon(row[2])
      for i = 1, 5 do
        local x = 11 + (i - 1) * 12
        if img then
          G2.setColor(1, 1, 1, i <= level and 1 or 0.25)
          G2.draw(img, x, y + 18, 0, 9 / img:getWidth(), 9 / img:getHeight(), img:getWidth() / 2, img:getHeight() / 2)
        elseif row[1] == "affection" then
          drawHeart(G2, x, y + 18, 3.5, i <= level)
        else
          local c = row[3]
          if i <= level then G2.setColor(c[1], c[2], c[3], 1) else G2.setColor(0.75, 0.75, 0.8, 1) end
          G2.circle("fill", x, y + 18, 3.5, 10)
        end
      end
    end
  end

  function Layer.draw()
    local s = G.session
    if not (s and love and love.graphics) then return end
    -- src/hd_top.lua draws the scene over the frame at window resolution; then only the
    -- backdrop goes into the engine's 240x160 canvas
    if Layer.hdLive then Layer.backdrop(love.graphics); return end
    Layer.drawScene(love.graphics)
  end

  function Layer.backdrop(G2)
    G2.setColor(0.55, 0.78, 0.98, 1)
    G2.rectangle("fill", 0, 0, 240, 160)
    G2.setColor(0.42, 0.75, 0.42, 1)
    G2.rectangle("fill", 0, 96, 240, 64)
  end

  -- Amie paints the whole playfield, as Super Training does (src/hd_top.lua hands the
  -- playfield in as Layer.extent, 240x160 units): main then lays the screens out the same way
  -- for both, the touch screen across the bottom at Super Training's size
  function Layer.fillTop() return G.session ~= nil end

  -- DECORATE's top screen (assets/amie_cottage.png, 1920 square, drawn to cover whatever the
  -- playfield is)
  local cottage = nil
  local function cottageImage()
    if cottage == nil then
      cottage = false
      local bytes = mod.read and mod:read("assets/amie_cottage.png")
      local LI, LF = love and love.image, love and love.filesystem
      if bytes and LI and LF and love.graphics then
        local ok, im = pcall(function()
          local img = love.graphics.newImage(LI.newImageData(LF.newFileData(bytes, "amie_cottage.png")), { mipmaps = true })
          img:setFilter("linear", "linear")
          img:setMipmapFilter("linear")
          return img
        end)
        cottage = ok and im or false
      end
    end
    return cottage or nil
  end

  local function cover(G2, img, e)
    local iw, ih = img:getDimensions()
    local k = math.max(e.w / iw, e.h / ih)
    G2.setColor(1, 1, 1, 1)
    G2.draw(img, e.x + (e.w - iw * k) / 2, e.y + (e.h - ih * k) / 2, 0, k, k)
  end

  -- PLAY's top screen, sky only as in the game: the dotted sky with the rainbow
  -- (assets/amie-play-bg.png, 1920 square) anchored
  -- bottom right so the rainbow shows, translucent clouds drifting across, white clouds along
  -- the foot hiding the rainbow's end, soap bubbles rising (the game's scene/* textures, from
  -- the import; drawn plain without them)
  local playSky = nil
  local function playSkyImage()
    if playSky == nil then
      playSky = false
      local bytes = mod.read and mod:read("assets/amie-play-bg.png")
      local LI, LF = love and love.image, love and love.filesystem
      if bytes and LI and LF and love.graphics then
        local ok, im = pcall(function()
          local img = love.graphics.newImage(LI.newImageData(LF.newFileData(bytes, "amie-play-bg.png")), { mipmaps = true })
          img:setFilter("linear", "linear")
          img:setMipmapFilter("linear")
          return img
        end)
        playSky = ok and im or false
      end
    end
    return playSky or nil
  end
  G.playSkyImage = playSkyImage

  -- n drifting things, the same each frame from their index (no per-frame tables)
  local function hash(i, k) return (math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end

  local function drawPlayTop(G2, e)
    -- 3D AMIE: the stage seen looking up (src/amie/stage3d.lua; PLAY's update renders it)
    local St, s = G.stage3d, G.session
    if St and St.on and s and s.mode == "play" and St.drawTop(G2, e.x, e.y, e.w, e.h) then return end
    local t = (love and love.timer and love.timer.getTime()) or 0
    local sky = playSkyImage()
    if sky then
      local iw, ih = sky:getDimensions()
      local k = math.max(e.w / iw, e.h / ih)
      G2.setColor(1, 1, 1, 1)
      G2.draw(sky, e.x + e.w - iw * k, e.y + e.h - ih * k, 0, k, k)
    else
      G2.setColor(0.04, 0.12, 0.55, 1)
      G2.rectangle("fill", e.x, e.y, e.w, e.h)
    end
    -- the translucent clouds drifting right
    local cloud = topIcon("scene/cloud")
    if cloud then
      -- the texture's left part is the cloud; two small scraps sit beside it
      local tw, th = cloud:getDimensions()
      if not G.cloudQuad and love and love.graphics then G.cloudQuad = love.graphics.newQuad(0, 0, tw * 0.72, th, tw, th) end
      local cw, ch = tw * 0.72, th
      for i = 1, 4 do
        local w = 70 + 40 * hash(i, 1)
        local k = w / cw
        local span = e.w + w
        local x = e.x - w + ((t * (4 + 3 * hash(i, 2)) + span * hash(i, 3)) % span)
        local y = e.y + e.h * (0.08 + 0.55 * hash(i, 4))
        -- added, not blended: the texture's grey under its alpha would darken the sky
        G2.setBlendMode("add")
        G2.setColor(0.35, 0.45, 0.7, 0.55)
        if G.cloudQuad then G2.draw(cloud, G.cloudQuad, x, y, 0, k, k) else G2.draw(cloud, x, y, 0, k, k) end
        G2.setBlendMode("alpha")
      end
    end
    -- white clouds along the foot
    local cumulus = topIcon("scene/cumulus")
    if cumulus then
      local cw, ch = cumulus:getDimensions()
      G2.setColor(1, 1, 1, 1)
      local k = (e.w * 0.42) / cw
      for i = 0, 2 do
        G2.draw(cumulus, e.x + e.w * (i * 0.36 - 0.06), e.y + e.h - ch * k * 0.55, 0, k, k)
      end
    end
    -- soap bubbles rising and wobbling
    local bub = topIcon("scene/bubbles")
    local quad = G.bubbleQuad
    if bub and not quad and love and love.graphics then
      local bw, bh = bub:getDimensions()
      quad = love.graphics.newQuad(0, bh / 2, bw / 4, bh / 2, bw, bh)
      G.bubbleQuad = quad
    end
    for i = 1, 14 do
      local r = 3 + 6 * hash(i, 5)
      local span = e.h + 2 * r
      local y = e.y + e.h + r - ((t * (8 + 10 * hash(i, 6)) + span * hash(i, 7)) % span)
      local x = e.x + e.w * hash(i, 8) + math.sin(t * 1.3 + i) * 4
      if bub and quad then
        local _, _, qw = quad:getViewport()
        G2.setColor(1, 1, 1, 0.85)
        G2.draw(bub, quad, x, y, 0, 2 * r / qw, 2 * r / qw, qw / 2, qw / 2)
      else
        G2.setColor(0.85, 0.92, 1, 0.5)
        G2.circle("line", x, y, r, 12)
      end
    end
  end

  -- the top screen in 240x160 units (drawn by Layer.draw or, at window resolution, hd_top);
  -- e is the playfield (the 240x160 frame when not filling): the sky and grass cover it, the
  -- name and meters sit at its top left, the words at its foot, the Pokemon in the frame
  function Layer.drawScene(G2)
    local s = G.session
    if not s then return end
    local e = Layer.extent or { x = 0, y = 0, w = 240, h = 160 }
    G2.push("all")
    -- a game with its own top screen (Berry Picker's score.bclyt)
    if s.mode == "game" and G.gameApp and G.gameApp.drawTop then
      local ok, drew = pcall(G.gameApp.drawTop, G2, e)
      if not ok then mod.log:warn("game top screen failed: %s", tostring(drew)) end
      if ok and drew then G2.pop(); return end
    end
    if s.mode == "decorate" then
      local img = cottageImage()
      if img then
        cover(G2, img, e)
        G2.pop()
        return
      end
    end
    -- PLAY (and a game without its own top screen): the sky only, as the game
    if s.mode == "play" or s.mode == "game" then
      drawPlayTop(G2, e)
      G2.pop()
      return
    end
    G2.setColor(0.55, 0.78, 0.98, 1)
    G2.rectangle("fill", e.x, e.y, e.w, e.h)
    G2.setColor(0.42, 0.75, 0.42, 1)
    G2.rectangle("fill", e.x, 96, e.w, e.y + e.h - 96)
    G2.setColor(0.95, 0.9, 0.55, 0.55)
    G2.ellipse("fill", 120, 98, 60, 10)
    local pic = s.pic
    if pic and pic.image then
      local scale = 1
      local bounce = s.anim.bounce or 0
      local sx = 1 + (s.anim.squash or 0)
      local sy = 1 - (s.anim.squash or 0)
      G2.setColor(1, 1, 1, 1)
      drawPixel(pic.image, 120, 100 - bounce, 0, scale * sx, scale * sy, (pic.w or 64) / 2, (pic.h or 64))
    end
    -- the name and the meters from the playfield's top left
    G2.push()
    G2.translate(e.x, e.y)
    G2.setColor(1, 1, 1, 0.85)
    G2.rectangle("fill", 4, 4, math.max(232, e.w - 8), 16, 3, 3)
    drawText(s.name, 8, 6, { maxWidth = 224 })
    drawMeters(G2, s)
    G2.pop()
    local hint = "B: DONE"
    if s.mode == "home" then hint = "A: PLAY   B: CLOSE"
    elseif s.mode == "game" then hint = (s.game and s.game.hud) or "B: QUIT"
    elseif s.tool == "games" then hint = "Pick a game.  B: BACK"
    elseif s.fromHome then hint = "B: BACK" end
    local msg = s.message or hint
    -- the words at the playfield's foot, centred across it
    G2.push()
    G2.translate(e.x + (e.w - 240) / 2, e.y + e.h - 160)
    if host.Chrome and host.Chrome.stdFrame then
      pcall(host.Chrome.stdFrame, 2, 16, 26, 3)
    else
      G2.setColor(1, 1, 1, 0.9)
      G2.rectangle("fill", 12, 124, 216, 30, 3, 3)
    end
    drawBoxText(msg)
    G2.pop()
    G2.pop()
  end

  -- ------- lifecycle

  -- every Gen 3 front pic is 64x64, so the sprite size says nothing; until a
  -- species size table exists everyone takes three bites
  local function sizeClassOf(pic)
    local h = pic and pic.h or 64
    if h < 48 then return "small" end
    return "medium"
  end

  -- the per-Pokemon part of a session; switching swaps these in place
  local function monFields(mon)
    local pic = host.frontPic(mon)
    return {
      mon = mon, key = host.monKey(mon),
      national = host.national and host.national(mon) or host.speciesOf(mon),
      name = host.displayName(mon),
      pic = pic,
      icon = host.icon and host.icon(mon) or nil,
      sizeClass = sizeClassOf(pic),
      status = host.statusOf(mon),
      meters = Store.meters(host.monKey(mon)),
      petAccum = 0,
    }
  end

  local function appFor(mode)
    if mode == "home" then return "home" end
    if mode == "decorate" then return "decorate" end
    return "play"
  end

  -- As Super Training's home: the room lives on the bottom screen alone,
  -- the game keeps the top screen and the player walks about; the top-screen layer (which
  -- pauses the field) is up for PLAY, DECORATE and the minigames only. G.frame ticks the
  -- session while no layer is up.
  local LAYER_MODES = { play = true, decorate = true, game = true }
  local function syncLayer(s)
    local want = s and LAYER_MODES[s.mode] == true
    if want and not s.layered then
      local ok, err = host.pushLayer(Layer)
      if ok then s.layered = true else mod.log:warn("could not push the amie layer: %s", tostring(err)) end
    elseif s and not want and s.layered then
      host.popLayer()
      s.layered = false
    end
  end
  G.syncLayer = function() syncLayer(G.session) end

  function G.frame(dt)
    local s = G.session
    if s and not s.layered then G.tick(dt) end
  end

  -- a battle takes the bottom screen back; the room waits under it
  function G.inBattle()
    return host.battleActive ~= nil and host.battleActive() == true
  end

  -- opts = { home, source }
  function G.start(mon, opts)
    opts = opts or {}
    if not mon or G.session then return false end
    if G.busy and G.busy() then return false, "busy" end
    mon = host.resolve(mon) or mon
    local s = monFields(mon)
    s.mode = opts.home and "home" or "play"
    s.fromHome = opts.home and true or false
    s.puffs = Store.puffs()
    s.tool = nil
    s.log = {}
    s.anim = { bounce = 0, squash = 0, timer = 0 }
    s.source = opts.source or "battle"
    s.startedAt = host.now()
    s.lastCry = 0
    G.session = s
    G.previousApp = Apps:active() and Apps:active().id or nil
    syncLayer(s)
    Apps:setActive(appFor(s.mode), mod.game)
    onChange()
    if s.mode == "home" then G.enterHome(true) else G.enterPlay() end
    return true
  end

  -- DECORATE: the drawer over the room
  function G.enterDecorate()
    local s = G.session
    if not s or not G.Decor then return false end
    s.mode = "decorate"
    s.tool = nil
    syncLayer(s)
    Apps:setActive("decorate", mod.game)
    onChange()
    return true
  end

  -- the room: the Pokemon wanders until it is tapped
  function G.enterHome(first)
    local s = G.session
    if not s then return end
    if G.Decor then
      local decor = G.Decor.ensure(Store.decor())
      G.Decor.ensureRoom(Store.room(), decor)
      Store.saveDecor(); Store.saveRoom()
    end
    if first and G.Visitors then G.Visitors.reset() end
    s.mode = "home"
    s.tool = nil
    s.feeding = nil
    syncLayer(s)
    Apps:setActive("home", mod.game)
    if first then
      host.playCry(s.mon)
      say(("%s is here!"):format(s.name), 2)
    end
    onChange()
  end

  -- play's BACK: the games panel folds first, then back to the room it came from, or close
  function G.back()
    local s = G.session
    if not s then return end
    -- an open picker or puff strip folds first
    if s.mode == "play" and (s.tool == "games" or s.tool == "beans") then
      G.se(s.tool == "beans" and "close_puffs" or "back", "SE_SELECT")
      s.tool = nil
      onChange()
      return
    end
    if s.mode == "play" and s.fromHome then
      G.se("back", "SE_SELECT")
      persist()
      G.enterHome(false)
    else
      G.finish()
    end
  end

  -- PLAY left alone: the Pokemon has dozed off; back to the room (opened from the START menu's
  -- PLAY too)
  function G.idleToRoom()
    local s = G.session
    if not (s and s.mode == "play") then return end
    s.tool = nil
    persist()
    G.enterHome(false)
  end

  -- GAMES: the picker, on the play screen itself (its tray button; three badges and the four
  -- ranks under the chosen one). Needs three healthy party members.
  function G.showGames()
    local s = G.session
    if not s then return false end
    if not G.Games then return false, "no games" end
    local ok, why = G.Games.canPlay(s.key)
    if not ok then
      say(G.tx("needThree"), 3)
      return false, why
    end
    if s.mode ~= "play" then G.enterPlay() end
    s.tool = "games"
    s.feeding = nil
    say(G.tx("whichGame", nil, "Pick a game."), 2)
    onChange()
    return true
  end

  -- the game's own effect for `event` (data/amie_sounds.lua, G.sounds; a list plays one of
  -- its effects at random), else the Emerald stand-in. The stand-in's haptic is felt either
  -- way (src/haptics.lua maps the stand-in's name). Returns the effect's handle (stop() for a
  -- loop) when the game's played.
  function G.se(event, standIn, opts)
    local id = G.sounds and G.sounds[event]
    -- false: the game plays nothing there (a capture showed it); with the art extracted, silence
    if id == false and mod.sfx and mod.sfx.has and mod.sfx.has("se/kw_select") then return nil end
    if type(id) == "table" then id = id[math.random(#id)] end
    local h = id and mod.sfx and mod.sfx.play(id, opts) or nil
    if h then
      if standIn and mod.haptics then pcall(mod.haptics.onSound, standIn) end
      return h
    end
    if standIn then host.playSe(standIn) end
    return nil
  end

  -- a tap's click, for the apps that have no host of their own
  function G.click() G.se("select", "SE_SELECT") end

  -- a game starts: the app with that id takes the surface
  function G.startGame(id, diff)
    local s = G.session
    if not (s and G.Games) then return false end
    if not G.Games.isUnlocked(id, diff) then return false, "locked" end
    local list, why = G.Games.participants(s.key)
    if not list then say(G.tx("needThree"), 3); return false, why end
    s.mode = "game"
    s.game = { id = id, diff = diff, participants = list, hud = nil }
    local app = Apps:get("game_" .. id)
    if not app then s.mode = "play"; return false, "no app" end
    syncLayer(s)
    G.gameApp = app
    Apps:setActive("game_" .. id, mod.game)
    if app.start then app:start(s.game) end
    G.se("start_game", "SE_SELECT")
    onChange()
    return true
  end

  -- a game ended: record it; with `stay` the game app keeps the screen to
  -- show the result until leaveGame, otherwise the picker returns at once
  function G.endGame(value, quit, stay)
    local s = G.session
    if not (s and s.game) then return nil end
    local result = nil
    if not quit then
      result = G.Games.finish(s.game.id, s.game.diff, value, s.game.participants, G.rng)
      s.lastResult = result
      s.game.result = result
      G.se("results", "SE_SUCCESS")
    end
    if stay and not quit then
      onChange()
      return result
    end
    return G.leaveGame(), result
  end

  -- back to the play screen with the picker still open; the result stays as a line.
  -- opts.toPetting: the picker closed, back to petting (a game's Quit, as the game does)
  function G.leaveGame(opts)
    local s = G.session
    if not s then return false end
    s.game = nil
    G.gameApp = nil
    s.mode = "play"
    -- back in PLAY from a minigame: +10 enjoyment, as opening it
    Rules.openPlay(s.meters)
    if opts and opts.toPetting then s.tool = nil else s.tool = "games" end
    syncLayer(s)
    Apps:setActive("play", mod.game)
    local r = s.lastResult
    if r and G.Games then
      say(("%s %s: %s  +%d puffs"):format(G.Games.name(r.game), G.Games.diffLabel(r.diff), r.title, #r.puffs), 4)
    end
    onChange()
    return true
  end

  -- SWITCH: another party member takes the room
  function G.switchTo(mon)
    local s = G.session
    if not (s and mon) then return false end
    mon = host.resolve(mon) or mon
    if host.isEgg and host.isEgg(mon) then return false end
    persist()
    local f = monFields(mon)
    for k, v in pairs(f) do s[k] = v end
    s.tool = nil
    s.feeding = nil
    G.setActiveKey(s.key)
    host.playCry(mon)
    say(("%s is here!"):format(s.name), 2)
    onChange()
    return true
  end

  -- play opened: +10 enjoyment, a cry, the right message
  function G.enterPlay()
    local s = G.session
    if not s then return end
    s.mode = "play"
    syncLayer(s)
    Apps:setActive("play", mod.game)
    Rules.openPlay(s.meters)
    host.playCry(s.mon)
    say(("%s is here!"):format(s.name), 2)
    onChange()
  end

  local function close()
    local s = G.session
    if not s then return end
    persist()
    if s.layered then host.popLayer(); s.layered = false end
    G.session = nil
    if G.previousApp and G.previousApp ~= "play" and G.previousApp ~= "home" and Apps:get(G.previousApp) then
      Apps:setActive(G.previousApp, mod.game)
    end
    G.previousApp = nil
    onChange()
  end

  function G.finish()
    if not G.session then return end
    G.se("back", "SE_SELECT")
    close()
  end

  -- ------- actions the surface app calls

  local function inPlay() local s = G.session; return s and s.mode == "play" and s or nil end

  function G.selectTool(tool)
    local s = inPlay()
    if not s then return end
    local was = s.tool
    if s.tool == tool then s.tool = nil else s.tool = tool end
    local ev = (s.tool == "beans" and "open_puffs") or (s.tool == "games" and "open_games")
      or (was == "beans" and "close_puffs") or "back"
    G.se(ev, "SE_SELECT")
    onChange()
  end

  function G.setTool(tool)
    local s = inPlay()
    if not s then return end
    s.tool = tool
    onChange()
  end

  local function bump(s, squash, bounce)
    s.anim.squash = squash or 0.12
    s.anim.bounce = bounce or 6
    s.anim.timer = 0.35
  end
  G.bump = function(squash, bounce) local s = G.session; if s then bump(s, squash, bounce) end end

  -- Petting as the game's script counts it (data PET): while a finger is on the body, the time
  -- it moves (more than MOVE_PX a tick) on the current spot class and anywhere on the body. A
  -- reward once either is long enough (a spot class needs more for each reward in a row on
  -- it); the petting then ends until the finger is lifted (G.petLift). `cls` is the spot class
  -- (the zone for a normal spot, else the spot kind). -> { hearts, spot } on a reward, else nil
  function G.petTouch(dt, moving, spot, cls)
    local s = inPlay()
    if not s then return nil end
    if not Rules.canPet(s.national) then return nil end
    local P, tk = Rules.PET, Rules.ticks
    local t = s.petT
    if not t then t = { clsT = 0, anyT = 0, pendT = 0 }; s.petT = t end
    -- another class takes over once it has lasted SWITCH_TICKS
    if cls ~= t.cls then
      if t.pend ~= cls then t.pend, t.pendT = cls, 0 end
      t.pendT = t.pendT + dt
      if t.cls == nil or t.pendT >= tk(P.SWITCH_TICKS) - 1e-6 then t.cls, t.clsT, t.pend = cls, 0, nil end
    else
      t.pend = nil
    end
    if not moving then return nil end
    if t.cls == cls then t.clsT = t.clsT + dt end
    if spot ~= "disfavored" then t.anyT = t.anyT + dt end
    local need
    if spot == "disfavored" then
      need = P.DISLIKED_TICKS
    else
      local rep = s.petRepeat
      need = P.SPOT_TICKS + P.REPEAT_TICKS * ((rep and rep.cls == cls) and rep.n or 0)
    end
    -- (a hair under, for the frames' sums of 1/30 s)
    local onSpot = t.cls == cls and t.clsT >= tk(need) - 1e-6
    local onBody = spot ~= "disfavored" and t.anyT >= tk(P.BODY_TICKS) - 1e-6
    if not (onSpot or onBody) then return nil end
    s.petT = nil
    -- the body-wide path pays as a normal spot
    local paid = onSpot and spot or "normal"
    if paid ~= "disfavored" then
      local rep = s.petRepeat
      if rep and rep.cls == cls then rep.n = rep.n + 1 else s.petRepeat = { cls = cls, n = 1 } end
    end
    local hearts, kind = G.petEvent(paid)
    return { hearts = hearts, spot = kind }
  end

  -- a fresh visit to PLAY: the script starts again (the reward streak, the jolt count)
  function G.resetPetting()
    local s = G.session
    if s then s.petT, s.effectT, s.petRepeat, s.effectJolts = nil, nil, nil, 0 end
  end

  -- the finger lifted (or petting ended): the counts start again next touch
  function G.petLift()
    local s = G.session
    if s then s.petT, s.effectT = nil, nil end
  end

  -- a finger on an interrupting spot (burning, paralyzing, cutting, freezing): a jolt at once and
  -- every JOLT_TICKS while it stays; the EFFECT_JOLTS-th of the visit makes the Pokemon recoil.
  -- -> "jolt" | "recoil" | nil
  function G.petEffect(dt, kind)
    local s = inPlay()
    if not s then return nil end
    local P = Rules.PET
    if s.petT then s.petT.clsT, s.petT.anyT = 0, 0 end
    s.effectT = (s.effectT or 0) - dt
    if s.effectT > 1e-6 then return nil end
    s.effectT = Rules.ticks(P.JOLT_TICKS[kind] or 30)
    s.effectJolts = (s.effectJolts or 0) + 1
    G.se((kind == "burning" and "burn") or (kind == "paralyzing" and "shock") or "hurt", "SE_NOT_EFFECTIVE")
    if s.effectJolts >= P.EFFECT_JOLTS then
      s.effectJolts = 0
      s.effectT = nil
      return "recoil"
    end
    return "jolt"
  end

  -- one petting reward: affection by spot and enjoyment band (Rules.pet)
  function G.petEvent(spot)
    local s = inPlay()
    if not s then return 0, spot, false end
    local before = s.meters.affection
    local hearts, spent = Rules.pet(s.meters, spot)
    affectionChanged(s, before)
    onChange()
    local now = host.now()
    if hearts > 0 and now - s.lastCry > 4 then
      s.lastCry = now
      host.playCry(s.mon)
      bump(s, 0.08, 4)
    end
    if spot == "disfavored" then
      if (s.annoyedAt or 0) + 2 < now then
        s.annoyedAt = now
        say(("%s doesn't like that."):format(s.name), 1.5)
      end
    elseif hearts > 0 and before > 0 and spot == "favored" and (s.happyAt or 0) + 3 < now then
      s.happyAt = now
      say(("%s loves that!"):format(s.name), 1.5)
    elseif hearts == 0 and spent == 0 and (s.boredAt or 0) + 4 < now then
      s.boredAt = now
      say(("%s has had enough petting for now."):format(s.name), 2)
    end
    return hearts, spot, true
  end

  -- a rapid double tap on the same place
  function G.hit()
    local s = inPlay()
    if not s then return false end
    Rules.hit(s.meters)
    bump(s, -0.1, 0)
    G.se("hit", "SE_NOT_EFFECTIVE")
    say(("%s got hit!"):format(s.name), 1.5)
    onChange()
    return true
  end

  function G.canHighFive()
    local s = inPlay()
    return s ~= nil and Rules.canHighFive(s.meters)
  end

  function G.highFive()
    local s = inPlay()
    if not (s and Rules.canHighFive(s.meters)) then return false end
    Rules.highFive(s.meters)
    bump(s, 0.1, 10)
    G.se("high_five", "SE_SUCCESS")
    host.playCry(s.mon)
    say(("%s gave you a high five!"):format(s.name), 2)
    onChange()
    return true
  end

  -- ------- feeding: a puff held on the Pokemon is eaten bite by bite

  -- the message box is one line; a long nickname plus a long variety name
  -- is cut down to the variety alone
  local function puffMessage(s, kind)
    local msg = ("%s ate the %s!"):format(s.name, Rules.puffName(kind))
    if host.Font and host.Font.measure then
      local ok, w = pcall(host.Font.measure, msg)
      if ok and tonumber(w) and w > 204 then msg = ("Yum! A %s!"):format(Rules.puffName(kind)) end
    end
    return msg
  end

  -- can this puff be offered right now? false, "full" | "cannot" | "none"
  function G.canFeed(kind)
    local s = inPlay()
    if not s then return false, "closed" end
    local ok, why = Rules.canFeed(s.meters, s.national)
    if not ok then return false, why end
    if Rules.jarCount(s.puffs, kind) <= 0 then return false, "none" end
    return true
  end

  -- the puff touches the Pokemon: take it out of the jar and start biting
  function G.feedStart(kind)
    local s = inPlay()
    if not s or s.feeding then return false end
    local ok, why = G.canFeed(kind)
    if not ok then
      if why == "full" then say(("%s is full."):format(s.name))
      elseif why == "cannot" then say(("%s can't eat Poke Puffs."):format(s.name))
      else say("No Poke Puffs left.") end
      return false, why
    end
    Rules.jarTake(s.puffs, kind)
    local bites = Rules.bitesFor(s.national)
    s.feeding = { kind = kind, bites = bites, taken = 0, timer = 0, pace = Rules.bitePace(s.meters, bites) }
    onChange()
    return true
  end

  -- a bite's time, and with the pause a nearly full Pokemon takes after each
  local BITE_QUICK, BITE_SLOW = 0.45, 1.1

  -- called every frame while the puff is held on the Pokemon
  function G.feedHold(dt)
    local s = inPlay()
    local f = s and s.feeding
    if not f then return nil end
    f.timer = f.timer + dt
    local slow = Rules.bitePace(s.meters, f.bites) == "slow"
    if f.timer < (slow and BITE_SLOW or BITE_QUICK) then return nil end
    f.timer = 0
    f.taken = f.taken + 1
    s.anim.squash = 0.1
    s.anim.timer = 0.2
    G.se("bite", "SE_SELECT")
    if f.taken >= f.bites then
      local before = s.meters.affection
      local hearts = Rules.finishPuff(s.meters, f.kind, f.taken - 1, f.bites)
      affectionChanged(s, before)
      s.feeding = nil
      bump(s, 0.12, 4)
      say(puffMessage(s, f.kind))
      onChange()
      return "done", hearts
    end
    Rules.bite(s.meters, f.bites)
    onChange()
    return "bite"
  end

  -- the puff was pulled away before the last bite: fullness only
  function G.feedDrop()
    local s = inPlay()
    local f = s and s.feeding
    if not f then return false end
    s.feeding = nil
    if f.taken > 0 then say(("%s wanted the rest of that..."):format(s.name), 2)
    else say(("%s looks confused."):format(s.name), 1.5) end
    onChange()
    return true
  end

  -- the puff taken back before the first bite (dragged back to the puff button): into the jar
  -- again; false once it has been bitten
  function G.feedCancel()
    local s = inPlay()
    local f = s and s.feeding
    if not f or f.taken > 0 then return false end
    s.feeding = nil
    Rules.jarAdd(s.puffs, f.kind)
    onChange()
    return true
  end

  -- a puff let go of before it was offered: it falls away and is lost
  function G.dropPuff(kind)
    local s = inPlay()
    if not (s and kind) then return false end
    local ok = Rules.jarTake(s.puffs, kind)
    if ok then onChange() end
    return ok
  end

  -- one call for tests and simple callers: the whole puff at once
  function G.feedPuff(kind)
    local s = inPlay()
    if not s then return false end
    if not kind then
      local owned = Rules.ownedPuffs(s.puffs)
      kind = owned[1] and owned[1].id
      if not kind then say("No Poke Puffs left."); return false, "none" end
    end
    local okStart, why = G.feedStart(kind)
    if not okStart then return false, why end
    local f = s.feeding
    local before = s.meters.affection
    local hearts = Rules.finishPuff(s.meters, f.kind, 0, f.bites)
    affectionChanged(s, before)
    s.feeding = nil
    s.eating = 0.9
    bump(s, 0.12, 2)
    say(puffMessage(s, kind))
    onChange()
    return true, hearts
  end

  -- ------- rules that run outside a session

  local function metersFor(key)
    if not key then return nil end
    return Store.meters(key)
  end

  function G.onBattleStarted()
    local key = G.activeKey()
    local m = metersFor(key)
    if not m then return false end
    Rules.battleEntered(m)
    Store.saveMons()
    return true
  end

  function G.onStep()
    local meta = Store.meta()
    meta.steps = (meta.steps or 0) + 1
    if meta.steps % N.STEPS.EVERY ~= 0 then return false end
    -- after the Hall of Fame, the next visitor groups bring Supreme Honor Poke Puffs, one each
    -- (the game sets a counter of 3 in its Hall of Fame routine, main 0x3d491c)
    if not meta.honorGiven and host.gameCleared and host.gameCleared() then
      meta.honorGiven = true
      meta.honorLeft = 3
    end
    Store.saveMeta()
    local m = metersFor(G.activeKey())
    if not m then return false end
    Rules.steps(m, 1)
    Store.saveMons()
    return true
  end

  -- ------- per-frame

  function G.tick(dt)
    local s = G.session
    if not s then return end
    if s.anim.timer > 0 then
      s.anim.timer = s.anim.timer - dt
      local f = math.max(0, s.anim.timer / 0.35)
      s.anim.squash = s.anim.squash * f
      s.anim.bounce = s.anim.bounce * f
      onChange()
    end
    if s.eating and s.eating > 0 then
      s.eating = s.eating - dt
      s.anim.squash = 0.08 * math.sin(s.eating * 25)
      if s.eating <= 0 then s.eating = nil; s.anim.squash = 0 end
      onChange()
    end
    if s.message and s.messageUntil and host.now() > s.messageUntil then
      s.message = nil
      onChange()
    end
  end

  -- ------- the battle hook: nothing opens and nothing drops. Poke Puffs come from the Amie
  -- minigames only, as in the game

  function G.onBattleEnded(ev)
    local result = ev and ev.result
    local st = ev and ev.battle or {}
    mod.log:info("amie: battle ended (result %s, wild %s, over %s)", tostring(result),
      tostring(st.wild), tostring(st.over))
    return false, "no puffs from battles"
  end

  -- the Pokemon the room shows: the remembered active one when it is still
  -- in the party, else the lead
  function G.activeMon()
    local key = Store.meta().activeKey
    if key and host.party then
      for _, p in ipairs(host.party()) do
        if host.monKey(p) == key and not (host.isEgg and host.isEgg(p)) then return p end
      end
    end
    return host.leadMon()
  end

  -- open directly (START menu, other mods): the room
  function G.open(mon)
    if not host.available() then return false, "no host" end
    mon = mon or G.activeMon()
    if not mon then return false, "no mon" end
    return G.start(mon, { home = true, source = "menu" })
  end

  -- straight into play (other mods, tests)
  function G.openPlay(mon)
    if not host.available() then return false, "no host" end
    mon = mon or G.activeMon()
    if not mon then return false, "no mon" end
    return G.start(mon, { home = false, source = "menu" })
  end

  function G.state()
    local s = G.session
    if not s then return nil end
    return { phase = s.mode, mode = s.mode, key = s.key, name = s.name, tool = s.tool, national = s.national,
      status = s.status, meters = s.meters, puffs = s.puffs,
      message = s.message, source = s.source, feeding = s.feeding, sizeClass = s.sizeClass,
      fromHome = s.fromHome, icon = s.icon, game = s.game, lastResult = s.lastResult }
  end

  return G
end
