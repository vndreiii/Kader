import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."
import "../I18n.js" as I18n

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
    readonly property bool _isGif: (root._d.mime_type || "").toString() === "image/gif"

    // Whichever media element is active — used to gate layer FBO allocation
    readonly property int _activeStatus: root._isGif ? gifImg.status : img.status

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
        // Only allocate the FBO once the active media element is loaded
        layer.enabled: root._activeStatus === Image.Ready
    }

    // ── All content — clipped to rounded rect via MultiEffect ─────────────
    Item {
        id: contentLayer
        anchors.fill: parent

        Image {
            id: img
            anchors.fill: parent
            visible: !root._isGif
            // Always use the async 768px thumbnail provider. Never decode the
            // full-resolution original in the grid — that was the main scroll
            // stutter (a 20MP decode + huge texture upload per wide tile mid-fling).
            source: {
                if (root._isGif) return ""
                var p = root._d.thumb || ""           // "image://thumbnails/<path>"
                if (p) return p
                var fp = root._d.file_path || ""
                return fp ? (fp.indexOf("://") === -1 ? "file://" + fp : fp) : ""
            }
            // Cap decode resolution so even the file:// fallback can't upload a
            // giant texture. 768 matches the cached thumbnail's longest edge.
            sourceSize.height: 768
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            autoTransform: true
            cache: true

            scale: mouseArea.containsMouse ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        }

        // Animated GIF — plays directly from file, loops automatically
        AnimatedImage {
            id: gifImg
            anchors.fill: parent
            visible: root._isGif
            source: root._isGif ? ("file://" + (root._d.file_path || "")) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            playing: root._isGif
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

        // GIF badge
        Rectangle {
            visible: root._isGif
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            height: 18; radius: 9; width: gifLabel.implicitWidth + 10
            color: Qt.alpha("black", 0.55)
            Label { id: gifLabel; anchors.centerIn: parent; text: "GIF"; color: "white"; font.pixelSize: 9; font.weight: Font.Bold }
        }

        // Selection checkmark — z above the privacy cover so hidden tiles stay
        // selectable (restore/delete) even while their thumbnail is covered.
        Rectangle {
            z: 10
            visible: root.selectable || root.selected
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: ThemeManager.primary
            opacity: (root.selectable || root.selected) ? 1 : 0
            M3Icon { anchors.centerIn: parent; name: "check"; size: 16; color: ThemeManager.onPrimary }
        }

        // Favorite button — 28dp visual chip inside a 48dp hit area (centered).
        // Reveal-on-hover still follows the whole-tile MouseArea (below), only
        // the click target itself is enlarged.
        Item {
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8 - (48 - 28) / 2
            width: 48; height: 48

            Rectangle {
                id: favButton
                anchors.centerIn: parent
                width: 28; height: 28; radius: 14
                color: Qt.alpha("black", 0.45)
                opacity: (mouseArea.containsMouse || (root._d.is_favorite ? true : false)) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                M3Icon {
                    anchors.centerIn: parent
                    name: (root._d.is_favorite ? true : false) ? "favorite_fill" : "favorite"
                    size: 16
                    color: (root._d.is_favorite ? true : false) ? ThemeManager.tertiaryContainer : "white"
                }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleFav() }
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
                    color: "white"; font.pixelSize: ThemeManager.fontLabelS; font.weight: Font.Medium
                }
            }
        }

        // Privacy cover — hidden items shown OUTSIDE the Hidden view (e.g. still
        // mixed into All/Favorites/Trash) must never reveal their thumbnail.
        // Opaque, sits above the image/badges/favorite button/date label but
        // below the selection checkmark (z: 10 above) so the tile stays
        // selectable for restore/delete without ever exposing the media.
        Rectangle {
            id: privacyCover
            z: 5
            visible: root._isHidden && TimelineModel.filterMode !== 3 /* HiddenMode */
            anchors.fill: parent
            radius: 16
            color: "black"
            M3Icon {
                anchors.centerIn: parent
                name: "visibility_off"
                size: 28
                color: "white"
            }
        }

        // Skip the FBO entirely while the placeholder is showing — no media loaded yet
        layer.enabled: root._activeStatus === Image.Ready
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

    // Context menu + album picker are created lazily (only on first right-click /
    // first "Send to album"). Eagerly instantiating these for every tile was a
    // big per-tile cost that hurt scroll when delegates recycle.
    function _showMenu() {
        menuLoader.active = true
        menuLoader.item.popup()
    }

    Loader {
        id: menuLoader
        active: false
        sourceComponent: M3Menu {
            M3MenuItem {
                text: I18n.t(Settings.language, "ctx_select")
                onTriggered: root.enterSelectionMode()
            }
            M3MenuItem {
                text: root._isFav ? "Unfavorite" : "Favorite"
                onTriggered: { if (root._mediaId) { DB.toggleFavorite(root._mediaId); TimelineModel.refresh() } }
            }
            M3MenuItem {
                text: I18n.t(Settings.language, "ctx_open_folder")
                onTriggered: { if (root._filePath) DB.revealInFolder(root._filePath) }
            }
            M3MenuItem {
                text: I18n.t(Settings.language, "ctx_send_album")
                visible: TimelineModel.filterMode !== 3 /* HiddenMode */
                onTriggered: {
                    sendLoader.active = true
                    sendLoader.item.albumList = DB.getAlbumList()
                    sendLoader.item.open()
                }
            }
            M3MenuItem {
                text: root._isHidden ? "Unhide" : "Hide"
                onTriggered: {
                    if (root._mediaId) {
                        DB.setHidden(root._mediaId, !root._isHidden)
                        TimelineModel.refresh()
                    }
                }
            }
            M3MenuItem {
                text: I18n.t(Settings.language, "ctx_add_ignored")
                onTriggered: {
                    if (root._mediaId) {
                        DB.setIgnored(root._mediaId, true)
                        TimelineModel.refresh()
                    }
                }
            }
            M3MenuItem {
                text: root._isTrashed ? "Restore" : "Move to Trash"
                onTriggered: {
                    if (root._mediaId) {
                        DB.setTrashed(root._mediaId, !root._isTrashed)
                        TimelineModel.refresh()
                    }
                }
            }
            M3MenuItem {
                text: I18n.t(Settings.language, "tip_delete_perm")
                onTriggered: {
                    if (root._mediaId) { DB.deleteMediaPermanently(root._mediaId); TimelineModel.refresh() }
                }
            }
        }
    }

    // Album picker popup for "Send to album..." (lazy)
    Loader {
        id: sendLoader
        active: false
        sourceComponent: Popup {
            parent: Overlay.overlay
            modal: true
            anchors.centerIn: parent
            width: 260
            padding: 8
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            property var albumList: []

            background: Rectangle {
                radius: 16
                color: ThemeManager.surfaceContainer
            }

            Column {
                width: parent.width - parent.padding * 2
                spacing: 0

                Label {
                    width: parent.width
                    text: I18n.t(Settings.language, "ctx_send_album_title")
                    font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
                    color: ThemeManager.onSurfaceVariant
                    leftPadding: 8; topPadding: 4; bottomPadding: 8
                }

                Repeater {
                    model: parent.parent.albumList
                    delegate: Rectangle {
                        width: parent.width; height: 44; radius: ThemeManager.radiusSm
                        color: sendMa.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            M3Icon { name: "folder"; size: 16; color: ThemeManager.onSurfaceVariant; anchors.verticalCenter: parent.verticalCenter }
                            Label {
                                text: modelData.name || ""
                                font.pixelSize: ThemeManager.fontLabelL; color: ThemeManager.onSurface
                                elide: Text.ElideRight
                                width: 200
                            }
                        }
                        MouseArea {
                            id: sendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var targetPath = modelData.path || ""
                                if (root._mediaId && targetPath) {
                                    DB.moveMediaToAlbum(root._mediaId, targetPath)
                                    TimelineModel.refresh()
                                    AlbumModel.refresh()
                                }
                                sendLoader.item.close()
                            }
                        }
                    }
                }
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
                else root._showMenu()
            } else if (root.selectable) {
                root.selectToggle()
            } else if (!privacyCover.visible) {
                root.open()
            }
        }
    }
}
