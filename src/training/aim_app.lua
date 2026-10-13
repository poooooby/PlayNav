-- REGIMEN, the bottom screen while a Super-Training Regimen runs: the game's aim screen
-- (lower.bclyt in a/1/1/4, played by src/lytplayer.lua): the + field scrolling, the frame,
-- the brackets, the reticle (marker) that follows the stylus, the best time and the return
-- button. Touch anywhere to aim, hold to charge, let go to fire; blocking is L / R as in the
-- game, moving the d-pad (the top layer reads both). Without the extracted art it draws the
-- plain pad it always had. The result panel afterwards.

return function(mod, Pointer, T, Rules, Sim)
  local app = { id = "training_aim", title = "REGIMEN", live = true, hideTabs = true }
  local N = Rules.N

  function app:wantsSurface()
    local s = T.session
    return s ~= nil and (s.mode == "regimen" or s.mode == "result")
  end

  local W, H = 256, 178
  local K = 256 / 320
  local BLEED = 14
  -- where a touch aims: the field inside the brackets (layout units; the brackets stand at x 72
  -- and 248 about y 94), and the pad the drivers and the fallback drawing use (app units)
  local AIM = { cx = 160, cy = 94, rx = 100, ry = 70 }
  local PAD = { cx = AIM.cx * K, cy = AIM.cy * K - BLEED, r = AIM.ry * K }
  local BLOCK = { x = 210, y = 128, w = 42, h = 42 }
  -- the return button (pane 1m, 64x64 at 291,212)
  local EXIT = { x = (291 - 26) * K, y = (212 - 26) * K - BLEED, w = 52 * K, h = 52 * K }
  local roles = {}

  local function art(id)
    local A = app.assets
    if not A or mod.options:get("use_rom_art") == false then return nil end
    return A.image(id)
  end

  local function fonts()
    if app.fontsFn then
      local f, s = app.fontsFn()
      if f then return f, s or f end
    end
    local f = love.graphics.getFont()
    return f, f
  end

  local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

  -- the aim reach of the running regimen (a sprite balloon reaches further)
  local function reach(sim)
    if sim and sim.aimExtent then return sim:aimExtent() end
    return 1, 1
  end

  -- the pad and the top screen share their brackets: the aim screen's (aim_c, panes 1e / 1g at
  -- x 72 / 248, 90 tall about y 94 of 320x240) stand for the HUD's (bg_02, panes 5x / 5z at
  -- x 96 / 304, 110 tall about y 120 of 400x240, which the top screen shows at 0.6 across and
  -- 2/3 down: x 57.6 .. 182.4, y 43.3 .. 116.7 of 240x160). A touch maps linearly from one
  -- box to the other (and on past them), then onto the balloon's plane.
  local PADBOX = { x0 = 72, x1 = 248, y0 = 94 - 45, y1 = 94 + 45 }
  local TOPBOX = { x0 = 120 + (96 - 200) * 0.6, x1 = 120 + (304 - 200) * 0.6,
    y0 = 80 + (65 - 120) * (160 / 240), y1 = 80 + (175 - 120) * (160 / 240) }
  app.PADBOX, app.TOPBOX = PADBOX, TOPBOX

  local function clampAim(sim, ax, ay)
    local ex, ey = reach(sim)
    return math.max(-ex, math.min(ex, ax)), math.max(0, math.min(ey, ay))
  end
  -- app point -> aim (the balloon's plane), and back
  local function aimAt(sim, x, y)
    local lx, ly = x / K, (y + BLEED) / K
    local sx = TOPBOX.x0 + (lx - PADBOX.x0) / (PADBOX.x1 - PADBOX.x0) * (TOPBOX.x1 - TOPBOX.x0)
    local sy = TOPBOX.y0 + (ly - PADBOX.y0) / (PADBOX.y1 - PADBOX.y0) * (TOPBOX.y1 - TOPBOX.y0)
    return clampAim(sim, Sim.unproject(sx, sy))
  end
  local function layoutPointFor(sim, gx, gy)
    local sx, sy = Sim.project(gx, gy, 1)
    return PADBOX.x0 + (sx - TOPBOX.x0) / (TOPBOX.x1 - TOPBOX.x0) * (PADBOX.x1 - PADBOX.x0),
      PADBOX.y0 + (sy - TOPBOX.y0) / (TOPBOX.y1 - TOPBOX.y0) * (PADBOX.y1 - PADBOX.y0)
  end

  function app.geometry() return { PAD = PAD, BLOCK = BLOCK, EXIT = EXIT } end

  -- the app point for a goal in arena space (drivers aim with it)
  function app.padPointFor(gx, gy)
    local lx, ly = layoutPointFor(T.sim, gx, gy)
    return lx * K, ly * K - BLEED
  end

  -- the clock as the game writes it: 2:52.7
  local function clock(secs)
    secs = math.max(0, secs or 0)
    local m = math.floor(secs / 60)
    return ("%d:%04.1f"):format(m, secs - m * 60)
  end
  app.clockText = clock

  -- the game's screen for this regimen, or nil (no extracted art)
  local function screen()
    local sim = T.sim
    if app.screen and app.screenSim == sim then return app.screen end
    local S = T.lyt
    local P = S and S.open("st_aim", "lower.bclyt", { "st_aim" }) or nil
    if not P then return nil end
    P:play("bg_scroll", { loop = true })
    P:play("cursor", { loop = true })
    P:play("passive")
    P:play("init")
    -- the best time, under the field (text panes w and y, which the game fills)
    local s = T.session
    local rec = s and s.course and T.courseRecord and T.courseRecord(s.course.id)
    P:set("w", "visible", true)
    P:set("y", "visible", true)
    P:setText("w", T.resultText and T.resultText("bestTime") or "Best Time:", { align = "left" })
    P:setText("y", rec and rec.best and clock(rec.best) or "-:--.-", { align = "left" })
    app.screen, app.screenSim = P, sim
    app.lastT, app.live = nil, nil
    return P
  end

  function app:pointer(ev, rec)
    local s = T.session
    local sim = T.sim
    if not s then return end
    if s.mode == "result" then
      if ev.phase == "released" and Pointer.isTap(rec, 20, 1.5) then
        if T.resultNext then T.resultNext() else T.leaveResult() end
      end
      return
    end
    if not sim then return end
    local x, y = ev.x, ev.y
    local P = app.screen
    if ev.phase == "pressed" then
      if inRect(x, y, EXIT) then
        roles[ev.id] = "exit"
        if P then P:play("touch") end
        return
      end
      if not P and inRect(x, y, BLOCK) then roles[ev.id] = "block"; sim:block(); return end
      roles[ev.id] = "aim"
      sim:aim(aimAt(sim, x, y))
      sim:pressFire()
    elseif ev.phase == "moved" then
      local role = roles[ev.id]
      if role == "aim" then sim:aim(aimAt(sim, x, y)) end
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      local role = roles[ev.id]
      roles[ev.id] = nil
      if role == "aim" then
        sim:aim(aimAt(sim, x, y))
        sim:releaseFire()
      elseif role == "exit" then
        if P then P:play("release") end
        if inRect(x, y, EXIT) then T.quitRegimen() end
      end
    end
  end

  function app:releaseAll()
    local sim = T.sim
    roles = {}
    if sim then sim:releaseFire() end
  end

  function app:update(dt) end

  local function drawButton(G, r, label, font, on, dim)
    if dim then G.setColor(0.2, 0.22, 0.28, 1) elseif on then G.setColor(0.25, 0.7, 0.95, 1) else G.setColor(0.25, 0.3, 0.42, 1) end
    G.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
    G.setColor(1, 1, 1, dim and 0.4 or 0.9)
    G.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 5, 5)
    G.setFont(font)
    G.printf(label, r.x, r.y + math.floor((r.h - font:getHeight()) / 2), r.w, "center")
  end

  local function drawResult(G, s, font, small)
    local r = s.result
    G.setColor(0.09, 0.11, 0.16, 1)
    G.rectangle("fill", 0, 0, W, H)
    if not r then return end
    local ribbon = art("training/ribbon_results")
    if ribbon then
      G.setColor(1, 1, 1, 1)
      G.draw(ribbon, W / 2, 20, 0, 0.7, 0.7, 115, 22)
    else
      G.setFont(font)
      G.setColor(1, 1, 1, 1)
      G.printf("RESULTS", 0, 12, W, "center")
    end
    G.setFont(small)
    G.setColor(1, 1, 1, 1)
    local y = 44
    local function line(t)
      local _, wrapped = small:getWrap(t, W - 32)
      G.printf(t, 16, y, W - 32, "center")
      y = y + math.max(1, #wrapped) * (small:getHeight() + 1) + 2
    end
    line(r.courseName or "")
    if r.praise then
      G.setColor(1, 0.95, 0.7, 1)
      line(r.praise)
      G.setColor(1, 1, 1, 1)
    end
    if r.clear then
      line(("%s %s"):format(T.resultText("targetRemaining"), T.Draw and T.Draw.clock(r.remaining) or tostring(r.remaining)))
      line(r.medal and T.resultText("award") or T.resultText("tryTarget"))
      if r.stat then line(("%s %s +%d"):format(T.resultText("increase"), T.statWord and T.statWord(r.stat) or Rules.STAT_LABEL[r.stat], r.ev or 0)) end
      if r.statText then line(r.statText) end
    else
      line(T.resultText("failed"))
    end
    if r.bag then line(("%s %s"):format(T.resultText("bagsReceived"), T.bagName and T.bagName(r.bag) or r.bag)) end
    if r.item then line(("%s %s"):format(T.resultText("itemsReceived"), r.item.name)) end
    if r.unlockText then
      G.setColor(0.7, 0.95, 1, 1)
      line(r.unlockText)
    end
    -- the hint only when it fits; the top screen says "A: continue" either way
    if y + 2 <= H - 14 then
      G.setColor(1, 1, 1, 0.7)
      G.printf("tap to continue", 0, H - 14, W, "center")
    end
  end

  -- the game's aim screen: the field, the reticle where the aim is, the best time
  local function drawScreen(G, P, sim)
    local t = sim and sim.t or 0
    if app.lastT then P:advance(math.max(0, math.min(0.25, t - app.lastT)) * 30) end
    app.lastT = t
    -- the return button lights once play begins (passive -> active)
    local live = sim and sim.phase ~= "countdown"
    if live ~= app.live then
      app.live = live
      P:play(live and "active" or "passive")
    end
    if sim then
      local lx, ly = layoutPointFor(sim, sim.player.aim.x, sim.player.aim.y)
      P:set("12", "tx", lx - 160)
      P:set("12", "ty", 120 - ly)
    end
    G.push()
    G.translate(0, -(app.bleed or BLEED))
    G.scale(K, K)
    P:draw(G)
    G.pop()
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    if not s then return end
    if s.mode == "result" then
      local Rs = T.results
      if Rs and Rs.list and Rs.bottom then
        G.push()
        G.translate(0, -(app.bleed or BLEED))
        G.scale(K, K)
        Rs.drawBottom(G)
        local v = T.transView and T.transView("bottom")
        if v and v.black and v.black > 0 then
          G.setColor(0, 0, 0, v.black)
          G.rectangle("fill", -10, -20, 340, 280)
        end
        G.pop()
        G.setColor(1, 1, 1, 1)
        return
      end
      drawResult(G, s, font, small)
      return
    end
    local sim = T.sim
    local P = screen()
    if P then drawScreen(G, P, sim); return end
    G.setColor(0.09, 0.11, 0.16, 1)
    G.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    -- the pad
    local pent = art("training/pentagon")
    if pent then
      local iw, ih = pent:getDimensions()
      G.setColor(1, 1, 1, 1)
      G.draw(pent, PAD.cx, PAD.cy, 0, (PAD.r * 2) / iw, (PAD.r * 2) / ih, iw / 2, ih / 2)
    else
      G.setColor(0.14, 0.18, 0.26, 1)
      G.circle("fill", PAD.cx, PAD.cy, PAD.r, 40)
      G.setColor(0.3, 0.4, 0.55, 0.8)
      G.circle("line", PAD.cx, PAD.cy, PAD.r, 40)
      G.circle("line", PAD.cx, PAD.cy, PAD.r * 0.5, 30)
      G.line(PAD.cx - PAD.r, PAD.cy, PAD.cx + PAD.r, PAD.cy)
      G.line(PAD.cx, PAD.cy - PAD.r, PAD.cx, PAD.cy + PAD.r)
    end
    if sim then
      -- the goals mirrored on the pad, so the pad reads like the bot plane
      for _, g in ipairs(sim.goals) do
        local gx, gy = sim:goalPos(g)
        local px, py = app.padPointFor(gx, gy)
        if g.kind == "chance" then G.setColor(1, 0.3, 0.3, 0.8) elseif g.kind == "fading" then G.setColor(1, 0.9, 0.3, 0.8)
        elseif g.kind == "marker" then G.setColor(1, 0.85, 0.2, 0.9) else G.setColor(1, 1, 1, 0.7) end
        G.circle("line", px, py, 7, 12)
      end
      -- the reticle and the charge
      local rx, ry = app.padPointFor(sim.player.aim.x, sim.player.aim.y)
      local stage = sim:chargeStage()
      if sim.player.charging then
        local f = math.min(1, sim.player.chargeT / N.CHARGE.OVER_S)
        G.setColor(stage >= 3 and 1 or 0.98, stage >= 3 and 0.3 or 0.75, 0.2, 0.9)
        G.arc("line", rx, ry, 14, -math.pi / 2, -math.pi / 2 + f * 2 * math.pi, 20)
      end
      local ring = art("training/aim")
      if ring then
        G.setColor(1, 1, 1, 1)
        G.draw(ring, rx, ry, 0, 0.6, 0.6, 24, 24)
      else
        G.setColor(1, 1, 1, 1)
        G.circle("line", rx, ry, 6, 12)
        G.line(rx - 10, ry, rx + 10, ry)
        G.line(rx, ry - 10, rx, ry + 10)
      end
      local cl, cr = art("training/cursor_left"), art("training/cursor_right")
      if cl and cr then
        G.setColor(1, 1, 1, 0.8)
        G.draw(cl, PAD.cx - PAD.r - 18, PAD.cy - 12)
        G.draw(cr, PAD.cx + PAD.r - 14, PAD.cy - 12)
      end
      -- guts and score
      G.setColor(0.98, 0.6, 0.15, 1)
      G.arc("fill", 232, 100, 9, -math.pi / 2, -math.pi / 2 + sim.guts * 2 * math.pi, 20)
      G.setColor(1, 1, 1, 0.8)
      G.circle("line", 232, 100, 10, 20)
      G.setFont(small)
      G.printf("GUTS", 214, 112, 36, "center")
      G.setColor(1, 1, 1, 0.9)
      G.printf(("%d / %d"):format(math.floor(sim.score), sim.bot and sim.bot.target or 0), PAD.cx - 70, 4, 140, "center")
      G.printf(T.Draw and T.Draw.clock(sim.remaining) or "", PAD.cx - 70, 162, 140, "center")
    end
    G.setFont(small)
    G.setColor(1, 1, 1, 0.6)
    G.printf("D-PAD: MOVE", 4, 162, 70, "left")
    local cd = sim and sim.player.shieldCd > 0
    drawButton(G, BLOCK, "BLOCK", small, sim and sim.player.shield > 0, cd)
    local ret = art("training/btn_return")
    if ret then
      G.setColor(1, 1, 1, 1)
      G.draw(ret, EXIT.x + EXIT.w - 20, EXIT.y - 2, 0, 20 / 48, 20 / 48)
      G.setFont(small)
      G.printf("EXIT", EXIT.x - 10, EXIT.y + 3, 30, "center")
    else
      drawButton(G, EXIT, "EXIT", small, false, false)
    end
    G.setColor(1, 1, 1, 1)
  end

  return app
end
