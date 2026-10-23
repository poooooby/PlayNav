-- Driver: Amie's engine pictures beside the card image's, id by id: each row the engine's
-- (left) and the card's (right) at up to 3x on grey, the id under them (art_compare.png).
-- ART_IDS = a comma list of ids or prefixes ending in "*" (lyt/amie_play/* by default).
--   SHOT_DIR=<dir> ART_IDS="lyt/amie_play/*" POKEPORT_GAME=emerald POKEPORT_VERSION=emerald \
--   POKEPORT_TOUCH=1 POKEPORT_DRIVER=mods/play_nav/tests/drivers/amie_art_compare.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  local X = game.mods and game.mods.exports and game.mods.exports.play_nav
  if not X then log("FAIL no exports"); return end
  X._test.keepArt()
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  waitFor(function() return game.phase == "field" end, 1200)
  U.wait(30)
  local A = X._test.assets()
  if not A then log("FAIL no assets"); return end
  -- the ids: the card's manifest rows matching the patterns
  local pats = {}
  for p in (os.getenv("ART_IDS") or "lyt/amie_play/*"):gmatch("[^,]+") do pats[#pats + 1] = p end
  local ids = {}
  for _, row in ipairs(A.list and A.list() or {}) do
    for _, p in ipairs(pats) do
      local pre = p:match("^(.*)%*$")
      if (pre and row.id:sub(1, #pre) == pre) or row.id == p then ids[#ids + 1] = row.id; break end
    end
  end
  log("ids:", #ids)
  local G = love.graphics
  local engine = A.engine
  local cols, cw, ch = 4, 420, 0
  local pairs_ = {}
  for _, id in ipairs(ids) do
    A.engine = engine
    local e = A.image(id)
    A.engine = nil
    local r = A.image(id)
    A.engine = engine
    local w, h = 16, 16
    if r then w, h = r:getDimensions() elseif e then w, h = e:getDimensions() end
    local k = math.min(3, 190 / w, 190 / h)
    pairs_[#pairs_ + 1] = { id = id, e = e, r = r, k = k, h = h * k }
    ch = math.max(ch, h * k + 24)
    log(id, e and "drawn" or "-", r and "card" or "-")
    -- ART_SAVE=1: each engine picture as its own PNG too (drawn_<id with _ for />.png)
    if e and os.getenv("ART_SAVE") then
      local c = G.newCanvas(e:getWidth(), e:getHeight(), { dpiscale = 1 })
      G.push("all"); G.setCanvas(c); G.origin(); G.clear(0, 0, 0, 0)
      G.setBlendMode("replace", "premultiplied"); G.setColor(1, 1, 1, 1); G.draw(e); G.pop()
      local f = io.open(dir .. "/drawn_" .. id:gsub("/", "_") .. ".png", "wb")
      if f then f:write(c:newImageData():encode("png"):getString()); f:close() end
    end
  end
  local rows = math.ceil(#pairs_ / cols)
  local canvas = G.newCanvas(cols * cw, math.max(1, rows * ch), { dpiscale = 1 })
  G.push("all")
  G.setCanvas(canvas)
  G.origin()
  G.clear(0.42, 0.42, 0.48, 1)
  for i, p in ipairs(pairs_) do
    local x, y = ((i - 1) % cols) * cw + 6, math.floor((i - 1) / cols) * ch + 4
    G.setColor(1, 1, 1, 1)
    for j, img in ipairs({ p.e or false, p.r or false }) do
      if img then
        local w, h = img:getDimensions()
        local k = p.k * ((p.r and p.r:getWidth() or w) / w)
        G.draw(img, x + (j - 1) * 205, y, 0, k, k)
      end
    end
    G.setColor(1, 1, 0, 1)
    G.print(p.id, x, y + ch - 20)
  end
  G.pop()
  local fd = canvas:newImageData():encode("png")
  local f = io.open(dir .. "/art_compare.png", "wb")
  if f then f:write(fd:getString()); f:close() end
  log("DONE")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/play_nav"
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
