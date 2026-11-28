import Quickshell
import Quickshell.Io
import QtQuick

// Settings > Desktop > Infinite Desktop: the windows of a workspace float on an endless canvas that you move (and on
// Hyprland zoom). Hyprland only (rice-infinite.lua does the work); on niri the page only says so (V4.23).
// Your keys: Keys, below (rice-infinite key ...).
Item {
    id: page
    property var ctl
    readonly property bool niri: !!Quickshell.env("NIRI_SOCKET")
    property var st: ({ keys: { key_toggle: "SUPER + F", mod_hold: "SUPER + ALT", mod_go: "SUPER + CTRL", mod_zoom: "CTRL" }, on: false, zoom: 1, step: 0.12, min: 0.2, pan: 180, speed: 1.0, dir: 1, push: 1, screens: 0, poll: false, input: true, daemon: true, devices: null, loaded: true })

    function sh(args) { runner.command = ["bash", "-c", "\"$HOME/.local/bin/rice-infinite\" \"$@\" 2>&1", "_"].concat(args); runner.running = true }
    function fmt(n) { return String(Math.round(n * 100) / 100) }
    function kv(k, d) { return page.st.keys && page.st.keys[k] ? page.st.keys[k] : d }
    function nice(k) { return String(k).split(" + ").map(function(p) { return p.length > 1 ? p.charAt(0) + p.slice(1).toLowerCase() : p }).join(" + ") }
    function setKey(k, v) { page.sh(["key", k, v]); const n = Object.assign({}, page.st); n.keys = Object.assign({}, page.st.keys || {}); n.keys[k] = v; page.st = n }

    Process {
        id: stateProc
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-infinite\" state"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.st = JSON.parse(text) } catch (e) { } } }
    }
    Process { id: runner; stdout: StdioCollector { onStreamFinished: stateLater.restart() } }
    Timer { id: stateLater; interval: 350; onTriggered: stateProc.running = true }
    Timer { interval: 2000; running: page.visible; repeat: true; onTriggered: if (!stateProc.running) stateProc.running = true }
    onVisibleChanged: if (visible) stateProc.running = true

    component KeyPick: SettingRow {
        id: kp
        property string key: ""
        property var choices: []
        reserved: 520
        Seg {
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            options: kp.choices.map(function(c) { return { value: c, label: page.nice(c) } })
            current: page.kv(kp.key, kp.choices[0])
            onChosen: v => page.setKey(kp.key, v)
        }
    }
    PageScroll {
        anchors.fill: parent

        // ---------- the switch, with a little canvas that breathes ----------
        Rectangle {
            width: parent.width
            height: 210
            radius: M3.sq ? 0 : (M3.rXL)
            color: page.st.on ? M3.primaryContainer : M3.surfaceC
            clip: true
            Behavior on color { ColorAnimation { duration: 220 } }
            // the canvas: windows that come together when it zooms out
            Item {
                id: art
                width: 260; height: 170
                anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
                property real k: 1
                SequentialAnimation on k {
                    loops: Animation.Infinite; running: page.visible
                    NumberAnimation { to: 0.55; duration: 1600; easing.type: Easing.InOutCubic }
                    PauseAnimation { duration: 700 }
                    NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutCubic }
                    PauseAnimation { duration: 700 }
                }
                Repeater {
                    model: [[-80, -40, 120, 80], [56, -52, 110, 64], [-20, 46, 96, 70], [100, 36, 84, 92], [-150, 30, 70, 56], [170, -70, 80, 60]]
                    Rectangle {
                        readonly property var g: modelData
                        width: g[2] * art.k; height: g[3] * art.k
                        x: art.width / 2 + g[0] * art.k - width / 2; y: art.height / 2 + g[1] * art.k - height / 2
                        radius: M3.sq ? 0 : (10 * art.k)
                        color: index === 0 ? M3.primary : M3.alpha(page.st.on ? M3.inkPrimaryC : M3.ink, 0.10 + 0.05 * (index % 3))
                        border.width: 1; border.color: M3.alpha(M3.ink, 0.12)
                        Rectangle { x: 6 * art.k; y: 6 * art.k; width: parent.width * 0.4; height: 4 * art.k; radius: M3.sq ? 0 : (2); color: M3.alpha(M3.ink, 0.18) }
                    }
                }
            }
            Column {
                x: 24; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - art.width - 64
                spacing: 6
                T { text: I18n.t("INFINITE DESKTOP"); font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.2
                    color: M3.alpha(page.st.on ? M3.inkPrimaryC : M3.ink, 0.7) }
                T { kind: "title"; text: page.niri ? I18n.t("Hyprland only") : page.st.on ? I18n.t("On") + (page.niri ? "" : " · " + Math.round(page.st.zoom * 100) + " %") : I18n.t("Off"); font.pixelSize: 28; font.weight: Font.Medium
                    color: page.st.on ? M3.inkPrimaryC : M3.ink }
                T { kind: "reading"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; color: M3.alpha(page.st.on ? M3.inkPrimaryC : M3.ink, 0.8)
                    text: page.niri ? I18n.t("Infinite Desktop is made for Hyprland (it zooms and moves the windows on an endless canvas). niri scrolls its own way already, so here it is off.")
                                    : I18n.t("Your windows float on an endless canvas: zoom out to see them all, move the canvas to where you work.") }
                Item { width: 1; height: 4 }
                Btn {
                    visible: !page.niri
                    text: page.st.on ? I18n.t("Turn off") : I18n.t("Turn on"); sym: page.st.on ? "close_fullscreen" : "open_in_full"; icon: ""
                    variant: page.st.on ? "tonal" : "filled"
                    onClicked: { page.sh([page.st.on ? "off" : "on"]); const n = Object.assign({}, page.st); n.on = !n.on; page.st = n }
                }
            }
        }

        T {
            visible: !page.niri && page.st.loaded === false
            width: parent.width; wrapMode: Text.WordWrap; color: M3.error
            text: I18n.t("Run the update once more (rice-update) so Hyprland loads it.")
        }

        // ---------- how it feels ----------
        SectionTitle { text: I18n.t("How it feels") }
        SettingRow {
            label: I18n.t("When you move the mouse")
            desc: page.st.dir === 2 ? I18n.t("The canvas goes the other way, like looking around") : I18n.t("The windows follow the mouse, like pushing a sheet of paper")
            reserved: 420
            Seg {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "1", label: I18n.t("Follow") }, { value: "2", label: I18n.t("Reversed") }]
                current: String(page.st.dir || 1)
                onChosen: v => { page.sh(["set", "dir", v]); const n = Object.assign({}, page.st); n.dir = Number(v); page.st = n }
            }
        }
        SliderRow {
            label: I18n.t("Sensitivity of the mouse")
            desc: I18n.t("1.00x: the window under the pointer stays under it. Lower is calmer, higher goes farther")
            from: 0.3; to: 3; step: 0.05; decimals: 2; unit: "x"
            value: page.st.speed || 1.0
            onCommitted: function(v) { page.sh(["set", "speed", String(Math.round(v * 100) / 100)]); const n = Object.assign({}, page.st); n.speed = v; page.st = n }
        }
        SettingRow {
            visible: !page.niri
            label: I18n.t("Screens")
            desc: page.st.screens === 1 ? I18n.t("The canvas is the workspace you turn it on: the screens on either side keep their own windows, which stay where they are") : I18n.t("Every screen is one canvas, side by side as the screens are: a drag that leaves a screen goes on the other one, and a new window gets its room on its own screen")
            reserved: 420
            Seg {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "0", label: I18n.t("Every screen") }, { value: "1", label: I18n.t("This workspace") }]
                current: page.st.screens === 1 ? "1" : "0"
                onChosen: v => { page.sh(["set", "screens", v]); const n = Object.assign({}, page.st); n.screens = Number(v); page.st = n }
            }
        }
        ToggleRow {
            visible: !page.niri
            label: I18n.t("The wallpaper moves with it")
            desc: I18n.t("Moving around the canvas also moves the wallpaper, slower than the windows, as if you travelled over a big picture")
            checked: page.st.wall !== 0
            onToggled: function(v) { page.sh(["set", "wall", v ? "1" : "0"]); const n = Object.assign({}, page.st); n.wall = v ? 1 : 0; page.st = n }
        }
        SliderRow {
            visible: !page.niri && page.st.wall !== 0
            label: I18n.t("Wallpaper zoom")
            desc: I18n.t("How much bigger the moving wallpaper is: lower looks closer to your wallpaper, higher gives it more room to move")
            from: 1.05; to: 1.5; step: 0.01; decimals: 2; unit: "x"
            value: page.st.wallzoom || 1.15
            onCommitted: function(v) { page.sh(["set", "wallzoom", String(Math.round(v * 100) / 100)]); const n = Object.assign({}, page.st); n.wallzoom = v; page.st = n }
        }
        ToggleRow {
            visible: !page.niri
            label: I18n.t("The bar and the dock step aside while you move")
            desc: I18n.t("Holding the keys and moving the mouse slides the bar and the dock away; they come back when you let go")
            checked: page.st.hidebar !== 0
            onToggled: function(v) { page.sh(["set", "hidebar", v ? "1" : "0"]); const n = Object.assign({}, page.st); n.hidebar = v ? 1 : 0; page.st = n }
        }
        SettingRow {
            visible: !page.niri
            label: I18n.t("Zoom speed")
            desc: I18n.t("How much one turn of the wheel zooms")
            reserved: 300
            Seg {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "0.06", label: I18n.t("Slow") }, { value: "0.12", label: I18n.t("Normal") }, { value: "0.22", label: I18n.t("Fast") }]
                current: page.st.step <= 0.08 ? "0.06" : (page.st.step >= 0.18 ? "0.22" : "0.12")
                onChosen: v => { page.sh(["set", "step", v]); const n = Object.assign({}, page.st); n.step = Number(v); page.st = n }
            }
        }
        SettingRow {
            visible: !page.niri
            label: I18n.t("Zoom out as far as")
            desc: I18n.t("Smaller means more windows fit on the screen")
            reserved: 300
            Seg {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "0.5", label: "50 %" }, { value: "0.3", label: "30 %" }, { value: "0.2", label: "20 %" }, { value: "0.1", label: "10 %" }]
                current: page.fmt(page.st.min)
                onChosen: v => { page.sh(["set", "min", v]); const n = Object.assign({}, page.st); n.min = Number(v); page.st = n }
            }
        }
        SettingRow {
            label: I18n.t("Move step")
            desc: I18n.t("How far the canvas moves for one turn of the wheel or one arrow")
            reserved: 300
            Seg {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "100", label: I18n.t("Short") }, { value: "180", label: I18n.t("Normal") }, { value: "320", label: I18n.t("Long") }]
                current: page.st.pan <= 120 ? "100" : (page.st.pan >= 260 ? "320" : "180")
                onChosen: v => { page.sh(["set", "pan", v]); const n = Object.assign({}, page.st); n.pan = Number(v); page.st = n }
            }
        }
        Rectangle {
            width: parent.width; height: note.implicitHeight + 24; radius: M3.sq ? 0 : (M3.rM); color: M3.alpha(M3.primary, 0.08)
            T { id: note; x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 32; wrapMode: Text.WordWrap; font.pixelSize: 12; color: M3.inkDim
                text: I18n.t("A new window gets its own room next to the one you were in, and the canvas glides to it, so there is always space. Zooming really makes the windows smaller (apps may keep a smallest size). Turning it off tiles the windows again, and the canvas is remembered: turn it on again (also after a restart) and every window is where you left it.") }
        }
        // ---------- the keys: yours to change ----------
        SectionTitle { text: I18n.t("Keys"); sub: I18n.t("Pick the keys you like. The ones with arrows and the wheel work while it is on, on the workspace where you turned it on.") }
        KeyPick { label: I18n.t("On / off"); desc: page.nice(page.kv("key_toggle", "")); key: "key_toggle"
            choices: page.niri ? ["SUPER + ALT + F", "SUPER + ALT + I", "SUPER + CTRL + I"] : ["SUPER + F", "SUPER + ALT + F", "SUPER + I"] }
        KeyPick { label: I18n.t("Hold and move the mouse"); desc: I18n.t("The whole canvas moves with the mouse; with the arrows: one step"); key: "mod_hold"
            choices: ["SUPER + ALT", "SUPER + SHIFT", "CTRL + ALT"] }
        KeyPick { label: I18n.t("Next window") + " (+ " + I18n.t("Arrows") + ")"; desc: I18n.t("Go to the next window that way (the canvas glides to it)"); key: "mod_go"
            choices: page.niri ? ["SUPER + ALT + SHIFT", "CTRL + ALT", "SUPER + CTRL"] : ["SUPER + CTRL", "SUPER + ALT + SHIFT", "CTRL + ALT"] }
        KeyPick { visible: !page.niri; label: I18n.t("Zoom") + " (+ " + I18n.t("Mouse wheel") + ")"; desc: I18n.t("Zoom out (down) and in (up) around the pointer"); key: "mod_zoom"
            choices: ["CTRL", "SUPER + CTRL", "ALT"] }
        T { kind: "reading"; visible: !page.niri; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 11; color: M3.inkDim
            text: I18n.t("SUPER + Mouse wheel moves the canvas up and down, SUPER + SHIFT + Mouse wheel left and right, and + 0 goes back to 100 %.") }
        T { kind: "reading"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 11; color: M3.inkDim; topPadding: 6
            text: I18n.t("Based on hyprland-infinite-desktop-v2 by Sarods2D (github.com/sarodscommits).") }
    }
}
