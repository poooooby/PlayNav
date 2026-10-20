-- One still frame of a Pokemon's front / back pic, whatever mod hands it out (shared as
-- mod.stillPic). The game's own pics are one 64x64 frame. A sprite mod may animate:
-- g9-battle-sprites-gen3 picks the frame from the clock each time a pic is asked for
-- (frameIndex: love.timer.getTime() x its fps), so a screen that asks once gets whatever pose
-- was showing, and one that asks every frame animates. `callAt` asks with the clock held at a
-- given time. `get` asks across the animation's loop and keeps its resting pose: the frame
-- whose opaque box the loop holds longest (frame 0 is often a dip or a crouch). A provider
-- that answers the same image at every moment is static and comes back as it is.
-- `still` cuts the first frame out of an entry handed out as a sheet (a quad, a list of quads,
-- or a strip of `frames`) into an image of its own; a plain entry comes back as it is.

return function(mod)
  local SP = {}

  SP.STEP = 1 / 60        -- the clock's step while sampling a loop
  SP.MAX_S = 12           -- the longest loop sampled
  SP.MAX_FRAMES = 128     -- the most distinct frames a loop may have

  -- fn(...) with love.timer.getTime answering `t` for the call (restored at once, even on error)
  function SP.callAt(t, fn, ...)
    local T = love and love.timer
    local real = T and T.getTime
    local swapped = false
    if real then swapped = pcall(function() T.getTime = function() return t end end) end
    local ok, a = pcall(fn, ...)
    if swapped then pcall(function() T.getTime = real end) end
    if ok then return a end
    return nil
  end

  function SP.call(fn, ...) return SP.callAt(0, fn, ...) end

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

  -- an image's opaque box at its own (logical) size, as a key "x0,y0,x1,y1"; nil without graphics
  function SP.boxKey(img)
    if not (love and love.graphics and img and img.getDimensions) then return nil end
    local key
    pcall(function()
      local w, h = img:getDimensions()
      local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.pop()
      local data = c:newImageData()
      local x0, y0, x1, y1 = w, h, -1, -1
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local _, _, _, a = data:getPixel(x, y)
          if a > 0.1 then
            if x < x0 then x0 = x end
            if x > x1 then x1 = x end
            if y < y0 then y0 = y end
            if y > y1 then y1 = y end
          end
        end
      end
      data:release()
      c:release()
      key = x0 .. "," .. y0 .. "," .. x1 .. "," .. y1
    end)
    return key
  end

  -- the loop's frames in order with the time each shows: { { entry, n }, ... }; stops when the
  -- first frame comes round again after another, or at MAX_S
  function SP.sample(fn, ...)
    local first = SP.callAt(0, fn, ...)
    if type(first) ~= "table" or not first.image then return nil end
    local list, byImg = { { entry = first, n = 1 } }, { [first.image] = 1 }
    local last = first.image
    for i = 1, math.floor(SP.MAX_S / SP.STEP) do
      local e = SP.callAt(i * SP.STEP, fn, ...)
      local img = type(e) == "table" and e.image
      if not img then break end
      if img == first.image and last ~= first.image then break end
      local j = byImg[img]
      if not j then
        -- a provider making a new image at every call is no loop: frame 0 alone
        if #list >= SP.MAX_FRAMES then return { list[1] } end
        list[#list + 1] = { entry = e, n = 0 }
        j = #list
        byImg[img] = j
      end
      list[j].n = list[j].n + 1
      last = img
    end
    return list
  end

  local rest = setmetatable({}, { __mode = "k" })   -- frame 0's image -> the resting entry

  -- the loop's resting pose: frames grouped by opaque box, the group shown longest, its first
  -- frame; frame 0 when the boxes cannot be read
  function SP.restingOf(list)
    if #list == 1 then return list[1].entry end
    local weight, firstOf, order = {}, {}, {}
    for _, f in ipairs(list) do
      local key = SP.boxKey(f.entry.image)
      if not key then return list[1].entry end
      if not weight[key] then
        weight[key], firstOf[key] = 0, f.entry
        order[#order + 1] = key
      end
      weight[key] = weight[key] + f.n
    end
    local best = order[1]
    for _, key in ipairs(order) do
      if weight[key] > weight[best] then best = key end
    end
    return firstOf[best]
  end

  -- a provider's pic as one still frame: SP.get(Pokemon.monFrontPic, mon, nil, "summary")
  function SP.get(fn, ...)
    local first = SP.callAt(0, fn, ...)
    if type(first) ~= "table" or not first.image then return nil end
    local hit = rest[first.image]
    if hit then return SP.still(hit) end
    local list = SP.sample(fn, ...) or { { entry = first, n = 1 } }
    hit = SP.restingOf(list)
    rest[first.image] = hit
    return SP.still(hit)
  end

  return SP
end
