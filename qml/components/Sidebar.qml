import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property bool collapsed: false
    property string currentView: "timeline"
    signal viewChanged(string view)

    width: collapsed ? 84 : 280
    implicitWidth: width
    color: ThemeManager.surfaceContainer
    radius: 16
    clip: true

    // Flatten left side
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 16
        color: parent.color
    }

    Behavior on width {
        NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint }
    }

    // ── Sliding active pill ───────────────────────────────────────────────
    Rectangle {
        id: activePill
        x: 12
        width: root.width - 24
        height: 56
        radius: 28
        color: ThemeManager.secondaryContainer
        z: 0

        Behavior on width { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }

        // Animate y with a spring — gives the "physical" bounce effect
        Behavior on y {
            SpringAnimation { spring: 600; damping: 28; mass: 1.0 }
        }
    }

    // ── Top section ───────────────────────────────────────────────────────
    Column {
        id: topColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        z: 1

        // Brand block
        Item {
            width: parent.width
            height: 80

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 28
                width: 32; height: 32; radius: 8
                color: ThemeManager.surfaceContainerHighest

                M3Icon {
                    anchors.centerIn: parent
                    name: "app_icon"; size: 24
                    color: ThemeManager.isColorDark(parent.color) ? "white" : "black"
                }
            }

            Column {
                visible: !root.collapsed
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 72
                Label { text: "Kader"; font.family: "Roboto Flex"; font.pixelSize: 18; font.weight: Font.Medium; color: ThemeManager.onSurface }
                Label { text: "Gallery"; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant; opacity: 0.6 }
            }
        }

        Item { width: 1; height: 8 }

        SidebarItem { id: itTimeline;  icon: "schedule";      label: "Timeline";  active: root.currentView === "timeline";   collapsed: root.collapsed; onClicked: root.viewChanged("timeline")  }
        SidebarItem { id: itAlbums;    icon: "folder";        label: "Albums";    active: root.currentView === "albums";     collapsed: root.collapsed; onClicked: root.viewChanged("albums")   }
        SidebarItem { id: itVideos;    icon: "video_library"; label: "Videos";    active: root.currentView === "videos";     collapsed: root.collapsed; onClicked: root.viewChanged("videos")   }
        SidebarItem { id: itMap;       icon: "map";           label: "Map";       active: root.currentView === "map";        collapsed: root.collapsed; onClicked: root.viewChanged("map")      }

        Rectangle {
            width: parent.width - 48; height: 1
            color: ThemeManager.outlineVariant; opacity: 0.3
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Item { width: 1; height: 8 }

        SidebarItem { id: itFavorites; icon: "favorite";  label: "Favorites"; active: root.currentView === "favorites"; collapsed: root.collapsed; onClicked: root.viewChanged("favorites") }
        SidebarItem { id: itHidden;    icon: "lock";      label: "Hidden";    active: root.currentView === "hidden";    collapsed: root.collapsed; onClicked: root.viewChanged("hidden")    }
        SidebarItem { id: itTrash;     icon: "delete";    label: "Trash";     active: root.currentView === "trash";     collapsed: root.collapsed; onClicked: root.viewChanged("trash")     }
    }

    // ── Pill y tracker ────────────────────────────────────────────────────
    // Map view name → the SidebarItem that owns it, then track its y in root coordinates.
    readonly property var _activeItem: {
        switch (root.currentView) {
        case "timeline":  return itTimeline
        case "albums":    return itAlbums
        case "videos":    return itVideos
        case "map":       return itMap
        case "favorites": return itFavorites
        case "hidden":    return itHidden
        case "trash":     return itTrash
        default:          return itTimeline
        }
    }

    // Reposition pill whenever the active item or layout changes
    function _syncPill() {
        if (!_activeItem) return
        var mapped = _activeItem.mapToItem(root, 0, 0)
        activePill.y = mapped.y
    }

    onCurrentViewChanged: Qt.callLater(_syncPill)
    Component.onCompleted: Qt.callLater(_syncPill)
    // Also re-sync when column height changes (section labels appear/disappear)
    onHeightChanged: Qt.callLater(_syncPill)
    Connections { target: topColumn; function onHeightChanged() { Qt.callLater(root._syncPill) } }

    // ── Bottom section ────────────────────────────────────────────────────
    Column {
        id: bottomColumn
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8
        z: 1

        // Storage card
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 12
            height: root.collapsed ? 160 : 140
            radius: root.collapsed ? 22 : 16
            color: ThemeManager.surfaceContainerLow
            clip: true

            readonly property double _otherGb: Math.max(0,
                StorageManager.totalGb - StorageManager.freeGb
                - StorageManager.photoGb - StorageManager.videoGb)

            Column {
                anchors.fill: parent; anchors.margins: 16; spacing: 10
                visible: !root.collapsed

                Row {
                    spacing: 8
                    M3Icon { name: "computer"; size: 18; color: ThemeManager.primary }
                    Label { text: "This PC"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeManager.onSurface }
                }
                Rectangle {
                    width: parent.width; height: 6; radius: 3
                    color: ThemeManager.surfaceContainerHighest
                    Row {
                        height: parent.height; spacing: 0
                        Rectangle {
                            width: parent.parent.width * (StorageManager.photoGb / Math.max(0.001, StorageManager.totalGb))
                            height: parent.height; radius: 3; color: ThemeManager.primary
                        }
                        Rectangle {
                            width: parent.parent.width * (StorageManager.videoGb / Math.max(0.001, StorageManager.totalGb))
                            height: parent.height; color: ThemeManager.tertiary
                        }
                        Rectangle {
                            width: parent.parent.width * (parent.parent.parent._otherGb / Math.max(0.001, StorageManager.totalGb))
                            height: parent.height; color: ThemeManager.secondary; opacity: 0.7
                        }
                    }
                }
                Row {
                    width: parent.width; spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: ThemeManager.primary; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: StorageManager.photoGb.toFixed(1) + " GB photos"; font.pixelSize: 11; color: ThemeManager.onSurfaceVariant }
                    Rectangle { width: 8; height: 8; radius: 4; color: ThemeManager.tertiary; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: StorageManager.videoGb.toFixed(1) + " GB video"; font.pixelSize: 11; color: ThemeManager.onSurfaceVariant }
                }
                Row {
                    width: parent.width; spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: ThemeManager.secondary; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: parent._otherGb.toFixed(1) + " GB other"; font.pixelSize: 11; color: ThemeManager.onSurfaceVariant }
                }
                Label {
                    width: parent.width
                    text: StorageManager.freeGb.toFixed(1) + " GB free · " + StorageManager.totalGb.toFixed(0) + " GB total"
                    font.pixelSize: 10
                    color: Qt.alpha(ThemeManager.onSurfaceVariant, 0.6)
                    elide: Text.ElideRight
                }
            }

            Column {
                anchors.fill: parent; anchors.margins: 8; spacing: 12
                visible: root.collapsed

                M3Icon { name: "computer"; size: 18; color: ThemeManager.primary; anchors.horizontalCenter: parent.horizontalCenter }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 8; height: 80; radius: 4
                    color: ThemeManager.surfaceContainerHighest
                    Column {
                        anchors.bottom: parent.bottom; width: parent.width; spacing: 0
                        Rectangle {
                            width: parent.width
                            height: Math.max(0, parent.parent.height * (parent.parent.parent.parent._otherGb / Math.max(0.001, StorageManager.totalGb)))
                            color: ThemeManager.secondary; opacity: 0.7
                        }
                        Rectangle {
                            width: parent.width
                            height: Math.max(0, parent.parent.height * (StorageManager.videoGb / Math.max(0.001, StorageManager.totalGb)))
                            color: ThemeManager.tertiary
                        }
                        Rectangle {
                            width: parent.width
                            height: Math.max(0, parent.parent.height * (StorageManager.photoGb / Math.max(0.001, StorageManager.totalGb)))
                            radius: 4; color: ThemeManager.primary
                        }
                    }
                }
                Label {
                    text: StorageManager.mediaPercent + "%"
                    font.pixelSize: 14; font.weight: Font.Bold
                    color: ThemeManager.onSurfaceVariant
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        SidebarItem {
            icon: "settings"; label: "Settings"
            active: root.currentView === "settings"
            collapsed: root.collapsed
            onClicked: root.viewChanged("settings")
        }

        Item { width: 1; height: 8 }
    }
}
