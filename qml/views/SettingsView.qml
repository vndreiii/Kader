import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property real topPadding: 32

    implicitWidth: 800
    implicitHeight: 600

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
                        model: [
                            { path: Settings.homePath + "/Pictures", count: 0, lastScan: "never", active: true }
                        ]
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
                                        Label { text: modelData.count.toLocaleString() + " items · scanned " + modelData.lastScan; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                                    }
                                }
                            }
                        }
                    }

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
                            FileScanner.startScan(Settings.homePath + "/Pictures")
                        }
                    }

                    SettingsRow {
                        label: "Auto-scan"
                        sub: "Watch indexed folders for new photos and videos"
                        action: M3Switch { checked: true }
                    }
                    SettingsRow {
                        label: "Trash retention"
                        sub: "30 days"
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
