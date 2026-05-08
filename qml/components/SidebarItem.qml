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
    
    // Sidebar column margins are 12. 
    // This highlight starts at 4px from that column edge (16px from window edge)
    // The icon starts at 12px from highlight edge (28px from window edge?)
    // WAIT, user said "shifted more left aligned to for exmaple when the widget for the this pc starts ont he left side"
    
    // If I use 0 margins on sidebar column, and handle everything here:
    
    Rectangle {
        id: highlight
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        radius: 28
        color: root.active ? ThemeManager.secondaryContainer : "transparent"
        
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16 // Icon starts 16px from highlight edge (12+16 = 28 from window edge)
            spacing: 12

            M3Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.icon
                size: 24
                color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
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
            }
        }

        // Hover layer
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
