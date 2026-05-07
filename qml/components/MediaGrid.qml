import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QmlMaterial

Item {
    id: root

    GridView {
        id: grid
        anchors.fill: parent
        cellWidth: width / Math.floor(width / 180)
        cellHeight: cellWidth
        model: MediaModel
        clip: true

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                color: Theme.surfaceColor
                radius: 8
                clip: true

                Image {
                    anchors.fill: parent
                    source: model.thumb
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    
                    // Simple fade-in when loaded
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }

                // Video indicator
                Rectangle {
                    visible: model.mimeType.startsWith("video/")
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 24
                    height: 24
                    radius: 12
                    color: "#80000000"
                    
                    Label {
                        anchors.centerIn: parent
                        text: "▶"
                        color: "white"
                        font.pixelSize: 10
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    console.log("Clicked:", model.path)
                    // TODO: Open fullscreen viewer
                }
            }
        }
    }
}
