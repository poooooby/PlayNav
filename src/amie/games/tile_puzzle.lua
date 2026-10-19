-- TILE PUZZLE, played from the game's own screens (a/0/1/8: easy / normal / hard_bound and
-- effect for the tiles' marks and the star burst, bg_down on the touch screen, bg_up on the
-- top screen; Wooble's capture 2026-10-19). A picture of the three Pokemon is cut into tiles
-- and every tile is swapped once; tap two tiles to swap them. Easy 5x4, Normal 6x5, Hard 8x6,
-- rated by time (the clock counts up and never runs out); Unlimited chains puzzles against a
-- 30-second clock that correct tiles and finished puzzles top up. Rules: Bulbapedia "Tile
-- Puzzle".
--
-- Flow, as the capture: the whole picture with the rule window and Begin -> the tiles fly to
-- their shuffled places -> START! -> play: a tile out of place has blue corners and a dark
-- gap (frame.bclim; the gap shows at its edges' middles), the chosen one red corners
-- (cursol.bclim), a second tap swaps the two (both lift with a black edge over orange holes);
-- a tile that lands home bursts into stars, loses its corners and is locked -> FINISHED! ->
-- the RESULTS card on top (the three best times, NEW, HIGH SCORE) and the smoke and Poke Puff
-- medallions below -> View Picture / Play Again / Quit.
--
-- The picture: the game renders a live 3D stage there (CGFX, entries 3-8). Ours is 2D from the
-- game's art (Wooble, 2026-10-19): the sky strip, the sea, clouds and trees of the soaring
-- scenery (day, sunset and night sets), the stage's own photo frame, and the participants'
-- sprites. Its light cycles day -> sunset -> night -> dawn while the round runs (the capture:
-- day, then sunset ~20 s in, night by ~23 s; Wooble: "just part of the scene"). The Pokemon's
-- motion ramps with the puzzle's difficulty (Wooble): Easy idle bounces and sways in place,
-- Normal moves them about the scene, Hard also pans the camera.

return function(mod, Pointer, G, Games, Rules, host)

  -- pixel art (GBA sprites) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "game_tile", title = "TILES", live = true }

  function app:wantsSurface()
    local s = G.session
    return s ~= nil and s.mode == "game" and s.game and s.game.id == "tile" or false
  end

  local L = 256 / 320
  local BLEED = 14
  -- the clips' rate (bg_down's START! is 41 frames, ~1.4 s on the capture)
  local FPS = 30
  -- the screen's shape: the board is the game's 320x240; a taller screen (Kanto Gear's) has
  -- D more, the board centred in it (D / 2 above and below), the top window kept at the top
  local LH, D = 240, 0
  local function bleed() return app.bleed or BLEED end
  local function setShape(h)
    local lh = math.max(240, ((h or 178) + bleed()) / L)
    if lh == LH then return end
    LH, D = lh, lh - 240
    app.shapeDirty = true
  end
  app.setShape = setShape

  -- the grids, from easy / normal / hard_bound: the tiles' pitch, the first one's top left,
  -- and the corner marks' size (each pane is a 58 / 46 / 36 square on a 60 / 48 / 38 pitch)
  local GRID = {
    easy = { cols = 5, rows = 4, pitch = 60, x = 10, y = 0, mark = 58 },
    normal = { cols = 6, rows = 5, pitch = 48, x = 16, y = 0, mark = 46 },
    hard = { cols = 8, rows = 6, pitch = 38, x = 8, y = 6, mark = 36 },
  }
  local ORANGE = { 242 / 255, 183 / 255, 53 / 255 }   -- the board under the tiles (the capture)
  local GAP = { 0, 5 / 255, 15 / 255 }                -- between tiles out of place
  local SWAP_S = 0.28          -- a swap's flight
  local SHUFFLE_S = 1.1        -- the opening shuffle: the last tile lands by then
  local BURST_S = 0.7          -- the star burst (effect_eff_star: 15 frames out, 21 in all)
  -- the five stars' ends from the tile's middle (effect_eff_star_00, panes 3d 3g 3i 3k 3m; the
  -- layout's y is up)
  local BURST = { { 0, 50.5 }, { -42, 28 }, { 31, -29.5 }, { -39.5, -25 }, { 38, 28.5 } }
  -- the scene's day: seconds from the round's start (day, sunset, night, dawn, round again)
  local DAY = { day = 18, toDusk = 2, dusk = 2, toNight = 2, night = 36, toDawn = 3, dawn = 1, toDay = 3 }

  local st = nil
  local players = {}

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  local OPEN = {
    easy = { "tile_bound", "easy_bound.bclyt" }, normal = { "tile_bound", "normal_bound.bclyt" },
    hard = { "tile_bound", "hard_bound.bclyt" },
    down = { "tile_down", "bg_down.bclyt" }, up = { "tile_up", "bg_up.bclyt", { "tile_up", "berry_lang" } },
  }
  local function screen(name)
    local p = players[name]
    if p == nil then
      local S, o = mod.lyt, OPEN[name]
      p = S and S.open(o[1], o[2], o[3] or { o[1] }) or false
      players[name] = p
    end
    return p or nil
  end

  local function roll(a, b)
    local g = st and st.rng
    if g then return g:random(a, b) end
    return math.random(a, b)
  end
  local function rand()
    local g = st and st.rng
    if g then return g:random() end
    return math.random()
  end

  -- ------- the puzzle

  -- a perfect matching of swaps: every tile moves exactly once
  local function shuffle(n)
    local order = {}
    for i = 1, n do order[i] = i end
    for i = n, 2, -1 do
      local j = roll(1, i)
      order[i], order[j] = order[j], order[i]
    end
    local tiles = {}
    for i = 1, n do tiles[i] = i end
    for i = 1, n - 1, 2 do
      local a, b = order[i], order[i + 1]
      tiles[a], tiles[b] = tiles[b], tiles[a]
    end
    return tiles
  end

  local function newPuzzle(diff)
    local g = GRID[diff] or GRID.easy
    local n = g.cols * g.rows
    local tiles = shuffle(n)
    local correct = 0
    for i = 1, n do if tiles[i] == i then correct = correct + 1 end end
    return { diff = diff, g = g, n = n, tiles = tiles, sel = nil, correct = correct,
      -- the tiles flying now: [pos] = { from = pos, t, dur, delay }
      moving = {}, bursts = {} }
  end

  local function solved(pz)
    for i = 1, pz.n do if pz.tiles[i] ~= i then return false end end
    return true
  end

  local function cellXY(g, pos)
    local c, r = (pos - 1) % g.cols, math.floor((pos - 1) / g.cols)
    return g.x + c * g.pitch, g.y + r * g.pitch
  end

  -- the motion of the puzzle on now: 0 bounce in place, 1 about the scene, 2 and the camera
  local MOTION = { easy = 0, normal = 1, hard = 2 }

  -- ------- the Pokemon in the picture

  local function startMons(participants)
    local mons = {}
    for i = 1, 3 do
      local mon = participants and participants[i] and participants[i].mon
      local home = 0.24 + (i - 1) * 0.26
      mons[i] = { pic = mon and host.frontPic and host.frontPic(mon) or nil, home = home, x = home,
        depth = 0.45 + (i % 2) * 0.12, tx = home, td = 0.5, phase = i * 1.7, face = (i == 3) and -1 or 1,
        hop = nil, wait = 0.5 + i * 0.7 }
    end
    return mons
  end

  local function stepMons(dt, level)
    for i, m in ipairs(st.mons) do
      m.phase = m.phase + dt * (2.2 + i * 0.3)
      if level >= 1 then
        m.wait = m.wait - dt
        if m.wait <= 0 then
          -- a new spot: near home on Normal, anywhere on Hard (and nearer or farther)
          local span = level >= 2 and 0.42 or 0.16
          m.tx = math.max(0.1, math.min(0.9, m.home + (rand() * 2 - 1) * span))
          m.td = level >= 2 and (0.25 + rand() * 0.6) or m.depth
          m.wait = (level >= 2 and 1.6 or 2.4) + rand() * 2.5
          if rand() < 0.35 then m.hop = 0 end
        end
        local speed = (level >= 2 and 0.12 or 0.07) * dt
        local dx = m.tx - m.x
        if math.abs(dx) > 0.002 then
          m.face = dx > 0 and 1 or -1
          m.x = m.x + math.max(-speed, math.min(speed, dx))
        end
        local dd = m.td - m.depth
        m.depth = m.depth + math.max(-speed, math.min(speed, dd))
      end
      if m.hop then m.hop = m.hop + dt; if m.hop > 0.45 then m.hop = nil end end
    end
  end

  -- ------- the scene's light: weights of the day, sunset and night sets at time t

  local function lightAt(t)
    local seq = { { "day", DAY.day }, { "toDusk", DAY.toDusk }, { "dusk", DAY.dusk }, { "toNight", DAY.toNight },
      { "night", DAY.night }, { "toDawn", DAY.toDawn }, { "dawn", DAY.dawn }, { "toDay", DAY.toDay } }
    local total = 0
    for _, s in ipairs(seq) do total = total + s[2] end
    t = t % total
    for _, s in ipairs(seq) do
      if t < s[2] then
        local f = t / s[2]
        local k = s[1]
        if k == "day" then return 1, 0, 0
        elseif k == "toDusk" then return 1 - f, f, 0
        elseif k == "dusk" or k == "dawn" then return 0, 1, 0
        elseif k == "toNight" then return 0, 1 - f, f
        elseif k == "night" then return 0, 0, 1
        elseif k == "toDawn" then return 0, f, 1 - f
        else return f, 1 - f, 0 end
      end
      t = t - s[2]
    end
    return 1, 0, 0
  end
  app.lightAt = lightAt

  -- ------- the end

  local function setPhase(p) st.phase, st.pt = p, 0 end

  -- START! / NEXT! / FINISHED! / TIME'S UP!: the window 8v and its text 99, which the clips
  -- grow (1.5 -> 1.8); every banner clip carries the same tracks, the game sets the words.
  -- (4l / 4v and 4j / 95 / 97 stay hidden: the capture's banner is the 200 x 50 window.)
  local function banner(text)
    local Dn = st and st.art and screen("down")
    if not Dn then return end
    Dn:set("8v", "visible", text ~= nil)
    Dn:set("99", "visible", text ~= nil)
    if text then
      Dn:setText("99", text, { align = "center", valign = "center" })
      -- anm_start for every banner: anm_next / anm_timeup left the words out (their 99 tracks
      -- keep it unseen in our player); START!'s shows the window and grows the words
      Dn:play("anm_start")
    end
  end

  local function finish(value)
    st.result = G.endGame(value, false, true)
    st.sel = nil
    setPhase("finished")
    -- a timed puzzle ends on its last tile's stars, no banner (the capture); Unlimited's clock
    -- running out says TIME'S UP!
    if st.diff == "unlimited" then banner(Games.line("tile", "timesUp", nil, "TIME'S UP!")) end
    host.playSe("SE_SUCCESS")
  end

  local PUFF_TIER = { basic = 1, frosted = 2, fancy = 3, deluxe = 4, supreme = 5 }
  local function layMedals()
    local Dn = screen("down")
    if not Dn then return end
    local u = Dn.L.byName["u"]
    if not u then return end
    local panes = {}
    for _, c in ipairs(u.children) do panes[#panes + 1] = c end
    for _, c in ipairs(panes) do Dn:set(c.name, "visible", false) end
    Dn:set("u", "visible", true)
    Dn:set("0", "visible", true)
    local puffs = (st.result and st.result.puffs) or {}
    local n = math.min(#puffs, 12)
    local perRow = math.min(6, n)
    for j = 1, n do
      local pane = panes[j]
      local child = pane and pane.children[1]
      if pane and child then
        local row = math.floor((j - 1) / 6)
        local col = (j - 1) % 6
        local inRow = (row == 0) and perRow or (n - 6)
        -- the capture: a row of medallions over the middle, ~56 apart, at y ~75
        local x = 160 + (col - (inRow - 1) / 2) * 56
        local y = 72 + row * 58
        Dn:set(pane.name, "visible", true)
        Dn:set(child.name, "visible", true)
        -- (its parents 0 and u sit at the layout's middle, so its translation is its place)
        Dn:set(pane.name, "tx", x - 160)
        Dn:set(pane.name, "ty", 120 - y)
        local tier = PUFF_TIER[Rules.puffTier and Rules.puffTier(puffs[j]) or "basic"] or 1
        Dn:setImage(pane.name, Dn:image(("wappen_%02d.bclim"):format(tier)))
        local img = art(puffs[j])
        if img then Dn:setImage(child.name, img) end
      end
    end
  end

  local function topWindow(text)
    local Dn = screen("down")
    if not Dn then return end
    Dn:setText("9m", text, { align = "center", valign = "center" })
    Dn:play("window_open")
  end

  -- ------- start / quit

  local function beginPuzzle(diff)
    st.pz = newPuzzle(diff)
    st.pzDiff = diff
    -- the shuffle: every tile flies from its home to its new place, one after another
    for pos = 1, st.pz.n do
      local src = st.pz.tiles[pos]
      if src ~= pos then
        st.pz.moving[pos] = { from = src, t = 0, dur = 0.42, delay = rand() * (SHUFFLE_S - 0.42) }
      end
    end
  end

  function app:start(game)
    st = { diff = game.diff, participants = game.participants, phase = "intro", t = 0, pt = 0, sceneT = 0,
      elapsed = 0, timer = 30, puzzles = 0, score = 0, result = nil,
      rotation = { "easy", "normal", "hard" }, rotIndex = 1, placed = 0, done = {} }
    do
      local ok, g = pcall(function()
        local t = love.timer.getTime()
        return love.math.newRandomGenerator(os.time() + math.floor((t - math.floor(t)) * 1e6))
      end)
      st.rng = ok and g or nil
    end
    local firstDiff = (game.diff == "unlimited") and "easy" or game.diff
    st.pz = newPuzzle(firstDiff)
    st.pzDiff = firstDiff
    st.pz.shown = true    -- the intro shows the picture whole
    st.mons = startMons(game.participants)
    st.art = true
    for name in pairs(OPEN) do if not screen(name) then st.art = false end end
    if st.art then
      for name in pairs(OPEN) do
        local P = screen(name)
        P.active, P.over, P.texts, P.images = {}, {}, {}, {}
      end
      local Dn, Up = screen("down"), screen("up")
      -- the touch screen: the rule window and Begin; everything else waits
      for _, n in ipairs({ "4h", "8v", "99", "13", "u", "2a", "4i", "1l", "t", "4j", "95", "97", "2r" }) do Dn:set(n, "visible", false) end
      Dn:setText("5l", Games.line("tile", "tapTiles", nil, "Tap tiles to swap their positions and complete the picture!"),
        { align = "center", valign = "center" })
      Dn:setText("1i", Games.line("tile", "begin", nil, "Begin"), { align = "center", valign = "center" })
      Dn:play("rule_appear")
      Dn:play("startbutton_start")
      Dn:set("5l", "visible", true)
      for _, n in ipairs({ "4l", "4v", "4j", "95", "97" }) do Dn:set(n, "visible", false) end
      banner(nil)
      -- the top screen: How to Play and the time
      Up:set("2c", "visible", false)
      Up:set("7v", "visible", false)
      Up:set("35", "visible", true)
      local unlimited = st.diff == "unlimited"
      Up:set("2u", "visible", true)
      Up:set("2n", "visible", not unlimited)
      Up:set("36", "visible", unlimited)
      Up:setText("2s", Games.line("tile", "howTo", nil, "How to Play"), { align = "center", valign = "center" })
      Up:setText("2o", Games.line("tile", "tapTwo", nil, "Tap two tiles to swap their positions."), { align = "center", valign = "center" })
      Up:setText("2q", Games.line("tile", "pressB", nil, "Press the B Button to quit."), { align = "center", valign = "center" })
      Up:setText("2d", Games.line("tile", "time", nil, "Time:"), { align = "left", valign = "center" })
    end
    game.hud = ("TILE PUZZLE  %s"):format(Games.DIFF_LABEL[game.diff])
  end

  function app:quit()
    if st and (st.phase == "intro" or st.phase == "shuffle" or st.phase == "start" or st.phase == "play") then
      st = nil
      G.endGame(nil, true)
    end
  end

  -- the driver ends a run early: seconds for a timed puzzle, puzzles for Unlimited
  function app.forceEnd(value)
    if st and (st.phase == "intro" or st.phase == "shuffle" or st.phase == "start" or st.phase == "play") then
      if st.diff == "unlimited" then st.puzzles = value or st.puzzles; finish(st.puzzles)
      else st.elapsed = value or st.elapsed; finish(st.elapsed) end
    end
  end

  -- ------- input (board units: the game's 320x240, the board D / 2 down)

  local function toBoard(x, y) return x / L, (y + bleed()) / L - D / 2 end
  local function fromBoard(x, y) return x * L, (y + D / 2) * L - bleed() end

  local function tileAt(x, y)
    local g = st.pz.g
    local c = math.floor((x - g.x) / g.pitch)
    local r = math.floor((y - g.y) / g.pitch)
    if c < 0 or r < 0 or c >= g.cols or r >= g.rows then return nil end
    return r * g.cols + c + 1
  end

  -- the buttons at the end (the capture: View Picture / Play Again / Quit down the middle)
  local BUTTONS = { view = { 160, 152, 126, 26 }, again = { 160, 182, 126, 26 }, quit = { 160, 212, 126, 26 } }
  local BEGIN = "1k"     -- Begin's hit box (bg_down, over 1g)
  local function inButton(b, x, y) return math.abs(x - b[1]) <= b[3] / 2 and math.abs(y - b[2]) <= b[4] / 2 end
  local function inBegin(x, y)
    local Dn = screen("down")
    if Dn then
      local bx, by, bw, bh = Dn:box(BEGIN)
      if bx then return x >= bx and x <= bx + bw and y >= by and y <= by + bh end
    end
    return math.abs(x - 160) <= 55 and math.abs(y - 142) <= 16
  end

  local function burst(pos)
    st.pz.bursts[#st.pz.bursts + 1] = { pos = pos, t = 0 }
  end

  local function swap(a, b)
    local pz = st.pz
    local wasA, wasB = pz.tiles[a] == a, pz.tiles[b] == b
    pz.tiles[a], pz.tiles[b] = pz.tiles[b], pz.tiles[a]
    pz.moving[a] = { from = b, t = 0, dur = SWAP_S, delay = 0 }
    pz.moving[b] = { from = a, t = 0, dur = SWAP_S, delay = 0 }
    local nowA, nowB = pz.tiles[a] == a, pz.tiles[b] == b
    local gained = (nowA and not wasA and 1 or 0) + (nowB and not wasB and 1 or 0)
    pz.correct = pz.correct + gained - ((wasA and not nowA and 1 or 0) + (wasB and not nowB and 1 or 0))
    -- the stars once it lands (update)
    if nowA then pz.moving[a].landed = true end
    if nowB then pz.moving[b].landed = true end
    host.playSe(gained > 0 and "SE_PIN" or "SE_SELECT")
    if st.diff == "unlimited" then
      st.score = math.min(49999, st.score + gained)
      for _ = 1, gained do
        st.placed = st.placed + 1
        if st.placed % 2 == 0 then st.timer = st.timer + 1 end
      end
    end
  end

  local function completePuzzle()
    if st.diff ~= "unlimited" then
      finish(st.elapsed)
      return
    end
    st.puzzles = st.puzzles + 1
    st.timer = st.timer + math.max(5, 30 - st.puzzles)
    st.done[st.pzDiff] = (st.done[st.pzDiff] or 0) + 1
    local bonus = ({ easy = 80, normal = 100, hard = 200 })[st.pzDiff] or 80
    st.score = math.min(49999, st.score + bonus * st.done[st.pzDiff])
    st.rotIndex = st.rotIndex % 3 + 1
    setPhase("next")
    banner(Games.line("tile", "next", nil, "NEXT!"))
    host.playSe("SE_SUCCESS")
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (st and s and s.mode == "game") then return end
    local x, y = toBoard(ev.x, ev.y)
    local tap = ev.phase == "released" and Pointer.isTap(rec, 16, 1.0)
    if st.phase == "intro" then
      if tap and inBegin(x, y) then
        host.playSe("SE_SELECT")
        local Dn = screen("down")
        if Dn then
          Dn:play("button_select")
          Dn:play("rule_end")
          Dn:play("starbutton_end")
          Dn:set("5l", "visible", false)
        end
        st.pz = nil
        beginPuzzle(st.pzDiff)
        setPhase("shuffle")
      end
      return
    end
    if st.phase == "buttons" then
      if not tap then return end
      if inButton(BUTTONS.view, x, y) then
        host.playSe("SE_SELECT")
        setPhase("view")
      elseif inButton(BUTTONS.again, x, y) then
        host.playSe("SE_SELECT")
        local game = s.game
        G.startGame(game.id, game.diff)
      elseif inButton(BUTTONS.quit, x, y) then
        host.playSe("SE_SELECT")
        st = nil
        G.leaveGame({ toPetting = true })
      end
      return
    end
    if st.phase == "view" then
      if tap then setPhase("buttons") end
      return
    end
    if not st.art and st.result then
      if tap and st.pt > 1.0 then st = nil; G.leaveGame({ toPetting = true }) end
      return
    end
    if st.phase ~= "play" or ev.phase ~= "pressed" then return end
    local pz = st.pz
    local i = tileAt(x, y)
    -- a tile home is locked; one still flying waits
    if not i or pz.tiles[i] == i or pz.moving[i] then return end
    if not pz.sel then
      pz.sel = i
      host.playSe("SE_SELECT")
      return
    end
    if pz.sel == i then pz.sel = nil; return end
    local a = pz.sel
    pz.sel = nil
    swap(a, i)
  end

  -- ------- update

  local function advanceAll(frames)
    for _, P in pairs(players) do if P then P:advance(frames) end end
  end

  local function stepTiles(dt)
    local pz = st.pz
    local landing = false
    for pos, m in pairs(pz.moving) do
      if m.delay > 0 then m.delay = m.delay - dt
      else
        m.t = m.t + dt
        if m.t >= m.dur then
          pz.moving[pos] = nil
          if m.landed then burst(pos); host.playSe("SE_PIN") end
        else
          landing = true
        end
      end
    end
    for k = #pz.bursts, 1, -1 do
      local b = pz.bursts[k]
      b.t = b.t + dt
      if b.t > BURST_S then table.remove(pz.bursts, k) end
    end
    return landing
  end

  local function busyTiles()
    for _ in pairs(st.pz.moving) do return true end
    return false
  end

  function app:update(dt)
    local s = G.session
    if not (st and s and s.mode == "game") then app.live = false; return end
    app.live = true
    dt = dt or 0
    st.t = st.t + dt
    st.pt = st.pt + dt
    st.sceneT = st.sceneT + dt
    if st.art then advanceAll(dt * FPS) end
    stepMons(dt, MOTION[st.pzDiff] or 0)
    stepTiles(dt)
    local Dn = st.art and screen("down")

    if st.phase == "shuffle" then
      if not busyTiles() and st.pt > 0.3 then
        setPhase("start")
        banner(Games.line("tile", "start", nil, "START!"))
      end
      return
    end
    if st.phase == "start" then
      if (Dn and Dn:finished("anm_start") and st.pt > 0.5) or (not Dn and st.pt > 1.2) then
        setPhase("play")
        st.t = 0
        banner(nil)
      end
      return
    end
    if st.phase == "next" then
      -- NEXT!, then the next puzzle shuffles in
      if (Dn and Dn:finished("anm_start") and st.pt > 0.6) or (not Dn and st.pt > 1.0) then
        banner(nil)
        beginPuzzle(st.rotation[st.rotIndex])
        setPhase("shuffle")
      end
      return
    end
    if st.phase == "play" then
      if st.diff == "unlimited" then
        st.timer = st.timer - dt
        if st.timer <= 0 then st.timer = 0; finish(st.puzzles); return end
        s.game.hud = ("TILE PUZZLE  UNLIMITED   %d puzzles  %d pts  %ds"):format(st.puzzles, st.score, math.ceil(st.timer))
      else
        st.elapsed = st.elapsed + dt
        s.game.hud = ("TILE PUZZLE  %s   %d:%02d   %d/%d tiles"):format(Games.DIFF_LABEL[st.diff],
          math.floor(st.elapsed / 60), math.floor(st.elapsed % 60), st.pz.correct, st.pz.n)
      end
      -- done once the last tile has landed and burst
      if solved(st.pz) and not busyTiles() then completePuzzle() end
      return
    end
    if st.phase == "finished" then
      if st.pt > 1.6 then
        setPhase("smoke")
        banner(nil)
        if Dn then
          Dn:set("1l", "visible", true)
          Dn:play("anm_smoke")
        end
      end
      return
    end
    if st.phase == "smoke" then
      -- under the smoke the medallions come, and "Poke Puffs Received!" at the top
      if st.pt > 0.25 and not st.revealed then
        st.revealed = true
        layMedals()
        local n = st.result and #(st.result.puffs or {}) or 0
        topWindow(Games.line("tile", n == 1 and "puffReceived" or "puffsReceived", nil, "Poké Puffs Received!"))
      end
      if st.pt > 2.4 then
        if st.result and st.result.unlockedNew and not st.saidRank then
          st.saidRank = true
          topWindow(Games.line("tile", "nextRank", nil, "You can now access the next rank!"))
          st.pt = 0.4
        else
          if Dn then Dn:play("window_close") end
          setPhase("buttons")
        end
      end
    end
  end

  -- ------- drawing: the picture into a canvas (board units at the screen's density), the
  -- tiles as quads of it

  local canvas, canvasK = nil, 1
  -- quads made once and moved (a new one a draw call is garbage every frame)
  local quad, tileQuad, skyQuad, seaQuad = nil, nil, nil, nil
  local TREES = {   -- trees_day / trees_night (256 square): what the scene uses
    conifer = { 2, 186, 45, 68 }, tree = { 2, 53, 25, 28 }, row = { 24, 1, 71, 28 }, bush = { 116, 209, 40, 41 },
  }
  local treeQuads = {}

  local function drawLayer(G2, img, x, y, sx, sy, alpha, qd)
    if not img or alpha <= 0.001 then return end
    G2.setColor(1, 1, 1, alpha)
    if qd then G2.draw(img, qd, x, y, 0, sx, sy) else G2.draw(img, x, y, 0, sx, sy) end
  end

  -- the picture's rect (the frame's) in board units: the grid's extent
  local function picRect(g)
    return g.x, g.y, g.cols * g.pitch, g.rows * g.pitch
  end

  local function drawScene(G2, g)
    local px, py, pw, ph = picRect(g)
    local day, dusk, night = lightAt(st.sceneT)
    local level = MOTION[st.pzDiff] or 0
    local t = st.sceneT
    G2.push()
    -- Hard: the camera drifts and leans in about the middle
    local camX = level >= 2 and math.sin(t * 0.23) * 34 or 0
    local camZ = level >= 2 and (1.08 + 0.06 * math.sin(t * 0.17)) or 1
    local horizon = py + ph * 0.46
    G2.translate(px + pw / 2, horizon)
    G2.scale(camZ, camZ)
    G2.translate(-(px + pw / 2), -horizon)
    -- the sky: the strip's columns (day, deep blue, sunset, night), each a top-to-bottom ramp
    local sky = art("tile/sky")
    local W0, W1 = px - 80, px + pw + 80
    if sky then
      local sw, sh = sky:getDimensions()
      skyQuad = skyQuad or love.graphics.newQuad(0, 0, 1, 1, sw, sh)
      local function col(i, a)
        if a <= 0.001 then return end
        skyQuad:setViewport(i * sw / 4 + 3, 2, sw / 4 - 6, sh - 4, sw, sh)
        drawLayer(G2, sky, W0, py - 40, (W1 - W0) / (sw / 4 - 6), (horizon - py + 44) / (sh - 4), a, skyQuad)
      end
      col(0, 1)
      col(2, dusk)
      col(3, night)
    else
      G2.setColor(0.45 * day + 0.9 * dusk + 0.05 * night, 0.7 * day + 0.5 * dusk + 0.1 * night, 0.95 * day + 0.4 * dusk + 0.3 * night, 1)
      G2.rectangle("fill", W0, py - 40, W1 - W0, horizon - py + 44)
    end
    -- the night's stars
    local star = art("tile/night_star")
    if star and night > 0.01 then
      local sw = star:getWidth()
      for k = 1, 18 do
        local sx = px + ((k * 73) % 97) / 97 * pw
        local sy = py + ((k * 41) % 53) / 53 * (horizon - py) * 0.8
        local tw = 0.5 + 0.5 * math.sin(t * (1.5 + (k % 5) * 0.4) + k)
        local size = 4 + (k % 3) * 2
        drawLayer(G2, star, sx - size / 2, sy - size / 2, size / sw, size / sw, night * tw)
      end
    end
    -- clouds drifting along the horizon, tinted by the hour
    local cloud, cumulus = art("scene/cloud"), art("scene/cumulus")
    local cr = day + dusk * 1.0 + night * 0.35
    local cg = day + dusk * 0.72 + night * 0.4
    local cb = day + dusk * 0.62 + night * 0.62
    for k, c in ipairs({ { cumulus, 0.0, 150, 70, 0.9 }, { cloud, 0.45, 130, 55, 0.8 }, { cumulus, 0.8, 120, 52, 0.7 } }) do
      local img = c[1]
      if img then
        local iw, ih = img:getDimensions()
        local span = pw + c[3] + 160
        local x = px - 80 - c[3] + ((c[2] * span + t * (4 + k * 1.5)) % span)
        G2.setColor(cr, cg, cb, c[5])
        G2.draw(img, x, horizon - c[4] + 2, 0, c[3] / iw, c[4] / ih)
      end
    end
    -- the sea: the day / sunset / night tiles, rows squeezed toward the horizon, drifting
    local seaD, seaU, seaN = art("tile/sea_day"), art("tile/sea_dusk"), art("tile/sea_night")
    local bottom = py + ph + 20
    if seaD then
      local tw0 = seaD:getWidth()
      seaD:setWrap("repeat", "repeat")
      if seaU then seaU:setWrap("repeat", "repeat") end
      if seaN then seaN:setWrap("repeat", "repeat") end
      seaQuad = seaQuad or love.graphics.newQuad(0, 0, 1, 1, tw0, tw0)
      -- rows from the horizon down, each a strip of the tile: far rows small and squashed
      -- (kx / ky units a texel), near ones large; the water drifts, slower up close
      local y0, v = horizon, 0
      while y0 < bottom do
        local depth = (y0 - horizon) / (bottom - horizon)
        local kx = 0.18 + depth * 0.9
        local ky = kx * 0.45
        local h = 3 + depth * 10
        seaQuad:setViewport(W0 / kx + t * 6 * (1 - depth * 0.5), v, (W1 - W0) / kx, h / ky, tw0, tw0)
        drawLayer(G2, seaD, W0, y0, kx, ky, day, seaQuad)
        drawLayer(G2, seaU or seaD, W0, y0, kx, ky, dusk, seaQuad)
        drawLayer(G2, seaN or seaD, W0, y0, kx, ky, night, seaQuad)
        v = v + h / ky
        y0 = y0 + h
      end
    else
      G2.setColor(0.2 * day + 0.6 * dusk + 0.05 * night, 0.6 * day + 0.4 * dusk + 0.15 * night, 0.85 * day + 0.5 * dusk + 0.4 * night, 1)
      G2.rectangle("fill", W0, horizon, W1 - W0, bottom - horizon)
    end
    -- the horizon's glint
    G2.setColor(1, 1, 1, 0.35 * day + 0.25 * dusk + 0.08 * night)
    G2.rectangle("fill", W0, horizon - 0.5, W1 - W0, 1.2)
    -- the shores: a spit of land each side with its trees (day and night sets)
    local trD, trN = art("tile/trees_day"), art("tile/trees_night")
    local function shore(cx, flip)
      G2.setColor(0.25 * (day + dusk * 0.8) + 0.08 * night, 0.32 * (day + dusk * 0.6) + 0.1 * night, 0.22 * (day + dusk * 0.5) + 0.14 * night, 1)
      G2.ellipse("fill", cx, horizon + 4, 46, 7, 24)
      if not trD then return end
      local iw, ih = trD:getDimensions()
      local list = { { "row", cx - 30, 0.9 }, { "conifer", cx - 12, 0.7 }, { "tree", cx + 16, 1.0 }, { "bush", cx + 28, 0.45 } }
      for _, it in ipairs(list) do
        local r = TREES[it[1]]
        treeQuads[it[1]] = treeQuads[it[1]] or love.graphics.newQuad(r[1], r[2], r[3], r[4], iw, ih)
        local k = it[3]
        local x = cx + (it[2] - cx) * flip
        local tint = 1 - dusk * 0.25
        G2.setColor(tint, tint - dusk * 0.15, tint - dusk * 0.25, 1 - night)
        G2.draw(trD, treeQuads[it[1]], x, horizon + 6, 0, k * flip, k, r[3] / 2, r[4])
        if trN and night > 0 then
          G2.setColor(1, 1, 1, night)
          G2.draw(trN, treeQuads[it[1]], x, horizon + 6, 0, k * flip, k, r[3] / 2, r[4])
        end
      end
    end
    shore(px + 30 - camX * 0.2, 1)
    shore(px + pw - 26 - camX * 0.2, -1)
    -- the Pokemon in the water, nearer ones lower and bigger; Hard's camera pans across them
    local order = {}
    for i, m in ipairs(st.mons) do order[i] = m end
    table.sort(order, function(a, b) return a.depth < b.depth end)
    for _, m in ipairs(order) do
      local pic = m.pic
      local x = px + m.x * pw - camX
      -- (the capture's are ~60-110 units across a 240 picture; a 64x64 sprite's frame has room
      -- round the Pokemon, so the frame is drawn larger)
      local feet = horizon + 14 + m.depth * (ph * 0.36)
      local size = (72 + m.depth * 44)
      local bob = math.sin(m.phase) * (level == 0 and 2.5 or 2)
      local sway = level == 0 and math.sin(m.phase * 0.5) * 0.06 or math.sin(m.phase * 0.7) * 0.03
      local hop = m.hop and math.sin(m.hop / 0.45 * math.pi) * 14 or 0
      local shade = 1 - night * 0.45 - dusk * 0.12
      -- the ripple round its middle
      G2.setColor(1, 1, 1, 0.35 * (1 - night * 0.6))
      G2.ellipse("line", x, feet - size * 0.08, size * 0.42 + math.sin(m.phase) * 2, size * 0.07, 24)
      if pic and pic.image then
        local k = size / (pic.h or 64)
        G2.setColor(shade, shade - dusk * 0.06, shade - dusk * 0.1 + night * 0.08, 1)
        drawPixel(pic.image, x, feet - bob - hop, sway, k * m.face, k, (pic.w or 64) / 2, (pic.h or 64) * 0.86)
      else
        G2.setColor(0.9 * shade, 0.75 * shade, 0.3 * shade, 1)
        G2.circle("fill", x, feet - size * 0.4 - bob - hop, size * 0.32, 20)
      end
    end
    G2.pop()
    -- the photo frame over the edges (the stage's own; its transparent inside is the scene's)
    local frame = art("tile/frame_" .. (st.pzDiff or "easy"))
    if frame then
      local fw = frame:getWidth()
      -- the frame fills the texture's top 128 x 104 (the rest is clear)
      quad = quad or love.graphics.newQuad(0, 0, 128, 104, fw, fw)
      G2.setColor(1, 1, 1, 1)
      G2.draw(frame, quad, px, py, 0, pw / 128, ph / 104)
    end
  end

  local function renderPicture(G2)
    if not (love and love.graphics and love.graphics.newCanvas) then return nil end
    local HD = mod.hd
    local k = HD and HD.enabled and math.max(1, math.min(HD.MAX_K, HD.outputScale() * L)) or 1
    if not canvas or canvasK ~= k then
      local ok, c = pcall(love.graphics.newCanvas, math.floor(320 * k + 0.5), math.floor(240 * k + 0.5), { dpiscale = 1 })
      if not ok then return nil end
      canvas, canvasK = c, k
    end
    local prev = G2.getCanvas()
    G2.push("all")
    G2.setCanvas(canvas)
    G2.origin()
    G2.scale(canvasK, canvasK)
    G2.clear(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    local ok, err = pcall(drawScene, G2, st.pz.g)
    if not ok then mod.log:warn("tile puzzle scene: %s", tostring(err)) end
    G2.setCanvas(prev)
    G2.pop()
    return canvas
  end

  local function ease(f) return f < 0.5 and 2 * f * f or 1 - (-2 * f + 2) ^ 2 / 2 end

  local function drawTiles(G2, pic)
    local pz = st.pz
    local g = pz.g
    local P = st.art and screen(pz.diff)
    local frameImg = P and P:image("frame.bclim")
    local cursolImg = P and P:image("cursol.bclim")
    local k = canvasK
    tileQuad = tileQuad or love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    local qd = tileQuad
    local cw, ch = pic:getDimensions()
    local function piece(src, x, y, s)
      local sx, sy = cellXY(g, src)
      qd:setViewport(sx * k, sy * k, g.pitch * k, g.pitch * k, cw, ch)
      G2.setColor(1, 1, 1, 1)
      local sc = s / (g.pitch * k)
      G2.draw(pic, qd, x + g.pitch / 2, y + g.pitch / 2, 0, sc, sc, g.pitch * k / 2, g.pitch * k / 2)
    end
    -- the corners reach the tile's edge and cover the gap there, so the dark shows only at the
    -- edges' middles (the capture); the texture's corners are 80% opaque, drawn twice to read
    -- as solid as the game's
    local function mark(img, x, y)
      if not img then return end
      local iw = img:getWidth()
      G2.setColor(1, 1, 1, 1)
      for _ = 1, 2 do
        G2.draw(img, x + g.pitch / 2, y + g.pitch / 2, 0, g.pitch / iw, g.pitch / iw, iw / 2, iw / 2)
      end
    end
    local shown = pz.shown
    -- the board: the orange under everything, the dark gaps of the tiles out of place
    G2.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    G2.rectangle("fill", 0, -D, 320, LH + D)
    if shown then
      -- the intro: the picture whole under faint lines
      G2.setColor(1, 1, 1, 1)
      G2.draw(pic, 0, 0, 0, 1 / k, 1 / k)
      G2.setColor(0.3, 0.3, 0.3, 0.55)
      G2.setLineWidth(0.8)
      local px, py, pw, ph = picRect(g)
      for c = 1, g.cols - 1 do G2.line(px + c * g.pitch, py, px + c * g.pitch, py + ph) end
      for r = 1, g.rows - 1 do G2.line(px, py + r * g.pitch, px + pw, py + r * g.pitch) end
      G2.setLineWidth(1)
      return
    end
    -- the picture's edges outside the grid (the frame's orange bars) come from the canvas too
    G2.setColor(1, 1, 1, 1)
    -- tiles in place: seamless; out of place: the gap, the piece, the corners
    for pos = 1, pz.n do
      local x, y = cellXY(g, pos)
      local m = pz.moving[pos]
      if m and m.delay <= 0 then
        -- the hole under a tile in flight
        G2.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        G2.rectangle("fill", x, y, g.pitch, g.pitch)
      elseif m then
        -- not yet off: still the old picture there
        piece(m.from, x, y, g.pitch)
      else
        local src = pz.tiles[pos]
        if src == pos then
          piece(src, x, y, g.pitch)
        else
          G2.setColor(GAP[1], GAP[2], GAP[3], 1)
          G2.rectangle("fill", x, y, g.pitch, g.pitch)
          piece(src, x, y, g.pitch - 2)
          mark(pz.sel == pos and cursolImg or frameImg, x, y)
          if not (frameImg and cursolImg) then
            G2.setColor(pz.sel == pos and 0.9 or 0.45, pz.sel == pos and 0.2 or 0.8, pz.sel == pos and 0.2 or 0.95, 1)
            G2.rectangle("line", x + 1, y + 1, g.pitch - 2, g.pitch - 2)
          end
        end
      end
    end
    -- the tiles in flight: lifted, a black edge, over everything
    for pos, m in pairs(pz.moving) do
      if m.delay <= 0 then
        local f = ease(math.min(1, m.t / m.dur))
        local fx, fy = cellXY(g, m.from)
        local tx, ty = cellXY(g, pos)
        local lift = math.sin(f * math.pi) * 6
        local x, y = fx + (tx - fx) * f - lift, fy + (ty - fy) * f - lift
        G2.setColor(0, 0, 0, 1)
        G2.rectangle("fill", x - 1.5, y - 1.5, g.pitch + 3, g.pitch + 3)
        piece(pz.tiles[pos], x, y, g.pitch)
      end
    end
    -- the star bursts from tiles that landed home
    local P0 = st.art and screen("easy")
    local starImg = P0 and P0:image("star.bclim")
    for _, b in ipairs(pz.bursts) do
      local x, y = cellXY(g, b.pos)
      local cx, cy = x + g.pitch / 2, y + g.pitch / 2
      local f = math.min(1, b.t / (BURST_S * 15 / 21))
      local fade = b.t > BURST_S * 0.7 and (1 - (b.t - BURST_S * 0.7) / (BURST_S * 0.3)) or 1
      local scale = g.pitch / 60
      for _, e in ipairs(BURST) do
        local sx, sy = cx + e[1] * f * scale, cy - e[2] * f * scale
        if starImg then
          local iw = starImg:getWidth()
          G2.setColor(1, 1, 1, math.max(0, fade))
          G2.draw(starImg, sx, sy, f * math.pi * 2, 16 / iw, 15.2 / iw, iw / 2, iw / 2)
        else
          G2.setColor(1, 0.85, 0.2, math.max(0, fade))
          G2.circle("fill", sx, sy, 5)
        end
      end
    end
  end

  local function drawButton(G2, b, label, back, font)
    local img = art("game/pill_button")
    local x0, y0 = b[1] - b[3] / 2, b[2] - b[4] / 2
    if img then
      local iw, ih = img:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(img, x0, y0, 0, b[3] / iw, b[4] / ih)
    else
      G2.setColor(0.96, 0.55, 0.35, 1)
      G2.rectangle("fill", x0, y0, b[3], b[4], 12, 12)
    end
    if font then
      G2.setFont(font)
      local k = 14 / font:getHeight()
      G2.setColor(1, 1, 1, 1)
      G2.print(label, x0 + 12, b[2] - font:getHeight() * k / 2, 0, k, k)
    end
    if back then
      local ic = art("lyt/amie_deco/button_back") or art("training/home_return")
      if ic then
        local iw, ih = ic:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(ic, x0 + b[3] - 24, b[2] - 9, 0, 18 / iw, 18 / ih)
      end
    end
  end

  function app:draw(G2, w, h)
    setShape(h)
    local font
    if app.fontsFn then font = app.fontsFn() end
    if not st then return end
    G2.push()
    G2.translate(0, -bleed())
    G2.scale(L, L)
    G2.translate(0, D / 2)
    local pic = renderPicture(G2)
    if pic then
      drawTiles(G2, pic)
    else
      G2.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
      G2.rectangle("fill", 0, -D, 320, LH + D)
    end
    local Dn = st.art and screen("down")
    local phase = st.phase
    if Dn then
      if app.shapeDirty or Dn.shapeD ~= D then
        Dn.shapeD = D
        Dn.adjust = D > 0 and { ["9c"] = { dy = D / 2 } } or nil  -- (y up)
        app.shapeDirty = false
      end
      if phase ~= "view" then Dn:draw(G2) end
    end
    if phase == "buttons" then
      drawButton(G2, BUTTONS.view, Games.line("tile", "viewPicture", nil, "View Picture"), false, font)
      drawButton(G2, BUTTONS.again, Games.line("tile", "playAgain", nil, "Play Again"), false, font)
      drawButton(G2, BUTTONS.quit, Games.line("tile", "quit", nil, "Quit"), true, font)
    end
    if not st.art and st.result then
      G2.setColor(0, 0, 0, 0.5)
      G2.rectangle("fill", 40, 80, 240, 80)
      G2.setColor(1, 1, 1, 1)
      if font then G2.setFont(font) end
      G2.printf((st.result.title or "") .. "  " .. tostring(st.result.stars or 0) .. "*", 40, 110, 240, "center")
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  -- ------- the top screen (session Layer.drawScene in a game hands it the playfield e, 240x160
  -- units): bg_up, How to Play and the time while playing, RESULTS after

  local function clock(secs)
    secs = math.max(0, math.floor(secs or 0))
    return ("%02d:%02d"):format(math.min(99, math.floor(secs / 60)), secs % 60)
  end

  local STAR_TEX = { easy = "star_easy", normal = "star_normal", hard = "star_hard", unlimited = "star_infinite" }
  local RANK_STARS = { "87", "89", "8b", "8d", "8f" }
  local STAR_ROW = {   -- [slot] = { [diff] = { full, half } } (bg_up 7v's palette: rows y 260..358)
    { easy = { "5l", "5n" }, hard = { "5p", "5r" }, unlimited = { "5t", "5v" }, normal = { "5x", "5z" } },
    { easy = { "7d", "7f" }, hard = { "7h", "7j" }, unlimited = { "7l", "7n" }, normal = { "7p", "7r" } },
    { easy = { "6x", "6z" }, hard = { "71", "73" }, unlimited = { "75", "77" }, normal = { "79", "7b" } },
    { easy = { "6h", "6j" }, hard = { "6l", "6n" }, unlimited = { "6p", "6r" }, normal = { "6t", "6v" } },
    { easy = { "61", "63" }, hard = { "65", "67" }, unlimited = { "69", "6b" }, normal = { "6d", "6f" } },
  }

  -- put a pane's middle at (cx, cy) on the card (layout units, y down): its translation set,
  -- its box measured and the difference taken off (as Berry Picker's card)
  local function placeAt(P, name, cx, cy)
    P:set(name, "tx", cx - 200)
    P:set(name, "ty", 120 - cy)
    local bx, by, bw, bh = P:box(name)
    if not bx then return end
    P:set(name, "tx", cx - 200 + cx - (bx + bw / 2))
    P:set(name, "ty", 120 - cy - (cy - (by + bh / 2)))
  end

  local function dressResults(Up)
    local res = st.result or {}
    local unlimited = st.diff == "unlimited"
    local fmt = unlimited and function(v) return tostring(v or 0) end or clock
    Up:set("35", "visible", false)
    Up:set("2c", "visible", true)
    Up:set("2b", "visible", false)
    Up:set("1g", "visible", true)
    local times = res.times or {}
    local rows = { { "2", "c" }, { "4", "k" }, { "6", "s" } }
    for i, r in ipairs(rows) do
      local hit = res.rank == i
      local col = hit and { 220, 30, 40, 255 } or { 60, 50, 40, 255 }
      Up:set(r[1], "visible", true)
      Up:set(r[2], "visible", true)
      Up:setText(r[1], i .. ".", { align = "right", valign = "center", color = col })
      Up:setText(r[2], fmt(times[i] or 0), { align = "right", valign = "center", color = col })
    end
    local red = { 220, 30, 40, 255 }
    Up:set("4r", "visible", true)
    Up:set("4j", "visible", true)
    Up:setText("4r", Games.line("tile", "new", nil, "NEW"), { align = "right", valign = "center", color = red })
    Up:setText("4j", fmt(unlimited and st.puzzles or st.elapsed), { align = "right", valign = "center", color = red })
    -- the rank's title and its five stars: 87..8f are the faint backdrops, the gold ones the
    -- palette below the card (a row per slot, a full and a half star per difficulty), moved
    -- onto them as Berry Picker's card does
    Up:set("7v", "visible", true)
    for _, c in ipairs(Up.L.byName["7v"].children) do
      if c.kind == "pic" then Up:set(c.name, "visible", false) end
    end
    Up:set("8h", "visible", true)
    Up:set("7x", "visible", true)
    Up:set("7t", "visible", true)
    Up:setText("7t", res.title or "", { align = "center", valign = "center", color = { 90, 60, 40, 255 } })
    local diff = STAR_TEX[st.diff] and st.diff or "easy"
    local stars = res.stars or 0
    for j, name in ipairs(RANK_STARS) do
      Up:set(name, "visible", true)
      Up:setImage(name, Up:image(STAR_TEX[diff] .. ".bclim"))
      local full, half = stars >= j, stars >= j - 0.5
      if full or half then
        local gold = STAR_ROW[j][diff][full and 1 or 2]
        local p = Up.L.byName[gold]
        local bx, by, bw, bh = Up:box(name)
        if p and bx then
          local k = p.w > 0 and bw / p.w or 1
          Up:set(gold, "visible", true)
          Up:set(gold, "sx", k)
          Up:set(gold, "sy", k)
          placeAt(Up, gold, bx + bw / 2, by + bh / 2)
        end
      end
    end
    -- HIGH SCORE: a new best
    if res.rank == 1 and not st.stamped then
      st.stamped = true
      Up:set("8s", "visible", true)
      Up:setText("8u", Games.line("tile", "highScore", nil, "HIGH SCORE"), { align = "center", valign = "center" })
      Up:play("highsc_anime")
    end
  end

  function app.drawTop(G2, e)
    if not (st and st.art) then return false end
    local Up = screen("up")
    if not Up then return false end
    e = e or { x = 0, y = 0, w = 240, h = 160 }
    -- the patterned backdrop across the whole playfield
    local bg = Up:image("bg_up.bclim")
    if bg then
      local iw, ih = bg:getDimensions()
      local k = math.max(e.w / iw, e.h / ih)
      G2.setColor(1, 1, 1, 1)
      G2.draw(bg, e.x + (e.w - iw * k) / 2, e.y + (e.h - ih * k) / 2, 0, k, k)
    end
    Up:set("4h", "visible", false)
    local phase = st.phase
    if phase == "intro" or phase == "shuffle" or phase == "start" or phase == "play" or phase == "next" then
      if st.diff == "unlimited" then
        Up:setText("37", Games.line("tile", "timeRemaining", nil, "Time Remaining:"), { align = "left", valign = "center" })
        Up:setText("4f", Games.line("tile", "seconds", { N = math.ceil(st.timer) }, ("%d Seconds"):format(math.ceil(st.timer))), { align = "left", valign = "center" })
        Up:setText("4b", Games.line("tile", "puzzleNo", { N = st.puzzles + 1 }, ("Puzzle No. %d"):format(st.puzzles + 1)), { align = "left", valign = "center" })
        Up:setText("3b", Games.line("tile", "points", { N = st.score }, ("%d Points"):format(st.score)), { align = "left", valign = "center" })
        for _, n in ipairs({ "37", "4f", "4b", "3b" }) do Up:set(n, "visible", true) end
      else
        Up:setText("2f", clock(st.elapsed), { align = "left", valign = "center" })
        Up:set("2d", "visible", true)
        Up:set("2f", "visible", true)
      end
      for _, n in ipairs({ "2s", "2o", "2q", "2v" }) do Up:set(n, "visible", true) end
    else
      dressResults(Up)
    end
    -- the layout centred across the playfield, from its top
    local k = math.min(e.w / 400, e.h / 240)
    local off = math.max(0, (e.h / k - 240) / 2)
    G2.push()
    G2.translate(e.x + (e.w - 400 * k) / 2, e.y + off * k)
    G2.scale(k, k)
    Up:draw(G2)
    G2.pop()
    G2.setColor(1, 1, 1, 1)
    return true
  end

  -- ------- for the driver and tests

  function app.debugState() return st end
  app.screen = screen
  -- busy: tiles in flight or a phase still playing out
  function app.busy()
    if not st then return false end
    if st.phase == "play" then return busyTiles() end
    return st.phase ~= "intro" and st.phase ~= "buttons" and st.phase ~= "view"
  end
  function app.tapPoint(what, i)
    if not st then return nil end
    if what == "begin" then return fromBoard(160, 142) end
    if what == "tile" then
      local g = st.pz.g
      local x, y = cellXY(g, i or 1)
      return fromBoard(x + g.pitch / 2, y + g.pitch / 2)
    end
    local b = BUTTONS[what]
    if b then return fromBoard(b[1], b[2]) end
    return nil
  end
  -- a move that puts a tile home: the place of the first tile out of place and where its
  -- picture is now
  function app.nextMove()
    local pz = st and st.pz
    if not pz then return nil end
    for pos = 1, pz.n do
      if pz.tiles[pos] ~= pos then
        for at = 1, pz.n do if pz.tiles[at] == pos then return pos, at end end
      end
    end
    return nil
  end

  function app:releaseAll() if st and st.pz then st.pz.sel = nil end end
  app.leave = app.releaseAll
  return app
end
