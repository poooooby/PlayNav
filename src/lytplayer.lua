-- Plays a game screen from its own layout and clips (src/lytfile.lua reads them): the pane
-- tree drawn with love, each pane's translate / rotate / scale about its parent, its origin,
-- vertex colours, alpha (passed on to the children when the pane says so), its material's
-- texture with wrap and texture SRT, and the material's black / white colours (the colour is
-- black + (white - black) * texel, times the vertex colour: a shader). Clips drive the panes
-- of their layout groups (and their children when the clip binds them) at 30 frames a second;
-- a clip that has ended holds its last frame.
--
-- local P = Player.new(layout, { image = fn(texName) -> Image | nil, clip = fn(name) -> clip | nil })
-- P:play(name, { loop, speed }) ; P:stop(name) ; P:playing(name) ; P:finished(name)
-- P:advance(frames) ; P:draw(G) (layout units, origin top-left, y down; the caller scales)
-- P:set(pane, key, value) (visible, alpha, tx, ty, sx, sy, rz, w, h: over the animation;
--   inherit = true passes the pane's alpha to its children)
-- P.stretchY = k: every pane's position (not its size) spread by k about the layout's middle,
--   full-height panes stretched with it: the layout fits a screen of another shape)
-- P.adjust = { [name] = { mx, my, dx, dy, sx, sy, qx, qy, tileY } }: per pane, on top of its clips:
--   its position times mx / my plus dx / dy (layout units, in its parent's space, y up; mx
--   scales a clip's slide with the pane), a scale of the pane and its children, and a
--   scale of its own picture alone (about its origin); fits a layout to a wider / taller screen
--   while chosen panes keep their place (src/training/hud.lua); `tileY` repeats a wrapping
--   texture that many times more down a taller qy (a pattern grows, not stretches);
--   `parked = true` applies it only
--   while no tx / ty is set on the pane from outside
-- P.stretchMode = "backdrop" (with stretchY): the panes stay where the layout has them (top
--   aligned); only full-height pictures stretch down to fill the taller screen
-- P:setText(pane, s, opts) (opts.align "left" | "center" | "right", opts.color) ;
-- P:setImage(pane, img) ; P:box(pane) -> x, y, w, h in layout units (rotation ignored)

local Player = {}
Player.__index = Player
Player.FPS = 30
Player.FONT_SCALE = 0.64

local F   -- src/lytfile.lua, handed in by the loader (Player.files)

local WRAP = { [0] = "clamp", [1] = "repeat", [2] = "mirroredrepeat", [3] = "clamp" }

local SHADER_SRC = [[
uniform vec4 black;
uniform vec4 white;
vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 sc) {
  vec4 t = Texel(tex, uv);
  return (black + (white - black) * t) * vcolor;
}
]]
local shader, shaderTried
local function getShader(G)
  if shaderTried then return shader end
  shaderTried = true
  local ok, s = pcall(G.newShader, SHADER_SRC)
  shader = ok and s or nil
  return shader
end

local white1x1
local function plainImage(G)
  if white1x1 == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 1, 1, 1, 1)
      return G.newImage(d)
    end)
    white1x1 = ok and img or false
  end
  return white1x1 or nil
end

function Player.new(layout, opts)
  local self = setmetatable({ L = layout, opts = opts or {}, active = {}, clips = {}, bound = {},
    over = {}, texts = {}, images = {}, imageCache = {}, matOwner = {} }, Player)
  for _, pane in pairs(layout.byName) do
    if pane.mat and layout.materials[pane.mat] then self.matOwner[layout.materials[pane.mat].name] = pane.name end
    if pane.kind == "wnd" then
      if pane.content and layout.materials[pane.content.mat] then self.matOwner[layout.materials[pane.content.mat].name] = pane.name end
      for _, fr in ipairs(pane.frames or {}) do
        if layout.materials[fr.mat] then self.matOwner[layout.materials[fr.mat].name] = pane.name end
      end
    end
  end
  return self
end

function Player.setFiles(files) F = files end

-- the panes a clip drives: its groups' panes, and their children when it binds them
local function boundSet(self, clip)
  local set = {}
  local function add(pane, deep)
    if not pane or set[pane.name] then return end
    set[pane.name] = true
    if deep then for _, c in ipairs(pane.children) do add(c, true) end end
  end
  for _, g in ipairs(clip.groups) do
    for _, name in ipairs(self.L.groups[g] or {}) do add(self.L.byName[name], clip.bind) end
  end
  return set
