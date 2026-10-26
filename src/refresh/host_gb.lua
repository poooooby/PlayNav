-- Everything Pokemon-Amie needs from the Game Boy games (Gen 1 Red / Blue / Yellow, Gen 2 Gold /
-- Silver / Crystal): the same table host_gen3.lua hands out, over the engine's shared Gen 1 / 2
-- pieces - the live game (mod.game: save.party, data, stack, input), Sound and Music, the
-- pictures under assets/generated. Nothing of Gen 3's is required here.
--
-- The games' pictures are four shades of grey coloured by palette as they are drawn; PlayNav
-- draws them in full colour among the 3DS art, so each is coloured once on the CPU (ImageData,
-- no canvas: safe to make anywhere, in a draw too) with its species' palette, the white round
-- it made see-through (the white inside the outline kept), and put on a 64x64 pic as Gen 3's are.
--
-- The top-screen layers are states on the engine's StateStack (layerState below): the layer's
-- pad input from the game's Input, its scene drawn over the 160x144 frame (profile.frame).
--
-- host = makeHost(mod, profile)   profile = src/gen.lua's

return function(mod, profile)
  local function req(name)
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then return m end
    return nil
  end

  local gen = profile.gen
  local H = {
    Sound = req("src.core.Sound"),
    Music = req("src.core.Music"),
    EngineAssets = req("src.render.Assets"),
    Sprites = req("src.pokemon.Sprites"),
    Records = req("src.box.Records"),
    name = "gen" .. tostring(gen),
    gb = true,
    profile = profile,
  }
  if gen == 1 then H.PaletteFX = req("src.render.PaletteFX") else H.Palettes = req("src.world.gen2.Palettes") end

  local function game() return mod.game end
  local function save()
    local g = game()
    return g and g.save or nil
  end
  local function data()
    local g = game()
    return g and g.data or nil
  end
  H.game, H.save, H.data = game, save, data

  function H.available()
    local s = save()
    return s ~= nil and type(s.party) == "table" and data() ~= nil
  end

  function H.now()
    if love and love.timer then return love.timer.getTime() end
    return os.clock()
  end

  function H.wallClock() return os.time() end

  function H.party()
    local s = save()
    return s and type(s.party) == "table" and s.party or {}
  end

  -- one Pokemon's key across saves: the engine's own identity (generation, OT id and name, DVs;
  -- src/box/Records), else the OT id and DVs
  function H.monKey(mon)
    if type(mon) ~= "table" then return nil end
    if H.Records and H.Records.identity then
      local ok, k = pcall(H.Records.identity, gen, mon)
      if ok and type(k) == "string" then return k end
    end
    local d = type(mon.dvs) == "table" and mon.dvs or {}
    return table.concat({ gen, tostring(mon.otId or "?"), d.attack or 0, d.defense or 0, d.speed or 0, d.special or 0 }, "|")
  end

  -- a battle's copy of a party Pokemon: the party record
  function H.resolve(mon)
    local key = H.monKey(mon)
    if not key then return nil end
    for _, p in ipairs(H.party()) do
      if p == mon or H.monKey(p) == key then return p end
    end
    return mon
  end

  function H.isEgg(mon) return type(mon) == "table" and mon.isEgg == true end

  function H.speciesOf(mon) return type(mon) == "table" and mon.species or nil end

  local function def(species)
    local d = data()
    return d and d.pokemon and species and d.pokemon[species] or nil
  end
  H.speciesDef = def

  local function titleCase(s)
    s = tostring(s or "")
    return (s:gsub("_TYPE$", ""):lower():gsub("^%l", string.upper))
  end

  function H.speciesName(species)
    local d = def(species)
    return (d and d.name) or (species and tostring(species)) or "???"
  end

  function H.displayName(mon)
    if type(mon) ~= "table" then return "POKEMON" end
    if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
    if type(mon.name) == "string" and mon.name ~= "" and gen == 2 then return mon.name end
    return H.speciesName(mon.species)
  end

  -- National Dex numbers: the species record's dex (Gen 1's internal index is another order)
  function H.speciesNational(species)
    local d = def(species)
    return d and tonumber(d.dex) or nil
  end
  function H.national(mon) return H.speciesNational(H.speciesOf(mon)) end

  local byNational = nil
  function H.speciesFromNational(n)
    n = tonumber(n)
    if not n then return nil end
    if not byNational then
      byNational = {}
      local d = data()
      for sp, rec in pairs(d and d.pokemon or {}) do
        if type(rec) == "table" and tonumber(rec.dex) and not byNational[rec.dex] then byNational[rec.dex] = sp end
      end
    end
    return byNational[n]
  end

  -- a few common Pokemon for a player who has seen almost nothing (visitors)
  H.VISITOR_NATIONAL = { 16, 19, 10, 13, 21, 25, 29, 32, 41, 43 }
  function H.visitorFallback()
    local out = {}
    for _, n in ipairs(H.VISITOR_NATIONAL) do
      local sp = H.speciesFromNational(n)
      if sp then out[#out + 1] = sp end
    end
    return out
  end

  function H.playerName()
    local s = save()
    local p = s and s.player
    local n = type(p) == "table" and p.name or nil
    return type(n) == "string" and n or nil
  end

  function H.gameCleared()
    local s = save()
    local hof = s and s.hallOfFame
    if type(hof) ~= "table" then return false end
    if tonumber(hof.count) then return tonumber(hof.count) > 0 end
    return #hof > 0
  end

  function H.dexSeen()
    local s = save()
    local seen = s and s.pokedex and s.pokedex.seen
    local out = {}
    if type(seen) ~= "table" then return out end
    for sp, v in pairs(seen) do
      if v and type(sp) == "string" and def(sp) then out[#out + 1] = sp end
    end
    table.sort(out)
    return out
  end

  function H.typesOf(species)
    local d = def(species)
    local t = d and d.types
    if type(t) ~= "table" then return {} end
    local out = {}
    for i, v in ipairs(t) do
      if i == 1 or v ~= t[1] then out[#out + 1] = v end
    end
    return out
  end

  -- "PSYCHIC_TYPE" -> "Psychic" (the names Decor's categories and the shot types use)
  function H.typeName(id)
    if id == nil then return nil end
    return titleCase(id)
  end

  local evoParent
  function H.evoRoot(species)
    if not species then return nil end
    if not evoParent then
      evoParent = {}
      local d = data()
      for sp, rec in pairs(d and d.pokemon or {}) do
        for _, e in ipairs(type(rec) == "table" and rec.evolutions or {}) do
          local into = type(e) == "table" and (e.species or e.into) or nil
          if into and not evoParent[into] then evoParent[into] = sp end
        end
      end
    end
    local root, guard = species, 0
    while evoParent[root] and guard < 8 do root = evoParent[root]; guard = guard + 1 end
    return root
  end

  -- "PSN" | "PAR" | "SLP" | "FRZ" | "BRN" | nil (Gen 1 keeps the short names, Gen 2 words)
  local STATUS = { slp = "SLP", sleep = "SLP", psn = "PSN", poison = "PSN", toxic = "PSN", tox = "PSN",
    brn = "BRN", burn = "BRN", frz = "FRZ", freeze = "FRZ", par = "PAR", paralyze = "PAR", prz = "PAR" }
  function H.statusOf(mon)
    local st = type(mon) == "table" and mon.status or nil
    if type(st) ~= "string" then return nil end
    return STATUS[st:lower()]
  end

  -- ------- pictures, coloured once

  local function white(r, g, b) return r > 0.83 and g > 0.83 and b > 0.83 end

  -- the species' four colours, 0..1, light to dark (nil: greys)
  local function colorsOf(species, shiny)
    local c = nil
    local d = data()
    if gen == 1 and H.PaletteFX and H.PaletteFX.monPal then
      local ok, v = pcall(H.PaletteFX.monPal, d, species)
      c = ok and v or nil
    elseif gen == 2 and H.Palettes and H.Palettes.monColors then
      local ok, v = pcall(H.Palettes.monColors, d and d.gen2Palettes, species, shiny)
      c = ok and v or nil
    end
    if type(c) ~= "table" or #c < 4 then c = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } } end
    local out = {}
    for i = 1, 4 do
      local e = c[i] or { 0, 0, 0 }
      local k = ((e[1] or 0) > 1 or (e[2] or 0) > 1 or (e[3] or 0) > 1) and 255 or 1
      out[i] = { (e[1] or 0) / k, (e[2] or 0) / k, (e[3] or 0) / k }
    end
    return out
  end

  local function imageData(path)
    local A = H.EngineAssets
    if not (A and A.imageData and path) then return nil end
    local ok, d = pcall(A.imageData, path)
    return ok and d or nil
  end

  -- a shaded pic coloured: shade by the red channel (the engine's thresholds), the white
  -- reachable from the edge made see-through (`keyEdge`), every other pixel opaque
  local function colour(src, colors, keyEdge)
    local w, h = src:getDimensions()
    local out = love.image.newImageData(w, h)
    local shade = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = src:getPixel(x, y)
        local s
        -- (a pic may keep its white as see-through: Yellow's back pics do; it is white all the same)
        if a < 0.5 or r > 0.83 then s = 0
        elseif r > 0.5 then s = 1
        elseif r > 0.17 then s = 2
        else s = 3 end
        shade[y * w + x] = s
      end
    end
    local clear = {}
    if keyEdge then
      -- `keyEdge` true: the white reachable from the edge. A number R: the outline closed first
      -- (the inked pixels grown by R, then shrunk by it), so gaps of up to 2R px do not let the
      -- outside in and the white of the body stays - back pics take 4: Gen 1's are dotted and
      -- open at the foot (Yellow's Pikachu by 9); then the white the closing itself sealed in
      -- the outline's nooks goes back to the outside, R / 2 steps, so no white rims the sprite.
      local R = type(keyEdge) == "number" and keyEdge or 0
      local ink = {}
      for i = 0, w * h - 1 do ink[i] = shade[i] > 0 end
      local function grow(src, want)
        local out = {}
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local hit = not want
            for dy = -R, R do
              local yy = y + dy
              for dx = -R, R do
                local xx = x + dx
                local v
                if xx < 0 or yy < 0 or xx >= w or yy >= h then v = false else v = src[yy * w + xx] end
                if v == want then hit = want; break end
              end
              if hit == want then break end
            end
            out[y * w + x] = hit
          end
        end
        return out
      end
      local barrier = R > 0 and grow(grow(ink, true), false) or ink
      local stack = {}
      local function push(x, y)
        local i = y * w + x
        if not clear[i] and shade[i] <= 0 and not barrier[i] then clear[i] = true; stack[#stack + 1] = i end
      end
      for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
      for y = 0, h - 1 do push(0, y); push(w - 1, y) end
      while #stack > 0 do
        local i = table.remove(stack)
        local x, y = i % w, math.floor(i / w)
        if x > 0 then push(x - 1, y) end
        if x < w - 1 then push(x + 1, y) end
        if y > 0 then push(x, y - 1) end
        if y < h - 1 then push(x, y + 1) end
      end
      if R > 0 then
        for _ = 1, math.floor(R / 2) do
          local add = {}
          for i in pairs(clear) do
            local x, y = i % w, math.floor(i / w)
            local function near(xx, yy)
              if xx < 0 or yy < 0 or xx >= w or yy >= h then return end
              local j = yy * w + xx
              if not clear[j] and shade[j] <= 0 and barrier[j] and not ink[j] then add[#add + 1] = j end
            end
            near(x - 1, y); near(x + 1, y); near(x, y - 1); near(x, y + 1)
          end
          for _, j in ipairs(add) do clear[j] = true end
        end
      end
    end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = y * w + x
        local s = shade[i]
        if s < 0 or clear[i] then out:setPixel(x, y, 0, 0, 0, 0)
        else
          local c = colors[s + 1]
          out:setPixel(x, y, c[1], c[2], c[3], 1)
        end
      end
    end
    return out
  end

  -- a picture onto a size x size pic, scaled by a whole or nearest step to `fit`, its feet on
  -- the bottom and centred across
  local function onPic(src, size, fit)
    local w, h = src:getDimensions()
    local k = math.max(1, math.floor(fit / math.max(w, h) + 1e-9))
    if math.max(w, h) * k > size then k = 1 end
    local out = love.image.newImageData(size, size)
    local ox = math.floor((size - w * k) / 2)
    local oy = size - h * k
    for y = 0, h * k - 1 do
      for x = 0, w * k - 1 do
        local r, g, b, a = src:getPixel(math.floor(x / k), math.floor(y / k))
        if a > 0 then out:setPixel(ox + x, oy + y, r, g, b, a) end
      end
    end
    return out
  end

  local function newImage(d)
    local ok, img = pcall(love.graphics.newImage, d)
    if not ok then return nil end
    img:setFilter("nearest", "nearest")
    return img
  end

  local pics = {}
  local function picFor(species, side, mon, shiny)
    if not (species and love and love.image and love.graphics) then return nil end
    local key = table.concat({ tostring(species), side, shiny and "s" or "" }, "|")
    local hit = pics[key]
    if hit ~= nil then return hit or nil end
    pics[key] = false
    local path, trueColor = nil, false
    if H.Sprites and H.Sprites.path then
      local ok, p, t = pcall(H.Sprites.path, data(), species, side, { mon = mon, kind = "summary" })
      if ok then path, trueColor = p, t end
    end
    if not path then
      local d = def(species)
      path = d and (side == "back" and d.spriteBack or d.spriteFront)
    end
    local src = imageData(path)
    if not src then return nil end
    local ok, entry = pcall(function()
      local coloured = trueColor and src or colour(src, colorsOf(species, shiny), side == "back" and 4 or true)
      -- the 64x64 Gen 3 pics are drawn feet down; a back pic (32 / 48 px) grows to fill it
      local pic = onPic(coloured, 64, side == "back" and 64 or 56)
      local img = newImage(pic)
      return img and { image = img, w = 64, h = 64 } or nil
    end)
    pics[key] = (ok and entry) or false
    return ok and entry or nil
  end

  local function shinyOf(mon) return type(mon) == "table" and mon.shiny == true end


  -- Front and back pics are Pokemon Crystal's from PlayNav's atlases (assets/gb_fronts.png,
  -- gb_backs.png + data/gb_fronts.lua, gb_backs.lua; tools/gb_backs_atlas.py): full colour, the
  -- bodies solid. H.setBacks(backs, read, fronts) hands them in (read(path) -> the PNG's bytes);
  -- each atlas is read once on the CPU, each pic made the first time it is asked for
  -- (ImageData, no canvas). A Pokemon without a cell: its game's own pic.
  local sets = {
    back = { data = nil, atlas = nil, file = "assets/gb_backs.png", pics = {} },
    front = { data = nil, atlas = nil, file = "assets/gb_fronts.png", pics = {} },
  }
  local readFile = nil
  function H.setBacks(backData, read, frontData)
    sets.back.data = type(backData) == "table" and backData or nil
    sets.front.data = type(frontData) == "table" and frontData or nil
    readFile = read
  end

  local function atlasOf(set)
    if set.atlas ~= nil then return set.atlas or nil end
    set.atlas = false
    local bytes = readFile and readFile(set.file)
    if bytes and love and love.image and love.filesystem then
      local ok, img = pcall(function()
        return love.image.newImageData(love.filesystem.newFileData(bytes, set.file:match("[^/]+$")))
      end)
      if ok and img then set.atlas = img end
    end
    return set.atlas or nil
  end

  local function hexColour(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
  end

  -- the atlas key: the National number; Unown's letter after it (A is the plain one)
  local function backKey(mon)
    local n = H.national(mon)
    if not n then return nil end
    local key = tostring(n)
    local letter = mon.unownLetter
    if n == 201 and type(letter) == "string" and letter:upper() ~= "A" then key = key .. letter:upper() end
    return key
  end

  local function crystalPic(side, mon, shiny)
    local set = sets[side]
    local D = set.data
    local key = D and backKey(mon)
    local rec = key and (D.cells[key] or D.cells[key:match("^%d+")])
    if not rec then return nil end
    local cache = (shiny and "s" or "n") .. key
    local hit = set.pics[cache]
    if hit ~= nil then return hit or nil end
    set.pics[cache] = false
    local atlas = atlasOf(set)
    if not (atlas and love.graphics) then return nil end
    local cell, pal = rec, rec.pal
    if shiny and rec.shinyCell then cell, pal = rec.shinyCell, rec.shinyCell.pal
    elseif shiny and rec.shiny then pal = rec.shiny end
    local ok, entry = pcall(function()
      local size, step = D.size or 56, D.step or 63
      local cols = {}
      for i, h in ipairs(pal) do cols[i] = { hexColour(h) } end
      local w, h = cell.w, cell.h
      local src = love.image.newImageData(w, h)
      local ox, oy = cell.c * size, cell.r * size
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local v = atlas:getPixel(ox + x, oy + y)
          local n = math.floor(v * 255 / step + 0.5)
          local c = n > 0 and cols[n]
          if c then src:setPixel(x, y, c[1], c[2], c[3], 1) end
        end
      end
      local img = newImage(onPic(src, 64, 64))
      return img and { image = img, w = 64, h = 64 } or nil
    end)
    set.pics[cache] = (ok and entry) or false
    return ok and entry or nil
  end

  -- shiny: Gen 2's flag; Gen 1 by its DVs, as the engine's own pics read it
  local function shinyNow(mon)
    local shiny = shinyOf(mon)
    if gen == 1 and not shiny and type(mon.dvs) == "table" then
      local Stats = req("src.pokemon.Stats")
      if Stats and Stats.isShiny then
        local ok, s = pcall(Stats.isShiny, mon.dvs)
        shiny = ok and s == true
      end
    end
    return shiny
  end

  function H.backPic(mon)
    if type(mon) ~= "table" then return nil end
    local shiny = shinyNow(mon)
    return crystalPic("back", mon, shiny) or picFor(mon.species, "back", mon, shiny)
  end

  function H.frontPic(mon)
    if type(mon) ~= "table" then return nil end
    local shiny = shinyNow(mon)
    if mon.isEgg then return picFor("EGG", "front", mon, false) or picFor(mon.species, "front", mon, false) end
    return crystalPic("front", mon, shiny) or picFor(mon.species, "front", mon, shiny)
  end

  function H.speciesFrontPic(species) return picFor(species, "front", nil, false) end

  -- party icons: { image, quads[0], quads[1], frames = 2, w = 16, h = 16 } in the mon's colours.
  -- Gen 2's are 16x32 strips of two frames; Gen 1's are a class of icon (byDex), the left half
  -- of a 16 px frame mirrored as the game draws them (HELIX whole)
  local icons = {}
  local function iconFor(species, egg)
    if not (species and love and love.image and love.graphics) then return nil end
    local key = egg and "EGG" or species
    local hit = icons[key]
    if hit ~= nil then return hit or nil end
    icons[key] = false
    local d = data()
    local set = d and (gen == 2 and (d.gen2Icons or d.icons) or d.icons)
    if type(set) ~= "table" then return nil end
    local path, name, frames = nil, nil, {}
    if gen == 2 then
      name = egg and "ICON_EGG" or (set.species and set.species[species])
      local e = name and set.icons and set.icons[name]
      path = e and e.image
      frames = { 0, 16 }
    else
      local rec = def(species)
      local entry = (set.bySpecies and set.bySpecies[species]) or (rec and rec.icon)
      if type(entry) == "string" then name = entry; path = set.icons and set.icons[entry]
      elseif type(entry) == "table" then path = entry.image end
      if not path then
        name = rec and rec.dex and set.byDex and set.byDex[rec.dex]
        path = name and set.icons and set.icons[name]
      end
    end
    local src = imageData(path)
    if not src then return nil end
    local ok, entry = pcall(function()
      local w, h = src:getDimensions()
      if gen == 1 then
        -- the party menu's two frames: the sheet's first and its second (an overworld sheet of
        -- 6 frames walks on its fourth), a 16 px icon alone (BALL, HELIX) is its own only frame
        local f1 = h >= 64 and 3 or (h >= 32 and 1 or 0)
        frames = { 0, f1 * 16 }
      end
      local colored = colour(src, colorsOf(egg and "EGG" or species, false), true)
      local strip = love.image.newImageData(16, 32)
      for f = 1, 2 do
        local sy = math.min(frames[f] or 0, math.max(0, h - 16))
        for y = 0, 15 do
          for x = 0, 15 do
            local sx = x
            if gen == 1 and name ~= "HELIX" and w <= 16 and x >= 8 then sx = 15 - x end
            if sx < w and sy + y < h then
              local r, g, b, a = colored:getPixel(sx, sy + y)
              strip:setPixel(x, (f - 1) * 16 + y, r, g, b, a)
            end
          end
        end
      end
      local img = newImage(strip)
      if not img then return nil end
      local q0 = love.graphics.newQuad(0, 0, 16, 16, 16, 32)
      local q1 = love.graphics.newQuad(0, 16, 16, 16, 16, 32)
      return { image = img, quads = { [0] = q0, [1] = q1 }, frames = 2, w = 16, h = 16 }
    end)
    icons[key] = (ok and entry) or false
    return ok and entry or nil
  end

  -- G9 Battle Sprites (the Gen 1 / 2 mod) with its PARTY ICONS on: its own true-colour icons,
  -- the HD 64x64 cells it publishes for other screens (exports.iconArtHD, two frames), so
  -- PlayNav's screens show the same icons as the party list. Its atlas is decoded lazily: a
  -- first ask can answer nil, and the next frame asks again (only a found icon is kept).
  local G9 = "g9-battle-sprites"
  local g9Icons = {}
  local function g9Icon(mon)
    local lib = mod.find and mod:find(G9)
    local ex = lib and lib.exports
    if not (type(ex) == "table" and type(ex.iconArtHD) == "function") then return nil end
    local g = game()
    local opts = g and g.mods and g.mods.modOptions and g.mods.modOptions[G9]
    if type(opts) == "table" and opts.party_icons == false then return nil end
    local key = mon.isEgg and "EGG" or tostring(mon.species) .. (mon.gender == "female" and "/f" or "")
    local hit = g9Icons[key]
    if hit then return hit end
    local ok0, q0, img, cell = pcall(ex.iconArtHD, mon, 0)
    local ok1, q1 = pcall(ex.iconArtHD, mon, 1)
    if not (ok0 and type(q0) == "table" and q0.full and img) then return nil end
    local size = tonumber(cell) or 64
    local entry = { image = img, quads = { [0] = q0.full, [1] = (ok1 and type(q1) == "table" and q1.full) or q0.full },
      frames = 2, w = size, h = size }
    g9Icons[key] = entry
    return entry
  end

  function H.icon(mon)
    if type(mon) ~= "table" then return nil end
    return g9Icon(mon) or iconFor(mon.species, mon.isEgg == true)
  end

  function H.iconSpecies(species)
    return (species and g9Icon({ species = species })) or iconFor(species, false)
  end

  -- ------- sound

  local SOUNDS = nil
  function H.setSounds(t) SOUNDS = type(t) == "table" and t["gen" .. gen] or nil end

  function H.playCry(mon)
    local sp = H.speciesOf(mon)
    if sp and H.Sound and H.Sound.playCry and data() then pcall(H.Sound.playCry, data(), sp) end
  end

  -- a Gen 3 effect's name (PlayNav's stand-ins) -> the game's own (data/gb_sounds.lua)
  function H.seLabel(name)
    local label = SOUNDS and SOUNDS[name]
    if type(label) == "table" then
      local d = data()
      local sfx = d and d.audio and d.audio.sfx or {}
      for _, l in ipairs(label) do if sfx[l] then return l end end
      return nil
    end
    return label
  end

  function H.playSe(name)
    local label = H.seLabel(name)
    if label and H.Sound and H.Sound.play and data() then pcall(H.Sound.play, data(), label) end
  end

  -- ------- the top-screen layers: states on the engine's StateStack

  -- the pad as the Gen 3 layers read it (input:wasPressed / isDown over the game's Input)
  local padProxy = {}
  function padProxy:wasPressed(b)
    local g = game()
    local inp = g and g.input
    return inp ~= nil and inp.pressed ~= nil and inp.pressed[b] == true
  end
  function padProxy:isDown(b)
    local g = game()
    local inp = g and g.input
    if not inp then return false end
    if inp.state and inp.state[b] then return true end
    return inp.aliasHeld ~= nil and inp.aliasHeld[b] == true
  end
  H.padProxy = padProxy

  local states = {}   -- [id] = the state pushed for that layer id
  local function layerState(id, module)
    local st = { isOpaque = true, playNavId = id, module = module, isMenu = module.isMenu }
    function st.update(self, dt)
      if module.handleInput then
        local ok, err = pcall(module.handleInput, padProxy)
        if not ok then mod.log:warn("layer %s input failed: %s", id, tostring(err)) end
      end
      if module.update then module.update(dt) end
    end
    -- the scene over the 160x144 frame: the layer draws in 240-unit space, the frame its
    -- profile.frame (src/hd_top.lua redraws it at window resolution and sets hdLive)
    function st.draw(self)
      local G = love and love.graphics
      if not G then return end
      local f = profile.frame
      local k = profile.frameW / f.w
      G.push("all")
      G.scale(k, k)
      G.translate(-f.x, -f.y)
      local P = H.PaletteFX
      if P and P.markTrueColor then pcall(P.markTrueColor, 0, 0, profile.frameW, profile.frameH) end
      if module.hdLive then
        G.setColor(0, 0, 0, 1)
        G.rectangle("fill", f.x, f.y, f.w, f.h)
      elseif module.drawScene then
        module.extent = f
        local ok, err = pcall(module.drawScene, G)
        module.extent = nil
        if not ok then mod.log:warn("layer %s draw failed: %s", id, tostring(err)) end
      end
      G.pop()
    end
    -- Gen 1 shades the frame through palettes: ours is drawn in full colour (the trueColor
    -- opt-out over the whole screen)
    if gen == 1 and H.PaletteFX and H.PaletteFX.trueColorZone then
      local okZ, zone = pcall(H.PaletteFX.trueColorZone, 0, 0, 20, 18)
      local zones = okZ and zone and { zone } or nil
      if zones then st.sgbPalettes = function() return zones end end
    end
    return st
  end

  local function stack()
    local g = game()
    return g and g.stack or nil
  end

  function H.pushLayerAs(id, module)
    local stk = stack()
    if not (stk and stk.push) then return false, "no stack" end
    if states[id] and H.layerOpenAs(id) then return true end
    local st = layerState(id, module)
    local ok, err = pcall(stk.push, stk, st)
    if not ok then return false, err end
    states[id] = st
    return true
  end

  function H.popLayerAs(id)
    local st, stk = states[id], stack()
    if not (st and stk) then return false end
    states[id] = nil
    local list = stk.states or {}
    if list[#list] == st then return pcall(stk.pop, stk) end
    -- not on top (something of the game's over it): taken out where it is
    for i = #list, 1, -1 do
      if list[i] == st then
        table.remove(list, i)
        if type(st.exit) == "function" then pcall(st.exit, st) end
        return true
      end
    end
    return false
  end

  function H.layerOpenAs(id)
    local st, stk = states[id], stack()
    if not (st and stk) then return false end
    for _, s in ipairs(stk.states or {}) do if s == st then return true end end
    return false
  end

  -- the stack as src/hd_top.lua reads Gen 3's: top() -> { id, mod } for a layer of ours
  H.Stack = {
    top = function()
      local stk = stack()
      local top = stk and stk.top and stk:top()
      if type(top) == "table" and top.playNavId then return { id = top.playNavId, mod = top.module } end
      return top and { id = "?", mod = nil } or nil
    end,
  }

  H.LAYER_ID = "play_nav_amie"
  function H.pushLayer(module) return H.pushLayerAs(H.LAYER_ID, module) end
  function H.popLayer() return H.popLayerAs(H.LAYER_ID) end
  function H.layerOpen() return H.layerOpenAs(H.LAYER_ID) end

  -- the field: nothing of the game's on the stack over the overworld (Gen 2 keeps the
  -- overworld off the stack; Gen 1 has it at the bottom)
  function H.inField()
    local g = game()
    if not g then return false end
    if g.phase ~= nil and g.phase ~= "play" and g.phase ~= "field" then return false end
    local stk = g.stack
    local list = stk and stk.states or {}
    if gen == 2 then return #list == 0 end
    return #list <= 1 and (list[1] == nil or list[1] == g.overworld)
  end

  -- closes the START menu the game has open (Gen 1 / 2: the top state)
  function H.closeStartMenu()
    local stk = stack()
    local top = stk and stk.top and stk:top()
    if type(top) ~= "table" then return false end
    -- (pushed through Screens.push, which stamps the screen's id: Gen 2 prefixes its own)
    if top.screenId ~= (gen == 2 and "Gen2StartMenu" or "Start" .. "Menu") then return false end
    return pcall(stk.pop, stk)
  end

  function H.activeMon(ev)
    local b = ev and ev.battle
    local mon = b and b.player
    if type(mon) == "table" and mon.mon then mon = mon.mon end
    if type(mon) ~= "table" or not mon.species then
      for _, p in ipairs(H.party()) do
        if (tonumber(p.hp) or 0) > 0 and not H.isEgg(p) then return p end
      end
      return H.party()[1]
    end
    return H.resolve(mon)
  end

  function H.leadMon()
    for _, p in ipairs(H.party()) do
      if not H.isEgg(p) then return p end
    end
    return nil
  end

  function H.battleActive()
    local g = game()
    for _, st in ipairs(g and g.stack and g.stack.states or {}) do
      if type(st) == "table" and (st.isBattleState or st.isGen2BattleState or st.screenId == "Gen2BattleState") then
        return true
      end
    end
    return false
  end

  return H
end
