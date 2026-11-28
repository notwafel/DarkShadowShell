import Quickshell
import Quickshell.Io
import QtQuick

// Settings > Appearance > Explore (V5.07): themes made by people who use DarkShadow's Shell. The list comes from
// the repo on GitHub (rice-explore checks every file against it). Get keeps one as your own theme, Use puts it on.
// Share my setup turns your desktop into a theme file and opens the page to send it in.
Item {
    id: page
    property var ctl
    property var pd: ({ themes: [], offline: false })
    property string busy: ""          // the id being downloaded or put on
    property bool loading: true
    property bool sharing: false

    Process {
        id: listP
        property bool refresh: false
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-explore\" list " + (refresh ? "--refresh" : "") + " 2>/dev/null"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.pd = JSON.parse(text) } catch (e) { } page.loading = false; listP.refresh = false } }
    }
    onVisibleChanged: if (visible && !listP.running) listP.running = true
    function reload(fresh) { if (listP.running) return; loading = true; listP.refresh = fresh; listP.running = true }

    Process {
        id: run
        property string what: ""
        stderr: StdioCollector { id: runErr }
        onExited: function(code) {
            const why = runErr.text.trim().split("\n").pop()
            if (page.ctl) page.ctl.status = code === 0 ? I18n.t(run.what) : (why !== "" ? why : I18n.t("That did not work"))
            page.busy = ""
            page.reload(false)
        }
    }
    function act(verb, t) {
        if (run.running) return
        busy = t.id
        run.what = verb === "use" ? "Theme: " + t.name : t.name + " is now one of your themes"
        run.command = ["bash", "-c", "\"$HOME/.local/bin/rice-explore\" \"$1\" \"$2\"", "_", verb, t.id]
        run.running = true
    }
    Process {
        id: shareP
        stdout: StdioCollector {
            onStreamFinished: {
                page.sharing = false
                try {
                    const j = JSON.parse(text)
                    if (page.ctl) page.ctl.status = I18n.t("Saved: drop %1 on the page that opened", j.upload.split("/").pop())
                } catch (e) { if (page.ctl) page.ctl.status = I18n.t("That did not work") }
            }
        }
    }

    // ---------- import a theme a friend sent you (a .dstheme file): the same file Themes exports ----------
    property var imp: null
    function importTheme(f) {
        const pth = String(f).trim()
        if (pth === "") { impF.forceActiveFocus(); return }
        imp.what = "Imported: it is with your themes above"
        imp.command = ["bash", "-c", "\"$HOME/.local/bin/rice-theme\" import \"$1\"", "_", pth]
        imp.running = true
        impF.text = ""
    }
    Process {
        id: imp
        property string what: ""
        stderr: StdioCollector { id: impErr }
        onExited: function(code) {
            if (page.ctl) page.ctl.status = code === 0 ? I18n.t(imp.what) : (impErr.text.trim().split("\n").pop() || I18n.t("That did not work"))
            page.reload(false)
        }
    }
    Process {
        id: impPick
        stdout: StdioCollector { onStreamFinished: { const d = text.trim(); if (d) page.importTheme(d) } }
    }

    PageScroll {
        anchors.fill: parent

        SectionTitle { text: I18n.t("Explore"); sym: "travel_explore"
            sub: I18n.t("Themes made by people who use DarkShadow's Shell: a wallpaper and a whole look each. Get one, then use it like your other themes.") }

        // ---------- share yours ----------
        Rectangle {
            width: parent.width
            height: shareRow.height + 36
            radius: M3.sq ? 0 : M3.rL
            color: M3.primaryContainer
            Row {
                id: shareRow
                x: 20; y: 18
                width: parent.width - 40
                spacing: 16
                Item { width: 52; height: 52; anchors.verticalCenter: parent.verticalCenter
                    Blob { anchors.fill: parent; kind: Prefs.accentShape; color: M3.primary }
                    Icon { anchors.centerIn: parent; name: "ios_share"; glyph: ""; size: 22; color: M3.inkPrimary } }
                Column {
                    width: parent.width - 52 - shareBtn.width - 32
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    T { text: I18n.t("Share your setup"); font.pixelSize: 17; font.weight: Font.DemiBold; color: M3.inkPrimaryC }
                    T { kind: "reading"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; color: M3.inkPrimaryC; opacity: 0.85
                        text: I18n.t("Your desktop as a theme file (its wallpaper too) in DarkShadow-themes, and the page on GitHub to send it in. Once it is checked, everyone sees it here.") }
                }
                Btn {
                    id: shareBtn
                    anchors.verticalCenter: parent.verticalCenter
                    primary: true
                    enabled: !page.sharing
                    sym: "upload"; icon: ""
                    text: page.sharing ? I18n.t("Saving...") : I18n.t("Share my setup")
                    onClicked: { page.sharing = true; shareP.command = ["bash", "-c", "\"$HOME/.local/bin/rice-explore\" share \"$1\"", "_", Quickshell.env("USER") + "'s setup"]; shareP.running = true }
                }
            }
        }

        Item { width: 1; height: 8 }

        // ---------- a theme from a friend ----------
        Rectangle {
            width: parent.width
            height: impRow.height + 28
            radius: M3.sq ? 0 : (M3.rL)
            color: M3.surfaceC
            Row {
                id: impRow
                x: 18; y: 14
                width: parent.width - 36
                spacing: 12
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "folder_open"; glyph: ""; size: 20; color: M3.primary }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 - impBtn.width - impPickBtn.width - 36
                    spacing: 2
                    T { text: I18n.t("Import a theme"); font.pixelSize: 14; font.weight: Font.DemiBold }
                    T { kind: "reading"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 11; color: M3.inkDim
                        text: I18n.t("A .dstheme file (one you saved and sent, or a friend did). It shows up with your themes.") }
                }
                Field { id: impF; width: 260; anchors.verticalCenter: parent.verticalCenter; placeholder: I18n.t("~/Downloads/theme.dstheme")
                    onAccepted: page.importTheme(text) }
                Btn { id: impPickBtn; anchors.verticalCenter: parent.verticalCenter; sym: "folder"; icon: ""; text: I18n.t("Pick")
                    onClicked: { impPick.command = ["bash", "-c", "zenity --file-selection --file-filter='*.dstheme' --title=\"$1\" 2>/dev/null || kdialog --getopenfilename ~ '*.dstheme' 2>/dev/null", "_", I18n.t("A theme file")]; impPick.running = true } }
                Btn { id: impBtn; anchors.verticalCenter: parent.verticalCenter; primary: true; sym: "download"; icon: ""; text: I18n.t("Import")
                    onClicked: page.importTheme(impF.text) }
            }
        }

        Item {
            width: parent.width; height: 34
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                T { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("Themes"); font.pixelSize: 15; font.weight: Font.DemiBold }
                T { anchors.verticalCenter: parent.verticalCenter; color: M3.inkDim; font.pixelSize: 12
                    text: page.loading ? I18n.t("Looking...") : (page.pd.offline ? I18n.t("Offline: the list from last time") : I18n.t("%1 themes", (page.pd.themes || []).length)) }
            }
            // moved here from its own line (it sat oddly under the list heading)
            Btn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                sym: "refresh"; icon: ""; text: I18n.t("Look again"); enabled: !page.loading; onClicked: page.reload(true) }
        }

        T {
            visible: !page.loading && (page.pd.themes || []).length === 0
            width: parent.width; wrapMode: Text.WordWrap; color: M3.inkDim; font.pixelSize: 13
            text: I18n.t("Nothing here yet: Explore needs the internet the first time.")
        }

        // ---------- the themes ----------
        Flow {
            width: parent.width
            spacing: 14
            Repeater {
                model: page.pd.themes || []
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool working: page.busy === modelData.id
                    readonly property int cols: parent.width > 900 ? 3 : 2
                    width: (parent.width - 14 * (cols - 1)) / cols
                    height: cardCol.height + 16
                    radius: M3.sq ? 0 : M3.rL
                    color: M3.surfaceC
                    border.width: modelData.in_use ? 2 : 0
                    border.color: M3.primary
                    // they come in one after another
                    NumberAnimation on opacity { from: 0; to: 1; duration: 380 + card.index * 90; easing.type: Easing.OutCubic }
                    Column {
                        id: cardCol
                        x: 8; y: 8
                        width: parent.width - 16
                        spacing: 10
                        RoundImage {
                            width: parent.width; height: width * 9 / 16
                            cornerRadius: M3.sq ? 0 : M3.rL - 6
                            res: 640
                            source: card.modelData.picture ? "file://" + card.modelData.picture : ""
                        }
                        Item {
                            width: parent.width; height: nameCol.height
                            Column {
                                id: nameCol
                                x: 6
                                width: parent.width - getBtn.width - 18
                                spacing: 2
                                T { text: card.modelData.name; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width }
                                T { text: I18n.t("by %1", card.modelData.author || "?"); font.pixelSize: 12; color: M3.inkDim }
                            }
                            Btn {
                                id: getBtn
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                primary: card.modelData.installed && !card.modelData.in_use
                                enabled: page.busy === "" && !card.modelData.in_use
                                sym: card.modelData.in_use ? "check" : (card.modelData.installed ? "palette" : "download"); icon: ""
                                text: card.working ? I18n.t("Working...") : (card.modelData.in_use ? I18n.t("In use") : (card.modelData.installed ? I18n.t("Use") : I18n.t("Get")))
                                onClicked: page.act(card.modelData.installed ? "use" : "install", card.modelData)
                            }
                        }
                        T { x: 6; kind: "reading"; width: parent.width - 12; wrapMode: Text.WordWrap; font.pixelSize: 13; color: M3.inkDim; text: card.modelData.desc }
                        Row {
                            x: 6
                            spacing: 6
                            Repeater {
                                model: card.modelData.colors || []
                                delegate: Rectangle { required property string modelData; width: 18; height: 18; radius: 9; color: modelData
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15) }
                            }
                            Item { width: 6; height: 1 }
                            Repeater {
                                model: card.modelData.tags || []
                                delegate: Rectangle { required property string modelData; height: 20; width: tg.implicitWidth + 16; radius: 10; color: M3.surfaceHigh
                                    T { id: tg; anchors.centerIn: parent; text: I18n.t(modelData); font.pixelSize: 11; color: M3.inkDim } }
                            }
                        }
                        Item { width: 1; height: 2 }
                    }
                }
            }
        }
    }
}