end

function Player:clip(name)
  if self.clips[name] == nil then
    local c = self.opts.clip and self.opts.clip(name) or nil
    self.clips[name] = c or false
    if c then self.bound[name] = boundSet(self, c) end
  end
  return self.clips[name] or nil
end

local function sameGroups(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- start a clip from its first frame; a clip already running on the same groups gives way
function Player:play(name, o)
  local c = self:clip(name)
  if not c then return false end
  o = o or {}
  for i = #self.active, 1, -1 do
    local a = self.active[i]
    if a.name == name or sameGroups(a.clip.groups, c.groups) then table.remove(self.active, i) end
  end
  self.active[#self.active + 1] = { name = name, clip = c, frame = o.from or 0,
    loop = o.loop == nil and c.loop or o.loop, speed = o.speed or 1 }
  return true
end

function Player:stop(name)
  for i = #self.active, 1, -1 do if self.active[i].name == name then table.remove(self.active, i) end end
end

function Player:entry(name)
  for _, a in ipairs(self.active) do if a.name == name then return a end end
  return nil
end

function Player:playing(name)
  local a = self:entry(name)
  return a ~= nil and (a.loop or a.frame < a.clip.frames - 1)
end

function Player:finished(name)
  local a = self:entry(name)
  return a == nil or (not a.loop and a.frame >= a.clip.frames - 1)
end

function Player:frameOf(name)
  local a = self:entry(name)
  return a and a.frame or nil
end

function Player:advance(frames)
  for _, a in ipairs(self.active) do
    local n = a.clip.frames
    a.frame = a.frame + frames * a.speed
    if a.loop then
      if n > 1 then a.frame = a.frame % (n - 1) end
    elseif a.frame > n - 1 then
      a.frame = n - 1
    end
  end
end

function Player:set(pane, key, value)
  local o = self.over[pane] or {}
  self.over[pane] = o
  o[key] = value
end

function Player:clear(pane, key)
  local o = self.over[pane]
  if o then if key then o[key] = nil else self.over[pane] = nil end end
end

function Player:setText(pane, s, o)
  self.texts[pane] = s and { s = s, align = o and o.align, color = o and o.color, valign = o and o.valign } or nil
end

function Player:setImage(pane, img) self.images[pane] = img end

-- ------- the state of one pane this frame

-- one state table per pane, reused frame to frame: a layout draw is hundreds of panes, and
-- a table each left the device's collector sweeping every frame
local BASE_KEYS = { tx = true, ty = true, rz = true, sx = true, sy = true, w = true, h = true, alpha = true,
  visible = true, colorAnim = true }
local function paneProps(self, pane)
  local st = pane._st
  if st then
    for k in pairs(st) do if not BASE_KEYS[k] then st[k] = nil end end
  else
    st = {}
    pane._st = st
  end
  st.tx, st.ty, st.rz, st.sx, st.sy, st.w, st.h = pane.t[1], pane.t[2], pane.rz, pane.s[1], pane.s[2], pane.w, pane.h
  st.alpha, st.visible, st.colorAnim = pane.alpha, pane.visible, nil
  local colors
  for _, a in ipairs(self.active) do
    if self.bound[a.name][pane.name] then
      local props = a.clip.panes[pane.name]
      if props then
        for key, track in pairs(props) do
          local v = F.eval(track, a.frame)
          if v ~= nil then
            if key == "visible" then st.visible = v ~= 0
            elseif key:sub(1, 1) == "c" and key:find("%.") then
              colors = colors or {}
              colors[key] = v
            else st[key] = v end
          end
        end
      end
    end
  end
  local o = self.over[pane.name]
  if o then for k, v in pairs(o) do st[k] = v end end
  st.colorAnim = colors
  return st
end

-- material state: the texture SRT, pattern and colours the clips set
local function matProps(self, pane, mat)
  local out
  for _, a in ipairs(self.active) do
    if self.bound[a.name][pane.name] then
      local props = a.clip.materials[mat.name]
      if props then
        out = out or {}
        for key, track in pairs(props) do
          local v = F.eval(track, a.frame)
          if v ~= nil then
            if key:sub(1, 2) == "tp" then out[key] = a.clip.textures[math.floor(v) + 1] else out[key] = v end
          end
        end
      end
    end
  end
  return out
end

function Player:image(texName)
  if not texName then return nil end
  local c = self.imageCache[texName]
  if c == nil then
    c = self.opts.image and self.opts.image(texName) or nil
    self.imageCache[texName] = c or false
  end
  return c or nil
end

local CORNERS = { "tl", "tr", "bl", "br" }
local WHITE4 = { 255, 255, 255, 255 }
local CKEY = {}
for i, c in ipairs(CORNERS) do CKEY[i] = { r = "c" .. c .. ".r", g = "c" .. c .. ".g", b = "c" .. c .. ".b", a = "c" .. c .. ".a" } end
local function vcolor(base, anim, i, alpha)
  local c = base and base[i] or WHITE4
  local r, g, b, a = c[1], c[2], c[3], c[4]
  if anim then
    local k = CKEY[i]
    r = anim[k.r] or r; g = anim[k.g] or g; b = anim[k.b] or b; a = anim[k.a] or a
  end
  return r / 255, g / 255, b / 255, a / 255 * alpha
end

-- the four corner colours of the pane being drawn (quad reads them at once; one set reused).
-- Never `{ vcolor(...) }`: a call as a constructor's last element is a multi-value store that
-- this LuaJIT compiles into a slow path allocating tens of KB per table.
local COLS = { {}, {}, {}, {} }
local function fillCols(base, anim, alpha)
  for i = 1, 4 do
    local c = COLS[i]
    c[1], c[2], c[3], c[4] = vcolor(base, anim, i, alpha)
  end
  return COLS
end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- the rect of a pane in its own space (y down): the origin decides where (0, 0) sits
local function rectOf(pane, w, h)
  local ox, oy = pane.origin % 3, math.floor(pane.origin / 3)
  local x0 = ox == 0 and 0 or (ox == 1 and -w / 2 or -w)
  local y0 = oy == 0 and 0 or (oy == 1 and -h / 2 or -h)
  return x0, y0
end

local mesh
local DEFAULT_UV = { 0, 0, 1, 0, 0, 1, 1, 1 }
local BLACK0, WHITE255 = { 0, 0, 0, 0 }, { 255, 255, 255, 255 }
-- the mesh's four vertices and the shader's two colours: filled in place every quad
local VERTS = { {}, {}, {}, {} }
local SEND_B, SEND_W = { 0, 0, 0, 0 }, { 1, 1, 1, 1 }
local function setVert(v, x, y, u, vv, c)
  v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] = x, y, u, vv, c[1], c[2], c[3], c[4]
