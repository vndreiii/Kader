import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import "../components"
import "../I18n.js" as I18n
import "../Paths.js" as Paths

// Storage dashboard: where the space goes (disk overview, folders, years,
// file types) and where to win it back (largest files, likely duplicates,
// trash).
Item {
    id: root
    anchors.fill: parent

    function _t(k) { return I18n.t(Settings.language, k) }

    function formatSize(bytes) {
        bytes = Number(bytes) || 0
        if (bytes < 1024) return bytes + " B"
        var units = ["KB", "MB", "GB", "TB"], v = bytes / 1024, i = 0
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
        return (v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2)) + " " + units[i]
    }

    // ── data ────────────────────────────────────────────────────────────
    property var ov: ({})
    property var folders: []
    property var years: []
    property var types: []
    property var largest: []
    property var dups: []
    property var trash: []
    property bool _loading: true
    property int tab: 0            // 0 largest, 1 duplicates, 2 trash
    property var selected: ({})
    readonly property int selCount: Object.keys(selected).length

    function reload() {
        StorageManager.refresh()
        ov = StorageManager.overview()
        folders = StorageManager.byFolder(8)
        years = StorageManager.byYear()
        types = StorageManager.byType()
        largest = StorageManager.largest(60)
        dups = StorageManager.duplicates(40)
        trash = StorageManager.trashItems(200)
        selected = ({})
        _loading = false
    }
    function scheduleReload() { _loading = true; reloadTimer.restart() }
    Timer { id: reloadTimer; interval: 32; onTriggered: root.reload() }
    Component.onCompleted: scheduleReload()
    onVisibleChanged: if (visible) scheduleReload()

    function toggle(item) {
        var s = Object.assign({}, selected)
        if (s[item.id]) delete s[item.id]; else s[item.id] = item
        selected = s
    }
    function afterChange() {
        TimelineModel.refresh()
        AlbumModel.refresh()
        reload()
    }

    readonly property var segments: [
        { k: "photos", c: ThemeManager.primary,          t: _t("photos_title") },
        { k: "videos", c: ThemeManager.tertiary,         t: _t("videos") },
        { k: "raw",    c: ThemeManager.secondary,        t: "RAW" },
        { k: "trash",  c: ThemeManager.error,            t: _t("trash") },
        { k: "other",  c: ThemeManager.outline,          t: _t("storage_other") },
        { k: "free",   c: ThemeManager.surfaceContainerHighest, t: _t("storage_free") }
    ]
    readonly property real libraryBytes: (ov.photos || 0) + (ov.videos || 0) + (ov.raw || 0)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: col
            x: 32
            width: flick.width - 64
            spacing: 20

            // ── header ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 28
                ColumnLayout {
                    spacing: 2
                    Label { text: root._t("storage_title"); font.pixelSize: 30; color: ThemeManager.onSurface }
                    Label {
                        text: root.ov.disk && root.ov.disk !== "/" ? root._t("storage_on_disk").arg(root.ov.disk) : ""
                        visible: text.length > 0
                        font.pixelSize: 13
                        color: ThemeManager.onSurfaceVariant
                    }
                }
                Item { Layout.fillWidth: true }
                M3Button { kind: "tonal"; text: root._t("refresh"); onClicked: root.scheduleReload() }
            }

            // ── disk overview ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ovCol.implicitHeight + 48
                radius: 28
                color: ThemeManager.surfaceContainerLow
                ColumnLayout {
                    id: ovCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 16
                    RowLayout {
                        spacing: 10
                        Label {
                            text: root._loading ? "–" : root.formatSize(root.libraryBytes)
                            font.pixelSize: 44
                            font.weight: Font.Medium
                            color: ThemeManager.onSurface
                        }
                        Label {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 8
                            text: root._t("storage_library_of").arg(root.formatSize(root.ov.total || 0))
                            font.pixelSize: 15
                            color: ThemeManager.onSurfaceVariant
                        }
                    }
                    // segmented bar (M3 Expressive: rounded segments with gaps)
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        Skeleton { anchors.fill: parent; radius: 11; visible: root._loading }
                        Row {
                            id: bar
                            anchors.fill: parent
                            spacing: 3
                            visible: !root._loading
                            readonly property real total: Math.max(1, root.ov.total || 1)
                            Repeater {
                                model: root.segments
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property real v: root.ov[modelData.k] || 0
                                    visible: v > 0
                                    height: bar.height
                                    // tiny shares stay visible as a sliver
                                    width: Math.max(6, (bar.width - 3 * 5) * v / bar.total)
                                    radius: 6
                                    topLeftRadius: index === 0 ? 11 : 6
                                    bottomLeftRadius: index === 0 ? 11 : 6
                                    topRightRadius: modelData.k === "free" ? 11 : 6
                                    bottomRightRadius: modelData.k === "free" ? 11 : 6
                                    color: modelData.c
                                    ToolTip.visible: segMa.containsMouse
                                    ToolTip.text: modelData.t + " · " + root.formatSize(v)
                                    MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true }
                                }
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 18
                        Repeater {
                            model: root.segments
                            Row {
                                required property var modelData
                                spacing: 8
                                visible: (root.ov[modelData.k] || 0) > 0
                                Rectangle { width: 12; height: 12; radius: 6; color: modelData.c; anchors.verticalCenter: parent.verticalCenter
                                            border.width: modelData.k === "free" ? 1 : 0; border.color: ThemeManager.outline }
                                Label { text: modelData.t; color: ThemeManager.onSurface; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                                Label { text: root.formatSize(root.ov[modelData.k] || 0); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }

            // ── stat cards ──────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: width > 900 ? 4 : 2
                columnSpacing: 12
                rowSpacing: 12
                Repeater {
                    model: [
                        { icon: "photo_library", t: root._t("photos_title"), n: StorageManager.photoCount, b: (root.ov.photos || 0) + (root.ov.raw || 0), c: ThemeManager.primaryContainer, f: ThemeManager.onPrimaryContainer },
                        { icon: "videocam",      t: root._t("videos"),       n: StorageManager.videoCount, b: root.ov.videos || 0, c: ThemeManager.tertiaryContainer, f: ThemeManager.onTertiaryContainer },
                        { icon: "raw_on",        t: "RAW",                   n: -1, b: root.ov.raw || 0, c: ThemeManager.secondaryContainer, f: ThemeManager.onSecondaryContainer },
                        { icon: "delete",        t: root._t("trash"),        n: root.trash.length, b: root.ov.trash || 0, c: ThemeManager.errorContainer, f: ThemeManager.onErrorContainer }
                    ]
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 112
                        radius: 24
                        color: modelData.c
                        ColumnLayout {
                            anchors { fill: parent; margins: 18 }
                            spacing: 4
                            RowLayout {
                                MaterialSymbol { name: modelData.icon; size: 22; color: modelData.f }
                                Label { text: modelData.t; color: modelData.f; font.pixelSize: 14; font.weight: Font.Medium }
                            }
                            Item { Layout.fillHeight: true }
                            Label { text: root._loading ? "–" : root.formatSize(modelData.b); color: modelData.f; font.pixelSize: 24; font.weight: Font.Medium }
                            Label {
                                visible: modelData.n >= 0
                                text: root._t("n_items").arg(modelData.n)
                                color: modelData.f; opacity: 0.8; font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // ── breakdowns ──────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: width > 900 ? 2 : 1
                columnSpacing: 12
                rowSpacing: 12

                // folders
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: fCol.implicitHeight + 40
                    radius: 24
                    color: ThemeManager.surfaceContainerLow
                    ColumnLayout {
                        id: fCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                        spacing: 12
                        Label { text: root._t("storage_by_folder"); font.pixelSize: 18; font.weight: Font.Medium; color: ThemeManager.onSurface }
                        Repeater {
                            model: root.folders
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { Layout.fillWidth: true; text: modelData.name || modelData.folder; elide: Text.ElideMiddle; color: ThemeManager.onSurface; font.pixelSize: 14 }
                                    Label { text: root.formatSize(modelData.bytes) + " · " + modelData.count; color: ThemeManager.onSurfaceVariant; font.pixelSize: 12 }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8; radius: 4
                                    color: ThemeManager.surfaceContainerHighest
                                    Rectangle {
                                        height: parent.height; radius: 4
                                        width: parent.width * modelData.bytes / Math.max(1, root.folders[0].bytes)
                                        color: ThemeManager.primary
                                    }
                                }
                            }
                        }
                    }
                }

                // years + types
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: yCol.implicitHeight + 40
                    radius: 24
                    color: ThemeManager.surfaceContainerLow
                    ColumnLayout {
                        id: yCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                        spacing: 12
                        Label { text: root._t("storage_by_year"); font.pixelSize: 18; font.weight: Font.Medium; color: ThemeManager.onSurface }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 150
                            readonly property real maxB: root.years.reduce((m, y) => Math.max(m, y.bytes), 1)
                            Row {
                                id: yearBars
                                anchors.fill: parent
                                spacing: 6
                                Repeater {
                                    model: root.years
                                    Item {
                                        required property var modelData
                                        width: Math.max(14, (yearBars.width - yearBars.spacing * (root.years.length - 1)) / Math.max(1, root.years.length))
                                        height: yearBars.height
                                        Rectangle {
                                            anchors { bottom: yLbl.top; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                                            width: Math.min(40, parent.width)
                                            height: Math.max(4, (parent.height - 24) * modelData.bytes / parent.parent.parent.maxB)
                                            radius: Math.min(10, width / 2)
                                            color: yHov.containsMouse ? ThemeManager.primary : Qt.alpha(ThemeManager.primary, 0.65)
                                            MouseArea { id: yHov; anchors.fill: parent; hoverEnabled: true }
                                            ToolTip.visible: yHov.containsMouse
                                            ToolTip.text: modelData.year + " · " + root.formatSize(modelData.bytes) + " · " + root._t("n_items").arg(modelData.count)
                                        }
                                        Label {
                                            id: yLbl
                                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                            text: String(modelData.year).slice(root.years.length > 8 ? 2 : 0)
                                            font.pixelSize: 11
                                            color: ThemeManager.onSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }
                        Label { text: root._t("storage_by_type"); font.pixelSize: 18; font.weight: Font.Medium; color: ThemeManager.onSurface; Layout.topMargin: 8 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: root.types
                                Rectangle {
                                    required property var modelData
                                    height: 32
                                    width: tRow.implicitWidth + 24
                                    radius: 10
                                    color: modelData.raw ? ThemeManager.secondaryContainer : ThemeManager.surfaceContainerHighest
                                    Row {
                                        id: tRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Label { text: (modelData.ext || "?").toUpperCase(); font.pixelSize: 12; font.weight: Font.Bold; color: ThemeManager.onSurface }
                                        Label { text: root.formatSize(modelData.bytes); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── free up space ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: freeCol.implicitHeight + 40
                radius: 28
                color: ThemeManager.surfaceContainerLow
                ColumnLayout {
                    id: freeCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 14
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: root._t("storage_free_up"); font.pixelSize: 18; font.weight: Font.Medium; color: ThemeManager.onSurface }
                        Item { Layout.fillWidth: true }
                        // segmented tabs
                        Row {
                            spacing: 2
                            Repeater {
                                model: [root._t("storage_largest"), root._t("storage_duplicates").arg(root.dups.length), root._t("trash") + " · " + root.trash.length]
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool on: root.tab === index
                                    height: 40
                                    width: tabTxt.implicitWidth + (on ? 44 : 28)
                                    topLeftRadius: index === 0 ? 20 : 6; bottomLeftRadius: index === 0 ? 20 : 6
                                    topRightRadius: index === 2 ? 20 : 6; bottomRightRadius: index === 2 ? 20 : 6
                                    color: on ? ThemeManager.secondaryContainer : ThemeManager.surfaceContainerHighest
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol { visible: parent.parent.on; name: "check"; size: 16; color: ThemeManager.onSecondaryContainer; anchors.verticalCenter: parent.verticalCenter }
                                        Label { id: tabTxt; text: modelData; font.pixelSize: 13; font.weight: Font.Medium
                                                color: parent.parent.on ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                                                anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.tab = index; root.selected = ({}) } }
                                }
                            }
                        }
                    }

                    // actions for the current tab
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.selCount > 0 || root.tab === 2
                        Label {
                            Layout.fillWidth: true
                            text: root.selCount > 0 ? root._t("storage_selected").arg(root.selCount) : ""
                            color: ThemeManager.onSurfaceVariant
                        }
                        M3Button {
                            visible: root.selCount > 0 && root.tab !== 2
                            kind: "filled"
                            text: root._t("move_to_trash")
                            onClicked: {
                                for (var id in root.selected) DB.setTrashed(parseInt(id), true)
                                root.afterChange()
                            }
                        }
                        M3Button {
                            visible: root.selCount > 0 && root.tab === 2
                            kind: "tonal"
                            text: root._t("restore")
                            onClicked: {
                                for (var id in root.selected) DB.setTrashed(parseInt(id), false)
                                root.afterChange()
                            }
                        }
                        M3Button {
                            visible: root.tab === 2 && root.trash.length > 0
                            kind: "filled"
                            text: root._t("empty_trash_now").arg(root.formatSize(root.ov.trash || 0))
                            onClicked: emptyConfirm.open()
                        }
                    }

                    Label {
                        visible: !root._loading && (root.tab === 0 ? root.largest.length === 0
                                                  : root.tab === 1 ? root.dups.length === 0 : root.trash.length === 0)
                        text: root.tab === 1 ? root._t("storage_no_dups") : root.tab === 2 ? root._t("storage_trash_empty") : ""
                        color: ThemeManager.onSurfaceVariant
                    }

                    // rows: files (largest / trash) or duplicate groups
                    Column {
                        Layout.fillWidth: true
                        spacing: 2
                        Repeater {
                            model: root._loading ? 6 : (root.tab === 0 ? root.largest : root.tab === 2 ? root.trash : [])
                            delegate: FileRow {
                                required property var modelData
                                width: parent.width
                                item: root._loading ? null : modelData
                            }
                        }
                        Repeater {
                            model: root.tab === 1 && !root._loading ? root.dups : []
                            delegate: Column {
                                required property var modelData
                                width: parent.width
                                spacing: 2
                                Label {
                                    text: modelData.name + "  ·  " + root._t("storage_wasted").arg(root.formatSize(modelData.wasted))
                                    color: ThemeManager.onSurfaceVariant
                                    font.pixelSize: 12
                                    topPadding: 10; bottomPadding: 4; leftPadding: 4
                                }
                                Repeater {
                                    model: modelData.copies
                                    delegate: FileRow {
                                        required property var modelData
                                        required property int index
                                        width: parent.width
                                        item: modelData
                                        note: index === 0 ? root._t("storage_original") : ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // one file: thumbnail, name, folder, date, size, selection
    component FileRow: Rectangle {
        id: fr
        property var item: null
        property string note: ""
        readonly property bool sel: item !== null && !!root.selected[item.id]
        height: 64
        radius: 14
        color: sel ? ThemeManager.secondaryContainer : frMa.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.05) : ThemeManager.surfaceContainer
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 14 }
            spacing: 12
            Item {
                Layout.preferredWidth: 46; Layout.preferredHeight: 46
                Rectangle { id: fmask; anchors.fill: parent; radius: 12; visible: false; layer.enabled: true }
                Skeleton { anchors.fill: parent; radius: 12; visible: !fr.item || fImg.status !== Image.Ready; active: visible }
                Image { id: fImg; anchors.fill: parent; source: fr.item ? fr.item.thumb : ""; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: false }
                MultiEffect { anchors.fill: parent; source: fImg; visible: fImg.status === Image.Ready; maskEnabled: true; maskSource: fmask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: fr.item ? Paths.fileName(fr.item.file_path) : ""
                    elide: Text.ElideMiddle
                    color: ThemeManager.onSurface
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Label {
                    Layout.fillWidth: true
                    text: fr.item ? (fr.note ? fr.note + " · " : "") + String(fr.item.folder_path || "")
                                  + (fr.item.creation_date ? " · " + Qt.formatDate(new Date(fr.item.creation_date * 1000), "d MMM yyyy") : "") : ""
                    elide: Text.ElideMiddle
                    color: ThemeManager.onSurfaceVariant
                    font.pixelSize: 12
                }
            }
            Label { text: fr.item ? root.formatSize(fr.item.file_size) : ""; color: ThemeManager.onSurface; font.pixelSize: 14; font.weight: Font.Medium }
            RoundButton {
                flat: true
                visible: fr.item !== null
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                contentItem: MaterialSymbol { name: "folder_open"; size: 20; color: ThemeManager.onSurfaceVariant }
                onClicked: DB.revealInFolder(fr.item.file_path)
                ToolTip.visible: hovered; ToolTip.text: root._t("show_in_folder")
            }
            Rectangle {
                width: 22; height: 22; radius: 6
                visible: fr.item !== null
                color: fr.sel ? ThemeManager.primary : "transparent"
                border.width: fr.sel ? 0 : 2
                border.color: ThemeManager.outline
                MaterialSymbol { anchors.centerIn: parent; visible: fr.sel; name: "check"; size: 16; color: ThemeManager.onPrimary }
            }
        }
        MouseArea {
            id: frMa
            anchors.fill: parent
            anchors.rightMargin: 90
            hoverEnabled: true
            enabled: fr.item !== null
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle(fr.item)
        }
    }

    Popup {
        id: emptyConfirm
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: 28
        width: Math.min(440, parent.width - 48)
        background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: root._t("empty_trash_title_q"); font.pixelSize: 22; color: ThemeManager.onSurface }
            Label {
                Layout.fillWidth: true
                text: root._t("empty_trash_body").arg(root.trash.length).arg(root.formatSize(root.ov.trash || 0))
                wrapMode: Text.WordWrap
                color: ThemeManager.onSurfaceVariant
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                M3Button { text: root._t("cancel"); onClicked: emptyConfirm.close() }
                M3Button { kind: "filled"; text: root._t("delete_forever"); onClicked: { DB.emptyTrash(); emptyConfirm.close(); root.afterChange() } }
            }
        }
    }
}
