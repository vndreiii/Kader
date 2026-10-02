import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../views"
import "../I18n.js" as I18n

Rectangle {
    id: root
    property bool collapsed: false
    property string currentView: "timeline"
    signal viewChanged(string view)

    width: collapsed ? 84 : 280
    implicitWidth: width
    color: ThemeManager.surfaceContainer
    radius: ThemeManager.radiusLg
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
        radius: ThemeManager.radiusXxl
        color: ThemeManager.secondaryContainer
        z: 0

        Behavior on width { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }

        // Animate y with a snappy bounce curve
        Behavior on y {
            NumberAnimation {
                duration: 300 // Snappy and fast
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
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

            Image {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 28
                width: 32; height: 32
                source: "qrc:/Kader/assets/Kader Logoicon.svg"
                // rasterise at display size (2x for HiDPI), not the SVG's 727px
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Column {
                visible: !root.collapsed
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 72
                Label { text: "Kader"; font.family: "Roboto Flex"; font.pixelSize: 18; font.weight: Font.Medium; color: ThemeManager.onSurface }
                Label { text: I18n.t(Settings.language, "timeline"); font.pixelSize: ThemeManager.fontLabelM; color: ThemeManager.onSurfaceVariant; opacity: 0.6 }
            }
        }

        Item { width: 1; height: 8 }

        SidebarItem { id: itTimeline;  icon: "schedule";      label: I18n.t(Settings.language, "timeline");  active: root.currentView === "timeline";   collapsed: root.collapsed; onClicked: root.viewChanged("timeline")  }
        SidebarItem { id: itSearch;    icon: "search";        label: I18n.t(Settings.language, "search");    active: root.currentView === "search";     collapsed: root.collapsed; onClicked: root.viewChanged("search")   }
        SidebarItem { id: itAlbums;    icon: "folder";        label: I18n.t(Settings.language, "albums");    active: root.currentView === "albums";     collapsed: root.collapsed; onClicked: root.viewChanged("albums")   }
        SidebarItem { id: itVideos;    icon: "video_library"; label: I18n.t(Settings.language, "videos");    active: root.currentView === "videos";     collapsed: root.collapsed; onClicked: root.viewChanged("videos")   }
        SidebarItem { id: itMap;       icon: "explore";       label: I18n.t(Settings.language, "map");       active: root.currentView === "map";        collapsed: root.collapsed; onClicked: root.viewChanged("map")      }

        Rectangle {
            width: parent.width - 48; height: 1
            color: ThemeManager.outlineVariant; opacity: 0.3
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Item { width: 1; height: 8 }

        SidebarItem { id: itFavorites; icon: "favorite";  label: I18n.t(Settings.language, "favorites"); active: root.currentView === "favorites"; collapsed: root.collapsed; onClicked: root.viewChanged("favorites") }
        SidebarItem { id: itHidden;    icon: "lock";      label: I18n.t(Settings.language, "hidden");    active: root.currentView === "hidden";    collapsed: root.collapsed; onClicked: root.viewChanged("hidden")    }
        SidebarItem { id: itTrash;     icon: "delete";    label: I18n.t(Settings.language, "trash");     active: root.currentView === "trash";     collapsed: root.collapsed; onClicked: root.viewChanged("trash")     }
    }

    // ── Pill y tracker ────────────────────────────────────────────────────
    // Map view name → the SidebarItem that owns it, then track its y in root coordinates.
    readonly property var _activeItem: {
        switch (root.currentView) {
        case "timeline":  return itTimeline
        case "search":    return itSearch
        case "albums":    return itAlbums
        case "videos":    return itVideos
        case "map":       return itMap
        case "favorites": return itFavorites
        case "hidden":    return itHidden
        case "trash":     return itTrash
        case "settings":  return itSettings
        default:          return null
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
            id: storageCard
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 12
            height: root.collapsed ? 160 : expandedCol.implicitHeight + 28
            radius: root.collapsed ? ThemeManager.radiusXl : ThemeManager.radiusLg
            color: ThemeManager.surfaceContainerLow
            clip: true

            readonly property double _otherGb: Math.max(0,
                StorageManager.totalGb - StorageManager.freeGb
                - StorageManager.photoGb - StorageManager.videoGb)

            Column {
                id: expandedCol
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: 14; anchors.leftMargin: 14; anchors.rightMargin: 14
                spacing: 9
                visible: !root.collapsed

                Row {
                    spacing: 8
                    M3Icon { name: "computer"; size: 18; color: ThemeManager.primary }
                    Label { text: I18n.t(Settings.language, "this_pc"); font.pixelSize: ThemeManager.fontLabelM; font.weight: Font.Medium; color: ThemeManager.onSurface }
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
                            width: parent.parent.width * (storageCard._otherGb / Math.max(0.001, StorageManager.totalGb))
                            height: parent.height; color: ThemeManager.secondary; opacity: 0.7
                        }
                    }
                }
                // Legend: photos + video on one line
                Row {
                    width: parent.width; spacing: 8
                    Rectangle { width: 8; height: 8; radius: 4; color: ThemeManager.primary; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: StorageManager.photoGb.toFixed(1) + " GB " + I18n.t(Settings.language, "photos"); font.pixelSize: ThemeManager.fontLabelS; color: ThemeManager.onSurfaceVariant }
                    Rectangle { width: 8; height: 8; radius: 4; color: ThemeManager.tertiary; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: StorageManager.videoGb.toFixed(1) + " GB " + I18n.t(Settings.language, "video"); font.pixelSize: ThemeManager.fontLabelS; color: ThemeManager.onSurfaceVariant }
                }
                // Other + free/total on one line
                Row {
                    width: parent.width; spacing: 6
                    Rectangle { width: 8; height: 8; radius: 4; color: ThemeManager.secondary; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: storageCard._otherGb.toFixed(1) + " GB " + I18n.t(Settings.language, "other"); font.pixelSize: 10; color: Qt.alpha(ThemeManager.onSurfaceVariant, 0.7) }
                    Label {
                        text: StorageManager.freeGb.toFixed(1) + " GB " + I18n.t(Settings.language, "free") + "  " + StorageManager.totalGb.toFixed(0) + " GB " + I18n.t(Settings.language, "total")
                        font.pixelSize: 10; color: Qt.alpha(ThemeManager.onSurfaceVariant, 0.5)
                        elide: Text.ElideRight
                        width: parent.width - parent.children[0].width - parent.children[1].implicitWidth - parent.spacing * 2
                    }
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
                            height: Math.max(0, parent.parent.height * (storageCard._otherGb / Math.max(0.001, StorageManager.totalGb)))
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
                    font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Bold
                    color: ThemeManager.onSurfaceVariant
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
            
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: ThemeManager.onSurface
                opacity: mouseAreaStorage.pressed ? ThemeManager.pressOpacity : (mouseAreaStorage.containsMouse ? ThemeManager.hoverOpacity : 0.0)
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
            }
            MouseArea {
                id: mouseAreaStorage
                anchors.fill: parent
                hoverEnabled: true
                onClicked: dashboardModal.openFrom(storageCard)
            }
        }

        SidebarItem {
            id: itSettings
            icon: "settings"; label: I18n.t(Settings.language, "settings")
            active: root.currentView === "settings"
            collapsed: root.collapsed
            onClicked: root.viewChanged("settings")
        }

        Item { width: 1; height: 8 }
    }

    Popup {
        id: dashboardModal
        parent: Overlay.overlay
        
        property real targetW: parent ? parent.width * 0.85 : 800
        property real targetH: parent ? parent.height * 0.85 : 600
        property real targetX: parent ? (parent.width - targetW) / 2 : 0
        property real targetY: parent ? (parent.height - targetH) / 2 : 0

        property real startX: 0
        property real startY: 0
        property real startW: 0
        property real startH: 0
        property real startRadius: 0

        x: targetX
        y: targetY
        width: targetW
        height: targetH

        modal: true
        dim: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.5)
            opacity: dashboardModal.opened ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
        }
        
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: dashboardModal.startX; to: dashboardModal.targetX; duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { property: "y"; from: dashboardModal.startY; to: dashboardModal.targetY; duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { property: "width"; from: dashboardModal.startW; to: dashboardModal.targetW; duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { property: "height"; from: dashboardModal.startH; to: dashboardModal.targetH; duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { target: modalBg; property: "radius"; from: dashboardModal.startRadius; to: ThemeManager.radiusXl; duration: 400; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { target: modalContent; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { target: dashboardModal; property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
            }
        }
        
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: dashboardModal.targetX; to: dashboardModal.startX; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { property: "y"; from: dashboardModal.targetY; to: dashboardModal.startY; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { property: "width"; from: dashboardModal.targetW; to: dashboardModal.startW; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { property: "height"; from: dashboardModal.targetH; to: dashboardModal.startH; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { target: modalBg; property: "radius"; from: ThemeManager.radiusXl; to: dashboardModal.startRadius; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                NumberAnimation { target: modalContent; property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                SequentialAnimation {
                    PauseAnimation { duration: 150 }
                    NumberAnimation { target: dashboardModal; property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] }
                }
            }
        }

        background: Rectangle {
            id: modalBg
            color: ThemeManager.surface
            radius: ThemeManager.radiusXl
            border.color: ThemeManager.outlineVariant
            border.width: 1
            clip: true
        }
        
        // Built on first open, not at startup. A Popup's contentItem is created
        // with the component, and DashboardView's Component.onCompleted runs
        // MediaModel.refresh() — a full-library query and sort that the app paid
        // for on every cold start, for a modal nobody had opened yet.
        property bool dashboardLoaded: false

        contentItem: Item {
            id: modalContent
            opacity: dashboardModal.opened ? 1 : 0

            Loader {
                anchors.fill: parent
                active: dashboardModal.dashboardLoaded
                sourceComponent: DashboardView { }
            }
        }

        function openFrom(sourceItem) {
            dashboardLoaded = true
            var pt = sourceItem.mapToItem(dashboardModal.parent, 0, 0)
            startX = pt.x
            startY = pt.y
            startW = sourceItem.width
            startH = sourceItem.height
            startRadius = sourceItem.radius || 0
            open()
        }
    }
}
