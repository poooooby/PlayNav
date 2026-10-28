-- NaviPlay shipped as `ds_touch` up to 0.3.0. The engine keys a mod's save data
-- (session.modData[id]) and its Mod Manager options (loader.modOptions[id]) by the
-- mod id, so the rename would otherwise start every player over. Once per save, the old
-- bucket is copied into the new one: the old progress wins over the fresh defaults the
-- mod wrote at load, the old bucket is left in place, and `renamedFrom` marks it done.
-- Options copy only the keys the player has not set under the new id.

return function(mod, OLD)
  local M = { OLD = OLD or "ds_touch" }

  -- modData = the session's per-mod save table; returns true when it copied
  function M.saveData(modData)
    if type(modData) ~= "table" then return false end
    local old = modData[M.OLD]
    if type(old) ~= "table" then return false end
    local new = modData[mod.id]
    if type(new) ~= "table" then
      new = {}
      modData[mod.id] = new
    end
    if new.renamedFrom then return false end
    for k, v in pairs(old) do new[k] = v end
    new.renamedFrom = M.OLD
    mod.log:info("save data carried over from %s", M.OLD)
    return true
  end

  -- loader.modOptions; returns the number of keys copied
  function M.options(modOptions)
    if type(modOptions) ~= "table" then return 0 end
    local old = modOptions[M.OLD]
    if type(old) ~= "table" then return 0 end
    local new = modOptions[mod.id]
    if type(new) ~= "table" then
      new = {}
      modOptions[mod.id] = new
    end
    local n = 0
    for k, v in pairs(old) do
      if new[k] == nil then new[k] = v; n = n + 1 end
    end
    if n > 0 then mod.log:info("%d option(s) carried over from %s", n, M.OLD) end
    return n
  end

  function M.install()
    mod.events:on("save.loaded", function(ev)
      local session = ev and ev.save
      local ok, err = pcall(M.saveData, session and session.modData)
      if not ok then mod.log:warn("carrying over %s save data failed: %s", M.OLD, tostring(err)) end
    end)
    -- options are read live, so they can follow on the first frame
    local done = false
    mod.hooks:wrap("render.hud", function(next, game, viewport)
      if not done then
        done = true
        local loader = game and game.mods
        local ok, err = pcall(M.options, loader and loader.modOptions)
        if not ok then mod.log:warn("carrying over %s options failed: %s", M.OLD, tostring(err)) end
      end
      return next(game, viewport)
    end)
  end

  return M
end
