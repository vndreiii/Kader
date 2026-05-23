import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qcm.Material as MD
import "../components"

Item {
    id: root
    signal openAlbum(string folderPath, string albumName)
    property alias topPadding: gridView.topMargin

    implicitWidth: 800
    implicitHeight: 600

    GridView {
        id: gridView
        anchors.fill: parent

        readonly property real contentW: width - leftMargin - rightMargin
        readonly property int  numCols:  Math.max(1, Math.floor(contentW / 220))
        cellWidth:  contentW / numCols
        cellHeight: cellWidth + 64

        model: AlbumModel
        clip: true
        cacheBuffer: height * 2
        leftMargin: 24; rightMargin: 24
        topMargin: 0; bottomMargin: 40

        delegate: Item {
            id: albumItem
            width: gridView.cellWidth
            height: gridView.cellHeight

            // Capture model values so context menu onTriggered can access them
            // even after the delegate is recycled or model goes out of scope.
            property string _path:   model.path   || ""
            property string _name:   model.name   || ""
            property bool   _pinned: model.pinned || false

            MD.Menu {
                id: albumMenu
                MD.MenuItem {
                    text: albumItem._pinned ? "Unpin album" : "Pin album"
                    onTriggered: { DB.pinAlbum(albumItem._path, !albumItem._pinned); AlbumModel.refresh() }
                }
                MD.MenuItem {
                    text: "Add to Ignored"
                    onTriggered: { DB.ignoreAlbum(albumItem._path, true); AlbumModel.refresh(); TimelineModel.refresh() }
                }
                MD.MenuItem {
                    text: "Move to Trash"
                    onTriggered: { DB.trashAlbum(albumItem._path); AlbumModel.refresh(); TimelineModel.refresh() }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) albumMenu.popup()
                    else root.openAlbum(albumItem._path, albumItem._name)
                }
            }

            Button {
                id: moreBtn
                z: 10
                anchors.top: parent.top; anchors.right: parent.right
                anchors.topMargin: 20; anchors.rightMargin: 20
                width: 32; height: 32
                visible: mouseArea.containsMouse
                background: Rectangle { radius: 16; color: Qt.alpha("black", 0.4) }
                contentItem: M3Icon { name: "more_vert"; size: 18; color: "white"; anchors.centerIn: parent }
                onClicked: albumMenu.popup()
            }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 8; spacing: 8

                Rectangle {
                    id: coverRect
                    Layout.fillWidth: true; Layout.preferredHeight: width
                    radius: mouseArea.containsMouse ? 28 : 24
                    color: ThemeManager.surfaceContainerHigh
                    Behavior on radius { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }

                    Rectangle {
                        id: coverMask
                        anchors.fill: parent
                        radius: parent.radius
                        color: "white"
                        visible: false
                        layer.enabled: true
                    }

                    Item {
                        anchors.fill: parent

                        Image {
                            anchors.fill: parent
                            source: {
                                var p = model.cover || ""
                                if (p && p.indexOf("://") === -1) return "file://" + p
                                return p
                            }
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                        }

                        Rectangle {
                            visible: model.pinned || false
                            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 12
                            width: 32; height: 32; radius: 16
                            color: Qt.alpha(ThemeManager.surface, 0.85)
                            M3Icon { anchors.centerIn: parent; name: "pin"; size: 16; color: ThemeManager.primary }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 12
                            width: weightLabel.width + 20; height: 24; radius: 12
                            color: Qt.alpha("black", 0.55)
                            Label { id: weightLabel; anchors.centerIn: parent; text: model.size || "–"; color: "white"; font.pixelSize: 11; font.weight: Font.Medium }
                        }

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            maskSource: coverMask
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { Layout.fillWidth: true; text: model.name || ""; font.pixelSize: 16; font.weight: Font.Medium; color: ThemeManager.onSurface; elide: Text.ElideRight }
                    RowLayout {
                        spacing: 6
                        Label { text: (model.count || 0) + " items"; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: gridView.count === 0
        spacing: 16
        M3Icon { Layout.alignment: Qt.AlignHCenter; name: "folder"; size: 96; color: ThemeManager.onSurfaceVariant; opacity: 0.5 }
        Label { Layout.alignment: Qt.AlignHCenter; text: "No albums"; font.pixelSize: 24; font.weight: Font.Light; color: ThemeManager.onSurface }
    }
}
