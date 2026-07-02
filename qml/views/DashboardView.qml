import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../components"
import "../I18n.js" as I18n

Item {
    id: root
    anchors.fill: parent

    // Current sort: field 0=Name 1=Date 2=Size 3=Format. Default newest-first.
    property int  sortKey: 1
    property bool sortAsc: false

    // Reload the flat list from the DB and (re)apply the active sort.
    function reload() {
        MediaModel.refresh(Settings.hideIgnoredInTimeline)
        MediaModel.sortBy(sortKey, sortAsc)
    }

    // Populate the list when the dashboard appears (and on reopen).
    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()

    function formatSize(bytes) {
        if (bytes === 0) return "0 B"
        let k = 1024, dm = 2, sizes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"],
            i = Math.floor(Math.log(bytes) / Math.log(k))
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + " " + sizes[i]
    }

    function formatDate(ts) {
        return new Date(ts * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        // Top Cards
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: ThemeManager.secondaryContainer
                radius: 12
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Label {
                        text: I18n.t(Settings.language, "photos") || "Photos"
                        font.pixelSize: 14
                        color: ThemeManager.onSecondaryContainer
                    }
                    Label {
                        text: StorageManager.photoCount
                        font.pixelSize: 32
                        font.weight: Font.DemiBold
                        color: ThemeManager.onSecondaryContainer
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: ThemeManager.tertiaryContainer
                radius: 12
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Label {
                        text: I18n.t(Settings.language, "videos") || "Videos"
                        font.pixelSize: 14
                        color: ThemeManager.onTertiaryContainer
                    }
                    Label {
                        text: StorageManager.videoCount
                        font.pixelSize: 32
                        font.weight: Font.DemiBold
                        color: ThemeManager.onTertiaryContainer
                    }
                }
            }
        }

        // Toolbar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                id: sortBtn
                text: I18n.t(Settings.language, "sort_by") || "Sort"
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
                background: Rectangle {
                    radius: 20
                    color: sortBtn.down ? Qt.darker(ThemeManager.secondaryContainer, 1.1)
                                        : ThemeManager.secondaryContainer
                }
                contentItem: Label {
                    text: sortBtn.text
                    color: ThemeManager.onSecondaryContainer
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: sortMenu.popup(sortBtn, 0, sortBtn.height + 4)
                SortMenu {
                    id: sortMenu
                    fields: [
                        { key: 0, label: I18n.t(Settings.language, "k_name") || "Name" },
                        { key: 1, label: I18n.t(Settings.language, "k_date_taken") || "Date" },
                        { key: 2, label: I18n.t(Settings.language, "k_size") || "Size" },
                        { key: 3, label: I18n.t(Settings.language, "k_type") || "Format" }
                    ]
                    currentKey: root.sortKey
                    ascending:  root.sortAsc
                    onPick: (key) => { root.sortKey = key; MediaModel.sortBy(key, root.sortAsc) }
                    onOrderPicked: (asc) => { root.sortAsc = asc; MediaModel.sortBy(root.sortKey, asc) }
                }
            }

            Item { Layout.fillWidth: true } // Spacer

            Button {
                id: selectAllBtn
                text: I18n.t(Settings.language, "select_all") || "Select All"
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
                background: Rectangle {
                    radius: 20
                    color: selectAllBtn.down ? Qt.darker(ThemeManager.secondaryContainer, 1.1)
                                             : ThemeManager.secondaryContainer
                }
                contentItem: Label {
                    text: selectAllBtn.text
                    color: ThemeManager.onSecondaryContainer
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: MediaModel.selectAll()
            }

            Button {
                id: deleteBtn
                text: I18n.t(Settings.language, "delete_selected") || "Delete Selected"
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
                background: Rectangle {
                    radius: 20
                    color: deleteBtn.down ? Qt.darker(ThemeManager.error, 1.1) : ThemeManager.error
                }
                contentItem: Label {
                    text: deleteBtn.text
                    color: ThemeManager.onError
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    let paths = MediaModel.getSelectedPaths()
                    for (let i = 0; i < paths.length; i++) {
                        DB.trashMedia(paths[i])
                    }
                    MediaModel.removeSelected()
                }
            }
        }

        // List Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Item { Layout.preferredWidth: 40; Layout.preferredHeight: 20 } // Checkbox space
            Item { Layout.preferredWidth: 60; Layout.preferredHeight: 20 } // Thumb
            Label { text: I18n.t(Settings.language, "k_name") || "Name"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.fillWidth: true }
            Label { text: I18n.t(Settings.language, "k_date_taken") || "Date"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.preferredWidth: 150 }
            Label { text: I18n.t(Settings.language, "k_size") || "Size"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
            Label { text: I18n.t(Settings.language, "k_type") || "Format"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.preferredWidth: 100 }
            Item { Layout.preferredWidth: 40; Layout.preferredHeight: 20 } // Action space
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: -16; height: 1; color: ThemeManager.outlineVariant }

        // List
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: MediaModel
            spacing: 8

            delegate: Item {
                width: ListView.view.width
                height: 60

                Rectangle {
                    anchors.fill: parent
                    color: isSelected ? ThemeManager.secondaryContainer : "transparent"
                    radius: 8
                    
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.color = isSelected ? ThemeManager.secondaryContainer : ThemeManager.surfaceContainerHigh
                        onExited: parent.color = isSelected ? ThemeManager.secondaryContainer : "transparent"
                        onClicked: isSelected = !isSelected
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 16

                    M3CheckBox {
                        checked: isSelected
                        onToggled: (v) => isSelected = v
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 4
                        color: ThemeManager.surfaceVariant
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: thumb ? thumb : "image://thumbnail/" + path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    Label {
                        text: path.split('/').pop()
                        font.pixelSize: 13
                        color: ThemeManager.onSurface
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: formatDate(date)
                        font.pixelSize: 13
                        color: ThemeManager.onSurfaceVariant
                        Layout.preferredWidth: 150
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: formatSize(fileSize)
                        font.pixelSize: 13
                        color: ThemeManager.onSurfaceVariant
                        Layout.preferredWidth: 80
                        horizontalAlignment: Text.AlignRight
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: mimeType ? mimeType.split('/').pop().toUpperCase() : "UNKNOWN"
                        font.pixelSize: 13
                        color: ThemeManager.onSurfaceVariant
                        Layout.preferredWidth: 100
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MaterialSymbol {
                        name: "delete"
                        size: 22
                        color: ThemeManager.onSurfaceVariant
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                DB.trashMedia(path)
                                MediaModel.removeByPath(path)
                            }
                        }
                    }
                }
            }
        }
    }
}
