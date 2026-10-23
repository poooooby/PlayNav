-- The bag drawer between visits: only the active app is updated, so a close still pending when
-- the session left the drawer (B, a battle, START -> PLAYNAV) shut it the moment it was opened
-- again, every time after. Run from the engine root:
--   luajit mods/play_nav/tests/bags_drawer_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")

local f = assert(io.open("mods/play_nav/src/training/bags_app.lua", "rb"))
local make = assert(load(f:read("*a"), "@bags_app.lua"))()
f:close()

local Session = { session = { mode = "core" } }
function Session.enterCore() Session.session.mode = "core" end
function Session.enterBags() Session.session.mode = "bags" end
function Session.finish() Session.session.mode = "closed" end

local Pointer = { isTap = function() return true end }
local Rules = { N = { LIMITS = { BAG_MAX = 12 } } }
local Store = { bags = function() return {} end }
local app = make({ log = { warn = function() end } }, Pointer, Session, Rules, Store)

local DT = 1 / 30
local function frames(n) for _ = 1, n do app:update(DT) end end
local function tap(r)
  app:pointer({ phase = "released", x = r.x + r.w / 2, y = r.y + r.h / 2 }, {})
end

-- open, then the return button: the drawer slides out and the room comes back
Session.enterBags()
frames(6)
local g = app.geometry()
tap(g.BACK)
frames(10)
T.eq(Session.session.mode, "core", "the return button closes the drawer")
app:leave()

-- open, the return button, and the session leaves before the slide-out ends (as B does)
Session.enterBags()
frames(6)
tap(g.BACK)
frames(1)
Session.enterCore()
app:leave()

-- the next visit: the drawer stays open and takes taps
Session.enterBags()
frames(10)
T.eq(Session.session.mode, "bags", "a close left pending on the last visit does not shut the drawer")
tap(g.BACK)
frames(10)
T.eq(Session.session.mode, "core", "and the return button still closes it")

T.finish("play_nav bag drawer")
