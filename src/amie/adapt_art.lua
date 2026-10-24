-- Pictures made from others (data/amie_adapt.lua): a picture another id already has, a part of
-- it, a tinted or greyed copy, or a plain colour. Made once, the first time it is asked for, then kept.
--
-- local Adapt = makeAdapt(mod, table, resolve) ; resolve(id) -> Image | nil (the engine's art)
-- Adapt.image(id) -> Image | nil, owned (true for an id of the table)

return function(mod, list, resolve)
  local Adapt = { images = {} }

  local function make(spec)
    local G = love and love.graphics
    if not G then return nil end
    if spec.fill then
      local data = love.image.newImageData(spec.w or 2, spec.h or 2)
      local c = spec.fill
      data:mapPixel(function() return c[1], c[2], c[3], c[4] or 1 end)
      return G.newImage(data)
    end
    local src = spec.from and resolve(spec.from)
    if not src then return nil end
    if not (spec.tint or spec.crop or spec.grey) then return src end
    local sw, sh = src:getDimensions()
    local c = spec.crop or { 0, 0, sw, sh }
    local canvas = G.newCanvas(c[3], c[4], { dpiscale = src:getDPIScale() })
    G.push("all")
    G.setCanvas(canvas)
    G.origin()
    G.setScissor()
    G.clear(0, 0, 0, 0)
    -- straight colour into the canvas, as the image is read back
    G.setBlendMode("replace", "premultiplied")
    local t = spec.tint or { 1, 1, 1 }
    if spec.grey then G.setColor(1, 1, 1, 1) else G.setColor(t[1], t[2], t[3], t[4] or 1) end
    G.draw(src, G.newQuad(c[1], c[2], c[3], c[4], sw, sh), 0, 0)
    G.pop()
    local data = canvas:newImageData()
    if spec.grey then
      -- its light alone, the tint then laid over it
      data:mapPixel(function(_, _, r, g, b, a)
        local v = (0.3 * r + 0.59 * g + 0.11 * b)
        return v * t[1], v * t[2], v * t[3], a
      end)
    end
    local img = G.newImage(data, { dpiscale = src:getDPIScale(), mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear")
    canvas:release()
    return img
  end

  function Adapt.image(id)
    local spec = list and list[id]
    if not spec then return nil end
    local img = Adapt.images[id]
    if img == nil then
      local ok, made = pcall(make, spec)
      if not ok then mod.log:warn("adapted picture %s: %s", id, tostring(made)) end
      img = ok and made or false
      Adapt.images[id] = img
    end
    return img or nil, true
  end

  return Adapt
end
