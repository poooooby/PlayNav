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

  -- the art loader's switch (always on in play; a test may turn it off)
  local function useArt()
    return not (S.assets and S.assets.enabled == false)
  end

  local function bytes(pack, name)
    local A = S.assets
    if not (A and A.file) then return nil end
    local ok, b = pcall(A.file, pack, name)
    return ok and b or nil
  end

  -- NaviPlay's own copy of a pack's layouts and clips (data/lyt/<pack>.lua, made by
  -- tools/lyt_data.lua: the same tables src/lytfile.lua parses, as numbers), read when the
  -- card image's files are not there; the pane tree's back links are rebuilt here
  S.packs = {}
  local function packData(pack)
    if S.packs[pack] == nil then
      local t = false
      local src = mod.read and mod:read("data/lyt/" .. pack .. ".lua")
      local chunk = src and load(src, "=data/lyt/" .. pack, "t", {})
      local ok, res = pcall(chunk or error)
      if ok and type(res) == "table" then t = res end
      S.packs[pack] = t
    end
    return S.packs[pack] or nil
  end
  local function relink(L)
    L.byName = {}
    local function walk(p, parent)
      p.parent = parent
      L.byName[p.name] = p
      for _, c in ipairs(p.children or {}) do walk(c, p) end
    end
    if L.root then walk(L.root, nil) end
    return L
  end
  local function own(pack, kind, name)
    local d = packData(pack)
    return d and d[kind] and d[kind][name] or nil
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
      if not L and not b then
        L = own(pack, "layouts", name)
        if L then relink(L) end
      end
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
      else
        C = own(pack, "clips", name)
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
