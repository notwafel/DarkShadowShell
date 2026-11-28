-- Infinite Desktop's Lua config with a fake Hyprland: the two screen modes (Settings > Desktop > Infinite Desktop >
-- Screens), a new window on the second screen, and turning it off. Run by tests/infinite.sh, once as 0.55 (no
-- hl.is_key_down: rice-canvasd) and once as 0.56+ (RI_TEST_POLL=1: the pointer itself, and the warp at the edge).
local path = arg[1]
local POLL = os.getenv("RI_TEST_POLL") == "1"
local moves, focuses, floatarr, events, anims = {}, {}, {}, {}, {}
local keys, timers, warps = {}, {}, {}
local timer
local n = 0
local function ok(msg) n = n + 1; print("ok " .. n .. " - " .. msg) end
local function bad(msg) print("not ok " .. (n + 1) .. " - " .. msg); os.exit(1) end
local function check(c, msg) if c then ok(msg) else bad(msg) end end
local function rec(d) if type(d) == "function" then d() else events[#events + 1] = d end end

local function mon(name, x, y)
    return { name = name, x = x, y = y, width = 1920, height = 1080, scale = 1, reserved = { left = 0, top = 0, right = 0, bottom = 0 } }
end
local M1, M2 = mon("DP-1", 0, 0), mon("HDMI-A-1", 1920, 0)

local function win(addr, wsid, m, x, y, w, h)
    return { address = addr, workspace = { id = wsid }, monitor = m, at = { x = x, y = y }, size = { x = w or 400, y = h or 300 },
        mapped = true, hidden = false, floating = true, pinned = false, fullscreen = 0, class = "app" }
end
local W = { win("0xa", 1, M1, 100, 100), win("0xb", 11, M2, 100, 100) }
local active_ws, cursor = 1, { x = 100, y = 100 }
local function at(t, fn) for _, w in ipairs(W) do if "address:" .. w.address == t.window then fn(w) end end end

local handlers = {}
hl = {
    on = function(name, fn) handlers[name] = fn end, bind = function() end, unbind = function() end, exec_cmd = function() end,
    animation = function(t) anims[#anims + 1] = t end,
    get_windows = function() return W end,
    get_active_workspace = function() return { id = active_ws } end,
    get_active_window = function() return W[1] end,
    get_active_monitor = function() return M1 end,
    get_cursor_pos = function() return cursor end,
    get_monitor_at = function(x) return x >= 1920 and M2 or M1 end,
    dispatch = rec,
    dsp = {
        window = {
            move = function(t) return function() moves[#moves + 1] = t; at(t, function(w) w.at.x, w.at.y = t.x, t.y end) end end,
            resize = function(t) return function() at(t, function(w) w.size.x, w.size.y = t.x, t.y end) end end,
            float = function(t) return function() floatarr[#floatarr + 1] = t.action end end,
            close = function() return function() end end,
        },
        focus = function(t) return function() focuses[#focuses + 1] = t; if t.workspace then active_ws = t.workspace end end end,
        exec_cmd = function() return function() end end,
    },
}
if POLL then
    hl.is_key_down = function(sym) return keys[sym] == true end
    hl.timer = function(fn, opts)
        local t = { ms = opts.timeout }
        function t:set_timeout(ms) self.ms = ms end
        timers[#timers + 1] = fn
        timer = t
        return t
    end
    hl.dsp.cursor = { move = function(t) return function() warps[#warps + 1] = t; cursor.x, cursor.y = t.x, t.y end end }
end
assert(loadfile(path))()
check(POLL == (type(hl.is_key_down) == "function"), "the fake Hyprland has hl.is_key_down, or not")

-- screens = 1: only the workspace it was turned on
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
check(RiceInfinite.on, "it is on")
local before = #moves
RiceInfinite.pan(100, 0)
local a = 0
for i = before + 1, #moves do if moves[i].window == "address:0xa" then a = a + 1 end end
check(a > 0, "screens = 1: the window of the workspace moves")
local b = 0
for i = before + 1, #moves do if moves[i].window == "address:0xb" then b = b + 1 end end
check(b == 0, "screens = 1: the window of the other screen stays")
RiceInfinite.set(false)
check(not RiceInfinite.on, "it is off")

-- screens = 0: every screen, but only the workspace each screen shows (a window on another workspace stays)
RiceInfinite.cfg.screens = 0
M1.active_workspace = { id = 1 }
W = { win("0xa", 1, M1, 100, 100), win("0xb", 11, M2, 1970, 100), win("0xd", 2, M1, 100, 100) }
before = #moves
RiceInfinite.set(true)
check(RiceInfinite.on, "it is on with every screen")
RiceInfinite.pan(100, 0)
a, b = 0, 0
for i = before + 1, #moves do
    if moves[i].window == "address:0xa" then a = a + 1 end
    if moves[i].window == "address:0xb" then b = b + 1 end
end
check(a > 0 and b > 0, "screens = 0: the windows of both screens move")
local d = 0
for i = before + 1, #moves do if moves[i].window == "address:0xd" then d = d + 1 end end
check(d == 0, "screens = 0: a window on a workspace no screen shows stays")
table.remove(W, 3)

-- a window that opens on the second screen gets its room there, inside that screen
cursor = { x = 2000, y = 300 }
local fresh = win("0xc", 11, M2, 2000, 300, 700, 500)
fresh.floating = false
W[#W + 1] = fresh
RiceInfinite.opened(fresh)
check(fresh.at.x >= 1920 and fresh.at.x + fresh.size.x <= 3840, "the new window stays on its own screen")

-- off: every screen is put back and tiled again
RiceInfinite.set(false)
check(floatarr[#floatarr] == "unset", "off tiles it again")
check(focuses[#focuses].window == "address:0xc", "the new window was focused")
check(not RiceInfinite.on, "it is off again")

-- a window that got its canvas place while the view was panned: turning it off brings the window back on screen
active_ws = 1
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
RiceInfinite.pan(5000, 0)
local stray = win("0xe", 1, M1, 3000, 200, 400, 300)
W[#W + 1] = stray
RiceInfinite.opened(stray)
RiceInfinite.set(false)
check(stray.at.x >= M1.x and stray.at.x + stray.size.x <= M1.x + 1920
      and stray.at.y >= M1.y and stray.at.y + stray.size.y <= M1.y + 1080,
    "off brings a window placed on a panned canvas back on screen")

-- a floating window that only stuck out of the screen came back half off and looked gone: off keeps the whole
-- rectangle inside the monitor now (Settings is the usual one; a tiled Firefox was retiled and stayed visible)
active_ws = 99
local edge = win("0xf", 99, M1, -180, 120, 420, 300)
W = { edge }
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
RiceInfinite.set(false)
check(edge.at.x >= M1.x + 24 and edge.at.x + edge.size.x <= M1.x + 1920
      and edge.at.y >= M1.y + 24 and edge.at.y + edge.size.y <= M1.y + 1080,
    "off clamps a floating window that only stuck out of the screen")

-- a floating app Infinite never put on the canvas (opened on a workspace no screen shows, so no world entry) is
-- still pulled back on screen when it is turned off: otherwise it stayed at its canvas numbers and looked gone
active_ws = 1
M1.active_workspace = { id = 1 }
local lost = win("0xfe", 2, M1, 5000, 5000, 400, 300)
W = { lost }
RiceInfinite.cfg.screens = 0
RiceInfinite.set(true)
RiceInfinite.set(false)
check(lost.at.x >= M1.x and lost.at.x + lost.size.x <= M1.x + 1920
      and lost.at.y >= M1.y and lost.at.y + lost.size.y <= M1.y + 1080,
    "off rescues a floating window it never placed on the canvas")

-- an odd window in the list (no place or size yet) must not abort the passing out of every other window
active_ws = 1
M1.active_workspace = { id = 1 }
local managed = win("0x1a", 1, M1, 100, 100, 400, 300)
local otherws = win("0x1b", 2, M1, -5000, -5000, 400, 300)   -- another workspace, off screen, never on the canvas
local odd = { address = "0x1c", workspace = { id = 1 }, monitor = M1 }   -- no at / size
W = { managed, otherws, odd }
RiceInfinite.cfg.screens = 0
RiceInfinite.set(true)
RiceInfinite.set(false)
check(managed.at.x >= M1.x and managed.at.x + managed.size.x <= M1.x + 1920,
    "off still places a managed window when an odd one (no place) is in the list")
check(otherws.at.x >= M1.x and otherws.at.x + otherws.size.x <= M1.x + 1920,
    "off pulls a floating window from another workspace back on screen")

-- 0.56+: the pointer itself, no input group (and the warp at the edge of the screen)
local function tick() for _, f in ipairs(timers) do f() end end
local function ticks() for _ = 1, 16 do tick() end end     -- 16 ms of the timer (16 ticks while held, one when idle)
local function hold(x, y)
    keys = { Super_L = true, Alt_L = true }
    cursor = { x = x, y = y or 500 }
    ticks()
end
local function move(x, y) cursor = { x = x, y = y or 500 }; ticks() end
local function let_go() keys = {}; ticks() end
if POLL then
    check(type(hl.is_key_down) == "function" and #timers == 1, "the pointer is followed by a timer")
    os.execute("mkdir -p " .. (os.getenv("HOME") or "") .. "/.config/rice")
    RiceInfinite.set(true)
    RiceInfinite.cfg.speed, RiceInfinite.cfg.dir = 1.0, 1
    local ox = RiceInfinite.ox
    hold(500)                                     -- the hold starts: no move yet
    check(RiceInfinite.ox == ox, "holding the keys alone moves nothing")
    check(timer.ms == 4, "while the keys are held the pointer is followed every 4 ms")
    move(540)
    check(math.abs(RiceInfinite.ox - ox - 40) < 0.001, "the pointer moves the canvas with it")
    check(anims[#anims] and anims[#anims].leaf == "windowsMove" and anims[#anims].enabled == false,
        "the window move animation is off while the canvas is dragged")
    local live = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/rice-infinite.live")
    local t = live and live:read("a") or ""
    if live then live:close() end
    check(t:match("hold 1") ~= nil and t:match("ox=") ~= nil, "the shell is told the canvas is held and where")

    -- at the edge the pointer is put back a little (it cannot leave the screen), so the canvas goes on
    let_go()
    hold(1915)
    ox = RiceInfinite.ox
    move(1919)
    check(#warps > 0 and warps[#warps].x == 1896, "at the edge the pointer is put back inside")
    check(math.abs(RiceInfinite.ox - ox - 4) < 0.001, "the move to the edge still moves it")
    ox = RiceInfinite.ox
    move(1900)
    check(math.abs(RiceInfinite.ox - ox - 4) < 0.001, "the jump back is not counted as movement")

    -- SUPER + ALT + another one of these keys: not the hold (SUPER + CTRL is Next window)
    keys.Control_L = true
    ox = RiceInfinite.ox
    move(1910)
    check(RiceInfinite.ox == ox, "SUPER + ALT + CTRL does not move the canvas")
    keys.Control_L = nil
    tick()                                        -- the hold starts again here (the pointer does not jump)
    ox = RiceInfinite.ox

    -- reversed: the canvas goes the other way
    RiceInfinite.cfg.dir = 2
    move(1890)
    check(math.abs(RiceInfinite.ox - ox - 20) < 0.001, "dir = 2 moves the canvas the other way")
    RiceInfinite.cfg.dir = 1

    -- letting go writes the place down and tells the shell
    let_go()
    check(anims[#anims] and anims[#anims].leaf == "windowsMove" and anims[#anims].enabled == true,
        "the window move animation is back after the drag")
    local st = io.open(os.getenv("HOME") .. "/.config/rice/infinite.state")
    local stt = st and st:read("a") or ""
    if st then st:close() end
    check(stt:match("on=1") ~= nil, "letting go saves the place")
    live = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/rice-infinite.live")
    t = live and live:read("a") or ""
    if live then live:close() end
    check(t:match("hold 0") ~= nil, "letting go tells the shell")
    check(timer.ms == 16, "letting go follows it every 16 ms again")
    RiceInfinite.set(false)
else
    check(#timers == 0, "0.55: no timer, rice-canvasd reads the mouse instead")
end
check((function() local f = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/rice-infinite.poll"); if f then f:close() return true end return false end)() == POLL,
    "the marker for Settings follows the Hyprland")

-- ---- real Hyprland hands a monitor as an object (userdata), not a Lua table. The table-only checks in shown() and
-- visible_place() were skipped on a real monitor (a `type(m) == "table"` test is false): every screen took every
-- workspace, and turning off never clamped a window. These use userdata monitors so it cannot regress. ----
local function umon(name, x, y, aws)
    local d = { name = name, x = x, y = y, width = 1920, height = 1080, scale = 1, transform = 0,
        reserved = { left = 0, top = 0, right = 0, bottom = 0 } }
    d.active_workspace = aws and { id = aws } or nil
    local u = io.tmpfile()
    debug.setmetatable(u, { __index = function(_, k) return d[k] end })
    return u, d
end
local function fire(name, arg) local h = handlers[name]; if h then h(arg) end end

local U1, D1 = umon("DP-1", 0, 0, 1)
local U2, D2 = umon("HDMI-A-1", 1920, 0, 11)
M1, M2 = U1, U2
check(type(U1) == "userdata", "the fake monitor is a userdata object, as Hyprland gives it")

-- every screen: only the workspace each screen shows moves, even with object monitors
active_ws = 1
local ua = win("0x21", 1, U1, 100, 100)
local ub = win("0x22", 11, U2, 2000, 100)
local uc = win("0x23", 3, U1, -3000, 100)     -- a workspace no screen shows
W = { ua, ub, uc }
RiceInfinite.cfg.screens = 0
RiceInfinite.set(true)
local b0 = #moves
RiceInfinite.pan(100, 0)
local na, nb, nc = 0, 0, 0
for i = b0 + 1, #moves do
    if moves[i].window == "address:0x21" then na = na + 1 end
    if moves[i].window == "address:0x22" then nb = nb + 1 end
    if moves[i].window == "address:0x23" then nc = nc + 1 end
end
check(na > 0 and nb > 0, "object monitors: the shown workspace of every screen moves")
check(nc == 0, "object monitors: a window on a workspace no screen shows stays")

-- off clamps a window whose canvas place is far outside the screen (object monitor)
D1.active_workspace = { id = 1 }
active_ws = 1
local z1 = win("0x31", 1, U1, 100, 100, 400, 300)
W = { z1 }
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
RiceInfinite.world["0x31"] = { x = 5000, y = 200, w = 400, h = 300 }   -- as on a far-panned canvas
RiceInfinite.set(false)
check(z1.at.x >= 0 and z1.at.x + z1.size.x <= 1920 and z1.at.y >= 0 and z1.at.y + z1.size.y <= 1080,
    "object monitor: off clamps a window whose canvas place is far outside the screen")

-- switching to another workspace while it is on: that workspace's windows join the canvas and the mouse moves them
D1.active_workspace = { id = 1 }
active_ws = 1
local p1 = win("0x41", 1, U1, 100, 100, 400, 300)
W = { p1 }
RiceInfinite.cfg.screens = 0
RiceInfinite.set(true)
active_ws = 5
D1.active_workspace = { id = 5 }
local p2 = win("0x42", 5, U1, 300, 300, 400, 300)
p2.floating = false
W[#W + 1] = p2
fire("workspace.active", { id = 5 })
local b1 = #moves
RiceInfinite.pan(100, 0)
local n2 = 0
for i = b1 + 1, #moves do if moves[i].window == "address:0x42" then n2 = n2 + 1 end end
check(n2 > 0, "switching workspace: its window joins the canvas and moves")
check(floatarr[#floatarr] == "set", "switching workspace floats it so the canvas can move it")
RiceInfinite.set(false)

-- six windows spread wider than a screen on the canvas come back side by side, not piled in one corner (they used
-- to all clamp to bottom-right and cover a floating app like Mullvad)
D1.active_workspace = { id = 1 }
active_ws = 1
local many = {}
for i = 1, 6 do many[i] = win("0x5" .. i, 1, U1, 100 + (i - 1) * 500, 150, 400, 300) end
local mull = win("0x5e", 1, U1, 1500, 720, 380, 300, true)   -- floating app already in place
many[#many + 1] = mull
W = many
RiceInfinite.cfg.screens = 0
RiceInfinite.layouts = {}     -- a clean turn-on (no remembered canvas from an earlier test)
RiceInfinite.set(true)
RiceInfinite.set(false)
local rects, onscreen, ov = {}, true, 0
for _, w in ipairs(W) do
    if w.at.x < 0 or w.at.y < 0 or w.at.x + w.size.x > 1920 or w.at.y + w.size.y > 1080 then onscreen = false end
    for _, r in ipairs(rects) do
        if w.at.x < r.x + r.w and r.x < w.at.x + w.size.x and w.at.y < r.y + r.h and r.y < w.at.y + w.size.y then ov = ov + 1 end
    end
    rects[#rects + 1] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
end
check(onscreen, "off lays windows that were spread off the screen back on it")
check(ov == 0, "off does not pile those windows on each other")
check(mull.at.x == 1500 and mull.at.y == 720, "off leaves a floating app that was in place where it was")

-- turning on again puts every window back on the canvas exactly where it was, even past the right edge. Clamping
-- each one to the nearest edge there piled Settings over Mullvad (they all slid right on top of each other)
D1.active_workspace = { id = 1 }
active_ws = 1
local c1 = win("0x61", 1, U1, 100, 100, 500, 400)
local c2 = win("0x62", 1, U1, 700, 300, 600, 450)
local c3 = win("0x63", 1, U1, 1450, 760, 380, 280, true)
W = { c1, c2, c3 }
RiceInfinite.cfg.screens = 0
RiceInfinite.layouts = {}
RiceInfinite.set(true)
RiceInfinite.pan(2000, 0)
local want = {}
for _, w in ipairs(W) do want[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y } end
RiceInfinite.set(false)
RiceInfinite.set(true)
for _, w in ipairs(W) do
    local s = want[w.address]
    check(w.at.x == s.x and w.at.y == s.y and w.size.x == s.w and w.size.y == s.h,
        "on again puts " .. w.address .. " back on the canvas where it was")
end
RiceInfinite.set(false)

-- ALT + TAB to a window the canvas left far off screen glides the canvas so it sits in the middle of its screen.
-- Only the axis out of sight moves: a window off to the left at the same height comes in sideways and the canvas
-- does not drift up or down (a floating app on the left, such as Mullvad, keeps its height).
D1.active_workspace = { id = 1 }
active_ws = 1
local far = win("0x71", 1, U1, 2600, 200, 400, 300)
W = { far }
RiceInfinite.cfg.screens = 0
RiceInfinite.layouts = {}
RiceInfinite.set(true)
RiceInfinite.reveal("0x71")
check(math.abs(far.at.x + far.size.x / 2 - 960) <= 2, "Alt + Tab to a window off screen glides it to the middle sideways")
check(far.at.y == 200, "Alt + Tab sideways leaves the height of everything alone")
local before = #moves
RiceInfinite.reveal("0x71")
check(#moves == before, "Alt + Tab to a window already in sight leaves the canvas still")
RiceInfinite.set(false)

-- a window out of sight on both axes moves diagonally, each axis to its own middle
local corner = win("0x72", 1, U1, 2600, -500, 400, 300)
W = { corner }
RiceInfinite.set(false)
RiceInfinite.layouts = {}
RiceInfinite.set(true)
RiceInfinite.reveal("0x72")
check(math.abs(corner.at.x + corner.size.x / 2 - 960) <= 2 and math.abs(corner.at.y + corner.size.y / 2 - 540) <= 2,
    "Alt + Tab to a window out of sight both ways glides diagonally to its middle")
RiceInfinite.set(false)

-- a window only a little above the screen (or taller than it) still comes in sideways: the canvas is a row, so a
-- small vertical stick-out must not drag the whole view (and a floating app on the left) up or down
D1.active_workspace = { id = 1 }
active_ws = 1
local edge = win("0x73", 1, U1, 2600, -100, 400, 300)
W = { edge }
RiceInfinite.cfg.screens = 0
RiceInfinite.layouts = {}
RiceInfinite.set(true)
RiceInfinite.reveal("0x73")
check(edge.at.y == -100, "Alt + Tab keeps the height when the window only sticks out a little above")
check(math.abs(edge.at.x + edge.size.x / 2 - 960) <= 2, "Alt + Tab still brings that window in sideways")
RiceInfinite.set(false)
