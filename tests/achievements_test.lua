-- NaviPlay's achievements against a stand-in recomp_achievements: every definition passes the
-- framework's rules, notes and sweeps award the right ids from fake saves, progress goes in as
-- absolute values, and without the framework everything is a no-op.
-- Run from the engine root: luajit mods/play_nav/tests/achievements_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local data = loadFile("mods/play_nav/data/achievements.lua")
local makeAch = loadFile("mods/play_nav/src/achievements.lua")

-- ------------------------------------------------------------ the definitions

do
  local seen, hidden, points = {}, 0, 0
  local VERSIONS = { red = 1, blue = 1, yellow = 1, gold = 1, silver = 1, crystal = 1, ruby = 1,
    sapphire = 1, emerald = 1, firered = 1, leafgreen = 1 }
  for i, row in ipairs(data.list) do
    local where = ("row %d (%s)"):format(i, tostring(row.id))
    T.check(type(row.id) == "string" and row.id:match("^[a-z0-9_%-]+$") and #row.id <= 48, where .. ": id")
    T.check(not seen[row.id], where .. ": id is unique")
    seen[row.id] = true
    T.check(type(row.title) == "string" and #row.title >= 1 and #row.title <= 32, where .. ": title length")
    T.check(type(row.description) == "string" and #row.description <= 160, where .. ": description length")
    T.check(not row.title:find("[\128-\255]") and not row.description:find("[\128-\255]"), where .. ": plain ASCII")
    T.check(type(row.points) == "number" and row.points >= 0 and row.points <= 100 and row.points % 1 == 0, where .. ": points")
    T.check(row.category and #row.category <= 16, where .. ": category")
    if row.goal then
      T.check(row.goal >= 1 and row.goal <= 1000000 and row.goal % 1 == 0, where .. ": goal")
      T.check(row.unit and #row.unit <= 12, where .. ": unit")
    end
    for _, g in ipairs(row.games or {}) do T.check(VERSIONS[g], where .. ": game " .. tostring(g)) end
    if row.hidden then hidden = hidden + 1 end
    points = points + row.points
  end
  T.eq(#data.list, 63, "32 Super Training + 31 Amie")
  T.eq(hidden, 6, "six hidden")
  T.check(points > 0, "points")
end

-- ------------------------------------------------------------ a stand-in framework

local function framework(opts)
  opts = opts or {}
  local fw = { registered = {}, unlocked = {}, progress = {}, listeners = {}, refused = opts.refused or {} }
  local handle = {}
  function handle:registerMany(list)
    local ok, errors = 0, {}
    for i, def in ipairs(list) do
      if fw.refused[def.id] then
        errors[#errors + 1] = { code = "invalid_title", msg = "refused" }
      else
        fw.registered[def.id] = def
        ok = ok + 1
      end
    end
    return ok, errors
  end
  function handle:unlock(id)
    if not fw.registered[id] then return nil, "unknown_id" end
    if not fw.attached then return nil, "no_save" end
    if fw.unlocked[id] then return nil, "already_unlocked" end
    fw.unlocked[id] = true
    return true
  end
  function handle:setProgress(id, n)
    local def = fw.registered[id]
    if not def then return nil, "unknown_id" end
    if not fw.attached then return nil, "no_save" end
    if not def.goal then return nil, "no_goal" end
    if fw.unlocked[id] then return nil, "already_unlocked" end
    n = math.max(0, math.min(n, def.goal))
    fw.progress[id] = n
    fw.sets = (fw.sets or 0) + 1
    if n >= def.goal then fw.unlocked[id] = true end
    return true
  end
  local api = { apiVersion = "1.2.0", events = { ready = "mod.recomp_achievements.ready" } }
  function api.supports() return true end
  function api.connect() return handle end
  fw.api = api
  function fw.ready()
    fw.attached = true
    for _, fn in ipairs(fw.listeners) do fn({ game = "emerald", how = "loaded" }) end
  end
  return fw
end

local function fakeMod(fw)
  local save = {}
  local m
  m = {
    id = "play_nav", exports = {}, saved = save,
    log = { info = function() end, warn = function(_, ...) m.warnings[#m.warnings + 1] = string.format(...) end },
    warnings = {},
    save = { get = function(_, k) return save[k] end, set = function(_, k, v) save[k] = v end },
    events = { on = function(_, name, fn) if fw then fw.listeners[#fw.listeners + 1] = fn end end },
  }
  if fw then m.find = function(_, id) if id == "recomp_achievements" then return { exports = fw.api } end end end
  return m
end

local clock = 0
local function now() return clock end

-- ------------------------------------------------------------ fake saves

local function trainingDeps(d)
  return function()
    return {
      Store = { data = function() return d end },
      Rules = { regularCleared = function(cleared, list)
        for _, c in ipairs(list) do if not cleared[c.id] then return false end end
        return #list > 0
      end },
      courses = function()
        local out = {}
        for level = 1, 3 do
          for _, stat in ipairs({ "hp", "atk", "def", "spa", "spd", "spe" }) do
            out[#out + 1] = { id = ("lv%d_%s"):format(level, stat) }
          end
        end
        return out
      end,
    }
  end
end

local function amieDeps(s)
  return function()
    return {
      Store = {
        mons = function() return s.mons end, games = function() return s.games end,
        decor = function() return s.decor end, room = function() return s.room end,
        meta = function() return s.meta end, puffs = function() return s.puffs end,
      },
      Rules = {
        level = function(a) return a >= 150 and 4 or a >= 100 and 3 or a >= 50 and 2 or 1 end,
        ownedPuffs = function(jar)
          local seen, out = {}, {}
          for _, id in ipairs(jar) do if not seen[id] then seen[id] = true; out[#out + 1] = { id = id } end end
          return out
        end,
      },
      Decor = {
        CATALOG = { { id = "w1", kind = "wall" }, { id = "i1", kind = "cushion" }, { id = "t", kind = "thumb" } },
        ownedCount = function(decor) local n = 0; for _ in pairs(decor.owned) do n = n + 1 end; return n end,
      },
    }
  end
end

local function fresh(opts)
  opts = opts or {}
  local fw = nil
  if not opts.noFramework then fw = framework(opts) end
  local mod = fakeMod(fw)
  local trainingSave = { mons = {}, cleared = {}, meta = {} }
  local amieSave = { mons = {}, games = { berry = { unlocked = 1, best = {} }, head = { unlocked = 1, best = {} },
    tile = { unlocked = 1, best = {} } }, decor = { owned = {} }, room = { items = {} }, meta = { steps = 0 }, puffs = {} }
  local A = makeAch(mod, { data = data, training = trainingDeps(trainingSave), amie = amieDeps(amieSave), now = now })
  return A, fw, mod, trainingSave, amieSave
end

-- ------------------------------------------------------------ without the framework

do
  local A, _, mod = fresh({ noFramework = true })
  T.check(not A.install(), "no framework: install says so")
  A.note("bag_cleared"); A.note("regimen_end", { clear = true }, {}, false, false)
  T.check(not A.sweep(), "no framework: no sweep")
  A.tick()
  T.check(mod.saved.achievements == nil, "no framework: nothing is written to the save")
  T.eq(#mod.warnings, 0, "no framework: no warnings")
end

-- ------------------------------------------------------------ registration

do
  local A, fw, mod = fresh({ refused = { dance = true } })
  T.check(A.install(), "installs")
  T.eq(fw.registered.first_punch.title, "First Punch", "registered")
  T.check(fw.registered.dance == nil, "a refused row is not registered")
  T.check(#mod.warnings >= 1, "...and warned about")
  T.check(A.install(), "installing twice is harmless")
end

-- ------------------------------------------------------------ before the save is ready, then ready

do
  local A, fw, mod, ts, am = fresh()
  A.install()
  ts.mons.a = { hits = 1200, courses = { lv1_hp = { clears = 3 } } }
  ts.cleared = { lv1_hp = true, lv1_atk = true, lv1_def = true, lv1_spa = true, lv1_spd = true, lv1_spe = true }
  A.note("regimen_end", { clear = true, medal = true, newBest = true, firstClear = false }, { playerHits = 0, blocked = 2, bitsPopped = 5 }, true, true)
  T.check(not fw.unlocked.flawless, "no save yet: nothing awarded")
  T.check(mod.saved.achievements and mod.saved.achievements.flags.flawless, "...but the moment is kept")
  fw.ready()
  for _, id in ipairs({ "first_punch", "first_regimen", "lv1_grad", "flawless", "shield", "first_award",
      "new_best", "circuit", "stadium_3d" }) do
    T.check(fw.unlocked[id], "awarded on ready: " .. id)
  end
  T.eq(fw.progress.heavy_hitter, 1000, "progress is clamped to the goal")
  T.check(fw.unlocked.heavy_hitter, "...and reaching it awards it")
  T.eq(fw.progress.bit_buster, 5, "bitbots counted")
  T.eq(fw.progress.clears_30, 3, "regimen clears summed over the party")
  T.check(not fw.unlocked.lv2_grad and not fw.unlocked.regular_clear, "a level not cleared stays locked")
end

-- ------------------------------------------------------------ a stricter run: no award without the condition

do
  local A, fw = fresh()
  A.install(); fw.ready()
  A.note("regimen_end", { clear = true, firstClear = true, newBest = true }, { playerHits = 2, blocked = 0, bitsPopped = 0 }, false, false)
  T.check(not fw.unlocked.flawless, "hit twice: not flawless")
  T.check(not fw.unlocked.new_best, "the first clear is not a personal best")
  T.check(not fw.unlocked.stadium_3d and not fw.unlocked.circuit, "flat view, one balloon")
  A.note("regimen_end", { clear = false }, { playerHits = 0 }, false, false)
  T.check(not fw.unlocked.flawless, "a failed regimen is never flawless")
  A.note("goal_hit", { stage = 0 })
  T.check(not fw.unlocked.charged, "an uncharged hit")
  A.note("goal_hit", { stage = 1 })
  T.check(fw.unlocked.charged, "a charged hit")
end

-- ------------------------------------------------------------ throttled sweeps

do
  local A, fw, _, ts = fresh()
  A.install(); fw.ready()
  clock = 100
  ts.mons.a = { hits = 10 }
  A.note("punch")
  A.tick()
  T.check(fw.unlocked.first_punch, "the first sweep runs")
  local sets = fw.sets or 0
  ts.mons.a.hits = 20
  clock = 100.2
  A.note("punch"); A.tick()
  T.eq(fw.progress.heavy_hitter, 10, "within a second: held back")
  clock = 101.5
  A.tick()
  T.eq(fw.progress.heavy_hitter, 20, "after it: swept")
  A.tick(); A.tick()
  T.eq(fw.sets, (sets or 0) + 1, "an unchanged value is not sent again")
end

-- ------------------------------------------------------------ secret courses and Amie

do
  local A, fw, _, ts, am = fresh()
  A.install(); fw.ready()
  ts.cleared = { secret_02 = true, secret_03 = true, secret_04 = true, secret_11 = true }
  A.note("regimen_end", { clear = true }, {}, false, false)
  clock = 200; A.tick()
  T.check(fw.unlocked.first_secret and fw.unlocked.stone_cups and fw.unlocked.sudden_death, "secret regimens")
  T.check(not fw.unlocked.finale and not fw.unlocked.all_secret, "...the finale and the full set wait")

  am.mons.a = { puffsEaten = 150, affection = 255 }
  am.mons.b = { puffsEaten = 3, affection = 100 }
  am.games.berry.best = { hard = 3 }
  am.games.head.best = { easy = 5 }
  am.games.tile.unlocked = 4
  am.meta.steps = 4200
  am.puffs = { "puff/a", "puff/b", "puff/supreme_honor", "puff/a" }
  am.decor.owned = { w1 = true, i1 = true }
  am.room.items = { { id = "i1" } }
  A.note("game_finished", { game = "tile", diff = "hard", value = 55, stars = 4 })
  clock = 300; A.tick()
  for _, id in ipairs({ "first_puff", "fond", "best_friends", "berry_3", "five_star", "unlimited", "honor",
      "decor_all", "decor_first", "first_game", "puzzle_time" }) do
    T.check(fw.unlocked[id], "awarded: " .. id)
  end
  T.eq(fw.progress.well_fed, 100, "well fed capped at its goal")
  T.check(fw.unlocked.well_fed, "...and awarded")
  T.eq(fw.progress.walk, 4200, "steps")
  T.eq(fw.progress.puffs_10, 3, "three kinds of puff owned")
  T.check(not fw.unlocked.head_3 and not fw.unlocked.five_each, "Head It not at three stars on Hard, one game at five stars")
  A.note("game_finished", { game = "tile", diff = "hard", value = 90, stars = 2 })
  T.check(fw.unlocked.puzzle_time, "(already earned stays)")
end

do
  local A, fw = fresh()
  A.install(); fw.ready()
  A.note("game_finished", { game = "tile", diff = "hard", value = 95, stars = 3 })
  T.check(fw.unlocked.first_game and not fw.unlocked.puzzle_time, "too slow for Speed Solver")
  A.note("game_finished", { game = "tile", diff = "easy", value = 20, stars = 5 })
  T.check(not fw.unlocked.puzzle_time, "only Hard counts")
  A.note("combo", 99); T.check(not fw.unlocked.combo_100, "combo 99")
  A.note("combo", 100); T.check(fw.unlocked.combo_100, "combo 100")
  A.note("gift_claimed"); A.note("gift_claimed")
  A.note("puff_owned", "puff/x")
  clock = 400; A.tick()
  T.eq(fw.progress.visitors_10, 2, "gifts counted")
  T.check(fw.unlocked.visitor, "a gift")
  A.note("puff_owned", "puff/supreme_honor")
  T.check(fw.unlocked.honor, "the Supreme Honor puff")
  A.note("nonsense")
end

T.finish("play_nav achievements")
