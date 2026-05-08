import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: root
    property var modelData
    property bool selectable: false
    property bool selected: false
    property string size: "size-1x1" // size-1x1, size-2x1, size-1x2, size-2x2, size-3x2
    signal open()
    signal toggleFav()
    signal selectToggle()

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: ThemeManager.surfaceContainerHigh
        clip: true
        
        border.width: root.selected ? 3 : 0
        border.color: ThemeManager.primary

        Image {
            id: img
            anchors.fill: parent
            anchors.margins: root.selected ? 4 : 0
            // Ensure path has file:// prefix if it is absolute
            source: {
                var p = root.modelData.thumb || root.modelData.file_path || ""
                if (p.indexOf("://") === -1 && p !== "") return "file://" + p
                return p
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            
            // Hover scale
            scale: mouseArea.containsMouse ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            Behavior on anchors.margins { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        }

        // Video Badge
        Rectangle {
            visible: root.modelData.mime_type && root.modelData.mime_type.startsWith("video/")
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: Qt.alpha("black", 0.55)
            M3Icon {
                anchors.centerIn: parent
                name: "play"
                size: 14; color: "white"
            }
        }

        // Checkmark for selection
        Rectangle {
            visible: root.selectable || root.selected
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: ThemeManager.primary
            opacity: (root.selectable || root.selected) ? 1 : 0
            M3Icon {
                anchors.centerIn: parent
                name: "check"
                size: 16; color: "white"
            }
        }

        // Favorite Button
        Rectangle {
            id: favButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 28; height: 28; radius: 14
            color: Qt.alpha("black", 0.45)
            opacity: (mouseArea.containsMouse || root.modelData.is_favorite) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
            
            M3Icon {
                anchors.centerIn: parent
                name: root.modelData.is_favorite ? "favorite_fill" : "favorite"
                size: 16; color: root.modelData.is_favorite ? "#ffd8e4" : "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.toggleFav()
                }
            }
        }

        // Meta (revealed on hover)
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 8
            height: 24
            radius: 12
            color: Qt.alpha("black", 0.4)
            visible: mouseArea.containsMouse
            Row {
                anchors.centerIn: parent
                leftPadding: 8; rightPadding: 8
                Label {
                    text: {
                        var d = root.modelData.creation_date
                        if (!d) return ""
                        return Qt.formatDateTime(new Date(d * 1000), "dd MMM")
                    }
                    color: "white"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (root.selectable) root.selectToggle()
            else root.open()
        }
    }
}
