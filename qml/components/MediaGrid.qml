import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    signal openViewer(var mediaData, int index)

    implicitWidth: 800
    implicitHeight: 600

    readonly property real hMargin:  20
    readonly property real gap:      6
    readonly property real contentW: width - hMargin * 2

    // Push content width to TimelineModel for aspect-ratio row packing.
    // Debounced so window-resize doesn't hammer the model.
    Timer {
        id: widthDebounce
        interval: 120
        onTriggered: TimelineModel.setContentWidth(Math.round(root.contentW))
    }
    onContentWChanged: widthDebounce.restart()
    Component.onCompleted: TimelineModel.setContentWidth(Math.round(contentW))

    // ── Preserve scroll position across model rebuilds ───────────────────
    // Save contentY before reset; restore after via a Timer (one frame later
    // lets the new delegates finish layout before we set contentY).
    property real _savedY: 0
    property bool _pendingRestore: false

    Connections {
        target: TimelineModel
        function onModelAboutToBeReset() {
            root._savedY = listView.contentY
        }
        function onModelReset() {
            if (root._savedY > 0) {
                // Qt.callLater defers until after layout is done — no visible jump
                Qt.callLater(function() {
                    var maxY = Math.max(0, listView.contentHeight - listView.height)
                    listView.contentY = Math.min(root._savedY, maxY)
                })
            }
        }
    }

    ListView {
        id: listView
        anchors.fill: parent
        model: TimelineModel
        clip: true
        spacing: root.gap
        leftMargin: hMargin
        rightMargin: hMargin
        topMargin: 0
        bottomMargin: 40
        cacheBuffer: Math.round(height * 3)
        visible: count > 0

        delegate: Item {
            id: rowItem
            readonly property bool   _isHeader: model.isHeader   || false
            readonly property string _month:    model.monthName  || ""
            readonly property var    _items:    model.items      || []
            // heightMult carries the actual row pixel height from aspect-ratio packing
            readonly property real   _rowH:     model.heightMult || 200

            width:  listView.width - root.hMargin * 2
            height: _isHeader ? 56 : Math.round(_rowH)

            Label {
                visible: rowItem._isHeader
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: rowItem._month
                font.family: "Roboto Flex"
                font.pixelSize: 20; font.weight: Font.Medium
                color: ThemeManager.onSurface
            }

            Row {
                visible: !rowItem._isHeader
                spacing: root.gap

                Repeater {
                    model: rowItem._items

                    Tile {
                        width:  modelData ? (modelData.item_width  || Math.round(rowItem._rowH * 1.33)) : Math.round(rowItem._rowH * 1.33)
                        height: rowItem._rowH
                        tileData: modelData
                        onOpen: {
                            if (modelData) root.openViewer(modelData, modelData._flat_index || 0)
                        }
                        onToggleFav: {
                            if (modelData) {
                                DB.toggleFavorite(modelData.id)
                                TimelineModel.refresh()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Fast-scroll date scrubber ────────────────────────────────────────
    // A draggable handle on the right edge that shows the current month/year
    // and lets the user scrub through date ranges by dragging.
    Rectangle {
        id: scrubber
        visible: listView.count > 0 && listView.contentHeight > listView.height * 1.5
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 6
        color: "transparent"

        // The draggable handle
        Rectangle {
            id: scrubHandle
            width: 32; height: 56
            radius: 16
            anchors.right: parent.right
            color: scrubDrag.pressed ? ThemeManager.primary : Qt.alpha(ThemeManager.onSurface, 0.2)
            Behavior on color { ColorAnimation { duration: 100 } }

            // Position based on scroll ratio
            y: Math.max(0, Math.min(scrubber.height - height,
                listView.visibleArea.yPosition * scrubber.height))

            // Month label (shown while dragging)
            Rectangle {
                visible: scrubDrag.pressed
                anchors.right: parent.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: ThemeManager.inverseSurface
                radius: 10
                width: monthLabel.implicitWidth + 20; height: 36

                Label {
                    id: monthLabel
                    anchors.centerIn: parent
                    text: {
                        if (!scrubDrag.pressed) return ""
                        var idx = Math.floor(listView.count * (scrubHandle.y / scrubber.height))
                        idx = Math.max(0, Math.min(listView.count - 1, idx))
                        var item = TimelineModel.data(TimelineModel.index(idx, 0), 258) // MonthNameRole
                        return item || ""
                    }
                    color: ThemeManager.inverseOnSurface
                    font.pixelSize: 13; font.weight: Font.Medium
                }
            }

            MouseArea {
                id: scrubDrag
                anchors.fill: parent
                drag.target: scrubHandle
                drag.axis: Drag.YAxis
                drag.minimumY: 0
                drag.maximumY: scrubber.height - scrubHandle.height

                onPositionChanged: {
                    if (pressed) {
                        var ratio = scrubHandle.y / Math.max(1, scrubber.height - scrubHandle.height)
                        var targetIdx = Math.floor(ratio * listView.count)
                        listView.positionViewAtIndex(
                            Math.max(0, Math.min(listView.count - 1, targetIdx)),
                            ListView.Beginning)
                    }
                }
            }
        }
    }

    // Empty state
    ColumnLayout {
        anchors.centerIn: parent
        visible: listView.count === 0
        spacing: 16

        readonly property int    mode:   TimelineModel.filterMode
        readonly property bool   isVid:  TimelineModel.mimeFilter === "video/"

        M3Icon {
            Layout.alignment: Qt.AlignHCenter
            name:    parent.mode === 2 ? "delete"
                   : parent.mode === 1 ? "favorite"
                   : parent.isVid ? "video_library"
                   : "schedule"
            size: 96; color: ThemeManager.onSurfaceVariant; opacity: 0.4
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.mode === 2 ? "Trash is empty"
                 : parent.mode === 1 ? "No favorites yet"
                 : parent.isVid      ? "No videos found"
                 :                     "No photos found"
            font.pixelSize: 24; font.weight: Font.Light; color: ThemeManager.onSurface
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.mode === 2 ? "Deleted photos will appear here."
                 : parent.mode === 1 ? "Tap the heart on any photo to add it to Favorites."
                 : parent.isVid      ? "Scan a directory containing video files."
                 :                     "Press \"Scan directory\" to discover your photo library."
            font.pixelSize: 14; color: ThemeManager.onSurfaceVariant
        }
    }
}
