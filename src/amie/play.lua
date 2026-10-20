-- PLAY: Pokemon-Amie's close-up, played from the game's own screen (a/0/4/1 entry 0
-- game_select_lower.bclyt, pack amie_play: the round puff / play / return buttons, the puff
-- strip, the minigame picker with its badges, arrows and difficulty ribbons) and the petting
-- hand's frames (a/0/4/2 kawaigari_icon, pack amie_hand):
--   the scene: sky (assets/amie-play-bg.png, cropped clear of its rainbow), a big
--   cumulus, the bush line along the horizon and the lawn (the game's scene/* textures from
--   the import), soap bubbles; the Pokemon large (about 3.5x its sprite, filling the height);
--   the wake: it starts with its back turned; a tap -> "!", a white flash, it faces you with
--   notes, and the buttons come in;
--   petting: the view eases in on the touch, the hand strokes (the game's frames: open hand,
--   burning / shocking / freezing / cutting / wet / dirty spots, tap sparkle, hit burst),
--   reactions by spot (hearts, notes, angry with the yellow burst); the buttons hide while the
--   finger is on the Pokemon;
--   feeding: the puff button slides the strip in (the jar's puffs, in order, seven a page);
--   a puff dropped on the Pokemon -> a white flash with stars -> a close-up on its head, the
--   puff shrinking bite by bite -> a reaction by the affection it gave -> back out;
--   the games: the play button drops the bar ("Which game do you want to play?") and the
--   three badges, gold arrows to turn; a tap on the badge -> "Select a difficulty level." and
--   the four ribbons with their stars; a tap on a ribbon starts the game; the return button
--   steps back.
-- The rules, the spots and the session API are unchanged: src/amie/rules.lua,
-- src/amie/petting.lua, src/amie/session.lua.

return function(mod, Pointer, G, Rules, Petting, host)
  host = host or {}

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "play", title = "AMIE", live = true }

  function app:wantsSurface() return G.session ~= nil and G.session.mode ~= "home" end

  -- the game's 320x240 layout, drawn under scale(L) from -bleed; a taller screen (Kanto
  -- Gear's) is LH tall: the scene is anchored to the foot (the sky grows), the top buttons
  -- stay, the return button goes to the foot, the picker to the middle
  local L, BLEED = 256 / 320, 14
  local LH, D = 240, 0
  local function bleed() return app.bleed or BLEED end
  local function setShape(h)
    local lh = math.max(240, ((h or 178) + bleed()) / L)
    if lh == LH then return end
    LH, D = lh, lh - 240
    app.shapeDirty = true
  end
  app.setShape = setShape
  local function toLyt(x, y) return x / L, (y + bleed()) / L end
  local function fromLyt(x, y) return x * L, y * L - bleed() end

  local function art(id)
    local A = app.assets
    if not A or A.enabled == false then return nil end
    return A.image(id)
  end

  -- ------- the numbers (layout units)

  local HORIZON = 0.55            -- the bushes' foot, as a share of LH from the top... of the 240 rows
  local FEET_UP = 20              -- the Pokemon's feet above the foot
  local MON_FILL = 0.68           -- its visible height as a share of the screen
  local MON_K_MIN, MON_K_MAX = 2.5, 5.5
  local ZOOM_TOUCH = 1.35         -- the view while a finger is on the Pokemon
  local ZOOM_EAT = 1.7            -- the close-up while it eats (more turns a GBA sprite to blocks)
  local EAT_R = 40                -- how near its mouth (screen units) a held puff must be to be eaten
  local JUMP_S, JUMP_PEAK = 0.7, 0.4   -- the high five's leap: its length, and when it reaches the hand
  local JUMP_REACH = 0.75         -- how much of the way from its head to the hand it leaps
  local JUMP_HOP = 30             -- and how high it springs on the way (layout units)
  local EASE = 9                  -- view easing, per second
  local STRIP_W = 313             -- the puff strip open (the game's window 2y)
  local STRIP_SLOTS = { "38", "3a", "3c", "3e", "3g", "3i", "3k" }
  local BADGE = { "a", "0", "c" }                   -- badge plates, game order
  local BADGE_NAME = { "1l", "1n", "1p" }
  local PLATE = { "k", "m", "o", "q" }              -- difficulty ribbons, DIFFS order
  local PLATE_TEXT = { "1t", "1v", "1x", "1z" }
  local PLATE_STARS = { { "s", "3w", "3y", "40", "42" }, { "14", "46", "48", "4a", "4c" },
    { "w", "4e", "4g", "4i", "4k" }, { "10", "4m", "4o", "4q", "4s" } }
  local PLATE_TEX = { "easy", "normal", "hard", "infinite" }

  -- ------- state

  local P, Pfail = nil, false
  local particles = {}
  local view = { z = 1, fx = 160, fy = 120, px = 160, py = 120 }   -- screen = p + (scene - f) * z
  local want = { z = 1, fx = 160, fy = 120, px = 160, py = 120 }
  local wake = nil        -- { session, stage = "asleep" | "exclaim" | "flash" | "awake" | "dozing", t }
  -- left alone awake for the game's IDLE ticks, it dozes off (still, drooping, "z"s) for its
  -- sleep cycles, shrinks back into its ball and the screen goes back to the room; a tap while
  -- it dozes wakes it again (data IDLE)
  local IDLE = { Z_EVERY = 0.7 }
  local function idleS() return Rules.ticks(Rules.IDLE.TICKS) end
  local function dozeS() return Rules.ticks(Rules.IDLE.CYCLES * Rules.IDLE.CYCLE_TICKS) end
  local lastActive = 0
  -- unwell on entering: three shivers (the script's motion 5, three times), then the room
  local SICK_S, SICK_SHIVERS = 3.0, 3
  local petLock = 0       -- after a reward or a recoil: petting waits until then
  local lastMode = nil
  local touch = nil       -- { id, x, y (layout), sx, sy (scene), onBody, t } a finger on the Pokemon
  local hand = nil        -- { kind, t, x, y } the hand's flipbook at a screen point
  local emote = nil       -- { id, untilT }
  local drag = nil        -- { kind = <puff id>, x, y (layout), id }
  local feed = nil        -- { stage = "flash" | "eat" | "after", t, kind, bites, taken }
  local strip = { open = 0, scroll = 0, vel = 0 }   -- the puff drawer: how open, scrolled (layout units)
  local falling = {}      -- puffs let go of: { kind, x, y, vx, vy, rot } (layout units) until off screen
  local jump = nil        -- the high five: { t, dur, hx, hy (scene), slapped } it leaps at the hand
  local picker = nil      -- { stage = "badge" | "diff", game = 1..3, diff = 1..4 }
  local pv = { tab = 145, cont = 0, badges = 0, plates = 0 }        -- the picker panes, eased
  local holdFive = nil
  local lastPress = nil   -- when the last press on the body began (a hit is a second one soon after)
  local fiveLeft = 0      -- the high five's countdown, seconds; it runs only while a hand is held out
  local dance = nil
  local flash = nil       -- { t, dur } a white flash over everything
  local stars = {}        -- the flash's stars
  -- its liveliness (lively by mood, mostly still while petted): `calm`
  -- eases to 1 while it is touched or eating; `hop` a hop under way; `excite` the burst after
  -- a liked touch; `lean` toward the hand
  local life = { calm = 0, hop = nil, nextHop = 1.5, excite = 0, lean = 0, twitch = 0, t = 0, stroke = 0, flinch = 0, phase = 0 }

  -- what its mood allows: 0 (low, hungry or unwell) .. 1 (happy, played with), and a status
  local function moodOf(s)
    local m = s.meters or {}
    local aff, enj, full = Rules.level(m.affection), Rules.level(m.enjoyment), Rules.level(m.fullness)
    local lively = 0.25 + 0.75 * math.min(1, (aff + 2 * enj) / 12)
    if full <= 0 then lively = lively * 0.55 end
    if s.status == "SLP" then lively = 0.1 end
    if s.status == "FRZ" or s.status == "PAR" then lively = lively * 0.5 end
    return lively, s.status, full <= 0
  end

  -- the motion this frame: x shift, lift (up), tilt, and squash (sx, sy) about its feet
  local function lifeMotion(s, t, pl)
    local lively, status, hungry = moodOf(s)
    local free = 1 - life.calm                    -- petted / eating: almost still
    local ex = math.max(0, life.excite)
    local energy = math.min(1.4, lively + 0.6 * ex)
    -- breathing: a little faster and fuller the livelier it is (about 0.4 to 1 a second); the
    -- phase is stepped at that rate in stepLife, so a change of rate never jumps the wave
    local ph = life.phase
    local breath = math.sin(ph) * (0.012 + 0.018 * energy)
    -- a sway side to side, a bob
    local tilt = math.sin(ph * 0.5 + 0.7) * (0.015 + 0.05 * energy) * free
    local dx = math.sin(ph * 0.25) * (2 + 6 * energy) * free
    local lift = (0.5 + 0.5 * math.sin(ph)) * (1 + 2.5 * energy) * free
    local sx, sy = 1 - breath * 0.6, 1 + breath
    -- a hop: up, a squash on landing
    if life.hop then
      local f = life.hop.t / life.hop.dur
      if f < 1 then
        lift = lift + math.sin(f * math.pi) * life.hop.h
        if f > 0.85 then sx, sy = sx + 0.06, sy - 0.06 end
      end
    end
    -- hungry: a little droop; unwell: a shiver now and then
    if hungry then sy = sy - 0.03; sx = sx + 0.02 end
    -- back into its ball: it shrinks away
    if wake and wake.stage == "ball" then
      local f = math.min(1, wake.t / Rules.IDLE.BALL_S)
      sx, sy = sx * (1 - f), sy * (1 - f)
    end
    -- unwell on entering: a hunched shiver, SICK_SHIVERS times
    if wake and wake.stage == "sick" then
      local per = SICK_S / SICK_SHIVERS
      local into = (wake.t % per) / per
      local on = into < 0.6 and math.sin(into / 0.6 * math.pi) or 0
      dx = dx + math.sin(t * 30) * 2 * on
      sy, sx = sy - 0.05 * on, sx + 0.03 * on
    end
    -- dozing off: it sinks a little and nods
    if wake and wake.stage == "dozing" then
      local d = math.min(1, wake.t / 1.2)
      sy, sx = sy - 0.05 * d, sx + 0.03 * d
      tilt = tilt + math.sin(t * 1.6) * 0.03 * d
    end
    if (status == "PSN" or status == "BRN" or status == "FRZ") and math.sin(t * 0.9) > 0.6 then
      dx = dx + math.sin(t * 18) * 1
    end
    if status == "PAR" and life.twitch > 0 then
      dx = dx + math.sin(t * 24) * 1.5
      tilt = tilt + math.sin(t * 16) * 0.03
    end
    -- leaning into the hand while petted
    tilt = tilt + life.lean * 0.05 * life.calm
    -- being stroked: it wriggles with the strokes, so the player sees the petting land
    if life.stroke > 0 then
      local k = life.stroke
      tilt = tilt + math.sin(t * 9) * 0.03 * k
      sy, sx = sy + math.sin(t * 9 + 1) * 0.025 * k, sx - math.sin(t * 9 + 1) * 0.015 * k
      lift = lift + (0.5 + 0.5 * math.sin(t * 9)) * 1.5 * k
    end
    -- a disliked spot: it flinches away from the hand
    if life.flinch > 0 then
      dx = dx + math.sin(t * 40) * 2.5 * life.flinch - life.lean * 4 * life.flinch
    end
    return dx, lift, tilt, sx, sy
  end

  local function stepLife(s, dt, pl)
    life.t = life.t + dt
    do
      local energy = math.min(1.4, moodOf(s) + 0.6 * math.max(0, life.excite))
      life.phase = (life.phase + (0.8 + 0.85 * energy) * math.pi * dt) % (8 * math.pi)
    end
    local still = (touch ~= nil) or (feed ~= nil) or (drag ~= nil) or (wake ~= nil and (wake.stage == "dozing" or wake.stage == "ball" or wake.stage == "sick"))
    life.calm = life.calm + ((still and 1 or 0) - life.calm) * (1 - math.exp(-6 * dt))
    life.excite = math.max(0, life.excite - dt / 1.6)
    life.stroke = math.max(0, life.stroke - dt * 3)
    life.flinch = math.max(0, life.flinch - dt * 2.5)
    if life.twitch > 0 then life.twitch = life.twitch - dt end
    if s.status == "PAR" and life.twitch <= 0 and math.random() < dt * 0.4 then life.twitch = 0.35 end
    -- toward the hand while petted
    local target = 0
    if touch and pl then
      local sx = view.fx + (touch.x - view.px) / view.z
      target = math.max(-1, math.min(1, (sx - pl.cx) / math.max(1, pl.rx)))
    end
    life.lean = life.lean + (target - life.lean) * (1 - math.exp(-5 * dt))
    -- hops: a lively, untouched Pokemon hops now and then (twice in a row when very happy)
    if life.hop then
      life.hop.t = life.hop.t + dt
      if life.hop.t >= life.hop.dur then
        life.hop = life.hop.again and { t = 0, dur = life.hop.dur, h = life.hop.h * 0.7 } or nil
      end
    end
    local lively = moodOf(s)
    local energy = lively + 0.6 * life.excite
    life.nextHop = life.nextHop - dt
    if not life.hop and life.nextHop <= 0 then
      if not still and energy > 0.55 and wake and wake.stage == "awake" then
        life.hop = { t = 0, dur = 0.32, h = 6 + 14 * math.min(1, energy), again = energy > 0.95 }
      end
      life.nextHop = (energy > 0.9 and 1.4 or 2.6) + math.random() * 1.6
    end
  end

  local function now() return Pointer.now() end
  -- haptics (src/haptics.lua): a pulse or a timed pattern at the player's level
  local function buzz(kind) local H = mod.haptics; if H then H.pulse(kind) end end
  local function buzzPattern(name) local H = mod.haptics; if H then H.pattern(name) end end

  local function showEmote(id, secs) emote = { id = id, untilT = now() + (secs or 1.2) } end

  -- ------- the screen

  local function screen()
    if P or Pfail then return P end
    P = mod.lyt and mod.lyt.open("amie_play", "game_select_lower.bclyt", { "amie_play" }) or nil
    if not P then Pfail = mod.lyt == nil; return nil end
    -- what the game keeps hidden until a clip shows it, and what we draw ourselves
    for _, n in ipairs({ "2y", "e", "2", "g", "24", "28", "2f", "2s", "2t", "2v", "3u", "44", "5e", "i" }) do
      P:set(n, "visible", false)
    end
    for _, n in ipairs(STRIP_SLOTS) do P:set(n, "visible", false) end
    P:set("23", "visible", false)
    app.shapeDirty = true
    return P
  end
  app.screen = function() return screen() end

  local function applyShape()
    if not P or not app.shapeDirty then return end
    app.shapeDirty = false
    if D > 0 then
      P.adjust = { ["4"] = { dy = -D }, ["e"] = { dy = -D }, ["23"] = { dy = -D / 2 },
        ["2"] = { dy = -D / 2 }, ["g"] = { dy = -D / 2 } }
    else
      P.adjust = nil
    end
  end

  local function box(name)
    if not P then return nil end
    return P:box(name)
  end
  local function inBox(name, x, y, pad)
    local bx, by, bw, bh = box(name)
    if not bx then return false end
    if bw < 0 then bx, bw = bx + bw, -bw end
    pad = pad or 0
    return x >= bx - pad and x <= bx + bw + pad and y >= by - pad and y <= by + bh + pad
  end

  -- ------- the Pokemon: its sprite's opaque box (read back once per picture), placed large

  local boxes = setmetatable({}, { __mode = "k" })
  local function opaqueBox(img)
    if not img then return nil end
    local b = boxes[img]
    if b then return b end
    local w, h = img:getDimensions()
    b = { x0 = 0, y0 = 0, x1 = w, y1 = h, w = w, h = h }
    local ok = pcall(function()
      -- one canvas pixel per sprite unit: the default density is the screen's (2-3 on a
      -- high-DPI device), which made the scan below read only the top-left corner
      local c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
      love.graphics.push("all")
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.origin()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.setCanvas()
      love.graphics.pop()
      local data = c:newImageData()
      local x0, y0, x1, y1 = w, h, -1, -1
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local _, _, _, a = data:getPixel(x, y)
          if a > 0.1 then
            if x < x0 then x0 = x end
            if x > x1 then x1 = x end
            if y < y0 then y0 = y end
            if y > y1 then y1 = y end
          end
        end
      end
      if x1 >= x0 then b.x0, b.y0, b.x1, b.y1 = x0, y0, x1 + 1, y1 + 1 end
    end)
    if not ok then b = { x0 = 0, y0 = 0, x1 = w, y1 = h, w = w, h = h } end
    boxes[img] = b
    return b
  end

  -- where the Pokemon stands (scene units): its feet, its scale, its body ellipse.
  -- Deterministic from the picture and the shape, and asked for several times a frame, so it
  -- is cached per image (nothing writes into the record) and dropped when the shape changes.
  local placements = setmetatable({}, { __mode = "k" })
  local placeLH = nil
  local function placement(s, pic)
    pic = pic or (s and s.pic)
    local img = pic and pic.image
    if placeLH ~= LH then
      placeLH = LH
      for k in pairs(placements) do placements[k] = nil end
    end
    local hit = img and placements[img]
    if hit then return hit end
    local b = opaqueBox(img) or { x0 = 0, y0 = 0, x1 = 64, y1 = 64 }
    local bw, bh = b.x1 - b.x0, b.y1 - b.y0
    local k = (LH * MON_FILL) / math.max(1, bh)
    k = math.max(MON_K_MIN, math.min(MON_K_MAX, k, 290 / math.max(1, bw)))
    local feetY = LH - FEET_UP
    local pl = {
      img = img, b = b, k = k, x = 160, y = feetY,
      cx = 160, cy = feetY - bh * k / 2, rx = bw * k / 2, ry = bh * k / 2,
      headX = 160, headY = feetY - bh * k * 0.78, mouthY = feetY - bh * k * 0.62,
    }
    if img then placements[img] = pl end
    return pl
  end

  local function toScene(lx, ly)
    return view.fx + (lx - view.px) / view.z, view.fy + (ly - view.py) / view.z
  end
  local function toBody(pl, sx, sy) return (sx - pl.cx) / pl.rx, (sy - pl.cy) / pl.ry end
  local function onBody(pl, sx, sy, slack)
    local bx, by = toBody(pl, sx, sy)
    return bx * bx + by * by <= (slack or 1.1) ^ 2
  end

  -- ------- particles (scene units)

  local function spawn(kind, x, y, n)
    for _ = 1, n or 1 do
      particles[#particles + 1] = {
        kind = kind, x = x + (math.random() - 0.5) * 30, y = y + (math.random() - 0.5) * 14,
        vx = (math.random() - 0.5) * 40, vy = -30 - math.random() * 40,
        life = 0.9 + math.random() * 0.6, age = 0, size = 4 + math.random() * 4,
      }
    end
  end

  -- ------- the hand: the game's frames, by what the finger found

  local HAND = {
    pet = { "icon_hand", "icon_hand_a0", "icon_hand_a1", "icon_hand_a0" },
    tap = { "icon_tap0", "icon_tap1", "icon_tap2", "icon_tap3", "icon_tap4" },
    hit = { "icon_hit0", "icon_hit1", "icon_hit2", "icon_hit3" },
    dislike = { "icon_biribiri1", "icon_biribiri3", "icon_biribiri1", "icon_biribiri3" },
    burning = { "icon_burn0", "icon_burn1", "icon_burn2", "icon_burn3" },
    paralyzing = { "icon_biribiri0", "icon_biribiri1", "icon_biribiri2", "icon_biribiri3" },
    freezing = { "icon_freeze0" },
    cutting = { "icon_hurt0", "icon_hurt1", "icon_hurt2" },
    gooey = { "icon_junk0", "icon_junk1" }, slimy = { "icon_junk0", "icon_junk1" },
    wet = { "icon_water0" }, five = { "icon_oide_a0", "icon_oide_a1", "icon_oide_a2", "icon_oide_fix" },
  }
  local HAND_FPS = 10
  local HAND_ONCE = { tap = 0.5, hit = 0.45, dislike = 0.6, burning = 0.7, paralyzing = 0.7,
    freezing = 0.7, cutting = 0.7 }
  local EFFECT_TEXT = { burning = "Ouch, hot!", freezing = "Brr, freezing!", paralyzing = "Zap!", cutting = "Ow, sharp!" }

  local function setHand(kind, lx, ly)
    hand = { kind = kind, t = 0, x = lx, y = ly, untilT = HAND_ONCE[kind] and (now() + HAND_ONCE[kind]) or nil }
  end

  -- ------- reactions

  local function react(pl, hearts, spot, sx, sy)
    if hearts > 0 then
      spawn("heart", sx, sy - 16, math.max(2, hearts))
      showEmote(spot == "favored" and "emote/love" or "emote/happy", 1.0)
      life.excite = 1
    elseif spot == "disfavored" then
      showEmote("emote/angry", 0.9)
      app.dislikeUntil = now() + 0.6
      return "dislike"
    else
      spawn("note", sx, sy - 16, 1)
    end
  end

  -- the touch ends (a reward, a recoil, or off the body too long): the view eases out and
  -- petting waits lockS for the motion to play
  local function endTouch(lockS)
    touch = nil
    want.z = 1
    petLock = now() + (lockS or 0)
    if G.petLift then G.petLift() end
  end

  -- a petting reward (G.petTouch): the hearts gained, then the happy motion - a bounce and music
  -- notes - with petting locked until it ends; a disliked spot's reward is an angry turn
  local function reward(s, pl, res, lx, ly)
    if res.spot == "disfavored" then
      showEmote("emote/angry", 1.0)
      setHand("dislike", lx, ly)
      G.bump(-0.08, 0)
      buzzPattern("hurt")
      endTouch(0.8)
      return
    end
    buzzPattern("happy")
    if res.hearts > 0 then
      spawn("heart", pl.headX, pl.headY - 10, math.min(5, res.hearts))
      showEmote(res.spot == "favored" and "emote/love" or "emote/happy", 1.2)
    end
    life.hop = { t = 0, dur = 0.32, h = 14, again = true }
    life.excite = 1
    spawn("note", pl.headX - 26, pl.headY, 2)
    spawn("note", pl.headX + 26, pl.headY, 2)
    endTouch(Rules.PET.LOCK_S)
  end

  local function hitEffect(kind, lx, ly)
    setHand(kind, lx, ly)
    showEmote(kind == "burning" and "emote/furious" or "emote/nervous", 0.8)
    G.bump(-0.06, 0)
    if (app.effectSaidAt or 0) + 2 < now() then
      app.effectSaidAt = now()
      G.say(EFFECT_TEXT[kind] or "!", 1.2)
    end
  end

  -- ------- the puff drawer: one of each kind the jar holds (catalogue order) with its count,
  -- drawn by us along the drawer from the puff button's right edge (the layout's seven slot
  -- panes started under the button and ran off the screen). It slides out of the button as it
  -- opens; a sideways drag scrolls it (with momentum), a pull down takes a puff out.

  local PUFF_PX, PUFF_PITCH = 34, 40   -- a puff's size and spacing in the drawer
  local function stripKinds(s) return Rules.ownedPuffs(s.puffs or {}) end
  -- the puff row: its left and right edges and middle height (layout units)
  local function stripGeom()
    local bx, by, bw, bh = box("6")
    if not bx then return 72, 306, 33 end
    return bx + bw + 4, bx + STRIP_W - 10, by + bh / 2
  end
  local function maxScroll(n, x0, x1) return math.max(0, n * PUFF_PITCH - (x1 - x0)) end
  -- how far the row has come out of the button (0..1, eased): the whole row slides out as one,
  -- at full opacity, from behind the button's edge (the drawer's clip hides the rest)
  local function slideOf()
    local e = math.max(0, math.min(1, strip.open))
    return e * e * (3 - 2 * e)
  end
  local function slotX(i, x0, x1)
    local home = x0 + PUFF_PITCH / 2 + (i - 1) * PUFF_PITCH - strip.scroll
    local hidden = ((x1 or (x0 + STRIP_W)) - x0) + PUFF_PITCH
    return home - (1 - slideOf()) * hidden
  end
  -- the kind under a point of the open drawer, or nil
  local function kindAt(s, lx, ly)
    local x0, x1, cy = stripGeom()
    if math.abs(ly - cy) > PUFF_PITCH / 2 or lx < x0 or lx > x1 then return nil end
    local i = math.floor((lx - x0 + strip.scroll) / PUFF_PITCH) + 1
    local kinds = stripKinds(s)
    return kinds[i] and i or nil, kinds
  end
  local function inStripRow(lx, ly)
    local x0, x1, cy = stripGeom()
    return math.abs(ly - cy) <= PUFF_PITCH / 2 + 4 and lx >= x0 - 8 and lx <= x1 + 8
  end
  -- a puff let go of: it drops off the bottom of the screen
  local function fall(kind, lx, ly)
    falling[#falling + 1] = { kind = kind, x = lx, y = ly, vx = (math.random() - 0.5) * 60, vy = -60, rot = 0 }
    local H = mod.haptics
    if H then H.pulse("light") end
  end

  -- ------- the picker

  local Games = function() return G.Games end
  local function openPicker(s)
    if picker then return end
    local GA = Games()
    local sel = 1
    for i, g in ipairs(GA and GA.GAMES or {}) do if g == app.lastGame then sel = i end end
    picker = { stage = "badge", game = sel, diff = 1 }
  end

  local function startDiff(gi)
    local GA = Games()
    if not GA then return end
    picker.game, picker.stage = gi, "diff"
    -- the highest open rank first
    local game = GA.GAMES[gi]
    local d = 1
    for i, diff in ipairs(GA.DIFFS) do if GA.isUnlocked(game, diff) then d = i end end
    picker.diff = d
    G.click()
  end

  -- a difficulty chosen (a tap on its ribbon, or A): another one is selected first, the selected
  -- one starts the game if it is open
  local function pickDiff(i)
    local GA = Games()
    if not (GA and picker) then return end
    local game, diff = GA.GAMES[picker.game], GA.DIFFS[i]
    if i ~= picker.diff then
      picker.diff = i
      G.click()
    elseif diff and GA.isUnlocked(game, diff) then
      app.lastGame = game
      G.startGame(game, diff)
    else
      G.say(G.tx("needThree", nil, "Earn three stars on the rank below first."), 2.5)
    end
  end

  -- ------- input

  local function buttonsUp(s)
    return wake and wake.stage == "awake" and not touch and not drag and not feed and not picker
  end

  local function handlePress(ev, rec, s, lx, ly)
    local pl = placement(s)
    -- asleep: a tap anywhere on it wakes it
    if wake and wake.stage ~= "awake" then
      if wake.stage == "asleep" then
        local bp = placement(s, wake.back or s.pic)
        local sx, sy = toScene(lx, ly)
        if onBody(bp, sx, sy, 1.3) then
          wake.stage, wake.t = "exclaim", 0
          G.click()
        end
      end
      return
    end
    if feed then return end
    -- the picker takes every press while it is up
    if picker then
      if inBox("e", lx, ly, 6) then rec.amieBack = true; return end
      if P and inBox("2", lx, ly, 6) and (picker.stage == "badge" and picker.game > 1 or picker.stage == "diff" and picker.diff > 1) then
        rec.amieArrow = -1; return
      end
      if P and inBox("g", lx, ly, 6) and (picker.stage == "badge" and picker.game < 3 or picker.stage == "diff" and picker.diff < 4) then
        rec.amieArrow = 1; return
      end
      if picker.stage == "badge" then
        for i = 1, 3 do if inBox(BADGE[i], lx, ly) then rec.amieBadge = i; return end end
      else
        for i = 1, 4 do if inBox(PLATE[i], lx, ly) then rec.amieDiff = i; return end end
      end
      return
    end
    -- the drawer: a press on its row is a scroll (sideways) or, on a puff, a pull (down) -
    -- decided as the finger moves (handleMove)
    if s.tool == "beans" and strip.open > 0.9 then
      if inBox("6", lx, ly, 4) then rec.amieButton = "puff"; buzz("tick"); return end
      if inStripRow(lx, ly) then
        local i, kinds = kindAt(s, lx, ly)
        rec.amieStrip = { x = lx, y = ly, scroll = strip.scroll, kind = i and kinds[i].id or nil,
          lastX = lx, lastT = now() }
        strip.vel = 0
        return
      end
    end
    -- the buttons (each ticks as it is pressed: the picker's or drawer's own sound comes later)
    if buttonsUp(s) or s.tool == "beans" then
      if inBox("6", lx, ly, 4) then rec.amieButton = "puff"; buzz("tick"); return end
      if s.tool ~= "beans" and inBox("8", lx, ly, 4) then rec.amieButton = "play"; buzz("tick"); return end
      if s.tool ~= "beans" and inBox("4", lx, ly, 4) then rec.amieButton = "back"; buzz("tick"); return end
    end
    -- the Pokemon (or a still finger off it: a high-five)
    local sx, sy = toScene(lx, ly)
    rec.amieBody = true
    rec.lastX, rec.lastY = lx, ly
    -- a second press on the body within HIT.TICKS of the first is a hit
    if onBody(pl, sx, sy, 1.2) then
      local t = now()
      if lastPress and t - lastPress <= Rules.ticks(Rules.N.HIT.TICKS) then
        lastPress = nil
        G.hit()
        setHand("hit", lx, ly)
        showEmote("emote/angry", 1.0)
        return
      end
      lastPress = t
    end
    if onBody(pl, sx, sy, 1.2) and now() < petLock then return end
    if onBody(pl, sx, sy, 1.2) then
      touch = { id = ev.id, x = lx, y = ly, sx = sx, sy = sy, t = now() }
      want.z, want.fx, want.fy, want.px, want.py = ZOOM_TOUCH, sx, sy, lx, ly
      setHand("pet", lx, ly)
    elseif G.canHighFive() then
      holdFive = { id = ev.id, startT = now(), x = lx, y = ly }
      setHand("five", lx, ly)
    end
  end

  local function handleMove(ev, rec, s, lx, ly)
    if drag and drag.id == ev.id then drag.x, drag.y = lx, ly; return end
    local sr = rec.amieStrip
    if sr then
      local dx, dy = lx - sr.x, ly - sr.y
      if not sr.mode then
        -- down (or more down than across) on a puff pulls it out; across scrolls
        if sr.kind and (dy > 10 or (math.abs(dy) > 8 and math.abs(dy) > math.abs(dx))) then sr.mode = "pull"
        elseif math.abs(dx) > 6 then sr.mode = "scroll" end
      end
      if sr.mode == "pull" then
        drag = { kind = sr.kind, x = lx, y = ly, id = ev.id }
        rec.amieStrip = nil
        buzz("tick")
      elseif sr.mode == "scroll" then
        strip.dragging, strip.target = true, nil
        local x0, x1 = stripGeom()
        local top = maxScroll(#stripKinds(s), x0, x1)
        local want = sr.scroll - dx
        -- a little give past the ends, pulled back on release
        if want < 0 then want = want * 0.35 elseif want > top then want = top + (want - top) * 0.35 end
        strip.scroll = want
        local t = now()
        if t > sr.lastT then strip.vel = -(lx - sr.lastX) / (t - sr.lastT) end
        sr.lastX, sr.lastT = lx, t
      end
      return
    end
    if holdFive and holdFive.id == ev.id then
      holdFive.x, holdFive.y = lx, ly
      if hand then hand.x, hand.y = lx, ly end
    end
    if not rec.amieBody or not touch then return end
    rec.lastX, rec.lastY = lx, ly
    -- where the finger is; the petting itself is counted each frame (update)
    touch.lx, touch.ly = lx, ly
    if hand then hand.x, hand.y = lx, ly end
    local want = touch.dislike and "dislike" or "pet"
    if hand and hand.kind ~= want and not hand.untilT then setHand(want, lx, ly) end
  end

  local function handleRelease(ev, rec, s, lx, ly)
    -- a held puff let go of: back on the puff button (or the drawer) it goes back in the jar if
    -- no bite has been taken; anywhere else it falls off the screen and is lost (the rest of a
    -- bitten one too)
    if drag and drag.id == ev.id then
      local d = drag
      drag = nil
      local home = inBox("6", lx, ly, 10) or (s.tool == "beans" and inStripRow(lx, ly))
      if feed and s.feeding then
        if home and G.feedCancel() then
          G.click()
        else
          G.feedDrop()
          fall(d.kind, lx, ly)
        end
        feed = nil
        want.z, want.fx, want.fy, want.px, want.py = 1, 160, LH / 2, 160, LH / 2
      elseif not home and not feed then
        if G.dropPuff(d.kind) then fall(d.kind, lx, ly) end
      end
      return
    end
    if rec.amieStrip then
      -- a scroll ends: its momentum carries on (update); a press that never moved does nothing
      rec.amieStrip = nil
      strip.dragging = false
      return
    end
    local wasTouch = touch and touch.id == ev.id
    if wasTouch then
      touch = nil
      want.z = 1
    end
    if rec.amieBody and G.petLift then G.petLift() end
    if holdFive and holdFive.id == ev.id then holdFive = nil; hand = nil end
    if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0) then
      local GA = Games()
      if rec.amieButton == "puff" and inBox("6", lx, ly, 6) then
        if s.tool == "beans" then G.selectTool("beans")
        elseif Rules.jarTotal(s.puffs) == 0 then G.say("No Poke Puffs left.", 1.5)
        elseif not Rules.canEat(s.national) then G.say(("%s can't eat Poke Puffs."):format(s.name), 1.5)
        else G.selectTool("beans") end
      elseif rec.amieButton == "play" and inBox("8", lx, ly, 6) then
        if G.showGames() then openPicker(s) end
      elseif rec.amieButton == "back" and inBox("4", lx, ly, 6) then
        G.back()
      elseif rec.amieBack and picker then
        if picker.stage == "diff" then picker.stage = "badge"; G.click()
        else G.back() end
      elseif rec.amieArrow and picker then
        if picker.stage == "badge" then picker.game = math.max(1, math.min(3, picker.game + rec.amieArrow))
        else picker.diff = math.max(1, math.min(4, picker.diff + rec.amieArrow)) end
        G.click()
      elseif rec.amieBadge and picker and inBox(BADGE[rec.amieBadge], lx, ly) then
        if rec.amieBadge == picker.game then startDiff(rec.amieBadge)
        else picker.game = rec.amieBadge; G.click() end
      elseif rec.amieDiff and picker and GA and inBox(PLATE[rec.amieDiff], lx, ly) then
        pickDiff(rec.amieDiff)
      elseif rec.amieBody and wasTouch then
        -- a tap is not petting (the game counts only a moving finger): the hand's sparkle
        setHand("tap", lx, ly)
      end
    end
    if hand and not hand.untilT and not touch and not holdFive then hand = nil end
    rec.amieButton, rec.amieBody, rec.amieStrip, rec.amieBack, rec.amieArrow, rec.amieBadge, rec.amieDiff =
      nil, nil, nil, nil, nil, nil, nil
  end

  function app:pointer(ev, rec)
    local s = G.session
    if not (s and s.mode == "play") then return end
    screen()
    lastActive = now()
    if wake and wake.stage == "dozing" then
      -- woken from its doze: it faces you again, no other work for this touch
      if ev.phase == "pressed" then wake.stage, wake.t = "awake", 0; showEmote("emote/smile", 0.8) end
      return
    end
    local lx, ly = toLyt(ev.x, ev.y)
    if ev.phase == "pressed" then handlePress(ev, rec, s, lx, ly)
    elseif ev.phase == "moved" then handleMove(ev, rec, s, lx, ly)
    else handleRelease(ev, rec, s, lx, ly) end
  end

  -- ------- update

  local function ease(cur, target, k) return cur + (target - cur) * k end

  function app:update(dt)
    dt = dt or 0
    local s = G.session
    screen()
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + dt
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vy = p.vy + ((p.kind == "heart" or p.kind == "note" or p.kind == "zzz") and -10 or 60) * dt
      if p.age >= p.life then table.remove(particles, i) end
    end
    if hand then
      hand.t = hand.t + dt
      if hand.untilT and now() > hand.untilT then hand = touch and { kind = "pet", t = 0, x = hand.x, y = hand.y } or nil end
    end
    if emote and now() > emote.untilT then emote = nil end
    if flash then flash.t = flash.t + dt; if flash.t >= flash.dur then flash = nil end end
    -- puffs let go of tumble off the bottom
    for i = #falling, 1, -1 do
      local f = falling[i]
      f.vy = f.vy + 900 * dt
      f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
      f.rot = f.rot + (f.vx >= 0 and 6 or -6) * dt
      if f.y > LH + 60 then table.remove(falling, i) end
    end

    if not s then app.live = false; return end
    -- a fresh visit to PLAY (a new session, or from the room) starts with its back turned
    if s.mode == "play" and (not wake or wake.session ~= s or (lastMode ~= "play" and lastMode ~= "game")) then
      local back = host.backPic and host.backPic(s.mon) or nil
      wake = { session = s, stage = back and "asleep" or "awake", t = 0, back = back }
      lastActive = now()
      petLock = 0
      lastPress = nil
      fiveLeft = Rules.ticks(Rules.highFiveTicks(s.meters and s.meters.affection or 0))
      if G.resetPetting then G.resetPetting() end
      -- content and full on entering: it dozes off at once (once a visit)
      local m = s.meters or {}
      wake.sated = (m.enjoyment or 0) >= Rules.IDLE.SATED and (m.fullness or 0) >= Rules.IDLE.SATED
      view.z, want.z = 1, 1
      particles, feed, drag, touch, hand, picker, jump = {}, nil, nil, nil, nil, nil, nil
      falling = {}
      strip.open, strip.scroll, strip.vel = 0, 0, 0
      if s.tool == "games" then openPicker(s) end
    end
    -- back from a game: the picker is on the badges again, at the game just played
    if lastMode == "game" and s.mode == "play" and picker then picker.stage = "badge" end
    lastMode = s.mode
    if s.mode ~= "play" then app.live = s.mode ~= "home"; return end

    -- the wake: "!", the flash, then it faces you
    if wake.stage == "exclaim" then
      wake.t = wake.t + dt
      if wake.t >= 0.7 then wake.stage, wake.t = "flash", 0; flash = { t = 0, dur = 0.5 } end
    elseif wake.stage == "flash" then
      wake.t = wake.t + dt
      if wake.t >= 0.25 then
        wake.stage, wake.t = "awake", 0
        -- unwell (a status condition): it cannot play; it shivers three times, then its ball
        if s.status then
          wake.stage = "sick"
          G.say(("%s doesn't seem to be feeling well..."):format(s.name or "It"), SICK_S)
        end
        if wake.sated then wake.sated = nil; lastActive = now() - idleS() end
        -- it turns to face you
        if not s.status then buzzPattern("happy") end
        local pl = placement(s)
        spawn("note", pl.headX - 30, pl.headY, 2)
        spawn("note", pl.headX + 30, pl.headY, 1)
        if host.playCry then pcall(host.playCry, s.mon) end
      end
    end

    -- left alone: it dozes off, then the room (anything under way keeps it awake)
    if wake.stage == "awake" then
      if touch or drag or feed or picker or (s.tool ~= nil) then lastActive = now() end
      if now() - lastActive >= idleS() then wake.stage, wake.t, wake.zAt = "dozing", 0, 0 end
    elseif wake.stage == "dozing" then
      wake.t = wake.t + dt
      wake.zAt = wake.zAt - dt
      if wake.zAt <= 0 then
        wake.zAt = IDLE.Z_EVERY
        local pl = placement(s)
        particles[#particles + 1] = { kind = "zzz", x = pl.headX + 18, y = pl.headY - 6, vx = 10, vy = -18,
          life = 1.6, age = 0, size = 7 + math.random() * 3 }
      end
      if wake.t >= dozeS() then wake.stage, wake.t = "ball", 0 end
    elseif wake.stage == "sick" then
      wake.t = wake.t + dt
      if wake.t >= SICK_S then wake.stage, wake.t = "ball", 0 end
    elseif wake.stage == "ball" then
      -- back into its ball, then the room
      wake.t = wake.t + dt
      if wake.t >= Rules.IDLE.BALL_S then
        wake = nil
        if G.idleToRoom then G.idleToRoom() end
        return
      end
    end

    -- petting, counted each frame a finger is on it (G.petTouch / G.petEffect, the game's ticks)
    if touch and wake.stage == "awake" then
      local pl = placement(s)
      local lx, ly = touch.lx or touch.x, touch.ly or touch.y
      local mx, my = math.abs(lx - (touch.px or lx)), math.abs(ly - (touch.py or ly))
      touch.px, touch.py = lx, ly
      -- (layout units are the touch screen's 320x240 px)
      local moving = dt > 0 and math.max(mx, my) > Rules.PET.MOVE_PX * Rules.PET.TICK_HZ * dt
      local sx, sy = toScene(lx, ly)
      if onBody(pl, sx, sy, 1.2) then
        touch.offT = 0
        local bx, by = toBody(pl, sx, sy)
        local zone = Petting.zoneAt(bx, by)
        local spot, effect = Petting.spot(s.national, zone)
        if spot == "effect" then
          local r = G.petEffect(dt, effect)
          if r then hitEffect(effect, lx, ly) end
          if r == "recoil" then
            buzzPattern("hurt")
            showEmote("emote/angry", 1.0)
            G.bump(-0.12, 0)
            endTouch(1.0)
          end
        else
          -- feedback while it builds: a stroke that moves makes it wriggle, with a note now
          -- and then (a heart on a favourite spot); a disliked spot turns the hand and makes
          -- it flinch
          touch.dislike = spot == "disfavored"
          if moving then
            touch.fbT = (touch.fbT or 0) + dt
            if touch.dislike then
              life.flinch = 1
              -- a disliked spot knocks twice, now and then while the finger stays on it
              if touch.fbT >= 0.6 or not touch.knocked then
                touch.fbT, touch.knocked = 0, true
                buzzPattern("bad")
              end
            else
              life.stroke = 1
              if touch.fbT >= 0.5 then
                touch.fbT = 0
                spawn(spot == "favored" and "heart" or "note", pl.headX + (math.random() - 0.5) * 40, pl.headY - 6, 1)
                buzz(spot == "favored" and "medium" or "light")
              end
            end
          end
          local want = touch.dislike and "dislike" or "pet"
          if hand and hand.kind ~= want and not hand.untilT then setHand(want, lx, ly) end
          local res = G.petTouch(dt, moving, spot, spot == "normal" and zone or spot)
          if res then reward(s, pl, res, lx, ly) end
        end
      else
        touch.offT = (touch.offT or 0) + dt
        if touch.offT >= Rules.ticks(Rules.PET.OFF_BODY_TICKS) and G.petLift then G.petLift() end
      end
    end

    stepLife(s, dt, placement(s))

    -- the picker follows the session (B / the return button fold it there)
    if s.tool == "games" and not picker then openPicker(s) end
    if s.tool ~= "games" and picker then picker = nil end

    -- a held puff touches the Pokemon: the meal starts (the flash, a close-up about its mouth,
    -- which stays under the finger); a refusal (full, can't eat) is said once a drag
    if drag and not feed and wake.stage == "awake" then
      local pl = placement(s)
      local sx, sy = toScene(drag.x, drag.y)
      if onBody(pl, sx, sy, 1.0) then
        if not drag.refused then
          if G.feedStart(drag.kind) then
            feed = { stage = "flash", t = 0, kind = drag.kind }
            flash = { t = 0, dur = 0.6 }
            stars = {}
            for i = 1, 10 do
              local a = i / 10 * 2 * math.pi
              stars[i] = { a = a, v = 90 + math.random() * 80, r = 6 + math.random() * 6,
                kind = (i % 2 == 0) and "lyt/amie_play/star_normal" or "lyt/amie_play/star_easy" }
            end
            want.z, want.fx, want.fy, want.px, want.py = ZOOM_EAT, pl.headX, pl.mouthY, drag.x, drag.y
          else
            drag.refused = true
            buzzPattern("bad")     -- full, or it can't eat: it turns the puff away
          end
        end
      end
    end

    -- the meal: the flash, the bites while the puff is held at the mouth, the reaction, back out
    if feed then
      feed.t = feed.t + dt
      local pl = placement(s)
      -- the mouth on screen (it moves with the view), and whether the puff is at it
      local mx = view.px + (pl.headX - view.fx) * view.z
      local my = view.py + (pl.mouthY - view.fy) * view.z
      feed.atMouth = drag ~= nil and (drag.x - mx) ^ 2 + (drag.y - my) ^ 2 <= EAT_R * EAT_R
      if feed.stage == "flash" then
        -- under the flash the mouth follows the puff, so it is at the finger when the flash clears
        if drag then want.px, want.py = drag.x, drag.y end
        if feed.t >= 0.6 then feed.stage, feed.t = "eat", 0 end
      elseif feed.stage == "eat" then
        local f = s.feeding
        if not f then
          feed.stage, feed.t = "after", 0
        elseif feed.atMouth then
          feed.bites, feed.taken = f.bites, f.taken
          local what, hearts = G.feedHold(dt)
          if what == "bite" then
            spawn("crumb", pl.headX, pl.mouthY, 3)
            buzz("medium")
            feed.taken = (s.feeding and s.feeding.taken) or feed.taken
          elseif what == "done" then
            feed.taken = feed.bites
            drag = nil      -- eaten: the finger holds nothing now
            life.excite = 1
            buzzPattern("happy")
            if (hearts or 0) >= 2 then
              spawn("heart", pl.headX, pl.headY - 10, 5)
              showEmote("emote/love", 1.6)
            else
              spawn("note", pl.headX, pl.headY - 10, 3)
              showEmote("emote/happy", 1.4)
            end
            feed.stage, feed.t = "after", 0
          end
        end
      elseif feed.stage == "after" and feed.t >= 1.4 then
        feed = nil
        want.z, want.fx, want.fy, want.px, want.py = 1, 160, LH / 2, 160, LH / 2
      end
    end

    -- the view
    local k = 1 - math.exp(-EASE * dt)
    view.z = ease(view.z, want.z, k)
    view.fx, view.fy = ease(view.fx, want.fx, k), ease(view.fy, want.fy, k)
    view.px, view.py = ease(view.px, want.px, k), ease(view.py, want.py, k)

    -- the strip and the picker's panes
    strip.open = ease(strip.open, (s.tool == "beans" and not feed) and 1 or 0, 1 - math.exp(-10 * dt))
    -- the drawer's scroll: momentum after a flick, then eased back inside its ends
    if s.tool == "beans" then
      local x0, x1 = stripGeom()
      local top = maxScroll(#stripKinds(s), x0, x1)
      if not strip.dragging then
        strip.scroll = strip.scroll + strip.vel * dt
        strip.vel = strip.vel * math.exp(-5 * dt)
        if math.abs(strip.vel) < 5 then strip.vel = 0 end
        if strip.scroll < 0 then strip.scroll = ease(strip.scroll, 0, 1 - math.exp(-14 * dt)); strip.vel = math.max(0, strip.vel)
        elseif strip.scroll > top then strip.scroll = ease(strip.scroll, top, 1 - math.exp(-14 * dt)); strip.vel = math.min(0, strip.vel) end
        if strip.target then
          strip.scroll = ease(strip.scroll, strip.target, 1 - math.exp(-14 * dt))
          if math.abs(strip.scroll - strip.target) < 0.5 then strip.target = nil end
        end
      end
    end
    local kp = 1 - math.exp(-16 * dt)
    pv.tab = ease(pv.tab, picker and 105 or 145, kp)
    if picker then
      pv.cont = ease(pv.cont, picker.stage == "diff" and 200 or 0, kp)
      pv.badges = ease(pv.badges, -200 * (picker.game - 1), kp)
      pv.plates = ease(pv.plates, -200 * (picker.diff - 1), kp)
    end

    -- the high-five: a finger held off the Pokemon; once the hand is out (POSE_TICKS) the
    -- countdown runs, then it reaches for the hand, and a new countdown is rolled
    if holdFive and now() - holdFive.startT >= Rules.ticks(Rules.N.HIGH_FIVE.POSE_TICKS) then
      fiveLeft = fiveLeft - dt
      if fiveLeft <= 0 then
        local hx, hy = toScene(holdFive.x, holdFive.y)
        holdFive = nil
        if G.highFive() then
          -- it leaps at the hand (drawMon), the slap at the top of the jump, then back down
          jump = { t = 0, dur = JUMP_S, hx = hx, hy = hy, lx = hand and hand.x, ly = hand and hand.y }
          showEmote("emote/laugh", 1.5)
        else
          hand = nil
        end
        fiveLeft = Rules.ticks(Rules.highFiveTicks(s.meters and s.meters.affection or 0))
      end
    end
    if jump then
      jump.t = jump.t + dt
      if not jump.slapped and jump.t >= jump.dur * JUMP_PEAK then
        jump.slapped = true
        spawn("sparkle", jump.hx, jump.hy, 8)
        buzz("strong")
        if jump.lx then setHand("hit", jump.lx, jump.ly) end
      end
      if jump.t >= jump.dur then
        jump = nil
        if hand and hand.kind == "five" then hand = nil end
      end
    end
    -- milestones the session reported
    for _, ev in ipairs(G.takeEvents()) do
      if ev.kind == "dance" then
        dance = { cries = ev.cries, t = 0, next = 0 }
      elseif ev.kind == "gift" then
        G.say(("%s wants to give you something!"):format(s.name), 3)
        showEmote("emote/love", 2)
        buzzPattern("big")
      end
    end
    if dance then
      dance.t = dance.t + dt
      if dance.t >= dance.next then
        dance.next = dance.next + 0.6
        dance.cries = dance.cries - 1
        G.bump(0.15, 12)
        buzz("medium")       -- each step of its dance
        local pl = placement(s)
        spawn("heart", pl.headX, pl.headY - 20, 4)
        if dance.cries <= 0 then dance = nil end
      end
    end
    app.live = true
  end

  -- ------- drawing: the scene (scene units, under the view)

  local skyQuad, grassQuad = nil, nil
  local function hash(i, k) return (math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end

  local function drawSky(G2)
    local sky = G.playSkyImage and G.playSkyImage()
    if sky then
      -- the art's left part, clear of the rainbow (it starts at x 1232 of 1920), its lower end
      local iw, ih = sky:getDimensions()
      local cw = iw * 1216 / 1920
      local chh = math.min(ih, cw * LH / 320)
      if not skyQuad or app.skyLH ~= LH then
        skyQuad = love.graphics.newQuad(0, ih - chh, cw, chh, iw, ih)
        app.skyLH = LH
      end
      G2.setColor(1, 1, 1, 1)
      G2.draw(sky, skyQuad, 0, 0, 0, 320 / cw, LH / chh)
    else
      G2.setColor(0.25, 0.55, 0.95, 1)
      G2.rectangle("fill", 0, 0, 320, LH)
    end
  end

  local function drawScene(G2, t)
    drawSky(G2)
    local hz = LH - 240 + 240 * HORIZON
    -- the big cumulus behind the bushes, right; a smaller one left
    local cu = art("scene/cumulus")
    if cu then
      local cw, ch = cu:getDimensions()
      G2.setColor(1, 1, 1, 1)
      local k = 230 / cw
      G2.draw(cu, 330, hz + 8, 0, -k, k, 0, ch)
      local k2 = 150 / cw
      G2.setColor(1, 1, 1, 0.9)
      G2.draw(cu, -20, hz + 6, 0, k2, k2, 0, ch)
    end
    -- the bush line along the horizon
    local bu = art("scene/bushes")
    if bu then
      local bw, bh = bu:getDimensions()
      local k = 170 / bw
      G2.setColor(1, 1, 1, 1)
      for i = 0, 2 do
        G2.draw(bu, -30 + i * 150, hz + 14, 0, k * (i == 1 and -1 or 1), k, i == 1 and bw or 0, bh)
      end
    end
    -- the lawn, a little lighter in soft ovals
    local gr = art("scene/grass")
    local top = hz + 6
    if gr then
      if not grassQuad then
        gr:setWrap("repeat", "repeat")
        grassQuad = love.graphics.newQuad(0, 0, 320 * 2, (LH - top) * 2 + 400, gr:getDimensions())
      end
      G2.setColor(1, 1, 1, 1)
      G2.draw(gr, grassQuad, 0, top, 0, 0.5, 0.5)
    else
      G2.setColor(0.35, 0.78, 0.3, 1)
      G2.rectangle("fill", 0, top, 320, LH - top)
    end
    for i = 1, 9 do
      local row = hash(i, 1)
      local y = top + 8 + row * (LH - top - 10)
      local rx = 10 + 26 * row
      G2.setColor(0.75, 1, 0.55, 0.16)
      G2.ellipse("fill", 320 * hash(i, 2), y, rx, rx * 0.32)
    end
    -- soap bubbles drifting up
    local bub = art("scene/bubbles")
    for i = 1, 8 do
      local r = 3 + 5 * hash(i, 5)
      local span = LH + 2 * r
      local y = LH + r - ((t * (10 + 12 * hash(i, 6)) + span * hash(i, 7)) % span)
      local x = 320 * hash(i, 8) + math.sin(t * 1.2 + i) * 5
      if bub then
        local bw, bh = bub:getDimensions()
        if not app.bubbleQuad then app.bubbleQuad = love.graphics.newQuad(0, bh / 2, bw / 4, bh / 2, bw, bh) end
        G2.setColor(1, 1, 1, 0.8)
        G2.draw(bub, app.bubbleQuad, x, y, 0, 2 * r / (bw / 4), 2 * r / (bw / 4), bw / 8, bh / 4)
      end
    end
  end

  local function drawMon(G2, s, t)
    local asleep = wake and (wake.stage == "asleep" or wake.stage == "exclaim" or wake.stage == "flash") and wake.back
    local pic = asleep and wake.back or s.pic
    local pl = placement(s, pic)
    if not pl.img then
      G2.setColor(0.9, 0.75, 0.3, 1)
      G2.circle("fill", pl.cx, pl.cy, 50, 32)
      return pl
    end
    -- the shadow
    G2.setColor(0, 0.2, 0, 0.22)
    G2.ellipse("fill", pl.x, pl.y + 2, pl.rx * 0.9, 7)
    local sx = 1 + (s.anim.squash or 0)
    local sy = 1 - (s.anim.squash or 0)
    local bounce = (s.anim.bounce or 0) * 2
    local dx, lift, tilt = 0, 0, 0
    if asleep then
      -- its back turned: a slow, deep breath
      tilt = math.sin(t * 1.6) * 0.03
      local b = math.sin(t * 1.4) * 0.02
      sx, sy = sx - b * 0.6, sy + b
    else
      local lsx, lsy
      dx, lift, tilt, lsx, lsy = lifeMotion(s, t, pl)
      sx, sy = sx * lsx, sy * lsy
      -- the high five: out to the hand by the peak (eased out), back to its spot after
      if jump then
        local u = jump.t / jump.dur
        local f = u < JUMP_PEAK and math.sin(u / JUMP_PEAK * math.pi / 2)
          or math.cos((u - JUMP_PEAK) / (1 - JUMP_PEAK) * math.pi / 2)
        local ox = (jump.hx - pl.headX) * JUMP_REACH * f
        local oy = (jump.hy - pl.headY) * JUMP_REACH * f
        dx = dx + ox
        lift = lift - oy + JUMP_HOP * f
        tilt = tilt + (ox >= 0 and 1 or -1) * 0.18 * f
        -- stretched as it springs, squashed as it lands
        local land = (u > 0.85) and math.sin((u - 0.85) / 0.15 * math.pi) * 0.08 or 0
        sx, sy = sx * (1 - 0.06 * f + land), sy * (1 + 0.08 * f - land)
      end
    end
    G2.setColor(1, 1, 1, 1)
    drawPixel(pl.img, pl.x + dx, pl.y - bounce - lift, tilt, pl.k * sx, pl.k * sy, (pl.b.x0 + pl.b.x1) / 2, pl.b.y1)
    return pl
  end

  local function drawParticle(G2, p)
    local f = 1 - p.age / p.life
    if p.kind == "heart" then
      local img = art("lyt/amie_room/particle_01") or art("fx/heart")
      if img then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, f); G2.draw(img, p.x, p.y, 0, 22 / iw, 22 / ih, iw / 2, ih / 2); return
      end
      G2.setColor(0.95, 0.35, 0.5, f)
      G2.circle("fill", p.x, p.y, p.size, 10)
    elseif p.kind == "note" then
      local img = art("fx/note")
      if img then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, f); G2.draw(img, p.x, p.y, 0, 22 / iw, 22 / ih, iw / 2, ih / 2); return
      end
      G2.setColor(1, 0.8, 0.2, f)
      G2.circle("fill", p.x, p.y, 4, 8)
    elseif p.kind == "zzz" then
      -- a "z" drawn as three strokes, white on a dark edge
      local r = p.size
      local pts = { p.x - r, p.y - r, p.x + r, p.y - r, p.x - r, p.y + r, p.x + r, p.y + r }
      G2.setLineWidth(r * 0.5)
      G2.setColor(0.15, 0.2, 0.35, f)
      G2.line(pts)
      G2.setLineWidth(r * 0.28)
      G2.setColor(1, 1, 1, f)
      G2.line(pts)
      G2.setLineWidth(1)
    elseif p.kind == "sparkle" then
      G2.setColor(1, 0.95, 0.5, f)
      local r = p.size
      G2.polygon("fill", p.x, p.y - r, p.x + r * 0.3, p.y, p.x, p.y + r, p.x - r * 0.3, p.y)
      G2.polygon("fill", p.x - r, p.y, p.x, p.y + r * 0.3, p.x + r, p.y, p.x, p.y - r * 0.3)
    else
      G2.setColor(0.95, 0.85, 0.7, f)
      G2.circle("fill", p.x, p.y, p.size * 0.5, 8)
    end
  end

  -- the "!" (and other words) in the room's talk bubble
  local function drawTalk(G2, x, y, sym, size)
    local bub = art("lyt/amie_room/talk_bubble_L")
    local mark = art("lyt/amie_room/" .. sym)
    size = size or 40
    if bub then
      local bw, bh = bub:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(bub, x, y, 0, size / bw, size / bh, bw / 2, bh / 2)
    end
    if mark then
      local mw, mh = mark:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(mark, x, y, 0, size / mw, size / mh, mw / 2, mh / 2)
    end
  end

  -- ------- drawing: the layout, our overrides

  local function dressPicker(s)
    local GA = Games()
    P:set("i", "visible", pv.tab < 144)
    P:set("i", "ty", pv.tab)
    P:set("23", "visible", picker ~= nil)
    P:set("e", "visible", picker ~= nil)
    if not GA then return end
    P:setText("1r", G.tx(picker and picker.stage == "diff" and "selectDiff" or "whichGame", nil,
      picker and picker.stage == "diff" and "Select a difficulty level." or "Which game do you want to play?"),
      { align = "center", valign = "center", color = { 255, 255, 255, 255 } })
    if not picker then
      P:set("2", "visible", false)
      P:set("g", "visible", false)
      return
    end
    P:set("23", "ty", pv.cont)
    P:set("21", "tx", pv.badges)
    P:set("22", "tx", pv.plates)
    -- the row that has slid off stays out of the title bar's way
    P:set("21", "visible", pv.cont < 150)
    P:set("22", "visible", pv.cont > 50)
    for i, g in ipairs(GA.GAMES) do
      P:setText(BADGE_NAME[i], GA.name(g), { align = "center", valign = "center", color = { 255, 255, 255, 255 } })
    end
    local game = GA.GAMES[picker.game]
    for d, diff in ipairs(GA.DIFFS) do
      P:setImage(PLATE[d], P:image(("play_game%02d_%s.bclim"):format(picker.game, PLATE_TEX[d])))
      P:setText(PLATE_TEXT[d], GA.diffLabel(diff), { align = "center", valign = "center", color = { 255, 255, 255, 255 } })
      local open = GA.isUnlocked(game, diff)
      P:set(PLATE[d], "alpha", open and 255 or 120)
      local best = math.floor(GA.best(game, diff) or 0)
      for j, star in ipairs(PLATE_STARS[d]) do
        P:set(star, "alpha", j <= best and 255 or 70)
      end
    end
    local first = picker.stage == "badge" and picker.game <= 1 or picker.stage == "diff" and picker.diff <= 1
    local last = picker.stage == "badge" and picker.game >= 3 or picker.stage == "diff" and picker.diff >= 4
    P:set("2", "visible", not first)
    P:set("g", "visible", not last)
  end

  local function dressStrip(s)
    local w = STRIP_W * strip.open
    P:set("2y", "visible", w > 2)
    P:set("2y", "w", w)
    -- the layout's slot panes stay hidden: the puffs are drawn by drawStrip
    for _, n in ipairs(STRIP_SLOTS) do P:set(n, "visible", false) end
  end

  -- a count in the corner of a stacked puff: white, outlined black
  local function drawCount(G2, n, x, y)
    local font = app.smallFont or app.font
    if not font then return end
    local str = tostring(n)
    local k = 11 / font:getHeight()
    local tw = font:getWidth(str) * k
    local tx, ty = x - tw, y - font:getHeight() * k
    G2.setFont(font)
    G2.setColor(0, 0, 0, 1)
    for ox = -1, 1 do
      for oy = -1, 1 do
        if ox ~= 0 or oy ~= 0 then G2.print(str, tx + ox * 0.9, ty + oy * 0.9, 0, k, k) end
      end
    end
    G2.setColor(1, 1, 1, 1)
    G2.print(str, tx, ty, 0, k, k)
  end

  -- the drawer's puffs, one per kind with its count, sliding out of the button as it opens;
  -- clipped to the drawer
  local function drawStrip(G2, s)
    if strip.open < 0.02 then return end
    local x0, x1, cy = stripGeom()
    local kinds = stripKinds(s)
    -- clipped to the drawer as far as it has opened (its window widens with it)
    local wx, _, ww = box("2y")
    local right = x1 + 2
    if wx and ww then right = math.min(right, wx + ww - 8) end
    if right <= x0 then return end
    local ax, ay = G2.transformPoint(x0 - 2, cy - PUFF_PITCH / 2)
    local bx, by = G2.transformPoint(right, cy + PUFF_PITCH / 2)
    G2.push("all")
    G2.intersectScissor(math.floor(ax), math.floor(ay), math.max(0, math.ceil(bx - ax)), math.max(0, math.ceil(by - ay)))
    for i, k in ipairs(kinds) do
      local n = k.count
      -- the one in the hand is out of the jar's count until it is offered or put back
      if drag and drag.kind == k.id and not feed then n = n - 1 end
      local x = slotX(i, x0, x1)
      local img = art(k.id)
      if img and n > 0 and x > x0 - PUFF_PITCH and x < x1 + PUFF_PITCH then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, x, cy, 0, PUFF_PX / iw, PUFF_PX / ih, iw / 2, ih / 2)
        if n > 1 then drawCount(G2, n, x + PUFF_PX / 2 + 2, cy + PUFF_PX / 2 + 2) end
      end
    end
    G2.pop()
  end

  local function dressButtons(s)
    local up = buttonsUp(s)
    local stripUp = s.tool == "beans" and not feed and not drag
    P:set("6", "visible", (up or stripUp) and true or false)
    P:set("8", "visible", up and s.tool ~= "beans" or false)
    P:set("4", "visible", up and s.tool ~= "beans" or false)
  end

  function app:draw(G2, w, h)
    local s = G.session
    setShape(h)
    local font, small
    if app.fontsFn then font, small = app.fontsFn() end
    app.font, app.smallFont = font, small
    local t = (love and love.timer and love.timer.getTime()) or 0
    G2.push()
    G2.translate(0, -bleed())
    G2.scale(L, L)
    if not s then
      drawSky(G2)
      G2.pop()
      return
    end
    -- the scene and the Pokemon, under the view
    G2.push()
    G2.translate(view.px, view.py)
    G2.scale(view.z, view.z)
    G2.translate(-view.fx, -view.fy)
    drawScene(G2, t)
    local pl = drawMon(G2, s, t)
    for _, p in ipairs(particles) do drawParticle(G2, p) end
    G2.pop()
    -- the emote beside its head, at the screen's own size whatever the view
    local ex = view.px + (pl.headX - view.fx) * view.z
    local ey = view.py + (pl.headY - view.fy) * view.z
    if wake and wake.stage == "exclaim" then
      drawTalk(G2, ex + 30, ey - 36, "talk_exc1", 34)
    elseif emote then
      local img = art(emote.id)
      if img then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, math.max(26, ex - 52), math.max(26, ey - 34), 0, 40 / iw, 40 / ih, iw / 2, ih / 2)
      end
    end

    -- the game's layout over it
    local Pl = screen()
    if Pl then
      applyShape()
      dressButtons(s)
      dressStrip(s)
      dressPicker(s)
      Pl:draw(G2)
      drawStrip(G2, s)
    end

    -- the held puff, a little larger (the game's food_scale_on), a bite smaller each bite
    if drag then
      local img = art(drag.kind)
      local frac = (feed and feed.bites and feed.bites > 0) and (feed.taken or 0) / feed.bites or 0
      if img and frac < 1 then
        local iw, ih = img:getDimensions()
        local size = 48 * (1 - 0.7 * frac)
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, drag.x, drag.y, 0, size / iw, size / ih, iw / 2, ih / 2)
      end
    end
    -- puffs let go of, tumbling away
    for _, f in ipairs(falling) do
      local img = art(f.kind)
      if img then
        local iw, ih = img:getDimensions()
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, f.x, f.y, f.rot, 44 / iw, 44 / ih, iw / 2, ih / 2)
      end
    end

    -- the hand
    if hand and not drag and not picker then
      local frames = HAND[hand.kind] or HAND.pet
      local i = math.floor(hand.t * HAND_FPS) % #frames + 1
      local img = art("lyt/amie_hand/" .. frames[i])
      if img then
        local iw, ih = img:getDimensions()
        local size = iw >= 64 and 56 or 34
        G2.setColor(1, 1, 1, 1)
        G2.draw(img, hand.x, hand.y, 0, size / iw, size / ih, iw / 2, ih / 2)
      end
    end

    -- the white flash, with stars flying out on a meal
    if flash then
      local f = flash.t / flash.dur
      local a = f < 0.5 and f * 2 or (1 - f) * 2
      G2.setColor(1, 1, 1, math.max(0, math.min(1, a)))
      G2.rectangle("fill", 0, 0, 320, LH)
      for _, st in ipairs(stars) do
        local img = art(st.kind)
        local r = st.v * flash.t
        local x, y = 160 + math.cos(st.a) * r, LH * 0.45 + math.sin(st.a) * r
        if img then
          local iw, ih = img:getDimensions()
          G2.setColor(1, 1, 1, 1 - f)
          G2.draw(img, x, y, flash.t * 4, 2 * st.r / iw, 2 * st.r / ih, iw / 2, ih / 2)
        end
      end
    end
    G2.pop()
    G2.setColor(1, 1, 1, 1)
  end

  function app:releaseAll()
    -- a puff in the hand: back in the jar if it was not bitten, else the rest is lost
    if drag and feed and G.session and G.session.feeding then
      if not G.feedCancel() then G.feedDrop() end
      feed = nil
    end
    drag = nil
    strip.dragging = false
    touch, holdFive, hand = nil, nil, nil
    want.z = feed and want.z or 1
  end

  -- the pad in PLAY (the session's layer asks first; true = handled): on the minigame picker
  -- left / right move between the games or the difficulties, A is a tap on the selected one,
  -- B steps back from the difficulties to the games (from the games G.back folds the picker);
  -- left / right scroll the open puff drawer a puff at a time
  G.playInput = function(input)
    local s = G.session
    if not (s and s.mode == "play") or not input then return false end
    local function pressed(b) return input:wasPressed(b) end
    if picker and wake and wake.stage == "awake" then
      local left, right = pressed("left"), pressed("right")
      if left or right then
        local d = left and -1 or 1
        if picker.stage == "badge" then
          local g = math.max(1, math.min(3, picker.game + d))
          if g ~= picker.game then picker.game = g; G.click() end
        else
          local i = math.max(1, math.min(4, picker.diff + d))
          if i ~= picker.diff then picker.diff = i; G.click() end
        end
        return true
      end
      if pressed("a") then
        if picker.stage == "badge" then startDiff(picker.game) else pickDiff(picker.diff) end
        return true
      end
      if pressed("b") and picker.stage == "diff" then
        picker.stage = "badge"
        G.click()
        return true
      end
      return false
    end
    -- A wakes it (asleep, its back turned; or dozing off), as a tap on it does; awake with
    -- nothing open, A opens the minigame picker (the Play button). SELECT opens and closes the
    -- puff drawer (the puff button).
    if wake and pressed("a") then
      if wake.stage == "asleep" then
        wake.stage, wake.t = "exclaim", 0
        G.click()
        return true
      elseif wake.stage == "dozing" then
        wake.stage, wake.t = "awake", 0
        lastActive = now()
        showEmote("emote/smile", 0.8)
        return true
      elseif wake.stage == "awake" and not s.tool and not feed and not drag and not touch then
        G.click()
        if G.showGames() then openPicker(s) end
        return true
      end
    end
    if pressed("select") and wake and wake.stage == "awake" and not feed and not drag and not picker then
      if s.tool == "beans" then G.selectTool("beans")
      elseif Rules.jarTotal(s.puffs) == 0 then G.say("No Poke Puffs left.", 1.5)
      elseif not Rules.canEat(s.national) then G.say(("%s can't eat Poke Puffs."):format(s.name), 1.5)
      else G.selectTool("beans") end
      G.click()
      return true
    end
    if s.tool == "beans" and strip.open > 0.5 and not feed then
      local left, right = pressed("left"), pressed("right")
      if left or right then
        local x0, x1 = stripGeom()
        local top = maxScroll(#stripKinds(s), x0, x1)
        local from = strip.target or strip.scroll
        strip.target = math.max(0, math.min(top, from + (left and -1 or 1) * PUFF_PITCH))
        strip.vel = 0
        return true
      end
    end
    return false
  end
  -- switched away (a game, the room): app:update stops running meanwhile, so the mode it is
  -- leaving for is noted here (the session sets it before the switch); coming back from a
  -- game puts the picker on its badges, from the room turns the Pokemon's back again
  function app.leave()
    app:releaseAll()
    local s = G.session
    if s then lastMode = s.mode end
  end

  -- ------- for the drivers and tests: points in app space

  local function centre(name)
    local bx, by, bw, bh = box(name)
    if not bx then return nil end
    return fromLyt(bx + bw / 2, by + bh / 2)
  end
  function app.tapPoint(what, i)
    local s = G.session
    if not screen() or not s then return nil end
    if what == "puff_btn" then return centre("6") end
    if what == "play_btn" then return centre("8") end
    if what == "back" then return centre(picker and "e" or "4") end
    if what == "slot" then
      -- the i-th kind in the drawer, where it is drawn now
      local x0, x1, cy = stripGeom()
      return fromLyt(slotX(i or 1, x0, x1), cy)
    end
    if what == "strip" then
      -- a point on the drawer's row between the puffs' rows (for a sideways drag)
      local x0, x1, cy = stripGeom()
      return fromLyt((x0 + x1) / 2, cy)
    end
    if what == "badge" then return centre(BADGE[i or (picker and picker.game) or 1]) end
    if what == "diff" then return centre(PLATE[i or (picker and picker.diff) or 1]) end
    if what == "arrow_l" then return centre("2") end
    if what == "arrow_r" then return centre("g") end
    if what == "pet" or what == "zone" then
      -- the Pokemon's middle, or a zone's representative point (Petting.ZONE_POINT)
      local pl = placement(s)
      local zx, zy = 0, 0
      if what == "zone" and Petting.ZONE_POINT[i] then zx, zy = Petting.ZONE_POINT[i][1], Petting.ZONE_POINT[i][2] end
      local sx, sy = pl.cx + zx * pl.rx * 0.9, pl.cy + zy * pl.ry * 0.9
      local lx, ly = view.px + (sx - view.fx) * view.z, view.py + (sy - view.fy) * view.z
      return fromLyt(lx, ly)
    end
    return nil
  end
  function app.state()
    local s = G.session
    return { wake = wake and wake.stage, zoom = view.z, strip = strip.open, scroll = strip.scroll,
      kinds = s and #stripKinds(s) or 0, held = drag and drag.kind or nil, atMouth = feed and feed.atMouth or false,
      falling = #falling, jumping = jump ~= nil,
      picker = picker and { stage = picker.stage, game = picker.game, diff = picker.diff } or nil,
      feed = feed and feed.stage, hand = hand and hand.kind, emote = emote and emote.id,
      calm = life.calm, hopping = life.hop ~= nil, excite = life.excite, locked = now() < petLock,
      fiveHeld = holdFive ~= nil, fiveLeft = fiveLeft }
  end
  function app.busy()
    return (wake and wake.stage ~= "awake" and wake.stage ~= "asleep") or flash ~= nil
      or (feed ~= nil) or math.abs(view.z - want.z) > 0.02
  end

  -- the old geometry (refresh_flow_test, emerald_shot's older shots): the two tools, and the
  -- picker's points through tapPoint
  local function tools()
    local list = { "beans" }
    if G.Games then list[#list + 1] = "games" end
    return list
  end
  app.geometry = {
    tools = tools,
    trayX = function(list, i)
      local x = app.tapPoint(list[i] == "games" and "play_btn" or "puff_btn")
      return (x or 0) - 18
    end,
    gameBadge = function(i) local x, y = app.tapPoint("badge", i); return { x = (x or 0) - 4, y = (y or 0) - 4, w = 8, h = 8 } end,
    gameDiff = function(i) local x, y = app.tapPoint("diff", i); return { x = (x or 0) - 4, y = (y or 0) - 4, w = 8, h = 8 } end,
  }

  return app
end
