-- PlayNav's own look for its engine-drawn screens (the PLAYNAV import screen, the menu):
-- one accent, the banner's violet, over a near-black ground; the banner across the top
-- (the violet band, the two-figure icon, the outlined wordmark; imgs/banner.png is the
-- model, GitHub only) and the round x up in the strip's rows.
--
-- B = brand() ; B.INK ; B.col(G, c, a) ; B.banner(G, W, bleed) ; B.close(G, c)

return function()
  local B = {}

  B.INK = { bg = { 0.055, 0.04, 0.09 }, glow = { 0.486, 0.227, 0.929 },
    text = { 0.66, 0.61, 0.78 }, dim = { 0.48, 0.435, 0.59 }, bright = { 0.92, 0.9, 0.98 },
    accent = { 0.545, 0.36, 0.965 }, sheen = { 0.68, 0.53, 1.0 }, line = { 0.255, 0.2, 0.42 },
    track = { 0.133, 0.1, 0.21 }, warn = { 1.0, 0.69, 0.125 }, ok = { 0.2, 0.83, 0.6 },
    bandL = { 0.21, 0.1, 0.35 }, bandR = { 0.08, 0.045, 0.15 }, outline = { 0.42, 0.18, 0.85 } }
  local INK = B.INK

  function B.col(G, c, a) G.setColor(c[1], c[2], c[3], a or 1) end
  local col = B.col

  -- a word with a soft glow and a rounded outline under its fill
  function B.wordmark(G, word, tx, ty, k, fill, outline, glow)
    if glow then
      col(G, glow, 0.16)
      for a = 0, 7 do
        G.print(word, tx + 3.1 * math.cos(a * math.pi / 4), ty + 3.1 * math.sin(a * math.pi / 4), 0, k, k)
      end
    end
    col(G, outline)
    for a = 0, 11 do
      G.print(word, tx + 1.7 * math.cos(a * math.pi / 6), ty + 1.7 * math.sin(a * math.pi / 6), 0, k, k)
    end
    col(G, fill)
    G.print(word, tx, ty, 0, k, k)
  end

  -- the band from the top edge (bleed rows above y 0) down to y 24, a hairline at 30
  function B.banner(G, W, bleed)
    local y0, y1 = -(bleed or 0), 24
    local n = 8
    for i = 0, n - 1 do
      local t = i / (n - 1)
      G.setColor(INK.bandL[1] + (INK.bandR[1] - INK.bandL[1]) * t,
        INK.bandL[2] + (INK.bandR[2] - INK.bandL[2]) * t,
        INK.bandL[3] + (INK.bandR[3] - INK.bandL[3]) * t, 1)
      G.rectangle("fill", i * W / n, y0, W / n + 1, y1 - y0)
    end
    col(G, INK.outline, 0.55)
    G.rectangle("fill", 0, y1 - 1.2, W, 1.2)
    local f = G.getFont()
    local k = 1.55
    local word = "PlayNav"
    local tw = f:getWidth(word) * k
    local iconW = 30
    local x0 = (W - (iconW + 9 + tw)) / 2
    local cy = (y0 + y1) / 2 - 1
    -- the icon: a violet rounded square, white border, two figures
    local ic = { x = x0 + iconW / 2, y = cy }
    col(G, { 0.49, 0.25, 0.9 })
    G.rectangle("fill", ic.x - 14, ic.y - 10.5, 28, 21, 6, 6)
    col(G, { 1, 1, 1 }, 0.95)
    G.setLineWidth(2)
    G.rectangle("line", ic.x - 14, ic.y - 10.5, 28, 21, 6, 6)
    G.setLineWidth(1)
    for _, dx in ipairs({ -6, 6 }) do
      G.circle("fill", ic.x + dx, ic.y - 3.8, 2.8)
      -- the body: an arch, round at the shoulders and flat at the floor
      G.rectangle("fill", ic.x + dx - 4, ic.y - 0.2, 8, 7.2, 3.5, 3.5)
      G.rectangle("fill", ic.x + dx - 4, ic.y + 3.4, 8, 3.6)
    end
    B.wordmark(G, word, x0 + iconW + 9, cy - f:getHeight() * k / 2, k, { 0.96, 0.94, 1 }, INK.outline, INK.glow)
    -- a hairline under the band, bright in the middle
    for _, seg in ipairs({ { 42, 0.12 }, { 86, 0.3 } }) do
      col(G, INK.accent, seg[2])
      G.rectangle("fill", W / 2 - seg[1], 30, seg[1] * 2, 1)
    end
  end

  -- the round x at c = { x, y }: a dark disc, a light ring, two thick strokes
  function B.close(G, c)
    local r, d = 8.5, 3.2
    col(G, INK.track)
    G.circle("fill", c.x, c.y, r)
    G.setLineWidth(1.5)
    col(G, INK.sheen, 0.8)
    G.circle("line", c.x, c.y, r)
    G.setLineWidth(2.2)
    G.setLineStyle("smooth")
    col(G, INK.bright)
    G.line(c.x - d, c.y - d, c.x + d, c.y + d)
    G.line(c.x - d, c.y + d, c.x + d, c.y - d)
    G.setLineWidth(1)
  end

  return B
end
