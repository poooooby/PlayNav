-- An easter egg on Super Training's home screen (ours; nothing like it in the game): the Konami
-- code (up up down down left right left right B A START, read off the pad while the home screen
-- is up)
-- fades the screen to black, a red R grows in with a glint and a dark sting, and the home screen
-- comes back with a black R button in its bottom left. Until the screen is closed, that button
-- leads to an alley (src/training/rocket_scene.lua): both screens go black, the R flashes on the
-- top, the camera walks in to a street lamp and a dealer steps into its light. After his
-- greeting the top screen (a grimy brick wall) opens his shop: an R bag (+32 EVs, 12,500) and an
-- R+ bag (+64, 25,000) for each stat, bought for the player's money into a free slot of the bag
-- drawer (Rules.ROCKET_LIST: hung and punched like the stat bags). B or the red button leaves,
-- with a word from him, back to the home screen and the field.
--
--   Rk = rocket(mod, T, { host, Rules, Store, Scene })   (T = the training session, extended)
-- The rules (the code's matcher, a purchase, the lines) are pure: tests/rocket_test.lua.

return function(mod, T, deps)
  local host, Rules, Store, Scene = deps.host, deps.Rules, deps.Store, deps.Scene
  local Rk = {}
  T.rocket = Rk
  local min, max, floor, sin, pi = math.min, math.max, math.floor, math.sin, math.pi

  -- ------- the code

  Rk.KONAMI = { "up", "up", "down", "down", "left", "right", "left", "right", "b", "a", "start" }
  Rk.BUTTONS = { "up", "down", "left", "right", "b", "a", "start" }

  -- the longest start of the code that is also the end of what was entered (a KMP table), so
  -- up up up down ... still counts
  local fail = { [1] = 0 }
  do
    local K, k = Rk.KONAMI, 0
    for i = 2, #K do
      while k > 0 and K[k + 1] ~= K[i] do k = fail[k] end
      if K[k + 1] == K[i] then k = k + 1 end
      fail[i] = k
    end
  end
  function Rk.matcher() return { n = 0 } end
  -- one button pressed; true when it completes the code (the matcher starts over)
  function Rk.feed(m, btn)
    local K = Rk.KONAMI
    local n = m.n
    while n > 0 and K[n + 1] ~= btn do n = fail[n] end
    if K[n + 1] == btn then n = n + 1 end
    if n == #K then m.n = 0; return true end
    m.n = n
    return false
  end

  -- ------- the shop

  Rk.STOCK = Rules.ROCKET_LIST or {}
  function Rk.price(id) local b = Rules.bag(id); return b and b.price or nil end
  -- a purchase with `money` into the drawer `bags` (not changed): true and the money left, or
  -- false and why ("unknown", "full": no free slot, "money": not enough)
  function Rk.buy(money, bags, id)
    local price = Rk.price(id)
    if not price then return false, "unknown" end
    if Rules.inventoryFull(bags) then return false, "full" end
    money = floor(tonumber(money) or 0)
    if money < price then return false, "money" end
    return true, money - price
  end
  -- 25000 -> "25,000"
  -- (kept: the shop draws the same few amounts every frame)
  local moneyText, moneyCount = {}, 0
  function Rk.money(n)
    n = floor(tonumber(n) or 0)
    local s = moneyText[n]
    if s then return s end
    local out = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    s = (out:gsub("^,", ""))
    if moneyCount >= 64 then moneyText, moneyCount = {}, 0 end
    moneyText[n], moneyCount = s, moneyCount + 1
    return s
  end

  -- what he says (ours)
  Rk.LINES = {
    greet = { "Psst.. I think I know what you're looking for..", "Shh.. Not so loud. What do you need?",
      "You didn't see me, kid. But I see you. Looking to get strong, fast?",
      "Keep your voice down.. Heard you're after something a little extra." },
    open = { "Take a look. Cash only.", "Don't touch what you can't pay for.", "Go on, pick one." },
    sold = { "That's the good stuff, kid..", "Careful with that now.", "Pleasure doing business.",
      "Your POKeMON's gonna feel that one.", "Don't go showing that to the Professor." },
    broke = { "You're short, kid. Come back with the cash.", "No money, no bag. That's how this works." },
    full = { "Come back when you have room." },
    bye = { "If anyone asks, you didn't get this from me." },
  }
  -- a line from a list, never the one just said
  function Rk.pick(list, last, rng)
    rng = rng or math.random
    if #list <= 1 then return list[1] end
    local i
    repeat i = 1 + floor(rng() * #list) until list[i] ~= last
    return list[i]
  end
  -- the confirmation, as the game's shops ask it, with a YES / NO choice (rocket_app draws it):
  -- "\1" stands for the Pokedollar sign (the font has none; Rk.printLine draws it)
  Rk.PD = "\1"
  Rk.ASK = "You want the %s?\nIt's \1%s."

  -- ------- timing (seconds)

  -- the unlock on the home screen: to black, the R grows in, holds, the screen comes back
  Rk.UNLOCK = { FADE = 0.45, GROW = 1.1, HOLD = 0.7, BACK = 0.5 }
  -- the alley: the walk (rocket_scene's WALK.S), the dealer fading in, the typing, the shop's
  -- slide, the goodbye's wait before leaving on its own
  Rk.APPEAR_S, Rk.CPS, Rk.SHOP_S, Rk.BYE_S = 0.9, 40, 0.35, 2.5
  Rk.ROWS = 5

  function Rk.unlockTotal() local U = Rk.UNLOCK; return U.FADE + U.GROW + U.HOLD + U.BACK end

  -- the unlock's look now: black 0..1, the R's scale and alpha, the glint's place 0..1 (nil)
  function Rk.unlockView(t)
    local U = Rk.UNLOCK
    if t < U.FADE then return t / U.FADE, 0, 0 end
    t = t - U.FADE
    if t < U.GROW + U.HOLD then
      local u = min(1, t / U.GROW)
      local e = 1 - (1 - u) ^ 3
      local g = (t - U.GROW * 0.45) / (U.GROW * 0.7)
      return 1, 0.3 + 0.7 * e, e, (g >= 0 and g <= 1) and g or nil
    end
    t = t - U.GROW - U.HOLD
    local k = max(0, 1 - t / U.BACK)
    return k, 1, k
  end

  -- ------- the session's side

  local matcher = Rk.matcher()
  Rk.closeMenu = 0

  local function closeStartMenu()
    local ok, SM = pcall(require, "src.ui.game3.start_menu")
    if not (ok and type(SM) == "table") then return false end
    local okO, open = pcall(function() return SM.isOpen and SM.isOpen() end)
    if okO and open and SM.close then pcall(SM.close, true); return true end
    return false
  end

  -- the art the unlock and the alley use (src/training/ui_art.lua), made now (an update step)
  -- rather than mid-draw
  Rk.ART = { "rocket/logo", "rocket/glint", "rocket/button", "rocket/back", "rocket/up", "rocket/down",
    "rocket/panel", "rocket/red", "rocket/inset", "rocket/pill", "rocket/pill_on", "rocket/scan" }
  local function prewarm()
    local A = T.assets
    if not (A and A.image) then return false end
    for _, id in ipairs(Rk.ART) do pcall(A.image, id) end
    for _, id in ipairs(Rk.STOCK) do
      pcall(A.image, Rules.bagArt(id))
      local b = Rules.bag(id)
      if b and b.glow then pcall(A.image, "training/rbag_glow_" .. b.stat) end
    end
    return true
  end
  Rk.prewarm = prewarm

  function T.rocketUnlocked() local s = T.session; return s ~= nil and s.rocketUnlocked == true end
  -- the unlock is playing: the home screen takes no taps
  function T.rocketBusy() local s = T.session; return s ~= nil and s.anim ~= nil and s.anim.rocket ~= nil end

  function Rk.unlock()
    local s = T.session
    if not s then return end
    s.rocketUnlocked = true
    s.anim.rocket = { t = 0 }
    Rk.closeMenu = 20
    prewarm()
    if mod.haptics then mod.haptics.pattern("big") end
  end

  -- the engine's logic step (main's input.step wrap): the buttons pressed on the step before,
  -- whatever pressed them (keys, a pad, the touch pad); only on the home screen, at rest
  function T.konamiStep(input)
    if Rk.closeMenu > 0 then
      Rk.closeMenu = Rk.closeMenu - 1
      if closeStartMenu() then Rk.closeMenu = 0 end
    end
    local s = T.session
    -- the bags bought stay in the drawer after the screen closes: their pictures are made here,
    -- once a session is open, never in the middle of a draw (the drawer, the stand)
    if s and not Rk.warmed then Rk.warmed = prewarm() end
    if not (s and s.mode == "core") or s.trans or s.anim.rocket then matcher.n = 0; return end
    local p = input and input.pressed
    if type(p) ~= "table" then return end
    for _, b in ipairs(Rk.BUTTONS) do
      if p[b] and Rk.feed(matcher, b) then Rk.unlock(); return end
    end
  end
  Rk.matcherState = matcher

  -- the alley's state on the session
  -- the top screen dims only while he asks to confirm a purchase (the answer is below), and
  -- lights again as soon as it is answered
  Rk.DIM, Rk.DIM_RATE = 0.6, 4
  local function say(r, list, text)
    r.line = text or Rk.pick(Rk.LINES[list], r.line)
    r.chars = 0
  end
  function Rk.dimWanted(r)
    return r ~= nil and r.phase == "shop" and r.confirm ~= nil
  end
  local function typed(r) return r.line == nil or r.chars >= #r.line end

  -- the way in and out are quiet: the alley's music starts with the R (music.lua) and fades
  -- out on the way back
  function T.rocketTrans(mode) end

  local function stopRain(s)
    local r = s and s.rocket
    if r and r.rain then pcall(r.rain.stop); r.rain = nil end
  end

  -- the mode changed behind the black (session stepTrans)
  function T.rocketSwitched(to)
    local s = T.session
    if not s then return end
    if to == "rocket" then
      s.rocket = { phase = "walk", t = 0, clock = 0, sel = 1, top = 1, steps = 0, shopT = 0 }
      if Scene then Scene.reset() end
      -- the music (assets/UnseenEncounter.ogg) is decoded now, behind the black, and the R's
      -- time starts after it (the session's transition skips the long frame it costs)
      local A = T.assets
      local M = T.music
      if A and A.music and M and M.ROCKET then pcall(A.music, M.ROCKET) end
      if s.trans then s.trans.freeze = true end
      local h = T.sfx and T.sfx.play and T.sounds and T.sounds.rocket_rain and T.sfx.play(T.sounds.rocket_rain, { loop = true, volume = 0.8 })
      if h then s.rocket.rain = h end
    else
      stopRain(s)
      s.rocket = nil
    end
  end

  function T.rocketClosed(s)
    stopRain(s)
    if s then s.rocket = nil end
  end

  -- ------- what the alley does each tick (the session's T.tick)

  function T.tickRocket(s, dt)
    local a = s.anim and s.anim.rocket
    if a then
      local U = Rk.UNLOCK
      local before = a.t
      a.t = a.t + dt
      if before < U.FADE and a.t >= U.FADE then T.playSe("rocket_sting", "SE_M_SCARY_FACE") end
      local gAt = U.FADE + U.GROW * 0.5
      if before < gAt and a.t >= gAt then T.playSe("rocket_glint", "SE_SHINY") end
      if a.t >= Rk.unlockTotal() then s.anim.rocket = nil end
    end
    local r = s.rocket
    if not (r and s.mode == "rocket") then return end
    r.clock = r.clock + dt
    -- (the alley starts once the screens have faded in)
    if s.trans then return end
    r.t = r.t + dt
    -- the top screen's dim eases toward what is wanted
    local want = Rk.dimWanted(r) and 1 or 0
    local d = r.dim or 0
    if d < want then r.dim = min(want, d + dt * Rk.DIM_RATE) elseif d > want then r.dim = max(want, d - dt * Rk.DIM_RATE) end
    if r.line and r.chars < #r.line then r.chars = min(#r.line, r.chars + dt * Rk.CPS) end
    if r.phase == "walk" then
      if Scene then
        Scene.setWalk(r.t)
        local n = floor(Scene.walked() / Scene.WALK.STRIDE)
        if n > r.steps then
          r.steps = n
          if Scene.walkU() < 0.97 then T.playSe("rocket_step") end
        end
        -- (he steps into the light in silence)
        if r.t >= Scene.WALK.S then r.phase, r.t = "appear", 0 end
      else
        r.phase, r.t = "appear", 0
      end
    elseif r.phase == "appear" then
      if r.t >= Rk.APPEAR_S then r.phase, r.t = "greet", 0; say(r, "greet") end
    elseif r.phase == "shop" then
      r.shopT = min(1, r.shopT + dt / Rk.SHOP_S)
    elseif r.phase == "bye" then
      r.shopT = max(0, r.shopT - dt / Rk.SHOP_S)
      if typed(r) then
        r.byeWait = (r.byeWait or 0) + dt
        if r.byeWait >= Rk.BYE_S then Rk.leave() end
      end
    end
  end

  -- the alley's pictures, from the layer's update (outside the engine's draw)
  local wallImg = nil
  function T.rocketPrepare()
    local s = T.session
    if Scene and s and s.rocket then
      if s.rocket.phase == "walk" then Scene.setWalk(s.rocket.t) end
      local ok, err = pcall(Scene.prepare)
      if not ok and not Rk.warned then
        Rk.warned = true
        mod.log:warn("Super Training: the alley did not render (%s)", tostring(err))
      end
    end
    if not wallImg and Scene and Scene.picture then wallImg = Rk.wallPicture() end
  end

  -- ------- input (the layer's pad, and the touch screen's buttons through T.rocketTap)

  function Rk.leave()
    local s = T.session
    if not (s and s.mode == "rocket") or s.trans then return end
    T.goTo("core")
  end

  local function move(r, d)
    local n = #Rk.STOCK
    if n == 0 then return end
    local sel = max(1, min(n, r.sel + d))
    if sel == r.sel then return end
    r.sel = sel
    if r.sel < r.top then r.top = r.sel end
    if r.sel > r.top + Rk.ROWS - 1 then r.top = r.sel - Rk.ROWS + 1 end
    host.playSe("SE_SELECT")
  end

  local function ask(r)
    local id = Rk.STOCK[r.sel]
    if not id then return end
    r.confirm = { id = id, yes = true, before = r.line }
    r.line = Rk.ASK:format(T.bagName(id), Rk.money(Rk.price(id)))
    r.chars = #r.line
    host.playSe("SE_SELECT")
  end

  function T.rocketBuy(id)
    local s = T.session
    local r = s and s.rocket
    if not r then return false end
    local money = host.money and host.money() or 0
    local ok, res = Rk.buy(money, Store.bags(), id)
    local H = mod.haptics
    if ok then
      if not (host.spendMoney and host.spendMoney(money - res)) then ok, res = false, "money" end
    end
    if ok then
      Rules.inventoryAdd(Store.bags(), id)
      Store.save()
      T.playSe("rocket_buy", "SE_SHOP")
      if H then H.pulse("medium") end
      say(r, "sold")
      T.onChange()
      return true
    end
    if H then H.pattern("bad") end
    host.playSe("SE_FAILURE")
    say(r, res == "full" and "full" or "broke")
    return false, res
  end

  local function answer(r, yes)
    local c = r.confirm
    r.confirm = nil
    if yes then T.rocketBuy(c.id)
    else
      host.playSe("SE_SELECT")
      -- no: his words go back to what he said before, and the shop is the player's again
      r.line, r.chars = c.before, c.before and #c.before or 0
    end
  end

  local function bye(r)
    r.confirm = nil
    r.phase, r.t = "bye", 0
    say(r, "bye")
  end

  -- the dialogue: a press finishes the line, then goes on
  local function advance(r)
    if not typed(r) then r.chars = #r.line; return end
    if r.phase == "walk" or r.phase == "appear" then
      -- skipped to him
      if Scene then Scene.setWalk(Scene.WALK.S) end
      r.phase, r.t = "greet", 0
      say(r, "greet")
    elseif r.phase == "greet" then
      r.phase, r.t = "shop", 0
      T.playSe("rocket_open", "SE_SELECT")
      say(r, "open")
    elseif r.phase == "bye" then
      Rk.leave()
    end
  end

  -- what = "advance" | "up" | "down" | "buy" | "yes" | "no" | "back" | "row" (i)
  function T.rocketTap(what, i)
    local s = T.session
    local r = s and s.rocket
    if not r or s.trans then return end
    if what == "back" then
      if r.phase == "bye" then Rk.leave() elseif r.phase == "shop" then bye(r) else advance(r) end
      return
    end
    if r.phase ~= "shop" then advance(r); return end
    if r.confirm then
      if what == "yes" then answer(r, true) elseif what == "no" then answer(r, false) end
      return
    end
    if what == "up" then move(r, -1)
    elseif what == "down" then move(r, 1)
    elseif what == "row" and i then
      if i == r.sel then ask(r) else move(r, i - r.sel) end
    elseif what == "scroll" and i then
      -- a drag: the list's first row shown (the bag picked stays picked)
      r.top = max(1, min(floor(i + 0.5), #Rk.STOCK - Rk.ROWS + 1))
    elseif what == "buy" then ask(r)
    elseif what == "advance" and not typed(r) then r.chars = #r.line end
  end

  function T.rocketInput(input)
    local s = T.session
    local r = s and s.rocket
    if not r then return end
    local function p(b) return input:wasPressed(b) end
    if r.phase == "shop" and r.confirm then
      if p("up") or p("down") then r.confirm.yes = not r.confirm.yes; host.playSe("SE_SELECT")
      elseif p("a") then answer(r, r.confirm.yes)
      elseif p("b") then answer(r, false) end
      return
    end
    if r.phase == "shop" then
      if p("up") then move(r, -1)
      elseif p("down") then move(r, 1)
      elseif p("left") then move(r, -Rk.ROWS)
      elseif p("right") then move(r, Rk.ROWS)
      elseif p("a") then ask(r)
      elseif p("b") then bye(r) end
      return
    end
    if p("a") or p("b") then
      if r.phase == "bye" and typed(r) then Rk.leave() else advance(r) end
    end
  end

  -- what the touch screen and drivers read
  -- (one table, filled again on each call: the screens ask several times a frame; the line's
  -- typed part is cut only when it grows)
  local stateT, shownLine, shownN, shownS = {}, nil, -1, nil
  function Rk.state()
    local s = T.session
    local r = s and s.rocket
    if not r then return nil end
    local n = floor(r.chars or 0)
    if r.line ~= shownLine or n ~= shownN then
      shownLine, shownN = r.line, n
      shownS = r.line and r.line:sub(1, n) or nil
    end
    local o = stateT
    o.phase, o.t, o.line, o.shown, o.typed = r.phase, r.t, r.line, shownS, typed(r)
    o.sel, o.top, o.id, o.confirm = r.sel, r.top, Rk.STOCK[r.sel], r.confirm and r.confirm.yes
    o.shopT, o.money, o.bags, o.dim = r.shopT, host.money and host.money() or 0, #Store.bags(), r.dim or 0
    o.dealer = r.phase == "walk" and 0 or (r.phase == "appear" and min(1, r.t / Rk.APPEAR_S) or 1)
    o.clock = r.clock
    return o
  end

  -- ------- the top screen: the brick wall, the R's flash, the shop

  -- a grimy wall: courses of dark brick, soot and damp, a faded R sprayed on it
  function Rk.wallPicture()
    local picture = Scene and Scene.picture
    if not picture then return nil end
    local ok, img = pcall(picture, 256, 160, function(G, w, h)
      local function hash(i, k) return (sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end
      G.setColor(0.12, 0.1, 0.1, 1)
      G.rectangle("fill", 0, 0, w, h)
      local rows, cols = 16, 8
      local bh, bw = h / rows, w / cols
      for r = 0, rows - 1 do
        local off = (r % 2) * bw / 2
        for c = -1, cols do
          local i = r * 13 + c
          local t = hash(i, 1)
          G.setColor(0.3 + 0.12 * t, 0.15 + 0.05 * t, 0.12 + 0.04 * hash(i, 2), 1)
          G.rectangle("fill", c * bw + off + 0.7, r * bh + 0.7, bw - 1.4, bh - 1.4)
          G.setColor(1, 1, 1, 0.05)
          G.rectangle("fill", c * bw + off + 0.7, r * bh + 0.7, bw - 1.4, 0.8)
        end
      end
      for i = 1, 40 do
        G.setColor(0.02, 0.02, 0.02, 0.06 + 0.1 * hash(i, 3))
        local x, y, rr = w * hash(i, 4), h * hash(i, 5), 3 + 9 * hash(i, 6)
        for dx = -1, 1 do for dy = -1, 1 do G.circle("fill", x + dx * w, y + dy * h, rr, 24) end end
      end
      -- damp running down from the top
      for i = 1, 12 do
        local x = w * hash(i, 7)
        G.setColor(0, 0, 0, 0.15)
        G.rectangle("fill", x, 0, 2 + 4 * hash(i, 8), h * (0.3 + 0.6 * hash(i, 9)))
      end
    end)
    return ok and img or nil
  end

  local function topArt(id)
    local A = T.assets
    if not (A and A.image) then return nil end
    local ok, img = pcall(A.image, id)
    return ok and img or nil
  end

  -- fonts rasterised at the size they land on screen (the top screen is drawn under a scale)
  local fonts = {}
  local function fontAt(G2, size)
    local x0, y0 = G2.transformPoint(0, 0)
    local x1, y1 = G2.transformPoint(1, 0)
    local px = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    local d = max(1, min(16, floor(px * 2 + 0.5) / 2))
    local key = size * 100 + d
    if fonts[key] == nil then
      local ok, f = pcall(G2.newFont, size, "normal", d)
      fonts[key] = ok and f or false
    end
    return fonts[key] or G2.getFont()
  end
  Rk.fontAt = fontAt

  -- the Pokedollar: a P with two strokes through it, then the amount; returns the width
  function Rk.printMoney(G2, font, amount, x, y, align)
    local text = Rk.money(amount)
    local pw = font:getWidth("P")
    local w = pw + 1 + font:getWidth(text)
    if align == "right" then x = x - w end
    G2.setFont(font)
    G2.print("P", x, y)
    local h = font:getHeight()
    G2.setLineWidth(max(0.5, h * 0.07))
    G2.line(x - 0.5, y + h * 0.36, x + pw + 0.5, y + h * 0.36)
    G2.line(x - 0.5, y + h * 0.48, x + pw + 0.5, y + h * 0.48)
    G2.print(text, x + pw + 1, y)
    return w
  end

  -- text whose lines ("\n") may hold Rk.PD, drawn as the Pokedollar sign (as printMoney's), in
  -- the colour set, with a shadow under it; no wrapping (the lines are the caller's)
  local function pdGlyph(G2, font, x, y)
    local pw, h = font:getWidth("P"), font:getHeight()
    G2.print("P", x, y)
    G2.setLineWidth(math.max(0.5, h * 0.07))
    G2.line(x - 0.5, y + h * 0.36, x + pw + 0.5, y + h * 0.36)
    G2.line(x - 0.5, y + h * 0.48, x + pw + 0.5, y + h * 0.48)
    return pw + 1
  end
  -- a text cut once into its lines and pieces ({ piece, ... } a line, true for the sign); kept
  -- for the last few texts (a typed line grows a character at a time)
  local cut, cutN = {}, 0
  local function pieces(text)
    local c = cut[text]
    if c then return c end
    c = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local l = {}
      for seg, pd in line:gmatch("([^\1]*)(\1?)") do
        if seg ~= "" then l[#l + 1] = seg end
        if pd ~= "" then l[#l + 1] = true end
      end
      c[#c + 1] = l
    end
    if cutN >= 128 then cut, cutN = {}, 0 end
    cut[text], cutN = c, cutN + 1
    return c
  end
  local function lineRaw(G2, font, text, x, y)
    local lh = font:getHeight() * font:getLineHeight()
    local lines = pieces(text)
    for row = 1, #lines do
      local l = lines[row]
      local cx, yy = x, y + (row - 1) * lh
      for i = 1, #l do
        local p = l[i]
        if p == true then cx = cx + pdGlyph(G2, font, cx, yy)
        else G2.print(p, cx, yy); cx = cx + font:getWidth(p) end
      end
    end
  end
  function Rk.printLine(G2, font, text, x, y, r, g, b, a)
    G2.setFont(font)
    G2.setColor(0, 0, 0, 0.7 * (a or 1))
    lineRaw(G2, font, text, x + 0.6, y + 0.7)
    G2.setColor(r, g, b, a or 1)
    lineRaw(G2, font, text, x, y)
  end

  local function frameRect(e) if e then return e.x, e.y, e.w, e.h end return 0, 0, 240, 160 end

  -- a vertical gradient over a rect: dark at the top, the lamp's warmth at the foot
  local shadeMesh = nil
  local function shade(G2, x, y, w, h)
    if not shadeMesh then
      shadeMesh = G2.newMesh({
        { 0, 0, 0, 0, 0, 0, 0, 0.5 }, { 1, 0, 0, 0, 0, 0, 0, 0.5 },
        { 1, 0.45, 0, 0, 0, 0, 0, 0 }, { 0, 0.45, 0, 0, 0, 0, 0, 0 },
        { 0, 0.45, 0, 0, 1, 0.75, 0.4, 0 }, { 1, 0.45, 0, 0, 1, 0.75, 0.4, 0 },
        { 1, 1, 0, 0, 1, 0.75, 0.4, 0.14 }, { 0, 1, 0, 0, 1, 0.75, 0.4, 0.14 },
      }, "triangles", "static")
      shadeMesh:setVertexMap(1, 2, 3, 1, 3, 4, 5, 6, 7, 5, 7, 8)
    end
    G2.setColor(1, 1, 1, 1)
    G2.draw(shadeMesh, x, y, 0, w, h)
  end

  -- the grimy wall behind the store (the touch screen): tiled from the rect's corner, the faded R
  -- sprayed on it a little crooked, dark at the top, a lamp's warmth from below
  local wallQuad = nil
  local function drawWall(G2, ex, ey, ew, eh)
    local img = wallImg
    if img then
      local iw, ih = img:getDimensions()
      local k = 100 / ih
      wallQuad = wallQuad or G2.newQuad(0, 0, 1, 1, iw, ih)
      wallQuad:setViewport(0, 0, ew / k, eh / k, iw, ih)
      G2.setColor(1, 1, 1, 1)
      G2.draw(img, wallQuad, ex, ey, 0, k, k)
    else
      G2.setColor(0.24, 0.13, 0.11, 1)
      G2.rectangle("fill", ex, ey, ew, eh)
    end
    local logo = topArt("rocket/logo")
    if logo then
      local lw, lh = logo:getDimensions()
      local k = math.min(ew, eh) * 0.7 / lh
      G2.setColor(0.5, 0.08, 0.1, 0.32)
      G2.draw(logo, ex + ew / 2, ey + eh / 2, -0.08, k, k, lw / 2, lh / 2)
    end
    shade(G2, ex, ey, ew, eh)
  end

  local function bagIcon(G2, id, cx, cy, h)
    local img = topArt(Rules.bagArt(id))
    if not img then return end
    local iw, ih = img:getDimensions()
    local k = h / ih
    local b = Rules.bag(id)
    local glow = b and b.glow and topArt(Rules.bagGlowArt(id))
    if glow then
      local gw, gh = glow:getDimensions()
      G2.setColor(1, 1, 1, 1)
      G2.draw(glow, cx, cy, 0, k, k, gw / 2, gh / 2)
    end
    G2.setColor(1, 1, 1, 1)
    G2.draw(img, cx, cy, 0, k, k, iw / 2, ih / 2)
  end
  Rk.bagIcon = bagIcon

  -- ------- the UI's pieces (src/training/ui_art.lua's rocket/*): nine-sliced panels, glowing
  -- dividers, text with a shadow

  -- the slices of a texture with a border of b texture units, kept per image
  local sliceCache = setmetatable({}, { __mode = "k" })
  local function slicesOf(G2, img, b)
    local c = sliceCache[img]
    if c and c.b == b then return c end
    local tw, th = img:getDimensions()
    local mw, mh = tw - 2 * b, th - 2 * b
    local Q = function(x, y, w, h) return G2.newQuad(x, y, w, h, tw, th) end
    c = { b = b, mw = mw, mh = mh,
      tl = Q(0, 0, b, b), t = Q(b, 0, mw, b), tr = Q(tw - b, 0, b, b),
      l = Q(0, b, b, mh), m = Q(b, b, mw, mh), r = Q(tw - b, b, b, mh),
      bl = Q(0, th - b, b, b), bm = Q(b, th - b, mw, b), br = Q(tw - b, th - b, b, b) }
    sliceCache[img] = c
    return c
  end
  -- a panel `id` over x, y, w, h: its corners d units across (the texture's border b), the
  -- edges and middle stretched; `scan` lays the scanlines over the stretched middle again
  local SLICE = { ["rocket/panel"] = 14, ["rocket/red"] = 10, ["rocket/inset"] = 8, ["rocket/pill"] = 11,
    ["rocket/pill_on"] = 11 }
  function Rk.slice(G2, id, x, y, w, h, d, a, scan)
    local img = topArt(id)
    if not img then
      G2.setColor(0.05, 0.04, 0.06, a or 1)
      G2.rectangle("fill", x, y, w, h, 4, 4)
      return
    end
    d = math.min(d, w / 2, h / 2)
    local S = slicesOf(G2, img, SLICE[id] or 8)
    local k = d / S.b
    local iw, ih = w - 2 * d, h - 2 * d
    G2.setColor(1, 1, 1, a or 1)
    G2.draw(img, S.tl, x, y, 0, k, k)
    G2.draw(img, S.tr, x + w - d, y, 0, k, k)
    G2.draw(img, S.bl, x, y + h - d, 0, k, k)
    G2.draw(img, S.br, x + w - d, y + h - d, 0, k, k)
    if iw > 0 then
      G2.draw(img, S.t, x + d, y, 0, iw / S.mw, k)
      G2.draw(img, S.bm, x + d, y + h - d, 0, iw / S.mw, k)
    end
    if ih > 0 then
      G2.draw(img, S.l, x, y + d, 0, k, ih / S.mh)
      G2.draw(img, S.r, x + w - d, y + d, 0, k, ih / S.mh)
    end
    if iw > 0 and ih > 0 then
      G2.draw(img, S.m, x + d, y + d, 0, iw / S.mw, ih / S.mh)
      local sc = scan and topArt("rocket/scan")
      if sc then
        local sw, sh = sc:getDimensions()
        sc:setWrap("repeat", "repeat")
        Rk.scanQuad = Rk.scanQuad or G2.newQuad(0, 0, 1, 1, sw, sh)
        Rk.scanQuad:setViewport(0, 0, iw, ih, sw, sh)
        G2.setColor(1, 1, 1, a or 1)
        G2.draw(sc, Rk.scanQuad, x + d, y + d)
      end
    end
  end
  -- a divider: a red line glowing faintly
  function Rk.neonLine(G2, x0, y0, x1, y1, a)
    a = a or 1
    G2.setLineWidth(2.4); G2.setColor(0.85, 0.1, 0.16, 0.18 * a); G2.line(x0, y0, x1, y1)
    G2.setLineWidth(1.1); G2.setColor(0.95, 0.2, 0.25, 0.55 * a); G2.line(x0, y0, x1, y1)
    G2.setLineWidth(0.4); G2.setColor(1, 0.75, 0.75, 0.7 * a); G2.line(x0, y0, x1, y1)
  end
  -- text with a dark shadow under it (r, g, b, a its colour)
  function Rk.print(G2, font, text, x, y, r, g, b, a)
    G2.setFont(font)
    G2.setColor(0, 0, 0, 0.7 * (a or 1))
    G2.print(text, x + 0.6, y + 0.7)
    G2.setColor(r, g, b, a or 1)
    G2.print(text, x, y)
  end

  -- the store (the touch screen's units), slid up from below by k (0..1): its panel, the head
  -- (the R, the name, the money, the back button's place), the rows as many as fit (Rk.ROWS),
  -- a scroll bar, the bag picked's line. Where things are, for taps: Rk.where
  local SHOP = { pad = 6, head = 24, rowY = 36, rowH = 20, detail = 24, back = 22 }
  Rk.SHOP = SHOP
  Rk.where = { rows = {} }
  local GOLD = { 1, 0.86, 0.35 }
  -- (the rects are kept and filled again each draw; the rows from a pool; the texts per bag)
  local panelR, backR, listR, rowPool = {}, {}, {}, {}
  local function rset(t, x, y, w, h) t.x, t.y, t.w, t.h = x, y, w, h; return t end
  local detailText, roomText = {}, {}
  local function drawShop(G2, r, k, X, Y, W, H)
    local P = SHOP
    local e = 1 - (1 - k) ^ 3
    local x, y, w, h = X + P.pad, Y + P.pad + (1 - e) * (H + 20), W - 2 * P.pad, H - 2 * P.pad
    local where = Rk.where
    where.panel = rset(panelR, x, y, w, h)
    -- the panel, its shadow under it
    G2.setColor(0, 0, 0, 0.4)
    G2.rectangle("fill", x + 3, y + 4, w, h, 8, 8)
    Rk.slice(G2, "rocket/panel", x, y, w, h, 9, 1, true)
    -- the head: red glass, the R, the name; the money in a recess; the back button at its right
    local big, small = fontAt(G2, 11), fontAt(G2, 9)
    Rk.slice(G2, "rocket/red", x + 5, y + 4, w - 10, P.head, 6, 1, true)
    local ty = y + 4 + (P.head - big:getHeight()) / 2
    local logo = topArt("rocket/logo")
    if logo then
      local lw, lh = logo:getDimensions()
      local lk = (P.head - 4) / lh
      G2.setColor(0, 0, 0, 0.6)
      G2.draw(logo, x + 18.6, y + 4 + P.head / 2 + 0.8, 0, lk, lk, lw / 2, lh / 2)
      G2.setColor(1, 1, 1, 1)
      G2.draw(logo, x + 18, y + 4 + P.head / 2, 0, lk, lk, lw / 2, lh / 2)
    end
    Rk.print(G2, big, "BLACK MARKET", x + 30, ty, 1, 0.95, 0.92)
    where.back = rset(backR, x + w - P.back - 8, y + 4 + (P.head - P.back) / 2, P.back, P.back)
    local money = host.money and host.money() or 0
    local mw = small:getWidth("P 999,999") + 14
    local mx = where.back.x - mw - 4
    Rk.slice(G2, "rocket/inset", mx, y + 7, mw, P.head - 6, 4)
    G2.setColor(0, 0, 0, 0.7)
    Rk.printMoney(G2, small, money, mx + mw - 5.4, y + 7 + (P.head - 6 - small:getHeight()) / 2 + 0.7, "right")
    G2.setColor(GOLD[1], GOLD[2], GOLD[3], 1)
    Rk.printMoney(G2, small, money, mx + mw - 6, y + 7 + (P.head - 6 - small:getHeight()) / 2, "right")
    -- the rows: as many as fit; the picked one on red glass, the rest divided by faint lines
    local n = #Rk.STOCK
    local rows = math.max(3, floor((h - P.rowY - P.detail - 4) / P.rowH))
    if rows ~= Rk.ROWS then
      Rk.ROWS = rows
      r.top = max(1, min(r.top, n - rows + 1))
      if r.sel < r.top then r.top = r.sel elseif r.sel > r.top + rows - 1 then r.top = r.sel - rows + 1 end
    end
    local rx, rw = x + 8, w - 26
    for i = #where.rows, 1, -1 do where.rows[i] = nil end
    for i = 0, rows - 1 do
      local idx = r.top + i
      local id = Rk.STOCK[idx]
      if id then
        local ry = y + P.rowY + i * P.rowH
        local n2 = #where.rows + 1
        local rr = rowPool[n2]
        if not rr then rr = {}; rowPool[n2] = rr end
        rset(rr, rx, ry, rw, P.rowH).idx = idx
        where.rows[n2] = rr
        local sel = idx == r.sel
        if sel then
          Rk.slice(G2, "rocket/red", rx, ry, rw, P.rowH - 1, 5, 1)
        elseif i > 0 and r.top + i - 1 ~= r.sel then
          G2.setColor(1, 1, 1, 0.06)
          G2.rectangle("fill", rx + 6, ry - 0.5, rw - 12, 0.6)
        end
        bagIcon(G2, id, rx + 11, ry + (P.rowH - 1) / 2, P.rowH - 3)
        local ty2 = ry + (P.rowH - 1 - small:getHeight()) / 2
        local price = Rk.price(id) or 0
        local afford = money >= price
        local c = sel and 1 or 0.82
        Rk.print(G2, small, T.bagName(id), rx + 24, ty2, c, c, sel and 1 or 0.86)
        G2.setColor(0, 0, 0, 0.7)
        Rk.printMoney(G2, small, price, rx + rw - 5.4, ty2 + 0.7, "right")
        if afford then G2.setColor(GOLD[1], GOLD[2], GOLD[3], 1) else G2.setColor(0.6, 0.42, 0.42, 1) end
        Rk.printMoney(G2, small, price, rx + rw - 6, ty2, "right")
      end
    end
    where.list = rset(listR, rx, y + P.rowY, rw, rows * P.rowH)
    -- the scroll bar: a recessed track, a red glass thumb
    if n > rows then
      local top, span = y + P.rowY, rows * P.rowH - 1
      local tx = x + w - 15
      Rk.slice(G2, "rocket/inset", tx, top, 6, span, 3)
      local bh = max(8, span * rows / n)
      local by = top + (span - bh) * (r.top - 1) / (n - rows)
      Rk.slice(G2, "rocket/red", tx + 0.5, by + 0.5, 5, bh - 1, 2.5)
    end
    -- the bag picked: what it does, and the drawer's room, under a glowing divider
    local id = Rk.STOCK[r.sel]
    local b = id and Rules.bag(id)
    local dy = y + h - P.detail
    Rk.neonLine(G2, x + 10, dy - 2, x + w - 10, dy - 2, 0.8)
    if b then
      local ly = dy + (P.detail - 8 - small:getHeight()) / 2 + 2
      local dt = detailText[id]
      if not dt then
        dt = ("+%d %s EVs  ·  %d hits"):format(b.ev, Rules.STAT_LABEL[b.stat] or b.stat, b.hits)
        detailText[id] = dt
      end
      Rk.print(G2, small, dt, x + 11, ly, 0.85, 0.85, 0.9)
      local nb = #Store.bags()
      local room = roomText[nb]
      if not room then room = ("DRAWER %d/%d"):format(nb, Rules.N.LIMITS.BAG_MAX); roomText[nb] = room end
      local full = Rules.inventoryFull(Store.bags())
      if full then Rk.print(G2, small, room, x + w - 11 - small:getWidth(room), ly, 1, 0.45, 0.45)
      else Rk.print(G2, small, room, x + w - 11 - small:getWidth(room), ly, 0.72, 0.72, 0.78) end
    end
  end

  -- the touch screen: the wall, the store over it (from the shop on), dimmed while he asks
  function Rk.drawBottom(G2, s, x, y, w, h)
    drawWall(G2, x, y, w, h)
    local r = s.rocket
    if r and (r.shopT or 0) > 0 then drawShop(G2, r, r.shopT, x, y, w, h)
    else Rk.where.panel, Rk.where.back = nil, nil end
    if r and (r.dim or 0) > 0 then
      G2.setColor(0, 0, 0, Rk.DIM * r.dim)
      G2.rectangle("fill", x - 10, y - 10, w + 20, h + 20)
    end
  end

  -- the top screen: the alley (rocket_scene.lua) over the area, his words in a box along its foot
  function T.drawRocketTop(G2, s, e)
    local ex, ey, ew, eh = frameRect(e)
    local r = s.rocket
    local st = Rk.state()
    if Scene then
      local ok, err = pcall(Scene.draw, G2, ex, ey, ew, eh, st and st.dealer or 0, st and st.clock or 0)
      if not ok and not Rk.drawWarned then
        Rk.drawWarned = true
        mod.log:warn("Super Training: the alley's draw failed (%s)", tostring(err))
      end
    else
      G2.setColor(0.03, 0.035, 0.07, 1)
      G2.rectangle("fill", ex, ey, ew, eh)
    end
    if not (r and st and st.line) then return end
    local font, small = fontAt(G2, 9), fontAt(G2, 7)
    -- the box: across the area (at most 300 wide, centred), along its foot
    local bw, bh = math.min(ew - 12, 300), 40
    local bx = ex + (ew - bw) / 2
    local by = ey + eh - bh - 5
    Rk.slice(G2, "rocket/panel", bx, by, bw, bh, 8, 0.96, true)
    local tag = "???"
    local tw, th = small:getWidth(tag) + 12, small:getHeight() + 4
    Rk.slice(G2, "rocket/red", bx + 8, by - th + 3, tw, th, 4)
    Rk.print(G2, small, tag, bx + 14, by - th + 5, 1, 0.9, 0.9)
    local shown = st.shown or ""
    if shown:find(Rk.PD, 1, true) or shown:find("\n", 1, true) then
      Rk.printLine(G2, font, shown, bx + 10, by + 7, 0.96, 0.94, 0.92)
    else
      G2.setFont(font)
      G2.setColor(0, 0, 0, 0.7)
      G2.printf(shown, bx + 10.6, by + 7.7, bw - 22, "left")
      G2.setColor(0.96, 0.94, 0.92, 1)
      G2.printf(shown, bx + 10, by + 7, bw - 22, "left")
    end
    -- the line is out: a blinking mark to go on (not while the shop waits for a pick)
    if st.typed and st.phase ~= "shop" and (st.clock * 2) % 1 < 0.6 then
      local mx, my = bx + bw - 12, by + bh - 8
      G2.setColor(1, 0.4, 0.4, 1)
      G2.polygon("fill", mx - 4, my - 3, mx + 4, my - 3, mx, my + 2)
    end
  end

  -- the R over black, k 0..1 through its time: it fades and grows in once, its glint sweeps
  -- across, and it stays; `a` fades it out with the black as the alley comes in
  Rk.LOGO = { IN = 0.4, GLINT0 = 0.45, GLINT1 = 0.85 }
  function T.drawRocketLogo(G2, k, e, a)
    local logo = topArt("rocket/logo")
    if not logo then return end
    local P = Rk.LOGO
    local lw, lh = logo:getDimensions()
    local u = min(1, k / P.IN)
    local ease = 1 - (1 - u) ^ 3
    local scale = 110 / lh * (0.8 + 0.2 * ease)
    G2.setColor(1, 1, 1, ease * (a or 1))
    G2.draw(logo, 120, 80, 0, scale, scale, lw / 2, lh / 2)
    local glint = topArt("rocket/glint")
    if glint and k >= P.GLINT0 and k <= P.GLINT1 then
      local g = (k - P.GLINT0) / (P.GLINT1 - P.GLINT0)
      local gw, gh = glint:getDimensions()
      G2.setBlendMode("add")
      G2.setColor(1, 1, 1, sin(g * pi))
      G2.draw(glint, 120 - 34 + 68 * g, 80 - 30 + 20 * g, g * 2.5, 1.1, 1.1, gw / 2, gh / 2)
      G2.setBlendMode("alpha")
    end
  end

  return Rk
end
