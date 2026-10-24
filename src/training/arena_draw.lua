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

  -- The Balloon Bots' own sprites: every bot (Mega Aggron too) from one indexed atlas
  -- (tools/balloon_atlas.py: assets/balloon_bots.png, a 96x96 cell per bot holding colour
  -- numbers, 0 transparent; data/balloon_bots.lua the cells and their palettes). A cell is
  -- expanded to a full-colour image the first time its bot is asked for, so a regimen never
  -- depends on the game's own front sprites or a sprite mod's.
  local cellData, atlasData = nil, nil
  local botSprites = {}
  local function botCells()
    if cellData == nil then
      cellData = false
      local src = mod.read and mod:read("data/balloon_bots.lua")
      local chunk = src and load(src, "@data/balloon_bots.lua")
      local ok, t = false, nil
      if chunk then ok, t = pcall(chunk) end
      if ok and type(t) == "table" and type(t.cells) == "table" then cellData = t end
    end
    return cellData or nil
  end
  function D.botKey(row)
    return tostring(row.national) .. (row.mega and "-mega" or "")
  end
  -- pure: a "rrggbbaa" palette as { r, g, b, a } in 0..1
  function D.parsePalette(pal)
    local out = {}
    for i, hex in ipairs(pal or {}) do
      local r, g, b, a = hex:match("^(%x%x)(%x%x)(%x%x)(%x%x)$")
      out[i] = r and { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, tonumber(a, 16) / 255 }
        or { 0, 0, 0, 0 }
    end
    return out
  end
  -- the bot's sprite as { image, w, h }, or nil (no cell for it, or no graphics)
  function D.botSprite(row)
    if not row then return nil end
    local key = D.botKey(row)
    if botSprites[key] ~= nil then return botSprites[key] or nil end
    botSprites[key] = false
    local cells = botCells()
    local cell = cells and cells.cells[key]
    local G, LI, LF = love and love.graphics, love and love.image, love and love.filesystem
    if not (cell and G and LI and LF) then return nil end
    local ok, img = pcall(function()
      if not atlasData then
        local bytes = mod:read("assets/balloon_bots.png")
        atlasData = LI.newImageData(LF.newFileData(bytes, "balloon_bots.png"))
      end
      local size, y0 = cells.size, cell.row * cells.size
      local pal = D.parsePalette(cell.pal)
      local data = LI.newImageData(size, size)
      local A = atlasData
      data:mapPixel(function(x, y)
        local n = math.floor(A:getPixel(x, y0 + y) * 255 + 0.5)
        local c = pal[n]
        if not c then return 0, 0, 0, 0 end
        return c[1], c[2], c[3], c[4]
      end)
      local im = G.newImage(data)
      im:setFilter("nearest", "nearest")
      return im
    end)
    if not ok then
      mod.log:warn("super training: the Balloon Bot sprite for #%s could not be built (%s)", key, tostring(img))
      return nil
    end
    local entry = { image = img, w = cells.size, h = cells.size }
    botSprites[key] = entry
    return entry
  end

  function D.shapeFor(row)
    if not row then return nil end
    local key = D.botKey(row)
    if shapes[key] ~= nil then return shapes[key] or nil end
    shapes[key] = false
    -- the bot's own sprite; without the atlas, the game's (or a sprite mod's) front sprite
    local entry = D.botSprite(row)
    if not entry then
      -- course rows name species as constants ("SPECIES_BLASTOISE"); the pic wants the number
      local sp = host.speciesFromNational and row.national and host.speciesFromNational(row.national)
      if not sp and type(row.species) == "number" then sp = row.species end
      entry = sp and host.speciesFrontPic and host.speciesFrontPic(sp)
    end
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
  -- blown-up pixels stay square; `silhouette` 1 draws the flat outline colour. `puff` (the
  -- reach, in texels, of the inflation) shades it as a blown-up foil balloon: the alpha around
  -- each texel says how deep inside the outline it is (darker at the seams, fuller inside) and
  -- which way its edge faces (lit from the upper left, a glint on the bulges)
  local BALLOON_SRC = [[
uniform highp vec2 texSize;
uniform vec2 pxPerTexel;
uniform vec3 dark;
uniform vec3 light;
uniform float silhouette;
uniform float puff;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  highp vec2 texel = uv * texSize;
  highp vec2 base = floor(texel);
  vec2 d = fract(texel) - 0.5;
  vec2 region = 0.5 - 0.5 / pxPerTexel;
  vec2 f = (d - clamp(d, -region, region)) * pxPerTexel + 0.5;
  vec4 p = Texel(tex, (base + f) / texSize);
  float l = dot(p.rgb, vec3(0.299, 0.587, 0.114));
  vec3 c = mix(dark, light, smoothstep(0.02, 0.98, l));
  if (puff > 0.0 && silhouette < 0.5 && p.a > 0.0) {
    vec2 g = vec2(0.0);
    float s = 0.0;
    for (int i = 0; i < 12; i++) {
      float ang = float(i) * 0.5235988;
      vec2 dir = vec2(cos(ang), sin(ang));
      float a1 = Texel(tex, (texel + dir * puff * 0.4) / texSize).a;
      float a2 = Texel(tex, (texel + dir * puff) / texSize).a;
      s += a1 + a2;
      g += dir * (a1 + a2);
    }
    float inner = s / 24.0;
    float gl = length(g);
    float lit = gl > 0.01 ? dot(-g / gl, vec2(-0.6, -0.8)) * min(1.0, gl / 3.0) : 0.0;
    c *= mix(0.72, 1.06, smoothstep(0.4, 0.95, inner));
    c += vec3(0.28, 0.32, 0.36) * max(0.0, lit);
    c *= 1.0 - 0.3 * max(0.0, -lit);
    c += vec3(0.55) * smoothstep(0.45, 0.85, lit) * smoothstep(0.55, 0.8, inner);
  }
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

  -- the inflation's reach in sprite texels (BALLOON_SRC's `puff`), against the bot's radius
  D.PUFF = { texels = 7, minTexels = 3 }
  -- a glow round the balloon's own outline (the attack's warning): its silhouette spread
  -- GLOW.reach screen units out in GLOW.steps directions
  D.GLOW = { reach = 5, steps = 12 }
  -- draw the shape's sprite centred (its bbox centre) on (x, y), `ppx` screen units per
  -- sprite pixel, alpha a; glow (optional): r, g, b, a of a halo round its outline
  local function drawBalloon(G2, shape, x, y, ppx, a, gr, gg, gb, ga)
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
      sh:send("puff", math.max(D.PUFF.minTexels, D.PUFF.texels * shape.ppr * tpu / 40))
      G2.setShader(sh)
      sh:send("silhouette", 1)
      if ga and ga > 0 then
        -- the halo: the silhouette spread out round the outline, added
        G2.setBlendMode("add")
        G2.setColor(gr, gg, gb, ga * a / 3)
        local n, rr = D.GLOW.steps, D.GLOW.reach
        for i = 0, n - 1 do
          local ang = i / n * 2 * math.pi
          draw(math.cos(ang) * rr, math.sin(ang) * rr)
          draw(math.cos(ang) * rr * 0.5, math.sin(ang) * rr * 0.5)
        end
        G2.setBlendMode("alpha")
      end
      -- the outline: the silhouette nudged around it
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

  -- A wide area could frame the scene further back (the arena drawn smaller, z, about the
  -- middle of the area's foot, so the roof's edge where the beaten balloon leaves shows, the
  -- stadium art mirrored out to the sides). It is OFF (aspect huge, 2026-10-20, Wooble): on the
  -- Thor's 16:9 top screen it shrank the balloons, mirrored the art, and its aiming (the
  -- brackets stretched to the area, then back under the view) depended on the area's size, which
  -- a high-DPI screen measures differently, so shots landed low. At z 1 the arena keeps its
  -- size, the 302-unit art covers a 16:9 area's ~284 by itself, and aiming is the plain
  -- mapping. Set aspect back (1.6) to frame back again.
  D.VIEW_FIT = { aspect = math.huge, margin = 70, min = 0.55 }
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
  -- On a wide area (D.BG_FIT.aspect, the Thor's 16:9 top screen) the stadium art alone is drawn
  -- smaller, about the grass line (the trainee's stand stays on the ground), just enough that its
  -- top - the sky and the Poke Ball over the roof - reaches the area's top; its sides mirror out
  -- past it. The arena, the balloon and aiming keep their size (the view stays z 1); the
  -- beaten balloon's exit and twinkle are points of the art (D.bgPoint), so they come into frame
  -- with it. 2026-10-20, Wooble.
  D.BG_FIT = { aspect = 1.6 }
  local function bgShrinks(T)
    local _, _, ew, eh = sceneExtent(T)
    return eh > 0 and ew / eh >= D.BG_FIT.aspect
  end
  local function bgPlace(T)
    local bg = bgImage()
    local ex, ey, ew, eh = sceneExtent(T)
    local iw, ih = 1920, 1920
    if bg then iw, ih = bg:getDimensions() end
    local W, Hu = D.BG.w, D.BG.w * ih / iw
    local gf, gy = D.BG.grassFrac, D.BG.grassY
    local k
    if bgShrinks(T) or view(T) < 1 then
      -- as small as still covers the area from top to foot (the width mirrors)
      k = math.max((gy - ey) / (Hu * gf), (ey + eh - gy) / (Hu * (1 - gf)))
    else
      k = math.max(1, 2 * (120 - ex) / W, 2 * (ex + ew - 120) / W,
        (gy - ey) / (Hu * gf), (ey + eh - gy) / (Hu * (1 - gf)))
    end
    local s = W * k / iw
    return 120 - W * k / 2, gy - ih * gf * s, s, iw, ih
  end
  D.bgShrinks = bgShrinks
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
      -- drawn smaller on a wide area (or framed back), the sides mirror the art out; else its
      -- edge texels stretch
      bg:setWrap((bgShrinks(T) or view(T) < 1) and "mirroredrepeat" or "clamp", "clamp")
      G2.setColor(1, 1, 1, 1)
      G2.draw(bg, bgQuad, ex, ey, 0, s, s)
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

  end

  -- the balloon's shadow: on the far grass behind the trainee's stand (the stadium's grass
  -- starts near y 118), so it is never taken for the trainee's own
  D.BOT_SHADOW_Y = 124
  -- a plain party balloon's outline about (x, y), radius R: rounder on top, narrowing to the
  -- tie at the bottom (y + 1.1 R), for a bot with no sprite
  local BODY_PTS = {}
  local function balloonBody(x, y, R)
    local n = 28
    for i = 0, n - 1 do
      local t = i / n * 2 * math.pi
      local down = (1 - math.cos(t)) / 2          -- 0 at the top, 1 at the bottom
      BODY_PTS[i * 2 + 1] = x + math.sin(t) * R * 0.9 * (1 - 0.3 * down * down)
      BODY_PTS[i * 2 + 2] = y - math.cos(t) * R * (math.cos(t) < 0 and 1.1 or 0.95)
    end
    return BODY_PTS
  end

  local drawAura, drawShieldCage, drawCageShatter, drawClearPuffs
  -- a bitbot's string: `len` and end `sway` in its radii
  local BIT_STRING = { len = 1.6, sway = 0.25, segs = 10 }
  local BIT_PTS = {}
  -- a popped bitbot: ZIP_S darting about as the air goes (up ZIP_UP and aside ZIP_X radii,
  -- turning SPIN radians, down to SHRINK of its size, CRUMPLE its height), then FALL_S
  -- dropping at G units a second squared, fluttering FLUTTER_X radii at FLUTTER_HZ
  D.BIT_POP = { ZIP_S = 0.35, ZIP_UP = 1.2, ZIP_X = 0.8, SPIN = 9, SHRINK = 0.5, CRUMPLE = 0.75,
    FALL_S = 2.2, G = 260, FLUTTER_X = 0.6, FLUTTER_HZ = 1.4 }
  -- a purple party balloon about (x, y), radius r, its string waving on `ph`, turned rot,
  -- scaled sx / sy; flat 0..1 takes the air out of it (duller, no shine)
  local function drawBitBalloon(G2, x, y, r, ph, rot, sx, sy, flat)
    G2.push()
    G2.translate(x, y)
    G2.rotate(rot)
    G2.scale(sx, sy)
    local k = r * 0.22
    -- its string, hanging from the tie and waving
    local top = r * 1.1 + k
    for i = 0, BIT_STRING.segs do
      local u = i / BIT_STRING.segs
      BIT_PTS[i * 2 + 1] = math.sin(u * math.pi * 1.5 - ph * 1.3) * r * BIT_STRING.sway * u
      BIT_PTS[i * 2 + 2] = top + u * r * BIT_STRING.len
    end
    G2.setLineWidth(math.max(1, r * 0.07))
    G2.setColor(0.25, 0.08, 0.38, 0.9)
    G2.line(BIT_PTS)
    G2.setLineWidth(math.max(0.6, r * 0.035))
    G2.setColor(0.95, 0.92, 1, 0.95)
    G2.line(BIT_PTS)
    G2.setColor(0.42, 0.16, 0.62, 1)
    G2.polygon("fill", -k * 0.3, r * 1.05, k * 0.3, r * 1.05, k * 0.8, r * 1.1 + k, -k * 0.8, r * 1.1 + k)
    local d = 1 - 0.3 * flat
    G2.setColor(0.62 * d, 0.3 * d, 0.86 * d, 0.97)
    G2.polygon("fill", balloonBody(0, 0, r))
    G2.setColor(0.78 * d, 0.5 * d, 0.97 * d, 0.9 * (1 - 0.6 * flat))
    G2.polygon("fill", balloonBody(-r * 0.08, -r * 0.1, r * 0.72))
    if flat < 1 then
      G2.setColor(1, 1, 1, 0.75 * (1 - flat))
      G2.ellipse("fill", -r * 0.4, -r * 0.45, r * 0.13, r * 0.24)
    end
    G2.setColor(0.3, 0.08, 0.45, 1)
    G2.setLineWidth(math.max(1, r * 0.08))
    G2.polygon("line", balloonBody(0, 0, r))
    G2.setLineWidth(1)
    G2.pop()
  end

  -- the marked attack's aura (Wooble's Lv1 captures: Axew, Magnemite, Noibat): a magenta glow
  -- about 1.6 balloon radii out behind it, sparkles, and dark streaks rising through it in
  -- its last part; `a` its strength now
  D.AURA = { W = 1.45, H = 1.3, STREAKS = 11, RISE = 0.9 }
  -- (rw / rh: the balloon's half width / height on screen)
  function drawAura(G2, sim, x, y, rw, rh, a)
    local A = D.AURA
    local R = math.max(rw, rh)
    G2.push("all")
    G2.setBlendMode("add")
    for i = 5, 1, -1 do
      local k = i / 5
      G2.setColor(0.8, 0.12, 0.85, 0.2 * a)
      G2.ellipse("fill", x, y, rw * A.W * k, rh * A.H * k, 40)
    end
    G2.setBlendMode("alpha")
    G2.setLineWidth(math.max(1, R * 0.05))
    for i = 1, A.STREAKS do
      local u = (i - 0.5) / A.STREAKS
      local sx = x + (u - 0.5) * 2 * rw * A.W * 0.85
      local ph = (sim.t * A.RISE + i * 0.37) % 1
      local y0 = y + rh * A.H * (0.8 - 1.7 * ph)
      G2.setColor(0.25, 0.02, 0.3, 0.55 * a * math.sin(math.pi * ph))
      G2.line(sx, y0, sx, y0 - rh * 0.4)
    end
    G2.setColor(1, 0.8, 1, 0.8 * a)
    for i = 1, 6 do
      local ang = sim.t * 1.7 + i * 1.05
      local rr = 1.05 + 0.25 * math.sin(sim.t * 3 + i)
      G2.circle("fill", x + math.cos(ang) * rr * rw * A.W * 0.85, y + math.sin(ang) * rr * rh * A.H * 0.85, math.max(0.6, R * 0.03), 6)
    end
    G2.setLineWidth(1)
    G2.pop()
  end

  -- the balloon's shield (Wooble's Graveler capture): a cylinder of light round it from above
  -- its head to the grass, CAGE.W of its half width: pale cyan bars turning slowly with grid
  -- rings, a bright rim at the top, a white beam down the middle and a magenta glow rising from
  -- its foot, all added light (the balloon shows through)
  D.CAGE = { W = 1.4, TOP = 1.3, BARS = 18, RINGS = 4, SPIN = 0.25, GLOW = 0.38, RIM_RY = 0.13, TOP_GLOW = 0.16 }
  -- (fade: 1 standing, falling to 0 as it runs out)
  function drawShieldCage(G2, sim, cx, cy, rw, rh, fade)
    local C = D.CAGE
    local hw = rw * C.W
    local top, bottom = cy - rh * C.TOP, D.BOT_SHADOW_Y + 4
    local h = bottom - top
    local ry = hw * C.RIM_RY
    local flick = (0.9 + 0.1 * math.sin(sim.t * 13)) * (fade or 1)
    G2.push("all")
    G2.setBlendMode("add")
    -- the body of light, and the magenta glow at its foot (strips fading upward)
    G2.setColor(0.25, 0.6, 1, 0.13 * flick)
    G2.rectangle("fill", cx - hw, top, hw * 2, h)
    local n = 10
    for i = 0, n - 1 do
      local u = i / n
      G2.setColor(0.9, 0.12, 0.95, 0.45 * (1 - u) * (1 - u) * flick)
      G2.rectangle("fill", cx - hw, bottom - (u + 1 / n) * h * C.GLOW, hw * 2, h * C.GLOW / n + 0.5)
      -- the light along the top, fading down
      G2.setColor(0.4, 0.95, 1, 0.22 * (1 - u) * (1 - u) * flick)
      G2.rectangle("fill", cx - hw, top + u * h * C.TOP_GLOW, hw * 2, h * C.TOP_GLOW / n + 0.5)
    end
    G2.setColor(0.9, 0.2, 0.95, 0.45 * flick)
    G2.ellipse("fill", cx, bottom, hw, ry * 1.2, 40)
    -- the bars: round the cylinder, cyan above, pink toward the foot
    G2.setLineWidth(math.max(1, hw * 0.012))
    local spin = sim.t * C.SPIN
    for i = 0, C.BARS - 1 do
      local th = (i / C.BARS + spin) * 2 * math.pi
      local x = cx + hw * math.sin(th)
      local front = math.cos(th)
      local a = (0.3 + 0.2 * front) * flick
      local yt, yb = top + ry * front, bottom + ry * front
      local split = yt + (yb - yt) * 0.62
      for pass = 1, 2 do
        -- a soft wide glow, then the bar
        local k = pass == 1 and 0.35 or 1
        G2.setLineWidth(math.max(1, hw * (pass == 1 and 0.045 or 0.012)))
        G2.setColor(0.55, 0.95, 1, a * k)
        G2.line(x, yt, x, split)
        G2.setColor(0.95, 0.35, 1, a * k)
        G2.line(x, split, x, yb)
      end
    end
    -- the grid rings and the rim
    for k = 1, C.RINGS do
      local y = top + h * k / (C.RINGS + 1)
      local pink = k / (C.RINGS + 1) > 0.62
      if pink then G2.setColor(0.95, 0.4, 1, 0.22 * flick) else G2.setColor(0.6, 0.95, 1, 0.2 * flick) end
      G2.ellipse("line", cx, y, hw, ry, 40)
    end
    G2.setLineWidth(math.max(1, hw * 0.02))
    G2.setColor(0.45, 0.95, 1, 0.4 * flick)
    G2.ellipse("line", cx, top, hw, ry, 48)
    G2.setColor(0.3, 0.8, 1, 0.12 * flick)
    G2.ellipse("fill", cx, top, hw, ry, 48)
    -- the beam down the middle
    G2.setColor(1, 1, 1, 0.12 * flick)
    G2.rectangle("fill", cx - hw * 0.05, top, hw * 0.1, h)
    G2.setColor(1, 1, 1, 0.35 * flick)
    G2.setLineWidth(math.max(1, hw * 0.015))
    G2.line(cx, top, cx, bottom)
    G2.pop()
  end

  -- the shield shattering when its target is hit: a flash through the cylinder, then its bars
  -- broken into pieces flying out and falling, turning, fading over S (u 0..1 through it);
  -- run out instead, it fades over FADE_S
  D.CAGE_BREAK = { S = 0.9, FADE_S = 0.5, PIECES = 3, SPREAD = 0.9, FALL = 140 }
  function drawCageShatter(G2, sim, cx, cy, rw, rh, u)
    local C, B = D.CAGE, D.CAGE_BREAK
    local hw = rw * C.W
    local top, bottom = cy - rh * C.TOP, D.BOT_SHADOW_Y + 4
    local h = bottom - top
    G2.push("all")
    G2.setBlendMode("add")
    -- the flash
    local fa = math.max(0, 1 - u * 4)
    if fa > 0 then
      G2.setColor(0.7, 0.95, 1, 0.55 * fa)
      G2.rectangle("fill", cx - hw * (1 + u), top, hw * 2 * (1 + u), h)
      G2.setColor(1, 0.5, 1, 0.4 * fa)
      G2.ellipse("fill", cx, bottom, hw * (1 + u), hw * C.RIM_RY * 1.5, 40)
    end
    -- the pieces: each bar in PIECES lengths, out from the middle and down, turning
    local a = (1 - u) * (1 - u)
    G2.setLineWidth(math.max(1.2, hw * 0.02))
    for i = 0, C.BARS - 1 do
      local th = (i / C.BARS) * 2 * math.pi
      local side = math.sin(th)
      for k = 0, B.PIECES - 1 do
        local f0 = k / B.PIECES
        local len = h / B.PIECES * 0.8
        local seed = (i * 7 + k * 13) % 11 / 11
        local x = cx + hw * side * (1 + B.SPREAD * u * (0.6 + 0.8 * seed))
        local y = top + h * (f0 + 0.5 / B.PIECES) + B.FALL * u * u * (0.5 + seed) - 30 * u * (1 - seed)
        local rot = (seed - 0.5) * 5 * u + side * u
        local dx, dy = math.sin(rot) * len / 2, math.cos(rot) * len / 2
        if f0 < 0.6 then G2.setColor(0.6, 0.95, 1, 0.8 * a) else G2.setColor(1, 0.45, 1, 0.8 * a) end
        G2.line(x - dx, y - dy, x + dx, y + dy)
      end
    end
    G2.pop()
  end

  -- a cleared group's puffs (Wooble's magneton-2 capture): a white-green flash on both sides,
  -- streaks shooting out and down, then grey-white clouds lingering and fading, ~1.4 s
  D.CLEAR_PUFF = { S = 1.4, CLOUDS = 5, STREAKS = 5 }
  function drawClearPuffs(G2, e, x, y, rw, rh)
    local P = D.CLEAR_PUFF
    local u = e / P.S
    G2.push("all")
    for side = -1, 1, 2 do
      local bx = x + side * rw * 1.05
      if e < 0.25 then
        G2.setBlendMode("add")
        G2.setColor(0.85, 1, 0.85, 0.6 * (1 - e / 0.25))
        G2.ellipse("fill", bx + side * rw * 0.5, y, rw * 0.9, rh * 0.9, 24)
        G2.setBlendMode("alpha")
      end
      if e < 0.45 then
        local a = 1 - e / 0.45
        G2.setLineWidth(math.max(1, rw * 0.04))
        G2.setColor(0.9, 1, 0.6, 0.8 * a)
        for i = 1, P.STREAKS do
          local ang = math.rad(-10 + i * 12)
          local r0, r1 = rw * (0.2 + e * 2), rw * (0.6 + e * 3.5)
          G2.line(bx + side * math.cos(ang) * r0, y + math.sin(ang) * r0, bx + side * math.cos(ang) * r1, y + math.sin(ang) * r1)
        end
      end
      for i = 1, P.CLOUDS do
        local k = i / P.CLOUDS
        local cx = bx + side * rw * (0.2 + 0.9 * k) * (0.6 + 0.6 * u)
        local cy = y - rh * (0.2 - 0.5 * k) - rh * 0.3 * u
        G2.setColor(0.92, 0.94, 0.95, 0.55 * (1 - u) * (1 - u))
        G2.circle("fill", cx, cy, rw * (0.25 + 0.15 * k) * (0.7 + 0.8 * u), 16)
      end
    end
    G2.pop()
  end

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
    -- the attack's warning (a step the game marks): a magenta aura behind the balloon with dark
    -- streaks rising through it, and a glow round its outline
    local warn = bot.aura > 0 and 0.75 + 0.25 * math.sin(sim.t * 18) or 0
    local img, kind = botPic(bot)
    local shape = sim.shape and sim.shape.image and sim.shape or nil
    if warn > 0 then
      drawAura(G2, sim, sx + fx, sy, R * (shape and shape.halfW or 1), R * (shape and shape.halfH or 1), warn)
    end
    if shape then
      -- the Pokemon's own sprite as the balloon, at the same scale the goals use
      local x1 = Sim.project(1, cyW, 1)
      local x0 = Sim.project(0, cyW, 1)
      local unitPx = math.abs(x1 - x0)
      local rPx = N.BOT.R * bot.scale * unitPx
      local ppx = rPx / shape.ppr
      drawBalloon(G2, shape, sx + fx, sy, ppx, bot.flinch > 0 and 0.8 or 1, 0.95, 0.3, 1, warn)
    else
      -- no sprite: a plain party balloon, the badge or the front pic on it
      local body = balloonBody(sx + fx, sy, R)
      if warn > 0 then
        G2.setColor(0.95, 0.3, 1, 0.45 * warn)
        G2.polygon("fill", balloonBody(sx + fx, sy, R * 1.2))
        body = balloonBody(sx + fx, sy, R)
      end
      G2.setColor(0.45, 0.6, 1, 0.95)
      G2.polygon("fill", body)
      G2.setColor(1, 1, 1, 0.45)
      G2.ellipse("fill", sx + fx - R * 0.4, sy - R * 0.5, R * 0.16, R * 0.28)
      if img then
        local iw, ih = img:getDimensions()
        local scale = (2 * R) / math.max(iw, ih)
        G2.setColor(0.7, 0.85, 1, 1)
        local k = kind == "pic" and 0.9 or 1.2
        G2.draw(img, sx + fx, sy, 0, scale * k, scale * k, iw / 2, ih / 2)
      else
        G2.setColor(1, 1, 1, 0.9)
        G2.printf(("#%d"):format(bot.national or 0), sx - 30, sy - 6, 60, "center")
      end
      G2.setColor(0.25, 0.35, 0.7, 1)
      G2.polygon("line", balloonBody(sx + fx, sy, R))
    end
    -- a cleared group: puffs of air from both its sides (CLEAR_PUFF)
    if sim.clearPuffAt and sim.t - sim.clearPuffAt < D.CLEAR_PUFF.S then
      drawClearPuffs(G2, sim.t - sim.clearPuffAt, sx + fx, sy, R * (shape and shape.halfW or 1), R * (shape and shape.halfH or 1))
    end
    local cw, ch = R * (shape and shape.halfW or 1), R * (shape and shape.halfH or 1)
    if sim.barrier then
      drawShieldCage(G2, sim, sx + fx, sy, cw, ch)
    elseif sim.shieldBrokeAt and sim.t - sim.shieldBrokeAt < D.CAGE_BREAK.S then
      drawCageShatter(G2, sim, sx + fx, sy, cw, ch, (sim.t - sim.shieldBrokeAt) / D.CAGE_BREAK.S)
    elseif sim.shieldFadedAt and sim.t - sim.shieldFadedAt < D.CAGE_BREAK.FADE_S then
      drawShieldCage(G2, sim, sx + fx, sy, cw, ch, 1 - (sim.t - sim.shieldFadedAt) / D.CAGE_BREAK.FADE_S)
    end
    -- goals
    for _, g in ipairs(opts.noGoals and {} or sim.goals) do
      if g.hidden then goto nextgoal end
      local gx, gy = sim:goalPos(g)
      local px, py = Sim.project(gx, gy, 1)
      -- (goals keep their size as the balloon grows: they are the HUD's panes)
      local gr = g.r * hwFar
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
        -- orange once it is running out, see-through over its last FADE_S
        local fa = 1
        local tm = Sim.goalTimer and Sim.goalTimer(sim)
        local gone = tm and tm.gone or N.GOALS.GONE_AT
        local fadeS = math.min(N.GOALS.FADE_S or 1.5, (gone - (tm and tm.white or N.GOALS.YELLOW_AT)) * 0.33)
        if g.kind == "fading" and g.age >= gone - fadeS then fa = 0.4 end
        if g.kind == "marker" then
          -- the shield's target: glowing light, turning slowly and pulsing
          local mp = 1.25 * (1 + 0.08 * math.sin(sim.t * 7))
          -- (it fades in after the shield goes up)
          local ma = g.orbit and math.min(1, g.age / N.ATTACK.SHIELD.FADE_IN_S) or 1
          G2.setColor(1, 1, 1, ma)
          G2.draw(ring, px + fx, py, sim.t * 1.5, sc * mp, sc * mp, iw / 2, ih / 2)
          G2.setBlendMode("add")
          G2.setColor(1, 1, 1, 0.4 * ma)
          G2.draw(ring, px + fx, py, sim.t * 1.5, sc * mp * 1.12, sc * mp * 1.12, iw / 2, ih / 2)
          G2.setBlendMode("alpha")
        else
          if g.kind == "fading" then G2.setColor(1, 0.65, 0.2, fa) else G2.setColor(1, 1, 1, 1) end
          G2.draw(ring, px + fx, py, 0, sc, sc, iw / 2, ih / 2)
        end
      else
        G2.setLineWidth(2)
        G2.setColor(rgb[1], rgb[2], rgb[3], 0.95)
        G2.circle("line", px + fx, py, gr * pulse, 20)
        G2.setColor(rgb[1], rgb[2], rgb[3], 0.35)
        G2.circle("fill", px + fx, py, gr * 0.6 * pulse, 16)
        G2.setLineWidth(1)
      end
      ::nextgoal::
    end
    -- bits (the dead ones wait to regenerate); a popped one deflates and falls off the screen
    for _, bit in ipairs(sim.bits) do
      local px, py, kk = Sim.project(bit.x, bit.y, bit.z)
      local r = bit.r * 118 * kk
      local ph = sim.t * 2.2 + (bit.id or 0) * 1.7
      if not bit.dead then
        -- a purple party balloon, bobbing and swaying on its own beat
        drawBitBalloon(G2, px, py + math.sin(ph) * r * 0.08, r, ph, math.sin(ph * 0.7) * 0.12, 1, 1, 0)
        G2.setColor(0.2, 0.9, 0.3, 1)
        G2.rectangle("fill", px - r, py - r - 4, 2 * r * (bit.hp / N.ATTACK.bit.hp), 2)
      elseif bit.poppedAt then
        local P = D.BIT_POP
        local e = sim.t - bit.poppedAt
        if e < P.ZIP_S + P.FALL_S then
          local side = ((bit.id or 1) % 2 == 0) and 1 or -1
          local u = math.min(1, e / P.ZIP_S)
          -- the air rushing out: it darts up and about, spinning and shrinking
          local x = px + side * math.sin(u * math.pi * 1.5) * r * P.ZIP_X
          local y = py - r * P.ZIP_UP * math.sin(u * math.pi * 0.5)
          local rot = side * u * P.SPIN
          local sc = 1 - (1 - P.SHRINK) * u
          local wob = 1 + 0.25 * math.sin(e * 55) * (1 - u * 0.5)
          if e < P.ZIP_S then
            -- puffs of air from the tie, behind it
            G2.setColor(1, 1, 1, 0.6 * (1 - u))
            for i = 1, 3 do
              local back = i * r * 0.35
              G2.circle("fill", x - math.sin(rot) * (r * sc + back), y + math.cos(rot) * (r * sc + back), r * 0.18 * (1 - u * 0.5), 8)
            end
          else
            -- then the limp skin drops, fluttering side to side
            local f = e - P.ZIP_S
            x = x + math.sin(f * P.FLUTTER_HZ * 2 * math.pi) * r * P.FLUTTER_X
            y = y + 0.5 * P.G * f * f
            rot = rot + math.sin(f * P.FLUTTER_HZ * 2 * math.pi + 1) * 0.7
            wob = 1
          end
          drawBitBalloon(G2, x, y, r, ph, rot, sc * wob, sc * P.CRUMPLE / wob, u)
        end
      end
    end
  end

  -- the balls at the trainee: the game's soccer ball (target_ball00), growing as it comes (from
  -- N.ATTACK.BALL.FAR of its size at the balloon to its size at the trainee, and on past it up
  -- to the level's cap). A lobbed ball off the top of the screen shows where it will come down
  -- as a red shadow on the grass; back on screen it casts its own.
  -- the game's projectiles drawn as its camera shows them (Wooble's Lv1 captures): ~17 px across
  -- of its 400 at launch for a size-4.8 ball (PX_PER_UNIT of radius here a unit of its size),
  -- GROW times that at the trainee, 1 / size falling evenly with the depth flown (perspective)
  -- (a ball past the trainee grows no more and is gone PAST_FADE_S after it crossed, whatever
  -- its speed, rather than swelling over the camera)
  local GD = N.ATTACK.GAME and N.ATTACK.GAME.DRAWN or { PX_PER_UNIT = 1.06, GROW = 13 }
  D.GAME_BALL = { PX_PER_UNIT = GD.PX_PER_UNIT, GROW = GD.GROW, PAST = 1, PAST_FADE_S = 0.1 }
  local function gameBallRadius(sim, b)
    local G = D.GAME_BALL
    local pz = sim.player.z or 0.1
    local u = math.min(G.PAST, math.max(0, (1 - b.z) / math.max(0.05, 1 - pz)))
    local r0 = math.max(b.gsx or b.game.sx or 0, b.gsy or b.game.sy or 0) * G.PX_PER_UNIT
    local r1 = r0 * G.GROW
    local inv = (1 - u) / r0 + u / r1
    return math.max(1.5, 1 / math.max(inv, 1 / (r1 * 3)))
  end
  local function ballRadius(sim, b)
    if b.game and D.GAME_BALL then return gameBallRadius(sim, b) end
    local B = N.ATTACK.BALL
    local hwNear = Sim.view()
    local pz = sim.player.z or 0.1
    local t = (1 - b.z) / math.max(0.05, 1 - pz)
    local far = B and B.FAR or 1
    local r = b.r * hwNear * (far + (1 - far) * t)
    if B then
      -- (the game's own projectiles keep their sizes: its giants are meant to be giant)
      local lv = sim.isSecret and "secret" or sim.level
      local cap = b.game and 4 or (B.CAP[lv] or 1)
      r = math.min(r, cap * B.SPRITE_R * hwNear)
    end
    return math.max(1.5, r)
  end

  -- how near a ball is (Sim:ballEta: its arrival, and whether it would hit the trainee standing
  -- still): over its last SHADOW_S each incoming ball casts a shadow on the trainee's line where
  -- it will cross, darkening as it comes, with a ring closing in on it from RING_FROM times its
  -- size (red when the spot is on the trainee); over its last BLINK_S a ball that would hit
  -- blinks a red outline BLINK_HZ times a second and the trainee's own shadow blinks red with it.
  -- Sizes in screen units, at least MIN_SHADOW / MIN_RING across, so a small ball's still show.
  D.WARN = { SHADOW_S = 1.5, BLINK_S = 0.5, BLINK_HZ = 7, RED = { 0.95, 0.08, 0.08 },
    MIN_SHADOW = 7, MIN_RING = 6, RING_W = 1.6, RING_FROM = 3 }
  local function ballWarn(sim, b)
    if not sim.ballEta then return nil, false end
    return sim:ballEta(b)
  end
  local function blinkOn(sim)
    return math.floor(sim.t * D.WARN.BLINK_HZ * 2) % 2 == 0
  end
  -- every incoming ball's arrival spot on the trainee's line: `over` false draws the shadows
  -- and the rings of balls that miss (under the trainee), true the rings of balls that would
  -- hit (over it, else its board hides them)
  local function drawLandings(G2, sim, over)
    local W = D.WARN
    local pz = sim.player.z or 0.1
    for _, b in ipairs(sim.balls) do
      if b.z >= pz and not b.bounced and not b.lob then
        local eta, hits, x = ballWarn(sim, b)
        if eta and eta <= W.SHADOW_S then
          local u = 1 - eta / W.SHADOW_S
          local lx, ly, k = Sim.project(x, 0, pz)
          local rx = math.max(W.MIN_SHADOW, (b.w or b.r * 2) / 2 * 118 * k)
          local ry = rx * 0.3
          local R = hits and W.RED or nil
          if not over then
            if R then G2.setColor(R[1], R[2], R[3], 0.2 + 0.5 * u) else G2.setColor(0, 0, 0, 0.12 + 0.3 * u) end
            G2.ellipse("fill", lx, ly, rx * (0.6 + 0.4 * u), ry * (0.6 + 0.4 * u))
          end
          if (R ~= nil) == (over == true) then
            -- the ring closing in on it as the ball comes
            local ring = 1 + (W.RING_FROM - 1) * (1 - u)
            G2.setLineWidth(math.max(1, ry * (R and 0.4 or 0.3)))
            if R then G2.setColor(1, 0.2, 0.15, 0.45 + 0.55 * u) else G2.setColor(1, 1, 1, 0.2 + 0.35 * u) end
            G2.ellipse("line", lx, ly, rx * ring, ry * ring)
            G2.setLineWidth(1)
          end
        end
      end
    end
  end
  -- the red outline round a ball about to hit
  local function ballBlink(G2, sim, x, y, rx, ry, eta, hits)
    if not (hits and eta and eta <= D.WARN.BLINK_S and blinkOn(sim)) then return end
    local W = D.WARN
    local R = W.RED
    G2.setLineWidth(math.max(W.RING_W, rx * 0.22))
    G2.setColor(R[1], R[2], R[3], 0.95)
    G2.ellipse("line", x, y, math.max(W.MIN_RING, rx * 1.18 + 1), math.max(W.MIN_RING, ry * 1.18 + 1))
    G2.setColor(R[1], R[2], R[3], 0.35)
    G2.ellipse("fill", x, y, math.max(W.MIN_RING, rx * 1.18 + 1), math.max(W.MIN_RING, ry * 1.18 + 1))
    G2.setLineWidth(1)
  end
  -- the soonest ball that would hit the trainee where it stands (for its shadow), or nil
  function D.soonestHit(sim)
    local best
    for _, b in ipairs(sim.balls or {}) do
      local eta, hits = ballWarn(sim, b)
      if hits and eta and (not best or eta < best) then best = eta end
    end
    return best
  end

  -- each ball image's opaque extent (its art has margins), measured once
  local ballExtent = setmetatable({}, { __mode = "k" })

  -- which = "behind" (still coming) or "front" (past the trainee), drawn either side of it
  local function drawBalls(G2, sim, which)
    local soccer = art("lyt/st_hud/target_ball00") or art("training/ball_00")
    local pz = sim.player.z or 0.1
    if which ~= nil and sim.phase == "play" then drawLandings(G2, sim, which == "front") end
    for _, b in ipairs(sim.balls) do
      local past = b.z < pz
      -- past the trainee: gone in a moment
      local fade = 1
      if past and not b.bounced then
        -- (a lob flies its arc with no vz: its depth at ~0.7 a second)
        local vz = (b.lob or not b.vz or b.vz == 0) and 0.7 or math.abs(b.vz)
        local since = (pz - b.z) / vz
        fade = math.max(0, 1 - since / D.GAME_BALL.PAST_FADE_S)
      end
      if (which == nil or (which == "front") == past) and fade > 0 then
      local px, py, k = Sim.project(b.x, b.y, b.z)
      local rgb = BALL_RGB[b.kind] or BALL_RGB.small
      local _, fy = Sim.project(b.x, 0, b.z)
      local eta, hits = nil, false
      if not past then eta, hits = ballWarn(sim, b) end
      if not (b.w or b.h) or b.game then
        local r = ballRadius(sim, b)
        -- the game's tall / wide balls: the soccer ball stretched to their shape; a homing
        -- ball is blue and black (Wooble)
        local ax, ay = 1, 1
        local P = b.game
        local gsx, gsy = b.gsx or (P and P.sx), b.gsy or (P and P.sy)
        if gsx and gsy and gsx ~= gsy then
          local m = math.max(gsx, gsy)
          ax, ay = gsx / m, gsy / m
        end
        -- blue and black: the homing kinds the game colours (both ways, or a strong pull one
        -- way); Golem's pillars pull weakly up and down only and stay black
        local homing = P and Sim.homes(P)
        if b.lob and py + r < 0 then
          -- off the top: where it will land, in red on the grass
          local lx, ly = Sim.project(b.lob.tx, 0, b.lob.tz)
          local pulse = 0.28 + 0.12 * math.sin(sim.t * 12)
          G2.setColor(1, 0.1, 0.1, pulse)
          G2.ellipse("fill", lx, ly, b.r * 118 * 1.2, 5)
          G2.setColor(1, 0.2, 0.2, pulse + 0.2)
          G2.ellipse("line", lx, ly, b.r * 118 * 1.2, 5)
        else
          G2.setColor(0, 0, 0, (b.lob and 0.35 or 0.2) * fade)
          G2.ellipse("fill", px, fy, r * 0.9, math.max(2, r * 0.25))
          if soccer then
            local iw = soccer:getWidth()
            -- a ball knocked back off the shield glows cyan
            -- (the game's balls: white at Lv1, black with grey panels from Lv2 on, blue and black
            -- when they home; a bitbot's stay white)
            local dark = P and (sim.isSecret or (sim.level or 1) >= 2)
            if b.bounced then G2.setColor(0.55, 1, 1, 1)
            elseif homing then G2.setColor(0.3, 0.5, 1, fade)
            elseif dark then G2.setColor(0.42, 0.44, 0.48, fade)
            else G2.setColor(1, 1, 1, fade) end
            -- (a stretched one does not spin, so its shape reads)
            local spin = (ax == 1 and ay == 1) and (sim.t * 5 + (b.x or 0) * 3) or 0
            -- the ball itself (not its image, which has margins) is 2r across: its hitbox
            local ext = ballExtent[soccer]
            if ext == nil then
              local x0, y0, x1, y1
              if D.opaqueBox then x0, y0, x1, y1 = D.opaqueBox(soccer) end
              ext = x0 and { w = math.max(x1 - x0, y1 - y0), cx = (x0 + x1) / 2, cy = (y0 + y1) / 2 }
                or { w = iw, cx = iw / 2, cy = iw / 2 }
              ballExtent[soccer] = ext
            end
            G2.draw(soccer, px, py, spin, (r * 2) / ext.w * ax, (r * 2) / ext.w * ay, ext.cx, ext.cy)
          else
            if homing then G2.setColor(0.3, 0.45, 0.95, fade) else G2.setColor(0.95, 0.95, 0.95, fade) end
            G2.ellipse("fill", px, py, r * ax, r * ay, 16)
            G2.setColor(0.1, 0.1, 0.1, fade)
            G2.ellipse("line", px, py, r * ax, r * ay, 16)
          end
          ballBlink(G2, sim, px, py, r * ax, r * ay, eta, hits)
        end
      else
      G2.setColor(0, 0, 0, 0.2)
      G2.ellipse("fill", px, fy, (b.w or b.r * 2) / 2 * 118 * k, 3)
      G2.setColor(rgb[1], rgb[2], rgb[3], fade)
      if b.w or b.h then
        G2.ellipse("fill", px, py, (b.w or b.r * 2) / 2 * 118 * k, (b.h or b.r * 2) / 2 * 70 * k)
      else
        G2.circle("fill", px, py, b.r * 118 * k, 16)
      end
      G2.setColor(1, 1, 1, 0.7)
      if not (b.w or b.h) then G2.circle("line", px, py, b.r * 118 * k, 16) end
      ballBlink(G2, sim, px, py, (b.w or b.r * 2) / 2 * 118 * k, (b.h or b.r * 2) / 2 * ((b.w or b.h) and 70 or 118) * k, eta, hits)
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
  D.opaqueBox = opaqueBox

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

  -- the trainee and its board stay solid, and turn see-through (`RIDER_SEE` opacity) only while
  -- they cover something that matters - a goal or a live bit to aim at, or an attack on its
  -- way in - so a big sprite never hides one; eased both ways at `RIDER_FADE_PER_S`. Whole
  -- through the intro. The balloon's body does not count: a big one covers most of the screen.
  D.RIDER_SEE, D.RIDER_FADE_PER_S, D.RIDER_PAD = 0.38, 4, 2
  local riderA = setmetatable({}, { __mode = "k" })   -- sim -> { a, t }

  -- does the screen rect x0..x1, y0..y1 (the rider's) touch a goal or a live bit as drawn?
  function D.riderCovers(sim, x0, y0, x1, y1)
    local function touches(cx, cy, r)
      local nx = math.max(x0, math.min(x1, cx))
      local ny = math.max(y0, math.min(y1, cy))
      return (cx - nx) ^ 2 + (cy - ny) ^ 2 <= r * r
    end
    local bot = sim.bot
    if bot and sim.goals then
      local _, _, _, hwFar = Sim.view()
      for _, g in ipairs(sim.goals) do
        if not g.dead then
          local gx, gy = sim:goalPos(g)
          local cx, cy = Sim.project(gx, gy, 1)
          if touches(cx, cy, g.r * hwFar * bot.scale + D.RIDER_PAD) then return true end
        end
      end
    end
    for _, bit in ipairs(sim.bits or {}) do
      if not bit.dead then
        local cx, cy, kk = Sim.project(bit.x, bit.y, bit.z)
        if touches(cx, cy, bit.r * 118 * kk + D.RIDER_PAD) then return true end
      end
    end
    -- an attack still on its way (not yet past the trainee), to be seen and blocked
    local pz = sim.player and sim.player.z or 0.1
    for _, b in ipairs(sim.balls or {}) do
      if (b.z or 1) > pz then
        local cx, cy = Sim.project(b.x, b.y, b.z)
        if touches(cx, cy, ballRadius(sim, b) + D.RIDER_PAD) then return true end
      end
    end
    return false
  end

  -- the rider's opacity this frame, eased toward RIDER_SEE while it covers a target, else 1
  function D.riderAlpha(sim, x0, y0, x1, y1)
    if not sim or sim.phase == "countdown" then return 1 end
    local st = riderA[sim]
    if not st then st = { a = 1, t = sim.t or 0 }; riderA[sim] = st end
    local dt = math.max(0, math.min(0.1, (sim.t or 0) - st.t))
    st.t = sim.t or 0
    local want = (x0 and D.riderCovers(sim, x0, y0, x1, y1)) and D.RIDER_SEE or 1
    local step = D.RIDER_FADE_PER_S * dt
    if st.a < want then st.a = math.min(want, st.a + step) else st.a = math.max(want, st.a - step) end
    D.lastRider = { a = st.a, covers = want < 1, x0 = x0, y0 = y0, x1 = x1, y1 = y1 }   -- for drivers
    return st.a
  end

  -- the Charged Shot's fire, drawn: tongues of flame rising over the rider's box (w x h, feet at
  -- fx, fy), flickering; stage 2 taller, wider and orange at the edges. Added light.
  local drawFire, drawSmoke, drawShield, drawShatter
  -- the shield (Wooble's capture 2026-10-23_17-28-44): a see-through green dome of hexagons
  -- round the trainee and its stand, flaring bright as a stopped ball breaks it; the shatter a
  -- white-pink flash and hexagon pieces drifting out and up
  D.SHIELD = { HEX = 9, PAD = 1.6, ALPHA = 0.42, PIECES = 12 }
  local function hexagon(G2, x, y, r, mode)
    G2.polygon(mode or "line", x + r, y, x + r / 2, y - r * 0.866, x - r / 2, y - r * 0.866,
      x - r, y, x - r / 2, y + r * 0.866, x + r / 2, y + r * 0.866)
  end
  local function domeBox(fx, fy, w, h, k)
    local S = D.SHIELD
    local rx = math.max(w, 26 * k) / 2 * S.PAD
    local ry = math.max(h, 30 * k) / 2 * S.PAD
    return fx, fy - ry * 0.85, rx, ry
  end
  function drawShield(G2, sim, fx, fy, w, h, k, breakT)
    local S = D.SHIELD
    local cx, cy, rx, ry = domeBox(fx, fy, w, h, k)
    local flare = breakT and (1 - breakT / (N.BLOCK.BREAK_F / N.CHARGE.FPS)) or 0
    local a = S.ALPHA + 0.35 * flare + 0.08 * math.sin(sim.t * 9)
    G2.push("all")
    G2.stencil(function() G2.ellipse("fill", cx, cy, rx, ry, 32) end, "replace", 1)
    G2.setStencilTest("greater", 0)
    G2.setBlendMode("add")
    G2.setColor(0.25, 0.9, 0.55, 0.12 + 0.25 * flare)
    G2.ellipse("fill", cx, cy, rx, ry, 32)
    -- the net itself in front of the trainee: drawn over it, not added light
    G2.setBlendMode("alpha")
    local hr = S.HEX * k
    G2.setLineWidth(math.max(1.2, 1.1 * k))
    G2.setColor(0.35 + 0.5 * flare, 0.95, 0.55 + 0.3 * flare, math.min(1, a + 0.3))
    local dx, dy = hr * 1.5, hr * 1.732
    local row = 0
    for y = cy - ry - dy, cy + ry + dy, dy / 2 do
      local off = (row % 2) * dx / 2
      for x = cx - rx - dx + off, cx + rx + dx, dx do hexagon(G2, x, y, hr * 0.95) end
      row = row + 1
    end
    G2.setStencilTest()
    G2.setColor(0.6, 1, 0.8, a)
    G2.ellipse("line", cx, cy, rx, ry, 32)
    G2.pop()
  end
  function drawShatter(G2, sim, fx, fy, w, h, k, left)
    local S = D.SHIELD
    local cx, cy, rx, ry = domeBox(fx, fy, w, h, k)
    local u = 1 - math.max(0, math.min(1, left / N.BLOCK.SHATTER_S))
    G2.push("all")
    G2.setBlendMode("add")
    -- the flash
    local fa = math.max(0, 1 - u * 2.5)
    G2.setColor(1, 0.75, 0.9, 0.6 * fa)
    G2.ellipse("fill", cx, cy, rx * (1 + 0.3 * u), ry * (1 + 0.3 * u), 32)
    G2.setColor(1, 1, 1, 0.5 * fa)
    G2.ellipse("fill", cx, cy, rx * 0.6, ry * 0.6, 24)
    -- the pieces
    G2.setLineWidth(math.max(1, 0.9 * k))
    for i = 0, S.PIECES - 1 do
      local ang = i / S.PIECES * 2 * math.pi + 0.4
      local d = 0.7 + 0.9 * u
      local x = cx + math.cos(ang) * rx * d
      local y = cy + math.sin(ang) * ry * d - u * 24 * k
      G2.setColor(0.7, 1, 0.85, 0.8 * (1 - u))
      hexagon(G2, x, y, S.HEX * k * (0.8 - 0.4 * u))
    end
    G2.pop()
  end
  D.FIRE = { TONGUES = 7, HEIGHT = { 1.05, 1.45 }, WIDTH = { 1.0, 1.3 }, ALPHA = { 0.55, 0.7 } }
  local FIRE_OUTER = { { 1, 0.92, 0.3 }, { 1, 0.5, 0.08 } }
  local FIRE_INNER = { { 1, 1, 0.7 }, { 1, 0.9, 0.35 } }
  local function tongue(G2, x, base, w, h, lean)
    G2.polygon("fill", x - w, base, x - w * 0.55, base - h * 0.45, x + lean * w, base - h,
      x + w * 0.55, base - h * 0.45, x + w, base)
  end
  function drawFire(G2, sim, fx, fy, w, h, k, stage)
    local F = D.FIRE
    local st = math.min(2, stage)
    local W, H = math.max(w, 18 * k) * F.WIDTH[st], math.max(h, 24 * k) * F.HEIGHT[st]
    local t = sim.t
    G2.push("all")
    G2.setBlendMode("add")
    for layer = 1, 2 do
      local col = layer == 1 and FIRE_OUTER[st] or FIRE_INNER[st]
      local sc = layer == 1 and 1 or 0.62
      for i = 0, F.TONGUES - 1 do
        local u = (i + 0.5) / F.TONGUES - 0.5
        local flick = 0.75 + 0.25 * math.sin(t * (9 + i * 1.7) + i * 2.1)
        local hi = H * sc * (1 - 1.3 * u * u) * flick
        local x = fx + u * W * 0.9 * sc
        G2.setColor(col[1], col[2], col[3], F.ALPHA[st] * (layer == 1 and 0.75 or 0.9))
        tongue(G2, x, fy + 2 * k, W / F.TONGUES * 0.85 * sc, hi, 0.35 * math.sin(t * 6 + i))
      end
    end
    G2.pop()
  end
  -- the smoke after a fizzle: grey puffs drifting up and fading over the stop (`left` seconds)
  function drawSmoke(G2, sim, fx, fy, w, h, k, left)
    local total = N.CHARGE.STUN_F / N.CHARGE.FPS
    local u = 1 - math.max(0, math.min(1, left / total))
    for i = 0, 5 do
      local ang = i * 1.05
      local x = fx + math.sin(ang * 2.3) * w * 0.35
      local y = fy - h * (0.3 + 0.12 * (i % 3)) - u * 26 * k
      local r = (7 + 3 * (i % 2)) * k * (0.7 + 0.8 * u)
      G2.setColor(0.6, 0.6, 0.62, 0.55 * (1 - u))
      G2.circle("fill", x, y, r, 14)
    end
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
    local high = 1 - 0.4 * math.min(1, (p.y or 0) / (N.PLAYER.Y_MAX or 0.7))
    local srx, sry
    if board then
      local bk = k * D.BOARD.scale
      srx, sry = D.BOARD.cx * 0.9 * bk * high, 6 * bk * high
    else
      local shrink = (1 - 0.25 * (lift / math.max(1, D.HOP.HEIGHT))) * high
      srx, sry = 18 * k * shrink, 5 * k * shrink
    end
    -- a ball about to hit: the shadow blinks red with it
    local soon = sim.phase == "play" and D.soonestHit(sim)
    local warn = soon and soon <= D.WARN.BLINK_S and blinkOn(sim)
    if warn then
      local R = D.WARN.RED
      G2.setColor(R[1] * 0.7, R[2], R[3], 0.55)
    else
      G2.setColor(0, 0, 0, 0.3)
    end
    G2.ellipse("fill", px, gy, srx, sry)
    if warn then
      local R = D.WARN.RED
      G2.setLineWidth(math.max(1.5, sry * 0.35))
      G2.setColor(R[1], R[2], R[3], 0.9)
      G2.ellipse("line", px, gy, srx * 1.1, sry * 1.1)
      G2.setLineWidth(1)
    end
    local pic = playerPic(s)
    local stage = sim:chargeStage()
    local feetY = py + 2 - lift * k
    -- the rider's box on screen: its sprite as drawn, and the board under it
    local x0, y0, x1, y1 = px - 12 * k, feetY - 28 * k, px + 12 * k, feetY
    if pic then
      local ak = k * (pic.k or 1)
      x0, x1 = px - pic.w / 2 * ak * hsx, px + pic.w / 2 * ak * hsx
      y0 = feetY - pic.h * ak * hsy
    end
    if board then
      local bk = k * D.BOARD.scale
      local bw, bh = board:getDimensions()
      x0 = math.min(x0, px - D.BOARD.cx * bk)
      x1 = math.max(x1, px + (bw - D.BOARD.cx) * bk)
      y0 = math.min(y0, feetY - D.BOARD.feetY * bk)
      y1 = math.max(y1, feetY + (bh - D.BOARD.feetY) * bk)
    end
    local see = D.riderAlpha(sim, x0, y0, x1, y1)
    -- the shield: a dome of hexagons between the trainee and the balloon - the camera is behind
    -- the trainee, so it is drawn first and the trainee and its stand over it
    if p.shield > 0 then drawShield(G2, sim, px, feetY, x1 - x0, feetY - y0, k, p.breakT) end
    if board then
      -- under the rider, rolling and pitching with it
      local pitch = boardPitch(sim)
      hsy = hsy * (1 - D.BOARD.RIDER_PITCH * pitch)
      G2.setColor(1, 1, 1, see)
      local bk = k * D.BOARD.scale
      drawPixel(board, px, feetY, lean, bk, bk * (1 + D.BOARD.PITCH * pitch), D.BOARD.cx, D.BOARD.feetY)
    end
    if pic then
      local flash = p.stun > 0 and (math.floor(sim.t * 20) % 2 == 0)
      G2.setColor(1, 1, 1, (flash and 0.4 or 1) * see)
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
      G2.setColor(0.95, 0.6, 0.2, see)
      G2.circle("fill", px, py - 14 * k, 12 * k, 16)
    end
    -- the charge's fire over the Pokemon (yellow when Charged, a bigger yellow-orange at full),
    -- and the smoke it leaves when the charge fizzles
    if p.charging and stage > 0 then drawFire(G2, sim, px, feetY, x1 - x0, feetY - y0, k, stage) end
    if (p.smoke or 0) > 0 then drawSmoke(G2, sim, px, feetY, x1 - x0, feetY - y0, k, p.smoke) end
    -- the shield's shatter when it goes (the shield itself is drawn behind the trainee)
    if (p.shatter or 0) > 0 then drawShatter(G2, sim, px, feetY, x1 - x0, feetY - y0, k, p.shatter) end
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
    -- the meter grows from the middle out, as the game's
    local full = sim.guts >= 1
    G2.setColor(full and 1 or 0.98, full and 0.85 or 0.6, full and 0.3 or 0.15, 1)
    if sim.guts > 0.001 then G2.circle("fill", gx, gy, 9 * sim.guts, 20) end
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
    if s then s.hudReticle = Hud and (Hud.P ~= nil or Hud.engine) and Hud.sim == sim or nil end
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
