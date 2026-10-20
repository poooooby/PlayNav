-- One still frame of a Pokemon's front / back pic, whatever mod hands it out (shared as
-- mod.stillPic). The game's own pics are one 64x64 frame. A sprite mod may animate:
-- g9-battle-sprites-gen3 picks the frame from the clock each time a pic is asked for
-- (frameIndex: love.timer.getTime() x its fps), so a screen that asks once gets whatever pose
-- was showing, and one that asks every frame animates. `call` asks with the clock held at 0,
-- so a clock-driven provider answers with its first frame (the same cached frame every time).
-- `still` cuts the first frame out of an entry handed out as a sheet (a quad, a list of quads,
-- or a strip of `frames`) into an image of its own; a plain entry comes back as it is.

return function(mod)
  local SP = {}

  -- fn(...) with love.timer.getTime answering 0 for the call (restored at once, even on error)
  function SP.call(fn, ...)
    local T = love and love.timer
    local real = T and T.getTime
    local swapped = false
    if real then swapped = pcall(function() T.getTime = function() return 0 end end) end
    local ok, a = pcall(fn, ...)
    if swapped then pcall(function() T.getTime = real end) end
    if ok then return a end
    return nil
  end

  local cut = setmetatable({}, { __mode = "k" })   -- entry -> its first frame, made once

  -- the entry's first frame: { image, w, h } (plus anything else the entry carried)
  function SP.still(entry)
    if type(entry) ~= "table" or not entry.image then return entry end
    local quad = entry.quad
    if not quad and type(entry.quads) == "table" then quad = entry.quads[0] or entry.quads[1] end
    local img = entry.image
    if not quad and tonumber(entry.frames) and tonumber(entry.frames) > 1 and img.getDimensions then
      local iw, ih = img:getDimensions()
      local w, h = tonumber(entry.w) or iw, tonumber(entry.h) or ih
      if (w < iw or h < ih) and love and love.graphics then
        local ok, q = pcall(love.graphics.newQuad, 0, 0, w, h, iw, ih)
        if ok then quad = q end
      end
    end
    if not quad then return entry end
    local hit = cut[entry]
    if hit ~= nil then return hit or entry end
    local out = false
    pcall(function()
      local _, _, qw, qh = quad:getViewport()
      local c = love.graphics.newCanvas(qw, qh)
      c:setFilter("nearest", "nearest")
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, quad, 0, 0)
      love.graphics.pop()
      out = {}
      for k, v in pairs(entry) do out[k] = v end
      out.image, out.quad, out.quads, out.frames = c, nil, nil, nil
      out.w, out.h = tonumber(entry.w) or qw, tonumber(entry.h) or qh
    end)
    cut[entry] = out
    return out or entry
  end

  -- a provider's pic as one still frame: SP.get(Pokemon.monFrontPic, mon, nil, "summary")
  function SP.get(fn, ...)
    local entry = SP.call(fn, ...)
    if type(entry) ~= "table" or not entry.image then return nil end
    return SP.still(entry)
  end

  return SP
end
