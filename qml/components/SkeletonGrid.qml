import QtQuick
import ".."

// Mosaic-shaped loading placeholder for photo grids: month headers followed
// by justified rows of varied widths, the same rhythm as the real timeline,
// so content replaces it without the layout jumping.
Item {
    id: root
    property real gap: 6
    property real rowHeight: 180
    property bool headers: true
    clip: true

    // Relative widths per row; each row is scaled to the full width.
    readonly property var _rows: [
        [1.5, 1.0, 1.33, 0.75],
        [1.0, 1.78, 1.33],
        [0.75, 1.5, 1.0, 1.0, 1.33],
        [1.33, 1.33, 1.78],
        [1.0, 0.75, 1.5, 1.33]
    ]

    Column {
        width: parent.width
        spacing: root.gap

        Repeater {
            // enough rows to overfill any window
            model: Math.ceil(root.height / (root.rowHeight + root.gap)) + 1

            Column {
                id: rowCol
                required property int index
                readonly property var _w: root._rows[index % root._rows.length]
                readonly property real _sum: _w.reduce((a, b) => a + b, 0)
                width: root.width
                spacing: root.gap

                // a month header every few rows
                Item {
                    visible: root.headers && rowCol.index % 3 === 0
                    width: parent.width
                    height: visible ? 40 : 0
                    Skeleton {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 140; height: 18; radius: 9
                    }
                }

                Row {
                    spacing: root.gap
                    Repeater {
                        model: rowCol._w
                        Skeleton {
                            required property real modelData
                            width: (root.width - root.gap * (rowCol._w.length - 1)) * modelData / rowCol._sum
                            height: root.rowHeight
                            radius: 16
                        }
                    }
                }
            }
        }
    }
}
