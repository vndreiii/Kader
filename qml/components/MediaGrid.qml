import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    property alias topPadding: listView.topMargin
    signal openViewer(var mediaData)

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
        
        // Month Header
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
            // Sticky behavior can be simulated or we use the section delegate
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
                        
                        // Mosaic sizing logic
                        readonly property var sizes: ["size-1x1", "size-1x1", "size-2x1", "size-1x1", "size-2x2", "size-1x2", "size-1x1", "size-1x1"]
                        property string mSize: sizes[index % sizes.length]
                        
                        width: {
                            var cols = 6
                            var gap = 8
                            var unit = (parent.width - (cols - 1) * gap) / cols
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

    // Floating scrollbar logic from before can be adapted but the design is minimalist
}