end
local function quad(G, img, x0, y0, w, h, uv, cols, mat, mp, sh, wrapS, wrapT, tileY)
  -- texture coordinates: the pane's own, through the material's texture SRT (about the
  -- centre: (uv - 0.5) * scale + 0.5 + translate)
  local u = uv or DEFAULT_UV
  local srt = mat and mat.srt[1]
  local tx, ty, sx, sy = 0, 0, 1, 1
  if srt then tx, ty, sx, sy = srt[1], srt[2], srt[4], srt[5] end
  if mp then
    tx = mp["ts0.0"] or tx; ty = mp["ts0.1"] or ty; sx = mp["ts0.3"] or sx; sy = mp["ts0.4"] or sy
  end
  if tileY and tileY ~= 1 then
    -- a repeating texture made taller: more rows of it, the top row where it was
    ty = ty + 0.5 * sy * (tileY - 1)
    sy = sy * tileY
  end
  local u1, v1 = (u[1] - 0.5) * sx + 0.5 + tx, (u[2] - 0.5) * sy + 0.5 + ty
  local u2, v2 = (u[3] - 0.5) * sx + 0.5 + tx, (u[4] - 0.5) * sy + 0.5 + ty
  local u3, v3 = (u[5] - 0.5) * sx + 0.5 + tx, (u[6] - 0.5) * sy + 0.5 + ty
  local u4, v4 = (u[7] - 0.5) * sx + 0.5 + tx, (u[8] - 0.5) * sy + 0.5 + ty
  setVert(VERTS[1], x0, y0, u1, v1, cols[1])
  setVert(VERTS[2], x0 + w, y0, u2, v2, cols[2])
  setVert(VERTS[3], x0 + w, y0 + h, u4, v4, cols[4])
  setVert(VERTS[4], x0, y0 + h, u3, v3, cols[3])
  if not mesh then mesh = G.newMesh(4, "fan", "stream") end
  mesh:setVertices(VERTS)
  img:setWrap(wrapS or "clamp", wrapT or "clamp")
  mesh:setTexture(img)
  if sh then
    local bl, wh = mat and mat.black or BLACK0, mat and mat.white or WHITE255
    local b1, b2, b3, b4 = bl[1], bl[2], bl[3], bl[4]
    local w1, w2, w3, w4 = wh[1], wh[2], wh[3], wh[4]
    if mp then
      b1 = mp.mc0 or b1; b2 = mp.mc1 or b2; b3 = mp.mc2 or b3; b4 = mp.mc3 or b4
      w1 = mp.mc4 or w1; w2 = mp.mc5 or w2; w3 = mp.mc6 or w3; w4 = mp.mc7 or w4
    end
    SEND_B[1], SEND_B[2], SEND_B[3], SEND_B[4] = b1 / 255, b2 / 255, b3 / 255, b4 / 255
    SEND_W[1], SEND_W[2], SEND_W[3], SEND_W[4] = w1 / 255, w2 / 255, w3 / 255, w4 / 255
    sh:send("black", SEND_B)
    sh:send("white", SEND_W)
    G.setShader(sh)
  end
  G.setColor(1, 1, 1, 1)
  G.draw(mesh)
  if sh then G.setShader() end
