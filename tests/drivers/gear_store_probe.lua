-- Driver: PlayNav's apps in Kanto Gear's Silph Store. Both registered (Super Training and
-- Pokemon-Amie), available on Gen 3, their words translated; each opened as a press on its
-- tile does (the Gear's own modules.open, after installing it the way the store does), the
-- Gear standing down while it is up.
--   SHOT_DIR=<dir> POKEPORT_GAME=emerald POKEPORT_VERSION=emerald POKEPORT_TOUCH=1 \
--   POKEPORT_DRIVER=mods/play_nav/tests/drivers/gear_store_probe.lua love .

local function body(game, log)
  local U = require("tests.drivers.util")
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
  if s and #(s.party or {}) == 0 then Party.giveMon(s, C:require("species", "SPECIES_TORCHIC"), 12) end
  U.wait(60)

  local ex = game.mods and game.mods.exports
  local gear = ex and ex.kanto_gear
  local hook = gear and gear.modules
  if not hook then log("FAIL Kanto Gear or its modules hook is missing"); return end
  -- the registry behind the hook (register's upvalues: M, and through it the runtime)
  local M, runtime
  for i = 1, 40 do
    local name, v = debug.getupvalue(hook.register, i)
    if not name then break end
    if name == "M" then M = v end
    if name == "displayRuntime" then runtime = v end
  end
  if not M then log("FAIL could not reach the Gear's registry"); return end
  for i = 1, 40 do
    local name, v = debug.getupvalue(M.open, i)
    if not name then break end
    if name == "displayRuntime" then runtime = v end
  end
  log("registered:", table.concat(M.order or {}, ", "))

  local X = ex.play_nav
  local function i18n(lang, key, id)
    local THEME
    for i = 1, 40 do
      local name, v = debug.getupvalue(hook.register, i)
      if not name then break end
      if name == "THEME" then THEME = v end
    end
    local cat = THEME and THEME.i18n
    if not cat then return nil end
    local ok, text = pcall(function()
      if cat.translate then return cat:translate("@app/" .. id .. ":" .. key, lang) end
      return nil
    end)
    return ok and text or nil
  end

  for _, id in ipairs({ "super_training", "pokemon_amie" }) do
    local spec = M.specs and M.specs[id]
    if not spec then
      log("FAIL", id, "not registered")
    else
      local entry = runtime and runtime.storeById and runtime.storeById[id]
      local pkg = runtime and runtime.homeCatalog and runtime.homeCatalog.packages[id]
      log(("%s: label %s, category %s, accent %s, store row %s, hidden %s, available %s"):format(id,
        spec.label, spec.category, tostring(spec.accent), tostring(entry ~= nil),
        tostring(entry and entry.hidden), tostring(pkg and pkg.available)))
      log(("%s: de %s / fr %s / ja %s"):format(id, tostring(spec.translations.de[spec.label]),
        tostring(spec.translations.fr[spec.label]), tostring(spec.translations.ja[spec.label])))
      local tr = i18n("de", spec.label, id)
      if tr then log(id .. ": the Gear's catalogue gives de", tr) end
    end
  end

  -- each opened as its tile does: installed first (the store's INSTALL), then the Gear's open
  local amieState = function() return X.amie and X.amie.state and X.amie.state() end
  for _, id in ipairs({ "pokemon_amie", "super_training" }) do
    local pkg = runtime and runtime.homeCatalog and runtime.homeCatalog.packages[id]
    if pkg then pkg.installed = true end
    local opened = M.open(id)
    U.wait(30)
    local st = X.state and X.state() or {}
    local a = amieState()
    local t = X.training and X.training.state and X.training.state()
    log(("open %s: %s; surface %s; amie %s; training %s; Gear stands down %s"):format(id, tostring(opened),
      tostring(st.mode), tostring(a and a.mode), tostring(t and t.mode), tostring(M.anyShown())))
    log(("  a second open while one is up: %s (refused, as the Gear does)"):format(tostring(M.open(id))))
    if id == "pokemon_amie" then
      U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/play_nav") .. "/g01_amie_from_gear.png")
      if X.amie and X.amie.session and X.amie.session.finish then X.amie.session.finish() end
    else
      U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/play_nav") .. "/g02_training_from_gear.png")
      if X.training and X.training.session and X.training.finish then X.training.finish() end
    end
    U.wait(30)
    local st2 = X.state and X.state() or {}
    log(("  closed: Gear stands down %s; surface %s; active app %s"):format(tostring(M.anyShown()),
      tostring(st2.mode), tostring(X.apps:active() and X.apps:active().id)))
  end

  -- the PlayNav menu up: the Gear stands down and refuses its tiles; the x gives it back
  if X.menu then
    log("menu open:", tostring(X.menu.open()))
    U.wait(30)
    log(("  menu up: surface %s; Gear stands down %s; a tile press %s"):format(tostring((X.state() or {}).mode),
      tostring(M.anyShown()), tostring(M.open("super_training"))))
    U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/play_nav") .. "/g03_menu_over_gear.png")
    X.menu.close()
    U.wait(30)
    log(("  menu closed: surface %s; Gear stands down %s"):format(tostring((X.state() or {}).mode), tostring(M.anyShown())))
    local opened = M.open("pokemon_amie")
    U.wait(30)
    log(("  then a tile press: %s; amie %s"):format(tostring(opened), tostring(amieState() and amieState().mode)))
    if X.amie.session.finish then X.amie.session.finish() end
    U.wait(30)
    log(("  closed: surface %s; active app %s"):format(tostring((X.state() or {}).mode),
      tostring(X.apps:active() and X.apps:active().id)))
  end
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
  log("DONE")
  if logFile then logFile:close() end
  love.event.quit()
end
