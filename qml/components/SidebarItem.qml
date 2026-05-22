import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

    Row {
        anchors.fill: parent
        anchors.leftMargin: 28
        spacing: 12

        Item {
            width: 24; height: 24
            anchors.verticalCenter: parent.verticalCenter

            // Outline icon (fades out when active)
            M3Icon {
                anchors.fill: parent
                name: root.icon
                size: 24
                color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                opacity: root.active ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            }

            // Filled icon (fades in when active)
            M3Icon {
                anchors.fill: parent
                name: root.icon + "_fill"
                size: 24
                color: ThemeManager.onSecondaryContainer
                opacity: root.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            }
        }

        Label {
            visible: !root.collapsed
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
            font.pixelSize: 14
            font.weight: root.active ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            width: parent.width - 64
            Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
        }
    }

    // Hover layer
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 12; anchors.rightMargin: 12
        radius: 28
        color: ThemeManager.onSurface
        opacity: mouseArea.containsMouse && !root.active ? 0.08 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
