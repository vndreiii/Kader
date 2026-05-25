import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qcm.Material
import "components"
import "views"
import "I18n.js" as I18n

ApplicationWindow {
    id: window
    width: 1480
    height: 940
    visible: true
    title: qsTr("Kader")
    flags: Qt.Window | Qt.FramelessWindowHint

    property string currentView: "timeline"
    property bool sidebarCollapsed: false
    property string detailTitle: ""
    property bool viewerOnlyMode: false   // true when launched via argv[1]

    property real timelineScrollY: 0

    // Cached view instances — created once, reused across switches
    property Item _tlViewInst:       null
    property Item _albumsViewInst:   null
    property Item _mapViewInst:      null
    property Item _settingsViewInst: null

    Component.onCompleted: {
        var isViewerOnly = (typeof STARTUP_FILE === "string" && STARTUP_FILE !== "")

        // In vieweronly mode the stack and sidebar are never shown — skip expensive view creation.
        // Other views are created lazily on first navigation to avoid blocking startup.
        if (!isViewerOnly) Qt.callLater(() => {
            _tlViewInst = timelineView.createObject(null)
            mainStack.replace(_tlViewInst, StackView.Immediate)
        })

        if (isViewerOnly) {
            var mime = ""
            var fp = STARTUP_FILE
            if (/\.(mp4|mkv|mov|avi|webm)$/i.test(fp)) mime = "video/mp4"
            else mime = "image/jpeg"
            viewerOnlyMode = true
            viewerOverlay.allItems = [{ file_path: fp, mime_type: mime, id: -1, is_favorite: false, is_trashed: false }]
            viewerOverlay.currentIndex = 0
            viewerOverlay.mediaData = viewerOverlay.allItems[0]
            viewerOverlay.active = true
        }
    }

    // ── Folder picker (FAB + Settings "Add directory") ───────────────────
    function openFolderPickerForSettings() { mainFolderPicker.open() }

    FolderDialog {
        id: mainFolderPicker
        title: "Choose a directory to scan"
        onAccepted: {
            var path = selectedFolder.toString().replace(/^file:\/\//, "")
            DB.addIndexedDirectory(path)
            FileScanner.startScan(path)
        }
    }

    // Scan state
    property bool isScanning: false
    property string scanFolder: ""
    property int scanFileCount: 0
    property bool scanDone: false

    Connections {
        target: FileScanner
        function onScanStarted(path) {
            window.isScanning = true
            window.scanDone = false
            window.scanFolder = path
            window.scanFileCount = 0
            scanBannerTimer.stop()
        }
        function onScanProgress(count) {
            window.scanFileCount = count
        }
        function onScanFinished(paths, dirsScanned, duration, rootPath) {
            window.scanFileCount = paths.length
            window.isScanning = false
            window.scanDone = true
            scanBannerTimer.restart()
        }
    }

    Timer {
        id: scanBannerTimer
        interval: 3000
        onTriggered: window.scanDone = false
    }

    background: Rectangle {
        color: window.viewerOnlyMode ? "black" : ThemeManager.surface
        radius: window.viewerOnlyMode ? 0 : 14
        border.color: window.viewerOnlyMode ? "transparent" : Qt.alpha("black", 0.1)
        border.width: window.viewerOnlyMode ? 0 : 1
    }

    // Mouse back/forward buttons — navigate stack or viewer
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        propagateComposedEvents: true
        z: 9999
        onClicked: (mouse) => {
            if (mouse.button === Qt.BackButton) {
                if (viewerOverlay.active) {
                    viewerOverlay.navigatePrev()
                } else if (mainStack.depth > 1) {
                    mainStack.pop()
                    if (window.currentView === "hidden" || window.currentView === "trash" ||
                        window.currentView === "favorites") {
                        window.currentView = "timeline"
                        window.detailTitle = ""
                        TimelineModel.setFolderFilter("")
                        TimelineModel.setMimeFilter("")
                        TimelineModel.filterMode = 0
                    }
                }
            } else if (mouse.button === Qt.ForwardButton) {
                if (viewerOverlay.active) viewerOverlay.navigateNext()
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1 // For border
        spacing: 0
        visible: !window.viewerOnlyMode

        Sidebar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: width
            collapsed: window.sidebarCollapsed
            currentView: window.currentView
            onViewChanged: (view) => {
                if (view === "hidden") {
                    passwordPrompt.open()
                    return
                }
                window.currentView = view
                window.detailTitle = ""
                TimelineModel.setFolderFilter("")

                var tl = window._tlViewInst

                if (view === "timeline") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.setMimeFilter("")
                    TimelineModel.filterMode = 0
                } else if (view === "videos") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.filterMode = 0
                    TimelineModel.setMimeFilter("video/")
                } else if (view === "favorites") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.setMimeFilter("")
                    TimelineModel.filterMode = 1
                } else if (view === "trash") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.setMimeFilter("")
                    TimelineModel.filterMode = 2
                } else if (view === "albums") {
                    if (!window._albumsViewInst) window._albumsViewInst = albumsView.createObject(null)
                    mainStack.replace(window._albumsViewInst)
                } else if (view === "map") {
                    if (!window._mapViewInst) window._mapViewInst = mapView.createObject(null)
                    mainStack.replace(window._mapViewInst)
                } else if (view === "settings") {
                    if (!window._settingsViewInst) window._settingsViewInst = settingsView.createObject(null)
                    mainStack.replace(window._settingsViewInst)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Topbar
            Rectangle {
                id: topbar
                Layout.fillWidth: true
                height: 72
                color: ThemeManager.surface
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 16

                    // Sidebar toggle
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: foldHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                        M3Icon { anchors.centerIn: parent; name: window.sidebarCollapsed ? "menu" : "sidebar"; size: 24; color: ThemeManager.onSurfaceVariant }
                        MouseArea { id: foldHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.sidebarCollapsed = !window.sidebarCollapsed }
                    }

                    // Back button — Rectangle+MouseArea avoids Material style interference
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        visible: mainStack.depth > 1
                        color: backHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                        M3Icon { anchors.centerIn: parent; name: "arrow_back"; size: 24; color: ThemeManager.onSurfaceVariant }
                        MouseArea {
                            id: backHover
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mainStack.pop()
                                // If we were in a filtered view and there's nothing left to go back to,
                                // the stack top is now the real previous view — infer currentView from it.
                                if (window.currentView === "hidden" || window.currentView === "trash" ||
                                    window.currentView === "favorites") {
                                    // These views replace the whole stack; back here means we ended up
                                    // on a stale page — reset to a clean state.
                                    window.currentView = "timeline"
                                    window.detailTitle = ""
                                    TimelineModel.setFolderFilter("")
                                    TimelineModel.setMimeFilter("")
                                    TimelineModel.filterMode = 0
                                }
                            }
                        }
                    }

                    Column {
                        spacing: 2
                        Label {
                            text: mainStack.depth > 1 && window.detailTitle !== ""
                                  ? window.detailTitle
                                  : (viewTitles[window.currentView] || "")
                            font.family: "Roboto Flex"
                            font.pixelSize: 28
                            font.weight: Font.Medium
                            color: ThemeManager.onSurface
                        }
                        Label {
                            visible: mainStack.depth > 1 && window.detailTitle !== ""
                            text: viewTitles[window.currentView] || ""
                            font.pixelSize: 14
                            color: ThemeManager.onSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Empty Trash button — only shown in trash view
                    Rectangle {
                        visible: window.currentView === "trash"
                        height: 40
                        width: emptyTrashRow.implicitWidth + 24
                        radius: 20
                        color: emptyTrashHover.containsMouse
                               ? Qt.alpha(ThemeManager.error, 0.16)
                               : Qt.alpha(ThemeManager.error, 0.08)
                        Behavior on color { ColorAnimation { duration: 80 } }

                        RowLayout {
                            id: emptyTrashRow
                            anchors.centerIn: parent
                            spacing: 6
                            M3Icon {
                                name: "delete_forever"
                                size: 18
                                color: ThemeManager.error
                            }
                            Label {
                                text: I18n.t(Settings.language, "empty_trash")
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: ThemeManager.error
                            }
                        }

                        MouseArea {
                            id: emptyTrashHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                DB.emptyTrash()
                                TimelineModel.refresh()
                            }
                        }
                    }

                    Rectangle {
                        id: searchPill
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: searchField.forceActiveFocus()
                        }
                        width: 360
                        height: 48
                        radius: 24
                        color: ThemeManager.surfaceContainer
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            spacing: 12

                            M3Icon {
                                name: "search"
                                size: 20
                                color: ThemeManager.onSurfaceVariant
                            }

                            Item {
                                Layout.fillWidth: true
                                height: 28

                                Text {
                                    anchors.fill: parent
                                    text: I18n.t(Settings.language, "search_placeholder")
                                    color: ThemeManager.onSurfaceVariant
                                    font.pixelSize: 16
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchField.text.length === 0
                                }

                                TextInput {
                                    id: searchField
                                    objectName: "searchField"
                                    anchors.fill: parent
                                    color: ThemeManager.onSurface
                                    font.pixelSize: 16
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    onTextChanged: {
                                        TimelineModel.setSearchFilter(text)
                                        AlbumModel.setSearchFilter(text)
                                    }
                                }
                            }

                            Rectangle {
                                visible: searchField.text !== ""
                                width: 28; height: 28; radius: 14
                                color: clearHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                                M3Icon { anchors.centerIn: parent; name: "close"; size: 18; color: ThemeManager.onSurfaceVariant }
                                MouseArea { id: clearHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: searchField.text = "" }
                            }
                        }
                    }
                }
            }

            // Content Stack
            StackView {
                id: mainStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: timelineView
                
                pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
                pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
                popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
                popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
                replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
                replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            }
        }
    }
    
    // Timeline FAB — two-part: Refresh left, Add directory right
    Row {
        id: fabRow
        visible: !window.viewerOnlyMode && window.currentView === "timeline"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        z: 10
        spacing: 8

        // Left FAB — Refresh (icon always centered in 56px, label fades in to the right)
        Rectangle {
            id: fabRefresh
            property bool hovered: fabRefreshMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + refreshLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "sync"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: refreshLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "refresh_library")
                font.weight: Font.Medium; font.pixelSize: 14; color: ThemeManager.onPrimaryContainer
                opacity: fabRefresh.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: fabRefreshMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var dirs = DB.getIndexedDirectories()
                    for (var i = 0; i < dirs.length; i++) {
                        var p = dirs[i].path || ""
                        if (p) FileScanner.startScan(p)
                    }
                }
            }
        }

        // Right FAB — Add directory
        Rectangle {
            id: fabAdd
            property bool hovered: fabAddMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + addLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "add"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: addLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "add_directory")
                font.weight: Font.Medium; font.pixelSize: 14; color: ThemeManager.onPrimaryContainer
                opacity: fabAdd.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: fabAddMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: mainFolderPicker.open()
            }
        }
    }

    // Albums FAB — refresh left, new album right
    Row {
        id: albumFabRow
        visible: !window.viewerOnlyMode && window.currentView === "albums"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        z: 10
        spacing: 8

        Rectangle {
            id: fabAlbumRefresh
            property bool hovered: fabAlbumRefreshMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + albumRefreshLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "sync"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: albumRefreshLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "refresh_library")
                font.weight: Font.Medium; font.pixelSize: 14; color: ThemeManager.onPrimaryContainer
                opacity: fabAlbumRefresh.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            MouseArea {
                id: fabAlbumRefreshMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: AlbumModel.refresh()
            }
        }

        Rectangle {
            id: fabAlbumNew
            property bool hovered: fabAlbumNewMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + albumNewLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "add"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: albumNewLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "new_album")
                font.weight: Font.Medium; font.pixelSize: 14; color: ThemeManager.onPrimaryContainer
                opacity: fabAlbumNew.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            MouseArea {
                id: fabAlbumNewMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: newAlbumModal.open()
            }
        }
    }

    AlbumEditModal {
        id: newAlbumModal
        parent: Overlay.overlay
        onSaved: AlbumModel.refresh()
    }

    readonly property var viewTitles: ({
        "timeline":  I18n.t(Settings.language, "timeline"),
        "albums":    I18n.t(Settings.language, "albums"),
        "videos":    I18n.t(Settings.language, "videos"),
        "map":       I18n.t(Settings.language, "places"),
        "favorites": I18n.t(Settings.language, "favorites"),
        "hidden":    I18n.t(Settings.language, "hidden"),
        "trash":     I18n.t(Settings.language, "trash"),
        "settings":  I18n.t(Settings.language, "settings")
    })

    Component {
        id: timelineView
        MediaGrid {
            // Restore saved scroll when the grid is created (view switch back)
            Component.onCompleted: {
                if (window.timelineScrollY > 0)
                    Qt.callLater(() => { _savedY = window.timelineScrollY; _pendingRestore = true; restoreTimer.restart() })
            }
            // Save scroll position when this instance is about to be destroyed
            Component.onDestruction: window.timelineScrollY = _savedY

            onOpenViewer: (data, idx) => {
                viewerOverlay.mediaData = data
                viewerOverlay.currentIndex = idx
                viewerOverlay.allItems = TimelineModel.getFlatMediaList()
                viewerOverlay.active = true
            }
        }
    }

    Component {
        id: albumsView
        AlbumListView {
            onOpenAlbum: (folderPath, albumName) => {
                window.detailTitle = albumName
                var detail = mainStack.push(Qt.resolvedUrl("views/AlbumDetailView.qml"), {
                    folderPath: folderPath,
                    albumName: albumName
                })
                detail.openViewer.connect(function(data, idx) {
                    viewerOverlay.mediaData = data
                    viewerOverlay.currentIndex = idx
                    viewerOverlay.allItems = TimelineModel.getFlatMediaList()
                    viewerOverlay.active = true
                })
            }
        }
    }

    Component {
        id: mapView
        MapView {
            onOpenViewer: (data) => {
                viewerOverlay.mediaData = data
                viewerOverlay.currentIndex = 0
                viewerOverlay.allItems = [data]
                viewerOverlay.active = true
            }
        }
    }

    Component {
        id: settingsView
        SettingsView {}
    }

    // Scan progress banner
    Rectangle {
        id: scanBanner
        visible: window.isScanning || window.scanDone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 50
        width: Math.min(560, parent.width - 48)
        height: 64
        radius: 20
        color: window.scanDone ? ThemeManager.primaryContainer : ThemeManager.inverseSurface

        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        transform: Translate { y: scanBanner.visible ? 0 : 24 }

        // Animated scan indicator bar (only while scanning)
        Rectangle {
            visible: window.isScanning
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 10
            height: 3
            radius: 1.5
            color: Qt.alpha(ThemeManager.inverseOnSurface, 0.2)

            Rectangle {
                id: progressPill
                height: parent.height
                width: 80
                radius: parent.radius
                color: ThemeManager.inverseOnSurface
                SequentialAnimation on x {
                    running: window.isScanning
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: scanBanner.width - 112; duration: 1200; easing.type: Easing.InOutQuart }
                    NumberAnimation { from: scanBanner.width - 112; to: 0; duration: 1200; easing.type: Easing.InOutQuart }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: window.isScanning ? 16 : 0
            spacing: 12

            M3Icon {
                name: window.scanDone ? "check" : "schedule"
                size: 20
                color: window.scanDone ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface
            }

            Column {
                Layout.fillWidth: true
                spacing: 1
                Label {
                    text: window.scanDone
                        ? "Scan complete — " + window.scanFileCount.toLocaleString() + " files found"
                        : "Scanning " + window.scanFolder.replace(Settings.homePath, "~")
                    color: window.scanDone ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    visible: window.isScanning
                    text: window.scanFileCount.toLocaleString() + " media files found so far…"
                    color: Qt.alpha(window.scanDone ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface, 0.7)
                    font.pixelSize: 11
                }
            }
        }
    }

    PasswordPrompt {
        id: passwordPrompt
        parent: Overlay.overlay
        anchors.fill: parent
        onAccepted: {
            window.currentView = "hidden"
            window.detailTitle = ""
            TimelineModel.setFolderFilter("")
            TimelineModel.setMimeFilter("")
            TimelineModel.filterMode = 3
            // Clear any sub-pages so back button never appears inside Hidden
            while (mainStack.depth > 1)
                mainStack.pop(null, StackView.Immediate)
            mainStack.replace(timelineView)
        }
        onRejected: { /* stay on current view */ }
    }

    ViewerOverlay {
        id: viewerOverlay
        parent: Overlay.overlay
        anchors.fill: parent
        viewerOnlyMode: window.viewerOnlyMode
    }
}
