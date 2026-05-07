import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QmlMaterial

Item {
    id: root
    property string activeIcon: ""
    property string label: ""
    property bool active: false
    signal clicked()

    height: 48
    Layout.fillWidth: true

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 12
        color: root.active ? Qt.alpha(Theme.primaryColor, 0.15) : "transparent"
        
        Behavior on color { ColorAnimation { duration: 200 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            spacing: 12

            // Icon placeholder (we'll add actual icons later)
            Rectangle {
                width: 24
                height: 24
                radius: 4
                color: root.active ? Theme.primaryColor : Theme.textColor
                opacity: root.active ? 1.0 : 0.6
            }

            Label {
                text: root.label
                color: Theme.textColor
                font.bold: root.active
                opacity: root.active ? 1.0 : 0.8
                Layout.fillWidth: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: if (!root.active) parent.children[0].color = Qt.alpha(Theme.textColor, 0.05)
        onExited: if (!root.active) parent.children[0].color = "transparent"
        onClicked: root.clicked()
    }
}
