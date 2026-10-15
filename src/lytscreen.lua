-- Opening a game screen: its layout from the files the extract copied (Assets.file), its
-- textures from the recipe rows lyt/<pack>/<name> (searched across the packs the screen
-- names, as the game falls back on its shared packs), its clips parsed on first use.
--
-- local Screens = makeScreens(mod, Files, Player) ; Screens.assets = Assets (set by main)
-- Screens.open(pack, "upper.bclyt", { "st_hud", "st_lang" }) -> Player | nil
-- (clips are named without the layout's prefix: P:play("game_start") reads
-- upper_game_start.bclan)

return function(mod, Files, Player)
  local S = { layouts = {}, clips = {} }
  if Player and Files then Player.setFiles(Files) end

  -- the USE EXTRACTED ART option, as main reads it into the loader once a frame
  local function useArt()
    return not (S.assets and S.assets.enabled == false)
  end

  local function bytes(pack, name)
    local A = S.assets
    if not (A and A.file) then return nil end
    local ok, b = pcall(A.file, pack, name)
    return ok and b or nil
  end

  function S.layout(pack, name)
    local key = pack .. "/" .. name
    if S.layouts[key] == nil then
      local b = bytes(pack, name)
      local L, why = nil, "absent"
      if b then
        local ok, res, err = pcall(Files.layout, b)
        if ok then L, why = res, err else why = res end
      end
      if not L and b then mod.log:warn("layout %s did not parse (%s); the screen keeps its drawn fallback", key, tostring(why)) end
      S.layouts[key] = L or false
    end
    return S.layouts[key] or nil
  end

  function S.clip(pack, name)
    local key = pack .. "/" .. name
    if S.clips[key] == nil then
      local b = bytes(pack, name)
      local C = nil
      if b then
        local ok, res = pcall(Files.clip, b)
        C = ok and res or nil
      end
      S.clips[key] = C or false
    end
    return S.clips[key] or nil
  end

  -- a fresh player for the screen, or nil when the art is not there (the caller draws its own)
  function S.open(pack, layoutName, texPacks)
    if not (Player and Files and useArt()) then return nil end
    local L = S.layout(pack, layoutName)
    if not L then return nil end
    local base = layoutName:gsub("%.bclyt$", "")
    texPacks = texPacks or { pack }
    return Player.new(L, {
      image = function(tex)
        local A = S.assets
        if not (A and A.image) then return nil end
        local id = tex:gsub("%.bclim$", "")
        for _, p in ipairs(texPacks) do
          local ok, img = pcall(A.image, "lyt/" .. p .. "/" .. id)
          if ok and img then return img end
        end
        return nil
      end,
      clip = function(name) return S.clip(pack, base .. "_" .. name .. ".bclan") end,
    })
  end

  -- forget parsed files (a new extract)
  function S.reset()
    S.layouts, S.clips = {}, {}
  end

  return S
end
