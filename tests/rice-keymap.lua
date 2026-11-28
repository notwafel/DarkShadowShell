-- rice-keymap.lua with a fake Hyprland: what SUPER + SHIFT + F does to a game that runs its own fullscreen (CS2)
-- and to an ordinary window. Run by tests/keymap.sh.
local path = arg[1]
local n = 0
local function ok(msg) n = n + 1; print("ok " .. n .. " - " .. msg) end
local function bad(msg) print("not ok " .. (n + 1) .. " - " .. msg); os.exit(1) end
local function check(c, msg) if c then ok(msg) else bad(msg) end end

local calls = {}
local win = { class = "cs2", fullscreen = 0, fullscreen_client = 2 }
local fullscreen_key
hl = {
    bind = function(keys, d) if keys == "SUPER + SHIFT + F" then fullscreen_key = d end end,
    unbind = function() end,
    dispatch = function(d) if type(d) == "function" then d() end end,
    get_active_window = function() return win end,
    dsp = {
        exec_cmd = function() return function() end end,
        window = {
            close = function() return function() end end,
            float = function() return function() end end,
            fullscreen = function() return function() calls[#calls + 1] = "fullscreen" end end,
            fullscreen_state = function(t) return function() calls[#calls + 1] = string.format("state %s/%s", t.internal, t.client) end end,
        },
    },
}

assert(loadfile(path))()
check(type(fullscreen_key) == "function", "SUPER + SHIFT + F is bound and checked on every press")

fullscreen_key()
check(calls[#calls] == "state 0/0", "a game that runs its own fullscreen is asked to leave it, not resized by the compositor")

win.fullscreen_client = 0
fullscreen_key()
check(calls[#calls] == "fullscreen", "an ordinary window still gets the normal fullscreen toggle")