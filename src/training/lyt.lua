-- Drawing the game's layout panes (tools/clyt.py dumps them) in layout units: a textured or
-- plain quad with the pane's four vertex colours (TL, TR, BL, BR), mirroring and repeat; the
-- windows the card builds from two corner pieces; the shutters that close a screen
-- (black_out / black_out2, the clips *_black_out / *_black_in); the hermite key tracks.
--
-- L = lyt() ; L.quad(G, img, cx, cy, w, h, opts) ; L.window(G, lt, rt, cx, cy, w, h)
-- L.shutters(G, art, W, H, phase, f) ; L.eval(keys, f) ; L.text(G, font, s, x, y, w, h, opts)

return function()
  local L = {}
  local WHITE = { 255, 255, 255, 255 }

  -- value of a key track ({ frame, value, slope }) at frame f; two keys on one frame jump
  function L.eval(keys, f)
    if not keys or #keys == 0 then return nil end
    if f <= keys[1][1] then return keys[1][2] end
    for i = 1, #keys - 1 do
      local a, b = keys[i], keys[i + 1]
      if f < b[1] then
        local span = b[1] - a[1]
        if span <= 0 then return b[2] end
        local t = (f - a[1]) / span
        local t2, t3 = t * t, t * t * t
        return (2 * t3 - 3 * t2 + 1) * a[2] + (t3 - 2 * t2 + t) * (a[3] or 0) * span
          + (-2 * t3 + 3 * t2) * b[2] + (t3 - t2) * (b[3] or 0) * span
      end
    end
    return keys[#keys][2]
  end

  -- opts: colors = { tl, tr, bl, br } (0-255 rgba), alpha (0-255, the pane's), flipX / flipY,
  -- repU / repV (repeat count), u0 / v0 (texture offset in repeats). Meshes are rebuilt per
  -- call: the panes here are few.
  local mesh
  function L.quad(G, img, cx, cy, w, h, opts)
    opts = opts or {}
    local c = opts.colors or { WHITE, WHITE, WHITE, WHITE }
    local a = (opts.alpha or 255) / 255
    local x0, y0 = cx - w / 2, cy - h / 2
    local u0, v0 = opts.u0 or 0, opts.v0 or 0
    local u1, v1 = u0 + (opts.repU or 1), v0 + (opts.repV or 1)
    if opts.flipX then u0, u1 = u1, u0 end
    if opts.flipY then v0, v1 = v1, v0 end
    local function v(x, y, u, vv, k) return { x, y, u, vv, k[1] / 255, k[2] / 255, k[3] / 255, (k[4] or 255) / 255 * a } end
    local verts = { v(x0, y0, u0, v0, c[1]), v(x0 + w, y0, u1, v0, c[2]), v(x0 + w, y0 + h, u1, v1, c[4]), v(x0, y0 + h, u0, v1, c[3]) }
    if not mesh then mesh = G.newMesh(4, "fan", "stream") end
    mesh:setVertices(verts)
    if img then
      if opts.repU or opts.repV then img:setWrap("repeat", "repeat") end
      mesh:setTexture(img)
    else
      mesh:setTexture()
    end
    G.setColor(1, 1, 1, 1)
    G.draw(mesh)
  end

  -- a texture mirrored 2x2 into the rect (the material's mirror wrap at scale 2: one quarter
  -- drawn four ways)
  function L.mirror4(G, img, cx, cy, w, h, opts)
    opts = opts or {}
    local hw, hh = w / 2, h / 2
    for _, q in ipairs({ { -1, -1, false, false }, { 1, -1, true, false }, { -1, 1, false, true }, { 1, 1, true, true } }) do
      L.quad(G, img, cx + q[1] * hw / 2, cy + q[2] * hh / 2, hw, hh,
        { colors = opts.colors, alpha = opts.alpha, flipX = q[3], flipY = q[4] })
    end
  end

  -- the card's windows: lt / rt are the left and right corner pieces (the bottom ones the same
  -- flipped), the edges their inner rows and columns stretched, the middle their last pixel
  local quads = {}
  local function quadOf(G, img, x, y, w, h)
    local iw, ih = img:getDimensions()
    local key = tostring(img) .. x .. ":" .. y .. ":" .. w .. ":" .. h
    quads[key] = quads[key] or G.newQuad(x, y, w, h, iw, ih)
    return quads[key]
  end
  function L.window(G, lt, rt, cx, cy, w, h, alpha)
    if not (lt and rt) then
      G.setColor(0.07, 0.75, 0.68, (alpha or 230) / 255)
      G.rectangle("fill", cx - w / 2, cy - h / 2, w, h, 6, 6)
      return
    end
    local tw, th = lt:getDimensions()
    local rw = rt:getDimensions()
    local x0, y0 = cx - w / 2, cy - h / 2
    local half = math.min(th, h / 2)
    local midW, midH = w - tw - rw, h - 2 * half
    G.setColor(1, 1, 1, (alpha or 255) / 255)
    -- corners
    G.draw(lt, quadOf(G, lt, 0, 0, tw, half), x0, y0)
    G.draw(lt, quadOf(G, lt, 0, 0, tw, half), x0, y0 + h, 0, 1, -1)
    G.draw(rt, quadOf(G, rt, 0, 0, rw, half), x0 + w - rw, y0)
    G.draw(rt, quadOf(G, rt, 0, 0, rw, half), x0 + w - rw, y0 + h, 0, 1, -1)
    -- top and bottom edges: the left piece's last column; the sides: the last row
    if midW > 0 then
      G.draw(lt, quadOf(G, lt, tw - 1, 0, 1, half), x0 + tw, y0, 0, midW, 1)
      G.draw(lt, quadOf(G, lt, tw - 1, 0, 1, half), x0 + tw, y0 + h, 0, midW, -1)
    end
    if midH > 0 then
      G.draw(lt, quadOf(G, lt, 0, th - 1, tw, 1), x0, y0 + half, 0, 1, midH)
      G.draw(rt, quadOf(G, rt, 0, th - 1, rw, 1), x0 + w - rw, y0 + half, 0, 1, midH)
      if midW > 0 then G.draw(lt, quadOf(G, lt, tw - 1, th - 1, 1, 1), x0 + tw, y0 + half, 0, midW, midH) end
    end
  end

  -- the shutters (stageselect / training_message: panes b8 / bc with their black fills, the seam
  -- c4 / c6), W x H the screen in layout units. phase "close": the halves slide in from
  -- +-(W/2 + 16) over 10 frames, the seam flashes up at 10, wobbles and fades by 20; "open":
  -- they slide back out over 10 frames.
  local CLOSE_X = { { 0, 1, -0.1 }, { 10, 0, -0.1 } }   -- the offset in half-widths (176/176)
  local OPEN_X = { { 0, 0, -0.1 }, { 10, 1, -0.1 } }
  local SEAM_X = { { 10, 0, 2 }, { 11, 2, -0.667 }, { 13, -2, -0.4 }, { 16, 0, 0.286 }, { 20, 0, 0 } }
  local SEAM_A = { { 0, 0, 0 }, { 10, 0, 0 }, { 10, 255, 0 }, { 20, 0, -25.5 } }
  function L.shutters(G, art, W, H, phase, f)
    local edge, seam = art("training/ss_black_out"), art("training/ss_black_out2")
    local reach = W / 2 + 16
    local k = L.eval(phase == "open" and OPEN_X or CLOSE_X, f) or 0
    local off = k * reach
    local mid = W / 2
    -- left half: its fill, then its stepped edge (the texture mirrored) at the seam
    G.setColor(0, 0, 0, 1)
    -- each fill (160 wide, 95 beyond the edge's centre) ends where its edge piece begins
    G.rectangle("fill", -W, 0, W + mid - off - 15, H)
    G.rectangle("fill", mid + off + 15, 0, W * 2, H)
    if edge then
      L.quad(G, edge, mid - off, H / 2, 32, H, { flipX = true, repV = 4, v0 = 0.5 })
      L.quad(G, edge, mid + off, H / 2, 32, H, { repV = 4 })
    end
    if phase == "close" and seam then
      local a = math.max(0, math.min(255, L.eval(SEAM_A, f) or 0))
      if a > 0 then
        local sx = mid + (L.eval(SEAM_X, f) or 0)
        local blue = { 0, 115, 230, 255 }
        local black = { 0, 0, 0, 255 }
        L.quad(G, seam, sx, H / 4, 32, H / 2, { colors = { black, black, blue, blue }, alpha = a, repV = 2 })
        L.quad(G, seam, sx, H * 3 / 4, 32, H / 2, { colors = { blue, blue, black, black }, alpha = a, repV = 2 })
      end
    end
    G.setColor(1, 1, 1, 1)
  end

  -- text in a layout text pane: the font scaled to the pane's height (and narrower when it
  -- would overrun), opts.align ("left" / "center" / "right"), opts.color, opts.shadow
  function L.text(G, font, s, x, y, w, h, opts)
    if not (font and s) then return end
    opts = opts or {}
    G.setFont(font)
    local k = (opts.size or h) * 0.8 / math.max(1, font:getHeight())
    local tw = font:getWidth(s) * k
    if tw > w then k = k * w / tw; tw = w end
    local th = font:getHeight() * k
    local tx = x
    if opts.align == "center" then tx = x + (w - tw) / 2 elseif opts.align == "right" then tx = x + w - tw end
    local ty = y + (h - th) / 2
    if opts.shadow ~= false then
      G.setColor(0, 0, 0, 0.45)
      G.print(s, tx + 0.8, ty + 0.8, 0, k, k)
    end
    local c = opts.color or { 1, 1, 1, 1 }
    G.setColor(c[1], c[2], c[3], c[4] or 1)
    G.print(s, tx, ty, 0, k, k)
    G.setColor(1, 1, 1, 1)
  end

  return L
end
