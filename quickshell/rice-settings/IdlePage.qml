import Quickshell
import Quickshell.Io
import QtQuick

// Settings > Desktop > Idle & Login screen: when the screen turns off and the computer sleeps (hypridle), and the
// login screen (SDDM). The shell has no lock screen of its own any more.
Item {
    id: page
    property var ctl
    property var ls: ({})

    function v(k, d) { return ls[k] !== undefined ? ls[k] : d }
    function setv(key, value) {
        const n = Object.assign({}, ls)
        n[key] = value
        ls = n
        Quickshell.execDetached(["bash", "-c", "\"$HOME/.local/bin/rice-idle\" set \"$1\" \"$2\"", "_", key, String(value)])
        page.ctl.status = I18n.t("Applied")
        refresh.restart()
    }
    function mins(x) { return x <= 0 ? "Never" : (x + " min") }

    Process {
        id: stateProc
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-idle\" state"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.ls = JSON.parse(text) } catch (e) { } } }
    }
    Timer { id: refresh; interval: 800; onTriggered: stateProc.running = true }

    PageScroll {
        anchors.fill: parent

        SectionTitle { text: I18n.t("Idle"); sub: I18n.t("What happens when you leave the computer. Slide to 0 for Never.") }
        SliderRow {
            label: I18n.t("Turn screen off after")
            desc: I18n.t("Currently: ") + page.mins(page.v("screen_off_after", 0))
            from: 0; to: 60; step: 1; unit: " min"
            value: page.v("screen_off_after", 0)
            onCommitted: function(x) { page.setv("screen_off_after", Math.round(x)) }
        }
        SliderRow {
            label: I18n.t("Sleep after")
            desc: I18n.t("Currently: ") + page.mins(page.v("suspend_after", 15))
            from: 0; to: 120; step: 5; unit: " min"
            value: page.v("suspend_after", 15)
            onCommitted: function(x) { page.setv("suspend_after", Math.round(x)) }
        }
        Row {
            topPadding: 4
            Btn { text: I18n.t("Reset"); onClicked: { Quickshell.execDetached(["bash", "-c", "\"$HOME/.local/bin/rice-idle\" reset"]); page.ctl.status = I18n.t("Reset"); refresh.restart() } }
        }

        LoginScreenCard { ctl: page.ctl }
    }
}
