import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property real topPadding: 32

    implicitWidth: 800
    implicitHeight: 600

    property var indexedDirs: []

    function refreshDirs() {
        indexedDirs = DB.getIndexedDirectories()
    }

    Component.onCompleted: refreshDirs()

    Connections {
        target: FileScanner
        function onScanFinished(paths, dirsScanned, duration, rootPath) {
            refreshDirs()
            // Also refresh other models
            TimelineModel.refresh()
            AlbumModel.refresh()
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: settingsColumn.height + 64
        clip: true
        
        Column {
            id: settingsColumn
            width: Math.min(720, flick.width - 48)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            
            Item { width: 1; height: root.topPadding }

            // Library Section
            SettingsSection {
                title: "Library"
                
                Column {
                    width: parent.width
                    spacing: 0

                    Label {
                        text: "Indexed directories"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: ThemeManager.onSurfaceVariant
                        topPadding: 16
                        bottomPadding: 8
                        leftPadding: 20
                    }

                    Repeater {
                        model: root.indexedDirs
                        delegate: Item {
                            width: parent.width
                            height: 72
                            
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 36; height: 36; radius: 12
                                    color: ThemeManager.surfaceContainerHighest
                                    M3Icon { anchors.centerIn: parent; name: "folder"; size: 18; color: ThemeManager.onSurfaceVariant }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 150
                                    spacing: 2
                                    Label {
                                        width: parent.width
                                        text: modelData.path
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 13; font.weight: Font.Medium; color: ThemeManager.onSurface; elide: Text.ElideRight
                                    }
                                    Row {
                                        spacing: 6
                                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: modelData.active ? ThemeManager.primary : ThemeManager.outline }
                                        Label { 
                                            text: modelData.count.toLocaleString() + " items · scanned " + (modelData.lastScan > 0 ? Qt.formatDateTime(new Date(modelData.lastScan * 1000), "dd MMM HH:mm") : "never")
                                            font.pixelSize: 12; color: ThemeManager.onSurfaceVariant 
                                        }
                                    }
                                }
                                
                                Button {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 36; height: 36
                                    background: Rectangle { radius: 18; color: parent.hovered ? Qt.alpha(ThemeManager.error, 0.08) : "transparent" }
                                    contentItem: M3Icon { name: "delete"; size: 18; color: ThemeManager.error; anchors.centerIn: parent }
                                    onClicked: {
                                        DB.removeIndexedDirectory(modelData.path)
                                        root.refreshDirs()
                                    }
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 8 }

                    Button {
                        width: parent.width
                        height: 56
                        flat: true
                        background: Rectangle { color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.06) : "transparent" }
                        contentItem: Row {
                            spacing: 12
                            leftPadding: 20
                            anchors.verticalCenter: parent.verticalCenter
                            M3Icon { anchors.verticalCenter: parent; name: "add"; size: 20; color: ThemeManager.primary }
                            Label { anchors.verticalCenter: parent; text: "Add directory & Scan"; font.pixelSize: 14; font.weight: Font.Medium; color: ThemeManager.primary }
                        }
                        onClicked: {
                            var p = Settings.homePath + "/Pictures"
                            DB.addIndexedDirectory(p)
                            root.refreshDirs()
                            FileScanner.startScan(p)
                        }
                    }

                    SettingsRow {
                        label: "Auto-scan"
                        sub: "Watch indexed folders for new photos and videos"
                        action: M3Switch { checked: true }
                    }
                    SettingsRow {
                        label: "Trash retention"
                        sub: "Items are permanently deleted after this period"
                        action: ComboBox {
                            model: ["7 days", "30 days", "90 days", "Never"]
                            currentIndex: 1
                            width: 120
                        }
                        last: true
                    }
                }
            }

            SettingsSection {
                title: "Appearance"
                SettingsRow { label: "Theme"; sub: "System (dark)" }
                SettingsRow {
                    label: "Dynamic color"
                    sub: "From current cover photo"
                    action: M3Switch { checked: true }
                }
                SettingsRow { label: "Mosaic density"; sub: "Comfortable"; last: true }
            }

            SettingsSection {
                title: "Privacy"
                SettingsRow {
                    label: "Strip EXIF data"
                    sub: "Remove location and camera metadata"
                    action: Button {
                        text: "Strip metadata…"
                        onClicked: console.log("Strip EXIF")
                    }
                }
                SettingsRow { 
                    label: "Face groups"
                    action: M3Switch { checked: true }
                    last: true 
                }
            }
        }
    }
}
