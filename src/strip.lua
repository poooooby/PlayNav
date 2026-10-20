-- The PlayNav strip across the top of a bottom screen, as the game draws it over Super
-- Training and Pokemon-Amie (a/0/2/4: the grey strip with its stepped edge). Drawn in app
-- space under the hidden tab strip (`bleed` above y 0). The game's arrows on it are left
-- out: the PlayNav menu (START -> PLAYNAV) is the way between the apps.
--
-- Strip = strip(assetsFn) ; Strip.draw(G, w, bleed)

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
    G.setColor(1, 1, 1, 1)
  end

  return Strip
end
