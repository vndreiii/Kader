import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."
import "../Paths.js" as Paths

// Square-thumbnail grid for search results and groups. `items` is a list of
// media maps ({ id, file_path, thumb, mime_type, … }).
GridView {
    id: root
    property var items: []
    property real minCell: 150
    property int maxRows: 0           // >0: show at most this many rows (preview)
    property bool loading: false      // show skeleton cells instead
    signal openItem(int index)

    readonly property int columns: Math.max(2, Math.floor(width / minCell))
    readonly property int _shown: maxRows > 0 ? Math.min(items.length, columns * maxRows) : items.length

    cellWidth: width / columns
    cellHeight: cellWidth
    interactive: maxRows === 0
    clip: maxRows === 0
    implicitHeight: maxRows > 0
        ? Math.ceil((loading ? columns * Math.min(maxRows, 2) : _shown) / columns) * cellHeight
        : contentHeight
    model: loading ? columns * Math.max(1, Math.min(maxRows || 3, 3)) : _shown
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: root.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    delegate: Item {
        id: cell
        required property int index
        readonly property var media: root.loading ? null : root.items[index]
        width: root.cellWidth
        height: root.cellHeight

        Item {
            anchors.fill: parent
            anchors.margins: 3

            Skeleton {
                anchors.fill: parent
                radius: 12
                visible: root.loading || thumb.status !== Image.Ready
                active: visible
            }
            Image {
                id: thumb
                anchors.fill: parent
                source: cell.media ? (cell.media.thumb || Paths.fileUrl(cell.media.file_path)) : ""
                sourceSize: Qt.size(320, 320)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            Rectangle { id: round; anchors.fill: parent; radius: 12; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                source: thumb
                visible: thumb.status === Image.Ready
                maskEnabled: true
                maskSource: round
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                scale: hover.containsMouse ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            }
            Rectangle {
                visible: cell.media && (cell.media.mime_type || "").toString().startsWith("video/")
                anchors { left: parent.left; top: parent.top; margins: 8 }
                width: 24; height: 24; radius: 12
                color: Qt.alpha("black", 0.55)
                M3Icon { anchors.centerIn: parent; name: "play"; size: 14; color: "white" }
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.loading
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openItem(cell.index)
            }
        }
    }
}
