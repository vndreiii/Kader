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
    property var  mediaData: null
    property int  currentIndex: -1
    property var  allItems: []
    property bool infoPanelOpen: false

    focus: active
    Keys.onEscapePressed: root.active = false
    Keys.onLeftPressed:   navigatePrev()
    Keys.onRightPressed:  navigateNext()

    function navigatePrev() {
        if (currentIndex > 0) {
            currentIndex--
            mediaData = allItems[currentIndex]
        }
    }
    function navigateNext() {
        if (currentIndex < allItems.length - 1) {
            currentIndex++
            mediaData = allItems[currentIndex]
        }
    }

    // Backdrop dismiss
    MouseArea {
        anchors.fill: parent
        onClicked: root.active = false
    }

    // Main image — shrinks when info panel open
    Item {
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.margins: 72
        anchors.bottomMargin: 80

        Image {
            id: mainImg
            anchors.centerIn: parent
            width:  Math.min(parent.width,  implicitWidth  > 0 ? implicitWidth  : parent.width)
            height: Math.min(parent.height, implicitHeight > 0 ? implicitHeight : parent.height)
            source: root.mediaData ? "file://" + root.mediaData.file_path : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }

    // Prev
    Button {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 48; height: 48
        enabled: root.currentIndex > 0
        opacity: enabled ? 1.0 : 0.3
        onClicked: root.navigatePrev()
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12); border.color: Qt.alpha("white", 0.1); border.width: 1 }
        contentItem: M3Icon { name: "chevron_left"; size: 24; color: "white"; anchors.centerIn: parent }
    }

    // Next
    Button {
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 48; height: 48
        enabled: root.currentIndex < root.allItems.length - 1
        opacity: enabled ? 1.0 : 0.3
        onClicked: root.navigateNext()
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12); border.color: Qt.alpha("white", 0.1); border.width: 1 }
        contentItem: M3Icon { name: "chevron_right"; size: 24; color: "white"; anchors.centerIn: parent }
    }

    // Close
    Button {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        width: 48; height: 48
        onClicked: root.active = false
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
        contentItem: M3Icon { name: "close"; size: 24; color: "white"; anchors.centerIn: parent }
    }

    // Filename + date
    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 4
        Label {
            text: root.mediaData ? root.mediaData.file_path.split('/').pop() : "Untitled"
            color: "white"
            font.family: "Roboto Flex"
            font.pixelSize: 18
            font.weight: Font.Medium
        }
        Label {
            text: root.mediaData && root.mediaData.creation_date
                  ? Qt.formatDateTime(new Date(root.mediaData.creation_date * 1000), "dd MMMM yyyy")
                  : ""
            color: Qt.alpha("white", 0.7)
            font.pixelSize: 13
        }
    }

    // Action buttons
    Row {
        id: actionRow
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        spacing: 8

        Button {
            width: 48; height: 48
            background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
            contentItem: M3Icon {
                name: (root.mediaData && root.mediaData.is_favorite) ? "favorite_fill" : "favorite"
                size: 24; color: "white"; anchors.centerIn: parent
            }
            ToolTip.visible: hovered; ToolTip.text: "Favorite"
            onClicked: {
                if (!root.mediaData) return
                DB.toggleFavorite(root.mediaData.id)
                root.mediaData = DB.getMediaById(root.mediaData.id)
                TimelineModel.refresh()
            }
        }
        Button {
            width: 48; height: 48
            background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
            contentItem: M3Icon { name: "delete"; size: 24; color: "white"; anchors.centerIn: parent }
            ToolTip.visible: hovered; ToolTip.text: "Move to Trash"
            onClicked: {
                if (!root.mediaData) return
                DB.setTrashed(root.mediaData.id, true)
                root.active = false
                TimelineModel.refresh()
            }
        }
        Button {
            width: 48; height: 48
            background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
            contentItem: M3Icon { name: "folder_open"; size: 24; color: "white"; anchors.centerIn: parent }
            ToolTip.visible: hovered; ToolTip.text: "Show in folder"
            onClicked: {
                if (root.mediaData) Qt.openUrlExternally("file://" + root.mediaData.folder_path)
            }
        }
        Button {
            width: 48; height: 48
            background: Rectangle { radius: 24; color: root.infoPanelOpen ? Qt.alpha("white", 0.28) : Qt.alpha("white", 0.12) }
            contentItem: M3Icon { name: "info"; size: 24; color: "white"; anchors.centerIn: parent }
            ToolTip.visible: hovered; ToolTip.text: "Info"
            onClicked: root.infoPanelOpen = !root.infoPanelOpen
        }
        Button {
            width: 48; height: 48
            background: Rectangle { radius: 24; color: Qt.alpha("white", 0.12) }
            contentItem: M3Icon { name: "delete_forever"; size: 24; color: "#ffd8e4"; anchors.centerIn: parent }
            ToolTip.visible: hovered; ToolTip.text: "Delete permanently"
            onClicked: deleteConfirm.visible = true
        }
    }

    // Delete confirmation
    Rectangle {
        id: deleteConfirm
        visible: false
        anchors.horizontalCenter: actionRow.horizontalCenter
        anchors.bottom: actionRow.top
        anchors.bottomMargin: 8
        radius: 14
        color: ThemeManager.errorContainer
        width: confirmRow.implicitWidth + 24
        height: 52

        RowLayout {
            id: confirmRow
            anchors.centerIn: parent
            spacing: 8
            Label { text: "Delete permanently?"; color: ThemeManager.onErrorContainer; font.pixelSize: 13 }
            Button {
                flat: true
                contentItem: Label { text: "Cancel"; color: ThemeManager.onErrorContainer; font.pixelSize: 13; padding: 4 }
                onClicked: deleteConfirm.visible = false
            }
            Button {
                background: Rectangle { radius: 10; color: ThemeManager.error }
                contentItem: Label { text: "Delete"; color: "white"; font.pixelSize: 13; padding: 6; horizontalAlignment: Text.AlignHCenter }
                onClicked: {
                    if (root.mediaData) {
                        DB.deleteMediaPermanently(root.mediaData.id)
                        root.active = false
                        TimelineModel.refresh()
                    }
                }
            }
        }
    }

    // Info panel (slides in from right)
    MediaInfoPanel {
        id: infoPanel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 380
        mediaData: root.mediaData

        transform: Translate {
            x: root.infoPanelOpen ? 0 : 380
            Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
        }
    }
}
