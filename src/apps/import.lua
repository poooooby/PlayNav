-- IMPORT: the bottom-screen progress panel while Pokemon-Amie art is being
-- extracted from the player's card image. Takes the surface only while the
-- extraction runs; afterwards it steps aside and the surface goes dormant.

return function(mod, Pointer, Extract)
  local app = { id = "import", title = "IMPORT", live = true }

  local CANCEL = { x = 168, y = 150, w = 80, h = 18 }
  local shownDoneAt = nil

  function app:wantsSurface()
    local s = Extract.state
    if s == "running" or s == "finishing" then return true end
    if s == "done" or s == "failed" then
      -- keep the result on screen for a few seconds, then let go
      shownDoneAt = shownDoneAt or Pointer.now()
      return Pointer.now() - shownDoneAt < 6
    end
    return false
  end

  function app:pointer(ev, rec, game)
    if ev.phase == "released" and Pointer.isTap(rec, 16, 1.0)
        and ev.x >= CANCEL.x and ev.x <= CANCEL.x + CANCEL.w
        and ev.y >= CANCEL.y and ev.y <= CANCEL.y + CANCEL.h then
      if Extract.state == "running" then Extract.cancel() end
    end
  end

  function app:draw(G, w, h)
    G.setColor(0.12, 0.14, 0.2, 1)
    G.rectangle("fill", 0, -(app.bleed or 0), w, h + (app.bleed or 0))
    G.setColor(1, 1, 1, 1)
    G.printf("POKEMON-AMIE ART", 0, 22, w, "center")
    local done, total = Extract.progress()
    local frac = total > 0 and done / total or 0
    G.setColor(0.2, 0.22, 0.3, 1)
    G.rectangle("fill", 24, 60, w - 48, 16, 6, 6)
    G.setColor(0.35, 0.75, 1, 1)
    G.rectangle("fill", 25, 61, math.max(0, (w - 50) * frac), 14, 6, 6)
    G.setColor(1, 1, 1, 0.9)
    G.printf(("%d / %d"):format(done, total), 0, 82, w, "center")
    local msg = Extract.message or ""
    if Extract.state == "running" then
      msg = ("Reading Alpha Sapphire... %d%%"):format(math.floor(frac * 100))
    end
    G.printf(msg, 12, 104, w - 24, "center")
    if Extract.failed > 0 then
      G.setColor(1, 0.75, 0.4, 1)
      G.printf(("%d could not be decoded"):format(Extract.failed), 0, 124, w, "center")
    end
    if Extract.state == "running" then
      G.setColor(0.4, 0.4, 0.48, 1)
      G.rectangle("fill", CANCEL.x, CANCEL.y, CANCEL.w, CANCEL.h, 6, 6)
      G.setColor(1, 1, 1, 0.95)
      G.printf("PAUSE", CANCEL.x, CANCEL.y + 2, CANCEL.w, "center")
    end
  end

  return app
end
