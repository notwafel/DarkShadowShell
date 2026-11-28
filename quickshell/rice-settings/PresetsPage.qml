import Quickshell
import Quickshell.Io
import QtQuick

// Settings > Appearance > Presets (V5.04): a whole desktop in one click. The big picture shows the chosen preset
// as your desktop, its launcher, its lock screen and its login screen; under it what it sets, and Use. All eight
// below as small desktops. The first preset you use keeps how your desktop looked (My setup), to go back to.
Item {
    id: page
    property var ctl
    property var pd: ({ current: "", presets: [], before: null })
    property string sel: ""
    property string mode: "desktop"
    property string busy: ""
    property var live: ({})
    function find(k) { const l = pd.presets || []; for (let i = 0; i < l.length; i++) if (l[i].key === k) return l[i]; return null }
    readonly property var cur: find(sel) || find(pd.current) || ((pd.presets || []).length ? pd.presets[0] : null)

    Process {
        id: listP
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-preset\" list 2>/dev/null"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.pd = JSON.parse(text) } catch (e) { } } }
    }
    onVisibleChanged: if (visible && !listP.running) listP.running = true
    Process {
        id: run
        stderr: StdioCollector { id: runErr }
        onExited: function(code) {
            const name = page.busy === "before" ? I18n.t("My setup") : (page.find(page.busy) ? page.find(page.busy).name : "")
            page.busy = ""
            const why = runErr.text.trim().split("\n").pop()
            if (page.ctl) page.ctl.status = code === 0 ? I18n.t("Preset: %1", name) : (why !== "" ? why : I18n.t("That did not work"))
            listP.running = true
        }
    }
    function use(key) {
        if (run.running) return
        busy = key
        live = ({ step: I18n.t("Starting"), n: 0, total: 8 })
        run.command = ["bash", "-c", "\"$HOME/.local/bin/rice-preset\" apply \"$1\"", "_", key]
        run.running = true
    }
    // how far it is (rice-preset writes each step)
    Process {
        id: liveP
        command: ["bash", "-c", "cat \"$HOME/.cache/rice/preset-live.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { page.live = JSON.parse(text) } catch (e) { } } }
    }
    Timer { interval: 500; repeat: true; running: page.busy !== ""; onTriggered: if (!liveP.running) liveP.running = true }

    // what a preset sets, in words
    readonly property var names: ({
        dynamic: "Dynamic island", flat: "Flat", island: "Island", islands: "Islands", pills: "Pills", notch: "Notch", edge: "Edge",
        drawer: "Drawer", spotlight: "Spotlight", side: "Side sheet",
        expressive: "Expressive", stacked: "Stacked", shape: "Shape", analog: "Analog", digital: "Digital", line: "Line", cookie: "Cookie", pixel: "Pixel",
        floating: "Floating", full: "Full width",
        glance: "Glance", cards: "Cards", classic: "Classic", center: "Center", pill: "Pill", shapes: "Shapes",
        calm: "Calm", emphasized: "Emphasized", glide: "Glide", pop: "Pop",
        top: "top", bottom: "bottom", left: "left", right: "right"
    })
    function nm(k) { return I18n.t(names[k] || k || "") }
    function parts(p) {
        if (!p) return []
        const ex = p.extra || {}
        return [
            { i: "toolbar", t: I18n.t("Bar"), v: nm(p.theme.bar) + ", " + nm(p.bar.position) + (p.bar.autohide ? " · " + I18n.t("hides") : "") },
            { i: "search", t: I18n.t("Launcher"), v: nm(p.launcher.layout) },
            { i: "schedule", t: I18n.t("Clock"), v: p.clock.enabled === false ? I18n.t("Off") : nm(p.clock.style) },
            { i: "dock_to_bottom", t: I18n.t("Dock"), v: p.dock.enabled ? nm(p.dock.style) + (p.dock.magnify > 0 ? " · " + I18n.t("grows") : "") : I18n.t("Off") },
            { i: "lock", t: I18n.t("Lock screen"), v: nm(ex.lock_style) },
            { i: "login", t: I18n.t("Login screen"), v: nm(p.sddm) },
            { i: "animation", t: I18n.t("Motion"), v: nm(ex.anim_style) },
            { i: "palette", t: I18n.t("Colors"), v: I18n.t(p.theme.colors === "auto" ? "From the wallpaper" : p.theme.colors.charAt(0).toUpperCase() + p.theme.colors.slice(1)) }
        ]
    }

    PageScroll {
        anchors.fill: parent

        SectionTitle { text: I18n.t("Presets"); sym: "auto_awesome"
            sub: I18n.t("A whole desktop in one click: the wallpaper and its colors, the bar, the launcher, the clock, the dock, the lock and login screens, notifications and how windows move.") }

        // ---------- the chosen one, big ----------
        Rectangle {
            id: hero
            width: parent.width
            height: heroCol.height + 28
            radius: M3.sq ? 0 : M3.rL
            color: M3.surfaceC
            Column {
                id: heroCol
                x: 14; y: 14
                width: parent.width - 28
                spacing: 14
                Item {
                    width: parent.width
                    height: big.height
                    PresetPreview {
                        id: big
                        width: parent.width
                        p: page.cur
                        mode: page.mode
                        radius: M3.rL - 6
                        cornerColor: M3.surfaceC
                    }
                }
                // Desktop, Launcher, Lock screen, Login screen
                Item {
                    width: parent.width; height: 44
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 44; width: modeRow.width + 12; radius: M3.sq ? 0 : 22
                        color: M3.surfaceHigh
                        Row {
                            id: modeRow
                            anchors.centerIn: parent; spacing: 4
                            Repeater {
                                model: [{ k: "desktop", n: "Desktop", i: "desktop_windows" }, { k: "launcher", n: "Launcher", i: "apps" },
                                        { k: "lock", n: "Lock screen", i: "lock" }, { k: "login", n: "Login screen", i: "login" }]
                                delegate: Rectangle {
                                    readonly property bool on: page.mode === modelData.k
                                    height: 34; width: mr.implicitWidth + 24; radius: M3.sq ? 0 : 17
                                    color: on ? M3.primary : (mm.containsMouse ? M3.surfaceHighest : "transparent")
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    Row { id: mr; anchors.centerIn: parent; spacing: 6
                                        Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.i; glyph: ""; size: 15; color: parent.parent.on ? M3.inkPrimary : M3.ink }
                                        T { anchors.verticalCenter: parent.verticalCenter; text: I18n.t(modelData.n); font.pixelSize: 12; font.weight: Font.DemiBold; color: parent.parent.on ? M3.inkPrimary : M3.ink } }
                                    MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.mode = modelData.k }
                                }
                            }
                        }
                    }
                }
                // its name, what it is like, Use
                Item {
                    width: parent.width
                    height: Math.max(info.height, useBox.height)
                    Column {
                        id: info
                        width: parent.width - useBox.width - 20
                        spacing: 4
                        Row {
                            spacing: 10
                            T { text: page.cur ? page.cur.name : ""; font.pixelSize: 26; font.weight: Font.DemiBold }
                            Rectangle {
                                visible: !!page.cur && page.pd.current === page.cur.key
                                anchors.verticalCenter: parent.verticalCenter
                                height: 24; width: inUse.implicitWidth + 20; radius: M3.sq ? 0 : 12; color: M3.primaryContainer
                                T { id: inUse; anchors.centerIn: parent; text: I18n.t("In use"); font.pixelSize: 11; font.weight: Font.DemiBold; color: M3.inkPrimaryC }
                            }
                        }
                        T { kind: "reading"; width: parent.width; wrapMode: Text.WordWrap; text: page.cur ? I18n.t(page.cur.desc) : ""; font.pixelSize: 13; color: M3.inkDim }
                    }
                    Column {
                        id: useBox
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Btn {
                            anchors.right: parent.right
                            primary: true
                            enabled: page.busy === "" && !!page.cur
                            sym: page.cur && page.pd.current === page.cur.key ? "refresh" : "auto_awesome"; icon: ""
                            text: page.busy !== "" ? I18n.t("Applying...") : (page.cur && page.pd.current === page.cur.key ? I18n.t("Use again") : I18n.t("Use this preset"))
                            onClicked: if (page.cur) page.use(page.cur.key)
                        }
                        // the steps while it works
                        Item {
                            visible: page.busy !== ""
                            anchors.right: parent.right
                            width: 220; height: 22
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: M3.surfaceHighest
                                Rectangle { width: parent.width * Math.max(0.06, (page.live.n || 0) / (page.live.total || 8)); height: parent.height; radius: 3; color: M3.primary
                                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } }
                        }
                        T { visible: page.busy !== ""; anchors.right: parent.right; text: I18n.t(page.live.step || ""); font.pixelSize: 11; color: M3.inkDim }
                    }
                }
                // what it sets
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: page.parts(page.cur)
                        delegate: Rectangle {
                            height: 52; width: pr.implicitWidth + 28; radius: M3.sq ? 0 : 16
                            color: M3.surfaceHigh
                            Row { id: pr; anchors.centerIn: parent; spacing: 10
                                Item { width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
                                    Blob { anchors.fill: parent; kind: index % 2 ? "circle" : Prefs.accentShape; color: M3.secondaryContainer }
                                    Icon { anchors.centerIn: parent; name: modelData.i; glyph: ""; size: 15; color: M3.inkSecondaryC } }
                                Column { anchors.verticalCenter: parent.verticalCenter
                                    T { text: modelData.t; font.pixelSize: 11; color: M3.inkDim }
                                    T { text: modelData.v; font.pixelSize: 13; font.weight: Font.Medium } }
                            }
                        }
                    }
                }
            }
        }

        // ---------- all of them ----------
        SectionTitle { text: I18n.t("All presets"); sym: "grid_view"; sub: I18n.t("Pick one to see it above, then Use this preset.") }
        Grid {
            id: grid
            width: parent.width
            columns: width > 900 ? 4 : (width > 560 ? 3 : 2)
            spacing: 12
            Repeater {
                model: page.pd.presets || []
                delegate: Item {
                    id: card
                    readonly property bool on: !!page.cur && page.cur.key === modelData.key
                    readonly property bool used: page.pd.current === modelData.key
                    width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                    height: mini.height + 62
                    readonly property color face: card.on ? M3.secondaryContainer : (cm.containsMouse ? M3.surfaceHigh : M3.surfaceC)
                    Rectangle {
                        anchors.fill: parent
                        radius: M3.sq ? 0 : M3.rL
                        color: card.face
                        border.width: card.on ? 2 : 0; border.color: M3.primary
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    PresetPreview {
                        id: mini
                        x: 8; y: 8
                        width: parent.width - 16
                        p: modelData
                        radius: M3.rM
                        cornerColor: card.face
                    }
                    Row {
                        x: 14; y: mini.y + mini.height + 10
                        spacing: 8
                        T { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: 14; font.weight: Font.DemiBold
                            color: card.on ? M3.inkSecondaryC : M3.ink }
                        Rectangle { visible: card.used; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: M3.sq ? 0 : 9; color: M3.primary
                            Icon { anchors.centerIn: parent; name: "check"; glyph: ""; size: 12; color: M3.inkPrimary } }
                        T { visible: page.busy === modelData.key; anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Applying..."); font.pixelSize: 11; color: M3.primary }
                    }
                    T { x: 14; y: mini.y + mini.height + 32; width: parent.width - 28; elide: Text.ElideRight
                        text: (modelData.tags || []).map(function(t) { return I18n.t(t) }).join("  ·  "); font.pixelSize: 11; color: M3.inkDim }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { page.sel = modelData.key; page.mode = "desktop" }
                        onDoubleClicked: page.use(modelData.key) }
                }
            }
        }

        // ---------- back to how it was ----------
        SettingRow {
            visible: !!page.pd.before
            label: I18n.t("My setup")
            desc: I18n.t("How your desktop looked before the first preset: the wallpaper, the colors, the bar, the launcher, the clock, the dock and the lock screen")
            reserved: 200
            Btn { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                enabled: page.busy === ""; text: I18n.t("Go back"); sym: "undo"; icon: ""; onClicked: page.use("before") }
        }
    }
}
