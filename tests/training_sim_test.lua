-- The regimen simulation, headless and seeded: goals, shots, scoring, charge, guts,
-- attacks, hits and blocks, bits, barriers, circuits, the clock and determinism.
-- Run from the engine root: luajit mods/play_nav/tests/training_sim_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function loadFile(path, ...)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  return assert(load(src, "@" .. path))(...)
end

local N = loadFile("mods/play_nav/data/training_rules.lua")
local C = loadFile("mods/play_nav/data/training_courses.lua")
local Sim = loadFile("mods/play_nav/src/training/sim.lua")(N)

local function lcg(seed)
  local s = seed or 1
  return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end

local function make(id, opts)
  opts = opts or {}
  local course = C.byId[id]
  local sim = Sim.new(course, { anchors = C.anchors[course.goals.anchors], library = C.attacks,
    shotType = opts.shotType or "black", mods = opts.mods, level = course.level, shapes = opts.shapes }, opts.rng or lcg(7))
  return sim, course
end

-- run `secs` of play at 60 fps, collecting events by kind
local function run(sim, secs, onEvent)
  local counts = {}
  for _ = 1, math.floor(secs * 60 + 0.5) do
    for _, e in ipairs(sim:update(1 / 60)) do
      counts[e.kind] = (counts[e.kind] or 0) + 1
      if onEvent then onEvent(e) end
    end
  end
  return counts
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- ------- projection and the pad

do
  local V = N.VIEW
  local x, y, k = Sim.project(0, 0, 0)
  T.check(near(x, 120) and near(y, V.NEAR.fy) and near(k, 1), "the near plane's floor centre is (120, NEAR.fy)")
  x, y = Sim.project(0, 0, 1)
  T.check(near(x, 120) and near(y, V.FAR.fy), "the far plane's floor centre is (120, FAR.fy)")
  x = Sim.project(1, 0, 1)
  T.check(near(x, 120 + V.FAR.hw), "the far plane is FAR.hw px wide each side")
  local ux, uy = Sim.unproject(Sim.project(0.4, 0.9, 1))
  T.check(near(ux, 0.4) and near(uy, 0.9), "a screen point goes back onto the balloon's plane")
  local pad = { cx = 128, cy = 88, r = 70 }
  local tx, ty = Sim.aimFromPad(128, 88, pad)
  T.check(near(tx, 0) and near(ty, 0.5), "the pad centre aims at the bot's middle")
  tx, ty = Sim.aimFromPad(128 + 70, 88 - 70, pad)
  T.check(near(tx, 1) and near(ty, 1), "the pad's top right aims top right")
  local px, py = Sim.padFromAim(0.3, 0.7, pad)
  local bx, by = Sim.aimFromPad(px, py, pad)
  T.check(near(bx, 0.3) and near(by, 0.7), "padFromAim inverts aimFromPad")
end

-- ------- every course validates