end

-- a font for text drawn `px` layout units tall under the current transform: rasterised at the
-- size it lands on screen, so the top screen's window-resolution draw stays crisp
Player.fonts = {}
local function fontFor(G, px, opts)
  local x0, y0 = G.transformPoint(0, 0)
  local x1, y1 = G.transformPoint(0, 1)
  local k = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  -- the game's font sizes name its cell; love's default face at 0.64 of it matches the
  -- width of the game's lines (measured against a capture)
  local size = math.max(4, math.floor(px * k * Player.FONT_SCALE + 0.5))
  local fk = opts and opts.fontKey or false
  local byKey = Player.fonts[fk]
  if not byKey then byKey = {}; Player.fonts[fk] = byKey end
  local f = byKey[size]
  if f == nil then
    local ok, font = pcall(function()
      if opts and opts.font then return opts.font(size) end
      return G.newFont(size)
    end)
    f = ok and font or false
    byKey[size] = f
  end
  return f or nil, k
end

local function drawText(self, G, pane, st, alpha)
  local t = self.texts[pane.name]
  if not t then return end
  local font, k = fontFor(G, pane.fontH, self.opts)
  if not font or k <= 0 then return end
  local w, h = st.w, st.h
  local x0, y0 = rectOf(pane, w, h)
  local hp = pane.textPos % 3
  local align = t.align or (hp == 0 and "left" or (hp == 1 and "center" or "right"))
  local vp = math.floor(pane.textPos / 3)
  local lines = t.lines
  if not lines then
    lines = {}
    for line in (t.s .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    t.lines = lines
  end
  local lh = font:getHeight() / k
  local inv = 1 / k
  local total = lh * #lines
  local vy = t.valign or (vp == 0 and "top" or (vp == 1 and "center" or "bottom"))
  local y = vy == "top" and y0 or (vy == "center" and y0 + (h - total) / 2 or y0 + h - total)
  local c = t.color or pane.top
  G.setFont(font)
  for _, line in ipairs(lines) do
    local lw = font:getWidth(line) * inv
    -- a line wider than its box is squeezed to fit, as the game's text panes do
    local sx = lw > w and w / lw or 1
    local x = align == "left" and x0 or (align == "center" and x0 + (w - lw * sx) / 2 or x0 + w - lw * sx)
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, (c[4] or 255) / 255 * alpha)
    G.print(line, x, y, 0, inv * sx, inv)
    y = y + lh
  end
end

