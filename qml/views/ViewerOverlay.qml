import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.alpha("black", 0.94)
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

    // ── Navigation ────────────────────────────────────────────────────────
    function navigatePrev() {
        if (currentIndex > 0) {
            _transition(-1)
            currentIndex--
            mediaData = allItems[currentIndex]
        }
    }
    function navigateNext() {
        if (currentIndex < allItems.length - 1) {
            _transition(1)
            currentIndex++
            mediaData = allItems[currentIndex]
        }
    }

    // direction: -1 = going left (prev), 1 = going right (next)
    property int _dir: 0
    function _transition(dir) {
        _dir = dir
        // Freeze outgoing image
        outImg.source = mainImg.source
        outImg.opacity = 1
        outImg.x = 0
        // Slide outgoing out and bring new one in
        outAnim.restart()
        inAnim.restart()
    }

    // Backdrop dismiss
    MouseArea {
        anchors.fill: parent
        onClicked: root.active = false
    }

    // ── Image display area ────────────────────────────────────────────────
    Item {
        id: imgArea
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.margins: 72
        anchors.bottomMargin: 80
        clip: true

        // Outgoing image (slides out during transition)
        Image {
            id: outImg
            anchors.centerIn: parent
            width:  Math.min(imgArea.width,  implicitWidth  > 0 ? implicitWidth  : imgArea.width)
            height: Math.min(imgArea.height, implicitHeight > 0 ? implicitHeight : imgArea.height)
            fillMode: Image.PreserveAspectFit
            opacity: 0
            x: 0

            NumberAnimation {
                id: outAnim
                target: outImg
                property: "x"
                to: root._dir < 0 ? imgArea.width * 0.3 : -imgArea.width * 0.3
                duration: 280
                easing.type: Easing.OutQuint
                onRunningChanged: if (!running) outImg.opacity = 0
            }
        }

        // Main / incoming image
        Image {
            id: mainImg
            anchors.centerIn: parent
            width:  Math.min(imgArea.width,  implicitWidth  > 0 ? implicitWidth  : imgArea.width)
            height: Math.min(imgArea.height, implicitHeight > 0 ? implicitHeight : imgArea.height)
            source: root.mediaData ? "file://" + root.mediaData.file_path : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true

            NumberAnimation {
                id: inAnim
                target: mainImg
                property: "x"
                from: root._dir > 0 ? imgArea.width * 0.18 : -imgArea.width * 0.18
                to: 0
                duration: 320
                easing.type: Easing.OutQuint
            }
        }
    }

    // ── Prev ──────────────────────────────────────────────────────────────
    Button {
        anchors.left: parent.left; anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52
        enabled: root.currentIndex > 0
        opacity: enabled ? 1.0 : 0.25
        scale: pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        onClicked: root.navigatePrev()
        background: Rectangle { radius: 26; color: Qt.alpha("white", 0.14); border.color: Qt.alpha("white", 0.08); border.width: 1 }
        contentItem: M3Icon { name: "chevron_left"; size: 26; color: "white"; anchors.centerIn: parent }
    }

    // ── Next ──────────────────────────────────────────────────────────────
    Button {
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52
        enabled: root.currentIndex < root.allItems.length - 1
        opacity: enabled ? 1.0 : 0.25
        scale: pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        onClicked: root.navigateNext()
        background: Rectangle { radius: 26; color: Qt.alpha("white", 0.14); border.color: Qt.alpha("white", 0.08); border.width: 1 }
        contentItem: M3Icon { name: "chevron_right"; size: 26; color: "white"; anchors.centerIn: parent }
    }

    // ── Close ─────────────────────────────────────────────────────────────
    Button {
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 24
        width: 48; height: 48
        scale: pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        onClicked: root.active = false
        background: Rectangle { radius: 24; color: Qt.alpha("white", 0.14) }
        contentItem: M3Icon { name: "close"; size: 22; color: "white"; anchors.centerIn: parent }
    }

    // ── Filename + date ───────────────────────────────────────────────────
    Column {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 28
        spacing: 4
        Label {
            text: root.mediaData ? root.mediaData.file_path.split('/').pop() : "Untitled"
            color: "white"; font.family: "Roboto Flex"; font.pixelSize: 18; font.weight: Font.Medium
        }
        Label {
            text: root.mediaData && root.mediaData.creation_date
                  ? Qt.formatDateTime(new Date(root.mediaData.creation_date * 1000), "dd MMMM yyyy")
                  : ""
            color: Qt.alpha("white", 0.65); font.pixelSize: 13
        }
    }

    // ── Action buttons ────────────────────────────────────────────────────
    Row {
        id: actionRow
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        spacing: 8

        Repeater {
            model: [
                { icon: (root.mediaData && root.mediaData.is_favorite) ? "favorite_fill" : "favorite", tip: "Favourite",
                  action: function() { if (!root.mediaData) return; DB.toggleFavorite(root.mediaData.id); root.mediaData = DB.getMediaById(root.mediaData.id); TimelineModel.refresh() } },
                { icon: "delete",         tip: "Move to Trash",
                  action: function() { if (!root.mediaData) return; DB.setTrashed(root.mediaData.id, true); root.active = false; TimelineModel.refresh() } },
                { icon: "folder_open",    tip: "Show in folder",
                  action: function() { if (root.mediaData) Qt.openUrlExternally("file://" + root.mediaData.folder_path) } },
                { icon: "info",           tip: "Info",
                  action: function() { root.infoPanelOpen = !root.infoPanelOpen } },
                { icon: "delete_forever", tip: "Delete permanently",
                  action: function() { deleteConfirm.visible = true } }
            ]

            Button {
                width: 48; height: 48
                scale: pressed ? 0.90 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }
                background: Rectangle {
                    radius: 24
                    color: (modelData.icon === "info" && root.infoPanelOpen)
                           ? Qt.alpha("white", 0.28) : Qt.alpha("white", 0.12)
                }
                contentItem: M3Icon {
                    name: modelData.icon; size: 22; color: "white"; anchors.centerIn: parent
                }
                ToolTip.visible: hovered; ToolTip.text: modelData.tip
                onClicked: modelData.action()
            }
        }
    }

    // ── Delete confirmation ───────────────────────────────────────────────
    Rectangle {
        id: deleteConfirm
        visible: false
        anchors.horizontalCenter: actionRow.horizontalCenter
        anchors.bottom: actionRow.top; anchors.bottomMargin: 8
        radius: 14; color: ThemeManager.errorContainer
        width: confirmRow.implicitWidth + 24; height: 52

        RowLayout {
            id: confirmRow; anchors.centerIn: parent; spacing: 8
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
                    if (root.mediaData) { DB.deleteMediaPermanently(root.mediaData.id); root.active = false; TimelineModel.refresh() }
                }
            }
        }
    }

    // ── Info panel ────────────────────────────────────────────────────────
    MediaInfoPanel {
        id: infoPanel
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
        width: 380
        mediaData: root.mediaData

        transform: Translate {
            x: root.infoPanelOpen ? 0 : 380
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
        }
    }
}
