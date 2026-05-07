import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QmlMaterial

Item {
    id: root
    property alias topPadding: gridView.topMargin

    GridView {
        id: gridView
        anchors.fill: parent
        cellWidth: width / Math.floor(width / 220)
        cellHeight: cellWidth + 60
        model: AlbumModel
        clip: true
        leftMargin: 24
        rightMargin: 24
        bottomMargin: 40
        spacing: 12

        delegate: Item {
            width: gridView.cellWidth
            height: gridView.cellHeight

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Folder Cover
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.surfaceColor
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: model.coverThumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }

                    // Count Badge
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12
                        width: labelCount.width + 16
                        height: 24
                        radius: 12
                        color: Qt.alpha(Theme.backgroundColor, 0.7)
                        
                        Label {
                            id: labelCount
                            anchors.centerIn: parent
                            text: model.itemCount
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.textColor
                        }
                    }
                }

                // Album Info
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    Label {
                        width: parent.width
                        text: model.name
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.textColor
                        elide: Text.ElideRight
                    }

                    Label {
                        text: model.totalSize
                        font.pixelSize: 12
                        color: Theme.textColor
                        opacity: 0.6
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    console.log("Open Album:", model.path)
                    // TODO: Navigate to Album Detail
                }
            }
        }
    }
}
