-- SUPER TRAINING, the Core Training screen on the bottom: the Pokemon beside its training
-- bag (tap the bag to hit it, tap the Pokemon to wake it), the Effort-o-Meter with the
-- total column, the party strip, and the REGIMENS / BAGS buttons.

return function(mod, Pointer, T, Rules, Radar, host)

  -- pixel art (GBA sprites, icons) through src/hd.lua: whole pixels or the sharp shader
  local function drawPixel(...)
    local HD = mod.hd
    if HD then return HD.drawPixel(...) end
    return love.graphics.draw(...)
  end
  local app = { id = "training_core", title = "SUPER TRAINING", live = true, hideTabs = true }
  local N = Rules.N

  function app:wantsSurface() return T.session ~= nil and T.session.mode == "core" end

  local W, H = 256, 178
  local PIC = { x = 10, y = 30, w = 64, h = 64 }
  local BAG = { x = 86, y = 30, w = 28, h = 62 }
  local RADAR = { cx = 180, cy = 70, r = 34 }
  local TOTAL = { x = 230, y = 34, w = 8, h = 72 }
  local REGIMENS = { x = 2, y = 142, w = 64, h = 34 }
  local BAGS = { x = 190, y = 142, w = 64, h = 34 }
  -- six 21 px slots centred in the gap between REGIMENS and BAGS
  local PARTY = { slot = 21, y = 148, h = 26 }
  PARTY.x = math.floor((REGIMENS.x + REGIMENS.w + BAGS.x) / 2 - 3 * PARTY.slot)

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

  function app.geometry()
    return { PIC = PIC, BAG = BAG, RADAR = RADAR, TOTAL = TOTAL, REGIMENS = REGIMENS, BAGS = BAGS, PARTY = PARTY,
      partySlot = function(i) return { x = PARTY.x + (i - 1) * PARTY.slot, y = PARTY.y, w = PARTY.slot, h = PARTY.h } end }
  end

  function app:pointer(ev, rec)
    local s = T.session
    if not (s and s.mode == "core") then return end
    if ev.phase ~= "released" or not Pointer.isTap(rec, 16, 1.0) then return end
    local x, y = ev.x, ev.y
    if inRect(x, y, BAG) then T.hitBag("tap"); return end
    if inRect(x, y, PIC) then
      if s.rec.resting then T.wake() else T.hitBag("tap") end
      return
    end
    if inRect(x, y, REGIMENS) then
      if T.enterCourses then T.enterCourses() end
      return
    end
    if inRect(x, y, BAGS) then T.enterBags(); return end
    local party = T.party()
    for i, p in ipairs(party) do
      local r = app.geometry().partySlot(i)
      if inRect(x, y, r) then
        T.switchTo(p.mon)
        return
      end
    end
  end

  function app:update(dt) end

  local function drawBag(G, s, font)
    local bag = s.rec.bag
    local def = bag and Rules.bag(bag.id)
    -- the hook
    G.setColor(0.3, 0.3, 0.35, 1)
    G.rectangle("fill", BAG.x + BAG.w / 2 - 1, BAG.y, 2, 10)
    local id = def and ("training/sand_bag_%02d"):format(Rules.BAG_ART[def.id] or 0) or "training/sand_bag_00"
    local img = art(id)
    local wobble = (s.anim.hit > 0) and math.sin(s.anim.t * 40) * 2 or 0
    if img then
      local iw, ih = img:getDimensions()
      local sc = math.min(BAG.w / iw, (BAG.h - 10) / ih)
      G.setColor(1, 1, 1, 1)
      G.draw(img, BAG.x + BAG.w / 2 + wobble, BAG.y + 10, 0, sc, sc, iw / 2, 0)
    else
      local rgb = (def and def.stat and T.STAT_RGB[def.stat]) or (def and { 0.6, 0.6, 0.7 }) or { 0.14, 0.14, 0.16 }
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.rectangle("fill", BAG.x + 2 + wobble, BAG.y + 10, BAG.w - 4, BAG.h - 14, 8, 8)
      G.setColor(0, 0, 0, 0.25)
      G.rectangle("line", BAG.x + 2.5 + wobble, BAG.y + 10.5, BAG.w - 5, BAG.h - 15, 8, 8)
      if def then
        G.setFont(font)
        G.setColor(1, 1, 1, 1)
        local letter = def.stat and Rules.STAT_SHORT[def.stat] or (def.label:sub(1, 1))
        G.printf(letter .. (def.size and (" " .. Rules.SIZE_LABEL[def.size]) or ""), BAG.x + wobble, BAG.y + BAG.h / 2 - 2, BAG.w, "center")
      end
    end
    G.setFont(font)
    G.setColor(1, 1, 1, 0.95)
    if bag then
      G.printf(("%d/%d"):format(bag.hits, bag.needed), BAG.x - 10, BAG.y + BAG.h + 2, BAG.w + 20, "center")
    else
      G.printf("TAP", BAG.x - 10, BAG.y + BAG.h + 2, BAG.w + 20, "center")
    end
  end

  local function drawButton(G, r, label, font, active)
    if active then G.setColor(0.2, 0.6, 0.85, 1) else G.setColor(0.25, 0.3, 0.42, 1) end
    G.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
    G.setColor(1, 1, 1, 0.9)
    G.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
    G.setFont(font)
    G.printf(label, r.x, r.y + math.floor((r.h - font:getHeight()) / 2), r.w, "center")
  end

  function app:draw(G, w, h)
    local s = T.session
    local font, small = fonts()
    G.setColor(0.09, 0.11, 0.16, 1)
    G.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    G.setColor(0.13, 0.17, 0.25, 1)
    G.rectangle("fill", 0, 104, w, 40)
    if not s then
      G.setFont(font)
      G.setColor(1, 1, 1, 0.8)
      G.printf("No session", 0, h / 2 - 6, w, "center")
      return
    end
    -- name line
    G.setFont(font)
    G.setColor(1, 1, 1, 1)
    local tag = s.rec.supremely and "  SUPREMELY TRAINED" or (s.rec.fully and "  FULLY TRAINED" or "")
    G.print(s.name .. tag, 6, 4)
    local shotImg = art("training/shot_" .. (s.shot or "black"))
    if shotImg then
      G.setColor(1, 1, 1, 1)
      G.draw(shotImg, w - 26, 2, 0, 0.75, 0.75)
    else
      local rgb = T.SHOT_RGB[s.shot] or T.SHOT_RGB.black
      G.setColor(rgb[1], rgb[2], rgb[3], 1)
      G.circle("fill", w - 14, 10, 6, 16)
      G.setColor(1, 1, 1, 0.9)
      G.circle("line", w - 14, 10, 6, 16)
    end
    G.setFont(small)
    G.setColor(1, 1, 1, 0.8)
    G.printf((s.shot or "black"):upper(), w - 90, 26, 86, "right")
    -- the Pokemon
    local bounce = (s.anim.hit > 0) and 2 or 0
    G.setColor(0, 0, 0, 0.3)
    G.ellipse("fill", PIC.x + PIC.w / 2, PIC.y + PIC.h - 2, 26, 6)
    if s.pic and s.pic.image then
      G.setColor(1, 1, 1, 1)
      if s.rec.resting then
        drawPixel(s.pic.image, PIC.x + PIC.w / 2, PIC.y + PIC.h, math.pi / 2, 1, 1, (s.pic.w or 64) / 2, (s.pic.h or 64) / 2)
      else
        drawPixel(s.pic.image, PIC.x, PIC.y - bounce)
      end
    end
    -- the game's mood bubbles over the Pokemon
    local mood = s.rec.resting and "silence" or (T.refreshed() and "smile") or ((s.anim.burst or 0) > 0 and "surprise") or nil
    local bubble = mood and art("training/mood_" .. mood)
    if bubble then
      G.setColor(1, 1, 1, 1)
      G.draw(bubble, PIC.x + PIC.w - 12, PIC.y - 10, 0, 0.75, 0.75)
    elseif s.rec.resting then
      G.setFont(font)
      G.setColor(1, 1, 1, 0.9)
      G.print("...", PIC.x + PIC.w - 6, PIC.y - 2)
    elseif T.refreshed() then
      G.setFont(small)
      G.setColor(1, 0.95, 0.5, 1)
      G.print(":)", PIC.x + PIC.w - 4, PIC.y - 2)
    end
    if (s.anim.burst or 0) > 0 then
      local burst = art("training/burst")
      if burst then
        local k = 0.6 + (0.7 - s.anim.burst) * 0.8
        G.setColor(1, 1, 1, math.min(1, s.anim.burst * 3))
        G.draw(burst, BAG.x + BAG.w / 2, BAG.y + BAG.h / 2, 0, k, k, 32, 32)
      end
    end
    drawBag(G, s, small)
    -- the Effort-o-Meter on the game's canvas
    local canvas = art("training/meter_canvas")
    if canvas then
      G.setColor(1, 1, 1, 0.9)
      G.draw(canvas, RADAR.cx, RADAR.cy, 0, (RADAR.r * 2 + 28) / 128, (RADAR.r * 2 + 28) / 128, 64, 64)
    end
    Radar.draw(G, RADAR.cx, RADAR.cy, RADAR.r, { base = s.base, evs = s.evs, baseMax = 255, evMax = N.LIMITS.EV_CAP, font = small })
    local total = Rules.evTotal(s.evs)
    Radar.drawTotal(G, TOTAL.x, TOTAL.y, TOTAL.w, TOTAL.h, total, N.LIMITS.EV_TOTAL)
    G.setFont(small)
    G.setColor(1, 1, 1, 0.9)
    G.printf(("%d/%d"):format(total, N.LIMITS.EV_TOTAL), TOTAL.x - 24, TOTAL.y + TOTAL.h + 2, TOTAL.w + 32, "center")
    -- per-stat numbers under the radar
    local line = {}
    for _, k in ipairs(Rules.STATS) do line[#line + 1] = ("%s %d"):format(Rules.STAT_SHORT[k], s.evs[k] or 0) end
    G.printf(table.concat(line, "  "), 0, 120, w, "center")
    if s.rec.pending then
      G.setColor(1, 0.9, 0.5, 1)
      G.printf("NEXT REGIMEN: " .. (Rules.EFFECT_LABEL[s.rec.pending] or s.rec.pending), 0, 132, w, "center")
    end
    -- party strip
    for i, p in ipairs(T.party()) do
      local r = app.geometry().partySlot(i)
      if p.active then
        G.setColor(0.2, 0.6, 0.85, 0.9)
        G.rectangle("fill", r.x, r.y, r.w, r.h, 3, 3)
      end
      local icon = p.icon
      if icon and icon.image then
        G.setColor(1, 1, 1, p.eligible and 1 or 0.35)
        -- drawn from the frame's centre onto the slot's centre
        local q = icon.quads and (icon.quads[0] or icon.quads[1])
        local sc = 0.75
        local fw, fh = icon.w or 32, icon.h or 32
        local cx, cy = r.x + r.w / 2, r.y + r.h / 2
        if q then
          drawPixel(icon.image, q, cx, cy, 0, sc, sc, fw / 2, fh / 2)
        else
          drawPixel(icon.image, cx, cy, 0, sc, sc, fw / 2, fh / 2)
        end
      else
        G.setColor(1, 1, 1, p.eligible and 0.8 or 0.3)
        G.circle("fill", r.x + r.w / 2, r.y + r.h / 2, 6, 12)
      end
    end
    -- the game's round buttons, with a word under each
    local function roundButton(r, id, label)
      local img = art(id)
      if img then
        local iw = img:getWidth()
        G.setColor(1, 1, 1, 1)
        G.draw(img, r.x + r.w / 2, r.y + 12, 0, 24 / iw, 24 / iw, iw / 2, iw / 2)
        G.setFont(small)
        G.setColor(1, 1, 1, 0.9)
        G.printf(label, r.x - 8, r.y + 25, r.w + 16, "center")
      else
        drawButton(G, { x = r.x + 2, y = r.y + 8, w = r.w - 4, h = 22 }, label, small, false)
      end
    end
    roundButton(REGIMENS, "training/btn_regimens", "REGIMENS")
    roundButton(BAGS, "training/btn_bags", "BAGS")
    G.setColor(1, 1, 1, 1)
  end

  return app
end
