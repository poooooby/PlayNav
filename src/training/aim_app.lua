-- REGIMEN, the bottom screen while a Super-Training Regimen runs: the aiming pad (touch to
-- place the reticle and shoot, hold to charge), a BLOCK button beside L, EXIT, and the
-- result panel afterwards. Moving is the d-pad's job (the top layer reads it), never touch.
-- without a pad, EXIT, and the result panel afterwards.

return function(mod, Pointer, T, Rules, Sim)
  local app = { id = "training_aim", title = "REGIMEN", live = true, hideTabs = true }
  local N = Rules.N

  function app:wantsSurface()
    local s = T.session
    return s ~= nil and (s.mode == "regimen" or s.mode == "result")
  end

  local W, H = 256, 178
  local PAD = { cx = 112, cy = 88, r = 70 }
  local BLOCK = { x = 210, y = 128, w = 42, h = 42 }
  local EXIT = { x = 210, y = 4, w = 42, h = 16 }
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
  local function inPad(x, y) return (x - PAD.cx) ^ 2 + (y - PAD.cy) ^ 2 <= (PAD.r + 10) ^ 2 end

  -- the aim reach of the running regimen (a sprite balloon reaches further)
  local function reach(sim)
    if sim and sim.aimExtent then return sim:aimExtent() end
    return 1, 1
  end

  function app.geometry() return { PAD = PAD, BLOCK = BLOCK, EXIT = EXIT } end

  -- the pad point for a goal in arena space (drivers aim with it)
  function app.padPointFor(gx, gy)
    local sim = T.sim
    return Sim.padFromAim(gx, gy, PAD, reach(sim))
  end

  function app:pointer(ev, rec)
    local s = T.session
    local sim = T.sim
    if not s then return end
    if s.mode == "result" then
      if ev.phase == "released" and Pointer.isTap(rec, 20, 1.5) then T.leaveResult() end
      return
    end
    if not sim then return end
    local x, y = ev.x, ev.y
    if ev.phase == "pressed" then
      if inRect(x, y, EXIT) then roles[ev.id] = "exit"; return end
      if inRect(x, y, BLOCK) then roles[ev.id] = "block"; sim:block(); return end
      roles[ev.id] = "aim"
      sim:aim(Sim.aimFromPad(x, y, PAD, reach(sim)))
      sim:pressFire()
    elseif ev.phase == "moved" then
      local role = roles[ev.id]
      if role == "aim" then sim:aim(Sim.aimFromPad(x, y, PAD, reach(sim))) end
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      local role = roles[ev.id]
      roles[ev.id] = nil
      if role == "aim" then
        sim:aim(Sim.aimFromPad(x, y, PAD, reach(sim)))
        sim:releaseFire()
      elseif role == "exit" and inRect(x, y, EXIT) then
        T.quitRegimen()
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

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    if not s then return end
    if s.mode == "result" then drawResult(G, s, font, small); return end
    local sim = T.sim
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
        local px, py = Sim.padFromAim(gx, gy, PAD, reach(sim))
        if g.kind == "chance" then G.setColor(1, 0.3, 0.3, 0.8) elseif g.kind == "fading" then G.setColor(1, 0.9, 0.3, 0.8)
        elseif g.kind == "marker" then G.setColor(1, 0.85, 0.2, 0.9) else G.setColor(1, 1, 1, 0.7) end
        G.circle("line", px, py, 7, 12)
      end
      -- the reticle and the charge
      local rx, ry = Sim.padFromAim(sim.player.aim.x, sim.player.aim.y, PAD, reach(sim))
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
