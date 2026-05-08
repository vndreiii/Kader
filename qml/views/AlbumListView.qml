import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material

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
                    color: ThemeManager.surfaceColor
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
                        color: Qt.alpha(ThemeManager.backgroundColor, 0.7)
                        
                        Label {
                            id: labelCount
                            anchors.centerIn: parent
                            text: model.itemCount
                            font.pixelSize: 11
                            font.bold: true
                            color: ThemeManager.textColor
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
                        color: ThemeManager.textColor
                        elide: Text.ElideRight
                    }

                    Label {
                        text: model.totalSize
                        font.pixelSize: 12
                        color: ThemeManager.textColor
                        opacity: 0.6
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        albumMenu.popupTarget = model
                        albumMenu.popup()
                    } else {
                        console.log("Open Album:", model.path)
                    }
                }
            }
        }
    }

    Menu {
        id: albumMenu
        property var popupTarget: null
        
        MenuItem {
            text: "Pin Album"
            onTriggered: console.log("Pin:", albumMenu.popupTarget.path)
        }
        MenuItem {
            text: "Ignore Album"
            onTriggered: {
                DB.ignoreAlbum(albumMenu.popupTarget.path, true)
                AlbumModel.refresh()
                TimelineModel.refresh()
            }
        }
        MenuItem {
            text: "Delete Folder"
            onTriggered: console.log("Delete folder logic here")
        }
    }
}
