-- TILE PUZZLE: a moving picture of the three participants is cut into tiles
-- and every tile is swapped once; tap two tiles to swap them back. Easy 5x4,
-- Normal 6x5, Hard 8x6, rated by time; Unlimited chains puzzles against a
-- 30-second clock that correct tiles and finished puzzles top up.
-- Rules: Bulbapedia "Tile Puzzle".

return function(mod, Pointer, G, Games, Rules, host)

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
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

  local W, H = 256, 178
  local PIC_W, PIC_H = 200, 150
  local BOARD = { x = 28, y = 12 }
  local GRID = { easy = { 5, 4 }, normal = { 6, 5 }, hard = { 8, 6 } }

  local st = nil
  local canvas = nil
  local sprites = {}   -- the three bouncing Pokemon in the picture

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  -- a perfect matching of swaps: every tile moves exactly once
  local function shuffle(n)
    local order = {}
    for i = 1, n do order[i] = i end
    for i = n, 2, -1 do
      local j = math.random(1, i)
      order[i], order[j] = order[j], order[i]
    end
    local tiles = {}
    for i = 1, n do tiles[i] = i end
    local i = 1
    while i + 1 <= n do
      local a, b = order[i], order[i + 1]
      tiles[a], tiles[b] = tiles[b], tiles[a]
      i = i + 2
    end
    return tiles
  end

  local function newPuzzle(diff)
    local g = GRID[diff] or GRID.easy
    local cols, rows = g[1], g[2]
    local n = cols * rows
    local tiles = shuffle(n)
    local correct = 0
    for i = 1, n do if tiles[i] == i then correct = correct + 1 end end
    return { cols = cols, rows = rows, n = n, tiles = tiles, sel = nil, correct = correct,
      tw = PIC_W / cols, th = PIC_H / rows, flash = nil }
  end

  local function solved(pz)
    for i = 1, pz.n do if pz.tiles[i] ~= i then return false end end
    return true
  end

  local function finish(value)
    st.phase = "over"
    st.result = G.endGame(value, false, true)
  end

  local function startSprites(participants)
    sprites = {}
    for i = 1, 3 do
      local mon = participants[i] and participants[i].mon
      sprites[i] = { pic = host.frontPic and host.frontPic(mon) or nil, x = 40 + (i - 1) * 60, y = 120,
        vx = 18 + i * 6, phase = i * 1.7, facing = (i == 3) and -1 or 1 }
    end
  end

  function app:start(game)
    st = { diff = game.diff, participants = game.participants, phase = "countdown", t = 0, count = 3,
      elapsed = 0, timer = 30, puzzles = 0, score = 0, result = nil,
      rotation = { "easy", "normal", "hard" }, rotIndex = 1, placed = 0, done = {} }
    local firstDiff = (game.diff == "unlimited") and "easy" or game.diff
    st.pz = newPuzzle(firstDiff)
    st.pzDiff = firstDiff
    startSprites(game.participants)
    game.hud = ("TILE PUZZLE  %s"):format(Games.DIFF_LABEL[game.diff])
  end

  function app:quit()
    if st and st.phase ~= "over" then st = nil; G.endGame(nil, true) end
  end

  -- the driver ends a run early: seconds for a timed puzzle, puzzles for Unlimited
  function app.forceEnd(value)
    if st and st.phase == "play" then
      if st.diff == "unlimited" then st.puzzles = value or st.puzzles; finish(st.puzzles)
      else st.elapsed = value or st.elapsed; finish(st.elapsed) end
    end
  end

  local function tileAt(x, y)
    local pz = st.pz
    local cx = math.floor((x - BOARD.x) / pz.tw)
    local cy = math.floor((y - BOARD.y) / pz.th)
    if cx < 0 or cy < 0 or cx >= pz.cols or cy >= pz.rows then return nil end
    return cy * pz.cols + cx + 1
  end

  local function completePuzzle()
    host.playSe("SE_SUCCESS")
    if st.diff ~= "unlimited" then
      finish(st.elapsed)
      return
    end
    st.puzzles = st.puzzles + 1
    st.banner, st.bannerT = Games.line("tile", "next", nil, "NEXT!"), 0.9
    local n = st.puzzles
    st.timer = st.timer + math.max(5, 30 - n)
    local idx = st.rotIndex
    st.done[st.pzDiff] = (st.done[st.pzDiff] or 0) + 1
    local m = st.done[st.pzDiff]
    local bonus = ({ easy = 80, normal = 100, hard = 200 })[st.pzDiff] or 80
    st.score = math.min(49999, st.score + bonus * m)
    st.rotIndex = idx % 3 + 1
    st.pzDiff = st.rotation[st.rotIndex]
    st.pz = newPuzzle(st.pzDiff)
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (st and s and s.mode == "game") then return end
    if st.phase == "over" then
      if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) and st.t > 1.0 then G.leaveGame() end
      return
    end
    if st.phase ~= "play" or ev.phase ~= "pressed" then return end
    local pz = st.pz
    local i = tileAt(ev.x, ev.y)
    if not i then pz.sel = nil; return end
    if not pz.sel then
      pz.sel = i
      host.playSe("SE_SELECT")
      return
    end
    if pz.sel == i then pz.sel = nil; return end
    local a, b = pz.sel, i
    pz.sel = nil
    local wasA, wasB = pz.tiles[a] == a, pz.tiles[b] == b
    pz.tiles[a], pz.tiles[b] = pz.tiles[b], pz.tiles[a]
    local nowA, nowB = pz.tiles[a] == a, pz.tiles[b] == b
    local gained = (nowA and not wasA and 1 or 0) + (nowB and not wasB and 1 or 0)
    local lost = (wasA and not nowA and 1 or 0) + (wasB and not nowB and 1 or 0)
    pz.correct = pz.correct + gained - lost
    pz.flash = { a = a, b = b, t = 0.3 }
    host.playSe(gained > 0 and "SE_PIN" or "SE_SELECT")
    if st.diff == "unlimited" then
      st.score = math.min(49999, st.score + gained)
      for _ = 1, gained do
        st.placed = st.placed + 1
        if st.placed % 2 == 0 then st.timer = st.timer + 1 end
      end
    end
    if solved(pz) then completePuzzle() end
  end

  function app:update(dt)
    local s = G.session
    if not (st and s and s.mode == "game") then app.live = false; return end
    app.live = true
    st.t = st.t + dt
    for _, sp in ipairs(sprites) do
      sp.x = sp.x + sp.vx * dt * sp.facing
      if sp.x > PIC_W - 32 then sp.facing = -1 elseif sp.x < 32 then sp.facing = 1 end
      sp.phase = sp.phase + dt * 5
    end
    if st.pz.flash then st.pz.flash.t = st.pz.flash.t - dt; if st.pz.flash.t <= 0 then st.pz.flash = nil end end
    if st.phase == "countdown" then
      st.count = 3 - math.floor(st.t)
      if st.t >= 3 then st.phase = "play"; st.t = 0; host.playSe("SE_SUCCESS") end
      return
    end
    if st.phase ~= "play" then return end
    if st.diff == "unlimited" then
      st.timer = st.timer - dt
      if st.bannerT then
        st.bannerT = st.bannerT - dt
        if st.bannerT <= 0 then st.banner, st.bannerT = nil, nil end
      end
      if st.timer <= 0 then st.timer = 0; finish(st.puzzles); return end
      s.game.hud = ("TILE PUZZLE  UNLIMITED   %d puzzles  %d pts  %ds"):format(st.puzzles, st.score, math.ceil(st.timer))
    else
      st.elapsed = st.elapsed + dt
      s.game.hud = ("TILE PUZZLE  %s   %d:%02d   %d/%d tiles"):format(Games.DIFF_LABEL[st.diff],
        math.floor(st.elapsed / 60), math.floor(st.elapsed % 60), st.pz.correct, st.pz.n)
    end
  end

  -- ------- drawing: the picture is rendered to a canvas, tiles are quads of it

  -- the picture canvas is PIC_W x PIC_H logical units at the surface's density (the
  -- transform the surface draws under), so the tiles keep the art's full resolution
  local canvasK = 1
  local function renderPicture(G2)
    if not (love and love.graphics and love.graphics.newCanvas) then return nil end
    local HD = mod.hd
    local k = HD and HD.enabled and math.max(1, math.min(HD.MAX_K, HD.outputScale())) or 1
    if not canvas or canvasK ~= k then
      local ok, c = pcall(love.graphics.newCanvas, math.floor(PIC_W * k + 0.5), math.floor(PIC_H * k + 0.5), { dpiscale = 1 })
      if not ok then return nil end
      canvas, canvasK = c, k
    end
    local prev = G2.getCanvas()
    G2.push("all")
    G2.setCanvas(canvas)
    G2.origin()
    G2.scale(canvasK, canvasK)
    G2.clear(0, 0, 0, 0)
    local bg = art("bg/blue") or art("bg/plain")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      G2.draw(bg, 0, 0, 0, PIC_W / bw, PIC_H / bh)
    else
      G2.setColor(0.55, 0.78, 0.98, 1)
      G2.rectangle("fill", 0, 0, PIC_W, PIC_H)
      G2.setColor(0.42, 0.75, 0.42, 1)
      G2.rectangle("fill", 0, 100, PIC_W, 50)
    end
    for _, sp in ipairs(sprites) do
      local bounce = math.abs(math.sin(sp.phase)) * 8
      if sp.pic and sp.pic.image then
        G2.setColor(1, 1, 1, 1)
        drawPixel(sp.pic.image, sp.x, sp.y - bounce, 0, -sp.facing, 1, (sp.pic.w or 64) / 2, sp.pic.h or 64)
      else
        G2.setColor(0.9, 0.75, 0.3, 1)
        G2.circle("fill", sp.x, sp.y - 20 - bounce, 16, 20)
      end
    end
    G2.setCanvas(prev)
    G2.pop()
    return canvas
  end

  function app:draw(G2, w, h)
    local s = G.session
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local bg = art("game/tile_bg")
    if bg then
      G2.setColor(1, 1, 1, 1)
      local bw, bh = bg:getDimensions()
      local bl = app.bleed or 0
      local sc = math.max(w / bw, (h + bl) / bh)
      G2.draw(bg, (w - bw * sc) / 2, -bl + (h + bl - bh * sc) / 2, 0, sc, sc)
    else
      G2.setColor(0.25, 0.22, 0.3, 1)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    end
    if not st then return end
    local pz = st.pz
    local pic = renderPicture(G2)
    G2.setColor(0.1, 0.1, 0.12, 0.8)
    G2.rectangle("fill", BOARD.x - 2, BOARD.y - 2, PIC_W + 4, PIC_H + 4, 3, 3)
    for pos = 1, pz.n do
      local src = pz.tiles[pos]
      local px = BOARD.x + ((pos - 1) % pz.cols) * pz.tw
      local py = BOARD.y + math.floor((pos - 1) / pz.cols) * pz.th
      local sx = ((src - 1) % pz.cols) * pz.tw
      local sy = math.floor((src - 1) / pz.cols) * pz.th
      if pic then
        local k = canvasK
        local q = love.graphics.newQuad(sx * k, sy * k, pz.tw * k, pz.th * k, PIC_W * k, PIC_H * k)
        G2.setColor(1, 1, 1, 1)
        G2.draw(pic, q, px, py, 0, 1 / k, 1 / k)
      else
        local v = (src % 7) / 7
        G2.setColor(0.3 + v * 0.5, 0.5, 0.9 - v * 0.5, 1)
        G2.rectangle("fill", px, py, pz.tw, pz.th)
      end
      G2.setColor(0, 0, 0, 0.35)
      G2.rectangle("line", px + 0.5, py + 0.5, pz.tw - 1, pz.th - 1)
      if pz.sel == pos or (pz.flash and (pz.flash.a == pos or pz.flash.b == pos)) then
        local frame = art(pz.sel == pos and "game/tile_frame_red" or "game/tile_frame_blue")
        if frame then
          G2.setColor(1, 1, 1, 1)
          local fw, fh = frame:getDimensions()
          G2.draw(frame, px + pz.tw / 2, py + pz.th / 2, 0, (pz.tw + 4) / fw, (pz.th + 4) / fh, fw / 2, fh / 2)
        else
          G2.setColor(pz.sel == pos and 1 or 0.4, pz.sel == pos and 0.3 or 0.6, 0.3, 1)
          G2.setLineWidth(2)
          G2.rectangle("line", px + 1, py + 1, pz.tw - 2, pz.th - 2)
          G2.setLineWidth(1)
        end
      end
    end
    -- status
    G2.setColor(0, 0, 0, 0.55)
    G2.rectangle("fill", 4, h - 16, w - 8, 14, 4, 4)
    G2.setColor(1, 1, 1, 1)
    if app.smallFont then G2.setFont(app.smallFont) end
    if st.diff == "unlimited" then
      local no = Games.line("tile", "puzzleNo", { N = st.puzzles + 1 }, ("Puzzle No. %d"):format(st.puzzles + 1))
      G2.printf(("%s   %s %d   %s"):format(no, Games.line("tile", "timeRemaining", nil, "Time Remaining:"), math.ceil(st.timer),
        Games.line("tile", "points", { N = st.score }, ("%d Points"):format(st.score))), 8, h - 14, w - 16, "center")
    else
      G2.printf(("%s %d:%02d   %d / %d"):format(Games.line("tile", "time", nil, "Time:"), math.floor(st.elapsed / 60), math.floor(st.elapsed % 60), pz.correct, pz.n), 8, h - 14, w - 16, "center")
    end
    if app.font then G2.setFont(app.font) end
    if st.banner and st.phase == "play" then
      G2.setColor(1, 0.9, 0.3, 1)
      G2.printf(st.banner, 0, h / 2 - 10, w, "center")
    end
    if st.phase == "countdown" then
      G2.setColor(0, 0, 0, 0.4)
      G2.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
      G2.setColor(1, 1, 1, 1)
      G2.printf(st.count > 0 and Games.line("berry", "ready", nil, "READY") or Games.line("tile", "start", nil, "START!"), 0, h / 2 - 10, w, "center")
    elseif st.phase == "over" and st.result then
      local detail
      if st.diff == "unlimited" then
        detail = Games.line("tile", "puzzles", { N = st.puzzles }, ("%d Puzzles"):format(st.puzzles)) .. "   " ..
          Games.line("tile", "points", { N = st.score }, ("%d Points"):format(st.score))
      else
        detail = ("%s %d:%02d"):format(Games.line("tile", "time", nil, "Time:"), math.floor(st.elapsed / 60), math.floor(st.elapsed % 60))
      end
      Games.drawResult(G2, w, h, st.result, app, art, detail)
    end
  end

  -- for the driver and tests
  function app.debugState() return st end

  function app:releaseAll() end
  app.leave = app.releaseAll
  return app
end
