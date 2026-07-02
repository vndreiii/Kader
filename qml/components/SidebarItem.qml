import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: root
    property string icon: ""
    property string label: ""
    property bool active: false
    property bool collapsed: false
    signal clicked()

    width: parent ? parent.width : 0
    height: 56

    // No progress vars needed anymore! MaterialSymbol handles fill inherently.
    
    // Active background grows out based on fill? We can just use standard opacity here
    Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort; easing.type: Easing.OutQuint } }



    // NOTE: the M3 active-indicator pill (secondaryContainer, sliding) already
    // exists one level up in Sidebar.qml (`activePill`, tracks the active row's
    // y via mapToItem + a spring animation) — adding a second pill here would
    // just double-draw on top of it, so this component intentionally only
    // recolors icon/label for the active state, as before.

    Row {
        anchors.fill: parent
        anchors.leftMargin: root.collapsed ? Math.floor((root.width - 24) / 2) : 28
        spacing: 12

        // ── Icon ─────────────────────────────────────────────────────────
        Item {
            id: iconArea
            width: 24; height: 24
            anchors.verticalCenter: parent.verticalCenter

            MaterialSymbol {
                anchors.centerIn: parent
                name: root.icon
                size: 24
                color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                fill: root.active ? 1.0 : 0.0
                Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
            }
        }

        Label {
            visible: !root.collapsed
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
            font.pixelSize: ThemeManager.fontLabelL
            font.weight: root.active ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            width: parent.width - 64
            Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
        }
    }

    // ── Hover + press state layer ───────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 12; anchors.rightMargin: 12
        radius: ThemeManager.radiusXxl
        color: ThemeManager.onSurface
        opacity: mouseArea.pressed ? ThemeManager.pressOpacity : (mouseArea.containsMouse ? ThemeManager.hoverOpacity : 0)
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
