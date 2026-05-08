import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    property bool collapsed: false
    property string currentView: "timeline"
    signal viewChanged(string view)

    width: collapsed ? 84 : 280
    
    Behavior on width {
        NumberAnimation {
            duration: ThemeManager.durMed
            easing.type: Easing.OutQuint
        }
    }

    // Sidebar Background
    Rectangle {
        anchors.fill: parent
        color: ThemeManager.surfaceContainer
        radius: 28
        
        // Flatten the left side
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 28
            color: parent.color
            visible: true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 0

        // Brand Block
        Item {
            Layout.fillWidth: true
            height: 64
            Layout.topMargin: 12
            Layout.leftMargin: root.collapsed ? 0 : 16

            RowLayout {
                anchors.centerIn: root.collapsed ? parent : undefined
                anchors.left: root.collapsed ? undefined : parent.left
                spacing: 12

                Rectangle {
                    width: 32
                    height: 32
                    radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#6750A4" }
                        GradientStop { position: 1.0; color: "#7D5260" }
                    }
                }

                Column {
                    visible: !root.collapsed
                    Label {
                        text: "Kader"
                        font.family: "Roboto Flex"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: ThemeManager.onSurface
                    }
                    Label {
                        text: "Gallery"
                        font.pixelSize: 12
                        color: ThemeManager.onSurfaceVariant
                    }
                }
            }
        }

        Item { height: 16 }

        // Library Section
        Label {
            text: "Library"
            visible: !root.collapsed
            font.pixelSize: 11
            font.weight: Font.Medium
            color: ThemeManager.onSurfaceVariant
            Layout.leftMargin: 16
            Layout.topMargin: 18
            Layout.bottomMargin: 8
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            SidebarItem {
                icon: "schedule"
                label: "Timeline"
                active: root.currentView === "timeline"
                collapsed: root.collapsed
                onClicked: root.viewChanged("timeline")
            }
            SidebarItem {
                icon: "folder"
                label: "Albums"
                active: root.currentView === "albums"
                collapsed: root.collapsed
                onClicked: root.viewChanged("albums")
            }
            SidebarItem {
                icon: "map"
                label: "Map"
                active: root.currentView === "map"
                collapsed: root.collapsed
                onClicked: root.viewChanged("map")
            }
        }

        // Smart Views
        Label {
            text: "Smart views"
            visible: !root.collapsed
            font.pixelSize: 11
            font.weight: Font.Medium
            color: ThemeManager.onSurfaceVariant
            Layout.leftMargin: 16
            Layout.topMargin: 18
            Layout.bottomMargin: 8
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            SidebarItem {
                icon: "favorite"
                label: "Favorites"
                active: root.currentView === "favorites"
                collapsed: root.collapsed
                onClicked: root.viewChanged("favorites")
            }
            SidebarItem {
                icon: "delete"
                label: "Trash"
                active: root.currentView === "trash"
                collapsed: root.collapsed
                onClicked: root.viewChanged("trash")
            }
        }

        Item { Layout.fillHeight: true }

        // Storage Card placeholder
        Item {
            Layout.fillWidth: true
            height: root.collapsed ? 120 : 80
            Layout.margins: 4
            
            Rectangle {
                anchors.fill: parent
                color: ThemeManager.surfaceContainerLow
                radius: 16
                visible: !root.collapsed
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    RowLayout {
                        spacing: 8
                        Rectangle { width: 18; height: 18; color: "transparent" } // Icon
                        Label { text: "This PC"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeManager.onSurface }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: ThemeManager.surfaceContainerHighest
                        Rectangle {
                            width: parent.width * 0.6
                            height: parent.height
                            radius: 3
                            color: ThemeManager.primary
                        }
                    }
                    RowLayout {
                        Label { text: "184.6 GB media"; font.pixelSize: 11; color: ThemeManager.onSurfaceVariant }
                        Item { Layout.fillWidth: true }
                        Label { text: "1.8 TB total"; font.pixelSize: 11; color: ThemeManager.onSurfaceVariant }
                    }
                }
            }

            // Vertical storage card for collapsed
            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                color: ThemeManager.surfaceContainerLow
                radius: 22
                visible: root.collapsed
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle { width: 18; height: 18; color: "transparent" }
                    Rectangle {
                        width: 8
                        height: 60
                        radius: 4
                        color: ThemeManager.surfaceContainerHighest
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * 0.4
                            radius: 4
                            color: ThemeManager.primary
                        }
                    }
                    Label { text: "62%"; font.pixelSize: 10; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant }
                }
            }
        }

        // Settings
        SidebarItem {
            icon: "settings"
            label: "Settings"
            active: root.currentView === "settings"
            collapsed: root.collapsed
            onClicked: root.viewChanged("settings")
            Layout.topMargin: 8
        }
    }
}
