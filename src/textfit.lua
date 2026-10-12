-- Text that fits its box. With PlayNav drawing at the display's density (src/hd.lua), text
-- can shrink without turning to mush, so a line too long for its backing is wrapped inside
-- the box and, if the lines still do not fit its height, drawn smaller (down to MIN_SCALE)
-- instead of running past the edge or being clipped.
--
--   TF.layout(measure, wrap, lineH, text, w, h)  -> scale, lines   (pure; tests use it)
--   TF.print(G, font, text, x, y, w, h, align)   a love font, the box (x, y, w, h)
--   TF.engine(Font, text, x, y, w, h, opts)      the engine's Gen 3 font (frlg_font)

local TF = { MIN_SCALE = 0.6, STEP = 0.05 }

-- the largest scale <= 1 at which the wrapped lines fit h; the lines at that scale
function TF.layout(wrap, lineH, text, w, h)
  local s = 1
  while true do
    local lines = wrap(text, w / s)
    if #lines * lineH * s <= h + 0.01 or s <= TF.MIN_SCALE + 1e-6 then return s, lines end
    s = math.max(TF.MIN_SCALE, s - TF.STEP)
  end
end

function TF.print(G, font, text, x, y, w, h, align)
  text = tostring(text or "")
  if not (G and font) then return end
  local lineH = font:getHeight()
  local function wrap(t, width)
    local _, lines = font:getWrap(t, width)
    if #lines == 0 then lines = { "" } end
    return lines
  end
  local s, lines = TF.layout(wrap, lineH, text, w, h)
  local blockH = #lines * lineH * s
  local top = y + math.max(0, (h - blockH) / 2)
  G.push()
  G.translate(x, top)
  G.scale(s, s)
  G.printf(table.concat(lines, "\n"), 0, 0, w / s, align or "center")
  G.pop()
end

-- the engine font draws one line per call; its line height is 16 px in a Gen 3 text box
function TF.engine(Font, text, x, y, w, h, opts)
  text = tostring(text or "")
  if not (Font and Font.draw) then return false end
  local G = love and love.graphics
  local lineH = (opts and opts.lineH) or 14
  local function split(str)
    local lines = {}
    for line in (str .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    return lines
  end
  -- frlg_font's wrap returns one string with "\n" between the lines
  local function wrap(t, width)
    if Font.wrap then
      local ok, out = pcall(Font.wrap, t, width, opts)
      if ok and type(out) == "string" then return split(out) end
      if ok and type(out) == "table" and #out > 0 then return out end
    end
    return split(t)
  end
  local s, lines = TF.layout(wrap, lineH, text, w, h)
  if not G then return false end
  G.push()
  G.translate(x, y)
  G.scale(s, s)
  local o = {}
  for k, v in pairs(opts or {}) do o[k] = v end
  o.maxWidth = w / s
  for i, line in ipairs(lines) do
    pcall(Font.draw, line, 0, (i - 1) * lineH, o)
  end
  G.pop()
  return true
end

return TF
