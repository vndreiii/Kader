import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Qcm.Material as MD
import ".."

Item {
    id: root
    property var tileData: null
    property bool selectable: false
    property bool selected: false
    signal open()
    signal toggleFav()
    signal selectToggle()
    signal enterSelectionMode()

    readonly property var _d: (tileData !== null && tileData !== undefined) ? tileData : ({})

    // ── Background placeholder (visible while image loads) ────────────────
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: ThemeManager.surfaceContainerHigh
    }

    // ── Round mask shape — feeds MultiEffect below ────────────────────────
    Rectangle {
        id: roundMask
        anchors.fill: parent
        radius: 16
        color: "white"
        visible: false
        layer.enabled: true
    }

    // ── All content — clipped to rounded rect via MultiEffect ─────────────
    Item {
        id: contentLayer
        anchors.fill: parent

        Image {
            id: img
            anchors.fill: parent
            source: {
                if (root.width > 600 && root._d.file_path) return "file://" + root._d.file_path
                var p = root._d.thumb || root._d.file_path || ""
                if (p && p.indexOf("://") === -1) return "file://" + p
                return p
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            autoTransform: true
            cache: false

            scale: mouseArea.containsMouse ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        }

        // Video badge
        Rectangle {
            visible: root._d.mime_type ? root._d.mime_type.toString().startsWith("video/") : false
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: Qt.alpha("black", 0.55)
            M3Icon { anchors.centerIn: parent; name: "play"; size: 14; color: "white" }
        }

        // Selection checkmark
        Rectangle {
            visible: root.selectable || root.selected
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: ThemeManager.primary
            opacity: (root.selectable || root.selected) ? 1 : 0
            M3Icon { anchors.centerIn: parent; name: "check"; size: 16; color: "white" }
        }

        // Favorite button
        Rectangle {
            id: favButton
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
            width: 28; height: 28; radius: 14
            color: Qt.alpha("black", 0.45)
            opacity: (mouseArea.containsMouse || (root._d.is_favorite ? true : false)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
            M3Icon {
                anchors.centerIn: parent
                name: (root._d.is_favorite ? true : false) ? "favorite_fill" : "favorite"
                size: 16
                color: (root._d.is_favorite ? true : false) ? "#ffd8e4" : "white"
            }
            MouseArea { anchors.fill: parent; onClicked: root.toggleFav() }
        }

        // Date meta on hover
        Rectangle {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            anchors.leftMargin: 28; anchors.bottomMargin: 8
            height: 24; radius: 12
            color: Qt.alpha("black", 0.4)
            visible: mouseArea.containsMouse && !!root._d.creation_date
            Row {
                anchors.centerIn: parent; leftPadding: 8; rightPadding: 8
                Label {
                    text: {
                        var d = root._d.creation_date
                        if (!d) return ""
                        return Qt.formatDateTime(new Date(d * 1000), "dd MMM")
                    }
                    color: "white"; font.pixelSize: 11; font.weight: Font.Medium
                }
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            maskSource: roundMask
        }
    }

    // ── Selection border (outside clip so ring is fully visible) ──────────
    Rectangle {
        anchors.fill: parent; radius: 16
        color: "transparent"
        border.width: root.selected ? 3 : 0
        border.color: ThemeManager.primary
        visible: root.selected
    }

    // ── Context menu ──────────────────────────────────────────────────────
    property string _filePath:   root._d.file_path   || ""
    property int    _mediaId:    root._d.id          || 0
    property bool   _isFav:      root._d.is_favorite ? true : false
    property bool   _isTrashed:  root._d.is_trashed  ? true : false
    property bool   _isHidden:   root._d.is_hidden   ? true : false
    property string _folderPath: root._d.folder_path || ""

    MD.Menu {
        id: tileMenu
        MD.MenuItem {
            text: "Select"
            onTriggered: root.enterSelectionMode()
        }
        MD.MenuItem {
            text: root._isFav ? "Unfavorite" : "Favorite"
            onTriggered: { if (root._mediaId) { DB.toggleFavorite(root._mediaId); TimelineModel.refresh() } }
        }
        MD.MenuItem {
            text: "Open in Folder"
            onTriggered: { if (root._folderPath) Qt.openUrlExternally("file://" + root._folderPath) }
        }
        MD.MenuItem {
            text: root._isHidden ? "Unhide" : "Hide"
            onTriggered: {
                if (root._mediaId) {
                    DB.setHidden(root._mediaId, !root._isHidden)
                    TimelineModel.refresh()
                }
            }
        }
        MD.MenuItem {
            text: root._isTrashed ? "Restore" : "Move to Trash"
            onTriggered: {
                if (root._mediaId) {
                    DB.setTrashed(root._mediaId, !root._isTrashed)
                    TimelineModel.refresh()
                }
            }
        }
        MD.MenuItem {
            text: "Delete permanently"
            onTriggered: {
                if (root._mediaId) { DB.deleteMediaPermanently(root._mediaId); TimelineModel.refresh() }
            }
        }
    }

    // ── Mouse area ────────────────────────────────────────────────────────
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (root.selectable) root.selectToggle()
                else tileMenu.popup()
            } else if (root.selectable) {
                root.selectToggle()
            } else {
                root.open()
            }
        }
    }
}
