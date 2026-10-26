-- Japanese in PlayNav's own text: LOVE's default face draws Latin only, so a kana name (a
-- traded Gen 3 Pokemon's nickname, a Japanese translation mod's species names) came out as
-- boxes. Every font PlayNav makes goes through C.newFont, which gives it the engine's Plain
-- Pixel (assets/fonts/plainpixel, CC-BY 4.0, kana and CJK) as a fallback: only the glyphs the
-- primary face lacks come from it, so Latin text looks as before. The fallback is made at the
-- primary's size and density (a fallback at another density draws its glyphs at the wrong
-- scale), one per size and density. Shared as mod.cjk.
--
-- C.newFont(size [, hinting [, dpi]]) -> Font (love.graphics.newFont's default-face form)
-- C.attach(font, size) -> font ; C.has(text) -> true when text holds anything past ASCII

return function(mod)
local C = { PATH = "assets/fonts/plainpixel/PlainPixel-Regular.ttf" }

local function warn(fmt, ...)
  if mod and mod.log and mod.log.warn then pcall(mod.log.warn, mod.log, fmt, ...) end
end

local unavailable = false
local fallbacks = {}

local function fallbackFor(size, dpi)
  if unavailable then return nil end
  local key = size .. ":" .. dpi
  local hit = fallbacks[key]
  if hit ~= nil then return hit or nil end
  local G = love and love.graphics
  if not G then return nil end
  local ok, f = pcall(G.newFont, C.PATH, size, "normal", dpi)
  if not ok or not f then
    -- a build without the file: Latin as before, no retry every frame
    unavailable = true
    warn("no %s (%s): Japanese names draw as boxes; reinstall the engine to restore it", C.PATH, tostring(f))
    return nil
  end
  fallbacks[key] = ok and f or false
  return ok and f or nil
end

function C.attach(font, size)
  if not (font and font.setFallbacks) then return font end
  local dpi = font.getDPIScale and font:getDPIScale() or 1
  local fb = fallbackFor(size or 12, dpi)
  if fb then
    local ok, err = pcall(font.setFallbacks, font, fb)
    if not ok then warn("font fallback: %s", tostring(err)) end
  end
  return font
end

function C.newFont(size, hinting, dpi)
  local G = love and love.graphics
  if not G then return nil end
  size = size or 12
  local font
  if dpi then font = G.newFont(size, hinting or "normal", dpi)
  elseif hinting then font = G.newFont(size, hinting)
  else font = G.newFont(size) end
  return C.attach(font, size)
end

-- a font for text the engine font would draw where there is none (Gen 1 / 2's top screen)
local plain = {}
function C.plain(size)
  size = size or 11
  if plain[size] == nil then
    local ok, f = pcall(C.newFont, size)
    plain[size] = ok and f or false
  end
  return plain[size] or nil
end

function C.has(text)
  return type(text) == "string" and text:find("[\128-\255]") ~= nil
end

return C
end
