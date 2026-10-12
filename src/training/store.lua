-- Super Training's save data: one `training` record in mod.save (travels with the save,
-- rewinds with checkpoints), versioned on its own so Amie and Training migrate apart.
--
-- training = {
--   schema = 1,
--   bags = { "hp_s", ... },                -- ordered, at most LIMITS.BAG_MAX
--   mons = { [key] = { bag = { id, hits, needed } | nil, pending = effect | nil,
--                      refreshedUntil = wall clock | nil, resting = bool, fully = bool,
--                      supremely = bool, courses = { [id] = { best, medal, clears } }, hits = n } },
--   cleared = { [courseId] = true },       -- any Pokemon; the unlock ladder
--   meta = { blackTaps, lastAutoHitAt, pendingItems = { { index, qty } } },
-- }

return function(mod, Rules)
  local S = { SCHEMA = 1 }

  local function fresh()
    return { schema = S.SCHEMA, bags = {}, mons = {}, cleared = {},
      meta = { blackTaps = 0, lastAutoHitAt = nil, pendingItems = {} } }
  end

  function S.data()
    local d = mod.save:get("training")
    if type(d) ~= "table" then
      d = fresh()
      mod.save:set("training", d)
    end
    local f = fresh()
    for k, v in pairs(f) do if d[k] == nil then d[k] = v end end
    for k, v in pairs(f.meta) do if d.meta[k] == nil then d.meta[k] = v end end
    return d
  end

  function S.save() mod.save:set("training", S.data()) end

  -- schema bumps go here; 1 is the first
  function S.migrate()
    local d = S.data()
    if (tonumber(d.schema) or 0) >= S.SCHEMA then return false end
    d.schema = S.SCHEMA
    S.save()
    return true
  end

  function S.bags() return S.data().bags end
  function S.cleared() return S.data().cleared end
  function S.meta() return S.data().meta end

  function S.mon(key)
    local mons = S.data().mons
    local m = mons[key]
    if type(m) ~= "table" then
      m = {}
      mons[key] = m
    end
    if m.courses == nil then m.courses = {} end
    if m.hits == nil then m.hits = 0 end
    if m.resting == nil then m.resting = false end
    return m
  end

  function S.courseRecord(key, courseId)
    local m = S.mon(key)
    local c = m.courses[courseId]
    if type(c) ~= "table" then
      c = { best = nil, medal = false, clears = 0 }
      m.courses[courseId] = c
    end
    return c
  end

  -- counts for the tests and the result screens
  function S.counts()
    local d = S.data()
    local mons, cleared = 0, 0
    for _ in pairs(d.mons) do mons = mons + 1 end
    for _ in pairs(d.cleared) do cleared = cleared + 1 end
    return { bags = #d.bags, mons = mons, cleared = cleared, pendingItems = #d.meta.pendingItems }
  end

  function S.reset()
    mod.save:set("training", fresh())
  end

  return S
end
