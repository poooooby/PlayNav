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
  local PITCH_ROWS = { 0.2, 0.5, 0.8 }

  local function art(id)
    local A = D.assets
    if not A or A.enabled == false then return nil end
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
  local BAL_TEX, BAL_PPT = { 1, 1 }, { 1, 1 }   -- the uniforms' tables, reused every draw
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
      BAL_TEX[1], BAL_TEX[2] = pw, ph
      BAL_PPT[1], BAL_PPT[2] = math.max(1, out / tpu), math.max(1, out / tpu)
      sh:send("texSize", BAL_TEX)
      sh:send("pxPerTexel", BAL_PPT)
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

  -- the stadium (assets/stadiumlarge.png, a recreation of the scene, square so it
  -- reaches past the frame when the top screen fills the playfield): read once, drawn `w` units
  -- across with its grass line (`grassFrac` of its height) at `grassY`, where the trainee's
  -- stand floats; past its edges the edge texels stretch (clamp)
  D.BG = { file = "assets/stadiumlarge.png", w = 302.2, grassFrac = 1270 / 1920, grassY = 118.4,
    -- where the beaten balloon leaves the stadium and twinkles out: just above the roof's edge
    -- on the right (the edge is at y 470 of 1920 at x 1600), as fractions of the art
    exit = { x = 1600 / 1920, y = 425 / 1920 } }

  -- the area the top screen covers, in 240x160 units: T.topExtent while hd_top fills the
  -- playfield (x, y, w, h), else the frame
  local function extent(T)
    local e = T and T.topExtent
    if e then return e.x, e.y, e.w, e.h end
    return 0, 0, 240, 160
  end
  D.extent = extent

  -- A wide area (a second screen's whole 16:9 top display) frames the scene further back: the
  -- arena drawn smaller (z) about the middle of the area's foot, until the roof's edge where the
  -- beaten balloon leaves (D.BG.exit) and the star above it (VIEW_FIT.margin: the HUD band and sky for the flight over the roof) are under the
  -- top. The stadium art keeps its own size there and mirrors out to the sides (grown, it would
  -- lift the roof again). Areas nearer the frame's 3:2 keep the plain view (z 1).
  D.VIEW_FIT = { aspect = 1.6, margin = 70, min = 0.55 }
  local viewKey, viewZ = nil, 1
  local function artExitY(ey, eh)
    local W = D.BG.w
    local Hu = W   -- the art is square
    local gf, gy = D.BG.grassFrac, D.BG.grassY
    local k = math.max(1, (gy - ey) / (Hu * gf), (ey + eh - gy) / (Hu * (1 - gf)))
    return gy - (gf - D.BG.exit.y) * Hu * k
  end
  -- the view: z (1 = as drawn), and the pivot (px, py) on the area's foot
  local function view(T)
    local ex, ey, ew, eh = extent(T)
    local px, py = 120, ey + eh
    if ew / eh < D.VIEW_FIT.aspect then return 1, px, py end
    local key = ("%.2f %.2f %.2f %.2f"):format(ex, ey, ew, eh)
    if key ~= viewKey then
      local z = 1
      for _ = 1, 4 do
        local sy = py + (ey - py) / z
        local top = artExitY(sy, eh / z) - D.VIEW_FIT.margin
        z = math.max(D.VIEW_FIT.min, math.min(1, (py - ey) / (py - top)))
      end
      viewKey, viewZ = key, z
      -- for drivers and bug reports: the last view worked out
      D.lastView = { z = z, px = px, py = py, ex = ex, ey = ey, ew = ew, eh = eh }
    end
    return viewZ, px, py
  end
  D.view = view
  -- the area in scene units (what the arena draws to under the view)
  local function sceneExtent(T)
    local ex, ey, ew, eh = extent(T)
    local z, px, py = view(T)
    if z == 1 then return ex, ey, ew, eh end
    return px + (ex - px) / z, py + (ey - py) / z, ew / z, eh / z
  end
  -- a scene point to the screen, and back (the HUD's reticle, popups and aiming)
  function D.toScreen(T, x, y)
    local z, px, py = view(T)
    return px + (x - px) * z, py + (y - py) * z, z
  end
  local function bgImage()
    if D.bg == nil then
      D.bg = false
      local G, LI, LF = love and love.graphics, love and love.image, love and love.filesystem
      local bytes = mod.read and mod:read(D.BG.file)
      if G and LI and LF and bytes then
        local ok, img = pcall(function()
          local data = LI.newImageData(LF.newFileData(bytes, D.BG.file))
          local im = G.newImage(data, { mipmaps = true })
          im:setFilter("linear", "linear")
          im:setMipmapFilter("linear")
          im:setWrap("clamp", "clamp")
          return im
        end)
        if ok then D.bg = img end
      end
    end
    return D.bg or nil
  end

  -- where the art goes this frame: its top left (ix, iy) and units per texel (s), as large as
  -- it is, or larger where the area reaches past the art (a screen where the frame is small
  -- next to the area): grown about the grass line's middle, so the ground still meets the
  -- trainee's stand, rather than stretching the edge texels. iw, ih: the art's size (nil without it)
  local function bgPlace(T)
    local bg = bgImage()
    local ex, ey, ew, eh = sceneExtent(T)
    local iw, ih = 1920, 1920
    if bg then iw, ih = bg:getDimensions() end
    local W, Hu = D.BG.w, D.BG.w * ih / iw
    local gf, gy = D.BG.grassFrac, D.BG.grassY
    -- (framed back, the art does not grow to the width: it mirrors out to the sides)
    local wide = view(T) < 1
    local k = math.max(1, wide and 0 or 2 * (120 - ex) / W, wide and 0 or 2 * (ex + ew - 120) / W,
      (gy - ey) / (Hu * gf), (ey + eh - gy) / (Hu * (1 - gf)))
    local s = W * k / iw
    return 120 - W * k / 2, gy - ih * gf * s, s, iw, ih
  end
  -- a point of the art (fractions of its width / height) in 240x160 units this frame
  function D.bgPoint(T, fx, fy)
    local ix, iy, s, iw, ih = bgPlace(T)
    return ix + fx * iw * s, iy + fy * ih * s
  end
  -- the beaten balloon's way out: from where it hovers to just above the roof's edge
  -- (D.BG.exit), wherever that is on this screen, on it or not
  function D.exitOffset(sim, T)
    local bx, by = sim:botOffset()
    local cx, cy = Sim.project(bx, (sim.botCY and sim:botCY() or N.BOT.CY) + by, 1)
    local tx, ty = D.bgPoint(T, D.BG.exit.x, D.BG.exit.y)
    return tx - cx, ty - cy
  end

  local bgQuad, bgQuadKey = nil, nil
  local function drawBackground(G2, sim, T)
    local bg = bgImage()
    local ex, ey, ew, eh = sceneExtent(T)
    if bg then
      local ix, iy, s, iw, ih = bgPlace(T)
      -- one quad over the whole area, in image pixels; clamp stretches the edges past the art
      local qx, qy, qw, qh = (ex - ix) / s, (ey - iy) / s, ew / s, eh / s
      local key = ("%.2f %.2f %.2f %.2f"):format(qx, qy, qw, qh)
      if bgQuadKey ~= key then
        bgQuad = love.graphics.newQuad(qx, qy, qw, qh, iw, ih)
        bgQuadKey = key
      end
      -- framed back, the sides mirror the art out; else its edge texels stretch
      bg:setWrap(view(T) < 1 and "mirroredrepeat" or "clamp", "clamp")
      G2.setColor(1, 1, 1, 1)
      G2.draw(bg, bgQuad, ex, ey, 0, s, s)
      if sim and sim.bot and sim.bot.aura > 0 then
        G2.setColor(1, 0.2, 0.2, 0.15 + 0.15 * math.sin(sim.t * 20))
        G2.rectangle("fill", ex, ey, ew, eh)
      end
      return
    end
    G2.setColor(0.36, 0.6, 0.92, 1)
    G2.rectangle("fill", 0, 0, 240, 92)
    G2.setColor(0.55, 0.75, 0.98, 1)
    G2.rectangle("fill", 0, 60, 240, 32)
    G2.setColor(0.22, 0.62, 0.38, 1)
    G2.rectangle("fill", 0, 92, 240, 68)
    -- pitch lines (PITCH_ROWS hoisted: this runs every frame)
    G2.setColor(1, 1, 1, 0.25)
    for i = -2, 2 do
      local x0 = Sim.project(i * 0.5, 0, 0)
      local x1 = Sim.project(i * 0.5, 0, 1)
      G2.line(x0, 150, x1, 92)
    end
    for _, z in ipairs(PITCH_ROWS) do
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

  -- the balloon's shadow: on the far grass behind the trainee's stand (the stadium's grass
  -- starts near y 118), so it is never taken for the trainee's own
  D.BOT_SHADOW_Y = 124
  -- opts.noShadow: the caller draws the shadow on the grass; opts.noGoals: the goals are gone
  local function drawBot(G2, sim, opts)
    opts = opts or {}
    local bot = sim.bot
    if not bot then return end
    local bx, by = sim:botOffset()
    local cyW = sim.botCY and sim:botCY() or N.BOT.CY
    local sx, sy, k = Sim.project(bx, cyW + by, 1)
    local _, _, _, hwFar = Sim.view()
    local R = N.BOT.R * hwFar * bot.scale
    local fx = bot.flinch > 0 and math.sin(sim.t * 50) * 3 or 0
    -- shadow and aura
    local floorY = D.BOT_SHADOW_Y
    if not opts.noShadow then
      G2.setColor(0, 0, 0, 0.25)
      G2.ellipse("fill", sx, floorY, R * 0.9, 5)
    end
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
    for _, g in ipairs(opts.noGoals and {} or sim.goals) do
      local gx, gy = sim:goalPos(g)
      local px, py = Sim.project(gx, gy, 1)
      local gr = g.r * hwFar * bot.scale
      local rgb = GOAL_RGB[g.kind] or GOAL_RGB.white
      local pulse = (g.kind == "chance") and (1 + 0.06 * math.sin(sim.t * 8)) or 1
      -- the game's goal panes (upper.bclyt, 32x32): target01 (white) or big_target (red), its
      -- frames 0..8 from a ring to the grid as it appears; the barrier's marker its own
      local frame = math.min(8, math.floor((g.age or 1) * 30 / 2))
      local ring = (g.kind == "marker") and (art("lyt/st_hud/barrier_target") or art("training/marker"))
        or (g.kind == "chance" and (art("lyt/st_hud/big_target_" .. frame) or art(("training/big_target_%02d"):format(frame))))
        or art("lyt/st_hud/target01_" .. frame) or art(("training/target_%02d"):format(frame))
      if ring then
        local iw, ih = ring:getDimensions()
        local sc = (gr * 2 * pulse) / iw
        if g.kind == "fading" then G2.setColor(1, 0.9, 0.3, 1) else G2.setColor(1, 1, 1, 1) end
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

  -- the balls at the trainee: the game's soccer ball (target_ball00), growing as it comes (from
  -- N.ATTACK.BALL.FAR of its size at the balloon to its size at the trainee, and on past it up
  -- to the level's cap). A lobbed ball off the top of the screen shows where it will come down
  -- as a red shadow on the grass; back on screen it casts its own.
  local function ballRadius(sim, b)
    local B = N.ATTACK.BALL
    local hwNear = Sim.view()
    local pz = sim.player.z or 0.1
    local t = (1 - b.z) / math.max(0.05, 1 - pz)
    local far = B and B.FAR or 1
    local r = b.r * hwNear * (far + (1 - far) * t)
    if B then
      local lv = sim.isSecret and "secret" or sim.level
      r = math.min(r, (B.CAP[lv] or 1) * B.SPRITE_R * hwNear)
    end
    return math.max(1.5, r)
  end

  -- which = "behind" (still coming) or "front" (past the trainee), drawn either side of it
  local function drawBalls(G2, sim, which)
    local soccer = art("lyt/st_hud/target_ball00") or art("training/ball_00")
    local pz = sim.player.z or 0.1
    for _, b in ipairs(sim.balls) do
      local past = b.z < pz
      if which == nil or (which == "front") == past then
      local px, py, k = Sim.project(b.x, b.y, b.z)
      local rgb = BALL_RGB[b.kind] or BALL_RGB.small
      local _, fy = Sim.project(b.x, 0, b.z)
      if not (b.w or b.h) then
        local r = ballRadius(sim, b)
        if b.lob and py + r < 0 then
          -- off the top: where it will land, in red on the grass
          local lx, ly = Sim.project(b.lob.tx, 0, b.lob.tz)
          local pulse = 0.28 + 0.12 * math.sin(sim.t * 12)
          G2.setColor(1, 0.1, 0.1, pulse)
          G2.ellipse("fill", lx, ly, b.r * 118 * 1.2, 5)
          G2.setColor(1, 0.2, 0.2, pulse + 0.2)
          G2.ellipse("line", lx, ly, b.r * 118 * 1.2, 5)
        else
          G2.setColor(0, 0, 0, b.lob and 0.35 or 0.2)
          G2.ellipse("fill", px, fy, r * 0.9, math.max(2, r * 0.25))
          if soccer then
            local iw = soccer:getWidth()
            G2.setColor(1, 1, 1, 1)
            G2.draw(soccer, px, py, sim.t * 5 + (b.x or 0) * 3, (r * 2) / iw, (r * 2) / iw, iw / 2, iw / 2)
          else
            G2.setColor(0.95, 0.95, 0.95, 1)
            G2.circle("fill", px, py, r, 16)
            G2.setColor(0.1, 0.1, 0.1, 1)
            G2.circle("line", px, py, r, 16)
          end
        end
      else
      G2.setColor(0, 0, 0, 0.2)
      G2.ellipse("fill", px, fy, (b.w or b.r * 2) / 2 * 118 * k, 3)
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
  -- the opaque extent of a picture, or of one `quad` of it (x0, y0, x1, y1 exclusive, in the
  -- image's own units, from the image's top left), read back once; nil when it cannot be read
  -- or is empty
  local function opaqueBox(image, quad)
    local G = love and love.graphics
    if not (G and G.newCanvas and image) then return nil end
    local iw, ih = image:getDimensions()
    local qx, qy, qw, qh = 0, 0, iw, ih
    if quad then qx, qy, qw, qh = quad:getViewport() end
    local ok, data = pcall(function()
      local c = G.newCanvas(qw, qh, { dpiscale = 1 })
      G.push("all")
      G.setCanvas(c)
      G.origin()
      G.setShader()
      G.setBlendMode("alpha")
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      if quad then G.draw(image, quad, 0, 0) else G.draw(image, 0, 0) end
      G.pop()
      local d = c:newImageData()
      c:release()
      return d
    end)
    if not (ok and data) then return nil end
    local pw, ph = data:getDimensions()
    local x0, y0, x1, y1 = pw, ph, -1, -1
    for y = 0, ph - 1 do
      for x = 0, pw - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a > 0.1 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    data:release()
    if x1 < x0 then return nil end
    -- in the image's own units (a canvas with a dpiscale reports fewer units than pixels)
    local kx, ky = qw / pw, qh / ph
    return qx + x0 * kx, qy + y0 * ky, qx + (x1 + 1) * kx, qy + (y1 + 1) * ky
  end

  -- gen3-hd-sprites (optional): the spec a pic was tagged with by its provider, holding the
  -- full-resolution texture the battle would draw in its place (`texture`, `quad`, `scale`:
  -- texture px times scale = the pic's px); nil without the library or a tag
  local function hdTagOf(image)
    local ok, spec = pcall(function()
      local lib = mod.find and mod:find("gen3-hd-sprites")
      local ex = lib and lib.exports
      if not (type(ex) == "table" and type(ex.tagOf) == "function") then return nil end
      return ex.tagOf(image)
    end)
    if ok and type(spec) == "table" and spec.texture then return spec end
    return nil
  end

  -- The trainee's picture: the back pic, else the front. Drawn whole, measured once by its
  -- opaque pixels and drawn by that box with the feet at its bottom: a provider may paint a
  -- big Pokemon on a canvas larger than the 64x64 box it reports (g9-battle-sprites-gen3's back
  -- pics: Rapidash 76x78), or hand out a 64x64 stand-in cropped for the battle's overdraw and
  -- tagged (gen3-hd-sprites) with the full-resolution frame, which is then drawn instead
  -- (`k`: its px to the stand-in's). `sx, sy`: per-axis stretch of the art (not used).
  local function playerPic(s)
    if playerPics[s.key] == nil then
      local entry = host.backPic and host.backPic(s.mon) or nil
      if not (entry and entry.image) then entry = s.pic end
      if entry and entry.image then
        local image, quad, k, hd = entry.image, nil, 1, false
        local tag = hdTagOf(image)
        if tag then
          image, quad, k, hd = tag.texture, tag.quad, tag.scale or 1, true
        end
        local iw, ih = image:getDimensions()
        local x0, y0, x1, y1 = opaqueBox(image, quad)
        if not x0 then
          if quad then x0, y0, x1, y1 = quad:getViewport(); x1, y1 = x0 + x1, y0 + y1
          else x0, y0, x1, y1 = 0, 0, entry.w or iw, entry.h or ih end
        end
        local w, h = x1 - x0, y1 - y0
        local q = (love and love.graphics and (x0 > 0 or y0 > 0 or w < iw or h < ih))
          and love.graphics.newQuad(x0, y0, w, h, iw, ih) or nil
        playerPics[s.key] = { image = image, w = w, h = h, quad = q, x0 = x0, y0 = y0, k = k, hd = hd }
      else
        playerPics[s.key] = false
      end
    end
    return playerPics[s.key] or nil
  end

  -- for the driver: the player sprite's image, the part of it drawn (x0, y0, w, h) and its
  -- scale to the pic's px
  function D.debugPlayerPic(s)
    local pic = playerPic(s)
    if not pic then return nil end
    return pic.image, pic.x0 or 0, pic.y0 or 0, pic.w, pic.h, pic.k or 1
  end

  -- for the driver: what the player sprite resolved to
  function D.debugPlayer(s)
    local pic = playerPic(s)
    if not pic then return "nil" end
    local ok, w, h = pcall(pic.image.getDimensions, pic.image)
    return ("%s %sx%s as %dx%d%s"):format(type(pic.image), tostring(w), tostring(h), pic.w, pic.h,
      pic.hd and (" (gen3-hd-sprites frame, x%.3f)"):format(pic.k or 1) or "")
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

  D.PLAYER_SCALE = 0.8
  -- the hover board the trainee rides (assets/hoverboard.png, 114x34 pixel art):
  -- drawn at the sprite's scale, its middle 64 px under the sprite's 64 px frame, the feet
  -- FEET_Y px below its top; it hovers with a gentle bob
  -- scale: the whole board as wide as the sprite's 64 px frame (no bigger than the rider)
  D.BOARD = { file = "assets/hoverboard.png", cx = 57, feetY = 20, scale = 64 / 114, bob = 1.5, bobHz = 0.9,
    -- moving up tips the board back (more of its deck shows), down tips it forward; the rider
    -- leans with it. Eased, and added to the side-to-side lean, so diagonals do both.
    PITCH = 0.22, RIDER_PITCH = 0.06, EASE = 8 }
  local pitchState = setmetatable({}, { __mode = "k" })
  local function boardPitch(sim)
    local st = pitchState[sim]
    if not st then st = { t = sim.t, v = 0 }; pitchState[sim] = st end
    local dt = sim.t - st.t
    if dt < 0 or dt > 0.5 then dt = 0 end
    st.t = sim.t
    local want = (sim.player.mz or 0)
    st.v = st.v + (want - st.v) * math.min(1, dt * D.BOARD.EASE)
    return st.v
  end
  local function boardImage()
    if D.board == nil then
      D.board = false
      local G, LI, LF = love and love.graphics, love and love.image, love and love.filesystem
      local bytes = mod.read and mod:read(D.BOARD.file)
      if G and LI and LF and bytes then
        local ok, img = pcall(function()
          local im = G.newImage(LI.newImageData(LF.newFileData(bytes, D.BOARD.file)))
          im:setFilter("nearest", "nearest")
          return im
        end)
        if ok then D.board = img end
      end
    end
    return D.board or nil
  end

  local function drawPlayer(G2, sim, s)
    local p = sim.player
    local px, py, k = Sim.project(p.x, p.y or 0, p.z)
    k = k * D.PLAYER_SCALE
    local lift, hsx, hsy, lean, face = hopPose(sim)
    local board = boardImage()
    if board then
      -- on the board it does not hop: board and rider bob together
      lift, hsx, hsy = -math.sin(sim.t * 2 * math.pi * D.BOARD.bobHz) * D.BOARD.bob, 1, 1
    end
    -- its shadow on the grass below the stand
    local _, gy = Sim.project(p.x, 0, p.z)
    G2.setColor(0, 0, 0, 0.3)
    local high = 1 - 0.4 * math.min(1, (p.y or 0) / (N.PLAYER.Y_MAX or 0.7))
    if board then
      local bk = k * D.BOARD.scale
      G2.ellipse("fill", px, gy, D.BOARD.cx * 0.9 * bk * high, 6 * bk * high)
    else
      local shrink = (1 - 0.25 * (lift / math.max(1, D.HOP.HEIGHT))) * high
      G2.ellipse("fill", px, gy, 18 * k * shrink, 5 * k * shrink)
    end
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
    local feetY = py + 2 - lift * k
    if board then
      -- under the rider, rolling and pitching with it
      local pitch = boardPitch(sim)
      hsy = hsy * (1 - D.BOARD.RIDER_PITCH * pitch)
      G2.setColor(1, 1, 1, 1)
      local bk = k * D.BOARD.scale
      drawPixel(board, px, feetY, lean, bk, bk * (1 + D.BOARD.PITCH * pitch), D.BOARD.cx, D.BOARD.feetY)
    end
    if pic then
      local flash = p.stun > 0 and (math.floor(sim.t * 20) % 2 == 0)
      G2.setColor(1, 1, 1, flash and 0.4 or 1)
      -- scaled about its feet, so a squash flattens it onto the ground; a full-resolution
      -- frame (pic.k) at the size the pic would have had
      local y = feetY
      local ak = k * (pic.k or 1)
      if pic.quad then
        drawPixel(pic.image, pic.quad, px, y, lean, ak * hsx * face, ak * hsy, pic.w / 2, pic.h)
      else
        drawPixel(pic.image, px, y, lean, ak * hsx * face, ak * hsy, pic.w / 2, pic.h)
      end
    else
      G2.setColor(0.95, 0.6, 0.2, 1)
      G2.circle("fill", px, py - 14 * k, 12 * k, 16)
    end
    -- the reticle (the game's HUD draws its own)
    if s and s.hudReticle then return end
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

  -- the balloon's way out at the end: puffs of air behind it, a twinkle where it vanished
  -- (edge: the balloon's half width in px; the puffs trail from its lower left edge)
  local function drawPuffs(G2, x, y, k, t, scale, edge)
    scale = scale or 1
    local ex, ey = (edge or 0) * 0.85, (edge or 0) * 0.35
    for i = 1, 6 do
      local back = i * 0.09
      local a = math.max(0, 0.75 - back * 1.4) * (1 - k * 0.4)
      if a > 0 then
        local px = x - ex - 14 * i * (0.6 + k) * scale + math.sin(t * 7 + i) * 3 * scale
        local py = y + ey + 9 * i * (0.4 + k) * scale
        G2.setColor(1, 1, 1, a)
        G2.circle("fill", px, py, (6 + i * 1.6) * scale, 16)
      end
    end
  end

  -- ------- the game's air (fx/* textures, recipe kind "bch": battle effects' shared textures)
  -- streamline02f: 8 frames of 128x64, a puff curling away, white on black (ETC1, no alpha);
  -- circle01m: a soft round mask; kumo01m: cloud shading. Brightness is the alpha (the shader).
  -- sizes and distances in the balloon's half widths (its sprite's size on screen)
  D.AIR = {
    GUST_EVERY = 0.28, GUST_LIFE = 0.42, GUST_DIST = 0.7, GUST_SIZE = 0.38,   -- the leak's gusts
    BURST_N = 10, BURST_LIFE = 1.2, BURST_SIZE = 1.4,                        -- the burst's clouds
    TRAIL_EVERY = 0.05, TRAIL_LIFE = 0.9, TRAIL_SIZE = 0.9,                  -- the trail as it zips off
    ANGLES = { -0.35, 3.6, -1.1, 2.9, 0.2, -2.2, 3.3, -0.7 },                -- gusts' directions, in turn
  }
  local AIR_SRC = [[
    extern Image shade;
    extern number useShade;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      float a = max(p.r, max(p.g, p.b)) * p.a;
      vec3 rgb = color.rgb;
      if (useShade > 0.5) {
        // a cloud: a dense core under the soft mask, shaded grey by the cloud texture
        vec4 k = Texel(shade, tc);
        rgb = color.rgb * mix(0.7, 1.0, max(k.r, max(k.g, k.b)));
        a = clamp(a * 2.2, 0.0, 1.0);
      }
      return vec4(rgb, a * color.a);
    }
  ]]
  local function airShader()
    if D.airShader == nil then
      D.airShader = false
      local G = love and love.graphics
      if G and G.newShader then
        local ok, sh = pcall(G.newShader, AIR_SRC)
        if ok then D.airShader = sh end
      end
    end
    return D.airShader or nil
  end

  -- one frame of the gust flipbook (8 of 128x64, top to bottom)
  local function gustQuad(img, f)
    D.gustQuads = D.gustQuads or {}
    if not D.gustQuads[f] then
      D.gustQuads[f] = love.graphics.newQuad(0, f * 64, 128, 64, img:getDimensions())
    end
    return D.gustQuads[f]
  end

  -- the game's air sprites, when the import has them (else the drawn circles stand in)
  local function airArt()
    local streak, circle, kumo = art("fx/streamline02f"), art("fx/circle01m"), art("fx/kumo01m")
    local sh = airShader()
    if streak and circle and kumo and sh then return streak, circle, kumo, sh end
    return nil
  end

  -- the leak: gusts shoot off the balloon's edge, each a puff (the flipbook, curling away) at the
  -- head of a thin streak trailing back toward the balloon (the capture's first deflation)
  local function drawGusts(G2, x, y, t, scale, edge)
    local streak, _, _, sh = airArt()
    local A = D.AIR
    local first = math.max(0, math.floor((t - A.GUST_LIFE) / A.GUST_EVERY))
    for i = first, math.floor(t / A.GUST_EVERY) do
      local u = (t - i * A.GUST_EVERY) / A.GUST_LIFE
      if u >= 0 and u < 1 then
        local ang = A.ANGLES[i % #A.ANGLES + 1]
        local dx, dy = math.cos(ang), math.sin(ang)
        local ox, oy = x + dx * edge * 0.85, y + dy * edge * 0.6
        local dist = A.GUST_DIST * edge * (1 - (1 - u) * (1 - u))
        local hx, hy = ox + dx * dist, oy + dy * dist
        local fade = 1 - u
        -- the streak: a thin line from where it left to the puff, fading along its length
        G2.setColor(1, 1, 1, 0.7 * fade)
        G2.setLineWidth(math.max(0.8, edge * 0.03))
        G2.line(ox + dx * dist * 0.25, oy + dy * dist * 0.25, hx, hy)
        G2.setLineWidth(1)
        if streak and sh then
          local f = math.min(7, math.floor(u * 8))
          local w = A.GUST_SIZE * edge
          G2.setShader(sh)
          sh:send("useShade", 0)
          G2.setColor(1, 1, 1, 0.95)
          -- the puff points the way it flies (the flipbook's puffs rise: turn them onto the line)
          G2.draw(streak, gustQuad(streak, f), hx, hy, ang + math.pi / 2, w / 64, w / 64, 64, 32)
          G2.setShader()
        else
          G2.setColor(1, 1, 1, 0.8 * fade)
          G2.circle("fill", hx, hy, A.GUST_SIZE * edge * 0.2, 10)
        end
      end
    end
  end

  -- a cloud: the soft round mask, shaded by the cloud texture
  local function drawCloud(G2, x, y, px, a, rot)
    local _, circle, kumo, sh = airArt()
    if circle and sh then
      G2.setShader(sh)
      sh:send("useShade", 1)
      sh:send("shade", kumo)
      G2.setColor(1, 1, 1, a)
      G2.draw(circle, x, y, rot or 0, px / 64, px / 64, 32, 32)
      G2.setShader()
    else
      G2.setColor(1, 1, 1, a * 0.8)
      G2.circle("fill", x, y, px * 0.4, 16)
    end
  end

  -- the burst and the trail: a cluster of clouds where it burst, then clouds left behind on its
  -- way as it zips off (the capture's second deflation); the trail remembers where it passed
  local function drawBurst(G2, x, y, t, scale, edge)
    local A = D.AIR
    if t < A.BURST_LIFE then
      local u = t / A.BURST_LIFE
      -- on its trailing side (it zips off up and to the right): a dense cluster to its left
      D.burstAt = D.burstAt or { x = x, y = y, edge = edge }
      local e0 = D.burstAt.edge
      for i = 1, A.BURST_N do
        local ang = 2.2 + (i - 1) * 0.22
        local r = e0 * (0.55 + 0.75 * (1 - (1 - u) ^ 2)) * (0.75 + 0.35 * ((i * 37) % 10) / 10)
        local px = A.BURST_SIZE * e0 * (0.7 + 0.5 * u) * (0.8 + 0.4 * ((i * 53) % 10) / 10)
        drawCloud(G2, D.burstAt.x + math.cos(ang) * r, D.burstAt.y + math.sin(ang) * r * 0.8, px,
          u < 0.55 and 1 or (1 - u) / 0.45, i)
      end
    end
    -- the trail
    D.trail = D.trail or {}
    local last = D.trail[#D.trail]
    if not last or t - last.t >= A.TRAIL_EVERY then
      D.trail[#D.trail + 1] = { x = x, y = y, t = t, e = edge }
    end
    for _, p in ipairs(D.trail) do
      local u = (t - p.t) / A.TRAIL_LIFE
      if u < 1 then
        drawCloud(G2, p.x, p.y, A.TRAIL_SIZE * p.e * (0.6 + 0.6 * u), 0.9 * (1 - u), p.t * 7)
      end
    end
  end

  -- a new way out: forget the last one's burst and trail
  function D.resetAir()
    D.trail, D.burstAt = nil, nil
  end

  -- the star: its arms reach R0 + R * the swell, LINE thick, the centre DOT0 + DOT
  D.TWINKLE = { R0 = 5.5, R = 22, LINE = 1.7, DOT0 = 2, DOT = 2.8 }
  local function drawTwinkle(G2, x, y, k)
    local Tw = D.TWINKLE
    local a = math.sin(k * math.pi)
    local r = Tw.R0 + Tw.R * a
    G2.setColor(1, 1, 1, 0.9 * a)
    G2.setLineWidth(Tw.LINE)
    G2.line(x - r, y, x + r, y)
    G2.line(x, y - r, x, y + r)
    G2.line(x - r * 0.4, y - r * 0.4, x + r * 0.4, y + r * 0.4)
    G2.line(x - r * 0.4, y + r * 0.4, x + r * 0.4, y - r * 0.4)
    G2.circle("fill", x, y, Tw.DOT0 + Tw.DOT * a, 10)
    G2.setLineWidth(1)
  end

  function D.draw(G2, sim, s, T)
    if not sim then
      G2.setColor(0.1, 0.1, 0.15, 1)
      G2.rectangle("fill", 0, 0, 240, 160)
      return
    end
    local Hud = T and T.hud
    local pose = Hud and Hud.pose and Hud.pose(sim, s) or nil
    -- the view: the arena under it, in scene units (D.view); the HUD and the fades outside
    local vz, vpx, vpy = view(T)
    if vz < 1 then
      G2.push()
      G2.translate(vpx, vpy)
      G2.scale(vz, vz)
      G2.translate(-vpx, -vpy)
    end
    local ex, ey, ew, eh = sceneExtent(T)
    -- the intro's camera (hud.pose cam): the scene drawn zoomed about the flat balloon on the
    -- grass, which shows at the area's middle; as it settles (k -> 1) the focus moves to the
    -- middle itself, so zoom 1 is the plain view. The HUD and the fades stay outside it.
    local cam = pose and pose.cam
    if cam then
      local bx, by = sim:botOffset()
      local fx = Sim.project(bx, (sim.botCY and sim:botCY() or N.BOT.CY) + by, 1)
      local mx, my = ex + ew / 2, ey + eh / 2
      local k = cam.k or 0
      local Fx, Fy = fx + (mx - fx) * k, (D.BOT_SHADOW_Y - 6) + (my - D.BOT_SHADOW_Y + 6) * k
      G2.push()
      G2.translate(mx, my)
      G2.scale(cam.zoom, cam.zoom)
      G2.translate(-Fx, -Fy)
    end
    drawBackground(G2, sim, T)
    -- the stadium comes up out of the dark under the intro's title
    if pose and pose.veil and pose.veil > 0 then
      G2.setColor(0.0, 0.12, 0.14, 0.85 * pose.veil)
      G2.rectangle("fill", ex, ey, ew, eh)
      G2.setColor(0.2, 1, 0.8, 0.5 * pose.veil)
      for i = 0, 6 do
        local y = 92 + i * i * 2
        G2.line(ex, y, ex + ew, y)
      end
    end
    local b = pose and pose.bot
    if b then
      if (b.alpha or 1) > 0 then
        local bx, by = sim:botOffset()
        local cyW = sim.botCY and sim:botCY() or N.BOT.CY
        local cx, cy = Sim.project(bx, cyW + by, 1)
        local sx, sy = b.sx or b.scale or 1, b.sy or b.scale or 1
        local dy = b.dy or 0
        if b.ground then
          -- lying on the grass: its foot on the floor at its depth, floating up as it rises
          local _, _, _, hwFar = Sim.view()
          local halfH = ((sim.shape and sim.shape.halfH) or 1) * N.BOT.R * sim.bot.scale * hwFar
          local onGround = D.BOT_SHADOW_Y - halfH * sy
          dy = (onGround - cy) * (1 - (b.rise or 0))
        end
        dy = dy + (b.bob or 0)
        -- its shadow stays on the grass under it: as wide as it is, fading as it leaves
        local _, _, _, hwFar = Sim.view()
        local R = N.BOT.R * hwFar * sim.bot.scale
        local floorY = D.BOT_SHADOW_Y
        local shadowA = 0.25 * (b.shadow or 1) * (b.alpha or 1)
        if shadowA > 0.01 then
          G2.setColor(0, 0, 0, shadowA)
          G2.ellipse("fill", cx + (b.dx or 0), floorY, R * 0.9 * sx, 5 * math.min(1, sx))
        end
        local halfW = ((sim.shape and sim.shape.halfW) or 1) * R * sx
        local gameAir = airArt() and (b.leakT or b.burstT)
        if gameAir and b.burstT then
          -- the game's burst and its trail, behind the balloon
          drawBurst(G2, cx + (b.dx or 0), cy + dy, b.burstT, b.puffScale or 1, halfW)
        end
        G2.push()
        G2.translate(cx + (b.dx or 0), cy + dy)
        if b.rz then G2.rotate(b.rz) end
        G2.scale(sx, sy)
        G2.translate(-cx, -cy)
        drawBot(G2, sim, { noShadow = true, noGoals = b.noGoals })
        G2.pop()
        if gameAir then
          -- the leak's gusts come off its surface toward us: in front of it
          if b.leakT then drawGusts(G2, cx + (b.dx or 0), cy + dy, b.leakT, b.puffScale or 1, halfW) end
        elseif b.puffs then
          drawPuffs(G2, cx + (b.dx or 0), cy + dy, b.puffs, sim.t + (s.outro and s.outro.t or 0), b.puffScale, halfW)
        end
        if not b.burstT then D.resetAir() end
      end
    else
      drawBot(G2, sim)
    end
    if pose and pose.twinkle then
      local bx, by = sim:botOffset()
      local cx, cy = Sim.project(bx, (sim.botCY and sim:botCY() or N.BOT.CY) + by, 1)
      drawTwinkle(G2, cx + (pose.twinkle.dx or 85), cy + (pose.twinkle.dy or -110), pose.twinkle.k)
    end
    local last = sim.player.lastShot
    if last and sim.phase == "play" then
      local lx, ly = Sim.project(last.x, last.y, 1)
      local mark = art("lyt/st_hud/target02_c")
      if mark then
        local iw = mark:getWidth()
        local sc = 26 / iw
        G2.setColor(1, 1, 1, 0.75)
        G2.draw(mark, lx, ly, 0, sc, sc, iw / 2, mark:getHeight() / 2)
      else
        G2.setColor(1, 1, 1, 0.7)
        G2.rectangle("line", lx - 10, ly - 10, 20, 20)
      end
    end
    drawBalls(G2, sim, "behind")
    drawShots(G2, sim)
    if s then s.hudReticle = Hud and Hud.P ~= nil and Hud.sim == sim or nil end
    -- the trainee rides in from past the area's right edge (hud.pose playerIn: 0 off, 1 there)
    local enter = pose and pose.playerIn
    if enter and enter < 1 then
      if enter > 0 then
        local p = sim.player
        local px = Sim.project(p.x, p.y or 0, p.z)
        G2.push()
        G2.translate((ex + ew + 40 - px) * (1 - enter), 0)
        drawPlayer(G2, sim, s)
        G2.pop()
      end
    else
      drawPlayer(G2, sim, s)
    end
    drawBalls(G2, sim, "front")
    if cam then G2.pop() end
    if vz < 1 then G2.pop() end
    ex, ey, ew, eh = extent(T)
    if not (Hud and Hud.draw and Hud.draw(G2, sim, s)) then drawHud(G2, sim, s, T) end
    if pose and pose.fade and pose.fade > 0 then
      G2.setColor(0, 0, 0, pose.fade)
      G2.rectangle("fill", ex, ey, ew, eh)
    end
  end

  function D.drawResult(G2, s, T)
    local r = s.result
    G2.setColor(0.16, 0.2, 0.3, 1)
    G2.rectangle("fill", extent(T))
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
