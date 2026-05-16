import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material as MD
import Qt.labs.platform as Platform
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

    Platform.FolderDialog {
        id: folderPicker
        title: "Choose a directory to index"
        onAccepted: {
            var path = folder.toString().replace(/^file:\/\//, "")
            DB.addIndexedDirectory(path)
            root.refreshDirs()
            FileScanner.startScan(path)
        }
    }

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

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 36; height: 36; radius: 12
                                    color: ThemeManager.surfaceContainerHighest
                                    M3Icon { anchors.centerIn: parent; name: "folder"; size: 18; color: ThemeManager.onSurfaceVariant }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2
                                    Label {
                                        width: parent.width
                                        text: modelData.path
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 13; font.weight: Font.Medium
                                        color: ThemeManager.onSurface; elide: Text.ElideRight
                                    }
                                    Row {
                                        spacing: 6
                                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: modelData.active ? ThemeManager.primary : ThemeManager.outline }
                                        Label {
                                            text: modelData.count.toLocaleString() + " items · scanned "
                                                  + (modelData.lastScan > 0 ? Qt.formatDateTime(new Date(modelData.lastScan * 1000), "dd MMM HH:mm") : "never")
                                            font.pixelSize: 12; color: ThemeManager.onSurfaceVariant
                                        }
                                    }
                                }

                                Button {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
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

                    Button {
                        width: parent.width
                        height: 56
                        flat: true
                        background: Rectangle { color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.06) : "transparent" }
                        contentItem: Row {
                            spacing: 12
                            leftPadding: 20
                            anchors.verticalCenter: parent.verticalCenter
                            M3Icon { anchors.verticalCenter: parent.verticalCenter; name: "add"; size: 20; color: ThemeManager.primary }
                            Label { anchors.verticalCenter: parent.verticalCenter; text: "Add directory & Scan"; font.pixelSize: 14; font.weight: Font.Medium; color: ThemeManager.primary }
                        }
                        onClicked: folderPicker.open()
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
                SettingsRow {
                    label: "Theme"
                    sub: ["System", "Light", "Dark"][ThemeManager.themeMode]
                    action: Row {
                        spacing: 4
                        Repeater {
                            model: ["System", "Light", "Dark"]
                            delegate: Button {
                                required property int index
                                required property string modelData
                                text: modelData
                                checkable: true
                                checked: ThemeManager.themeMode === index
                                onClicked: ThemeManager.setThemeMode(index)
                                implicitWidth: 72; implicitHeight: 34
                                background: Rectangle {
                                    radius: 17
                                    color: parent.checked ? ThemeManager.secondaryContainer : ThemeManager.surfaceContainerHighest
                                    border.color: ThemeManager.outline; border.width: 1
                                }
                                contentItem: Label {
                                    text: parent.text; font.pixelSize: 12
                                    color: parent.checked ? ThemeManager.onSecondaryContainer : ThemeManager.onSurface
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
                SettingsRow {
                    label: "Dynamic color"
                    sub: "From current cover photo"
                    action: M3Switch { checked: true }
                }
                SettingsRow {
                    id: densityRow
                    label: "Mosaic density"
                    sub: {
                        var names = ["Compact", "Comfortable", "Spacious"]
                        return names[Math.max(0, Math.min(Math.round(densitySlider.value) - 1, 2))]
                    }
                    last: true
                    action: MD.Slider {
                        id: densitySlider
                        from: 1; to: 3; stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: 2
                        width: 120
                        onValueChanged: TimelineModel.numColumns = [5, 4, 3][Math.max(0, Math.min(Math.round(value) - 1, 2))]
                    }
                }
            }

            SettingsSection {
                title: "Privacy"
                SettingsRow {
                    label: "Strip EXIF data"
                    sub: "Remove location and camera metadata"
                    last: true
                    action: Button {
                        text: "Strip metadata…"
                        onClicked: console.log("Strip EXIF")
                    }
                }
            }

            SettingsSection {
                title: "AI"
                SettingsRow {
                    label: "Face groups"
                    sub: "Automatic face detection groups similar faces across your library. Processed on-device."
                    action: M3Switch { checked: true }
                    last: true
                }
            }
        }
    }
}
