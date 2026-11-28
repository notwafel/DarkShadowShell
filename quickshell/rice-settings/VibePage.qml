import Quickshell
import Quickshell.Io
import QtQuick

// Settings > Appearance > Vibe (V6.10): the desktop goes with your music. The colors of the cover, the visualizer
// on the bar (Liquid, Dots or Bars), a light along the bottom of the screen, the island that breathes, moving
// wallpapers that dance, a ring around the cover on the lock screen, and the weather outside on the desktop
// (rice-vibe; ~/.config/rice/vibe.json). The stage at the top plays a song so you can see it all.
Item {
    id: page
    property var ctl
    property var vb: ({})
    property var bq: ({})
    function v(k, d) { return vb[k] !== undefined ? vb[k] : d }
    function setv(key, value) {
        const n = Object.assign({}, vb)
        n[key] = value === "on" ? true : value === "off" ? false : value
        vb = n
        Quickshell.execDetached(["bash", "-c", "\"$HOME/.local/bin/rice-vibe\" set \"$1\" \"$2\"", "_", key, String(value)])
        page.ctl.status = I18n.t("Applied")
    }
    function tryIt(w) {
        Quickshell.execDetached(["bash", "-c", "\"$HOME/.local/bin/rice-vibe\" try \"$1\"", "_", w])
        page.ctl.status = I18n.t("On your desktop for a minute")
    }
    Process {
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-vibe\" state 2>/dev/null"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.vb = JSON.parse(text) } catch (e) { } } }
    }
    // is the visualizer on the bar, and is a place set for the weather?
    Process {
        id: barP
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-bar\" state 2>/dev/null; echo; \"$HOME/.local/bin/rice-weather\" state 2>/dev/null; echo; head -c 4000 \"$HOME/.cache/rice/weather.json\" 2>/dev/null; echo"]
        running: true
        stdout: StdioCollector { onStreamFinished: {
            const l = text.split("\n").filter(function(x) { return x.trim() !== "" })
            page.cond = ""
            for (const x of l) {
                let j = null
                try { j = JSON.parse(x) } catch (e) { continue }
                if (j.layout !== undefined || j.style !== undefined) page.bq = j
                else if (j.cond !== undefined) page.cond = j.cond
                else if (j.place !== undefined) page.place = j.place || ""
            }
        } }
    }
    onVisibleChanged: if (visible && !barP.running) barP.running = true
    property string place: ""
    property string cond: ""
    // the same words as the desktop (Vibe.qml skyOf): what falls for this weather
    function fallOf(c) {
        c = (c || "").toLowerCase()
        if (/thunder/.test(c)) return "storm"
        if (/snow|sleet|blizzard|ice pellets|freezing/.test(c)) return "snow"
        if (/rain|drizzle|shower/.test(c)) return "rain"
        if (/fog|mist|haze/.test(c)) return "fog"
        return ""
    }
    readonly property var kinds: [
        { v: "live", t: "The weather outside", sym: "partly_cloudy_day" },
        { v: "rain", t: "Rain", sym: "rainy" }, { v: "snow", t: "Snow", sym: "ac_unit" },
        { v: "storm", t: "Storm", sym: "thunderstorm" }, { v: "fog", t: "Fog", sym: "foggy" },
        { v: "petals", t: "Cherry petals", sym: "local_florist" }, { v: "fireflies", t: "Fireflies", sym: "flare" }
    ]
    readonly property bool vizOnBar: ["left", "center", "right"].some(function(z) { return ((page.bq.layout || {})[z] || []).indexOf("visualizer") >= 0 })

    // ---------- the stage: a song plays ----------
    // the covers of the songs it plays (two colors each): the stage takes them like your desktop will
    readonly property var songs: [
        { t: "Midnight Drive", a: "Neon Coast", c1: "#ff8fb1", c2: "#8f9bff" },
        { t: "Low Tide", a: "Marina Hall", c1: "#6fd6c4", c2: "#5aa2ff" },
        { t: "Ember", a: "The Lanterns", c1: "#ffb36b", c2: "#ff6f6f" },
        { t: "Forest Radio", a: "Pines", c1: "#a8d672", c2: "#e6d36a" }
    ]
    property int song: 0
    readonly property color k1: page.v("cover", true) ? songs[song].c1 : M3.primary
    readonly property color k2: page.v("cover", true) ? songs[song].c2 : M3.tertiary
    property color c1: k1
    property color c2: k2
    Behavior on c1 { ColorAnimation { duration: 700; easing.type: Easing.InOutCubic } }
    Behavior on c2 { ColorAnimation { duration: 700; easing.type: Easing.InOutCubic } }
    Timer { running: page.visible; interval: 5200; repeat: true; onTriggered: page.song = (page.song + 1) % page.songs.length }
    // a made-up song: a kick on every beat and a few melodies over it
    property real tk: 0
    property real beat: 0
    property var bands: []
    Timer {
        running: page.visible; interval: 33; repeat: true
        onTriggered: {
            page.tk += 0.033
            const ph = (page.tk * 2.05) % 1, kick = Math.exp(-ph * 7), b = []
            for (let i = 0; i < 64; i++) {
                const low = Math.exp(-i / 7) * (55 + 45 * kick)
                const mel = 26 * Math.pow(Math.sin(i * 0.31 + page.tk * 3.1), 2) * Math.exp(-i / 40) + 14 * Math.pow(Math.sin(i * 0.9 - page.tk * 5), 2) * Math.exp(-i / 25)
                b.push(Math.min(100, low + mel))
            }
            page.bands = b
            page.beat = kick
            barLiq.take(b); edgeA.take(b); edgeW.take(b)
        }
    }
    function lvl(i, n) { const b = page.bands; if (!b || b.length < 8) return 0; const j = Math.floor(i * 48 / n); return Math.min(1, (b[j] || 0) / 100) }

    PageScroll {
        anchors.fill: parent

        Rectangle {
            id: stage
            width: parent.width; height: 236
            radius: M3.sq ? 0 : M3.rL
            clip: true
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(M3.surfaceLow, Qt.rgba(page.c2.r, page.c2.g, page.c2.b, 0.16)) }
                GradientStop { position: 1; color: Qt.tint(M3.surfaceLowest, Qt.rgba(page.c1.r, page.c1.g, page.c1.b, 0.1)) }
            }
            // the weather on the desktop
            Item {
                anchors.fill: parent
                visible: page.v("weather", false)
                rotation: 8
                Repeater {
                    model: 46
                    delegate: Rectangle {
                        readonly property real sp: 0.6 + Math.random() * 0.4
                        x: Math.random() * stage.width; width: 1.3; height: 12 + sp * 12; radius: 1
                        color: Qt.rgba(0.85, 0.92, 1, 0.18 + 0.25 * sp)
                        NumberAnimation on y { running: page.visible && page.v("weather", false); loops: Animation.Infinite
                            from: -30 - Math.random() * stage.height; to: stage.height + 10; duration: (stage.height + 40) / (0.5 + sp * 0.5) }
                    }
                }
            }
            // the light along the bottom
            Item {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 96
                opacity: page.v("edge", false) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } }
                LiquidWave { id: edgeA; anchors.fill: parent; mode: "bottom"; vertical: true; points: 16; fall: 0.93; floor: 0.04; c1: page.c1; c2: page.c2
                    fillA: page.v("edge_style", "glow") === "glow" ? 0.3 : 0.14 }
                LiquidWave { id: edgeW; anchors.fill: parent; anchors.topMargin: 18; mode: "bottom"; points: 30; floor: 0.03
                    vertical: page.v("edge_style", "glow") === "glow"; c1: page.c1; c2: page.v("edge_style", "glow") === "glow" ? page.c1 : page.c2
                    fillA: page.v("edge_style", "glow") === "glow" ? 0.6 : 0.3; lineW: page.v("edge_style", "glow") === "glow" ? 0 : 2 }
            }
            // the bar
            Rectangle {
                id: mbar
                x: 16; y: 14; width: parent.width - 32; height: 38; radius: M3.sq ? 0 : 19
                color: Qt.rgba(0, 0, 0, 0.38)
                Row { x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                    Repeater { model: 4; delegate: Rectangle { anchors.verticalCenter: parent.verticalCenter; width: index === 1 ? 24 : 8; height: 8; radius: M3.sq ? 0 : 4
                        color: index === 1 ? page.c1 : Qt.rgba(1, 1, 1, 0.3) } } }
                // the island, breathing
                Rectangle {
                    id: misl
                    anchors.centerIn: parent
                    width: 132; height: 28; radius: M3.sq ? 0 : 14
                    color: M3.surface
                    Rectangle { anchors.fill: parent; anchors.margins: -2 - 3 * page.beat; radius: M3.sq ? 0 : height / 2; color: "transparent"
                        border.width: 1.5 + 1.5 * page.beat; border.color: page.c1; opacity: page.v("island", true) ? 0.15 + 0.75 * page.beat : 0 }
                    Row { anchors.centerIn: parent; spacing: 8
                        Rectangle { width: 16; height: 16; radius: M3.sq ? 0 : 8; anchors.verticalCenter: parent.verticalCenter
                            gradient: Gradient { GradientStop { position: 0; color: page.c1 } GradientStop { position: 1; color: page.c2 } } }
                        T { text: "21:37"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter } }
                }
                // the visualizer, in the style you pick
                Item {
                    id: mviz
                    readonly property string st: page.v("bar", "liquid")
                    readonly property string sz: page.v("bar_size", "medium")
                    anchors.left: misl.right; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    width: st === "liquid" ? (sz === "small" ? 56 : sz === "wide" ? 150 : 96) : (st === "dots" ? (sz === "small" ? 7 : sz === "wide" ? 16 : 11) * 10 : (sz === "small" ? 8 : sz === "wide" ? 18 : 12) * 6)
                    height: 24
                    LiquidWave { id: barLiq; anchors.fill: parent; visible: mviz.st === "liquid"; mode: "center"; points: 20; gain: 1.3; floor: 0.07; fillA: 0.95; c1: page.c1; c2: page.c2 }
                    Repeater {
                        model: mviz.st === "bars" ? (mviz.sz === "small" ? 8 : mviz.sz === "wide" ? 18 : 12) : 0
                        delegate: Rectangle { readonly property real lv: page.lvl(index, mviz.width / 6); x: index * 6; width: 4; radius: 2
                            height: Math.max(4, 22 * (0.12 + 0.88 * lv)); anchors.verticalCenter: parent.verticalCenter; color: page.c1; opacity: 0.45 + 0.55 * lv }
                    }
                    Repeater {
                        model: mviz.st === "dots" ? (mviz.sz === "small" ? 7 : mviz.sz === "wide" ? 16 : 11) : 0
                        delegate: Rectangle { readonly property real lv: page.lvl(index, mviz.width / 10); readonly property real d: Math.min(9, 3 + lv * 6.5)
                            x: index * 10 + (9 - d) / 2; anchors.verticalCenter: parent.verticalCenter; width: d; height: d; radius: M3.sq ? 0 : d / 2
                            color: Qt.tint(page.c1, Qt.rgba(page.c2.r, page.c2.g, page.c2.b, index / 12)); opacity: 0.5 + 0.5 * lv }
                    }
                }
                Row { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 11
                    Repeater { model: 3; delegate: Rectangle { width: 11; height: 11; radius: M3.sq ? 0 : 5.5; color: Qt.rgba(1, 1, 1, 0.45) } } }
            }
            // the song that plays: its cover in your shape, with its two colors
            Rectangle {
                x: 24; y: 74; width: 268; height: 84; radius: M3.sq ? 0 : 26
                color: Qt.rgba(0, 0, 0, 0.3)
                Item { x: 12; y: 12; width: 60; height: 60
                    Blob { anchors.fill: parent; kind: Prefs.accentShape; color: page.c1
                        RotationAnimator on rotation { from: 0; to: 360; duration: 12000; loops: Animation.Infinite; running: page.visible } }
                    Blob { anchors.centerIn: parent; width: 30; height: 30; kind: "circle"; color: page.c2 } }
                Column { x: 86; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    T { text: page.songs[page.song].t; font.pixelSize: 15; font.bold: true }
                    T { text: page.songs[page.song].a; font.pixelSize: 12; color: M3.inkDim }
                    Row { spacing: 5; topPadding: 4
                        Rectangle { width: 22; height: 8; radius: M3.sq ? 0 : 4; color: page.c1 }
                        Rectangle { width: 22; height: 8; radius: M3.sq ? 0 : 4; color: page.c2 } } }
            }
            T { anchors.right: parent.right; anchors.rightMargin: 20; y: 88; width: parent.width - 330; horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap; font.pixelSize: 12; color: M3.inkDim
                text: page.v("cover", true) ? I18n.t("Every song brings its own colors") : I18n.t("Your theme's colors") }
        }
        T { width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: M3.inkDim
            text: I18n.t("A song plays on the stage above, so you can see what each switch does. On your desktop it all rests while nothing plays, under windows and in Light mode.") }

        // ---------- colors ----------
        SectionTitle { text: I18n.t("The music's colors"); sub: I18n.t("While music plays, the bar, the island, the dock, the control center and the widgets take the colors of its cover. A few seconds after it stops your theme comes back.") }
        ToggleRow { label: I18n.t("Colors from the cover"); desc: I18n.t("Every song brings its own colors; they flow in slowly")
            dflt: true; checked: page.v("cover", true) !== false; onToggled: function(x) { page.setv("cover", x ? "on" : "off") } }
        ToggleRow { label: I18n.t("Window borders too"); desc: I18n.t("Hyprland. Not when you picked your own border colors")
            enabled: page.v("cover", true) !== false; opacity: enabled ? 1 : 0.45
            dflt: true; checked: page.v("borders", true) !== false; onToggled: function(x) { page.setv("borders", x ? "on" : "off") } }

        // ---------- the bar ----------
        SectionTitle { text: I18n.t("Visualizer on the bar"); sub: I18n.t("The music on your bar, while it plays.") }
        SegRow { label: I18n.t("Style"); desc: I18n.t("Liquid: one soft shape that swells from the middle. Dots: a row of dots. Bars: the classic")
            options: [ { label: I18n.t("Liquid"), value: "liquid" }, { label: I18n.t("Dots"), value: "dots" }, { label: I18n.t("Bars"), value: "bars" } ]
            dflt: "liquid"; current: page.v("bar", "liquid"); onChosen: function(x) { page.setv("bar", x) } }
        SegRow { label: I18n.t("Size"); desc: I18n.t("How much of the bar it takes")
            options: [ { label: I18n.t("Small"), value: "small" }, { label: I18n.t("Medium"), value: "medium" }, { label: I18n.t("Wide"), value: "wide" } ]
            dflt: "medium"; current: page.v("bar_size", "medium"); onChosen: function(x) { page.setv("bar_size", x) } }
        Row {
            visible: !page.vizOnBar && page.bq.layout !== undefined
            spacing: 12
            T { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Not on your bar yet: add Visualizer in Bar layout"); font.pixelSize: 12; color: M3.inkDim }
            Btn { sym: "view_column"; text: I18n.t("Bar layout"); onClicked: page.ctl.page = 3 }
        }

        // ---------- the desktop ----------
        SectionTitle { text: I18n.t("On the desktop"); sub: I18n.t("Under your windows, so it never gets in the way.") }
        ToggleRow { label: I18n.t("Edge glow"); desc: I18n.t("A soft light along the bottom of the screen that moves with the music")
            dflt: false; checked: page.v("edge", false) === true; onToggled: function(x) { page.setv("edge", x ? "on" : "off") } }
        SegRow { label: I18n.t("Edge style"); desc: I18n.t("Glow rises and fades; Liquid is a clear shape with a bright edge")
            enabled: page.v("edge", false) === true; opacity: enabled ? 1 : 0.45
            options: [ { label: I18n.t("Glow"), value: "glow" }, { label: I18n.t("Liquid"), value: "liquid" } ]
            dflt: "glow"; current: page.v("edge_style", "glow"); onChosen: function(x) { page.setv("edge_style", x) } }
        SliderRow { label: I18n.t("Edge height"); desc: I18n.t("How high it may rise, in % of the screen")
            enabled: page.v("edge", false) === true; opacity: enabled ? 1 : 0.45
            from: 6; to: 40; step: 1; unit: " %"; dflt: 16; value: Math.round(page.v("edge_height", 0.16) * 100)
            onCommitted: function(x) { page.setv("edge_height", (Math.round(x) / 100).toFixed(2)) } }
        ToggleRow { label: I18n.t("The island breathes"); desc: I18n.t("Its edge glows softly with the beat while music plays")
            dflt: true; checked: page.v("island", true) !== false; onToggled: function(x) { page.setv("island", x ? "on" : "off") } }
        ToggleRow { label: I18n.t("Lock screen ring"); desc: I18n.t("A liquid ring around the cover on the lock screen (a line over it in the Cards style)")
            dflt: true; checked: page.v("lock", true) !== false; onToggled: function(x) { page.setv("lock", x ? "on" : "off") } }
        T { width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: M3.inkDim
            text: I18n.t("The visualizer widget has two new styles too: Liquid and Orb (the cover with a ring around it). Edit mode > Visualizer.") }

        // ---------- lyrics on the desktop (V6.11) ----------
        SectionTitle { text: I18n.t("Lyrics on the desktop"); sub: I18n.t("The line being sung, big and low on your desktop, like the words in a music video. Its words rise in one after another and fill with color as they are sung.") }
        ToggleRow { label: I18n.t("Lyrics on the desktop"); desc: I18n.t("Synced lyrics from LRCLIB, for songs that have them. Under your windows; gone for a full-screen one")
            dflt: false; checked: page.v("lyrics", false) === true; onToggled: function(x) { page.setv("lyrics", x ? "on" : "off") } }
        SegRow { label: I18n.t("Size"); desc: I18n.t("How big the words are")
            enabled: page.v("lyrics", false) === true; opacity: enabled ? 1 : 0.45
            options: [ { label: I18n.t("Small"), value: "small" }, { label: I18n.t("Medium"), value: "medium" }, { label: I18n.t("Large"), value: "large" } ]
            dflt: "medium"; current: page.v("lyrics_size", "medium"); onChosen: function(x) { page.setv("lyrics_size", x) } }
        T { width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: M3.inkDim
            text: I18n.t("The music card of the bar and the Lyrics widget show the words the same way now: one big line at a time.") }

        // ---------- the weather and more ----------
        SectionTitle { text: I18n.t("Weather on the desktop"); sub: I18n.t("When it rains outside, it rains on your desktop. Or pick what always falls: rain, snow, a storm, fog, cherry petals or fireflies that glow with the beat.") }
        ToggleRow { label: I18n.t("Weather on the desktop"); desc: I18n.t("Under your windows, slow and soft; it rests for a full-screen window and in Light mode")
            dflt: false; checked: page.v("weather", false) === true; onToggled: function(x) { page.setv("weather", x ? "on" : "off") } }
        // what falls: the weather outside, or always one of them
        Flow {
            width: parent.width
            spacing: 8
            opacity: page.v("weather", false) === true ? 1 : 0.45
            Repeater {
                model: page.kinds
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: page.v("weather_mode", "live") === modelData.v
                    height: 40; width: kr.implicitWidth + 32
                    radius: M3.sq ? 0 : (on ? 12 : 20)
                    color: on ? M3.primary : (ma.containsMouse ? M3.surfaceHighest : M3.surfaceHigh)
                    Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Row { id: kr; anchors.centerIn: parent; spacing: 7
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.sym; size: 18; filled: on; color: on ? M3.inkPrimary : M3.ink }
                        T { anchors.verticalCenter: parent.verticalCenter; text: I18n.t(modelData.t); font.pixelSize: 13; font.weight: on ? Font.DemiBold : Font.Normal; color: on ? M3.inkPrimary : M3.ink } }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { page.setv("weather_mode", modelData.v); if (page.v("weather", false) !== true) page.setv("weather", "on") } }
                }
            }
        }
        T { width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: M3.inkDim
            visible: page.v("weather_mode", "live") === "live"
            text: page.place === "" ? I18n.t("The weather outside needs your place: Settings > Language & region")
                : (page.cond === "" ? I18n.t("In %1: not checked yet", page.place)
                : (page.fallOf(page.cond) === "" ? I18n.t("In %1 now: %2. Nothing falls, so the desktop stays clear", page.place, page.cond)
                : I18n.t("In %1 now: %2", page.place, page.cond))) }
        Row {
            spacing: 8
            T { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Try for a minute:"); font.pixelSize: 13; color: M3.inkDim }
            Btn { sym: "rainy"; text: I18n.t("Rain"); onClicked: page.tryIt("rain") }
            Btn { sym: "ac_unit"; text: I18n.t("Snow"); onClicked: page.tryIt("snow") }
            Btn { sym: "local_florist"; text: I18n.t("Petals"); onClicked: page.tryIt("petals") }
            Btn { sym: "flare"; text: I18n.t("Fireflies"); onClicked: page.tryIt("fireflies") }
        }
    }
}
