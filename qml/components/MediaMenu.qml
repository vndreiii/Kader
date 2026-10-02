import QtQuick
import QtQuick.Controls
import ".."
import "../I18n.js" as I18n

// The right-click menu for one photo or video, shared by the gallery tiles
// and the Search page's grids. `media` is a media map ({ id, file_path,
// is_favorite, is_hidden, is_trashed, … }). `changed` fires after anything
// that alters the library, for views that cache their own lists.
Item {
    id: root
    property var media: null
    signal selectRequested()
    signal changed()

    readonly property var _d: media || ({})
    readonly property int _id: _d.id || 0
    readonly property string _path: _d.file_path || ""
    readonly property bool _fav: !!_d.is_favorite
    readonly property bool _hidden: !!_d.is_hidden
    readonly property bool _trashed: !!_d.is_trashed

    function popup() { menu.popup() }
    function _done() { TimelineModel.refresh(); root.changed() }

    M3Menu {
        id: menu
        M3MenuItem {
            iconName: "check_circle"
            text: I18n.t(Settings.language, "ctx_select")
            onTriggered: root.selectRequested()
        }
        M3MenuItem {
            iconName: root._fav ? "heart_minus" : "favorite"
            text: root._fav ? "Unfavorite" : "Favorite"
            onTriggered: if (root._id) { DB.toggleFavorite(root._id); root._done() }
        }
        M3MenuItem {
            iconName: "folder_open"
            text: I18n.t(Settings.language, "ctx_open_folder")
            onTriggered: if (root._path) DB.revealInFolder(root._path)
        }
        M3MenuItem {
            iconName: "photo_album"
            text: I18n.t(Settings.language, "ctx_send_album")
            visible: TimelineModel.filterMode !== 3 /* HiddenMode */
            height: visible ? implicitHeight : 0
            onTriggered: {
                sendLoader.active = true
                sendLoader.item.albumList = DB.getAlbumList()
                sendLoader.item.open()
            }
        }
        M3MenuItem {
            iconName: root._hidden ? "visibility" : "visibility_off"
            text: root._hidden ? "Unhide" : "Hide"
            onTriggered: if (root._id) { DB.setHidden(root._id, !root._hidden); root._done() }
        }
        M3MenuItem {
            iconName: "block"
            text: I18n.t(Settings.language, "ctx_add_ignored")
            onTriggered: if (root._id) { DB.setIgnored(root._id, true); root._done() }
        }
        M3MenuItem {
            iconName: root._trashed ? "restore_from_trash" : "delete"
            text: root._trashed ? "Restore" : "Move to Trash"
            onTriggered: if (root._id) { DB.setTrashed(root._id, !root._trashed); root._done() }
        }
        M3MenuItem {
            iconName: "delete_forever"
            destructive: true
            text: I18n.t(Settings.language, "tip_delete_perm")
            onTriggered: if (root._id) { DB.deleteMediaPermanently(root._id); root._done() }
        }
    }

    // Album picker for "Send to album…" (built on first use)
    Loader {
        id: sendLoader
        active: false
        sourceComponent: Popup {
            id: sendPopup
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
                    model: sendPopup.albumList
                    delegate: Rectangle {
                        required property var modelData
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
                                if (root._id && targetPath) {
                                    DB.moveMediaToAlbum(root._id, targetPath)
                                    AlbumModel.refresh()
                                    root._done()
                                }
                                sendPopup.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
