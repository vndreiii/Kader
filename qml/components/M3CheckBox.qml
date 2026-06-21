import QtQuick
import ".."

// Material 3 checkbox. Stateless w.r.t. its own value: it never mutates
// `checked` itself, so it can be bound to a model role (e.g. isSelected).
// Emits toggled(newValue) on click; the parent updates the source of truth.
Item {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 40
    implicitHeight: 40

    // State layer (hover / press ripple) — centered on the 40x40 target.
    Rectangle {
        anchors.centerIn: parent
        width: 40; height: 40; radius: 20
        color: root.checked ? ThemeManager.primary : ThemeManager.onSurface
        opacity: ma.pressed ? 0.12 : ma.containsMouse ? 0.08 : 0.0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
    }

    // The 18x18 box.
    Rectangle {
        id: box
        anchors.centerIn: parent
        width: 18; height: 18; radius: 2
        color: root.checked ? ThemeManager.primary : "transparent"
        border.width: root.checked ? 0 : 2
        border.color: root.checked ? "transparent" : ThemeManager.onSurfaceVariant
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

        MaterialSymbol {
            anchors.centerIn: parent
            name: "check"
            size: 16
            color: ThemeManager.onPrimary
            visible: root.checked
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
