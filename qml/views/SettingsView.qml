import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property alias topPadding: content.topMargin

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content
            width: Math.min(720, scroll.width - 48)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24
            Layout.topMargin: 8

            // Library Section
            SettingsSection {
                title: "Library"
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: "Indexed directories"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: ThemeManager.onSurfaceVariant
                        Layout.margins: 16
                        Layout.leftMargin: 20
                    }

                    // Mock Indexed Directories (we'll connect to real data later)
                    Repeater {
                        model: [
                            { path: "/home/meh/Pictures/Camera Roll", count: 4218, lastScan: "2 min ago", active: true },
                            { path: "/mnt/Storage/Photos", count: 1842, lastScan: "yesterday", active: true }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            color: "transparent"
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    width: 36; height: 36; radius: 12
                                    color: ThemeManager.surfaceContainerHighest
                                    M3Icon {
                                        anchors.centerIn: parent
                                        name: "folder" // Should be scan_folder
                                        size: 18; color: ThemeManager.onSurfaceVariant
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label {
                                        text: modelData.path
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        color: ThemeManager.onSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    RowLayout {
                                        spacing: 6
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: modelData.active ? ThemeManager.primary : ThemeManager.outline
                                        }
                                        Label {
                                            text: modelData.count.toLocaleString() + " items · scanned " + modelData.lastScan
                                            font.pixelSize: 12; color: ThemeManager.onSurfaceVariant
                                        }
                                    }
                                }

                                Control {
                                    width: 36; height: 36
                                    background: Rectangle { radius: 18; color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent" }
                                    contentItem: M3Icon { name: "settings"; size: 18; color: ThemeManager.onSurfaceVariant; anchors.centerIn: parent }
                                }
                                Control {
                                    width: 36; height: 36
                                    background: Rectangle { radius: 18; color: parent.hovered ? Qt.alpha(ThemeManager.error, 0.08) : "transparent" }
                                    contentItem: M3Icon { name: "delete"; size: 18; color: ThemeManager.error; anchors.centerIn: parent }
                                }
                            }
                            
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1
                                color: ThemeManager.outlineVariant
                                opacity: 0.5
                            }
                        }
                    }

                    // Add Directory Button
                    Button {
                        Layout.fillWidth: true
                        height: 56
                        flat: true
                        contentItem: RowLayout {
                            spacing: 12
                            M3Icon { name: "add"; size: 20; color: ThemeManager.primary; Layout.leftMargin: 20 }
                            Label { text: "Add directory"; font.pixelSize: 14; font.weight: Font.Medium; color: ThemeManager.primary }
                        }
                        background: Rectangle {
                            color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.06) : "transparent"
                        }
                    }

                    SettingsRow {
                        label: "Auto-scan"
                        sub: "Watch indexed folders for new photos and videos"
                        action: Switch { checked: true }
                    }
                    SettingsRow {
                        label: "Trash retention"
                        sub: "30 days"
                        last: true
                    }
                }
            }

            // Appearance Section
            SettingsSection {
                title: "Appearance"
                SettingsRow { label: "Theme"; sub: "System (dark)" }
                SettingsRow {
                    label: "Dynamic color from cover photo"
                    action: Switch { checked: true }
                }
                SettingsRow { label: "Mosaic density"; sub: "Comfortable"; last: true }
            }

            // Privacy Section
            SettingsSection {
                title: "Privacy"
                SettingsRow {
                    label: "Strip EXIF data"
                    sub: "Remove location, camera and timestamp metadata from all photos"
                    action: Button {
                        text: "Strip metadata…"
                        font.pixelSize: 14; font.weight: Font.Medium
                        background: Rectangle {
                            radius: 20
                            border.color: ThemeManager.outline
                            color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.08) : "transparent"
                        }
                        contentItem: Label {
                            text: parent.text; color: ThemeManager.primary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 16; rightPadding: 16
                        }
                    }
                }
                SettingsRow {
                    label: "Face groups"
                    sub: "On-device only"
                    action: Switch { checked: true }
                }
                SettingsRow { label: "Hidden folder"; sub: "Require system password to view"; last: true }
            }
        }
    }

    // Helper components
    Component {
        id: sectionComp
        ColumnLayout {
            property string title: ""
            Layout.fillWidth: true
            spacing: 0
            Label {
                text: title
                font.family: "Roboto Flex"
                font.pixelSize: 18
                font.weight: Font.Medium
                color: ThemeManager.onSurface
                Layout.margins: 4
                Layout.bottomMargin: 12
            }
            Rectangle {
                id: sectionRect
                Layout.fillWidth: true
                radius: 16
                color: ThemeManager.surfaceContainer
                clip: true
                // Children will go here
            }
        }
    }
}
