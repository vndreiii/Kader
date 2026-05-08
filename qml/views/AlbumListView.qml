import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property alias topPadding: gridView.topMargin

    GridView {
        id: gridView
        anchors.fill: parent
        cellWidth: width / Math.floor(width / 240)
        cellHeight: cellWidth + 60
        model: AlbumModel
        clip: true
        leftMargin: 24
        rightMargin: 24
        topMargin: 0
        bottomMargin: 40

        delegate: Item {
            id: albumItem
            width: gridView.cellWidth
            height: gridView.cellHeight

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Album Cover
                Rectangle {
                    id: coverRect
                    Layout.fillWidth: true
                    Layout.preferredHeight: width
                    radius: mouseArea.containsMouse ? 28 : 24
                    color: ThemeManager.surfaceContainerHigh
                    clip: true
                    
                    Behavior on radius { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }

                    Image {
                        anchors.fill: parent
                        source: model.cover || "" // Assuming cover role exists
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    // Pinned icon
                    Rectangle {
                        visible: model.pinned || false
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 12
                        width: 32; height: 32; radius: 16
                        color: Qt.alpha(ThemeManager.surface, 0.85)
                        M3Icon {
                            anchors.centerIn: parent
                            name: "pin"
                            size: 16; color: ThemeManager.primary
                        }
                    }

                    // Overflow button
                    Control {
                        id: overflowBtn
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12
                        width: 32; height: 32
                        opacity: mouseArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                        
                        background: Rectangle {
                            radius: 16
                            color: Qt.alpha("black", 0.4)
                        }
                        contentItem: M3Icon {
                            name: "more_vert"
                            size: 18; color: "white"
                            anchors.centerIn: parent
                        }
                    }

                    // Weight badge
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: 12
                        width: weightLabel.width + 20
                        height: 24; radius: 12
                        color: Qt.alpha("black", 0.55)
                        Label {
                            id: weightLabel
                            anchors.centerIn: parent
                            text: model.size || "0 MB"
                            color: "white"
                            font.pixelSize: 11; font.weight: Font.Medium
                        }
                    }
                }

                // Album Info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    Label {
                        Layout.fillWidth: true
                        text: model.name
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: ThemeManager.onSurface
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        spacing: 6
                        Label {
                            text: model.count + " items"
                            font.pixelSize: 12
                            color: ThemeManager.onSurfaceVariant
                        }
                        Rectangle {
                            width: 3; height: 3; radius: 1.5
                            color: ThemeManager.onSurfaceVariant
                            opacity: 0.6
                        }
                        Label {
                            visible: model.customCover || false
                            text: "Custom cover"
                            font.pixelSize: 12
                            color: ThemeManager.onSurfaceVariant
                        }
                    }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: console.log("Open Album:", model.name)
            }
        }
    }
}
