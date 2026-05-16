import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
        leftMargin: 24
        rightMargin: 24
        topMargin: 0
        bottomMargin: 40

        delegate: Item {
            id: albumItem
            width: gridView.cellWidth
            height: gridView.cellHeight

            // Context menu at item level — triggered by ··· button OR right-click
            MD.Menu {
                id: albumMenu
                MD.MenuItem {
                    text: model.pinned ? "Unpin album" : "Pin album"
                    onTriggered: { DB.pinAlbum(model.folder_path, !model.pinned); AlbumModel.refresh() }
                }
                MD.MenuItem {
                    text: "Add to Ignored"
                    onTriggered: { DB.ignoreAlbum(model.folder_path, true); AlbumModel.refresh(); TimelineModel.refresh() }
                }
                MD.MenuItem {
                    text: "Change album cover"
                    enabled: false
                }
                MD.MenuItem {
                    text: "Move to Trash"
                    onTriggered: { DB.trashAlbum(model.folder_path); AlbumModel.refresh(); TimelineModel.refresh() }
                }
            }

            // MouseArea FIRST = lower z-order, so buttons on top capture clicks first
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        albumMenu.popup()
                    else
                        root.openAlbum(model.folder_path, model.name)
                }
            }

            // ··· button: direct child of albumItem at z:10 — guaranteed above mouseArea (z:0)
            Button {
                id: moreBtn
                z: 10
                // Position at top-right of the cover image area (cover = cellWidth - 2*8 margin = content area)
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 20   // 8px layout margin + 12px cover margin
                anchors.rightMargin: 20
                width: 32; height: 32
                visible: mouseArea.containsMouse
                background: Rectangle { radius: 16; color: Qt.alpha("black", 0.4) }
                contentItem: M3Icon { name: "more_vert"; size: 18; color: "white"; anchors.centerIn: parent }
                onClicked: albumMenu.popup()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

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
                        source: {
                            var p = model.cover || ""
                            if (p && p.indexOf("://") === -1) return "file://" + p
                            return p
                        }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Rectangle {
                        visible: model.pinned || false
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 12
                        width: 32; height: 32; radius: 16
                        color: Qt.alpha(ThemeManager.surface, 0.85)
                        M3Icon { anchors.centerIn: parent; name: "pin"; size: 16; color: ThemeManager.primary }
                    }


                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: 12
                        width: weightLabel.width + 20
                        height: 24; radius: 12
                        color: Qt.alpha("black", 0.55)
                        Label { id: weightLabel; anchors.centerIn: parent; text: model.size || "–"; color: "white"; font.pixelSize: 11; font.weight: Font.Medium }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { Layout.fillWidth: true; text: model.name || ""; font.pixelSize: 16; font.weight: Font.Medium; color: ThemeManager.onSurface; elide: Text.ElideRight }
                    RowLayout {
                        spacing: 6
                        Label { text: (model.count || 0) + " items"; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                        Rectangle { width: 3; height: 3; radius: 1.5; color: ThemeManager.onSurfaceVariant; opacity: 0.6 }
                        Label { visible: model.customCover || false; text: "Custom cover"; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                    }
                }
            }
        }
    }

    // Empty State
    ColumnLayout {
        anchors.centerIn: parent
        visible: gridView.count === 0
        spacing: 16
        M3Icon { Layout.alignment: Qt.AlignHCenter; name: "folder"; size: 96; color: ThemeManager.onSurfaceVariant; opacity: 0.5 }
        Label { Layout.alignment: Qt.AlignHCenter; text: "No albums"; font.pixelSize: 24; font.weight: Font.Light; color: ThemeManager.onSurface }
    }
}