-- a window: the content quad, then the four corner frames (each its material's texture at its
-- own size; the edges stretch the corners' inner row / column)
local function drawWindow(self, G, pane, st, alpha, sh)
  local L = self.L
  local w, h = st.w, st.h
  local x0, y0 = rectOf(pane, w, h)
  local cols = fillCols(pane.content.colors, st.colorAnim, alpha)
  local cm = L.materials[pane.content.mat]
  local cimg = cm and cm.maps[1] and self:image(L.textures[cm.maps[1].tex]) or plainImage(G)
  local frames = pane.frames or {}
  local imgs = {}
  for i, fr in ipairs(frames) do
    local m = L.materials[fr.mat]
    imgs[i] = m and m.maps[1] and self:image(L.textures[m.maps[1].tex]) or nil
  end
  local lt, rt = imgs[1], imgs[2] or imgs[1]
  if not lt then
    if cimg then quad(G, cimg, x0, y0, w, h, pane.content.uv, cols, cm, nil, sh) end
    return
  end
  local tw, th = lt:getDimensions()
  local rw = rt:getDimensions()
  local half = math.min(th, h / 2)
  if cimg then quad(G, cimg, x0 + tw / 2, y0 + half / 2, w - tw / 2 - rw / 2, h - half, pane.content.uv, cols, cm, nil, sh) end
  G.setColor(1, 1, 1, alpha)
  self.wq = self.wq or {}
  local Q = self.wq[pane.name]
  if not (Q and Q.tw == tw and Q.th == th and Q.half == half and Q.lt0 == lt and Q.rt0 == rt) then
    local function q(img, x, y, qw, qh)
      local iw, ih = img:getDimensions()
      return G.newQuad(x, y, qw, qh, iw, ih)
    end
    Q = { tw = tw, th = th, half = half, lt0 = lt, rt0 = rt,
      lt = q(lt, 0, 0, tw, half), rt = q(rt, 0, 0, rw, half), ltEdge = q(lt, tw - 1, 0, 1, half),
      ltSide = q(lt, 0, th - 1, tw, 1), rtSide = q(rt, 0, th - 1, rw, 1), mid = q(lt, tw - 1, th - 1, 1, 1) }
    self.wq[pane.name] = Q
  end
  G.draw(lt, Q.lt, x0, y0)
  G.draw(lt, Q.lt, x0, y0 + h, 0, 1, -1)
  G.draw(rt, Q.rt, x0 + w - rw, y0)
  G.draw(rt, Q.rt, x0 + w - rw, y0 + h, 0, 1, -1)
  local midW, midH = w - tw - rw, h - 2 * half
  if midW > 0 then
    G.draw(lt, Q.ltEdge, x0 + tw, y0, 0, midW, 1)
    G.draw(lt, Q.ltEdge, x0 + tw, y0 + h, 0, midW, -1)
  end
  if midH > 0 then
    G.draw(lt, Q.ltSide, x0, y0 + half, 0, 1, midH)
    G.draw(rt, Q.rtSide, x0 + w - rw, y0 + half, 0, 1, midH)
    if midW > 0 then G.draw(lt, Q.mid, x0 + tw, y0 + half, 0, midW, midH) end
  end
end

-- ctx: the parent's absolute y (layout units, y up from the middle), its accumulated y
-- scale and the shift the stretch gave it
-- an image set from outside draws plain: no texture SRT, black 0 and white 255
local PLAIN_MAT = { srt = {}, black = { 0, 0, 0, 0 }, white = { 255, 255, 255, 255 } }
-- the pane's P.adjust entry, or nil (`parked`: only while nothing places the pane, no tx /
-- ty set from outside)
local function adjustOf(self, pane)
  local adj = self.adjust and self.adjust[pane.name]
  if adj and adj.parked then
    local o = self.over[pane.name]
    if o and (o.tx ~= nil or o.ty ~= nil) then return nil end
  end
  return adj
end

