import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    anchors.fill: parent
    color: "#F5000000"  // 96% opaque black — enough to hide sidebar/topbar
    z: 1000
    visible: active

    property bool active: false
    property var  mediaData: null
    property int  currentIndex: -1
    property var  allItems: []
    property bool infoPanelOpen: false

    // ── Zoom / pan state ──────────────────────────────────────────────────
    property real _zoom: 1.0
    property real _panX: 0
    property real _panY: 0

    function resetZoom() { _zoom = 1.0; _panX = 0; _panY = 0 }
    onMediaDataChanged: resetZoom()

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
        resetZoom()
        _dir = dir
        outImg.source = mainImg.source
        outImg.opacity = 1
        outImg.x = 0
        outAnim.restart()
        inAnim.restart()
    }

    // ── Backdrop dismiss (only when not zoomed) ───────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: { if (root._zoom <= 1.0) root.active = false }
        onWheel: (wheel) => {
            if (wheel.angleDelta.y !== 0) {
                var factor = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15)
                root._zoom = Math.max(1.0, Math.min(8.0, root._zoom * factor))
                if (root._zoom <= 1.02) root.resetZoom()
                wheel.accepted = true
            }
        }
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
            autoTransform: true
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

        // Main / incoming image with zoom + pan
        Image {
            id: mainImg
            anchors.centerIn: parent
            width:  Math.min(imgArea.width,  implicitWidth  > 0 ? implicitWidth  : imgArea.width)
            height: Math.min(imgArea.height, implicitHeight > 0 ? implicitHeight : imgArea.height)
            source: root.mediaData ? "file://" + root.mediaData.file_path : ""
            fillMode: Image.PreserveAspectFit
            autoTransform: true
            asynchronous: true

            scale: root._zoom
            transformOrigin: Item.Center
            transform: Translate { x: root._panX; y: root._panY }

            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

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

        // Double-click zoom toggle + pan drag handler
        MouseArea {
            id: imgMouseArea
            anchors.fill: parent
            z: 2
            hoverEnabled: false
            acceptedButtons: Qt.LeftButton

            property real _dragStartX:   0
            property real _dragStartY:   0
            property real _dragStartPanX: 0
            property real _dragStartPanY: 0
            property bool _wasDrag:      false

            onDoubleClicked: {
                if (root._zoom > 1.05) {
                    root.resetZoom()
                } else {
                    root._zoom = 2.5
                }
            }

            onPressed: {
                _wasDrag = false
                if (root._zoom > 1.05) {
                    _dragStartX    = mouseX; _dragStartY    = mouseY
                    _dragStartPanX = root._panX; _dragStartPanY = root._panY
                }
            }

            onPositionChanged: {
                if (pressed && root._zoom > 1.05) {
                    _wasDrag = true
                    root._panX = _dragStartPanX + (mouseX - _dragStartX)
                    root._panY = _dragStartPanY + (mouseY - _dragStartY)
                }
            }

            onClicked: {
                if (!_wasDrag && root._zoom <= 1.05) root.active = false
            }

            cursorShape: root._zoom > 1.05 ? Qt.OpenHandCursor : Qt.ArrowCursor
        }
    }

    // ── Prev ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.left: parent.left; anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52; radius: 26
        color: Qt.alpha("white", prevMa.pressed ? 0.28 : prevMa.containsMouse ? 0.20 : 0.14)
        border.color: Qt.alpha("white", 0.08); border.width: 1
        opacity: root.currentIndex > 0 ? 1.0 : 0.25
        Behavior on color { ColorAnimation { duration: 80 } }
        scale: prevMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        M3Icon { anchors.centerIn: parent; name: "chevron_left"; size: 26; color: "white" }
        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.currentIndex > 0; onClicked: root.navigatePrev() }
    }

    // ── Next ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52; radius: 26
        color: Qt.alpha("white", nextMa.pressed ? 0.28 : nextMa.containsMouse ? 0.20 : 0.14)
        border.color: Qt.alpha("white", 0.08); border.width: 1
        opacity: root.currentIndex < root.allItems.length - 1 ? 1.0 : 0.25
        Behavior on color { ColorAnimation { duration: 80 } }
        scale: nextMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        M3Icon { anchors.centerIn: parent; name: "chevron_right"; size: 26; color: "white" }
        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.currentIndex < root.allItems.length - 1; onClicked: root.navigateNext() }
    }

    // ── Close ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 24
        width: 48; height: 48; radius: 24
        color: Qt.alpha("white", closeMa.pressed ? 0.28 : closeMa.containsMouse ? 0.20 : 0.14)
        Behavior on color { ColorAnimation { duration: 80 } }
        scale: closeMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        M3Icon { anchors.centerIn: parent; name: "close"; size: 22; color: "white" }
        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.active = false }
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

    // ── Zoom controls (centered at bottom) ───────────────────────────────
    Row {
        id: zoomRow
        anchors.horizontalCenter: imgArea.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        spacing: 8

        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", zoomOutMa.pressed ? 0.28 : zoomOutMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: zoomOutMa.pressed ? 0.92 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "remove"; size: 22; color: "white" }
            MouseArea { id: zoomOutMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { root._zoom = Math.max(1.0, root._zoom / 1.5); if (root._zoom <= 1.02) root.resetZoom() } }
        }

        Rectangle {
            width: 72; height: 48; radius: 24
            color: Qt.alpha("white", zoomResetMa.pressed ? 0.28 : zoomResetMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: zoomResetMa.pressed ? 0.92 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            Label { anchors.centerIn: parent; text: Math.round(root._zoom * 100) + "%"; color: "white"; font.pixelSize: 14; font.weight: Font.Medium }
            MouseArea { id: zoomResetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resetZoom() }
        }

        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", zoomInMa.pressed ? 0.28 : zoomInMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: zoomInMa.pressed ? 0.92 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "add"; size: 22; color: "white" }
            MouseArea { id: zoomInMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root._zoom = Math.min(8.0, root._zoom * 1.5) }
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

        property bool isFav: root.mediaData ? !!root.mediaData.is_favorite : false

        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", favMa.pressed ? 0.28 : favMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: favMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: actionRow.isFav ? "favorite_fill" : "favorite"; size: 22; color: "white" }
            MouseArea { id: favMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (!root.mediaData) return; DB.toggleFavorite(root.mediaData.id); root.mediaData = DB.getMediaById(root.mediaData.id); TimelineModel.refresh() } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", trashMa.pressed ? 0.28 : trashMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: trashMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "delete"; size: 22; color: "white" }
            MouseArea { id: trashMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (!root.mediaData) return; DB.setTrashed(root.mediaData.id, true); root.active = false; TimelineModel.refresh() } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", folderMa.pressed ? 0.28 : folderMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: folderMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "folder_open"; size: 22; color: "white" }
            MouseArea { id: folderMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.mediaData) Qt.openUrlExternally("file://" + root.mediaData.folder_path) } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", infoMa.pressed ? 0.28 : root.infoPanelOpen ? 0.28 : infoMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: infoMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "info"; size: 22; color: "white" }
            MouseArea { id: infoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.infoPanelOpen = !root.infoPanelOpen }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", delMa.pressed ? 0.28 : delMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: delMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "delete_forever"; size: 22; color: "#ffd8e4" }
            MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: deleteConfirm.visible = true }
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
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: 380
        mediaData: root.mediaData

        opacity: root.infoPanelOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

        transform: Translate {
            x: root.infoPanelOpen ? 0 : 380
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
        }
    }
}
