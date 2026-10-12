-- PlayNav (id play_nav; ds_touch before 0.3.0): a DS-style bottom touch screen for
-- gen1recomp, built to host
-- Pokemon-Amie (play, care, minigames) and future touch minigames.
--
-- The surface is a logical 256x192 space that lives on the second display
-- (AYN Thor, or a desktop companion window) or in the lower part of a
-- single-screen phone. It stays dormant until an app asks for it (an Amie
-- session after a battle or from the START menu), so other mods that own
-- the bottom screen, such as Kanto Gear, keep it the rest of the time. The
-- game picture on the top screen is never a touch target.
--
-- Module map:
--   src/layout.lua         pure geometry: where the surface sits, coordinate mapping
--   src/surface.lua        the 256x192 canvas, blit, readback for the second screen
--   src/pointer.lua        per-pointer records, velocity, path, gesture helpers
--   src/apps/init.lua      app registry + tab strip + pointer dispatch
--   src/apps/scratch.lua   free-touch demo (dev option)
--   src/apps/import.lua    the Alpha Sapphire extraction progress panel
--   src/amie/rules.lua     pure Amie stat rules (data/amie_rules.lua holds the numbers)
--   src/amie/petting.lua   zones over the sprite + per-species spots (data/petting_gen3.lua)
--   src/amie/store.lua     mod.save records and the schema migration
--   src/amie/session.lua   battle.ended listener, top-screen layer, the session
--   src/amie/play.lua      the bottom-screen play / care app
--   src/amie/home.lua      the Amie room: wandering Pokemon, DECORATE / PLAY / SWITCH
--   src/amie/games/        common rules, the picker, Berry Picker, Head It, Tile Puzzle
--   src/amie/decor.lua     the decor catalogue rules (data/decor_catalog.lua), gifts
--   src/amie/decorate.lua  the decorate drawer over the room
--   src/amie/visitors.lua  visiting Pokemon, their chat and gifts
--   src/amie/benefits.lua  affection benefits in battle (hooks)
--   src/refresh/care.lua   pure cleaning rules: marks, tools, rubbing
--   src/refresh/host_gen3.lua  the Gen 3 engine adapter
--   src/pad_hide.lua       hides the built-in pad; Gen 3 touch routing
--   src/cutout.lua         hands the Gen 3 picture area to the engine in split mode

