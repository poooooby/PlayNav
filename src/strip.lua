-- The PlayNav strip across the top of a bottom screen, as the game draws it over Super
-- Training and Pokemon-Amie (a/0/2/4: the grey strip with its stepped edge, the grey arrows).
-- Its arrows switch between the two. Drawn in app space under the hidden tab strip
-- (`bleed` above y 0); `hit` says which arrow a tap is on.
--
-- Strip = strip(assetsFn) ; Strip.draw(G, w, bleed) ; Strip.hit(x, y, w, bleed) -> "left" | "right" | nil

return function(assetsFn)
  local Strip = { H = 16.8 }

  local function art(id)
    local A = assetsFn and assetsFn()
    if not A then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end

  function Strip.draw(G, w, bleed)
    local strip = art("training/home_strip")
    local y0 = -(bleed or 0)
    if strip then
      local sw, sh = strip:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(strip, 0, y0, 0, (w / 2) / sw, Strip.H / sh)
      G.draw(strip, w, y0, 0, -(w / 2) / sw, Strip.H / sh)
    else
      G.setColor(0.45, 0.46, 0.5, 1)
      G.rectangle("fill", 0, y0, w, Strip.H)
    end
    local arrow = art("training/home_arrow")
    local s = 14.4
    if arrow then
      local aw, ah = arrow:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(arrow, 4, y0 + 1.6, 0, s / aw, s / ah)
      G.draw(arrow, w - 4, y0 + 1.6, 0, -s / aw, s / ah)
    else
      G.setColor(0.9, 0.9, 0.92, 1)
      G.polygon("fill", 6, y0 + 8.4, 16, y0 + 3, 16, y0 + 13.8)
      G.polygon("fill", w - 6, y0 + 8.4, w - 16, y0 + 3, w - 16, y0 + 13.8)
    end
    G.setColor(1, 1, 1, 1)
  end

  function Strip.hit(x, y, w, bleed)
    local y0 = -(bleed or 0)
    if y < y0 or y > y0 + Strip.H + 4 then return nil end
    if x <= 34 then return "left" end
    if x >= w - 34 then return "right" end
    return nil
  end

  return Strip
end
