-- PlayNav's high-resolution drawing helpers. PlayNav owns both of its screens (the touch
-- surface and its top-screen layers), so instead of capturing draws and replaying them the
-- way gen3-hd-sprites does for engine passes, it draws them at the output's pixel density
-- in the first place. This module holds what that needs:
--
--   HD.density(scale, dpi)   output pixels per logical unit, quantised and capped
--   HD.outputScale()         the current transform's scale in real pixels
--   HD.drawPixel(img, [quad,] x, y, r, sx, sy, ox, oy)   (love.graphics.draw's arguments)
--                            pixel art (GBA sprites, icons): nearest when it lands on whole
--                            pixels, a sharp-bilinear shader otherwise (crisp texels, a
--                            one-pixel blend at their edges, no doubled rows), linear when
--                            shrunk
--   HD.prepareArt(image)     high-resolution art (the ORAS textures): mipmaps + linear
--
-- Everything is guarded: headless (no love.graphics) every call is a no-op or returns 1.

local HD = { MAX_K = 4, enabled = true }

local function G() return love and love.graphics end

-- quarter steps keep canvas sizes whole for 256x192 and 240x160
function HD.density(scale, dpi)
  if not HD.enabled then return 1 end
  local k = (tonumber(scale) or 1) * (tonumber(dpi) or 1)
  if k ~= k or k <= 1 then return 1 end
  k = math.floor(k * 4 + 0.5) / 4
  return math.min(HD.MAX_K, math.max(1, k))
end

-- the real pixels one logical unit covers right now (transform x DPI when on the window)
function HD.outputScale()
  local g = G()
  if not (g and g.transformPoint) then return 1 end
  local x0, y0 = g.transformPoint(0, 0)
  local x1, y1 = g.transformPoint(1, 0)
  local s = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  local onWindow = g.getCanvas and g.getCanvas() == nil
  if onWindow and g.getDPIScale then s = s * (g.getDPIScale() or 1) end
  return s
end

-- ------- the sharp-bilinear shader

local SHARP_SRC = [[
uniform vec2 texSize;
uniform vec2 pxPerTexel;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = uv * texSize;
  vec2 base = floor(texel);
  vec2 d = fract(texel) - 0.5;
  vec2 region = 0.5 - 0.5 / pxPerTexel;
  vec2 f = (d - clamp(d, -region, region)) * pxPerTexel + 0.5;
  return Texel(tex, (base + f) / texSize) * color;
}
]]

local sharp, sharpFailed = nil, false
function HD.sharpShader()
  if sharp or sharpFailed then return sharp end
  local g = G()
  if not (g and g.newShader) then sharpFailed = true; return nil end
  local ok, sh = pcall(g.newShader, SHARP_SRC)
  if ok then sharp = sh else sharpFailed = true end
  return sharp
end

-- "nearest" | "sharp" | "linear" for an effective scale (real pixels per texel)
function HD.modeFor(pxPerTexel)
  if not HD.enabled then return "nearest" end
  local s = math.abs(pxPerTexel or 1)
  if s < 0.999 then return "linear" end
  if math.abs(s - math.floor(s + 0.5)) < 0.02 then return "nearest" end
  return "sharp"
end

local function texelsPerUnit(img)
  if not (img.getPixelWidth and img.getWidth) then return 1 end
  local w = img:getWidth()
  if not w or w <= 0 then return 1 end
  return img:getPixelWidth() / w
end

local function isQuad(v)
  return type(v) == "userdata" and type(v.getViewport) == "function"
    or (type(v) == "table" and type(v.getViewport) == "function")
end

function HD.drawPixel(img, a, ...)
  local quad, x, y, r, sx, sy, ox, oy
  if isQuad(a) then quad = a; x, y, r, sx, sy, ox, oy = ...
  else x = a; y, r, sx, sy, ox, oy = ... end
  local g = G()
  if not (g and img) then return end
  sx = sx or 1
  sy = sy or sx
  local s = HD.outputScale() * math.abs(sx) / texelsPerUnit(img)
  local mode = HD.modeFor(s)
  local prevMin, prevMag = "nearest", "nearest"
  if img.getFilter then prevMin, prevMag = img:getFilter() end
  local shader = mode == "sharp" and HD.sharpShader() or nil
  if mode == "sharp" and not shader then mode = "nearest" end
  local prevShader = g.getShader and g.getShader() or nil
  if mode ~= "nearest" and img.setFilter then img:setFilter("linear", "linear") end
  if shader then
    local pw, ph = img:getPixelDimensions()
    pcall(shader.send, shader, "texSize", { pw, ph })
    local sy2 = HD.outputScale() * math.abs(sy) / texelsPerUnit(img)
    pcall(shader.send, shader, "pxPerTexel", { math.max(1, s), math.max(1, sy2) })
    g.setShader(shader)
  end
  if quad then g.draw(img, quad, x, y, r or 0, sx, sy, ox or 0, oy or 0)
  else g.draw(img, x, y, r or 0, sx, sy, ox or 0, oy or 0) end
  if shader then g.setShader(prevShader) end
  if mode ~= "nearest" and img.setFilter then img:setFilter(prevMin, prevMag) end
end

-- high-resolution art: smooth when enlarged, trilinear when shrunk (call once on load)
function HD.prepareArt(img)
  if not img then return img end
  if not HD.enabled then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  if img.setFilter then img:setFilter("linear", "linear") end
  if img.setMipmapFilter and img.getMipmapCount and img:getMipmapCount() > 1 then
    pcall(img.setMipmapFilter, img, "linear")
  end
  return img
end

return HD
