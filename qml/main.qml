import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QmlMaterial
import "components"
import "views"

ApplicationWindow {
    id: window
    width: 1100
    height: 800
    visible: true
    title: qsTr("Kader")

    property string currentView: "timeline"

    Component.onCompleted: {
        Theme.primaryColor = ThemeManager.primaryColor
        Theme.backgroundColor = ThemeManager.backgroundColor
        Theme.surfaceColor = ThemeManager.surfaceColor
        Theme.textColor = ThemeManager.textColor
    }

    Connections {
        target: ThemeManager
        function onThemeChanged() {
            Theme.primaryColor = ThemeManager.primaryColor
            Theme.backgroundColor = ThemeManager.backgroundColor
            Theme.surfaceColor = ThemeManager.surfaceColor
            Theme.textColor = ThemeManager.textColor
        }
    }

    background: Rectangle {
        color: Theme.backgroundColor
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.fillHeight: true
            width: 240
            color: Theme.backgroundColor
            
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
                            source: "file://" + CMAKE_SOURCE_DIR + "/assets/icon.svg"
                            sourceSize: Qt.size(32, 32)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: "Kader"
                            font.pixelSize: 24
                            font.bold: true
                            color: Theme.textColor
                        }
                    }
                }

                SidebarItem {
                    label: "Timeline"
                    active: window.currentView === "timeline"
                    onClicked: {
                        window.currentView = "timeline"
                        mainStack.replace(timelineView)
                    }
                }
                SidebarItem {
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
                    onClicked: window.currentView = "favorites"
                }
                SidebarItem {
                    label: "Trash"
                    active: window.currentView === "trash"
                    onClicked: window.currentView = "trash"
                }

                Item { Layout.fillHeight: true }

                Label {
                    id: statusLabel
                    text: "Ready"
                    font.pixelSize: 11
                    color: Theme.textColor
                    opacity: 0.6
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 8
                }
            }

            // Divider
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.textColor
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
                color: Qt.alpha(Theme.surfaceColor, 0.9)
                border.color: Qt.alpha(Theme.textColor, 0.1)
                border.width: 1
                z: 100

                // Glass effect (simple)
                layer.enabled: true
                
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
                        border.color: Theme.textColor
                        border.width: 2
                        opacity: 0.5
                    }

                    TextField {
                        id: searchField
                        placeholderText: "Search your memories..."
                        Layout.fillWidth: true
                        background: null
                        color: Theme.textColor
                        font.pixelSize: 14
                        
                        onAccepted: console.log("Searching for:", text)
                    }

                    Button {
                        text: "Scan"
                        onClicked: FileScanner.startScan("/home/meh/Builds")
                        // Style manually to fit the dock
                        background: Rectangle {
                            radius: 20
                            color: parent.pressed ? Qt.alpha(Theme.primaryColor, 0.3) : Qt.alpha(Theme.primaryColor, 0.1)
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.primaryColor
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
            // Padding to account for floating bar
            topPadding: 100
        }
    }

    Component {
        id: albumsView
        AlbumListView {
            anchors.fill: parent
            topPadding: 100
        }
    }

    Connections {
        target: FileScanner
        function onScanFinished(paths, dirsScanned, duration) {
            statusLabel.text = "Found " + paths.length + " media files"
        }
    }
}
