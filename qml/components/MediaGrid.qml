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
    // Debounced via a timer so window-resize doesn't hammer the model.
    Timer {
        id: widthDebounce
        interval: 120
        onTriggered: TimelineModel.setContentWidth(Math.round(root.contentW))
    }
    onContentWChanged: widthDebounce.restart()
    Component.onCompleted: TimelineModel.setContentWidth(Math.round(contentW))

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
            readonly property bool   _isHeader:    model.isHeader   || false
            readonly property string _month:       model.monthName  || ""
            readonly property var    _items:       model.items      || []
            // heightMult now carries the actual row pixel height from the packing algorithm
            readonly property real   _rowH:        model.heightMult || 200

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

            // Photo row: tiles have individually computed widths from aspect ratios
            Row {
                visible: !rowItem._isHeader
                spacing: root.gap

                Repeater {
                    model: rowItem._items

                    Tile {
                        // item_width and item_height are pre-computed by TimelineModel
                        // using the photo's real aspect ratio + row-packing algorithm.
                        width:  modelData ? (modelData.item_width  || rowItem._rowH * 1.33) : rowItem._rowH * 1.33
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

    // Empty state
    ColumnLayout {
        anchors.centerIn: parent
        visible: listView.count === 0
        spacing: 16

        readonly property int mode: TimelineModel.filterMode

        M3Icon {
            Layout.alignment: Qt.AlignHCenter
            name:    parent.mode === 2 ? "delete" : parent.mode === 1 ? "favorite" : "schedule"
            size: 96; color: ThemeManager.onSurfaceVariant; opacity: 0.4
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.mode === 2 ? "Trash is empty"
                 : parent.mode === 1 ? "No favorites yet"
                 :                     "No photos found"
            font.pixelSize: 24; font.weight: Font.Light; color: ThemeManager.onSurface
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.mode === 2 ? "Deleted photos will appear here."
                 : parent.mode === 1 ? "Tap the heart on any photo to add it to Favorites."
                 :                     "Press \"Scan directory\" to discover your photo library."
            font.pixelSize: 14; color: ThemeManager.onSurfaceVariant
        }
    }
}
