-- Driver: Super Training's engine-drawn UI (src/training/ui_art.lua) against the card image's,
-- side by side: the home screen, a punch, the bag drawer and its description window, each shot
-- with the engine's UI (e_*) and the card image's (r_*), and a sheet of every drawn image
-- (ui_sheet.png, on grey, at 3x).
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/engine_ui_probe.lua love .

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
  love.window.setMode(tonumber(os.getenv("SHOT_W")) or 603, tonumber(os.getenv("SHOT_H")) or 1294, { resizable = true, highdpi = true })
  U.wait(2)
  if not waitFor(function() return game.phase == "boot" and game.boot end, 900) then
    log("FAIL boot phase not reached; phase:", game.phase)
    return
  end
  do
    local Xk = game.mods and game.mods.exports and game.mods.exports.play_nav
    if Xk and Xk._test and Xk._test.keepArt then Xk._test.keepArt() end
  end
  game:_handleBootAction({ action = "new_game", name = "DS", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Party = require("src.core.game3.party")
  local s = Runtime.getSession()
  if s and #(s.party or {}) == 0 then
    Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12)
    Party.giveMon(s, C:require("species", "SPECIES_ZIGZAGOON"), 6)
  end
  waitFor(function() return game.phase == "field" end, 1200)
  U.wait(60)
  local loader = game.mods
  local X = loader and loader.exports and loader.exports.play_nav
  if not X then log("FAIL no exports"); return end
  loader.modOptions.play_nav = loader.modOptions.play_nav or {}
  local opts = loader.modOptions.play_nav
  local savedDisplay = opts.display_mode
  opts.display_mode = "combined"
  local function shot(name) log("shot", name, U.shot(game, dir .. "/" .. name .. ".png") and "ok" or "MISSING") end
  local function both(name)
    X._test.engineUi(true); U.wait(3); shot("e_" .. name)
    X._test.engineUi(false); U.wait(3); shot("r_" .. name)
    X._test.engineUi(true)
  end

  local ok, err = pcall(function()
    local ui = X._test.engineUi(true)
    log("ui art ids:", ui and #ui.ids() or 0)
    -- the sheet: every drawn image on grey at 3x, its id under it
    if ui then
      local G = love.graphics
      local ids = ui.ids()
      local cols, cw, ch, k = 8, 180, 210, 3
      local rows = math.ceil(#ids / cols)
      local canvas = G.newCanvas(cols * cw, rows * ch, { dpiscale = 1 })
      G.push("all")
      G.setCanvas(canvas)
      G.origin()
      G.clear(0.42, 0.42, 0.48, 1)
      for i, id in ipairs(ids) do
        local img = ui.image(id)
        local x, y = ((i - 1) % cols) * cw + 6, math.floor((i - 1) / cols) * ch + 4
        if img then
          local w, h = img:getDimensions()
          local kk = math.min(k, (cw - 12) / w, (ch - 24) / h)
          G.setColor(1, 1, 1, 1)
          G.draw(img, x, y, 0, kk, kk)
        end
        G.setColor(1, 1, 0, 1)
        G.print(id:gsub("^training/", ""), x, y + ch - 20)
      end
      G.pop()
      local fd = canvas:newImageData():encode("png")
      local f = io.open(dir .. "/ui_sheet.png", "wb")
      if f then f:write(fd:getString()); f:close() end
      log("sheet", #ids, "images, made", ui.made)
    end

    local T = X.training.session
    log("training open:", tostring(X.training.open()))
    waitFor(function() return T.session and T.session.mode == "core" end, 600)
    U.wait(40)
    both("01_home")
    T.hitBag("tap")
    U.wait(4)
    both("02_punch")
    U.wait(30)
    T.enterBags()
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 1 do U.wait(1) end
    both("03_drawer")
    local Store = X.training.store
    local bags = Store.bags()
    log("bags held:", #bags)
    T.enterCore()
    U.wait(20)
    -- the regimen picker, a course picked (its card on the top screen)
    T.enterCourses()
    U.wait(30)
    local first = T.courseList()[3]
    if first then T.session.picked = first.id end
    t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 1 do U.wait(1) end
    both("04_picker")
    X.training.finish()
  end)
  opts.display_mode = savedDisplay
  if not ok then log("probe body failed:", tostring(err)) end
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
