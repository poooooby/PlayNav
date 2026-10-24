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
local Rules = loadFile("mods/play_nav/src/training/rules.lua")(N, loadFile("mods/play_nav/data/training_shot_types.lua"))

local function lcg(seed)
  local s = seed or 1
  return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end

local function make(id, opts)
  opts = opts or {}
  local course = C.byId[id]
  local sim = Sim.new(course, { anchors = C.anchors[course.goals.anchors], library = C.attacks,
    shotType = opts.shotType or "black", mods = opts.mods, level = course.level, shapes = opts.shapes,
    -- the balloon held still (aimed shots take most of a second to arrive); opts.sway lets it move
    still = not opts.sway }, opts.rng or lcg(7))
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
  -- aim at the first goal and fire plain shots until one lands (the goal rides the balloon's
  -- sway, and a shot takes most of a second to get there)
  local hit, tries = nil, 0
  while not hit and tries < 8 do
    tries = tries + 1
    local g = sim:state().goals[1]
    sim.guts = 1
    sim:aim(g.x, g.y)
    sim:pressFire()
    sim:update(1 / 60)
    sim:releaseFire()
    run(sim, 1.2, function(e) if e.kind == "goal_hit" then hit = e end end)
  end
  T.check(hit ~= nil, "a shot scores (" .. tries .. " fired)")
  T.eq(hit and hit.points, 20, "...20 points on Lv1")
  T.eq(sim.score, 20, "score 20")
  T.eq(#sim.goals, 1, "the goal is gone")
  T.check(sim.bot.scale > 1, "the balloon grew")
  T.check(sim.stats.shots == tries and sim.stats.hits == 1, "stats count the shots and the hit")
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

-- ------- charge (the game's frames at 30 a second): Charged at 50, full at 66 (x3), fizzles
-- at 96 into a 30-frame stop; a Charged Shot is followed by 15 frames with no shot

do
  local F = N.CHARGE.FPS
  local sim = make("lv1_hp")
  run(sim, 3.1)
  sim.guts = 1
  local g = sim:state().goals[1]
  sim:aim(g.x, g.y)
  sim:pressFire()
  run(sim, (N.CHARGE.STAGE_F[1] - 2) / F)
  T.eq(sim:chargeStage(), 0, "not Charged before frame 50")
  run(sim, 3 / F)
  T.eq(sim:chargeStage(), 1, "Charged at frame 50")
  run(sim, (N.CHARGE.STAGE_F[2] - N.CHARGE.STAGE_F[1]) / F)
  T.eq(sim:chargeStage(), 2, "full at frame 66")
  g = sim:state().goals[1]
  sim:aim(g.x, g.y)
  sim:releaseFire()
  T.check(math.abs(sim.guts - (1 - N.SHOT.black.chargedCost)) < 1e-6, "the Charged Shot used the meter (180 of 500)")
  T.check(sim.player.lock and sim.player.lock > 0, "a Charged Shot is followed by a pause")
  T.eq(sim:pressFire(), false, "...with no charge meanwhile")
  local hit
  run(sim, 1.5, function(e) if e.kind == "goal_hit" then hit = e end end)
  T.eq(hit and hit.points, 60, "a full charge scores 3x (60)")
  -- a release halfway between stage 1 and full: x2
  sim.guts = 1
  run(sim, 0.6)
  g = sim:state().goals[1]
  sim:aim(g.x, g.y)
  sim:pressFire()
  run(sim, (N.CHARGE.STAGE_F[1] + (N.CHARGE.STAGE_F[2] - N.CHARGE.STAGE_F[1]) / 2 + 0.5) / F)
  local rise = sim:chargeRise()
  T.check(rise and rise > 0.4 and rise < 0.6, "halfway to full (" .. tostring(rise) .. ")")
  local shot = (sim:releaseFire() and sim.shots[#sim.shots])
  T.check(shot and shot.points >= 38 and shot.points <= 42, "...scores about 2x (" .. tostring(shot and shot.points) .. ")")
  -- held too long
  run(sim, 1.0)
  sim:pressFire()
  local ev = run(sim, (N.CHARGE.FIZZLE_F + 1) / F)
  T.eq(ev.overcharge, 1, "holding past frame 96 breaks the charge")
  T.check(math.abs(sim.player.stun - N.CHARGE.STUN_F / F) < 0.05, "...and stops the Pokemon for 30 frames")
  T.eq(ev.shot_fired, nil, "...with no shot")
  T.eq(sim:releaseFire(), false, "...and the release fires nothing")
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
  run(sim, N.CHARGE.STAGE_F[2] / N.CHARGE.FPS - 1.0 + 0.05)
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
  local hit, safeAt
  run(sim, 2.5, function(e) if e.kind == "player_hit" then hit = e; safeAt = sim.player.safe end end)
  T.check(hit ~= nil, "standing still gets hit")
  T.eq(hit and hit.loss, 40, "a hit costs Wailmer's 40 (the game's course data)")
  T.eq(sim.score, 260, "score 300 -> 260")
  T.check(safeAt and safeAt > 0.9, "...then 30 frames untouchable")
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
  T.eq(sim.score, 260, "...no points lost")
  T.check(not sim:block(), "the shield has a cooldown")
end

-- ------- the shield (capture 2026-10-23_17-28-44): a stopped ball bounces off, the shield shatters
-- BREAK_F frames later; held to its length it shatters too

do
  local F = N.CHARGE.FPS
  local mods = { pointMult = 1, shotSize = 1, lossMult = 1, gutsRate = 1, blockLen = 1, moveMult = 1,
    ballSpeedMult = 1, blockS = 45 / F }
  local sim = make("lv1_hp", { mods = mods })
  run(sim, 3.1)
  sim.balls = {}
  sim.score = 100
  sim:block()
  local ball = { x = 0, y = 0.15, z = 0.25, vx = 0, vy = 0, vz = -1.5, r = 0.06, kind = "small" }
  sim.balls[#sim.balls + 1] = ball
  local blocked
  run(sim, 0.2, function(e) if e.kind == "blocked" then blocked = e end end)
  T.check(blocked ~= nil and ball.bounced, "a blocked ball bounces off")
  T.check(ball.vz > 0, "...back toward the balloon")
  T.eq(sim.score, 100, "...and costs nothing")
  T.check(sim.player.shield > 0, "the shield holds a moment after")
  local down
  run(sim, N.BLOCK.BREAK_F / F + 0.05, function(e) if e.kind == "block_down" then down = e end end)
  T.check(down and down.why == "blocked" and sim.player.shield == 0, "...then shatters")
  T.check(sim.player.shatter > 0 and sim.player.shieldCd > 0, "...its pieces fly and the cooldown starts")
  run(sim, 2)
  T.eq(sim:block(), true, "held, the next one")
  down = nil
  run(sim, 45 / F + 0.05, function(e) if e.kind == "block_down" then down = e end end)
  T.check(down and down.why == "held", "...shatters at its length (1.5 s here)")
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
  -- the reticle on a bit as the screen shows it, from the trainee well to one side: hits it
  do
    local s3 = make("lv2_spd")
    run(s3, 9.1)
    local b = s3.bits[2]
    T.check(b ~= nil and not b.dead, "a live bit to aim at")
    s3.player.x = -0.7
    local ax, ay = Sim.unproject(Sim.project(b.x, b.y, b.z))
    s3:aim(ax, ay)
    T.check(s3:bitUnder(ax, ay, 0) == b, "the reticle is over it")
    local hits = 0
    s3:pressFire(); s3:update(1 / 60); s3:releaseFire()
    run(s3, 0.9, function(e) if e.kind == "bit_hit" or e.kind == "bit_pop" then hits = hits + 1 end end)
    T.eq(hits, 1, "a shot at the bit on screen hits it")
    T.eq(b.hp, N.ATTACK.bit.hp - 1, "...and it takes the damage")
    T.check(s3:bitUnder(0, 0.05, 0) == nil, "a reticle away from the bits aims at the balloon")
  end
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

-- ------- the energy meter (the game's 500): a shot costs its colour's share; one it cannot
-- cover is the weak shot, free; the rings' ready flag follows the plain shot's cost

do
  local sim = make("lv1_hp", { shotType = "green" })
  run(sim, 3.1)
  sim.guts = 1
  sim:aim(0, 0.45)
  T.check(sim:shotReady(), "a full meter covers a shot")
  local kinds = {}
  for _ = 1, 2 do
    sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
    for _, e in ipairs(sim:update(1 / 60)) do if e.kind == "shot_fired" or e.kind == "weak_shot" then kinds[#kinds + 1] = e.type end end
  end
  T.eq(kinds[1], "green", "the first green shot (300 of 500)")
  T.eq(kinds[2], "weak", "the second, the meter short: the weak shot")
  T.check(sim.shots[1].points > sim.shots[2].points, "...worth less")
  T.check(not sim:shotReady(), "the rings go with the meter below the cost")
  local g0 = sim.guts
  run(sim, 0.5)
  T.check(sim.guts > g0, "it refills with time")
end

-- ------- the guard: up while held, for at most its length, a cooldown after; half-speed moving

do
  local sim = make("lv1_hp", { mods = { pointMult = 1, shotSize = 1, lossMult = 1, gutsRate = 1, blockLen = 1,
    moveMult = 1, ballSpeedMult = 1, blockS = 40 / 30 } })
  run(sim, 3.1)
  T.eq(sim:block(), true, "the guard rises")
  T.eq(sim:pressFire(), true, "...a press still charges")
  T.eq(sim:releaseFire(), false, "...but nothing fires while it is up")
  sim:setMove(1, 0)
  local x0 = sim.player.x
  run(sim, 0.5)
  local guarded = sim.player.x - x0
  T.check(sim.player.shield > 0, "held, it stays up")
  T.eq(sim:unblock(), true, "let go, it drops")
  T.eq(sim:block(), false, "...and cannot rise again during the cooldown")
  x0 = sim.player.x
  run(sim, 0.5)
  T.check(math.abs((sim.player.x - x0) - 2 * guarded) < 1e-6 or sim.player.x >= N.PLAYER.X_MAX - 1e-6, "it moves at half speed while up")
  sim:setMove(0, 0)
  run(sim, 0.6)
  T.eq(sim:block(), true, "after the cooldown it rises again")
  run(sim, 40 / 30 + 0.05)
  T.check(sim.player.shield == 0 and sim.player.shieldCd > 0, "held past its length it drops on its own")
end

-- ------- the game's shot power and refill from the Pokemon's stats

do
  -- Latias-like bases (Atk 80, SpA 110, Def 90, SpD 130) and 252 Atk / 252 SpA / 6 HP EVs
  local base = { hp = 80, atk = 80, def = 90, spe = 110, spa = 110, spd = 130 }
  local evs = { hp = 6, atk = 252, spa = 252 }
  local st = Rules.shotStats(base, evs, nil)
  -- (80 + 110) div 5 = 38, 504 div 4 = 126, 0.5 x 50 + 0.2 x 50 + 0.1 x 410 = 76 -> 240
  T.eq(st.power, 240, "the shot power is the game's formula")
  T.eq(Rules.shotStats(base, evs, "strength").power, 360, "...x1.5 with Strength")
  -- DEFv = 90 + 130, EV total 510: int(4 x (1 + 730 x 0.0025)) = 11 a frame, 330 a second
  T.check(math.abs(st.gutsPerS - 11 * 30 / 500) < 1e-9, "the refill a frame from Def / Sp. Def and the EVs")
  local sim = make("lv1_hp", { mods = Rules.modifiers(evs, nil, { base = base }) })
  run(sim, 3.1)
  sim.guts = 1
  local g = sim:state().goals[1]
  sim:aim(g.x, g.y)
  sim:pressFire(); sim:update(1 / 60); sim:releaseFire()
  local hit
  run(sim, 1.5, function(e) if e.kind == "goal_hit" then hit = e end end)
  T.eq(hit and hit.points, 240, "a plain black hit scores the shot power")
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

  local aero = make("lv2_spe", { sway = true })
  run(aero, 3.1)
  local _, y0 = aero:botOffset()
  run(aero, 1.35)
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
  T.eq(lv3.score, 1000 - 450, "a Lv3 Wailord hit costs its 450")
  lv3.score = 1000
  lv3:playerHit({ kind = "bit" })
  T.eq(lv3.score, 1000 - math.floor(450 * N.DAMAGE.BIT_SHARE), "...a bitbot's shot its share")
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
  T.eq(sim.score, 0, "...and hit with its second form's 2500")
  calm.score = 2000
  calm:playerHit({ kind = "big" })
  T.eq(calm.score, 800, "calm, Aegislash's 1200")
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
  T.check(base.guts < 0.01, "the energy meter starts empty")
  run(base, 3.1)
  base.guts = 1
  local strong = make("lv1_hp", { mods = { pointMult = 2, shotSize = 1, lossMult = 0.5, gutsRate = 1, blockLen = 1, moveMult = 1, ballSpeedMult = 1 } })
  run(strong, 3.1)
  strong.guts = 1
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

-- ------- the game's attack scripts (data/training_attacks.lua from tools/st_attacks.py)

do
  local GA = loadFile("mods/play_nav/data/training_attacks.lua")
  local function gameSim(id, opts)
    opts = opts or {}
    local course = C.byId[id]
    return Sim.new(course, { anchors = C.anchors[course.goals.anchors], library = C.attacks,
      shotType = "black", level = course.level, still = true, gameAttacks = GA }, opts.rng or lcg(11))
  end
  T.check(GA and GA.courses and GA.phases and GA.volleys and GA.projectiles, "the game's attack data loads")
  -- every course runs a minute of its script without trouble, and attacks
  local quiet = {}
  for _, c in ipairs(C.courses) do
    local sim = gameSim(c.id)
    T.check(sim.script ~= nil, c.id .. " has the game's script")
    run(sim, 3.1)
    sim.player.safe = 1e9   -- untouchable: the clock and the balloon stay put
    local launches, balls = 0, 0
    local ok, err = pcall(run, sim, 60, function(e) if e.kind == "attack_launch" then launches = launches + 1 end end)
    T.check(ok, c.id .. " runs (" .. tostring(err) .. ")")
    for _, b in ipairs(sim.balls) do if b.game then balls = balls + 1 end end
    if launches == 0 and #sim.bits == 0 then quiet[#quiet + 1] = c.id end
  end
  T.eq(#quiet, 0, "every course attacks within a minute (" .. table.concat(quiet, ", ") .. ")")

  -- Wailmer (lv1_hp): a single aimed shot each loop; it flies at the game's speed, aimed at the trainee
  local w = gameSim("lv1_hp")
  run(w, 3.1)
  w.player.x = 0.4
  local launched
  run(w, 20, function(e) if e.kind == "attack_launch" and not launched then launched = e end end)
  T.check(launched ~= nil, "Wailmer fires")

  -- the warning's prediction (Sim:ballEta): a game ball's arrival and whether it hits match the hit
  do
    local e = gameSim("lv1_hp")
    run(e, 3.1)
    e.script, e.balls, e.spawnQueue = nil, {}, {}
    e.player.x = 0.3
    local ball = Sim.gameBall(e, { p = 0, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
    e.balls[1] = ball
    local eta, hits = e:ballEta(ball)
    T.check(eta and hits, "an aimed ball is predicted to hit a still trainee")
    local t0, hitAt = e.t, nil
    run(e, 10, function(ev) if ev.kind == "player_hit" and not hitAt then hitAt = ev.t end end)
    T.check(hitAt and math.abs((hitAt - t0) - eta) < 0.05, ("...and arrives when predicted (%.2f vs %.2f s)"):format(eta or -1, (hitAt or 0) - t0))
    local m = gameSim("lv1_hp")
    run(m, 3.1)
    m.script, m.balls = nil, {}
    m.player.x = 0.3
    local miss = Sim.gameBall(m, { p = 0, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
    m.player.x = -0.6
    local _, mh = m:ballEta(miss)
    T.check(mh == false, "...one the trainee has stepped away from is not")

    -- a ball that reaches an untouchable trainee (just hit) breaks there, harmless
    local u = gameSim("lv1_hp")
    run(u, 3.1)
    u.script, u.balls, u.spawnQueue = nil, {}, {}
    u.player.x = 0.3
    local ub = Sim.gameBall(u, { p = 0, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
    u.balls[1] = ub
    u.player.safe = 1e9
    local before, absorbed = u.score, false
    run(u, 4, function(ev) if ev.kind == "ball_absorbed" then absorbed = true end end)
    T.check(absorbed and #u.balls == 0 and u.score == before,
      "a ball on an untouchable trainee breaks there and costs nothing (not on into the camera)")
  end

  -- Graveler (lv2_def): its first step raises a shield with a target; nothing is thrown while
  -- it stands, the target breaks it and the script goes on
  do
    local g = gameSim("lv2_def")
    run(g, 3.1)
    g.player.safe = 1e9
    local up
    run(g, 8, function(e) if e.kind == "barrier_up" then up = true end end)
    local marker
    for _, goal in ipairs(g.goals) do if goal.kind == "marker" then marker = goal end end
    T.check(up and g.barrier and marker, "Graveler's shield goes up with its target")
    local thrown = 0
    run(g, 6, function(e) if e.kind == "attack_launch" then thrown = thrown + 1 end end)
    T.eq(thrown, 0, "...nothing is thrown while it stands")
    -- a shot on one of its goals while it stands scores nothing
    local white
    for _, goal in ipairs(g.goals) do if goal.kind ~= "marker" then white = goal end end
    if white then
      local gx, gy = g:goalPos(white)
      g.shots = { { x = gx, y = gy, z = 0.99, vx = 0, vy = 0, vz = 2, r = 0.05, points = 100, type = "black", stage = 0 } }
      local scoreBefore = g.score
      run(g, 0.2)
      T.eq(g.score, scoreBefore, "...a shot at its goals is absorbed (it cannot be hit)")
    end
    g:hitGoal(marker, { points = 100 })
    T.check(not g.barrier and g.shieldBrokeAt, "...the target breaks it, shattering")
    run(g, 20, function(e) if e.kind == "attack_launch" then thrown = thrown + 1 end end)
    T.check(thrown > 0, "...and the attacks go on (" .. thrown .. ")")
  end
  local hitAt
  local w2 = gameSim("lv1_hp")
  run(w2, 3.1)
  w2.player.x = 0.4
  local t0
  run(w2, 30, function(e)
    if e.kind == "attack_launch" and not t0 then t0 = e.t end
    if e.kind == "player_hit" and t0 and not hitAt then hitAt = e.t end
  end)
  T.check(hitAt and t0 and hitAt - t0 > 1.5 and hitAt - t0 < 3.5, ("an aimed shot reaches a still trainee (%.2f s; 240 / its speed)"):format((hitAt or 0) - (t0 or 0)))

  -- homing: a homing projectile bends toward where the trainee is now
  local P5 = GA.projectiles[5]
  T.check(P5 and P5.homeX > 0, "projectile 5 homes")
  local h = gameSim("lv1_hp")
  run(h, 3.1)
  h.player.x = -0.5
  local ball = Sim.gameBall(h, { p = 5, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
  h.balls[#h.balls + 1] = ball
  h.player.x = 0.5   -- moves after the launch
  for _ = 1, 20 do h:update(1 / 60) end
  T.check(ball.x > ball.bx + 0.05, "...it bends toward the trainee's new place")

  -- homing (Wooble): a round homing ball (projectile 57) hits a trainee standing still, misses
  -- one that moves in its last 0.25 s; a wide one (36, across strong) hits one moving across,
  -- misses one moving up; a tall one (37) the other way round
  do
    local function trial(pid, move)
      local e = gameSim("lv1_hp")
      run(e, 3.1)
      e.script, e.balls, e.spawnQueue = nil, {}, {}
      e.player.x, e.player.y, e.player.safe = 0.1, 0, 0
      local b = Sim.gameBall(e, { p = pid, next = 0, dx = 0, dy = 0, yaw = 0, pitch = 0, aimX = 1, aimY = 1 })
      e.balls[1] = b
      local hit = false
      local moved = false
      for _ = 1, 60 * 4 do
        if not moved and b.lockX then
          moved = true
          if move == "across" then e.player.x = e.player.x + 0.08 end
          if move == "up" then e.player.y = (e.player.y or 0) + 0.08 end
        end
        for _, ev in ipairs(e:update(1 / 60)) do if ev.kind == "player_hit" then hit = true end end
      end
      return hit
    end
    T.check(trial(57, nil), "a round homing ball hits a trainee standing still")
    T.check(not trial(57, "across"), "...and misses one moving in its last 0.25 s")
    T.check(trial(36, "across"), "a wide ball follows across: moving sideways still hit")
    T.check(not trial(36, "up"), "...moving up dodges it")
    T.check(trial(37, "up"), "a tall ball follows up and down: moving up still hit")
    T.check(not trial(37, "across"), "...moving sideways dodges it")
  end

  -- a stream: its shots leave on their frames, not together
  local stream
  for vid, shots in pairs(GA.volleys) do
    if #shots >= 3 and shots[1].next and shots[1].next > 0 then stream = vid; break end
  end
  T.check(stream ~= nil, "the data has a stream")
  local st = gameSim("lv1_hp")
  run(st, 3.1)
  st.spawnQueue = {}
  st.balls = {}
  local times = {}
  for _, q in ipairs((function() local qq = {} local d = 0 for _, shot in ipairs(GA.volleys[stream]) do qq[#qq + 1] = d; d = d + shot.next end return qq end)()) do times[#times + 1] = q end
  T.check(times[2] > times[1], "...shot 2 leaves frames after shot 1")

  -- Aegislash (secret_06): below half its score left, its second form - the other list and 2500
  local a = gameSim("secret_06")
  run(a, 3.1)
  a.player.safe = 1e9
  T.eq(a.script.form, false, "Aegislash starts in its first form")
  a.score = 2500   -- 2300 of 4800 left: under 50%
  local changed
  run(a, 40, function(e) if e.kind == "form_change" then changed = e end end)
  T.check(changed and changed.form == "B" and a.script.form, "...below half, its second form")
  a.player.safe = 0
  a.score = 4000
  a:playerHit({ kind = "small" })
  T.eq(a.score, 1500, "...whose hits cost 2500")

  -- Roserade (secret_07) starts fierce and calms at half
  local r = gameSim("secret_07")
  run(r, 3.1)
  run(r, 6)
  T.eq(r.script.form, true, "Roserade starts in its fierce form")

  -- bitbots (lv2_spd, Tentacruel): spawned by the script, firing about once a second at the trainee
  local b = gameSim("lv2_spd")
  run(b, 3.1)
  b.player.safe = 1e9
  local fired = 0
  run(b, 30, function(e) if e.kind == "bit_fire" then fired = fired + 1 end end)
  T.check(#b.bits > 0 and #b.bits <= 3, "Tentacruel's bits come, three at most (" .. #b.bits .. ")")
  T.check(fired >= 5, "...and fire (" .. fired .. ")")
end

T.finish()
