import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material
import "components"
import "views"

ApplicationWindow {
    id: window
    width: 1100
    height: 800
    visible: true
    title: qsTr("Kader")

    property string currentView: "timeline"

    background: Rectangle {
        color: ThemeManager.backgroundColor
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.fillHeight: true
            width: 240
            color: ThemeManager.backgroundColor
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                // Logo/Title
                Item {
                    height: 64
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        Image {
                            source: "qrc:/Kader/assets/icon.svg"
                            sourceSize: Qt.size(32, 32)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: "Kader"
                            font.pixelSize: 24
                            font.bold: true
                            color: ThemeManager.textColor
                        }
                    }
                }

                SidebarItem {
                    objectName: "timelineSidebarItem"
                    label: "Timeline"
                    active: window.currentView === "timeline"
                    onClicked: {
                        window.currentView = "timeline"
                        mainStack.replace(timelineView)
                    }
                }
                SidebarItem {
                    objectName: "albumsSidebarItem"
                    label: "Albums"
                    active: window.currentView === "albums"
                    onClicked: {
                        window.currentView = "albums"
                        mainStack.replace(albumsView)
                    }
                }
                SidebarItem {
                    label: "Favorites"
                    active: window.currentView === "favorites"
                    onClicked: {
                        window.currentView = "favorites"
                        // mainStack.replace(favoritesView)
                    }
                }
                SidebarItem {
                    label: "Trash"
                    active: window.currentView === "trash"
                    onClicked: {
                        window.currentView = "trash"
                        // mainStack.replace(trashView)
                    }
                }

                Item { Layout.fillHeight: true }

                // Settings Button at bottom
                SidebarItem {
                    label: "Settings"
                    active: window.currentView === "settings"
                    onClicked: {
                        window.currentView = "settings"
                        mainStack.replace(settingsView)
                    }
                }

                Label {
                    id: statusLabel
                    text: "Kader Gallery v0.1"
                    font.pixelSize: 11
                    color: ThemeManager.textColor
                    opacity: 0.4
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 8
                }
            }

            // Divider
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: ThemeManager.textColor
                opacity: 0.1
            }
        }

        // Main Content Area
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Content Stack
            StackView {
                id: mainStack
                anchors.fill: parent
                anchors.topMargin: 0
                initialItem: timelineView
                
                pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
                pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 } }
                replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
                replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 } }
            }

            // Floating Top Bar (Dock-like)
            Rectangle {
                id: topBar
                width: Math.min(600, parent.width - 64)
                height: 52
                anchors.top: parent.top
                anchors.topMargin: 24
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 26
                color: Qt.alpha(ThemeManager.surfaceColor, 0.9)
                border.color: Qt.alpha(ThemeManager.textColor, 0.1)
                border.width: 1
                z: 100
                visible: window.currentView !== "settings"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 12
                    spacing: 12

                    // Search Icon
                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "transparent"
                        border.color: ThemeManager.textColor
                        border.width: 2
                        opacity: 0.5
                    }

                    TextField {
                        id: searchField
                        objectName: "searchField"
                        placeholderText: "Search"
                        Layout.fillWidth: true
                        background: null
                        color: ThemeManager.textColor
                        font.pixelSize: 14
                        
                        onAccepted: console.log("Searching for:", text)
                    }

                    Button {
                        objectName: "scanButton"
                        text: "Scan"
                        onClicked: FileScanner.startScan("/home/meh/Builds")
                        background: Rectangle {
                            radius: 20
                            color: parent.pressed ? Qt.alpha(ThemeManager.primaryColor, 0.3) : Qt.alpha(ThemeManager.primaryColor, 0.1)
                        }
                        contentItem: Label {
                            text: parent.text
                            color: ThemeManager.primaryColor
                            font.bold: true
                            padding: 8
                        }
                    }
                }
            }
        }
    }

    Component {
        id: timelineView
        MediaGrid {
            anchors.fill: parent
            topPadding: 100
            onOpenViewer: (data) => {
                viewerOverlay.mediaData = data
                viewerOverlay.active = true
            }
        }
    }

    Component {
        id: albumsView
        AlbumListView {
            anchors.fill: parent
            topPadding: 100
        }
    }

    Component {
        id: settingsView
        SettingsView {
            anchors.fill: parent
            topPadding: 40
        }
    }

    ViewerOverlay {
        id: viewerOverlay
    }

    Connections {
        target: FileScanner
        function onScanFinished(paths, dirsScanned, duration) {
            statusLabel.text = "Found " + paths.length + " media files"
        }
    }
}
