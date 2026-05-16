import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
                window.currentView = view
                if (view === "timeline") {
                    TimelineModel.filterMode = 0
                    mainStack.replace(timelineView)
                } else if (view === "albums") {
                    mainStack.replace(albumsView)
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

                    Button {
                        visible: mainStack.depth > 1
                        width: 40; height: 40
                        background: Rectangle {
                            radius: 20
                            color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        }
                        contentItem: M3Icon { name: "arrow_back"; size: 24; color: ThemeManager.onSurfaceVariant; anchors.centerIn: parent }
                        onClicked: mainStack.pop()
                    }

                    Button {
                        id: foldButton
                        width: 40; height: 40
                        background: Rectangle {
                            radius: 20
                            color: foldButton.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        }
                        contentItem: M3Icon {
                            name: window.sidebarCollapsed ? "menu_open" : "menu_close"
                            size: 24
                            color: ThemeManager.onSurfaceVariant
                            anchors.centerIn: parent
                        }
                        onClicked: window.sidebarCollapsed = !window.sidebarCollapsed
                    }

                    Label {
                        text: viewTitles[window.currentView] || ""
                        font.family: "Roboto Flex"
                        font.pixelSize: 28
                        color: ThemeManager.onSurface
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        width: 40; height: 40
                        background: Rectangle {
                            radius: 20
                            color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        }
                        contentItem: M3Icon {
                            name: "tune"
                            size: 20
                            color: ThemeManager.onSurfaceVariant
                            anchors.centerIn: parent
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

                            Button {
                                visible: searchField.text !== ""
                                width: 28; height: 28
                                background: Rectangle {
                                    radius: 14
                                    color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                                }
                                contentItem: M3Icon {
                                    name: "close"
                                    size: 18
                                    color: ThemeManager.onSurfaceVariant
                                    anchors.centerIn: parent
                                }
                                onClicked: searchField.text = ""
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
        onClicked: {
            if (window.currentView === "timeline" || window.currentView === "favorites" || window.currentView === "trash") {
                var p = Settings.homePath + "/Pictures"
                DB.addIndexedDirectory(p)
                FileScanner.startScan(p)
            }
        }
    }

    readonly property var viewTitles: ({
        "timeline": "Timeline",
        "albums": "Albums",
        "map": "Places",
        "favorites": "Favorites",
        "trash": "Trash",
        "settings": "Settings"
    })

    Component {
        id: timelineView
        MediaGrid {
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

    ViewerOverlay {
        id: viewerOverlay
    }
}
