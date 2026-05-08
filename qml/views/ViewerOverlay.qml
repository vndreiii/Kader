import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.alpha("black", 0.92)
    z: 1000
    visible: active
    
    property bool active: false
    property var mediaData: null
    
    // Close on Escape
    focus: active
    Keys.onEscapePressed: root.active = false

    MouseArea {
        anchors.fill: parent
        onClicked: root.active = false
    }

    // Main Image Container
    Item {
        anchors.fill: parent
        anchors.margins: 48

        Image {
            id: mainImg
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.9, implicitWidth > 0 ? implicitWidth : parent.width)
            height: Math.min(parent.height * 0.86, implicitHeight > 0 ? implicitHeight : parent.height)
            source: root.mediaData ? root.mediaData.path : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Qt.alpha("white", 0.1)
                border.width: 1
                radius: 8
            }
        }
    }

    // Navigation Buttons
    Control {
        id: prevBtn
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        width: 48; height: 48
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12); border.color: Qt.alpha("white", 0.1); border.width: 1 }
        contentItem: M3Icon { name: "schedule"; size: 24; color: "white"; anchors.centerIn: parent } // Placeholder for Chevron
    }
    Control {
        id: nextBtn
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        width: 48; height: 48
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12); border.color: Qt.alpha("white", 0.1); border.width: 1 }
        contentItem: M3Icon { name: "schedule"; size: 24; color: "white"; anchors.centerIn: parent } // Placeholder for Chevron
    }

    // Close Button
    Control {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        width: 48; height: 48
        onClicked: root.active = false
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
        contentItem: M3Icon { name: "close"; size: 24; color: "white"; anchors.centerIn: parent }
    }

    // Info (Bottom Left)
    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 4
        Label {
            text: root.mediaData ? root.mediaData.path.split('/').pop() : "Untitled"
            color: "white"
            font.family: "Roboto Flex"
            font.pixelSize: 18
            font.weight: Font.Medium
        }
        Label {
            text: root.mediaData ? Qt.formatDateTime(new Date(root.modelData.date * 1000), "dd MMMM yyyy") : ""
            color: Qt.alpha("white", 0.7)
            font.pixelSize: 13
        }
    }

    // Actions (Bottom Right)
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 8
        
        Repeater {
            model: [
                { icon: "favorite", title: "Favorite" },
                { icon: "delete", title: "Trash" }, // Should be shredder for EXIF
                { icon: "folder", title: "Download" },
                { icon: "settings", title: "Info" },
                { icon: "delete", title: "Delete" }
            ]
            delegate: Control {
                width: 48; height: 48
                background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
                contentItem: M3Icon { name: modelData.icon; size: 24; color: "white"; anchors.centerIn: parent }
                ToolTip.visible: hovered
                ToolTip.text: modelData.title
            }
        }
    }
}