-- A mod's own files load as chunks through mod:read; require() cannot see
-- them. A sibling that fails to read or compile is reported with the file
-- that broke so the load degrades instead of failing.
local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  mod.options:define({
    { key = "refresh", label = "POKEMON-AMIE", type = "toggle", default = true },
    { key = "care_frequency", label = "DIRT AFTER BATTLE", type = "choice", default = "normal",
      choices = { { "OFF", "off" }, { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" } } },
    { key = "prompt_always", label = "ASK AFTER EVERY BATTLE", type = "toggle", default = false },
    { key = "beans_per_win", label = "PUFFS PER WIN", type = "number", default = 1,
      min = 0, max = 3, step = 1 },
    { key = "affection_benefits", label = "AFFECTION BENEFITS", type = "toggle", default = true },
    { key = "training", label = "SUPER TRAINING", type = "toggle", default = true },
    { key = "top_screen_pic", label = "TOP SCREEN PICTURE", type = "choice", default = "small",
      choices = { { "SMALL", "small" }, { "LARGE", "large" } } },
    { key = "display", label = "TOUCH SCREEN", type = "choice", default = "auto",
      choices = { { "AUTO", "auto" }, { "SECOND SCREEN", "second_screen" },
        { "SPLIT SCREEN", "split" }, { "OFF", "off" } } },
    { key = "surface", label = "SHOW TOUCH SCREEN", type = "choice", default = "when_needed",
      choices = { { "WHEN NEEDED", "when_needed" }, { "ALWAYS", "always" } } },
    { key = "split_balance", label = "SPLIT SIZES", type = "choice", default = "auto",
      choices = { { "AUTO", "auto" }, { "3DS", "ds3" }, { "EQUAL", "equal" }, { "3DS FLIPPED", "ds3_flip" },
        { "MAX GAME", "game" }, { "MAX TOUCH", "touch" } } },
    { key = "game_scale", label = "GAME SCALE", type = "choice", default = "auto",
      choices = { { "AUTO", "auto" }, { "1X", "1" }, { "2X", "2" }, { "3X", "3" }, { "4X", "4" }, { "5X", "5" }, { "6X", "6" } } },
    { key = "touch_scale", label = "TOUCH SCALE", type = "choice", default = "auto",
      choices = { { "AUTO", "auto" }, { "1X", "1" }, { "2X", "2" }, { "3X", "3" }, { "4X", "4" }, { "5X", "5" }, { "6X", "6" } } },
    { key = "split_ratio", label = "GAME SHARE %", type = "number", default = 60,
      min = 35, max = 80, step = 5 },
    { key = "bottom_safe_area", label = "BOTTOM SAFE PX", type = "number", default = 0,
      min = 0, max = 200, step = 8 },
    { key = "hide_virtual_pad", label = "HIDE VIRTUAL PAD", type = "toggle", default = true },
    { key = "second_screen_scale", label = "2ND SCREEN SCALE", type = "number", default = 3,
      min = 1, max = 6, step = 1 },
    { key = "dev_scratch", label = "DEV: SCRATCH APP", type = "toggle", default = false },
    { key = "extract_on_boot", label = "EXTRACT AMIE ART ON BOOT", type = "toggle", default = true },
    { key = "use_rom_art", label = "USE EXTRACTED ART", type = "toggle", default = true },
    { key = "hd_render", label = "HD RENDERING", type = "toggle", default = true },
  })

  -- save data and options kept under the old id carry over once
  local makeRename = loadSibling(mod, "src/rename.lua")
  if makeRename then makeRename(mod, "ds_touch").install() end

  local Layout = loadSibling(mod, "src/layout.lua")
  local makePointer = loadSibling(mod, "src/pointer.lua")
  local makeSurface = loadSibling(mod, "src/surface.lua")
  -- PlayNav draws its own screens at the output's pixel density (src/hd.lua); shared with
  -- the apps as mod.hd so pixel art and art filters follow one switch
  local HD = loadSibling(mod, "src/hd.lua")
  if HD then
    HD.enabled = mod.options:get("hd_render") ~= false
    mod.hd = HD
  end
  local makeHdTop = loadSibling(mod, "src/hd_top.lua")
  -- text that wraps and shrinks to fit its box (shared as mod.textfit)
  mod.textfit = loadSibling(mod, "src/textfit.lua")
  local makeApps = loadSibling(mod, "src/apps/init.lua")
  local makePadHide = loadSibling(mod, "src/pad_hide.lua")
  local makeCutout = loadSibling(mod, "src/cutout.lua")
  local Gate = loadSibling(mod, "src/second_gate.lua")
  if not (Layout and makePointer and makeSurface and makeApps and makePadHide) then
    mod.log:error("core modules missing; PlayNav stays off")
    return
  end

  local Pointer = makePointer(mod)
  local Surface = makeSurface(mod, Layout, HD)
  local HdTop = (HD and makeHdTop) and makeHdTop(mod, { HD = HD,
    ids = { play_nav_amie = true, play_nav_training = true } }) or nil
  local Apps = makeApps(mod, Pointer, Layout)
  local PadHide = makePadHide(mod)
  local Cutout = makeCutout and makeCutout(mod) or nil
  Apps.onChange = function() Surface.dirty = true end
  local function dirty() Surface.dirty = true end

  -- ------- Pokemon-Amie (Gen 3 host in v1; the rules and apps are host-agnostic)

  local Care = loadSibling(mod, "src/refresh/care.lua")
  local RuleNumbers = loadSibling(mod, "data/amie_rules.lua")
  local makeRules = loadSibling(mod, "src/amie/rules.lua")
  local PettingData = loadSibling(mod, "data/petting_gen3.lua")
  local makePetting = loadSibling(mod, "src/amie/petting.lua")
  local makeStore = loadSibling(mod, "src/amie/store.lua")
  local makeHost = loadSibling(mod, "src/refresh/host_gen3.lua")
  local makeSession = loadSibling(mod, "src/amie/session.lua")
  local makePlayApp = loadSibling(mod, "src/amie/play.lua")
  local makeHomeApp = loadSibling(mod, "src/amie/home.lua")
  local DecorCatalog = loadSibling(mod, "data/decor_catalog.lua")
  local makeDecor = loadSibling(mod, "src/amie/decor.lua")
  local makeDecorateApp = loadSibling(mod, "src/amie/decorate.lua")
  local makeVisitors = loadSibling(mod, "src/amie/visitors.lua")
  local makeGames = loadSibling(mod, "src/amie/games/common.lua")
  local makeGamesMenu = loadSibling(mod, "src/amie/games/menu.lua")
  local gameMakers = {
    berry = loadSibling(mod, "src/amie/games/berry_picker.lua"),
    head = loadSibling(mod, "src/amie/games/head_it.lua"),
    tile = loadSibling(mod, "src/amie/games/tile_puzzle.lua"),
  }
  local makeBenefits = loadSibling(mod, "src/amie/benefits.lua")
  local makeAmieText = loadSibling(mod, "src/amie/text.lua")
  local Rules, Petting, Store, Amie, amieHost, Benefits = nil, nil, nil, nil, nil, nil
  if Care and RuleNumbers and makeRules and makePetting and makeStore and makeHost and makeSession and makePlayApp then
    Rules = makeRules(RuleNumbers)
    Petting = makePetting(PettingData or {})
    Store = makeStore(mod, Rules)
    amieHost = makeHost(mod)
    Amie = makeSession(mod, { host = amieHost, Rules = Rules, Petting = Petting, Care = Care,
      Store = Store, Apps = Apps, onChange = dirty })
    if makeAmieText then
      local okT, AT = pcall(makeAmieText, Amie)
      if okT and type(AT) == "table" then
        Amie.text = AT
        Rules.textPuffName = function(id) return AT.puffName(id) end
      else
        mod.log:warn("amie text helper failed to build (%s); our own wording stands in", tostring(AT))
      end
    end
    local ok, app = pcall(makePlayApp, mod, Pointer, Amie, Care, Rules, Petting)
    if ok and type(app) == "table" then
      Apps:register(app)
      app.fontsFn = function() return Surface.font, Surface.smallFont end
    else
      mod.log:error("play app failed to build: %s", tostring(app))
    end
    if makeHomeApp then
      local okH, home = pcall(makeHomeApp, mod, Pointer, Amie, Rules, Store, amieHost)
      if okH and type(home) == "table" then
        Apps:register(home)
        home.fontsFn = function() return Surface.font, Surface.smallFont end
      else
        mod.log:error("home app failed to build: %s", tostring(home))
      end
    end
    if makeDecor and DecorCatalog then
      local Decor = makeDecor(DecorCatalog, Rules)
      Amie.Decor = Decor
      if Amie.text then
        Amie.text.setDecor(Decor)
        Decor.textName = function(id) return Amie.text.decorName(id) end
      end
      if makeDecorateApp then
        local okD, dapp = pcall(makeDecorateApp, mod, Pointer, Amie, Decor, Rules, Store, amieHost)
        if okD and type(dapp) == "table" then
          Apps:register(dapp)
          dapp.fontsFn = function() return Surface.font, Surface.smallFont end
        else
          mod.log:error("decorate app failed to build: %s", tostring(dapp))
        end
      end
      if makeVisitors then
        Amie.Visitors = makeVisitors(mod, { session = Amie, Rules = Rules, Decor = Decor, Store = Store, host = amieHost })
      end
    end
    if makeGames and makeGamesMenu then
      local Games = makeGames(mod, { Rules = Rules, Store = Store, host = amieHost, session = Amie })
      Amie.Games = Games
      local okM, menu = pcall(makeGamesMenu, mod, Pointer, Amie, Games, amieHost)
      if okM and type(menu) == "table" then
        Apps:register(menu)
        menu.fontsFn = function() return Surface.font, Surface.smallFont end
      else
        mod.log:error("games menu failed to build: %s", tostring(menu))
      end
      for id, make in pairs(gameMakers) do
        if make then
          local okG, gapp = pcall(make, mod, Pointer, Amie, Games, Rules, amieHost)
          if okG and type(gapp) == "table" then
            Apps:register(gapp)
            gapp.fontsFn = function() return Surface.font, Surface.smallFont end
          else
            mod.log:error("game %s failed to build: %s", id, tostring(gapp))
          end
        end
      end
    end
    if makeBenefits then
      Benefits = makeBenefits(mod, { Rules = Rules, Store = Store, host = amieHost,
        enabled = function() return mod.options:get("affection_benefits") ~= false end })
    end
  else
    mod.log:error("amie modules missing; Pokemon-Amie stays off")
  end

  -- ------- Super Training (Gen 3): Core Training, bags, regimens; a sibling of Amie
  -- that shares the host adapter, the apps and the surface, never the session

  local Training, TRules, TStore, TItems, trainHost = nil, nil, nil, nil, nil
  do
    local TrainingNumbers = loadSibling(mod, "data/training_rules.lua")
    local ShotTypes = loadSibling(mod, "data/training_shot_types.lua")
    local ItemsTable = loadSibling(mod, "data/training_items.lua")
    local makeTRules = loadSibling(mod, "src/training/rules.lua")
    local makeTStore = loadSibling(mod, "src/training/store.lua")
    local makeTHost = loadSibling(mod, "src/training/host.lua")
    local makeTItems = loadSibling(mod, "src/training/items.lua")
    local makeTSession = loadSibling(mod, "src/training/session.lua")
    local Radar = loadSibling(mod, "src/training/radar.lua")
    local makeCoreApp = loadSibling(mod, "src/training/core_app.lua")
    local Courses = loadSibling(mod, "data/training_courses.lua")
    local makeSim = loadSibling(mod, "src/training/sim.lua")
    local makeRegimen = loadSibling(mod, "src/training/regimen.lua")
    local makeArenaDraw = loadSibling(mod, "src/training/arena_draw.lua")
    local makeAimApp = loadSibling(mod, "src/training/aim_app.lua")
    local makeCoursesApp = loadSibling(mod, "src/training/courses_app.lua")
    local makeBagsApp = loadSibling(mod, "src/training/bags_app.lua")
    if amieHost and TrainingNumbers and makeTRules and makeTStore and makeTHost and makeTSession and makeCoreApp and Radar then
      TRules = makeTRules(TrainingNumbers, ShotTypes or {})
      TStore = makeTStore(mod, TRules)
      trainHost = makeTHost(mod, amieHost)
      if makeTItems then
        TItems = makeTItems(mod, { host = trainHost, Rules = TRules, data = ItemsTable or {} })
      end
      Training = makeTSession(mod, { host = trainHost, Rules = TRules, Store = TStore, Items = TItems, Apps = Apps,
        busy = function() return Amie ~= nil and Amie.session ~= nil end, onChange = dirty })
      if Amie then Amie.busy = function() return Training.session ~= nil end end
      local okC, capp = pcall(makeCoreApp, mod, Pointer, Training, TRules, Radar, trainHost)
      if okC and type(capp) == "table" then
        Apps:register(capp)
        capp.fontsFn = function() return Surface.font, Surface.smallFont end
      else
        mod.log:error("training core app failed to build: %s", tostring(capp))
      end
      -- the regimens: the simulation, the top-screen renderer, the aim pad and the picker
      if Courses and makeSim and makeRegimen then
        local TSim = makeSim(TrainingNumbers)
        local Draw = makeArenaDraw and makeArenaDraw(mod, { host = trainHost, Rules = TRules, Sim = TSim }) or nil
        Training.arenaDraw = Draw
        makeRegimen(mod, Training, { host = trainHost, Rules = TRules, Store = TStore, Items = TItems,
          Courses = Courses, Sim = TSim, Draw = Draw })
        for _, spec in ipairs({ { makeAimApp, "aim", { mod, Pointer, Training, TRules, TSim } },
          { makeCoursesApp, "courses", { mod, Pointer, Training, TRules } },
          { makeBagsApp, "bags", { mod, Pointer, Training, TRules, TStore } } }) do
          if spec[1] then
            local okA, tapp = pcall(spec[1], unpack(spec[3]))
            if okA and type(tapp) == "table" then
              Apps:register(tapp)
              tapp.fontsFn = function() return Surface.font, Surface.smallFont end
            else
              mod.log:error("training %s app failed to build: %s", spec[2], tostring(tapp))
            end
          end
        end
      else
        mod.log:warn("training regimen modules missing; Core Training only")
      end
    else
      mod.log:error("super training modules missing; Super Training stays off")
    end
  end

  -- ------- player-supplied Alpha Sapphire art: loader, extractor, progress app

  local Assets, Extract = nil, nil
  do
    local makeAssets = loadSibling(mod, "src/assets.lua")
    local makeExtract = loadSibling(mod, "src/import/extract.lua")
    local makeImportApp = loadSibling(mod, "src/apps/import.lua")
    local Recipe = loadSibling(mod, "data/oras_recipe.lua")
    if makeAssets then
      Assets = makeAssets(mod)
      for _, id in ipairs({ "play", "home", "decorate", "games", "game_berry", "game_head", "game_tile",
        "training_core", "training_bags", "training_courses", "training_aim" }) do
        local a = Apps:get(id)
        if a then a.assets = Assets end
      end
      if Training and Training.arenaDraw then Training.arenaDraw.assets = Assets end
      if Training then Training.assets = Assets end
      if Amie then Amie.assets = Assets end
    end
    if makeExtract and Recipe and Assets then
      Extract = makeExtract(mod, { recipe = Recipe, assets = Assets, onChange = dirty })
      if makeImportApp then
        local ok, app = pcall(makeImportApp, mod, Pointer, Extract)
        if ok and type(app) == "table" then Apps:register(app) end
      end
    else
      mod.log:warn("Alpha Sapphire import modules missing; extracted art stays off")
    end
  end

  if mod.options:get("dev_scratch") then
    local make = loadSibling(mod, "src/apps/scratch.lua")
    if make then
      local ok, app = pcall(make, mod, Pointer)
      if ok and type(app) == "table" then
        app.wantsSurface = function() return true end
        Apps:register(app)
      end
    end
  end
  -- the session screens switch apps themselves; no tab strip over them
  for _, id in ipairs({ "play", "home", "decorate", "games", "game_berry", "game_head", "game_tile", "import" }) do
    local a = Apps:get(id)
    if a then a.hideTabs = true end
  end
  Apps.activeId = "play"

  local state = {
    game = nil,
    mode = "off",          -- "off" | "split" | "second_screen"
    rect = nil,            -- window rect of the surface in split mode
    lastTick = nil,
    pushAt = 0, pushK = 1,
    secondWarned = false,
    secondId = "screen2",
    gen3Wrapped = false,
  }

  -- ------- the second display bridge (lazily required)

  local secondScreen
  local function second()
    if secondScreen == nil then
      local ok, SS = pcall(require, "src.render.SecondScreen")
      if ok and type(SS) == "table" then
        secondScreen = SS
      else
        secondScreen = false
        mod.log:warn("SecondScreen bridge unavailable: %s", tostring(SS))
      end
    end
    return secondScreen or nil
  end

  -- what downstream render.compose mods (Kanto Gear) get as the bridge
  local gate
  local function secondGate()
    if gate == nil then
      local SS = second()
      gate = (SS and Gate) and Gate.new(SS) or false
    end
    return gate or nil
  end

  local function osName()
    local ok, name = pcall(function() return love.system.getOS() end)
    return ok and name or "?"
  end

  -- the surface shows only while the active app asks for it, unless the
  -- player pinned it on; this is what lets Kanto Gear keep the bottom screen
  local function surfaceWanted()
    if mod.options:get("surface") == "always" then return true end
    local app = Apps:active()
    if app and app.wantsSurface then
      local ok, wants = pcall(app.wantsSurface, app)
      return ok and wants == true
    end
    return false
  end

  local function wantedMode()
    local choice = mod.options:get("display")
    if choice == "off" or not surfaceWanted() then return "off" end
    if choice == "split" then return "split" end
    local SS = second()
    local usable = false
    if SS and SS.usable then
      local ok, u = pcall(SS.usable)
      usable = ok and u == true
    end
    if choice == "second_screen" then return usable and "second_screen" or "split" end
    if usable and SS.detected then
      local ok, detected = pcall(SS.detected)
      if ok and detected then return "second_screen" end
    end
    return "split"
  end

  local function setMode(mode)
    if mode == state.mode then return end
    mod.log:info("display mode %s -> %s", state.mode, mode)
    Pointer:cancel()
    Apps:releaseAll(state.game)
    if state.mode == "second_screen" then
      local g = secondGate()
      if g then g:release() end
    end
    if mode == "second_screen" then
      local g = secondGate()
      if g then g:claim() end
    end
    state.mode = mode
    state.rect = nil
    state.pushAt = 0
    if Cutout and mode ~= "split" then Cutout:set(nil) end
    Surface.dirty = true
  end

  -- ------- pointer feeds

  local function feedWindow(phase, id, x, y, pressure, source)
    if phase == "pressed" then
      local rect = state.rect
      if not rect then return false end
      local lx, ly, inside = Layout.toLogical(rect, x, y)
      if not inside then return false end
      Pointer:begin(id, lx, ly, source, pressure)
      return true
    end
    if not Pointer:get(id) then return false end
    local lx, ly = Layout.toLogical(state.rect or { x = 0, y = 0, scale = 1 }, x, y)
    if phase == "moved" then
      Pointer:move(id, lx, ly, pressure)
    elseif phase == "released" then
      Pointer:finish(id, lx, ly)
    else
      Pointer:cancel(id)
    end
    return true
  end

  local function feedSecond(action, x, y)
    local k = state.pushK or 1
    local lx, ly = x / k, y / k
    local id = state.secondId
    if action == "down" then
      Pointer:begin(id, lx, ly, "touch")
      return true
    end
    if not Pointer:get(id) then return false end
    if action == "move" then
      Pointer:move(id, lx, ly)
    elseif action == "up" then
      Pointer:finish(id, lx, ly)
    else
      Pointer:cancel(id)
    end
    return true
  end

  Pointer:on(function(ev, rec)
    Surface.dirty = true
    Apps:pointer(ev, rec, state.game)
  end)

  local function ensureGen3Touch()
    if state.gen3Wrapped or mod.generation ~= 3 then return end
    local wrapped = PadHide:wrapTouch(function(phase, id, x, y, pressure)
      if state.mode ~= "split" then return false end
      return feedWindow(phase, id, x, y, pressure, id == "mouse" and "mouse" or "touch")
    end)
    if wrapped then
      state.gen3Wrapped = true
      PadHide:wrapMouse(function(phase, x, y)
        if state.mode ~= "split" then return false end
        return feedWindow(phase, "mouse", x, y, nil, "mouse")
      end)
    else
      state.gen3Wrapped = "failed"
      mod.log:warn("Gen 3: touch routing unavailable; use SECOND SCREEN or a build with input.pointer")
    end
  end

  -- ------- the per-frame tick (render.hud fires every drawn frame on all gens)

  local function drawAll(G, w, h) Apps:draw(G, w, h) end

  local function frameDt()
    local t = Pointer.now()
    local dt = state.lastTick and (t - state.lastTick) or (1 / 60)
    state.lastTick = t
    return math.min(0.1, math.max(0, dt))
  end

  -- Gen 3 has no viewport seam, but it fits its picture into the rectangle
  -- Playfield.cutout reports. In split mode the mod stacks picture and
  -- surface (src/layout.lua Layout.stack), hands the picture area to the
  -- engine through src/cutout.lua, and keeps the rest for the surface, so
  -- both scale with the window and never overlap. Without the cutout seam
  -- the surface falls back to the free strip under the engine's own placement.
  local function gen3Rect(vp)
    local ww, wh = vp.width or 0, vp.height or 0
    if ww < 1 or wh < 1 then return nil end
    local safe = mod.options:get("bottom_safe_area") or 0
    local share = (mod.options:get("split_ratio") or 60) / 100
    if Cutout and Cutout.pf then
      local lay = Layout.stack(ww, wh, { safeBottom = safe, maxGameShare = share,
        balance = mod.options:get("split_balance") or "auto",
        gameScale = tonumber(mod.options:get("game_scale")),
        surfaceScale = tonumber(mod.options:get("touch_scale")) })
      if lay then
        Cutout:set(lay.game)
        return lay.surface
      end
    end
    if wh >= ww then
      local bottom = (vp.gameY or 0) + (vp.gameHeight or 0)
      local r = Layout.inRect(0, bottom, ww, wh - bottom, { safeBottom = safe, anchor = "bottom" })
      if r and r.scale >= 1 then return r end
    else
      local right = (vp.gameX or 0) + (vp.gameWidth or 0)
      local r = Layout.inRect(right, 0, ww - right, wh, { safeBottom = safe })
      if r and r.scale >= 1 then return r end
    end
    return Layout.split(ww, wh, { ratio = share, safeBottom = safe }).surface
  end

  -- once per boot: if the player's card image is there and the art is not
  -- yet extracted, start the background extraction and show the IMPORT app
  local extractChecked = false
  local extractTicks = 0
  local function tickExtract()
    if not Extract then return end
    if not extractChecked then
      -- not during the engine's boot screens: the persistence filesystem is
      -- still being wired then and a cache read can miss files that exist
      extractTicks = extractTicks + 1
      local game = state.game
      local booting = game and game.phase ~= nil and game.phase ~= "field"
      if booting or extractTicks < 30 then return end
      extractChecked = true
      local what = Extract.check()
      if what ~= "complete" and Extract.lastManifestError then
        mod.log:info("import: manifest not usable yet (%s)", tostring(Extract.lastManifestError))
      end
      if what == "ready" and mod.options:get("extract_on_boot") ~= false then
        if Extract.start() then Apps:setActive("import", state.game) end
      elseif what == "complete" and Assets then
        Assets.refresh()
      end
    end
    if Extract.state == "running" or Extract.state == "finishing" then
      if Apps:active().id ~= "import" and not (Amie and Amie.session) and not (Training and Training.session) then
        Apps:setActive("import", state.game)
      end
      Extract.update()
    elseif (Extract.state == "done" or Extract.state == "failed") and Apps:active().id == "import" then
      local app = Apps:get("import")
      if app and not app:wantsSurface() then Apps:setActive("play", state.game) end
    end
  end

  -- While a mouse pointer is down on the surface, follow the real cursor
  -- every frame. Event routing for a held mouse differs per generation and
  -- per touch flag (see love.mousemoved in the engine's main.lua); polling
  -- makes a drag register the same way everywhere. A move that events
  -- already delivered is a zero-length step here and changes nothing.
  local function pollMouse()
    if not (love and love.mouse and love.mouse.getPosition) then return end
    local rec = Pointer:get("mouse")
    if not rec or state.mode ~= "split" then state.polledX, state.polledY = nil, nil; return end
    local mx, my = love.mouse.getPosition()
    if mx ~= state.polledX or my ~= state.polledY then
      state.polledX, state.polledY = mx, my
      local lx, ly = Layout.toLogical(state.rect or { x = 0, y = 0, scale = 1 }, mx, my)
      if lx ~= rec.x or ly ~= rec.y then Pointer:move("mouse", lx, ly) end
    end
  end

  local function tick(game, viewport)
    state.game = game
    local dt = frameDt()
    tickExtract()
    setMode(wantedMode())
    pollMouse()
    local mode = state.mode
    PadHide:apply(mode ~= "off" and mod.options:get("hide_virtual_pad") ~= false, game)
    -- apps keep ticking while dormant so a session can wake the surface
    Apps:update(dt, game)
    if mode == "off" then
      state.rect = nil
      return
    end

    local vw, vh = viewport and viewport.width, viewport and viewport.height
    if vw ~= state.lastW or vh ~= state.lastH then
      state.lastW, state.lastH = vw, vh
      Surface.dirty = true
    end

    Pointer:update()
    local needsDraw = Surface.dirty or Pointer:any() or Apps:live()
    state.lastViewport = viewport

    if mode == "split" then
      if mod.generation == 3 then
        ensureGen3Touch()
        local rect = gen3Rect(viewport or {})
        state.rect = rect
        if rect then
          local k = Surface:densityFor(rect)
          if needsDraw or k ~= Surface.k then Surface:render(drawAll, k) end
          Surface:blit(rect)
        end
      elseif needsDraw then
        Surface:render(drawAll)
      end
      return
    end

    state.rect = nil
    local SS = second()
    if not SS then return end
    pcall(SS.setEnabled, true)
    for _ = 1, 128 do
      local ok, event = pcall(SS.pollTouch)
      if not ok or not event then break end
      local action, x, y = Pointer.parse(event)
      if action and x and y then feedSecond(action, x, y) end
    end
    local t = Pointer.now()
    local okAvail, available = pcall(SS.available)
    if okAvail and available then
      local due = t - state.pushAt
      if (needsDraw and due >= 1 / 30) or due >= 1.0 then
        local k = math.floor(mod.options:get("second_screen_scale") or 3)
        state.pushK = k
        local data, w, h = Surface:imageData(k, drawAll)
        if data then
          pcall(SS.push, data, w, h, 0x000000, "secondary")
          state.pushAt = t
        end
      end
    elseif not state.secondWarned then
      state.secondWarned = true
      mod.log:info("waiting for a second display on %s", osName())
    end
  end

  -- ------- hooks

  mod.hooks:wrap("render.viewport", function(next, ctx)
    local base = next(ctx)
    setMode(wantedMode())
    if state.mode ~= "split" or mod.generation == 3 then
      if mod.generation ~= 3 then state.rect = nil end
      return base
    end
    local b = type(base) == "table" and base
      or { x = 0, y = 0, width = ctx.width, height = ctx.height }
    local layout = Layout.split(b.width, b.height, {
      ratio = (mod.options:get("split_ratio") or 55) / 100,
      safeBottom = mod.options:get("bottom_safe_area") or 0,
    })
    local s = layout.surface
    state.rect = { x = s.x + (b.x or 0), y = s.y + (b.y or 0), w = s.w, h = s.h, scale = s.scale }
    return {
      x = layout.game.x + (b.x or 0), y = layout.game.y + (b.y or 0),
      width = layout.game.w, height = layout.game.h, capture = true,
    }
  end)

  -- PlayNav first on the second display: this wrap runs outside every other
  -- render.compose mod and hands them the gate's proxy, which reports no
  -- display while PlayNav shows there (Kanto Gear then keeps to the main
  -- window) and passes everything through once PlayNav is idle
  mod.hooks:wrap("render.compose", function(next, renderer, ctx)
    if type(ctx) == "table" and ctx.secondScreen then
      setMode(wantedMode())
      local g = secondGate()
      if g then ctx.secondScreen = g.proxy end
    end
    return next()
  end, 1000)

  mod.hooks:wrap("render.window", function(next, game, ctx)
    local result = next(game, ctx)
    if state.mode == "split" and mod.generation ~= 3 and state.rect then
      Surface:blit(state.rect)
    end
    return result
  end)

  -- the HD switch can change in the Mod Manager at any time: art filters reload, the
  -- surface redraws, the top screen stands down
  local function syncHd()
    if not HD then return end
    local want = mod.options:get("hd_render") ~= false
    if want == HD.enabled then return end
    HD.enabled = want
    Surface.dirty = true
    if Assets and Assets.refresh then pcall(Assets.refresh) end
    if HdTop then HdTop.standDown() end
  end

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    syncHd()
    local ok, err = pcall(tick, game, viewport)
    if not ok then mod.log:warn("frame tick failed: %s", tostring(err)) end
    if HdTop and mod.generation == 3 then
      local okT, errT = pcall(HdTop.draw, viewport)
      if not okT then mod.log:warn("top screen overlay failed: %s", tostring(errT)) end
    end
    return next(game, viewport)
  end)

  mod.hooks:wrap("input.pointer", function(next, game, ev)
    state.game = game
    if state.mode == "split" and mod.generation ~= 3
        and feedWindow(ev.phase, ev.id, ev.x, ev.y, ev.pressure, ev.source) then
      return true
    end
    return next(game, ev)
  end)

  -- Pokemon-Amie: after a battle, from the Gen 3 start menu, steps and
  -- battles for the stats, and the affection benefits
  if Amie and mod.generation == 3 then
    if amieHost.available() then
      Store.migrate()
      mod.events:on("battle.ended", function(ev)
        local ok, err = pcall(Amie.onBattleEnded, ev)
        if not ok then mod.log:warn("amie after battle failed: %s", tostring(err)) end
      end)
      mod.events:on("battle.started", function()
        if mod.options:get("refresh") == false then return end
        pcall(Amie.onBattleStarted)
      end)
      mod.events:on("world.stepped", function()
        if mod.options:get("refresh") == false then return end
        pcall(Amie.onStep)
      end)
      if Benefits then Benefits.install() end
      mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
        local out = next(game, items)
        if type(out) ~= "table" or mod.options:get("refresh") == false then return out end
        for _, e in ipairs(out) do
          if type(e) == "table" and e.id == "play_nav_amie" then return out end
        end
        local entry = {
          id = "play_nav_amie", label = "AMIE", text = "AMIE",
          onSelect = function()
            local ok, StartMenu = pcall(require, "src.ui.game3.start_menu")
            if ok and StartMenu and StartMenu.close then pcall(StartMenu.close, true) end
            local okO, why = Amie.open()
            if not okO then mod.log:info("amie from the menu: %s", tostring(why)) end
          end,
        }
        local at = #out + 1
        for i, e in ipairs(out) do
          if type(e) == "table" and (e.id == "save" or e.id == "option" or e.id == "exit") then
            at = i
            break
          end
        end
        table.insert(out, at, entry)
        return out
      end)
    else
      mod.log:warn("Pokemon-Amie needs the Gen 3 UI stack and pokemon modules; it stays off")
    end
  elseif Amie then
    mod.log:info("Pokemon-Amie runs on Gen 3 in this version")
  end

  -- Super Training from the Gen 3 start menu, right after AMIE
  if Training and mod.generation == 3 and trainHost.available() then
    TStore.migrate()
    -- registered at load (the registry closes afterwards); national_dex_gen3 is an optional
    -- dependency so it loads first and its Gen 4 stones are found and shared, not fought
    if TItems then TItems.install() end
    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      local out = next(game, items)
      if type(out) ~= "table" or mod.options:get("training") == false then return out end
      for _, e in ipairs(out) do
        if type(e) == "table" and e.id == "play_nav_training" then return out end
      end
      local entry = {
        id = "play_nav_training", label = "TRAINING", text = "TRAINING",
        onSelect = function()
          local ok, StartMenu = pcall(require, "src.ui.game3.start_menu")
          if ok and StartMenu and StartMenu.close then pcall(StartMenu.close, true) end
          local okO, why = Training.open()
          if not okO then mod.log:info("training from the menu: %s", tostring(why)) end
        end,
      }
      local at = #out + 1
      for i, e in ipairs(out) do
        if type(e) == "table" and (e.id == "save" or e.id == "option" or e.id == "exit") then
          at = i
          break
        end
      end
      table.insert(out, at, entry)
      return out
    end)
  elseif Training then
    mod.log:info("Super Training runs on Gen 3 in this version")
  end

  -- ------- what other mods (future minigames) can reach

  mod.exports.pointer = Pointer
  mod.exports.apps = Apps
  mod.exports.layout = Layout
  mod.exports.W, mod.exports.H = Layout.W, Layout.H
  mod.exports.state = function()
    return { mode = state.mode, rect = state.rect, tabHeight = Apps.TAB_H }
  end
  mod.exports.assets = Assets
  if Extract then
    mod.exports.import = {
      state = function() return Extract.state end,
      progress = function() return Extract.progress() end,
      start = function() return Extract.start() end,
      cancel = function() return Extract.cancel() end,
      check = function() return Extract.check() end,
      message = function() return Extract.message end,
      manifest = function() return Extract.cacheManifest() end,
      lastError = function() return Extract.lastManifestError end,
    }
  end
  if Amie then
    mod.exports.amie = {
      open = function(mon) return Amie.open(mon) end,
      openPlay = function(mon) return Amie.openPlay(mon) end,
      state = function() return Amie.state() end,
      onBattleEnded = function(ev) return Amie.onBattleEnded(ev) end,
      puffs = function() return Store.puffs() end,
      meters = function(key) return Store.meters(key) end,
      rules = Rules,
      petting = Petting,
      care = Care,
      store = Store,
      session = Amie,
      benefits = Benefits,
      games = Amie.Games,
      decor = Amie.Decor,
      visitors = Amie.Visitors,
    }
    -- the name the first release used
    mod.exports.refresh = mod.exports.amie
  end
  if Training then
    mod.exports.training = {
      open = function(mon) return Training.open(mon) end,
      finish = function() return Training.finish() end,
      state = function() return Training.state() end,
      session = Training,
      rules = TRules,
      store = TStore,
      items = TItems,
      host = trainHost,
      courses = Training.Courses,
      sim = Training.Sim,
    }
  end
  mod.exports._test = {
    feedWindow = feedWindow,
    feedSecond = feedSecond,
    tick = tick,
    setRect = function(rect) state.rect = rect end,
    setMode = function(mode) state.mode = mode end,
    setGame = function(game) state.game = game end,
    setPushK = function(k) state.pushK = k end,
    tapButton = function(btn) return mod.input:tap(state.game, btn) end,
    lastViewport = function() return state.lastViewport end,
    surfaceWanted = surfaceWanted,
    setRefreshHost = function(fakeHost)
      if not Amie then return false end
      for k, v in pairs(fakeHost) do amieHost[k] = v end
      return true
    end,
    refreshHost = function() return amieHost end,
    setTrainingHost = function(fakeHost)
      if not Training then return false end
      for k, v in pairs(fakeHost) do trainHost[k] = v end
      return true
    end,
    trainingHost = function() return trainHost end,
    state = state,
    surface = Surface,
    padHide = PadHide,
    cutout = Cutout,
  }

  mod.log:info("PlayNav ready (gen %s, touch screen %s, shown %s)", tostring(mod.generation),
    tostring(mod.options:get("display")), tostring(mod.options:get("surface")))
end
