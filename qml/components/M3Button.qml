import QtQuick
import QtQuick.Controls
import ".."

// Material 3 button: "text" (default), "tonal" or "filled". `highlighted`
// is a shorthand for filled.
Button {
    id: root
    property string kind: highlighted ? "filled" : "text"
    readonly property color _fg: !enabled ? Qt.alpha(ThemeManager.onSurface, 0.38)
                               : kind === "filled" ? ThemeManager.onPrimary
                               : kind === "tonal" ? ThemeManager.onSecondaryContainer
                               : ThemeManager.primary
    implicitHeight: 40
    hoverEnabled: true
    background: Rectangle {
        radius: 20
        color: !root.enabled ? (root.kind === "text" ? "transparent" : Qt.alpha(ThemeManager.onSurface, 0.12))
             : root.kind === "filled" ? ThemeManager.primary
             : root.kind === "tonal" ? ThemeManager.secondaryContainer
             : "transparent"
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root._fg
            opacity: root.down ? 0.12 : root.hovered ? 0.08 : 0
        }
    }
    contentItem: Label {
        text: root.text
        color: root._fg
        font.pixelSize: 14
        font.weight: Font.Medium
        leftPadding: root.kind === "text" ? 12 : 22
        rightPadding: leftPadding
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
