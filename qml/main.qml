import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qcm.Material
import "components"
import "views"

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

    // Persists the timeline scroll position across view switches
    property real timelineScrollY: 0

    Component.onCompleted: {
        if (typeof STARTUP_FILE === "string" && STARTUP_FILE !== "") {
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
        color: ThemeManager.surface
        radius: 14
        border.color: Qt.alpha("black", 0.1)
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1 // For border
        spacing: 0

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
                // Reset all filters when switching top-level views
                TimelineModel.setFolderFilter("")
                TimelineModel.setMimeFilter("")
                TimelineModel.filterMode = 0
                if (view === "timeline") {
                    mainStack.replace(timelineView)
                } else if (view === "albums") {
                    mainStack.replace(albumsView)
                } else if (view === "videos") {
                    TimelineModel.setMimeFilter("video/")
                    mainStack.replace(timelineView)
                } else if (view === "map") {
                    mainStack.replace(mapView)
                } else if (view === "favorites") {
                    TimelineModel.filterMode = 1
                    mainStack.replace(timelineView)
                } else if (view === "trash") {
                    TimelineModel.filterMode = 2
                    mainStack.replace(timelineView)
                } else if (view === "settings") {
                    mainStack.replace(settingsView)
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
                        MouseArea { id: backHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mainStack.pop() }
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

                    // Refresh/Rescan button
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: refreshHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                        M3Icon {
                            id: refreshIcon
                            anchors.centerIn: parent
                            name: "sync"; size: 22
                            color: window.isScanning ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                            RotationAnimator on rotation {
                                running: window.isScanning
                                from: 0; to: 360; duration: 1000
                                loops: Animation.Infinite
                            }
                        }
                        MouseArea {
                            id: refreshHover
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !window.isScanning
                            onClicked: {
                                var dirs = DB.getIndexedDirectories()
                                for (var i = 0; i < dirs.length; i++) {
                                    var p = dirs[i].path || ""
                                    if (p) FileScanner.startScan(p)
                                }
                            }
                        }
                    }

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
                                text: "Empty trash"
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
                                    text: "Search photos and albums"
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
                replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
                replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            }
        }
    }
    
    // FAB moved outside RowLayout for absolute positioning
    Button {
        id: fab
        visible: (window.currentView === "timeline" || window.currentView === "albums")
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        height: 56
        padding: 16
        z: 10
        
        background: Rectangle {
            radius: 16
            color: ThemeManager.primaryContainer
        }
        
        contentItem: RowLayout {
            spacing: 8
            M3Icon {
                name: window.currentView === "timeline" ? "schedule" : "add"
                size: 24
                color: ThemeManager.onPrimaryContainer
            }
            Label {
                text: window.currentView === "timeline" ? "Scan directory" : "New album"
                font.weight: Font.Medium
                font.pixelSize: 14
                color: ThemeManager.onPrimaryContainer
            }
        }
        onClicked: mainFolderPicker.open()
    }

    readonly property var viewTitles: ({
        "timeline":  "Timeline",
        "albums":    "Albums",
        "videos":    "Videos",
        "map":       "Places",
        "favorites": "Favorites",
        "hidden":    "Hidden",
        "trash":     "Trash",
        "settings":  "Settings"
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
        MapView {}
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
            TimelineModel.setFolderFilter("")
            TimelineModel.setMimeFilter("")
            TimelineModel.filterMode = 3
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
