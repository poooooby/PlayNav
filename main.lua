-- PlayNav (id play_nav; ds_touch before 0.3.0): a DS-style bottom touch screen for
-- gen1recomp, built to host
-- Pokemon-Amie (the room, play, the minigames) and Super Training.
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
--   src/apps/menu.lua      the PlayNav menu (START -> PLAYNAV)
--   src/apps/import.lua    the Alpha Sapphire extraction progress panel
--   src/amie/rules.lua     pure Amie stat rules (data/amie_rules.lua holds the numbers)
--   src/amie/petting.lua   zones over the sprite + per-species spots (data/petting_gen3.lua)
--   src/amie/store.lua     mod.save records and the schema migration
--   src/amie/session.lua   battle.ended listener, top-screen layer, the session
--   src/amie/play.lua      the bottom-screen play app (petting, puffs, the games)
--   src/amie/home.lua      the Amie room: wandering Pokemon, DECORATE / PLAY / SWITCH
--   src/amie/games/        common rules, the picker, Berry Picker, Head It, Tile Puzzle
--   src/amie/decor.lua     the decor catalogue rules (data/decor_catalog.lua), gifts
--   src/amie/decorate.lua  the decorate drawer over the room
--   src/amie/visitors.lua  visiting Pokemon, their chat and gifts
--   src/amie/benefits.lua  affection benefits in battle (hooks)
--   src/refresh/host_gen3.lua  the Gen 3 engine adapter
--   src/pad_hide.lua       hides the built-in pad; Gen 3 touch routing
--   src/cutout.lua         hands the Gen 3 picture area to the engine in split mode
--   src/lytfile.lua        the games' BCLYT / BCLAN layouts and clips, parsed
--   src/lytplayer.lua      plays a layout and its clips with love (mod.lyt opens screens)

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
    { key = "affection_benefits", label = "AFFECTION BENEFITS", type = "toggle", default = true },
    { key = "display", label = "TOUCH SCREEN", type = "choice", default = "auto",
      choices = { { "AUTO", "auto" }, { "SECOND SCREEN", "second_screen" },
        { "SPLIT SCREEN", "split" }, { "OFF", "off" } } },
    { key = "hide_virtual_pad", label = "HIDE VIRTUAL PAD", type = "toggle", default = true },
    { key = "extract_on_boot", label = "EXTRACT AMIE ART ON BOOT", type = "toggle", default = true },
    -- an action: switching it on clears the cache, then it switches itself back off
    -- a button as far as the options screen allows (it has no button row): a two-way choice
    -- that reads PRESS TO CLEAR; pressed in the game it clears at once and reads PRESS TO CLEAR
    -- again, pressed in the launcher it waits for the next start (pressed again, it is undone)
    { key = "clear_rom_art", label = "CLEAR EXTRACTED ART", type = "choice", default = false,
      choices = { { "PRESS TO CLEAR", false }, { "CLEARS AT NEXT START", true } } },
    { key = "hd_render", label = "HD RENDERING", type = "toggle", default = true },
    { key = "haptics", label = "HAPTICS", type = "choice", default = "medium",
      choices = { { "HIGH", "high" }, { "MEDIUM", "medium" }, { "LOW", "low" }, { "OFF", "off" } } },
  })

  -- save data and options kept under the old id carry over once
  local makeRename = loadSibling(mod, "src/rename.lua")
  if makeRename then makeRename(mod, "ds_touch").install() end

  local Layout = loadSibling(mod, "src/layout.lua")
  -- the touch screen is Kanto Gear's shape, 10:9 (Layout's default)
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
  -- one still frame of a Pokemon's pic, whatever sprite mod hands it out (shared as mod.stillPic)
  do
    local makeStill = loadSibling(mod, "src/stillpic.lua")
    if makeStill then mod.stillPic = makeStill(mod) end
  end
  -- text that wraps and shrinks to fit its box (shared as mod.textfit)
  mod.textfit = loadSibling(mod, "src/textfit.lua")
  -- vibration for touches and play at the HAPTICS option's level (shared as mod.haptics)
  do
    local makeHaptics = loadSibling(mod, "src/haptics.lua")
    if makeHaptics then mod.haptics = makeHaptics(mod) end
  end
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
  mod.hdTop = HdTop
  local Apps = makeApps(mod, Pointer, Layout)
  local PadHide = makePadHide(mod)
  local Cutout = makeCutout and makeCutout(mod) or nil
  Apps.onChange = function() Surface.dirty = true end
  local function dirty() Surface.dirty = true end

  -- ------- Pokemon-Amie (Gen 3 host in v1; the rules and apps are host-agnostic)

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
  local gameMakers = {
    berry = loadSibling(mod, "src/amie/games/berry_picker.lua"),
    head = loadSibling(mod, "src/amie/games/head_it.lua"),
    tile = loadSibling(mod, "src/amie/games/tile_puzzle.lua"),
  }
  local makeBenefits = loadSibling(mod, "src/amie/benefits.lua")
  local makeAmieText = loadSibling(mod, "src/amie/text.lua")
  local Rules, Petting, Store, Amie, amieHost, Benefits = nil, nil, nil, nil, nil, nil
  if RuleNumbers and makeRules and makePetting and makeStore and makeHost and makeSession and makePlayApp then
    Rules = makeRules(RuleNumbers)
    Petting = makePetting(PettingData or {})
    Store = makeStore(mod, Rules)
    amieHost = makeHost(mod)
    -- every sound effect Amie (and Super Training's stand-ins, through the same host) plays has
    -- its haptic: menu presses tick, good hits pulse, misses knock twice (src/haptics.lua)
    if mod.haptics and amieHost.playSe then
      local playSe = amieHost.playSe
      amieHost.playSe = function(name, ...)
        pcall(mod.haptics.onSound, name)
        return playSe(name, ...)
      end
    end
    -- the top-screen overlay finds our layers on the engine's stack through the host
    if HdTop and amieHost.Stack then HdTop.Stack = amieHost.Stack end
    Amie = makeSession(mod, { host = amieHost, Rules = Rules, Petting = Petting,
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
    -- which of the game's own effects plays when (G.se)
    Amie.sounds = loadSibling(mod, "data/amie_sounds.lua") or {}
    local ok, app = pcall(makePlayApp, mod, Pointer, Amie, Rules, Petting, amieHost)
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
    if makeGames then
      local Games = makeGames(mod, { Rules = Rules, Store = Store, host = amieHost, session = Amie })
      Amie.Games = Games
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
  local UiArt, Chip, TrainingWords = nil, nil, nil
  local DecorArt, AdaptArt = {}, nil
  -- the engine's art first: Amie's Decor (PlayNav's atlases), the pictures made from them, then
  -- the drawn UI
  local function engineArt(id)
    for _, art in ipairs(DecorArt) do
      local img, owned = art.image(id)
      if owned then return img, true end
    end
    if AdaptArt then
      local img, owned = AdaptArt.image(id)
      if owned then return img, true end
    end
    if UiArt then return UiArt.image(id) end
    return nil
  end
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
    local makeHud = loadSibling(mod, "src/training/hud.lua")
    local makeResults = loadSibling(mod, "src/training/results.lua")
    local makeMusic = loadSibling(mod, "src/training/music.lua")
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
        if makeHud then
          local okH, hud = pcall(makeHud, mod, Training, TRules, TSim)
          if okH and type(hud) == "table" then Training.hud = hud else mod.log:warn("training HUD failed to build: %s", tostring(hud)) end
        end
        if makeResults then
          local okR, res = pcall(makeResults, mod, Training, TRules, Radar)
          if okR and type(res) == "table" then Training.results = res else mod.log:warn("training results failed to build: %s", tostring(res)) end
        end
        if makeMusic then
          local okM, music = pcall(makeMusic, mod, Training, trainHost)
          if okM and type(music) == "table" then Training.music = music else mod.log:warn("training music failed to build: %s", tostring(music)) end
        end
        makeRegimen(mod, Training, { host = trainHost, Rules = TRules, Store = TStore, Items = TItems,
          Courses = Courses, Sim = TSim, Draw = Draw })
        for _, spec in ipairs({ { makeAimApp, "aim", { mod, Pointer, Training, TRules, TSim } },
          { makeCoursesApp, "courses", { mod, Pointer, Training, TRules } },
          { makeBagsApp, "bags", { mod, Pointer, Training, TRules, TStore } } }) do
          if spec[1] then
            local okA, tapp = pcall(spec[1], unpack(spec[3]))
            if okA and type(tapp) == "table" then
              -- the bag drawer is drawn over the home screen
              if spec[2] == "bags" and okC and type(capp) == "table" then tapp.core = capp end
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
      Assets.enabled = true
      -- Super Training's UI is drawn by the engine, not taken from the card image
      local makeUiArt = Training and TRules and loadSibling(mod, "src/training/ui_art.lua")
      if makeUiArt then
        local okU, ui = pcall(makeUiArt, mod, { Rules = TRules, statRgb = Training.STAT_RGB, courses = Training.Courses,
          botSprite = Training.Draw and Training.Draw.botSprite,
          shapeFor = Training.Draw and Training.Draw.shapeFor, drawBalloon = Training.Draw and Training.Draw.drawBalloon })
        if okU and type(ui) == "table" then
          UiArt = ui
          Assets.engine = ui.image
          -- Pokemon-Amie's room draws through the same maker
          local makeAmieArt = ui.gen and loadSibling(mod, "src/amie/ui_art.lua")
          if makeAmieArt then
            local okA, errA = pcall(makeAmieArt, mod, ui.kit, ui.gen)
            if not okA then mod.log:warn("amie ui art failed to build: %s", tostring(errA)) end
          end
          -- and its Decor (cushions, objects, wallpapers), Poke Puffs, hand, Berry Picker's and
          -- Head It's art, Tile Puzzle's trees and PLAY's treeline and lawn come from PlayNav's own
          -- atlases
          local makeDecorArt = loadSibling(mod, "src/amie/decor_art.lua")
          for _, set in ipairs({ { "data/amie_decor.lua", "assets/amie_decor.png" },
              { "data/amie_walls.lua", "assets/amie_walls.png" },
              { "data/amie_puffs.lua", "assets/amie_puffs.png" },
              { "data/amie_hand.lua", "assets/amie_hand.png" },
              { "data/amie_berry.lua", "assets/amie_berry.png" },
              { "data/amie_head.lua", "assets/amie_head.png" },
              { "data/amie_tile.lua", "assets/amie_tile.png" },
              { "data/amie_scene.lua", "assets/amie_scene.png" },
              { "data/amie_grass.lua", "assets/amie_grass.png" } }) do
            local cells = makeDecorArt and loadSibling(mod, set[1])
            if type(cells) == "table" then
              local okD, art = pcall(makeDecorArt, mod, cells, set[2])
              if okD and type(art) == "table" then
                DecorArt[#DecorArt + 1] = art
                Assets.engine = engineArt
              else
                mod.log:warn("amie decor art (%s) failed to build: %s", set[1], tostring(art))
              end
            end
          end
          -- the minigames' pictures the pages lack, made from the atlases' (data/amie_adapt.lua)
          local makeAdapt = loadSibling(mod, "src/amie/adapt_art.lua")
          local adaptList = loadSibling(mod, "data/amie_adapt.lua")
          if makeAdapt and type(adaptList) == "table" then
            local okA2, adapt = pcall(makeAdapt, mod, adaptList, function(id) return (engineArt(id)) end)
            if okA2 and type(adapt) == "table" then AdaptArt = adapt
            else mod.log:warn("amie adapted art failed to build: %s", tostring(adapt)) end
          end
        else
          mod.log:warn("training ui art failed to build: %s", tostring(ui))
        end
      end
      -- its words are PlayNav's own
      if Training then
        local words = loadSibling(mod, "data/training_words.lua")
        if type(words) == "table" then Training.words, TrainingWords = words, words end
      end
      -- and its music is PlayNav's own, rendered by the chip synth in the background
      local makeChip = Training and loadSibling(mod, "src/chipmusic.lua")
      if makeChip then
        local okC, chip = pcall(makeChip, mod)
        if okC and type(chip) == "table" then
          Chip = chip
          Assets.engineMusic = chip.track
          Assets.engineSound = chip.sound
        else
          mod.log:warn("chip music failed to build: %s", tostring(chip))
        end
      end
      for _, id in ipairs({ "play", "home", "decorate", "game_berry", "game_head", "game_tile",
        "training_core", "training_bags", "training_courses", "training_aim" }) do
        local a = Apps:get(id)
        if a then a.assets = Assets end
      end
      if Training and Training.arenaDraw then Training.arenaDraw.assets = Assets end
      if Training then Training.assets = Assets end
      if Amie then Amie.assets = Assets end
      -- the game's own sound effects (rendered by the import), shared as mod.sfx
      local makeSfx = loadSibling(mod, "src/sfx.lua")
      if makeSfx then
        local okS, sfx = pcall(makeSfx, mod, { assets = Assets, host = trainHost })
        if okS and type(sfx) == "table" then
          mod.sfx = sfx
          if Training then
            Training.sfx = sfx
            Training.sounds = loadSibling(mod, "data/training_sounds.lua") or {}
          end
        else
          mod.log:warn("sound effects failed to build: %s", tostring(sfx))
        end
      end
      -- the game's own screens (layouts and clips the extract copies): shared as mod.lyt
      local LytFiles = loadSibling(mod, "src/lytfile.lua")
      local LytPlayer = loadSibling(mod, "src/lytplayer.lua")
      local makeScreens = loadSibling(mod, "src/lytscreen.lua")
      if LytFiles and LytPlayer and makeScreens then
        local Screens = makeScreens(mod, LytFiles, LytPlayer)
        Screens.assets = Assets
        mod.lyt = Screens
        if Training then Training.lyt = Screens end
        local refresh = Assets.refresh
        Assets.refresh = function(...)
          Screens.reset()
          return refresh(...)
        end
      end
    end
    if makeExtract and Recipe and Assets then
      Extract = makeExtract(mod, { recipe = Recipe, assets = Assets, onChange = dirty })
      if makeImportApp then
        local ok, app = pcall(makeImportApp, mod, Pointer, Extract, Assets)
        if ok and type(app) == "table" then Apps:register(app) end
      end
    else
      mod.log:warn("Alpha Sapphire import modules missing; extracted art stays off")
    end
  end

  -- Pokemon-Amie's minigame music: Super Training's player (src/training/music.lua) on the
  -- game's own sequences (recipe kind "song"). PLAY and the room keep the field's music, as the
  -- game does (Wooble's capture: the city's theme plays on under PLAY); a minigame holds it and
  -- plays its theme. Berry Picker's speeds up as its time runs out (x1.125 from 30 s left,
  -- x1.25 from 10 s, back at TIME'S UP; measured from the capture), the player moving between
  -- the tempo renders at the same point in the song.
  local amieMusic = nil
  if Amie and Assets and trainHost then
    local makeMusic = loadSibling(mod, "src/training/music.lua")
    local okM, M = false, nil
    if makeMusic then okM, M = pcall(makeMusic, mod, { assets = Assets }, trainHost) end
    if okM and type(M) == "table" then
      amieMusic = M
      M.PROBE = "bgm/kw_game01"
      M.SONGS = { ["bgm/kw_game01"] = { song = "game01", tempo = 1 },
        ["bgm/kw_game01_fast"] = { song = "game01", tempo = 1.125 },
        ["bgm/kw_game01_faster"] = { song = "game01", tempo = 1.25 } }
      M.FAST_AT, M.FASTER_AT = 30, 10
      M.FEVER_PITCH = 2 ^ (2 / 12)
      local THEME = { berry = "bgm/kw_game01", head = "bgm/kw_game02", tile = "bgm/kw_game03" }
      function M.session() return Amie.session end
      function M.holds(s, id) return id ~= nil end
      function M.wanted(s)
        if not (s and s.mode == "game" and s.game) or (Amie.inBattle and Amie.inBattle()) then
          return nil, false, M.FADE_S
        end
        local id = THEME[s.game.id]
        if s.game.id == "head" then
          -- FEVER: the theme 2 semitones up, faster with it (Wooble's Head It capture)
          local app = Apps:get("game_head")
          local st = app and app.debugState and app.debugState()
          if st and st.fever and (st.phase == "play" or st.phase == "timeup") then return id, true, 0, M.FEVER_PITCH end
        end
        if s.game.id == "berry" then
          local app = Apps:get("game_berry")
          local st = app and app.debugState and app.debugState()
          if st and st.phase == "play" and not st.lives and st.timer then
            if st.timer <= M.FASTER_AT then id = "bgm/kw_game01_faster"
            elseif st.timer <= M.FAST_AT then id = "bgm/kw_game01_fast" end
          end
        end
        return id, true, 0
      end
    else
      mod.log:warn("amie music failed to build: %s", tostring(M))
    end
  end

  -- the PlayNav menu (START -> PLAYNAV): its apps and callbacks are filled in below, once
  -- the import gate exists
  local menuDeps = { Assets = Assets }
  do
    local makeMenu = loadSibling(mod, "src/apps/menu.lua")
    if makeMenu then
      local ok, app = pcall(makeMenu, mod, Pointer, menuDeps)
      if ok and type(app) == "table" then Apps:register(app) else mod.log:warn("menu failed to build: %s", tostring(app)) end
    end
  end

  -- the session screens switch apps themselves; no tab strip over them
  for _, id in ipairs({ "play", "home", "decorate", "game_berry", "game_head", "game_tile", "import", "menu" }) do
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

  -- the surface shows only while the active app asks for it; this is what lets
  -- Kanto Gear keep the bottom screen
  local function surfaceWanted()
    local app = Apps:active()
    if app and app.wantsSurface then
      local ok, wants = pcall(app.wantsSurface, app)
      return ok and wants == true
    end
    return false
  end

  local PUSH_K_MAX = (HD and HD.MAX_K) or 4

  -- The bridge's display checks cross into Android (JNI, system settings) and several hooks
  -- ask every frame: share one answer for BRIDGE_CHECK_S, as Kanto Gear 4.0 does
  local BRIDGE_CHECK_S = 0.05
  local bridgeChecks = {}
  local function bridgeCheck(SS, name)
    local fn = SS and SS[name]
    if not fn then return false end
    local now = Pointer.now()
    local c = bridgeChecks[name]
    if not c or c.fn ~= fn or now < c.at or now >= c.at + BRIDGE_CHECK_S then
      local ok, v = pcall(fn)
      c = { fn = fn, at = now, value = ok and v == true }
      bridgeChecks[name] = c
    end
    return c.value
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
    if usable and bridgeCheck(SS, "detected") then return "second_screen" end
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
    -- the display is enabled afresh each time the mode is entered
    state.ssEnabled, state.ssShown = false, false
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
      -- the mouse can be pressed by two paths at once - the engine's pointer event (engines
      -- that deliver the desktop mouse to mods) and the poll below: a second press on a mouse
      -- already down is the same click, not a new one (restarting it read as a release, so a
      -- held shot fired once before charging)
      if source == "mouse" and Pointer:get(id) then return true end
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

  -- window units to physical pixels (the engine's Display.fit draws the picture at a whole
  -- number of physical pixels)
  local function windowDpi()
    if not (love and love.graphics and love.graphics.getDPIScale) then return 1 end
    local ok, d = pcall(love.graphics.getDPIScale)
    d = ok and tonumber(d) or 1
    return d > 0 and d or 1
  end

  -- Portrait split leaves the engine's touch pad its room: from the top of its highest
  -- control in the lower half (the player's own positions included) to the window's foot.
  -- Measured whenever the pad is on in the engine's settings, not only while it shows, so the
  -- layout does not jump when a PlayNav screen hides the pad.
  local okTC, TC = pcall(require, "src.core.TouchControls")
  if not (okTC and type(TC) == "table") then TC = nil end
  local gearPresent = nil
  local function padReserve(ww, wh)
    if wh < ww or not TC then return 0 end
    -- Kanto Gear owns the controls when it is installed: the engine pad never
    -- shows, so no room is held for it and the touch screen sits at the window's
    -- bottom, where the Gear's phone sat (feature/KantoGearAdd)
    if gearPresent == nil then gearPresent = (mod.find and mod:find("kanto_gear")) ~= nil end
    if gearPresent then return 0 end
    local game = state.game
    local opts = game and type(game.options) == "table" and game.options or nil
    if opts and TC.normalizeConfig then
      local okC, cfg = pcall(TC.normalizeConfig, opts.touchControls)
      if okC and type(cfg) == "table" and not cfg.enabled then return 0 end
    end
    if TC.active == false then return 0 end
    local okL, zones = pcall(TC.layout, TC)
    if not (okL and type(zones) == "table") and TC.defaultLayout then
      okL, zones = pcall(TC.defaultLayout, ww, wh, 0, 0, 1, true)
    end
    if not (okL and type(zones) == "table") then return math.floor(wh * 0.3) end
    local top = wh
    for name, z in pairs(zones) do
      if name ~= "hotbar" and type(z) == "table" and tonumber(z.cy) and z.cy > wh / 2 then
        top = math.min(top, z.cy - (tonumber(z.h) or tonumber(z.w) or 0) / 2)
      end
    end
    return math.max(0, wh - top)
  end

  -- Gen 3 has no viewport seam, but it fits its picture into the rectangle
  -- Playfield.cutout reports. In split mode the mod lays out picture and
  -- surface (src/layout.lua Layout.dual, New 3DS XL style), hands the picture area to the
  -- engine through src/cutout.lua, and keeps the rest for the surface, so
  -- both scale with the window and never overlap. Without the cutout seam
  -- the surface falls back to the free strip under the engine's own placement.
  -- the layout changes with the window, its DPI and the pad's room: the pad is measured once
  -- a second (the player can move its controls), the layout only when one of those moved
  local layoutCache = {}
  -- the overworld is on the top screen (no PlayNav layer on top of the engine's stack: Super
  -- Training's home): the playfield takes all the room the touch screen leaves (Layout.dual
  -- `fill`); a regimen fills too (topFills); with Amie, the picker or results up, the exact picture
  local function overworldLive()
    if not (HdTop and HdTop.topLayer) then return false end
    local ok, layer = pcall(HdTop.topLayer)
    return ok and layer == nil
  end
  -- the top screen fills the playfield: the live overworld, or a layer of ours that paints it
  -- all (the regimen's stadium; src/hd_top.lua wantsFill)
  local function topFills()
    if overworldLive() then return true end
    if not (HdTop and HdTop.wantsFill) then return false end
    local ok, v = pcall(HdTop.wantsFill)
    return ok and v == true
  end
  -- the area a filling top layer paints: split's playfield; with the touch screen on a second
  -- display (a Thor, Kanto Gear's phone) the whole top display, past the game's 3:2 picture
  if HdTop then
    HdTop.playfield = function()
      if Cutout and Cutout:active() then return Cutout.rect end
      if state.mode == "second_screen" or state.mode == "phone" then
        local ok, w, h = pcall(function() return love.graphics.getDimensions() end)
        if ok and w and h then return { x = 0, y = 0, w = w, h = h } end
      end
      return nil
    end
  end
  local function gen3Rect(vp)
    local ww, wh = vp.width or 0, vp.height or 0
    if ww < 1 or wh < 1 then return nil end
    if Cutout and Cutout.pf then
      local c, now, dpi = layoutCache, Pointer.now(), windowDpi()
      local fill = topFills()
      local moved = c.ww ~= ww or c.wh ~= wh or c.dpi ~= dpi or c.fill ~= fill or c.H ~= Layout.H
      if moved or now >= (c.padAt or 0) then
        local reserve = padReserve(ww, wh)
        c.padAt = now + 1
        if moved or c.reserve ~= reserve or c.lay == nil then
          c.ww, c.wh, c.dpi, c.reserve, c.fill, c.H = ww, wh, dpi, reserve, fill, Layout.H
          c.lay = Layout.dual(ww, wh, { dpi = dpi, reserveBottom = reserve, fill = fill }) or false
        end
      end
      local lay = c.lay
      if lay then
        Cutout:set(lay.game)
        return lay.surface
      end
    end
    if wh >= ww then
      local bottom = (vp.gameY or 0) + (vp.gameHeight or 0)
      local r = Layout.inRect(0, bottom, ww, wh - bottom, { anchor = "bottom" })
      if r and r.scale >= 1 then return r end
    else
      local right = (vp.gameX or 0) + (vp.gameWidth or 0)
      local r = Layout.inRect(right, 0, ww - right, wh, {})
      if r and r.scale >= 1 then return r end
    end
    return Layout.split(ww, wh, {}).surface
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

  -- PlayNav needs its extracted art: any attempt to open Pokemon-Amie or Super Training
  -- with the cache missing or stale lands on the PLAYNAV screen instead (Begin extraction,
  -- the progress bar, or the missing-card-image warning). True = gated, the screen is up.
  local gateDisabled = false   -- the flow tests run on fake hosts, not the player's cache
  local function importGate()
    if not Extract or gateDisabled then return false end
    if Extract.state == "running" or Extract.state == "finishing" or not Extract.cacheComplete() then
      Extract.check()
      Apps:setActive("import", state.game)
      return true
    end
    return false
  end
  -- Kanto Gear's Silph Store: PlayNav registers Super Training and Pokemon-Amie as
  -- third-party modules through the Gear's hook (exports.modules, api 1). Without
  -- Kanto Gear, or on a Gear without the hook, this is a no-op; the START menu
  -- entries remain.
  do
    local gear = mod.find and mod:find("kanto_gear")
    local modules = gear and gear.exports and gear.exports.modules
    local makeGearModule = modules and type(modules.register) == "function"
      and loadSibling(mod, "src/gear_module.lua")
    -- true while PlayNav's surface is up: the Gear stands down meanwhile
    local function shown() return state.mode ~= nil and state.mode ~= "off" end
    local function register(app, session)
      if not (makeGearModule and session) then return end
      local okSpec, spec = pcall(makeGearModule, {
        app = app,
        -- the press: the app opens, or the PLAYNAV import screen takes over
        -- first; both count as taking the bottom screen
        open = function()
          if importGate() then return true end
          local ok = session.open()
          return ok == true
        end,
        shown = shown,
      })
      if okSpec and spec then
        local okReg, registered, why = pcall(modules.register, spec)
        if okReg and registered == true then
          mod.log:info("registered %s in Kanto Gear's store", spec.id)
        else
          mod.log:warn("Kanto Gear store registration of %s refused: %s", tostring(spec.id),
            tostring(okReg and why or registered))
        end
      end
    end
    register("training", Training)
    register("amie", Amie)
  end

  do
    -- the PLAYNAV screen's x button steps aside (the surface goes dormant without a session)
    local gateApp = Apps:get("import")
    if gateApp then
      gateApp.close = function() Apps:setActive("play", state.game) end
      -- its play button: the PlayNav menu opens behind the closed shutters
      gateApp.openMenu = function()
        local menu = Apps:get("menu")
        if not menu then return false, "menu missing" end
        if Assets then Assets.refresh() end
        return menu.show({ shutters = true })
      end
    end
  end

  -- the PlayNav menu's apps, in the game's order (its Player Search System left out)
  do
    menuDeps.setActive = function(id) Apps:setActive(id, state.game) end
    menuDeps.inBattle = function() return Amie ~= nil and Amie.inBattle ~= nil and Amie.inBattle() end
    -- the game's shutters sound (Super Training's screen changes) wherever PlayNav draws them
    menuDeps.shutterSound = function()
      if Training and Training.playSe then Training.playSe("transition") end
    end
    local gateApp2 = Apps:get("import")
    if gateApp2 then gateApp2.shutterSound = menuDeps.shutterSound end
    local makeGearModule = loadSibling(mod, "src/gear_module.lua")
    local function iconFor(which)
      if not makeGearModule then return nil end
      local ok, spec = pcall(makeGearModule, { app = which })
      return ok and type(spec) == "table" and spec.icon or nil
    end
    local apps = {}
    if Amie and mod.generation == 3 and amieHost and amieHost.available() then
      apps[#apps + 1] = {
        id = "amie", caption = "Play with your Pokémon", name = "Pokémon-Amie",
        icon = iconFor("amie"),
        colours = { left = { 0.55, 0.15, 0.36 }, right = { 0.95, 0.47, 0.67 }, edge = { 1, 0.72, 0.84 },
          word = { 1, 1, 1 }, wordEdge = { 0.5, 0.1, 0.3 } },
        open = function()
          if importGate() then return true end
          return Amie.open()
        end,
      }
    end
    if Training and mod.generation == 3 and trainHost and trainHost.available() then
      apps[#apps + 1] = {
        id = "training", caption = "Train your Pokémon", name = "Super Training",
        icon = iconFor("training"), shutters = true, slant = 0.18,
        colours = { left = { 0.04, 0.3, 0.34 }, right = { 0.16, 0.7, 0.68 }, edge = { 0.6, 0.95, 0.92 },
          word = { 1, 0.8, 0.25 }, wordEdge = { 0.36, 0.16, 0.04 } },
        open = function()
          if importGate() then return true end
          local ok, why = Training.open()
          if ok and Training.session then
            -- its home screen opens behind the shutters the menu closed
            local X = Training.TRANS or { CLOSE = 20, OPEN = 10 }
            Training.session.trans = { to = "core", from = "gate", t = X.CLOSE + 2, switched = true }
          end
          return ok, why
        end,
      }
    end
    menuDeps.apps = apps
  end

  -- CLEAR EXTRACTED ART: wipe the cache, close any session that was drawing from it, and
  -- land on the PLAYNAV screen (BEGIN EXTRACTION, or the missing-card warning). Never
  -- starts an extraction by itself.
  local function clearExtractedArt()
    if not Extract then return end
    if Training and Training.session then pcall(Training.finish) end
    if Amie and Amie.session then pcall(Amie.finish) end
    local ok, err = pcall(Extract.clear)
    if not ok then mod.log:warn("clearing the extracted art failed: %s", tostring(err)) end
    Apps:setActive("import", state.game)
  end
  -- the option back to PRESS TO CLEAR, saved: mods get no options setter, so this writes
  -- where the Mod Manager's own setOption does (the loader's table, the save's options) and
  -- has the engine write options.lua
  local function resetClearOption()
    local game = state.game
    local loader = game and game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id].clear_rom_art = false
    end
    local saved = game and game.save and game.save.options and game.save.options.modOptions
    if saved and saved[mod.id] then saved[mod.id].clear_rom_art = false end
    if game and game.writeOptions then
      local ok, err = pcall(game.writeOptions, game)
      if not ok then mod.log:warn("saving CLEAR EXTRACTED ART back off failed: %s", tostring(err)) end
    end
  end
  mod.events:on("mod.options_changed", function(ev)
    if type(ev) ~= "table" or ev.mod ~= "play_nav" or ev.key ~= "clear_rom_art" or ev.value ~= true then return end
    clearExtractedArt()
    resetClearOption()
  end)

  -- While a mouse pointer is down on the surface, follow the real cursor
  -- every frame. Event routing for a held mouse differs per generation and
  -- per touch flag (see love.mousemoved in the engine's main.lua); polling
  -- makes a drag register the same way everywhere. A move that events
  -- already delivered is a zero-length step here and changes nothing.
  -- A finger is also reported as a mouse (LÖVE's touch-to-mouse emulation, on by default on
  -- iOS, Android and touchscreen PCs); polled, every tap reached the apps twice - the touch,
  -- then a "mouse" tap at the same spot, which toggled the bag drawer and Amie's menu straight
  -- back shut. Phones have no mouse to poll, and elsewhere a press with a touch down is a finger.
  local MOBILE = { iOS = true, Android = true }
  local function fingerDown()
    if not (love.touch and love.touch.getTouches) then return false end
    local ok, touches = pcall(love.touch.getTouches)
    return ok and type(touches) == "table" and #touches > 0
  end

  local function pollMouse()
    if not (love and love.mouse and love.mouse.getPosition) then return end
    if state.mode ~= "split" or MOBILE[osName()] then
      state.polledX, state.polledY, state.mouseWasDown = nil, nil, nil
      return
    end
    local rec = Pointer:get("mouse")
    local mx, my = love.mouse.getPosition()
    local down = love.mouse.isDown ~= nil and love.mouse.isDown(1) or false
    if not rec then
      state.polledX, state.polledY = nil, nil
      -- Desktop Gen 3 never delivers the mouse to mods as events (the game
      -- instance keeps its own handler, found 2026-10-17), so the poll starts
      -- the pointer itself the frame the button goes down on the surface.
      if down and not state.mouseWasDown and not fingerDown() then
        feedWindow("pressed", "mouse", mx, my, nil, "mouse")
      end
      state.mouseWasDown = down
      return
    end
    state.mouseWasDown = down
    if mx ~= state.polledX or my ~= state.polledY then
      state.polledX, state.polledY = mx, my
      local lx, ly = Layout.toLogical(state.rect or { x = 0, y = 0, scale = 1 }, mx, my)
      if lx ~= rec.x or ly ~= rec.y then Pointer:move("mouse", lx, ly) end
    end
    if not down then
      local lx, ly = Layout.toLogical(state.rect or { x = 0, y = 0, scale = 1 }, mx, my)
      Pointer:finish("mouse", lx, ly)
    end
  end

  local function tick(game, viewport)
    state.game = game
    local dt = frameDt()
    if mod.haptics then mod.haptics.update(dt) end
    if amieMusic then
      local okM, errM = pcall(amieMusic.update, dt)
      if not okM and not state.amieMusicWarned then
        state.amieMusicWarned = true
        mod.log:warn("amie music failed: %s", tostring(errM))
      end
    end
    tickExtract()
    if Chip then
      local okC, errC = pcall(Chip.update)
      if not okC and not state.chipWarned then
        state.chipWarned = true
        mod.log:warn("chip music failed: %s", tostring(errC))
      end
    end
    -- CLEAR EXTRACTED ART switched on in the launcher, before PlayNav loaded: no change event
    -- reaches us then, so it is honoured once, on the first frame in the field
    -- (drivers call _test.keepArt() before the field so a run on a machine whose options have
    -- it on leaves the player's art alone; the sandbox has no os.getenv)
    if extractChecked and not state.clearChecked then
      state.clearChecked = true
      if mod.options:get("clear_rom_art") == true and not state.keepArt then
        clearExtractedArt()
        resetClearOption()
      end
    end
    setMode(wantedMode())
    pollMouse()
    local mode = state.mode
    -- an app the player can walk around with (Super Training's home) keeps the engine's pad
    local active = Apps:active()
    local walking = active ~= nil and active.fieldPlay == true
    -- with Kanto Gear installed the engine pad is redundant (the Gear owns the
    -- controls), so it hides under the surface even on the walking screens
    if gearPresent == nil then gearPresent = (mod.find and mod:find("kanto_gear")) ~= nil end
    PadHide:apply(mode ~= "off" and (gearPresent == true or not walking) and mod.options:get("hide_virtual_pad") ~= false, game)
    -- apps keep ticking while dormant so a session can wake the surface
    Apps:update(dt, game)
    -- Super Training's home screen runs with the overworld live: its session ticks here
    -- Amie's room lives without the top-screen layer (the game keeps the top): its session
    -- ticks here then
    if Amie and Amie.frame then
      local ok, err = pcall(Amie.frame, dt)
      if not ok and not state.amieFrameWarned then
        state.amieFrameWarned = true
        mod.log:warn("amie: tick failed (%s)", tostring(err))
      end
    end
    if Training and Training.frame then
      local ok, err = pcall(Training.frame, dt)
      if not ok and not state.frameWarned then
        state.frameWarned = true
        mod.log:warn("super training: tick failed (%s)", tostring(err))
      end
    end
    -- Super Training keeps punching (and resting) while its screen is closed
    if Training and Training.background then
      local ok, err = pcall(Training.background, game ~= nil and game.phase == "field")
      if not ok and not state.bgWarned then
        state.bgWarned = true
        mod.log:warn("super training: background tick failed (%s); training resumes when the screen opens", tostring(err))
      end
    end
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
    -- Android posts UI-thread work for every enable call, even an unchanged one: enable once
    -- on entering the mode, then retry once a second only while frames are not getting through
    local now = Pointer.now()
    if not state.ssEnabled or (not state.ssShown and now >= (state.ssRetryAt or 0)) then
      pcall(SS.setEnabled, true)
      state.ssEnabled, state.ssRetryAt = true, now + 1
    end
    for _ = 1, 128 do
      local ok, event = pcall(SS.pollTouch)
      if not ok or not event then break end
      local action, x, y = Pointer.parse(event)
      if action and x and y then feedSecond(action, x, y) end
    end
    local t = Pointer.now()
    if bridgeCheck(SS, "available") then
      -- a frame read back since the last tick goes out now
      local ready, rw, rh = Surface:pollPush()
      if ready then
        local okP, shown = pcall(SS.push, ready, rw, rh, 0x000000, "secondary")
        state.ssShown = okP and shown ~= false
      end
      local due = t - state.pushAt
      if not Surface.pending and ((needsDraw and due >= 1 / 30) or due >= 1.0) then
        -- always as sharp as PlayNav draws (HD.MAX_K, 4); the display fits it to its size
        local k = PUSH_K_MAX
        state.pushK = k
        state.pushAt = t
        -- drawn now, read back without waiting (the pixels come through pollPush); only a LOVE
        -- without the async readback hands them back at once
        local data, w, h = Surface:requestPush(k, drawAll, t)
        if data then
          local okP, shown = pcall(SS.push, data, w, h, 0x000000, "secondary")
          state.ssShown = okP and shown ~= false
        end
      else
        Surface:dropStale(t)
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
    local layout = Layout.split(b.width, b.height, {})
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

  -- PlayNav's split owns the window's layout: an outer render.output that resizes the whole
  -- finished frame (Kanto Gear's combined screen) would shrink the picture PlayNav placed. So
  -- innermost, while the split shows on Gen 3, the frame goes to the window exactly as the
  -- engine draws it (1:1, scissored to the playfield) and reports it drawn: an outer mod then
  -- passes it through (Kanto Gear also drops its own touch area then). A shader preset keeps
  -- the engine's own path.
  mod.hooks:wrap("render.output", function(next, ctx)
    if mod.generation == 3 and state.mode == "split" and state.rect and type(ctx) == "table"
        and ctx.canvas and Cutout and Cutout:active() then
      local okFx, FX = pcall(require, "src.render.ShaderFX")
      local shaded = okFx and type(FX) == "table" and FX.active and FX.active()
      if not shaded then
        local G = love.graphics
        local r = Cutout.rect
        G.push("all")
        G.setCanvas()
        G.origin()
        G.setShader()
        G.setBlendMode("alpha")
        G.setScissor(r.x, r.y, r.w, r.h)
        G.setColor(1, 1, 1, 1)
        G.draw(ctx.canvas, 0, 0)
        G.pop()
        return true
      end
    end
    return next(ctx)
  end, -10000)

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
    -- Gen 3 on a desktop: a real mouse reaches gameplay only as these pointer
    -- events (the engine's #807 path; Game3 never dispatches the old mouse
    -- method wrap), so the surface claims its own clicks here. Touches keep
    -- the TouchControls route, which never emits a pointer event it consumed.
    if state.mode == "split" and mod.generation == 3 and ev.source == "mouse"
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
        pcall(Amie.onBattleStarted)
      end)
      mod.events:on("world.stepped", function()
        pcall(Amie.onStep)
      end)
      if Benefits then Benefits.install() end
    else
      mod.log:warn("Pokemon-Amie needs the Gen 3 UI stack and pokemon modules; it stays off")
    end
  elseif Amie then
    mod.log:info("Pokemon-Amie runs on Gen 3 in this version")
  end

  -- the PlayNav strip across the top of Amie's room, as over Super Training's home
  if Amie then
    local makeStrip = loadSibling(mod, "src/strip.lua")
    local Strip = makeStrip and makeStrip(function() return Assets end)
    local home = Apps:get("home")
    if Strip and home then
      local draw0 = home.draw
      home.draw = function(self, G, w, h)
        draw0(self, G, w, h)
        if Amie.session and Amie.session.mode == "home" then Strip.draw(G, w, self.bleed or 14) end
      end
    end
  end

  if Training and mod.generation == 3 and trainHost.available() then
    TStore.migrate()
    -- registered at load (the registry closes afterwards); national_dex_gen3 is an optional
    -- dependency so it loads first and its Gen 4 stones are found and shared, not fought
    if TItems then TItems.install() end
  elseif Training then
    mod.log:info("Super Training runs on Gen 3 in this version")
  end

  -- one START menu entry, PLAYNAV: the menu of PlayNav's apps (src/apps/menu.lua). It
  -- toggles: with an app or the menu up, it closes them.
  local menuApp = Apps:get("menu")
  if menuApp and mod.generation == 3 and #(menuDeps.apps or {}) > 0 then
    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      local out = next(game, items)
      if type(out) ~= "table" or #menuApp.cards() == 0 then return out end
      for _, e in ipairs(out) do
        if type(e) == "table" and e.id == "play_nav" then return out end
      end
      local entry = {
        id = "play_nav", label = "PLAYNAV", text = "PLAYNAV",
        onSelect = function()
          local ok, StartMenu = pcall(require, "src.ui.game3.start_menu")
          if ok and StartMenu and StartMenu.close then pcall(StartMenu.close, true) end
          local open = (Amie and Amie.session) or (Training and Training.session)
            or (menuApp.shown() and Apps:active() == menuApp)
          if open then
            menuApp.hide()
            if Amie and Amie.session then Amie.finish() end
            if Training and Training.session then Training.finish() end
            Apps:setActive("play", state.game)
            return
          end
          if importGate() then return end
          menuApp.show()
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
  end

  -- ------- what other mods (future minigames) can reach

  mod.exports.pointer = Pointer
  mod.exports.apps = Apps
  mod.exports.hdTop = HdTop   -- the top-screen overlay (drivers read .why)
  mod.exports.hd = HD         -- the pixel-art drawing (drivers check its shader)
  mod.exports.haptics = mod.haptics   -- (drivers record the pulses through .log)
  mod.exports.layout = Layout
  mod.exports.W, mod.exports.H = Layout.W, Layout.H
  mod.exports.state = function()
    return { mode = state.mode, rect = state.rect, tabHeight = Apps.TAB_H, pushK = state.pushK }
  end
  mod.exports.assets = Assets
  if menuApp then
    -- the PlayNav menu: open lands on the import screen first while the art is missing
    mod.exports.menu = {
      open = function()
        if importGate() then return false, "import_needed" end
        return menuApp.show()
      end,
      close = function()
        menuApp.hide()
        Apps:setActive("play", state.game)
      end,
      shown = function() return menuApp.shown() end,
      app = menuApp,
    }
  end
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
      open = function(mon)
        if importGate() then return false, "import_needed" end
        return Amie.open(mon)
      end,
      openPlay = function(mon)
        if importGate() then return false, "import_needed" end
        return Amie.openPlay(mon)
      end,
      state = function() return Amie.state() end,
      music = amieMusic,   -- the minigames' music player (drivers read .current)
      onBattleEnded = function(ev) return Amie.onBattleEnded(ev) end,
      puffs = function() return Store.puffs() end,
      meters = function(key) return Store.meters(key) end,
      monKey = function(mon) return amieHost.monKey(mon) end,
      rules = Rules,
      petting = Petting,
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
      open = function(mon)
        if importGate() then return false, "import_needed" end
        return Training.open(mon)
      end,
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
    surface = Surface,
    drawAll = drawAll,
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
    extract = function() return Extract end,
    assets = function() return Assets end,
    setImportGate = function(on) gateDisabled = on == false end,
    keepArt = function() state.keepArt = true end,
    -- false: the card image's UI art again (for side-by-side shots); true: the engine's
    -- false: the card image's music and effects again; true: PlayNav's own
    engineMusic = function(on)
      if Assets then
        Assets.engineMusic = (on ~= false and Chip) and Chip.track or nil
        Assets.engineSound = (on ~= false and Chip) and Chip.sound or nil
      end
      return Chip
    end,
    -- false: the card image's text again; true: PlayNav's own words
    engineText = function(on)
      if Training then Training.words = (on ~= false) and TrainingWords or nil end
      if Amie and Amie.text then Amie.text.ownText = on ~= false end
      return Training and Training.words
    end,
    engineUi = function(on)
      if Assets then Assets.engine = (on ~= false and UiArt) and engineArt or nil end
      return UiArt
    end,
  }

  mod.log:info("PlayNav ready (gen %s, touch screen %s)", tostring(mod.generation),
    tostring(mod.options:get("display")))
end
