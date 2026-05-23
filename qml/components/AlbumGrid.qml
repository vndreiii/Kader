import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qcm.Material as MD
import ".."

Item {
    id: root
    property string mimePrefix: ""   // "image/" or "video/" — filters which albums to show
    signal openAlbum(string folderPath, string albumName)

    readonly property int count: gridView.count
    implicitHeight: gridView.contentHeight

    GridView {
        id: gridView
        anchors.fill: parent
        // Filter the shared AlbumModel by dominant MIME type
        model: AlbumModel
        clip: false
        interactive: false
        leftMargin: 24
        rightMargin: 24
        topMargin: 0
        bottomMargin: 0

        readonly property real contentW: width - leftMargin - rightMargin
        readonly property int  numCols:  Math.max(1, Math.floor(contentW / 220))
        cellWidth:  contentW / numCols
        cellHeight: cellWidth + 64

        delegate: Item {
            id: albumItem
            width: gridView.cellWidth
            readonly property bool _show: root.mimePrefix === "" ||
                (model.mime_prefix ? model.mime_prefix.toString().startsWith(root.mimePrefix) : root.mimePrefix.startsWith("image/"))
            visible: _show
            height: _show ? gridView.cellHeight : 0

            MD.Menu {
                id: albumMenu
                MD.MenuItem {
                    text: model.pinned ? "Unpin album" : "Pin album"
                    onTriggered: { DB.pinAlbum(model.path, !model.pinned); AlbumModel.refresh() }
                }
                MD.MenuItem {
                    text: "Add to Ignored"
                    onTriggered: { DB.ignoreAlbum(model.path, true); AlbumModel.refresh(); TimelineModel.refresh() }
                }
                MD.MenuItem {
                    text: "Move to Trash"
                    onTriggered: { DB.trashAlbum(model.path); AlbumModel.refresh(); TimelineModel.refresh() }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) albumMenu.popup()
                    else root.openAlbum(model.path, model.name)
                }
            }

            Button {
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
                    id: thumbRect
                    Layout.fillWidth: true
                    Layout.preferredHeight: width
                    radius: mouseArea.containsMouse ? 28 : 24
                    color: ThemeManager.surfaceContainerHigh
                    Behavior on radius { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }

                    // Mask shape — invisible, feeds MultiEffect below
                    Rectangle {
                        id: thumbMask
                        anchors.fill: parent
                        radius: parent.radius
                        color: "white"
                        visible: false
                        layer.enabled: true
                    }

                    // Content clipped to rounded rect via MultiEffect
                    Item {
                        id: thumbContent
                        anchors.fill: parent

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

                        // Video badge
                        Rectangle {
                            visible: root.mimePrefix.startsWith("video/")
                            anchors.centerIn: parent
                            width: 48; height: 48; radius: 24
                            color: Qt.alpha("black", 0.55)
                            M3Icon { anchors.centerIn: parent; name: "play"; size: 28; color: "white" }
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
                            maskSource: thumbMask
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { Layout.fillWidth: true; text: model.name || ""; font.pixelSize: 16; font.weight: Font.Medium; color: ThemeManager.onSurface; elide: Text.ElideRight }
                    Label { text: (model.count || 0) + " items"; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                }
            }
        }
    }
}
