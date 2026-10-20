-- Haptics (shared as mod.haptics): short vibrations for touches and play, at the HAPTICS
-- option's level (high / medium / low / off). love.system.vibrate takes a length and nothing
-- else (as the engine's own touch pad does it, src/core/TouchControls.lua): on Android the
-- vibrator runs that long, on iOS a length maps to a Taptic impact, on desktop it is a no-op.
-- So a pulse's strength is its length, and a pattern (two knocks for a bad touch, a run for a
-- big moment) is pulses timed from H.update.
--
--   H.pulse(kind)      one pulse: "tick" (a menu touch), "light", "medium", "strong"
--   H.pattern(name)    a timed run: "bad", "hurt", "happy", "success", "big"
--   H.onSound(name)    Amie's (and Super Training's stand-in) sound effects: menu presses tick,
--                      a good hit or placement medium, a success its pattern, a miss "bad"
--   H.update(dt)       the patterns' later pulses (main's tick)
--
-- Pulses closer than MIN_GAP to the last are dropped unless stronger, so a fast stream (the
-- berries counted at the end of Berry Picker) stays crisp instead of one long buzz.

return function(mod)
  local H = {}

  H.LEVELS = { off = 0, low = 0.6, medium = 1, high = 1.5 }
  H.SECONDS = { tick = 0.010, light = 0.016, medium = 0.026, strong = 0.042 }
  local RANK = { tick = 1, light = 2, medium = 3, strong = 4 }
  H.MIN_GAP = 0.045
  -- { kind, then the gap before the next, kind, ... }
  H.PATTERNS = {
    bad = { "medium", 0.09, "medium" },                       -- a disliked touch, a miss
    hurt = { "strong", 0.08, "light", 0.06, "light" },        -- a hit taken
    happy = { "light", 0.07, "medium" },                      -- a good petting reward
    success = { "medium", 0.08, "medium", 0.08, "strong" },   -- a cleared bag, a finished puzzle
    big = { "strong", 0.10, "strong" },                       -- a popped balloon, a gift
  }
  H.SOUNDS = {
    SE_SELECT = "tick", SE_PIN = "medium", SE_SUCCESS = "success", SE_NOT_EFFECTIVE = "bad",
    SE_FAILURE = "bad", SE_EXP = "medium",
  }

  local lastAt, lastRank = -1, 0
  local queue = {}      -- { at, kind }
  local clock = 0

  local function level()
    local v = mod.options and mod.options.get and mod.options:get("haptics")
    return H.LEVELS[v] or H.LEVELS.medium
  end

  -- the vibrator (tests and drivers swap it to count pulses)
  function H.vibrate(secs)
    if love and love.system and love.system.vibrate then pcall(love.system.vibrate, secs) end
  end

  function H.pulse(kind)
    local base = H.SECONDS[kind or "light"]
    local k = level()
    if not base or k <= 0 then return false end
    local rank = RANK[kind] or 2
    if clock - lastAt < H.MIN_GAP and rank <= lastRank then return false end
    lastAt, lastRank = clock, rank
    H.vibrate(base * k)
    if H.log then H.log[#H.log + 1] = kind end
    return true
  end

  function H.pattern(name)
    local p = H.PATTERNS[name]
    if not p then return H.pulse(name) end
    if level() <= 0 then return false end
    local at = clock
    for i = 1, #p, 2 do
      if i == 1 then
        lastAt, lastRank = -1, 0     -- a pattern starts fresh
        H.pulse(p[1])
      else
        queue[#queue + 1] = { at = at, kind = p[i] }
      end
      at = at + (p[i + 1] or 0)
    end
    return true
  end

  -- the next sound's own haptic is skipped (an event that has just played its own), if it comes
  -- in the same moment; a sound that never follows leaves nothing behind
  local skipUntil = -1
  function H.skipNextSound() skipUntil = clock end    -- this frame only (clock moves per frame)

  function H.onSound(name)
    if clock <= skipUntil then skipUntil = -1; return false end
    local what = H.SOUNDS[name]
    if not what then return false end
    if H.PATTERNS[what] then return H.pattern(what) end
    return H.pulse(what)
  end

  function H.update(dt)
    clock = clock + (dt or 0)
    for i = #queue, 1, -1 do
      local q = queue[i]
      if clock >= q.at then
        table.remove(queue, i)
        lastAt, lastRank = -1, 0     -- a pattern's own pulses are never merged away
        H.pulse(q.kind)
      end
    end
  end

  function H.level() return level() end

  return H
end
