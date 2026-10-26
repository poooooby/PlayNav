-- A screen laid out in Lua as the game lays its screens out (PLAY's game_select_lower,
-- DECORATE's customize, in their 320x240 units): a tree of panes, each a middle (tx, ty from
-- its parent's middle, y up; the top ones from the screen's middle), a size, and what it shows
-- - a picture, words, or a window the caller draws. A pane's scale and turn (sx, sy, rz, about
-- its middle) carry its children with it, as its alpha does.
--
-- local S = Panes.new(rows, { art = fn(id) -> Image, prefix = "lyt/amie_play/",
--   windows = { [kind] = fn(G2, x, y, w, h, alpha, S, pane) } })
-- rows: { name, parent, tx, ty, w, h, art = <id after prefix>, text = <style>, window = <kind>,
--   hidden = true, left = true (tx is its left edge: it grows rightward), tile = n (the picture
--   repeated n times across), alpha (0..255), rz (degrees, anticlockwise) }; drawn in order,
--   children after their parent
-- text style: { size (the game's font size), color = { r, g, b }, outline = { r, g, b } | nil,
--   align = "center" | "left" | "right" }
-- S:set(name, key, value) over the pane's own (visible, alpha 0..255, tx, ty, w, h, sx, sy, rz);
-- S:clear(name, key) ; S:setText(name, s) ; S:setImage(name, id | Image) ; S:box(name) -> x, y, w, h
-- (screen units, scale and turn left out) ; S.adjust = { [name] = { dx, dy } } (y up) ; S:draw(G2)

local Panes = {}
Panes.__index = Panes

local function prop(self, pane, key)
  local o = self.over[pane.name]
  local v = o and o[key]
  if v == nil then v = pane[key] end
  return v
end

local function offset(self, pane)
  local a = self.adjust and self.adjust[pane.name]
  local tx, ty = prop(self, pane, "tx"), prop(self, pane, "ty")
  if a then tx, ty = tx + (a.dx or 0), ty + (a.dy or 0) end
  return tx, ty
end

-- a pane's middle on the screen (y down)
local function middle(self, pane)
  if not pane then return 160, 120 end
  local px, py = middle(self, pane.parent)
  local tx, ty = offset(self, pane)
  return px + tx, py - ty
end

function Panes.new(rows, opts)
  local self = setmetatable({ byName = {}, roots = {}, over = {}, texts = {}, images = {}, opts = opts or {},
    fonts = {} }, Panes)
  for _, row in ipairs(rows) do
    local pane = { name = row[1], tx = row[3], ty = row[4], w = row[5], h = row[6], art = row.art, text = row.text,
      window = row.window, left = row.left, tile = row.tile, alpha = row.alpha, rz = row.rz, visible = not row.hidden,
      children = {} }
    self.byName[pane.name] = pane
    local parent = row[2] and self.byName[row[2]]
    pane.parent = parent
    if parent then parent.children[#parent.children + 1] = pane else self.roots[#self.roots + 1] = pane end
  end
  return self
end

function Panes:set(name, key, value)
  local o = self.over[name]
  if not o then o = {}; self.over[name] = o end
  o[key] = value
end
function Panes:clear(name, key)
  local o = self.over[name]
  if o then o[key] = nil end
end
function Panes:get(name, key)
  local pane = self.byName[name]
  return pane and prop(self, pane, key)
end
function Panes:setText(name, text) self.texts[name] = text end
function Panes:setImage(name, img) self.images[name] = img end

function Panes:box(name)
  local pane = self.byName[name]
  if not pane then return nil end
  local x, y = middle(self, pane)
  local w, h = prop(self, pane, "w"), prop(self, pane, "h")
  if pane.left then return x, y - h / 2, w, h end
  return x - w / 2, y - h / 2, w, h
end

-- words in a box: love's face at 0.64 of the game's font size, rasterised at the size it lands
-- on screen; squeezed if too wide
local function drawText(self, G2, text, st, x, y, w, h, a)
  local x0, y0 = G2.transformPoint(0, 0)
  local x1, y1 = G2.transformPoint(0, 1)
  local k = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  if k <= 0 then return end
  local size = math.max(4, math.floor((st.size or 19) * k * 0.64 + 0.5))
  local font = self.fonts[size]
  if font == nil then
    local ok, f = pcall(Panes.newFont or G2.newFont, size)
    font = ok and f or false
    self.fonts[size] = font
  end
  if not font then return end
  local inv = 1 / k
  local lw, lh = font:getWidth(text) * inv, font:getHeight() * inv
  local sx = lw > w and w / lw or 1
  local tx = x + (w - lw * sx) / 2
  if st.align == "left" then tx = x elseif st.align == "right" then tx = x + w - lw * sx end
  local ty = y + (h - lh) / 2
  G2.setFont(font)
  local o = st.outline
  if o then
    G2.setColor(o[1], o[2], o[3], a)
    for ox = -1, 1 do
      for oy = -1, 1 do
        if ox ~= 0 or oy ~= 0 then G2.print(text, tx + ox * inv, ty + oy * inv, 0, inv * sx, inv) end
      end
    end
  end
  local c = st.color or { 1, 1, 1 }
  G2.setColor(c[1], c[2], c[3], a)
  G2.print(text, tx, ty, 0, inv * sx, inv)
end

local tileQuad = nil
local function drawPicture(G2, img, x, y, w, h, tile)
  local iw, ih = img:getDimensions()
  if tile and tile > 1 then
    img:setWrap("repeat", "clamp")
    if not tileQuad then tileQuad = G2.newQuad(0, 0, iw * tile, ih, iw, ih)
    else tileQuad:setViewport(0, 0, iw * tile, ih, iw, ih) end
    G2.draw(img, tileQuad, x, y, 0, w / (iw * tile), h / ih)
    return
  end
  G2.draw(img, x, y, 0, w / iw, h / ih)
end

local function drawPane(self, G2, pane, alpha)
  if not prop(self, pane, "visible") then return end
  local a = alpha * (prop(self, pane, "alpha") or 255) / 255
  if a <= 0 then return end
  local tx, ty = offset(self, pane)
  local rz, sx, sy = prop(self, pane, "rz") or 0, prop(self, pane, "sx") or 1, prop(self, pane, "sy") or 1
  G2.push()
  G2.translate(tx, -ty)
  if rz ~= 0 then G2.rotate(-math.rad(rz)) end
  if sx ~= 1 or sy ~= 1 then G2.scale(sx, sy) end
  local w, h = prop(self, pane, "w"), prop(self, pane, "h")
  local x0, y0 = pane.left and 0 or -w / 2, -h / 2
  if pane.window then
    local fn = self.opts.windows and self.opts.windows[pane.window]
    if fn then fn(G2, x0, y0, w, h, a, self, pane) end
  else
    local img = self.images[pane.name]
    if img == nil and pane.art then img = (self.opts.prefix or "") .. pane.art end
    if type(img) == "string" then img = self.opts.art and self.opts.art(img) end
    if img then
      G2.setColor(1, 1, 1, a)
      drawPicture(G2, img, x0, y0, w, h, pane.tile)
    end
  end
  local text = pane.text and self.texts[pane.name]
  if text then drawText(self, G2, text, pane.text, x0, y0, w, h, a) end
  for _, c in ipairs(pane.children) do drawPane(self, G2, c, a) end
  G2.pop()
end

function Panes:draw(G2)
  G2.push("all")
  G2.setShader()
  G2.setBlendMode("alpha")
  G2.translate(160, 120)
  for _, pane in ipairs(self.roots) do drawPane(self, G2, pane, 1) end
  G2.pop()
end

return Panes
