-- Where on the sprite the stylus is, and what the species thinks of it.
-- The body is the unit ellipse (bx, by in -1..1, y down) the apps already
-- use for marks; zones are coarse bands over it. Per-species spots come from
-- data/petting_gen3.lua keyed by National Dex number.

return function(DATA)
  local P = { DATA = DATA or {} }

  P.ZONES = { "head", "face", "cheeks", "chest", "belly", "side", "limbs", "bottom" }

  -- the zone under a body-space point
  function P.zoneAt(bx, by)
    local ax = math.abs(bx)
    if by < -0.55 then return "head" end
    if by < -0.1 then
      if ax < 0.35 then return "face" end
      if ax < 0.75 then return "cheeks" end
      return "side"
    end
    if by < 0.25 then
      if ax < 0.45 then return "chest" end
      if ax < 0.8 then return "side" end
      return "limbs"
    end
    if by < 0.65 then
      if ax < 0.5 then return "belly" end
      return "limbs"
    end
    return "bottom"
  end

  -- a representative point (body space) inside a zone, for tests and hints
  P.ZONE_POINT = {
    head = { 0, -0.8 }, face = { 0, -0.3 }, cheeks = { 0.5, -0.3 }, chest = { 0, 0.05 },
    belly = { 0, 0.45 }, side = { 0.6, 0.05 }, limbs = { 0.7, 0.45 }, bottom = { 0, 0.85 },
  }

  function P.row(national)
    return P.DATA[tonumber(national) or -1]
  end

  -- "normal" | "favored" | "disfavored" | "effect", plus the effect kind
  -- ("burning", "paralyzing", "freezing", "cutting", "gooey", "slimy",
  -- "haunted") when the stylus is on one. Interrupting effects are the
  -- first four; the others are cosmetic and pet as normal.
  P.INTERRUPTS = { burning = true, paralyzing = true, freezing = true, cutting = true }

  function P.spot(national, zone)
    local r = P.row(national)
    if not r then return "normal" end
    local fav, dis, ek, ez = r[1], r[2], r[3], r[4]
    if ek and (ez == "all" or ez == zone) then
      if P.INTERRUPTS[ek] then return "effect", ek end
      return "normal", ek
    end
    if fav and zone == fav then return "favored" end
    if dis and zone == dis then return "disfavored" end
    return "normal"
  end

  function P.spotAt(national, bx, by)
    return P.spot(national, P.zoneAt(bx, by))
  end

  -- the original Bulbapedia text, for hints and debugging
  function P.describe(national)
    local r = P.row(national)
    if not r then return nil end
    return { favored = r[5], disfavored = r[6], effect = r[3], effectWhere = r[7] }
  end

  return P
end
