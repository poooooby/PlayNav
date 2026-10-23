-- Pokemon-Amie's Decor pictures from PlayNav's own atlases: a greyscale image of colour numbers
-- and each picture's palette - the cushions and objects (assets/amie_decor.png +
-- data/amie_decor.lua, tools/decor_atlas.py, 8-bit) and the wallpapers with their thumbnails
-- (assets/amie_walls.png + data/amie_walls.lua, tools/wall_atlas.py, 16-bit), and the Poke
-- Puffs (assets/amie_puffs.png + data/amie_puffs.lua, tools/puff_atlas.py, 8-bit), and PLAY's
-- hand (assets/amie_hand.png + data/amie_hand.lua, tools/hand_atlas.py, 8-bit), and Berry
-- Picker's art (assets/amie_berry.png + data/amie_berry.lua, tools/berry_atlas.py, 16-bit; its
-- alias table names the same picture under another layout pack), and Head It's
-- (assets/amie_head.png + data/amie_head.lua, tools/head_atlas.py, 16-bit). A picture is
-- expanded into a full-colour image the first time it is asked for, then kept.
--
-- local Art = makeDecorArt(mod, data, file) ; Art.image(id) -> Image | nil, owned (true for an
-- id of the atlas); data = the data file's table ({ depth?, cells, alias? })

return function(mod, data, file)
  local cells = data and data.cells
  local alias = data and data.alias or {}
  local top = (data and data.depth == 16) and 65535 or 255
  local Art = { images = {} }
  local atlasData = nil
  local pals = {}

  local function parsePalette(pal)
    local out = {}
    for i, hex in ipairs(pal or {}) do
      local r, g, b, a = hex:match("^(%x%x)(%x%x)(%x%x)(%x%x)$")
      out[i] = r and { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, tonumber(a, 16) / 255 }
        or { 0, 0, 0, 0 }
    end
    return out
  end

  local function expand(cell)
    local G, LI, LF = love and love.graphics, love and love.image, love and love.filesystem
    if not (G and LI and LF) then return nil end
    if not atlasData then
      local bytes = mod:read(file)
      if not bytes then return nil end
      atlasData = LI.newImageData(LF.newFileData(bytes, file:match("[^/]+$")))
    end
    local pal = pals[cell]
    if not pal then pal = parsePalette(cell.pal); pals[cell] = pal end
    local A, x0, y0 = atlasData, cell.x, cell.y
    local out = LI.newImageData(cell.w, cell.h)
    out:mapPixel(function(x, y)
      local c = pal[math.floor(A:getPixel(x0 + x, y0 + y) * top + 0.5)]
      if not c then return 0, 0, 0, 0 end
      return c[1], c[2], c[3], c[4]
    end)
    local img = G.newImage(out, { mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear")
    return img
  end

  function Art.image(id)
    id = alias[id] or id
    local cell = cells and cells[id]
    if not cell then return nil end
    local img = Art.images[id]
    if img == nil then
      local ok, made = pcall(expand, cell)
      if not ok then mod.log:warn("decor sprite %s: %s", id, tostring(made)) end
      img = ok and made or false
      Art.images[id] = img
    end
    return img or nil, true
  end

  function Art.has(id) return cells ~= nil and cells[alias[id] or id] ~= nil end

  return Art
end
