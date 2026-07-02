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
                radius: ThemeManager.radiusMd
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Label {
                        text: I18n.t(Settings.language, "photos") || "Photos"
                        font.pixelSize: ThemeManager.fontLabelL
                        color: ThemeManager.onSecondaryContainer
                    }
                    Label {
                        text: StorageManager.photoCount
                        font.pixelSize: ThemeManager.fontHeadlineS
                        font.weight: Font.DemiBold
                        color: ThemeManager.onSecondaryContainer
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                color: ThemeManager.tertiaryContainer
                radius: ThemeManager.radiusMd
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Label {
                        text: I18n.t(Settings.language, "videos") || "Videos"
                        font.pixelSize: ThemeManager.fontLabelL
                        color: ThemeManager.onTertiaryContainer
                    }
                    Label {
                        text: StorageManager.videoCount
                        font.pixelSize: ThemeManager.fontHeadlineS
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
                implicitHeight: 48
                hoverEnabled: true
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
                background: Rectangle {
                    radius: ThemeManager.radiusXl
                    color: ThemeManager.secondaryContainer

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: ThemeManager.onSecondaryContainer
                        opacity: sortBtn.down ? ThemeManager.pressOpacity
                               : sortBtn.hovered ? ThemeManager.hoverOpacity : 0
                        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                    }
                }
                contentItem: Label {
                    text: sortBtn.text
                    color: ThemeManager.onSecondaryContainer
                    font.pixelSize: ThemeManager.fontLabelL
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
                implicitHeight: 48
                hoverEnabled: true
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
                background: Rectangle {
                    radius: ThemeManager.radiusXl
                    color: ThemeManager.secondaryContainer

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: ThemeManager.onSecondaryContainer
                        opacity: selectAllBtn.down ? ThemeManager.pressOpacity
                               : selectAllBtn.hovered ? ThemeManager.hoverOpacity : 0
                        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                    }
                }
                contentItem: Label {
                    text: selectAllBtn.text
                    color: ThemeManager.onSecondaryContainer
                    font.pixelSize: ThemeManager.fontLabelL
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: MediaModel.selectAll()
            }

            Button {
                id: deleteBtn
                text: I18n.t(Settings.language, "delete_selected") || "Delete Selected"
                implicitHeight: 48
                hoverEnabled: true
                leftPadding: 20; rightPadding: 20; topPadding: 10; bottomPadding: 10
                background: Rectangle {
                    radius: ThemeManager.radiusXl
                    color: ThemeManager.error

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: ThemeManager.onError
                        opacity: deleteBtn.down ? ThemeManager.pressOpacity
                               : deleteBtn.hovered ? ThemeManager.hoverOpacity : 0
                        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                    }
                }
                contentItem: Label {
                    text: deleteBtn.text
                    color: ThemeManager.onError
                    font.pixelSize: ThemeManager.fontLabelL
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
            Label { text: I18n.t(Settings.language, "k_name") || "Name"; font.pixelSize: ThemeManager.fontLabelM; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.fillWidth: true }
            Label { text: I18n.t(Settings.language, "k_date_taken") || "Date"; font.pixelSize: ThemeManager.fontLabelM; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.preferredWidth: 150 }
            Label { text: I18n.t(Settings.language, "k_size") || "Size"; font.pixelSize: ThemeManager.fontLabelM; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
            Label { text: I18n.t(Settings.language, "k_type") || "Format"; font.pixelSize: ThemeManager.fontLabelM; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant; Layout.preferredWidth: 100 }
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
                id: rowItem
                width: ListView.view.width
                height: 60

                // path (role) is "file://"-prefixed; the reveal-in-folder API
                // (like ViewerOverlay's folder button) wants a plain local path.
                readonly property string _rawPath: path ? path.toString().replace("file://", "") : ""

                Rectangle {
                    id: rowBg
                    anchors.fill: parent
                    color: isSelected ? ThemeManager.secondaryContainer : "transparent"
                    radius: ThemeManager.radiusSm

                    // Declarative state-layer overlay (bound, not imperative) — hover
                    // only shows on unselected rows since selected rows already have
                    // a container fill.
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: ThemeManager.onSurface
                        opacity: (!isSelected && rowMa.containsMouse) ? ThemeManager.hoverOpacity : 0
                        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) rowMenu.popup()
                            else isSelected = !isSelected
                        }
                    }
                }

                M3Menu {
                    id: rowMenu
                    M3MenuItem {
                        text: I18n.t(Settings.language, "ctx_open_folder")
                        onTriggered: if (rowItem._rawPath) Settings.revealInFolder(rowItem._rawPath)
                    }
                    M3MenuItem {
                        text: isFavorite ? "Unfavorite" : "Favorite"
                        onTriggered: { if (model.id) { DB.toggleFavorite(model.id); root.reload() } }
                    }
                    M3MenuItem {
                        text: I18n.t(Settings.language, "tip_hide")
                        onTriggered: {
                            if (model.id) {
                                DB.setHidden(model.id, true)
                                MediaModel.removeByPath(path)
                            }
                        }
                    }
                    M3MenuItem {
                        text: I18n.t(Settings.language, "ctx_add_ignored")
                        onTriggered: {
                            if (model.id) {
                                DB.setIgnored(model.id, true)
                                if (Settings.hideIgnoredInTimeline) MediaModel.removeByPath(path)
                            }
                        }
                    }
                    M3MenuItem {
                        text: I18n.t(Settings.language, "tip_move_trash")
                        onTriggered: {
                            if (path) {
                                DB.trashMedia(path)
                                MediaModel.removeByPath(path)
                            }
                        }
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
                        radius: ThemeManager.radiusXs
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
                        font.pixelSize: ThemeManager.fontLabelL
                        color: ThemeManager.onSurface
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: formatDate(date)
                        font.pixelSize: ThemeManager.fontLabelL
                        color: ThemeManager.onSurfaceVariant
                        Layout.preferredWidth: 150
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: formatSize(fileSize)
                        font.pixelSize: ThemeManager.fontLabelL
                        color: ThemeManager.onSurfaceVariant
                        Layout.preferredWidth: 80
                        horizontalAlignment: Text.AlignRight
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: mimeType ? mimeType.split('/').pop().toUpperCase() : "UNKNOWN"
                        font.pixelSize: ThemeManager.fontLabelL
                        color: ThemeManager.onSurfaceVariant
                        Layout.preferredWidth: 100
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        Layout.alignment: Qt.AlignVCenter

                        MaterialSymbol {
                            anchors.centerIn: parent
                            name: "delete"
                            size: 22
                            color: ThemeManager.onSurfaceVariant
                        }
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
