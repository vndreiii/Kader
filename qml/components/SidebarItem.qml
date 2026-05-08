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

    height: 56
    Layout.fillWidth: true

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: root.collapsed ? 12 : 0
        anchors.rightMargin: root.collapsed ? 12 : 0
        radius: 28
        color: root.active ? ThemeManager.secondaryContainer : "transparent"
        
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.collapsed ? 0 : 16
            anchors.rightMargin: root.collapsed ? 0 : 16
            spacing: 12

            // Icon using M3Icon
            M3Icon {
                name: root.icon
                size: 24
                color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            }

            Label {
                visible: !root.collapsed
                text: root.label
                color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                font.pixelSize: 14
                font.weight: root.active ? Font.Medium : Font.Normal
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Hover effect
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: ThemeManager.onSurface
            opacity: mouseArea.containsMouse && !root.active ? 0.08 : 0
            Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
