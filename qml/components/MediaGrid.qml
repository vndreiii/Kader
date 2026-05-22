import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    signal openViewer(var mediaData, int index)

    implicitWidth: 800
    implicitHeight: 600

    readonly property int  numCols:   4
    readonly property real gap:       6
    readonly property real hMargin:   24
    readonly property real contentW:  width - hMargin * 2
    readonly property real tileSize:  (contentW - (numCols - 1) * gap) / numCols
    readonly property real rowHeight: tileSize + gap

    Component.onCompleted: TimelineModel.numColumns = numCols

    ListView {
        id: listView
        anchors.fill: parent
        model: TimelineModel
        clip: true
        spacing: 0
        leftMargin: hMargin
        rightMargin: hMargin
        topMargin: 0
        bottomMargin: 40
        cacheBuffer: Math.round(height * 3)
        visible: count > 0

        delegate: Item {
            id: rowItem
            readonly property bool   _isHeader: model.isHeader  || false
            readonly property string _month:    model.monthName || ""
            readonly property var    _items:    model.items     || []

            width:  listView.width - hMargin * 2
            height: _isHeader ? 72 : root.rowHeight

            Label {
                visible: rowItem._isHeader
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                text: rowItem._month
                font.family: "Roboto Flex"
                font.pixelSize: 22
                font.weight: Font.Medium
                color: ThemeManager.onSurface
            }

            Row {
                visible: !rowItem._isHeader
                spacing: root.gap

                Repeater {
                    model: rowItem._items

                    Tile {
                        width: {
                            var span = (modelData && modelData.col_span) ? modelData.col_span : 1
                            return root.tileSize * span + root.gap * (span - 1)
                        }
                        height: root.tileSize
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

    ColumnLayout {
        anchors.centerIn: parent
        visible: listView.count === 0
        spacing: 16

        readonly property int mode: TimelineModel.filterMode

        M3Icon {
            Layout.alignment: Qt.AlignHCenter
            name:    parent.mode === 2 ? "delete" : parent.mode === 1 ? "favorite" : "schedule"
            size:    96
            color:   ThemeManager.onSurfaceVariant
            opacity: 0.4
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.mode === 2 ? "Trash is empty"
                 : parent.mode === 1 ? "No favorites yet"
                 :                     "No photos found"
            font.pixelSize: 24
            font.weight: Font.Light
            color: ThemeManager.onSurface
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.mode === 2 ? "Deleted photos will appear here."
                 : parent.mode === 1 ? "Tap the heart on any photo to add it to Favorites."
                 :                     "Press \"Scan directory\" to discover your photo library."
            font.pixelSize: 14
            color: ThemeManager.onSurfaceVariant
        }
    }
}