local function drawPane(self, G, pane, parentAlpha, sh, ctx)
  local st = paneProps(self, pane)
  if not st.visible then return end
  local adj = adjustOf(self, pane)
  -- the pane's height as the layout has it (P.adjust's scaling left out): what decides whether
  -- it is a full-height backdrop, so a pane scaled up to the screen's height is not stretched
  local layoutH = math.abs(st.h * (ctx.syRaw or ctx.sy) * st.sy)
  local rawSy = st.sy
  if adj then
    st.tx, st.ty = st.tx * (adj.mx or 1) + (adj.dx or 0), st.ty * (adj.my or 1) + (adj.dy or 0)
    st.sx = st.sx * (adj.sx or 1)
    st.sy = st.sy * (adj.sy or 1)
  end
  local alpha = clamp01(st.alpha / 255) * parentAlpha
  local sy = st.sy
  local absY = ctx.y + st.ty * ctx.sy
  local shift = ctx.shift
  local k = self.stretchY
  local inBackdrop = ctx.inBackdrop
  if k and self.stretchMode == "backdrop" then
    if not inBackdrop and pane.kind ~= "pan" and layoutH >= self.L.H - 0.5 and ctx.sy ~= 0 then
      -- a backdrop: taller by k, its top where it was (its children come along with it)
      sy = sy * k
      st.ty = st.ty - self.L.H * (k - 1) / 2 / ctx.sy
      inBackdrop = true
    end
    k = nil
  end
  if k and ctx.sy ~= 0 then
    shift = absY * (k - 1)
    st.ty = st.ty + (shift - ctx.shift) / ctx.sy
    -- a full-height picture (a mask, a backdrop) stretches with the screen; a group pane's
    -- children are placed by the shift above, so it keeps its scale
    if pane.kind ~= "pan" and layoutH >= self.L.H - 0.5 then sy = sy * k end
  end
  local childCtx = pane._ctx
  if not childCtx then childCtx = {}; pane._ctx = childCtx end
  childCtx.y, childCtx.sy, childCtx.shift, childCtx.inBackdrop = absY, ctx.sy * st.sy, shift, inBackdrop
  childCtx.syRaw = (ctx.syRaw or ctx.sy) * rawSy
  G.push()
  G.translate(st.tx, -st.ty)
  if st.rz ~= 0 then G.rotate(-math.rad(st.rz)) end
  if st.sx ~= 1 or sy ~= 1 then G.scale(st.sx, sy) end
  if alpha > 0.001 and st.sx ~= 0 and st.sy ~= 0 then
    if pane.kind == "pic" then
      local L = self.L
      local mat = L.materials[pane.mat]
      local mp = mat and matProps(self, pane, mat)
      local img = self.images[pane.name]
      local map = mat and mat.maps[1]
      if not img then
        local tex = mp and mp.tp0 or (map and L.textures[map.tex])
        img = tex and self:image(tex)
      end
      if not img and not map then img = plainImage(G) end
      if img and st.w ~= 0 and st.h ~= 0 then
        local cols = fillCols(pane.colors, st.colorAnim, alpha)
        local qw, qh = st.w * (adj and adj.qx or 1), st.h * (adj and adj.qy or 1)
        local x0, y0 = rectOf(pane, qw, qh)
        local ws, wt = map and WRAP[map.wrapS], map and WRAP[map.wrapT]
        quad(G, img, x0, y0, qw, qh, pane.uv, cols, self.images[pane.name] and PLAIN_MAT or mat, mp, sh, ws, wt,
          adj and adj.tileY)
      end
    elseif pane.kind == "txt" then
      drawText(self, G, pane, st, alpha)
    elseif pane.kind == "wnd" then
      drawWindow(self, G, pane, st, alpha, sh)
    end
  end
  local childAlpha = (pane.influence or st.inherit) and alpha or parentAlpha
  for _, c in ipairs(pane.children) do drawPane(self, G, c, childAlpha, sh, childCtx) end
  G.pop()
end

function Player:draw(G)
  local sh = getShader(G)
  G.push()
  -- stretched, the layout is H * k tall: its middle goes to the middle of that
  local spread = self.stretchY and self.stretchMode ~= "backdrop" and self.stretchY or 1
  G.translate(self.L.W / 2, self.L.H / 2 * spread)
  drawPane(self, G, self.L.root, 1, sh, { y = 0, sy = 1, shift = 0 })
  G.pop()
  G.setColor(1, 1, 1, 1)
end

-- where a pane is this frame, in layout units (top-left origin, y down); rotation ignored
function Player:box(name)
  local pane = self.L.byName[name]
  if not pane then return nil end
  local chain = {}
  local p = pane
  while p do table.insert(chain, 1, p); p = p.parent end
  local x, y, sx, sy = self.L.W / 2, self.L.H / 2, 1, 1
  local st, adj
  for _, q in ipairs(chain) do
    st = paneProps(self, q)
    adj = adjustOf(self, q)
    local tx, ty = st.tx, st.ty
    if adj then tx, ty = tx * (adj.mx or 1) + (adj.dx or 0), ty * (adj.my or 1) + (adj.dy or 0) end
    x, y = x + tx * sx, y - ty * sy
    sx, sy = sx * st.sx * (adj and adj.sx or 1), sy * st.sy * (adj and adj.sy or 1)
  end
  if self.stretchY and self.stretchMode ~= "backdrop" then
    y = (self.L.H / 2 + (y - self.L.H / 2) * self.stretchY) + self.L.H / 2 * (self.stretchY - 1)
  end
  local w, h = st.w * math.abs(sx) * (adj and adj.qx or 1), st.h * math.abs(sy) * (adj and adj.qy or 1)
  local x0, y0 = rectOf(pane, w, h)
  return x + x0, y + y0, w, h
end

return Player