do
  local bad = {}
  for _, c in ipairs(C.courses) do
    local ok, err = Sim.validate(c, C)
    if not ok then bad[#bad + 1] = err end
  end
  T.eq(#bad, 0, "all 30 courses validate (" .. table.concat(bad, "; ") .. ")")
  local ok, err = Sim.validate({ id = "x", bots = {}, goals = {} }, C)
  T.check(not ok and err:find("no bots"), "a course without bots is refused")
end

-- ------- countdown, goals, a hit

do
  local sim = make("lv1_hp")
  T.eq(sim.phase, "countdown", "starts in the countdown")
  local ev = run(sim, 3.1)
  T.eq(sim.phase, "play", "play after 3 s")
  T.eq(ev.play, 1, "...one play event")
  T.eq(#sim.goals, 2, "Wailmer shows two goals")
  T.eq(sim.goals[1].kind, "white", "...white")
  local st = sim:state()
  T.eq(st.target, 500, "the target is 500")
  T.check(near(st.remaining, 180, 0.2), "the clock starts at 3:00 when play starts")
  -- aim at the first goal and fire a plain shot
  local g = st.goals[1]
  sim:aim(g.x, g.y)
  sim:pressFire()
  sim:update(1 / 60)
  sim:releaseFire()
  local hit
  run(sim, 1.5, function(e) if e.kind == "goal_hit" then hit = e end end)
  T.check(hit ~= nil, "the shot scores")
  T.eq(hit and hit.points, 20, "...20 points on Lv1")
  T.eq(sim.score, 20, "score 20")
  T.eq(#sim.goals, 1, "the goal is gone")
  T.check(sim.bot.scale > 1, "the balloon grew")
  T.check(sim.stats.shots == 1 and sim.stats.hits == 1, "stats count the shot and the hit")
end

-- ------- yellow at 8 s, gone at 12 s, the next group

do
  local sim = make("lv1_hp")
  run(sim, 3.1)
  local ev = run(sim, 8.05)
  T.eq(ev.goal_yellow, 2, "both goals turned yellow at 8 s")
  T.eq(sim.goals[1].kind, "fading", "...fading now")
  ev = run(sim, 4.1)
  T.eq(ev.goal_expired, 2, "...and expired at 12 s")
  ev = run(sim, N.GOALS.GROUP_GAP_S + 0.1)
  T.eq(ev.goals_spawned, 1, "a new group follows")
  T.eq(#sim.goals, 2, "two goals again")
end

-- ------- the chance goal

do
  local sim = make("lv2_hp", { rng = function() return 0 end })   -- Relicanth: odds 1.0
  run(sim, 3.1)
  T.eq(#sim.goals, 3, "three goals")
  -- fire at whatever white goal is up until the group is gone (the balloon sways: a shot can miss)
  local function hitAll()
    for _ = 1, 12 do
      local target
      for _, g in ipairs(sim:state().goals) do
        if g.kind == "white" or g.kind == "fading" then target = g; break end
      end
      if not target then return end
      sim:aim(target.x, target.y); sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
      run(sim, 1.2)
    end
  end
  -- the red goal comes after every second cleared group (measured in the game)
  hitAll()
  local ev = run(sim, 0.2)
  local chance
  for _, g in ipairs(sim.goals) do if g.kind == "chance" then chance = g end end
  T.check(chance == nil, "the first cleared group brings no red goal")
  run(sim, N.GOALS.GROUP_GAP_S + 0.1)
  T.eq(#sim.goals, 3, "the next group of three")
  hitAll()
  ev = run(sim, 0.2)
  for _, g in ipairs(sim.goals) do if g.kind == "chance" then chance = g end end
  T.check(chance ~= nil, "clearing the second group brings the red Chance Goal")
  -- (the course's attacks may cost points meanwhile: count the red goal's own hits)
  local scored = 0
  for _ = 1, 3 do
    local cg
    for _, g in ipairs(sim:state().goals) do if g.kind == "chance" then cg = g end end
    if cg then sim:aim(cg.x, cg.y); sim:pressFire(); sim:update(1 / 60); sim:releaseFire() end
    run(sim, 1.0, function(e) if e.kind == "goal_hit" and e.goal == "chance" then scored = scored + (e.points or 0) end end)
  end
  T.check(scored > 0, "it scores again and again (" .. scored .. ")")
  T.check(#sim.goals >= 1 and sim.goals[#sim.goals].kind == "chance" or chance.hits >= 3, "it stays while you score")
  ev = run(sim, N.GOALS.CHANCE_S + 0.5)
  T.eq(ev.chance_expired, 1, "...and leaves after CHANCE_S without a score")
end

-- ------- the balls: sized by level and capped; lobbed balls come down where the trainee stood

do
  local B = N.ATTACK.BALL
  for _, id in ipairs({ "lv1_hp", "lv2_hp", "lv3_hp" }) do
    local sim = make(id)
    run(sim, 3.1)
    sim:launch({ kind = "big" })
    run(sim, 0.05)
    local cap = B.CAP[sim.level] * B.SPRITE_R
    local ball = sim.balls[1]
    T.check(ball and ball.r <= cap + 1e-9, ("%s: a big ball's radius %.3f stays within the cap %.3f"):format(id, ball and ball.r or -1, cap))
  end
  local s1, s3 = make("lv1_hp"), make("lv3_hp")
  run(s1, 3.1); run(s3, 3.1)
  s1:launch({ kind = "big" }); s3:launch({ kind = "big" })
  run(s1, 0.05); run(s3, 0.05)
  T.check(s3.balls[1].r > s1.balls[1].r, "Lv3's balls are bigger than Lv1's")

  -- a lob on a trainee that stays put lands on it; one that moves off the spot is missed
  local function lobAt(move)
    local sim = make("lv2_spa")
    run(sim, 3.1)
    sim.balls, sim.spawnQueue = {}, {}
    sim.schedule = {}
    sim.player.x = 0
    sim:launch({ kind = "lob" })
    local hit = false
    local peakY = 0
    sim:setMove(move, 0)
    run(sim, N.ATTACK.lob.flight + 0.6, function(e) if e.kind == "player_hit" then hit = true end end)
    sim:setMove(0, 0)
    return hit
  end
  T.check(lobAt(0), "a lobbed ball comes down on a trainee that stays put")
  T.check(not lobAt(1), "...and misses one that moves off the spot")
  local sim = make("lv2_spa")
  run(sim, 3.1)
  sim:launch({ kind = "lob" })
  run(sim, 0.05)
  local top = math.huge
  for _ = 1, 60 do
    run(sim, 1 / 60)
    for _, b in ipairs(sim.balls) do
      if b.kind == "lob" then local _, sy = Sim.project(b.x, b.y, b.z); top = math.min(top, sy) end
    end
  end
  T.check(top < 0, ("it goes up off the top of the screen (y %.0f)"):format(top))
end

-- ------- charge: stage 3 is 3x, overcharging stuns

do
  local sim = make("lv1_hp")
  run(sim, 3.1)
  local g = sim:state().goals[1]
  sim:aim(g.x, g.y)
  sim:pressFire()
  run(sim, N.CHARGE.STAGE_S[3] + 0.05)
  T.eq(sim:chargeStage(), 3, "stage 3 after holding")
  g = sim:state().goals[1]
  sim:aim(g.x, g.y)
  sim:releaseFire()
  local hit
  run(sim, 1.5, function(e) if e.kind == "goal_hit" then hit = e end end)
  T.eq(hit and hit.points, 60, "a max charge scores 3x (60)")
  sim:pressFire()
  local ev = run(sim, N.CHARGE.OVER_S + 0.1)
  T.eq(ev.overcharge, 1, "holding too long breaks the charge")
  T.check(sim.player.stun > 0, "...and stuns")
  T.eq(ev.shot_fired, nil, "...with no shot")
end

-- ------- guts: shooting empties it, a dry shot is weak

do
  local sim = make("lv1_hp", { shotType = "green" })
  run(sim, 3.1)
  sim:aim(0, 0.45)
  local weak = 0
  for _ = 1, 4 do
    sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
    for _, e in ipairs(sim:update(1 / 60)) do if e.kind == "weak_shot" then weak = weak + 1 end end
  end
  T.check(sim.guts < 0.3, "green shots drain the circle (" .. string.format("%.2f", sim.guts) .. ")")
  T.check(weak >= 1, "the dry shot is a weak black ball")
  local g0 = sim.guts
  run(sim, 2)
  T.check(sim.guts > g0, "it refills with time")
end

-- ------- yellow: holding only charges (no stream), a max charge bursts seven

do
  local sim = make("lv1_hp", { shotType = N.SHOT.RAPID })
  run(sim, 3.1)
  sim:aim(0, 0.45)
  sim:pressFire()
  local ev = run(sim, 1.0)
  T.eq((ev.shot_fired or 0) + (ev.weak_shot or 0), 0, "holding fires nothing until it is let go")
  run(sim, N.CHARGE.STAGE_S[3] - 1.0 + 0.05)
  sim:releaseFire()
  T.eq(sim.player.burst, 7, "a max-charge release bursts seven")
  ev = run(sim, 1.5)
  T.eq(sim.player.burst, 0, "...all fired")
end

-- ------- attacks: telegraph then launch, a hit costs points, a block saves them

do
  local sim = make("lv1_hp")
  run(sim, 3.1)
  sim.score = 300
  local tele, launch
  run(sim, 11.5, function(e)
    if e.kind == "attack_telegraph" and not tele then tele = e.t end
    if e.kind == "attack_launch" and not launch then launch = e.t end
  end)
  T.check(tele ~= nil and launch ~= nil, "the first attack is telegraphed then launched")
  T.check(launch and tele and near(launch - tele, N.ATTACK.TELEGRAPH_S, 0.02), "...one second apart")
  -- the player stands still: the big ball lands
  local hit
  run(sim, 2.5, function(e) if e.kind == "player_hit" then hit = e end end)
  T.check(hit ~= nil, "standing still gets hit")
  T.eq(hit and hit.loss, N.DAMAGE.big, "a big ball costs 150")
  T.eq(sim.score, 150, "score 300 -> 150")
  T.eq(sim.stats.playerHits, 1, "...one hit on record")
  -- the next one: wait until a ball is close, then block
  local blocked
  for _ = 1, 60 * 30 do
    local close = false
    for _, b in ipairs(sim.balls) do if b.z < 0.35 then close = true end end
    if close then break end
    sim:update(1 / 60)
  end
  T.check(sim:block(), "the shield goes up")
  run(sim, 1.0, function(e) if e.kind == "blocked" then blocked = e end end)
  T.check(blocked ~= nil, "the ball is blocked")
  T.eq(sim.score, 150, "...no points lost")
  T.check(not sim:block(), "the shield has a cooldown")
end

-- ------- moving away dodges

do
  local sim = make("lv1_hp")
  run(sim, 3.1)
  sim.score = 300
  -- step until the first ball flies, then run to the right
  for _ = 1, 60 * 15 do
    local launched = false
    for _, e in ipairs(sim:update(1 / 60)) do if e.kind == "attack_launch" then launched = true end end
    if launched then break end
  end
  sim:setMove(1, 0)
  local hits = 0
  run(sim, 3, function(e) if e.kind == "player_hit" then hits = hits + 1 end end)
  T.eq(hits, 0, "a ball aimed at the launch position misses a player who moved")
  T.check(near(sim.player.x, N.PLAYER.X_MAX, 0.01), "...who is pinned at the right edge")
end

-- ------- sudden death

do
  local sim = make("secret_11")
  run(sim, 3.1)
  sim.score = 1000
  local hit
  run(sim, 8, function(e) if e.kind == "player_hit" then hit = e end end)
  T.check(hit ~= nil and sim.score == 0, "Hydreigon's course: one hit, zero points")
end

-- ------- bits and the barrier

do
  local sim = make("lv2_spd")   -- Tentacruel: bits at 4 s
  run(sim, 3.1)
  local ev = run(sim, 6)
  T.eq(ev.bits_spawned, 1, "the bit balloons arrive")
  T.eq(#sim.bits, 2, "two of them")
  -- shoot one down: aim at its spot on the bot plane through its position
  local bit = sim.bits[1]
  local p = sim.player
  local f = (1 - p.z) / (bit.z - p.z)
  sim:aim(p.x + (bit.x - p.x) * f, 0.15 + (bit.y - 0.15) * f)
  local pops = 0
  for _ = 1, 6 do
    sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
    run(sim, 0.9, function(e) if e.kind == "bit_pop" then pops = pops + 1 end end)
  end
  T.check(pops >= 1, "shots pop a bit (" .. pops .. ")")
  local sim2 = make("lv2_def")   -- Graveler: barrier at 5 s
  run(sim2, 3.1)
  ev = run(sim2, 6.2)
  T.eq(ev.barrier_up, 1, "Graveler raises its block")
  T.check(sim2.barrier ~= nil, "...it is up")
  local marker
  for _, g in ipairs(sim2:state().goals) do if g.kind == "marker" then marker = g end end
  T.check(marker ~= nil, "a marker shows where to hit")
  local white
  for _, g in ipairs(sim2:state().goals) do if g.kind == "white" then white = g end end
  sim2:aim(white.x, white.y); sim2:pressFire(); sim2:update(1 / 60); sim2:releaseFire()
  ev = run(sim2, 1.2)
  T.eq(ev.shot_absorbed, 1, "a goal shot is absorbed while the barrier stands")
  sim2:aim(marker.x, marker.y); sim2:pressFire(); sim2:update(1 / 60); sim2:releaseFire()
  ev = run(sim2, 1.2)
  T.eq(ev.barrier_down, 1, "hitting the marker drops it")
  T.eq(sim2.barrier, nil, "...gone")
end

-- ------- popping the bot, circuits, the clock

do
  local sim = make("lv1_hp")
  run(sim, 3.1)
  sim.score = 499
  local g = sim:state().goals[1]
  sim:aim(g.x, g.y); sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
  local clear
  run(sim, 1.5, function(e) if e.kind == "clear" then clear = e end end)
  T.check(clear ~= nil, "500 points pop Wailmer and clear the course")
  T.eq(sim.phase, "clear", "phase clear")
  T.check(clear and clear.remaining > 170, "with most of the clock left")
  -- a circuit: the first pop adds 30 s and brings the next bot
  local circ = make("secret_01")
  run(circ, 3.1)
  local r0 = circ.remaining
  circ.score = 1799
  g = circ:state().goals[1]
  circ:aim(g.x, g.y); circ:pressFire(); circ:update(1 / 60); circ:releaseFire()
  local pop
  run(circ, 1.5, function(e) if e.kind == "bot_pop" then pop = e end end)
  T.check(pop ~= nil, "the first bot pops")
  T.eq(circ.phase, "play", "...play goes on")
  T.eq(circ.botIndex, 2, "...against the second bot")
  T.check(circ.remaining > r0 + 25, "...with 30 s added")
  T.eq(circ.score, 0, "...score reset for the new bot")
  -- time out
  local slow = make("lv1_spe")
  run(slow, 3.1)
  local ev = run(slow, 181)
  T.eq(ev.timeout, 1, "the clock runs out at 3:00")
  T.eq(slow.phase, "timeout", "phase timeout")
  -- forceEnd
  local f = make("lv1_hp")
  run(f, 3.1)
  T.check(f:forceEnd({ clear = true, remaining = 160 }), "forceEnd clears")
  local last = f:update(0)
  T.check(last[#last] and last[#last].kind == "clear" and last[#last].remaining == 160, "...with the remaining time asked")
end

-- ------- the energy meter: a full meter fires the species' Energy Shot, then plain balls

do
  local sim = make("lv1_hp", { shotType = "green" })
  run(sim, 3.1)
  sim:aim(0, 0.45)
  local kinds = {}
  for _ = 1, 3 do
    sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
    for _, e in ipairs(sim:update(1 / 60)) do if e.kind == "shot_fired" or e.kind == "weak_shot" then kinds[#kinds + 1] = e.type end end
  end
  T.eq(kinds[1], "green", "the first shot, meter full: the Energy Shot")
  T.check(kinds[2] == "black" or kinds[2] == "weak", "the second, meter down: a plain ball (" .. tostring(kinds[2]) .. ")")
  T.check(sim.shots[1].points > sim.shots[2].points, "...worth less")
  run(sim, 1 / N.GUTS.RATE + 0.1)
  T.check(sim:state().energy, "the meter refills to full")
  sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
  local last
  for _, e in ipairs(sim:update(1 / 60)) do if e.kind == "shot_fired" then last = e end end
  T.check(last and last.energy == true and last.type == "green", "...and the next shot is an Energy Shot again")
  T.eq(sim.stats.energyShots, 2, "two Energy Shots counted")
end

-- ------- bits regenerate, Aerodactyl bobs, Probopass's goals roam, levels hit harder

do
  local sim = make("lv2_spd")
  run(sim, 3.1 + 6)
  local bit = sim.bits[1]
  local p = sim.player
  local f = (1 - p.z) / (bit.z - p.z)
  sim:aim(p.x + (bit.x - p.x) * f, 0.15 + (bit.y - 0.15) * f)
  local popped = false
  for _ = 1, 8 do
    sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
    run(sim, 0.9, function(e) if e.kind == "bit_pop" then popped = true end end)
    if popped then break end
  end
  T.check(popped, "a bit pops")
  T.eq(sim:state().liveBits, 1, "...and lies dead, still counted")
  local ev = run(sim, N.ATTACK.bit.regen_s + 0.5)
  T.eq(ev.bit_regen, 1, "it regenerates after its time")
  T.eq(sim:state().liveBits, 2, "...both live again")

  local aero = make("lv2_spe")
  run(aero, 3.1)
  local _, y0 = aero:botOffset()
  run(aero, 0.55)
  local _, y1 = aero:botOffset()
  T.check(math.abs(y1 - y0) > 0.01, "Aerodactyl's balloon rises and falls")
  local still = make("lv1_hp")
  local _, ys = still:botOffset()
  T.eq(ys, 0, "Wailmer's stays put")

  local probo = make("secret_10")
  run(probo, 3.1)
  local g0 = probo:state().goals[1]
  run(probo, 0.7)
  local g1 = probo:state().goals[1]
  T.check(g0 and g1 and (math.abs(g1.x - g0.x) > 0.005 or math.abs(g1.y - g0.y) > 0.005), "Probopass's goals keep moving")

  local lv3 = make("lv3_hp")
  run(lv3, 3.1)
  lv3.score = 1000
  lv3:playerHit({ kind = "big" })
  T.eq(lv3.score, 1000 - N.DAMAGE.big * N.DAMAGE.LEVEL_MULT[3], "a Lv3 hit costs the level multiple")
end

-- ------- Aegislash rages past 2400: faster, stronger shots

do
  local sim = make("secret_06")
  run(sim, 3.1)
  sim.score = 2400
  run(sim, 0.1)
  T.eq(sim.bot.mood, "rage", "rage mode")
  sim:launch({ kind = "big" })
  sim:update(1 / 60)
  local calm = make("secret_06")
  run(calm, 3.1)
  calm:launch({ kind = "big" })
  calm:update(1 / 60)
  T.check(math.abs(sim.balls[1].vz) > math.abs(calm.balls[1].vz), "its balls fly faster")
  sim.score = 2400
  sim:playerHit({ kind = "big" })
  T.eq(sim.score, 2400 - math.floor(N.DAMAGE.big * N.DAMAGE.LEVEL_MULT.secret * N.BOT.RAGE_DAMAGE + 0.5), "...and hit harder")
end


-- ------- goals on the balloon's sprite: they start on it, walk over it, never leave it

do
  local Draw = loadFile("mods/play_nav/src/training/arena_draw.lua")({ options = { get = function() return nil end } },
    { host = {}, Rules = { N = N }, Sim = Sim })
  -- a 64x64 "sprite": a big body, a separate head joined by a 3-px neck, two thin arms
  local W, H = 64, 64
  local mask = {}
  for y = 0, H - 1 do
    mask[y] = {}
    for x = 0, W - 1 do
      local body = (x - 32) ^ 2 + (y - 44) ^ 2 <= 15 ^ 2
      local head = (x - 32) ^ 2 + (y - 14) ^ 2 <= 9 ^ 2
      local neck = x >= 31 and x <= 33 and y >= 20 and y <= 30
      local arm = y >= 40 and y <= 43 and ((x >= 4 and x < 18) or (x > 46 and x <= 60))
      mask[y][x] = body or head or neck or arm
    end
  end
  local shape = Draw.shapeFromMask(mask, W, H)
  T.check(shape ~= nil and #shape.list > 20, "a shape comes out of the mask (" .. (shape and #shape.list or 0) .. " cells)")

  -- a bot-local point back to its sprite pixel
  local function pixelOf(lx, ly)
    return math.floor(shape.cx + lx * shape.ppr), math.floor(shape.cy - ly * shape.ppr)
  end
  for _, c in ipairs(shape.list) do
    local px, py = pixelOf((c[1] + 0.5) * shape.cell, (c[2] + 0.5) * shape.cell)
    if not mask[py][px] then T.check(false, "a cell off the sprite at " .. px .. "," .. py) end
  end
  T.check(true, "every cell is on the sprite")

  for _, id in ipairs({ "lv1_hp", "lv3_spd", "secret_04", "secret_05", "secret_10" }) do
    local course = C.byId[id]
    local sim = make(id, { shapes = { shape, shape, shape, shape } })
    local off, moved, samples = 0, 0, 0
    local first = {}
    for _ = 1, 60 * 40 do
      sim:update(1 / 60)
      for k, g in ipairs(sim.goals) do
        if g.ci then
          samples = samples + 1
          local px, py = pixelOf(g.lx, g.ly)
          if not (mask[py] and mask[py][px]) then off = off + 1 end
          if not Sim.walkable(shape, g.ci, g.cj) then off = off + 1 end
          first[g] = first[g] or { g.lx, g.ly }
          if math.abs(first[g][1] - g.lx) + math.abs(first[g][2] - g.ly) > shape.cell then moved = moved + 1 end
        end
      end
    end
    T.check(samples > 100, id .. ": goals were on the shape (" .. samples .. " samples)")
    T.eq(off, 0, id .. ": no goal ever stood off the sprite")
    -- the game's goals stay where they appear (measured); the fleeing / roaming ones travel
    if course.fleeing or course.roaming then
      T.check(moved > 0, id .. ": its goals travel over it")
    else
      T.eq(moved, 0, id .. ": goals stay where they appear")
    end
    if course.fleeing or course.roaming then T.check(true, id .. ": a fleeing / roaming course stays on it too") end
  end

  -- a goal's world position is where the sprite is drawn: x by R, y by R * ASPECT
  local sim = make("lv1_hp", { shapes = { shape } })
  run(sim, 3.2)
  local g = sim.goals[1]
  local gx, gy = sim:goalPos(g)
  local R = N.BOT.R * sim.bot.scale
  local bx, by = sim:botOffset()
  T.check(math.abs(gx - (g.lx * R + bx)) < 1e-9, "x follows the sprite (and the balloon's sway)")
  T.check(math.abs(gy - (N.BOT.SHAPE_CY + g.ly * R * Sim.ASPECT + by)) < 1e-9, "y is stretched to the screen's aspect")

  -- every cell of the shape, fully grown, is inside the aim's reach (so on the pad and hittable)
  do
    local ex, ey = sim:aimExtent()
    local Rmax = N.BOT.R * N.BOT.SCALE_MAX
    local bad = 0
    for _, c in ipairs(shape.list) do
      local lx, ly = (c[1] + 0.5) * shape.cell, (c[2] + 0.5) * shape.cell
      local wx, wy = lx * Rmax, N.BOT.SHAPE_CY + ly * Rmax * Sim.ASPECT
      if math.abs(wx) > ex or wy < 0 or wy > ey then bad = bad + 1 end
    end
    T.eq(bad, 0, "the whole sprite, fully grown, is within the aim's reach")
    local pad = { cx = 112, cy = 88, r = 70 }
    local px, py = Sim.padFromAim(1.2, 1.8, pad, ex, ey)
    local ax, ay = Sim.aimFromPad(px, py, pad, ex, ey)
    T.check(near(ax, 1.2) and near(ay, 1.8), "the pad's mapping inverts at the larger reach")
    sim:aim(5, 5)
    T.check(near(sim.player.aim.x, ex) and near(sim.player.aim.y, ey), "aim clamps to the reach")
  end

  -- no shape (a species with no sprite): the old anchors
  local plain = make("lv1_hp")
  run(plain, 3.2)
  T.eq(plain.goals[1].ci, nil, "without a sprite, goals keep their anchors")
end


-- ------- the player's Pokemon hops and squishes as it moves (drawing only)

do
  local Draw = loadFile("mods/play_nav/src/training/arena_draw.lua")({ options = { get = function() return nil end } },
    { host = {}, Rules = { N = N }, Sim = Sim })
  local sim = make("lv1_hp")
  run(sim, 3.2)
  local lift, sx, sy, lean = Draw.hopPose(sim)
  T.eq(lift, 0, "standing still: no hop")
  T.check(sx == 1 and sy == 1 and lean == 0, "...no squash, no lean")
  sim:setMove(1, 0)
  local maxLift, squashed, stretched, x0 = 0, false, false, sim.player.x
  for _ = 1, 30 do   -- half a second: short of the arena's edge, where it would stop
    sim:update(1 / 60)
    local l, a, b, ln = Draw.hopPose(sim)
    maxLift = math.max(maxLift, l)
    if a > 1.02 and b < 0.98 then squashed = true end
    if b > 1.01 and a < 0.99 then stretched = true end
    lean = ln
  end
  T.check(sim.player.x > x0, "the Pokemon moved")
  T.check(maxLift > Draw.HOP.HEIGHT * 0.5, "it hops while moving (" .. maxLift .. ")")
  T.check(squashed, "...squashes on landing")
  T.check(stretched, "...stretches in the air")
  T.check(lean > 0, "...leans into the direction")
  sim:setMove(0, 0)
  local landed = false
  for _ = 1, 6 do
    sim:update(1 / 60)
    local _, a, b = Draw.hopPose(sim)
    if a > 1.02 and b < 0.98 then landed = true end
  end
  T.check(landed, "stopping: a last squash")
  for _ = 1, 60 do sim:update(1 / 60); Draw.hopPose(sim) end
  lift, sx, sy = Draw.hopPose(sim)
  T.check(lift < 0.05 and math.abs(sx - 1) < 0.01 and math.abs(sy - 1) < 0.01, "...then it settles")
  sim:setMove(-1, 0)
  for _ = 1, 10 do sim:update(1 / 60); Draw.hopPose(sim) end
  local _, _, _, _, face = Draw.hopPose(sim)
  T.eq(face, -1, "moving left, it faces left")
  sim:setMove(0, 0)
end

-- ------- modifiers reach the sim

do
  local base = make("lv1_hp")
  run(base, 3.1)
  local strong = make("lv1_hp", { mods = { pointMult = 2, shotSize = 1, lossMult = 0.5, gutsRate = 1, blockLen = 1, moveMult = 1, ballSpeedMult = 1 } })
  run(strong, 3.1)
  local function firstHit(sim)
    local g = sim:state().goals[1]
    sim:aim(g.x, g.y); sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
    local hit
    run(sim, 1.5, function(e) if e.kind == "goal_hit" then hit = e end end)
    return hit and hit.points
  end
  T.eq(firstHit(base), 20, "plain: 20")
  T.eq(firstHit(strong), 40, "pointMult 2: 40")
end

-- ------- determinism

do
  local function script(seed)
    local sim = make("lv2_atk", { rng = lcg(seed) })
    local log = {}
    for i = 1, 60 * 30 do
      if i % 90 == 0 then
        local g = sim:state().goals[1]
        if g then sim:aim(g.x, g.y); sim:pressFire() end
      elseif i % 90 == 20 then
        sim:releaseFire()
      elseif i % 200 == 0 then
        sim:setMove(i % 400 == 0 and 1 or -1, 0)
      end
      for _, e in ipairs(sim:update(1 / 60)) do log[#log + 1] = e.kind .. ":" .. tostring(e.points or e.loss or "") end
    end
    return table.concat(log, ","), sim.score
  end
  local a, sa = script(99)
  local b, sb = script(99)
  T.check(a == b and sa == sb, "the same seed and inputs replay the same events")
  T.check(#a > 20, "...and there were events (" .. #a .. " chars)")
end

T.finish()
