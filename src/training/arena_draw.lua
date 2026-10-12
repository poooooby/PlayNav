-- The top screen during a Super-Training Regimen (240x160): the arena, the Balloon Bot
-- with its goals, bits and barrier, the player's Pokemon, shots and balls, the HUD
-- (clock, score, guts, charge, caution) and the result card. Every piece has a drawn
-- fallback; ORAS art slots in through `D.assets` when the recipe carries it.
--
-- D = arena_draw(mod, { host, Rules, Sim })

return function(mod, deps)

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local host, Rules, Sim = deps.host, deps.Rules, deps.Sim
  local N = Rules.N
  local D = { assets = nil }

  local function art(id)
    local A = D.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  local SHOT_RGB = { black = { 0.2, 0.2, 0.22 }, yellow = { 0.98, 0.85, 0.2 }, orange = { 0.98, 0.55, 0.15 },
    green = { 0.3, 0.8, 0.35 }, blue = { 0.35, 0.65, 1 }, weak = { 0.1, 0.1, 0.1 } }
  local BALL_RGB = { small = { 0.95, 0.3, 0.3 }, big = { 0.9, 0.25, 0.25 }, ring = { 0.98, 0.6, 0.2 },
    homing = { 0.35, 0.6, 1 }, cross = { 0.98, 0.6, 0.2 }, wave = { 0.95, 0.5, 0.2 }, bit = { 0.75, 0.4, 0.95 } }
  local GOAL_RGB = { white = { 1, 1, 1 }, fading = { 1, 0.9, 0.3 }, chance = { 1, 0.25, 0.3 }, marker = { 1, 0.85, 0.2 } }

  local function clock(secs)
    secs = math.max(0, secs or 0)
    local m = math.floor(secs / 60)
    local s = secs - m * 60
    return ("%d:%05.2f"):format(m, s)
  end
  D.clock = clock

  local botPics = {}
  local function botPic(bot)
    if not bot then return nil end
    if bot.art then
      local img = art(bot.art)
      if img then return img, "art" end
    end
    local key = tostring(bot.national)
    if botPics[key] == nil then
      local sp = host.speciesFromNational and host.speciesFromNational(bot.national)
      local entry = sp and host.speciesFrontPic and host.speciesFrontPic(sp)
      botPics[key] = entry and entry.image or false
    end
    return botPics[key] or nil, "pic"
  end


  -- ------- the Balloon Bot: the Pokemon's own front sprite, blown up in balloon blue
  --
  -- D.shapeFor(botRow) reads the sprite's pixels once and returns its shape for the sim
  -- (Sim: goals stand on its cells and walk across them, never over empty space) plus what
  -- drawing needs. The sprite's larger side spans 2 * D.SIZE bot radii. nil when the game
  -- has no sprite for the species (the course badge stands in then).

  D.SIZE = 2.2       -- the cell range searched (bot radii); the fit below is the real size
  D.FIT_W = 2.2      -- half width, bot radii
  D.FIT_H = 1.25     -- half height, bot radii (x Sim.ASPECT on screen)
  D.CELL_PX = 2      -- shape cells, in sprite pixels
  D.ERODE_PX = 2     -- a goal's centre stays this far inside the sprite's edge
  local shapes = {}

  local function readMask(image, quad, w, h)
    local G = love and love.graphics
    if not (G and G.newCanvas) then return nil end
    local ok, canvas = pcall(G.newCanvas, w, h, { dpiscale = 1 })
    if not ok then return nil end
    G.push("all")
    G.setCanvas(canvas)
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    G.clear(0, 0, 0, 0)
    G.setColor(1, 1, 1, 1)
    if quad then G.draw(image, quad, 0, 0) else G.draw(image, 0, 0) end
    G.setCanvas()
    G.pop()
    local okD, data = pcall(canvas.newImageData, canvas)
    if not okD then return nil end
    local mask = {}
    for y = 0, h - 1 do
      local row = {}
      for x = 0, w - 1 do
        local _, _, _, a = data:getPixel(x, y)
        row[x] = a > 0.5
      end
      mask[y] = row
    end
    return mask
  end

  -- pure: the shape from a mask (rows 0..h-1 of columns 0..w-1, true = opaque)
  function D.shapeFromMask(mask, w, h)
    local x0, y0, x1, y1 = math.huge, math.huge, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if mask[y][x] then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    if x1 < 0 then return nil end
    local cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
    -- as large as fits: half width at most FIT_W bot radii, half height at most FIT_H (so a
    -- fully grown balloon, stretched to the screen's aspect, stays inside the aim's reach)
    local ppr = math.max((x1 - x0 + 1) / 2 / D.FIT_W, (y1 - y0 + 1) / 2 / D.FIT_H)
    local function inside(x, y, e)
      for yy = y - e, y + e do
        local row = mask[yy]
        if not row then return false end
        for xx = x - e, x + e do
          if not row[xx] then return false end
        end
      end
      return true
    end
    local cell = D.CELL_PX / ppr
    for e = D.ERODE_PX, 0, -1 do
      local cells, list = {}, {}
      local lo = math.floor(-D.SIZE / cell) - 1
      for i = lo, -lo do
        for j = lo, -lo do
          local px = math.floor(cx + (i + 0.5) * cell * ppr)
          local py = math.floor(cy - (j + 0.5) * cell * ppr)
          if px >= 0 and py >= 0 and px < w and py < h and inside(px, py, e) then
            cells[i] = cells[i] or {}
            cells[i][j] = true
            list[#list + 1] = { i, j }
          end
        end
      end
      if #list >= 12 or e == 0 then
        if #list == 0 then return nil end
        -- halfW / halfH: the sprite's half extent in bot-local units (anchors are spread over it)
        return { cell = cell, cells = cells, list = list, ppr = ppr, cx = cx, cy = cy, bbox = { x0, y0, x1, y1 },
          halfW = (x1 - x0 + 1) / 2 / ppr, halfH = (y1 - y0 + 1) / 2 / ppr }
      end
    end
  end

  function D.shapeFor(row)
    if not row then return nil end
    local key = tostring(row.national) .. ":" .. tostring(row.species)
    if shapes[key] ~= nil then return shapes[key] or nil end
    shapes[key] = false
    -- course rows name species as constants ("SPECIES_BLASTOISE"); the pic wants the number
    local sp = host.speciesFromNational and row.national and host.speciesFromNational(row.national)
    if not sp and type(row.species) == "number" then sp = row.species end
    local entry = sp and host.speciesFrontPic and host.speciesFrontPic(sp)
    if not (entry and entry.image) then
      mod.log:info("super training: no front sprite for #%s; the course badge stands in", tostring(row.national))
      return nil
    end
    local img = entry.image
    local iw, ih = img:getDimensions()
    local w, h = entry.w or iw, entry.h or ih
    local quad = (love and love.graphics and (w < iw or h < ih)) and love.graphics.newQuad(0, 0, w, h, iw, ih) or nil
    local mask = readMask(img, quad, w, h)
    local shape = mask and D.shapeFromMask(mask, w, h)
    if not shape then return nil end
    shape.image, shape.quad, shape.w, shape.h = img, quad, w, h
    shapes[key] = shape
    return shape
  end

  -- balloon blue: the sprite's light and shade on a blue ramp, sampled sharp-bilinear so the
  -- blown-up pixels stay square; `silhouette` 1 draws the flat outline colour
  local BALLOON_SRC = [[
uniform vec2 texSize;
uniform vec2 pxPerTexel;
uniform vec3 dark;
uniform vec3 light;
uniform float silhouette;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = uv * texSize;
  vec2 base = floor(texel);
  vec2 d = fract(texel) - 0.5;
  vec2 region = 0.5 - 0.5 / pxPerTexel;
  vec2 f = (d - clamp(d, -region, region)) * pxPerTexel + 0.5;
  vec4 p = Texel(tex, (base + f) / texSize);
  float l = dot(p.rgb, vec3(0.299, 0.587, 0.114));
  vec3 c = mix(dark, light, smoothstep(0.02, 0.98, l));
  c = mix(c, color.rgb, silhouette);
  return vec4(c, p.a * color.a);
}
]]
  local balloonShader, balloonFailed = nil, false
  local function balloon()
    if balloonShader or balloonFailed then return balloonShader end
    local G = love and love.graphics
    local ok, sh = pcall(G.newShader, BALLOON_SRC)
    if ok then
      balloonShader = sh
      pcall(sh.send, sh, "dark", { 0.02, 0.2, 0.6 })
      pcall(sh.send, sh, "light", { 0.6, 0.9, 1.0 })
    else
      balloonFailed = true
    end
    return balloonShader
  end

  -- draw the shape's sprite centred (its bbox centre) on (x, y), `ppx` screen units per
  -- sprite pixel, alpha a
  local function drawBalloon(G2, shape, x, y, ppx, a)
    local img = shape.image
    local sh = balloon()
    local HD = mod.hd
    local out = (HD and HD.outputScale and HD.outputScale() or 1) * ppx
    local pw, ph = img:getPixelDimensions()
    local tpu = pw / img:getWidth()
    local minF, magF = img:getFilter()
    local function draw(dx, dy)
      if shape.quad then G2.draw(img, shape.quad, x + dx, y + dy, 0, ppx, ppx, shape.cx, shape.cy)
      else G2.draw(img, x + dx, y + dy, 0, ppx, ppx, shape.cx, shape.cy) end
    end
    if sh then
      img:setFilter("linear", "linear")
      sh:send("texSize", { pw, ph })
      sh:send("pxPerTexel", { math.max(1, out / tpu), math.max(1, out / tpu) })
      G2.setShader(sh)
      -- the outline: the silhouette nudged around it
      sh:send("silhouette", 1)
      G2.setColor(0.02, 0.1, 0.32, a)
      local o = math.max(1, ppx * 0.7)
      draw(-o, 0); draw(o, 0); draw(0, -o); draw(0, o)
      sh:send("silhouette", 0)
      G2.setColor(1, 1, 1, a)
      draw(0, 0)
      G2.setShader()
      img:setFilter(minF, magF)
    else
      G2.setColor(0.55, 0.75, 1, a)
      draw(0, 0)
    end
  end
  D.drawBalloon = drawBalloon

  local function drawBackground(G2, sim)
    G2.setColor(0.36, 0.6, 0.92, 1)
    G2.rectangle("fill", 0, 0, 240, 92)
    G2.setColor(0.55, 0.75, 0.98, 1)
    G2.rectangle("fill", 0, 60, 240, 32)
    G2.setColor(0.22, 0.62, 0.38, 1)
    G2.rectangle("fill", 0, 92, 240, 68)
    -- pitch lines
    G2.setColor(1, 1, 1, 0.25)
    for i = -2, 2 do
      local x0 = Sim.project(i * 0.5, 0, 0)
      local x1 = Sim.project(i * 0.5, 0, 1)
      G2.line(x0, 150, x1, 92)
    end
    for _, z in ipairs({ 0.2, 0.5, 0.8 }) do
      local _, y = Sim.project(0, 0, z)
      local xl = Sim.project(-1, 0, z)
      local xr = Sim.project(1, 0, z)
      G2.line(xl, y, xr, y)
    end
    if sim and sim.bot and sim.bot.aura > 0 then
      G2.setColor(1, 0.2, 0.2, 0.15 + 0.15 * math.sin(sim.t * 20))
      G2.rectangle("fill", 0, 0, 240, 160)
    end
  end

  local function drawBot(G2, sim)
    local bot = sim.bot
    if not bot then return end
    local bx, by = sim:botOffset()
    local cyW = sim.botCY and sim:botCY() or N.BOT.CY
    local sx, sy, k = Sim.project(bx, cyW + by, 1)
    local R = N.BOT.R * 70 * bot.scale
    local fx = bot.flinch > 0 and math.sin(sim.t * 50) * 3 or 0
    -- shadow and aura
    G2.setColor(0, 0, 0, 0.25)
    G2.ellipse("fill", sx, 92 + 4, R * 0.9, 5)
    if bot.aura > 0 then
      G2.setColor(1, 0.3, 0.2, 0.45)
      G2.circle("fill", sx + fx, sy, R * 1.25, 32)
    end
    if sim.barrier then
      G2.setColor(0.4, 0.9, 1, 0.3)
      G2.circle("fill", sx + fx, sy, R * 1.15, 32)
      G2.setColor(0.6, 1, 1, 0.8)
      G2.circle("line", sx + fx, sy, R * 1.15, 32)
    end
    local img, kind = botPic(bot)
    local shape = sim.shape and sim.shape.image and sim.shape or nil
    if shape then
      -- the Pokemon's own sprite as the balloon, at the same scale the goals use
      local x1 = Sim.project(1, cyW, 1)
      local x0 = Sim.project(0, cyW, 1)
      local unitPx = math.abs(x1 - x0)
      local rPx = N.BOT.R * bot.scale * unitPx
      local ppx = rPx / shape.ppr
      drawBalloon(G2, shape, sx + fx, sy, ppx, bot.flinch > 0 and 0.8 or 1)
    elseif img then
      local iw, ih = img:getDimensions()
      local scale = (2 * R) / math.max(iw, ih)
      if kind == "pic" then
        -- the balloon: a blue-tinted sprite in a round body
        G2.setColor(0.45, 0.6, 1, 0.9)
        G2.circle("fill", sx + fx, sy, R, 32)
        G2.setColor(0.7, 0.85, 1, 1)
        G2.draw(img, sx + fx, sy, 0, scale * 0.9, scale * 0.9, iw / 2, ih / 2)
      else
        -- the ORAS course badge already carries the balloon's ring; let it fill the body
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, sx + fx, sy, 0, scale * 1.35, scale * 1.35, iw / 2, ih / 2)
      end
    else
      G2.setColor(0.45, 0.6, 1, 1)
      G2.circle("fill", sx + fx, sy, R, 32)
      G2.setColor(0.25, 0.35, 0.7, 1)
      G2.circle("line", sx + fx, sy, R, 32)
      G2.setColor(1, 1, 1, 0.9)
      G2.printf(("#%d"):format(bot.national or 0), sx - 30, sy - 6, 60, "center")
    end
    if not shape then
      G2.setColor(1, 1, 1, 0.6)
      G2.circle("line", sx + fx, sy, R, 32)
    end
    -- goals
    for _, g in ipairs(sim.goals) do
      local gx, gy = sim:goalPos(g)
      local px, py = Sim.project(gx, gy, 1)
      local gr = g.r * 70 * bot.scale
      local rgb = GOAL_RGB[g.kind] or GOAL_RGB.white
      local pulse = (g.kind == "chance") and (1 + 0.1 * math.sin(sim.t * 8)) or 1
      local frame = math.floor(sim.t * 12) % 9
      local ring = (g.kind == "marker") and art("training/marker")
        or (g.kind == "chance" and art(("training/big_target_%02d"):format(frame)))
        or art(("training/target_%02d"):format(frame))
      if ring then
        local iw, ih = ring:getDimensions()
        local sc = (gr * 2.4 * pulse) / iw
        if g.kind == "fading" then G2.setColor(1, 0.9, 0.3, 1) elseif g.kind == "chance" then G2.setColor(1, 0.5, 0.5, 1)
        else G2.setColor(1, 1, 1, 1) end
        G2.draw(ring, px + fx, py, 0, sc, sc, iw / 2, ih / 2)
      else
        G2.setLineWidth(2)
        G2.setColor(rgb[1], rgb[2], rgb[3], 0.95)
        G2.circle("line", px + fx, py, gr * pulse, 20)
        G2.setColor(rgb[1], rgb[2], rgb[3], 0.35)
        G2.circle("fill", px + fx, py, gr * 0.6 * pulse, 16)
        G2.setLineWidth(1)
      end
    end
    -- bits (the dead ones wait to regenerate)
    for _, bit in ipairs(sim.bits) do
      if bit.dead then goto nextbit end
      local px, py, kk = Sim.project(bit.x, bit.y, bit.z)
      local r = bit.r * 118 * kk
      G2.setColor(0.75, 0.4, 0.95, 0.95)
      G2.circle("fill", px, py, r, 16)
      G2.setColor(1, 1, 1, 0.8)
      G2.circle("line", px, py, r, 16)
      G2.setColor(0.2, 0.9, 0.3, 1)
      G2.rectangle("fill", px - r, py - r - 4, 2 * r * (bit.hp / N.ATTACK.bit.hp), 2)
      ::nextbit::
    end
  end

  local function drawBalls(G2, sim)
    for _, b in ipairs(sim.balls) do
      local px, py, k = Sim.project(b.x, b.y, b.z)
      local rgb = BALL_RGB[b.kind] or BALL_RGB.small
      G2.setColor(0, 0, 0, 0.2)
      local _, fy = Sim.project(b.x, 0, b.z)
      G2.ellipse("fill", px, fy, b.r * 118 * k, 3)
      G2.setColor(rgb[1], rgb[2], rgb[3], 1)
      if b.w or b.h then
        G2.ellipse("fill", px, py, (b.w or b.r * 2) / 2 * 118 * k, (b.h or b.r * 2) / 2 * 70 * k)
      else
        G2.circle("fill", px, py, b.r * 118 * k, 16)
      end
      G2.setColor(1, 1, 1, 0.7)
      if not (b.w or b.h) then G2.circle("line", px, py, b.r * 118 * k, 16) end
    end
  end

  -- the ORAS ball art per Energy Shot colour (a/1/1/4: white, yellow, orange, green, blue, black)
  local BALL_ART = { weak = 5, black = 0, yellow = 1, orange = 2, green = 3, blue = 4 }

  local function drawShots(G2, sim)
    for _, sh in ipairs(sim.shots) do
      local px, py, k = Sim.project(sh.x, sh.y, sh.z)
      local r = math.max(2, sh.r * 118 * k)
      local img = art(("training/ball_%02d"):format(BALL_ART[sh.type] or 0))
      if img then
        local iw = img:getWidth()
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, px, py, sim.t * 6, (r * 2) / iw, (r * 2) / iw, iw / 2, iw / 2)
      else
        local rgb = SHOT_RGB[sh.type] or SHOT_RGB.black
        G2.setColor(rgb[1], rgb[2], rgb[3], 1)
        G2.circle("fill", px, py, r, 12)
        G2.setColor(1, 1, 1, 0.9)
        G2.circle("line", px, py, r, 12)
      end
    end
  end

  -- the pic entry: image plus its logical size (HD sprite mods hand back a larger canvas
  -- with w/h still the GBA size, so draws scale by w/h, never by the image)
  local playerPics = {}
  local function playerPic(s)
    if playerPics[s.key] == nil then
      local entry = host.backPic and host.backPic(s.mon) or nil
      if not (entry and entry.image) then entry = s.pic end
      if entry and entry.image then
        -- the pic sits in the top-left w x h of its canvas (padded textures are larger)
        local iw, ih = entry.image:getDimensions()
        local w, h = entry.w or iw, entry.h or ih
        local quad = (love and love.graphics and (w < iw or h < ih)) and love.graphics.newQuad(0, 0, w, h, iw, ih) or nil
        playerPics[s.key] = { image = entry.image, w = w, h = h, quad = quad }
      else
        playerPics[s.key] = false
      end
    end
    return playerPics[s.key] or nil
  end

  -- for the driver: what the player sprite resolved to
  function D.debugPlayer(s)
    local pic = playerPic(s)
    if not pic then return "nil" end
    local ok, w, h = pcall(pic.image.getDimensions, pic.image)
    return ("%s %sx%s as %dx%d"):format(type(pic.image), tostring(w), tostring(h), pic.w, pic.h)
  end

  -- the player's Pokemon on the move: little hops with a squash on each landing and a
  -- stretch in the air, a lean into the direction, facing it; easing out into a last
  -- squash when it stops. Drawing only: the sim's position and hit area do not change.
  D.HOP = { PERIOD = 0.3, HEIGHT = 4, SQUASH = 0.14, STRETCH = 0.06, LEAN = 0.07, LAND_S = 0.18, EASE = 10 }
  local hopState = setmetatable({}, { __mode = "k" })
  local function hopPose(sim)
    local p = sim.player
    local H = D.HOP
    local st = hopState[sim]
    if not st then
      st = { t = sim.t, x = p.x, z = p.z, phase = 0, amp = 0, land = 0, face = 1, moving = false }
      hopState[sim] = st
    end
    local dt = sim.t - st.t
    if dt < 0 or dt > 0.5 then dt = 0 end
    local moved = math.abs(p.x - st.x) + math.abs(p.z - st.z)
    local moving = dt > 0 and moved / dt > 0.02 or (dt == 0 and st.moving)
    if st.moving and not moving then st.land = H.LAND_S end
    st.moving = moving
    if p.x - st.x > 1e-4 then st.face = 1 elseif p.x - st.x < -1e-4 then st.face = -1 end
    st.t, st.x, st.z = sim.t, p.x, p.z
    st.amp = st.amp + ((moving and 1 or 0) - st.amp) * math.min(1, dt * H.EASE)
    if st.amp > 0.01 then st.phase = st.phase + dt * math.pi / H.PERIOD else st.phase = 0 end
    st.land = math.max(0, st.land - dt)
    local hop = math.abs(math.sin(st.phase))       -- 0 on the ground, 1 at the top
    local sx, sy = 1, 1
    if hop < 0.25 then
      local s = (0.25 - hop) / 0.25 * H.SQUASH * st.amp
      sx, sy = 1 + s, 1 - s
    else
      local s = hop * H.STRETCH * st.amp
      sx, sy = 1 - s, 1 + s
    end
    local lift = hop * H.HEIGHT * st.amp
    if st.land > 0 then
      -- it just stopped: down on the ground, squashed, springing back
      local s = H.SQUASH * (st.land / H.LAND_S)
      sx, sy, lift = 1 + s, 1 - s, 0
      st.amp, st.phase = 0, 0
    end
    local dir = (p.mx or 0) ~= 0 and (p.mx > 0 and 1 or -1) or 0
    return lift, sx, sy, H.LEAN * st.amp * dir, st.face
  end
  D.hopPose = hopPose

  local function drawPlayer(G2, sim, s)
    local p = sim.player
    local px, py, k = Sim.project(p.x, 0, p.z)
    local lift, hsx, hsy, lean, face = hopPose(sim)
    G2.setColor(0, 0, 0, 0.3)
    local shrink = 1 - 0.25 * (lift / math.max(1, D.HOP.HEIGHT))
    G2.ellipse("fill", px, py, 18 * k * shrink, 5 * k * shrink)
    local pic = playerPic(s)
    local stage = sim:chargeStage()
    if p.charging and stage > 0 then
      local ring = art("training/charge")
      if ring then
        local sc = (36 + 10 * stage) * k / 64
        G2.setColor(1, 1, 1, 0.5 + 0.15 * stage)
        G2.draw(ring, px, py - 20 * k, sim.t * 4, sc, sc, 32, 32)
      else
        G2.setColor(1, 0.9, 0.4, 0.3 + 0.1 * stage)
        G2.circle("fill", px, py - 20 * k, (16 + 6 * stage) * k, 24)
      end
    end
    if p.shield > 0 then
      G2.setColor(0.4, 0.9, 1, 0.5)
      G2.arc("fill", px, py - 18 * k, 26 * k, -math.pi * 0.9, -math.pi * 0.1, 16)
    end
    if pic then
      local flash = p.stun > 0 and (math.floor(sim.t * 20) % 2 == 0)
      G2.setColor(1, 1, 1, flash and 0.4 or 1)
      -- scaled about its feet, so a squash flattens it onto the ground
      local y = py + 2 - lift * k
      if pic.quad then
        drawPixel(pic.image, pic.quad, px, y, lean, k * hsx * face, k * hsy, pic.w / 2, pic.h)
      else
        drawPixel(pic.image, px, y, lean, k * hsx * face, k * hsy, pic.w / 2, pic.h)
      end
    else
      G2.setColor(0.95, 0.6, 0.2, 1)
      G2.circle("fill", px, py - 14 * k, 12 * k, 16)
    end
    -- the reticle
    local rx, ry = Sim.project(p.aim.x, p.aim.y, 1)
    G2.setColor(1, 1, 1, 0.9)
    G2.circle("line", rx, ry, 5, 12)
    G2.line(rx - 8, ry, rx - 3, ry)
    G2.line(rx + 3, ry, rx + 8, ry)
    G2.line(rx, ry - 8, rx, ry - 3)
    G2.line(rx, ry + 3, rx, ry + 8)
  end

  -- a number out of the game's digit textures (prefix "training/num_" or "training/score_"),
  -- `scale` per digit; returns the width drawn, or nil when the art is absent
  local function drawDigits(G2, prefix, text, x, y, scale)
    local first = art(prefix .. "0")
    if not first then return nil end
    local dw = first:getWidth() * scale
    local cx = x
    G2.setColor(1, 1, 1, 1)
    for ch in tostring(text):gmatch(".") do
      if ch:match("%d") then
        local img = art(prefix .. ch)
        if img then G2.draw(img, cx, y, 0, scale, scale) end
        cx = cx + dw
      elseif ch == ":" or ch == "." then
        G2.circle("fill", cx + dw * 0.2, y + first:getHeight() * scale * 0.35, 1.2, 6)
        G2.circle("fill", cx + dw * 0.2, y + first:getHeight() * scale * 0.7, 1.2, 6)
        cx = cx + dw * 0.45
      elseif ch == "/" then
        local slash = art("training/score_slash")
        if slash then
          G2.draw(slash, cx, y, 0, scale, scale)
          cx = cx + slash:getWidth() * scale + 1
        else
          G2.line(cx + dw * 0.5, y, cx, y + first:getHeight() * scale)
          cx = cx + dw * 0.6
        end
      else
        cx = cx + dw * 0.6
      end
    end
    return cx - x
  end

  local function drawHud(G2, sim, s, T)
    local drawText = T.drawText
    G2.setColor(0, 0, 0, 0.45)
    G2.rectangle("fill", 4, 4, 70, 16, 3, 3)
    G2.rectangle("fill", 236 - 92, 4, 92, 16, 3, 3)
    G2.setColor(1, 1, 1, 1)
    if not drawDigits(G2, "training/num_", clock(sim.remaining), 8, 4, 0.5) then
      drawText(clock(sim.remaining), 8, 6, { maxWidth = 64, color = "white" })
    end
    local scoreText = ("%d/%d"):format(math.floor(sim.score), sim.bot and sim.bot.target or 0)
    if not drawDigits(G2, "training/score_", scoreText, 236 - 88, 2, 0.4) then
      drawText(scoreText, 236 - 88, 6, { maxWidth = 86, color = "white" })
    end
    -- "Start" when play begins
    if sim.phase == "play" and (sim.t - (sim.scheduleT0 or 0)) < 1.2 then
      local banner = art("training/banner_start")
      if banner then
        G2.setColor(1, 1, 1, 1)
        G2.draw(banner, 120, 60, 0, 0.75, 0.75, 128, 32)
      end
    end
    if #sim.course.bots > 1 then
      G2.setColor(0, 0, 0, 0.45)
      G2.rectangle("fill", 100, 4, 40, 16, 3, 3)
      drawText(("%d/%d"):format(sim.botIndex, #sim.course.bots), 104, 6, { maxWidth = 36, color = "white" })
    end
    -- the energy meter: the game's round gauge when extracted
    local gx, gy = 120, 148
    local gauge = art("training/gauge_bg")
    if gauge then
      G2.setColor(1, 1, 1, 1)
      G2.draw(gauge, gx, gy, 0, 24 / 64, 24 / 64, 32, 32)
    else
      G2.setColor(0, 0, 0, 0.5)
      G2.circle("fill", gx, gy, 10, 20)
    end
    local full = sim.guts >= N.GUTS.FULL_AT
    G2.setColor(full and 1 or 0.98, full and 0.85 or 0.6, full and 0.3 or 0.15, 1)
    if sim.guts > 0.001 then
      G2.arc("fill", gx, gy, 9, -math.pi / 2, -math.pi / 2 + sim.guts * 2 * math.pi, 20)
    end
    G2.setColor(1, 1, 1, 0.8)
    G2.circle("line", gx, gy, 10, 20)
    if sim.bot and sim.bot.aura > 0 then
      local strip = art("training/caution")
      if strip then
        G2.setColor(1, 1, 1, 0.6 + 0.4 * math.abs(math.sin(sim.t * 10)))
        G2.draw(strip, 120, 32, 0, 1, 1, 64, 16)
        -- the texture is the strip's plain backing; the word goes on top
        drawText("CAUTION!", 96, 26, { maxWidth = 60, color = "white" })
      else
        G2.setColor(1, 0.2, 0.2, 0.9)
        G2.rectangle("fill", 80, 26, 80, 14, 3, 3)
        drawText("CAUTION!", 96, 28, { maxWidth = 60, color = "white" })
      end
    end
    if sim.phase == "countdown" then
      G2.setColor(0, 0, 0, 0.5)
      G2.rectangle("fill", 96, 60, 48, 28, 4, 4)
      drawText(tostring(math.max(1, math.ceil(sim.countdown))), 114, 66, { maxWidth = 20, color = "white" })
    end
  end

  function D.draw(G2, sim, s, T)
    if not sim then
      G2.setColor(0.1, 0.1, 0.15, 1)
      G2.rectangle("fill", 0, 0, 240, 160)
      return
    end
    drawBackground(G2, sim)
    drawBot(G2, sim)
    drawBalls(G2, sim)
    drawShots(G2, sim)
    drawPlayer(G2, sim, s)
    drawHud(G2, sim, s, T)
  end

  function D.drawResult(G2, s, T)
    local r = s.result
    G2.setColor(0.16, 0.2, 0.3, 1)
    G2.rectangle("fill", 0, 0, 240, 160)
    G2.setColor(1, 1, 1, 0.92)
    G2.rectangle("fill", 10, 22, 220, 128, 4, 4)
    if not r then return end
    local drawText = T.drawText
    -- the game's banner and ribbon
    local banner = art(r.clear and "training/banner_success" or "training/banner_tryagain")
    if banner then
      G2.setColor(1, 1, 1, 1)
      G2.draw(banner, 120, 18, 0, 0.6, 0.6, 128, 32)
    else
      drawText(r.clear and "Success!" or "Try Again...", 18, 8, { maxWidth = 204 })
    end
    local y = 38
    local function line(text) drawText(text, 18, y, { maxWidth = 204 }); y = y + 13 end
    line(r.courseName or "")
    if r.clear then
      line(("%s %s"):format(T.resultText("targetRemaining"), clock(r.remaining)))
      if r.medal then
        local medal = art("training/medal")
        if medal then G2.setColor(1, 1, 1, 1); G2.draw(medal, 200, y - 2, 0, 0.5, 0.5) end
        line(T.resultText("award"))
      else
        line(T.resultText("tryTarget"))
      end
      if r.newBest then line(T.resultText("newBest")) end
      if r.stat then
        local label = art("training/label_" .. r.stat)
        if label then G2.setColor(1, 1, 1, 1); G2.draw(label, 18, y - 1, 0, 0.7, 0.7) end
        drawText(("+%d  (%d/510)"):format(r.ev or 0, Rules.evTotal(s.evs)), label and 66 or 18, y, { maxWidth = 160 })
        y = y + 13
      end
    else
      line(T.resultText("failed"))
      line(("SCORE: %d"):format(r.total or 0))
    end
    if r.bag then
      local def = Rules.bag(r.bag)
      line(("%s %s%s"):format(T.resultText("bagsReceived"), T.bagName and T.bagName(r.bag) or (def and def.label or r.bag), r.bagKept and "" or " (no room)"))
    end
    if r.item then line(("%s %s%s"):format(T.resultText("itemsReceived"), r.item.name, r.item.given and "" or " (kept for later)")) end
    if r.unlockText then line(r.unlockText) end
    if r.fully then line(T.resultText("fullyNow")) end
    if r.supremely then line(T.resultText("supremelyNow")) end
    drawText("A: continue", 150, 136, { maxWidth = 80 })
  end

  return D
end
