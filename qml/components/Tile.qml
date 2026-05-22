import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: root
    property var tileData: null
    property bool selectable: false
    property bool selected: false
    signal open()
    signal toggleFav()
    signal selectToggle()

    // Safe accessor — avoids TypeError when tileData is temporarily null/undefined
    // during model reset while 9000+ items are being loaded.
    readonly property var _d: (tileData !== null && tileData !== undefined) ? tileData : ({})

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
            source: {
                var p = root._d.thumb || root._d.file_path || ""
                if (p && p.indexOf("://") === -1) return "file://" + p
                return p
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true

            scale: mouseArea.containsMouse ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            Behavior on anchors.margins { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        }

        // Video badge
        Rectangle {
            visible: root._d.mime_type ? root._d.mime_type.toString().startsWith("video/") : false
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: Qt.alpha("black", 0.55)
            M3Icon { anchors.centerIn: parent; name: "play"; size: 14; color: "white" }
        }

        // Selection checkmark
        Rectangle {
            visible: root.selectable || root.selected
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: ThemeManager.primary
            opacity: (root.selectable || root.selected) ? 1 : 0
            M3Icon { anchors.centerIn: parent; name: "check"; size: 16; color: "white" }
        }

        // Favorite button
        Rectangle {
            id: favButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 28; height: 28; radius: 14
            color: Qt.alpha("black", 0.45)
            opacity: (mouseArea.containsMouse || (root._d.is_favorite ? true : false)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }

            M3Icon {
                anchors.centerIn: parent
                name: (root._d.is_favorite ? true : false) ? "favorite_fill" : "favorite"
                size: 16
                color: (root._d.is_favorite ? true : false) ? "#ffd8e4" : "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.toggleFav()
            }
        }

        // Date meta on hover
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18   // > tile radius (16) to avoid clip
            anchors.bottomMargin: 12
            height: 24
            radius: 12
            color: Qt.alpha("black", 0.4)
            visible: mouseArea.containsMouse && !!root._d.creation_date
            Row {
                anchors.centerIn: parent
                leftPadding: 8; rightPadding: 8
                Label {
                    text: {
                        var d = root._d.creation_date
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
