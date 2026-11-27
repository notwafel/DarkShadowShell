import QtQuick

// An icon: Material Symbols name ("speed", "memory", ...) or a Nerd Font glyph as fallback.
// filled is kept for the callers but not used: Qt's FILL axis on Material Symbols mixes up glyphs (info drew a
// globe, play_arrow a broken arrow), so every icon is drawn as the font draws it by default.
Text {
    id: mi
    property string name: ""
    property string glyph: ""
    property real size: 20
    property bool filled: false
    // the weight of the symbol font: it is a variable font and the thin outlines (power, Bluetooth, the bell) looked
    // lighter than Wi-Fi at the same size. Nerd Font icons have no axes, so this does nothing without the symbols
    property real weight: 400
    Component.onCompleted: {
        if (!DashFont.symbols || weight === 400) return
        try { font.variableAxes = { "wght": weight } } catch (e) { }
    }
    text: DashFont.symbols ? name : glyph
    font.family: DashFont.symbols ? "Material Symbols Rounded" : DashFont.nerd
    // the symbol font carries weight 500 as the "Medium" face too: this picks it on systems whose font stack does
    // not pass the variable axis through (older Qt or a static copy of the font)
    font.styleName: DashFont.symbols && weight === 500 ? "Medium" : ""
    font.pixelSize: DashFont.symbols ? size * 1.12 : size * 0.92
    color: "#F6F5F4"
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
