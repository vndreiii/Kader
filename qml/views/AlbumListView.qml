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

    // ── Multi-select state ─────────────────────────────────────────────────
    property bool selectionMode: false
    property var  _selSet: ({})

    function isAlbumSelected(path) { return !!_selSet[path] }
    function selectAlbum(path) {
        if (!_selSet[path]) { var s = Object.assign({}, _selSet); s[path] = true; _selSet = s }
    }
    function toggleAlbum(path) {
        var s = Object.assign({}, _selSet)
        if (s[path]) delete s[path]; else s[path] = true
        _selSet = s
    }
    function clearSelection() { _selSet = {}; selectionMode = false }
    function selectedPaths() { return Object.keys(_selSet) }

    Keys.onEscapePressed: if (selectionMode) clearSelection()

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
                    text: "Select"
                    onTriggered: { root.selectionMode = true; root.selectAlbum(albumItem._path) }
                }
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

            // Selection ring — wraps thumbnail only (not text labels below)
            Rectangle {
                x: 8; y: 8
                width: albumItem.width - 16
                height: albumItem.width - 16
                radius: mouseArea.containsMouse ? 28 : 24
                color: "transparent"
                border.width: root.isAlbumSelected(albumItem._path) ? 3 : 0
                border.color: ThemeManager.primary
                z: 5
                Behavior on border.width { NumberAnimation { duration: 80 } }
            }

            // Selection checkmark — inside thumbnail area
            Rectangle {
                visible: root.selectionMode
                x: 20; y: 20; z: 6
                width: 28; height: 28; radius: 14
                color: root.isAlbumSelected(albumItem._path) ? ThemeManager.primary : Qt.alpha("white", 0.5)
                Behavior on color { ColorAnimation { duration: 100 } }
                M3Icon {
                    anchors.centerIn: parent
                    name: "check"; size: 16; color: "white"
                    opacity: root.isAlbumSelected(albumItem._path) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 80 } }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (root.selectionMode) {
                        root.toggleAlbum(albumItem._path)
                    } else if (mouse.button === Qt.RightButton) {
                        albumMenu.popup()
                    } else {
                        root.openAlbum(albumItem._path, albumItem._name)
                    }
                }
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

    // Selection drag overlay
    MouseArea {
        id: albumSelOverlay
        anchors.fill: gridView
        enabled: root.selectionMode
        z: 50
        propagateComposedEvents: false

        property point _pressPos: Qt.point(0, 0)
        property bool  _dragging: false

        onPressed: (mouse) => {
            _pressPos = Qt.point(mouse.x, mouse.y)
            _dragging = false
        }
        onPositionChanged: (mouse) => {
            if (!pressed) return
            var dx = mouse.x - _pressPos.x; var dy = mouse.y - _pressPos.y
            if (Math.sqrt(dx*dx + dy*dy) > 6) { _dragging = true }
            if (_dragging) _selectAtPos(mouse.x, mouse.y)
        }
        onReleased: (mouse) => {
            if (!_dragging) _toggleAtPos(mouse.x, mouse.y)
            _dragging = false
        }

        function _selectAtPos(mx, my) {
            var pt = albumSelOverlay.mapToItem(gridView.contentItem, mx, my)
            var item = gridView.itemAt(pt.x, pt.y)
            if (item && item._path) root.selectAlbum(item._path)
        }
        function _toggleAtPos(mx, my) {
            var pt = albumSelOverlay.mapToItem(gridView.contentItem, mx, my)
            var item = gridView.itemAt(pt.x, pt.y)
            if (item && item._path) root.toggleAlbum(item._path)
        }
    }

    // Selection action bar
    Rectangle {
        visible: root.selectionMode
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        z: 200
        height: 56
        width: selAlbumRow.contentWidth + 8
        radius: 28
        color: ThemeManager.inverseSurface
        opacity: root.selectionMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Row {
            id: selAlbumRow
            anchors.centerIn: parent
            spacing: 4

            Label {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 12; rightPadding: 8
                text: Object.keys(root._selSet).length + " selected"
                color: ThemeManager.inverseOnSurface
                font.pixelSize: 14; font.weight: Font.Medium
            }

            // Pin / Unpin
            Rectangle {
                width: 44; height: 44; radius: 22
                color: pinSelMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                M3Icon { anchors.centerIn: parent; name: "pin"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: pinSelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var paths = root.selectedPaths()
                        for (var i = 0; i < paths.length; i++) DB.pinAlbum(paths[i], true)
                        AlbumModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Ignore / hide from gallery
            Rectangle {
                width: 44; height: 44; radius: 22
                color: ignoreSelMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                M3Icon { anchors.centerIn: parent; name: "visibility_off"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: ignoreSelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var paths = root.selectedPaths()
                        for (var i = 0; i < paths.length; i++) DB.ignoreAlbum(paths[i], true)
                        AlbumModel.refresh(); TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Trash selected
            Rectangle {
                width: 44; height: 44; radius: 22
                color: trashSelMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                M3Icon { anchors.centerIn: parent; name: "delete"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: trashSelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var paths = root.selectedPaths()
                        for (var i = 0; i < paths.length; i++) DB.trashAlbum(paths[i])
                        AlbumModel.refresh(); TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            Item { width: 4; height: 1 }

            // Clear selection
            Rectangle {
                width: 44; height: 44; radius: 22
                color: clearAlbSelMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                M3Icon { anchors.centerIn: parent; name: "close"; size: 18; color: Qt.alpha(ThemeManager.inverseOnSurface, 0.6) }
                MouseArea {
                    id: clearAlbSelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearSelection()
                }
            }

            Item { width: 4; height: 1 }
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
