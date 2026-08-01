// Floating bottom tab bar — the Aurora sibling of the iOS TabView / Android bottom NavigationBar
// (Home · Browse · Design · Settings). Styled as an iOS-26 "Liquid Glass"-style floating pill:
// inset from the edges, translucent/frosted, soft shadow, accent-tinted selection. Silica has no
// native bottom tab bar (it uses page stacks), so this is a custom control that switches the shown
// screen — matching iOS/Android so the three apps line up.
import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

Item {
    id: bar
    property int current: 0
    property color accent: "#5B5BF0"
    property bool dark: false
    signal selected(int index)

    // Destinations, not actions (HIG): filled, distinct glyphs + one-word labels.
    property var tabs: [
        { glyph: "⌂", label: "Home" },      // ⌂ house
        { glyph: "▦", label: "Browse" },    // ▦ grid
        { glyph: "◈", label: "Design" },    // ◈ hexagon-ish (Figma/tokens)
        { glyph: "⚙", label: "Settings" }   // ⚙ gear
    ]

    property real inset: 16
    property real pillH: 64
    implicitHeight: pillH + inset + 8
    height: implicitHeight

    property color idle: dark ? "#8A8A93" : "#9A9AA2"
    property color glass: dark ? Qt.rgba(0.14, 0.14, 0.16, 0.86) : Qt.rgba(1, 1, 1, 0.86)

    // Soft shadow behind the pill.
    RectangularGlow {
        anchors.fill: pill
        glowRadius: 18
        spread: 0.06
        color: "#33000000"
        cornerRadius: pill.radius + 18
    }
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: bar.inset
        width: parent.width - 2 * bar.inset
        height: bar.pillH
        radius: height / 2
        color: bar.glass
        border.color: bar.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
        border.width: 1

        Row {
            anchors.fill: parent
            Repeater {
                model: bar.tabs
                delegate: MouseArea {
                    width: pill.width / bar.tabs.length
                    height: pill.height
                    onClicked: { bar.current = index; bar.selected(index); }
                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.glyph
                            font.pixelSize: 25
                            color: index === bar.current ? bar.accent : bar.idle
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            font.pixelSize: 11
                            font.bold: index === bar.current
                            color: index === bar.current ? bar.accent : bar.idle
                        }
                    }
                }
            }
        }
    }
}
