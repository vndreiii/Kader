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

                            TextField {
                                id: searchField
                                objectName: "searchField"
                                Layout.fillWidth: true
                                placeholderText: "Search photos and albums"
                                background: null
                                color: ThemeManager.onSurface
                                font.pixelSize: 16
                                verticalAlignment: TextInput.AlignVCenter
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
            onOpenViewer: (data) => {
                viewerOverlay.mediaData = data
                viewerOverlay.active = true
            }
        }
    }

    Component {
        id: albumsView
        AlbumListView {}
    }

    Component {
        id: mapView
        MapView {}
    }

    Component {
        id: settingsView
        SettingsView {}
    }

    ViewerOverlay {
        id: viewerOverlay
    }

    ExifModal {
        id: exifModal
        onConfirmed: console.log("EXIF stripped")
        onClosed: active = false
    }
}
