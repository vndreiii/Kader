import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    property alias topPadding: listView.topMargin
    signal openViewer(var mediaData)

    implicitWidth: 800
    implicitHeight: 600

    ListView {
        id: listView
        anchors.fill: parent
        model: TimelineModel
        clip: true
        spacing: 0
        leftMargin: 24
        rightMargin: 24
        topMargin: 0
        bottomMargin: 40
        
        visible: model.rowCount() > 0

        section.property: "name"
        section.criteria: ViewSection.FullString
        section.delegate: Item {
            width: listView.width - 48
            height: 72
            Label {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                text: section
                font.family: "Roboto Flex"
                font.pixelSize: 22
                font.weight: Font.Medium
                color: ThemeManager.onSurface
            }
        }

        delegate: Item {
            width: listView.width - 48
            height: flowGrid.implicitHeight + 20
            
            Flow {
                id: flowGrid
                width: parent.width
                spacing: 8
                
                Repeater {
                    model: items
                    delegate: Tile {
                        modelData: modelData
                        
                        readonly property var sizes: ["size-1x1", "size-1x1", "size-2x1", "size-1x1", "size-2x2", "size-1x2", "size-1x1", "size-1x1"]
                        property string mSize: sizes[index % sizes.length]
                        
                        width: {
                            var cols = 6
                            var gap = 8
                            var unit = (flowGrid.width - (cols - 1) * gap) / cols
                            if (mSize === "size-2x1" || mSize === "size-2x2") return unit * 2 + gap
                            if (mSize === "size-3x2") return unit * 3 + gap * 2
                            return unit
                        }
                        height: {
                            var rowHeight = 124
                            var gap = 8
                            if (mSize === "size-1x2" || mSize === "size-2x2" || mSize === "size-3x2") return rowHeight * 2 + gap
                            return rowHeight
                        }
                        
                        onOpen: root.openViewer(modelData)
                    }
                }
            }
        }
    }

    // Empty State
    ColumnLayout {
        anchors.centerIn: parent
        visible: !listView.visible
        spacing: 16
        M3Icon {
            Layout.alignment: Qt.AlignHCenter
            name: "schedule"
            size: 96; color: ThemeManager.onSurfaceVariant
            opacity: 0.5
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "No media found"
            font.pixelSize: 24; font.weight: Font.Light; color: ThemeManager.onSurface
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "Mark photos with the heart to find them in favorites."
            font.pixelSize: 14; color: ThemeManager.onSurfaceVariant
        }
    }
}
