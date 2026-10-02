import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../I18n.js" as I18n

Item {
    id: root
    property real topPadding: 32

    implicitWidth: 800
    implicitHeight: 600

    property var indexedDirs: []
    property var ignoredFolders: []
    property var scanExclusions: []

    // Selection state for the ignored-items manager (gallery-style multi-select).
    property var ignoredSel: ({})
    function ignoredSelCount() { return Object.keys(root.ignoredSel).length }
    function isIgnoredSelected(p) { return root.ignoredSel[p] === true }
    function toggleIgnoredSel(p) {
        var s = root.ignoredSel
        if (s[p]) delete s[p]; else s[p] = true
        root.ignoredSel = Object.assign({}, s)
    }
    function clearIgnoredSel() { root.ignoredSel = ({}) }
    function selectAllIgnored() {
        var s = {}
        for (var i = 0; i < root.ignoredFolders.length; i++) s[root.ignoredFolders[i].path] = true
        root.ignoredSel = s
    }
    function unignore(paths) {
        for (var i = 0; i < paths.length; i++) {
            var p = paths[i]
            var item = root.ignoredFolders.find(function(x) { return x.path === p })
            if (item && item.isMedia) DB.setIgnored(item.id, false)  // single file
            else                      DB.ignoreAlbum(p, false)        // whole folder
        }
        root.clearIgnoredSel()
        root.refreshIgnored(); AlbumModel.refresh(); TimelineModel.refresh()
    }

    function refreshDirs() {
        indexedDirs = DB.getIndexedDirectories()
    }

    function refreshIgnored() {
        // Folder ignores + individual ignored files, shown together.
        ignoredFolders = DB.getIgnoredFolders().concat(DB.getIgnoredMedia())
    }

    function refreshExclusions() {
        scanExclusions = DB.getScanExclusions()
    }

    Component.onCompleted: { refreshDirs(); refreshIgnored(); refreshExclusions(); Qt.callLater(applyPages) }

    Connections {
        target: FileScanner
        function onScanFinished(fileCount, dirsScanned, duration, rootPath) {
            // Only the directory list is ours to update. main.cpp already
            // refreshes the timeline/album/media models on scanFinished, on a
            // debounce; refreshing them here as well doubled that work — and
            // this view is cached for the app's lifetime, so once Settings had
            // been opened every scan paid for two full library re-queries.
            refreshDirs()
        }
    }

    // Ignored folders modal
    Rectangle {
        id: ignoredModal
        property bool open: false
        onOpenChanged: if (open) { root.clearIgnoredSel(); root.refreshIgnored() }
        anchors.fill: parent
        color: Qt.alpha("black", 0.45)
        visible: open
        z: 200
        Behavior on opacity { NumberAnimation { duration: 150 } }

        MouseArea { anchors.fill: parent; onClicked: ignoredModal.open = false }

        Rectangle {
            width: 520
            height: Math.min(root.height - 96, cardColumn.implicitHeight + 48)
            radius: 28
            color: ThemeManager.surfaceContainerHigh
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: cardColumn
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0

                Label {
                    text: I18n.t(Settings.language, "ignored_folders_title")
                    font.pixelSize: ThemeManager.fontTitle
                    font.weight: Font.Medium
                    color: ThemeManager.onSurface
                    bottomPadding: 4
                }
                Label {
                    text: I18n.t(Settings.language, "ignored_folders_sub")
                    font.pixelSize: ThemeManager.fontLabelL
                    color: ThemeManager.onSurfaceVariant
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    bottomPadding: 16
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: ThemeManager.outlineVariant
                }

                // Virtualized, multi-selectable list (gallery-style: click a row to
                // toggle; bulk-unignore from the footer). ListView handles hundreds of
                // rows efficiently and the WheelHandler gives free-spin mice real speed.
                ListView {
                    id: ignoredListView
                    Layout.fillWidth: true
                    visible: root.ignoredFolders.length > 0
                    Layout.preferredHeight: visible ? Math.min(contentHeight, root.height - 320) : 0
                    clip: true
                    model: root.ignoredFolders
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 4000
                    maximumFlickVelocity: 6000
                    cacheBuffer: 256
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    // Free-spin wheel: scroll a generous chunk per notch.
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (e) => {
                            var dy = (e.angleDelta.y !== 0 ? e.angleDelta.y : e.pixelDelta.y)
                            var max = Math.max(0, ignoredListView.contentHeight - ignoredListView.height)
                            ignoredListView.contentY =
                                Math.max(0, Math.min(max, ignoredListView.contentY - dy * 1.6))
                        }
                    }

                    delegate: Rectangle {
                        id: ignRow
                        required property var modelData
                        width: ignoredListView.width
                        height: 64
                        radius: 12
                        readonly property bool _sel: root.isIgnoredSelected(modelData.path)
                        color: _sel ? Qt.alpha(ThemeManager.primary, 0.12)
                                     : (ignRowMa.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.04) : "transparent")

                        MouseArea {
                            id: ignRowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleIgnoredSel(ignRow.modelData.path)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 12

                            // Thumbnail preview (folder cover / file thumb), with a
                            // selected overlay and an icon fallback when none exists.
                            Rectangle {
                                width: 40; height: 40; radius: 10
                                clip: true
                                color: ignRow._sel ? ThemeManager.primary : ThemeManager.surfaceContainerHighest

                                Image {
                                    anchors.fill: parent
                                    visible: !ignRow._sel && status === Image.Ready
                                    source: ignRow.modelData.thumb || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 80; sourceSize.height: 80
                                }
                                M3Icon {
                                    anchors.centerIn: parent
                                    visible: ignRow._sel || !ignRow.modelData.thumb
                                    name: ignRow._sel ? "check" : (ignRow.modelData.isMedia ? "image" : "folder")
                                    size: 18
                                    color: ignRow._sel ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    width: parent.width
                                    text: ignRow.modelData.name || ignRow.modelData.path.split("/").filter(Boolean).pop()
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: ThemeManager.onSurface
                                    elide: Text.ElideRight
                                }
                                Label {
                                    width: parent.width
                                    text: ignRow.modelData.path
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    color: ThemeManager.onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    visible: root.ignoredFolders.length === 0
                    Label {
                        anchors.centerIn: parent
                        text: I18n.t(Settings.language, "no_ignored_folders")
                        font.pixelSize: 14
                        color: ThemeManager.onSurfaceVariant
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: ThemeManager.outlineVariant
                }

                Item { height: 16 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Select all / Clear (only when there is something to act on)
                    Button {
                        visible: root.ignoredFolders.length > 0
                        flat: true
                        text: root.ignoredSelCount() === root.ignoredFolders.length && root.ignoredFolders.length > 0
                              ? I18n.t(Settings.language, "clear_selection")
                              : I18n.t(Settings.language, "select_all")
                        onClicked: {
                            if (root.ignoredSelCount() === root.ignoredFolders.length) root.clearIgnoredSel()
                            else root.selectAllIgnored()
                        }
                        background: Rectangle { radius: 20; color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.06) : "transparent" }
                        contentItem: Label {
                            text: parent.text
                            color: ThemeManager.primary
                            font.weight: Font.Medium; font.pixelSize: 14
                            topPadding: 8; bottomPadding: 8; leftPadding: 12; rightPadding: 12
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Bulk un-ignore selected
                    Button {
                        visible: root.ignoredSelCount() > 0
                        text: I18n.t(Settings.language, "unignore") + " (" + root.ignoredSelCount() + ")"
                        onClicked: root.unignore(Object.keys(root.ignoredSel))
                        background: Rectangle { radius: 20; color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.16) : Qt.alpha(ThemeManager.primary, 0.10) }
                        contentItem: Label {
                            text: parent.text
                            color: ThemeManager.primary
                            font.weight: Font.Medium; font.pixelSize: 14
                            topPadding: 8; bottomPadding: 8; leftPadding: 16; rightPadding: 16
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: I18n.t(Settings.language, "done")
                        onClicked: ignoredModal.open = false
                        background: Rectangle { radius: 20; color: ThemeManager.primaryContainer }
                        contentItem: Label {
                            text: parent.text
                            color: ThemeManager.onPrimaryContainer
                            font.weight: Font.Medium
                            font.pixelSize: 14
                            topPadding: 8; bottomPadding: 8; leftPadding: 20; rightPadding: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    // ── categories (M3 Expressive: colour-coded icon tiles) ────────────────
    property string current: "library"
    property string settingsQuery: ""
    readonly property bool compactNav: width < 900
    readonly property var categories: [
        { key: "library",     icon: "photo_library",  hue: 0.58, t: "section_library" },
        { key: "appearance",  icon: "palette",        hue: 0.83, t: "section_appearance" },
        { key: "playback",    icon: "play_circle",    hue: 0.95, t: "section_playback" },
        { key: "raw",         icon: "raw_on",         hue: 0.08, t: "section_raw" },
        { key: "privacy",     icon: "shield",         hue: 0.36, t: "section_privacy" },
        { key: "places",      icon: "public",         hue: 0.50, t: "section_map" },
        { key: "ai",          icon: "auto_awesome",   hue: 0.72, t: "section_ai" },
        { key: "performance", icon: "speed",          hue: 0.13, t: "section_performance" },
        { key: "updates",     icon: "system_update",  hue: 0.62, t: "section_updates" },
        { key: "about",       icon: "info",           hue: 0.0,  t: "section_about" }
    ]
    function tileBg(h) { return h === 0.0 ? ThemeManager.surfaceContainerHighest
                                           : Qt.hsla(h, ThemeManager.isDark ? 0.35 : 0.70, ThemeManager.isDark ? 0.28 : 0.86, 1) }
    function tileFg(h) { return h === 0.0 ? ThemeManager.onSurfaceVariant
                                           : Qt.hsla(h, ThemeManager.isDark ? 0.70 : 0.65, ThemeManager.isDark ? 0.82 : 0.28, 1) }
    function applyPages() {
        var q = settingsQuery.trim()
        for (var i = 0; i < settingsColumn.children.length; i++) {
            var c = settingsColumn.children[i]
            if (c.key === undefined || c.key === "") continue
            c.searching = q.length > 0
            if (q.length > 0) c.updateHit()
            c.visible = q.length > 0 ? c.searchHit : c.key === current
        }
        flick.contentY = 0
    }
    onCurrentChanged: applyPages()
    onSettingsQueryChanged: Qt.callLater(applyPages)

    Rectangle {
        id: navPane
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: root.topPadding + 8; bottomMargin: 16; leftMargin: 16 }
        width: root.compactNav ? 76 : 300
        radius: 28
        color: ThemeManager.surfaceContainerLow
        Behavior on width { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutCubic } }

        Column {
            anchors { fill: parent; margins: 12 }
            spacing: 4

            // search
            Rectangle {
                visible: !root.compactNav
                width: parent.width
                height: 52
                radius: 26
                color: ThemeManager.surfaceContainerHigh
                border.width: setSearch.activeFocus ? 2 : 0
                border.color: ThemeManager.primary
                MaterialSymbol { id: sIcon; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } name: "search"; size: 22; color: ThemeManager.onSurfaceVariant }
                TextField {
                    id: setSearch
                    anchors { left: sIcon.right; leftMargin: 8; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    background: null
                    font.pixelSize: 15
                    color: ThemeManager.onSurface
                    placeholderText: I18n.t(Settings.language, "settings_search")
                    placeholderTextColor: ThemeManager.onSurfaceVariant
                    onTextChanged: root.settingsQuery = text
                }
            }
            Item { width: 1; height: 8; visible: !root.compactNav }

            Repeater {
                model: root.categories
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: root.settingsQuery.length === 0 && root.current === modelData.key
                    width: parent.width
                    height: 56
                    radius: 28
                    color: sel ? ThemeManager.secondaryContainer
                         : catMa.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                    Row {
                        anchors { left: parent.left; leftMargin: root.compactNav ? (parent.width - 40) / 2 : 10; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Rectangle {
                            width: 40; height: 40
                            radius: sel ? 14 : 20   // circle → squircle when selected (shape morph)
                            Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                            color: root.tileBg(modelData.hue)
                            MaterialSymbol { anchors.centerIn: parent; name: modelData.icon; size: 22; color: root.tileFg(modelData.hue); fill: sel ? 1 : 0 }
                        }
                        Label {
                            visible: !root.compactNav
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.t(Settings.language, modelData.t)
                            font.pixelSize: 15
                            font.weight: sel ? Font.DemiBold : Font.Medium
                            color: sel ? ThemeManager.onSecondaryContainer : ThemeManager.onSurface
                        }
                    }
                    MouseArea {
                        id: catMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { setSearch.text = ""; root.current = modelData.key }
                    }
                    ToolTip.visible: root.compactNav && catMa.containsMouse
                    ToolTip.text: I18n.t(Settings.language, modelData.t)
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors { left: navPane.right; leftMargin: 8; right: parent.right; top: parent.top; bottom: parent.bottom }
        contentHeight: settingsColumn.height + 64
        clip: true
        
        Column {
            id: settingsColumn
            width: Math.min(760, flick.width - 64)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            
            Item { width: 1; height: root.topPadding }

            // Library Section
            SettingsSection {
                title: I18n.t(Settings.language, "section_library")
                key: "library"

                Column {
                    width: parent.width
                    spacing: 2

                    SettingsTile {
                        keywords: I18n.t(Settings.language, "indexed_dirs") + " folders directories scan add ignored"
                    Label {
                        text: I18n.t(Settings.language, "indexed_dirs")
                        font.pixelSize: ThemeManager.fontLabelL
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
                                        font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
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
                            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t(Settings.language, "add_dir_scan"); font.pixelSize: 14; font.weight: Font.Medium; color: ThemeManager.primary }
                        }
                        onClicked: ApplicationWindow.window.openFolderPickerForSettings()
                    }

                    Button {
                        width: parent.width
                        height: 56
                        flat: true
                        background: Rectangle { color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.04) : "transparent" }
                        contentItem: Row {
                            spacing: 12
                            leftPadding: 20
                            anchors.verticalCenter: parent.verticalCenter
                            M3Icon { anchors.verticalCenter: parent.verticalCenter; name: "close"; size: 20; color: ThemeManager.onSurfaceVariant }
                            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.t(Settings.language, "manage_ignored"); font.pixelSize: 14; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant }
                        }
                        onClicked: { root.refreshIgnored(); ignoredModal.open = true }
                    }
                    }

                    // Scan exclusion patterns
                    SettingsTile {
                        keywords: I18n.t(Settings.language, "scan_exclusions") + " exclude folders"
                    Label {
                        text: I18n.t(Settings.language, "scan_exclusions")
                        font.pixelSize: ThemeManager.fontLabelL
                        font.weight: Font.Medium
                        color: ThemeManager.onSurfaceVariant
                        topPadding: 16
                        bottomPadding: 4
                        leftPadding: 20
                    }
                    Label {
                        text: I18n.t(Settings.language, "scan_exclusions_sub")
                        font.pixelSize: 12
                        color: ThemeManager.onSurfaceVariant
                        wrapMode: Text.Wrap
                        width: parent.width - 40
                        leftPadding: 20
                        bottomPadding: 8
                    }

                    Repeater {
                        model: root.scanExclusions
                        delegate: Item {
                            width: parent.width
                            height: 48
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 12
                                spacing: 12
                                Rectangle {
                                    width: 28; height: 28; radius: 8
                                    color: ThemeManager.surfaceContainerHighest
                                    Label { anchors.centerIn: parent; text: "/"; font.family: "JetBrains Mono"; font.pixelSize: 14; color: ThemeManager.onSurfaceVariant }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: ThemeManager.fontLabelL
                                    color: ThemeManager.onSurface
                                    elide: Text.ElideRight
                                }
                                Button {
                                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                    background: Rectangle { radius: 16; color: parent.hovered ? Qt.alpha(ThemeManager.error, 0.08) : "transparent" }
                                    contentItem: M3Icon { name: "delete"; size: 16; color: ThemeManager.error; anchors.centerIn: parent }
                                    onClicked: { DB.removeScanExclusion(modelData); root.refreshExclusions() }
                                }
                            }
                        }
                    }

                    // Add new exclusion pattern row
                    RowLayout {
                        height: 56
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 12
                        spacing: 0

                        TextField {
                            id: exclusionInput
                            Layout.fillWidth: true
                            placeholderText: "e.g.  /src/  or  node_modules"
                            font.family: "JetBrains Mono"
                            font.pixelSize: ThemeManager.fontLabelL
                            background: Rectangle { radius: 8; color: ThemeManager.surfaceContainerHighest; border.color: ThemeManager.outline; border.width: 1 }
                            color: ThemeManager.onSurface
                            leftPadding: 12; rightPadding: 12
                            Keys.onReturnPressed: addExclusion()
                        }
                        Item { width: 8 }
                        Button {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            background: Rectangle { radius: 16; color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.12) : Qt.alpha(ThemeManager.primary, 0.06) }
                            contentItem: M3Icon { name: "add"; size: 18; color: ThemeManager.primary; anchors.centerIn: parent }
                            onClicked: addExclusion()
                        }

                        function addExclusion() {
                            var p = exclusionInput.text.trim()
                            if (p.length > 0) { DB.addScanExclusion(p); root.refreshExclusions(); exclusionInput.text = "" }
                        }
                    }
                    }

                    SettingsRow {
                        label: I18n.t(Settings.language, "auto_scan")
                        sub: I18n.t(Settings.language, "auto_scan_sub")
                        action: M3Switch {
                            checked: Settings.autoScan
                            onCheckedChanged: Settings.autoScan = checked
                        }
                    }
                    SettingsRow {
                        label: I18n.t(Settings.language, "trash_retention")
                        sub: I18n.t(Settings.language, "trash_retention_sub")
                        action: Row {
                            spacing: 4
                            Repeater {
                                model: [[I18n.t(Settings.language, "days_n").arg(7), 7],
                                        [I18n.t(Settings.language, "days_n").arg(30), 30],
                                        [I18n.t(Settings.language, "days_n").arg(90), 90],
                                        [I18n.t(Settings.language, "never"), 0]]
                            delegate: Button {
                                required property var modelData
                                text: modelData[0]
                                checkable: true
                                checked: Settings.trashRetentionDays === modelData[1]
                                onClicked: Settings.trashRetentionDays = modelData[1]
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
                        last: true
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_appearance")
                key: "appearance"
                SettingsRow {
                    label: I18n.t(Settings.language, "theme")
                    sub: [I18n.t(Settings.language, "theme_system"), I18n.t(Settings.language, "theme_light"), I18n.t(Settings.language, "theme_dark")][ThemeManager.themeMode]
                    action: Row {
                        spacing: 4
                        Repeater {
                            model: [I18n.t(Settings.language, "theme_system"), I18n.t(Settings.language, "theme_light"), I18n.t(Settings.language, "theme_dark")]
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
                    label: I18n.t(Settings.language, "window_buttons")
                    sub: I18n.t(Settings.language, typeof SYSTEM_WINDOW_BUTTONS !== "undefined" && SYSTEM_WINDOW_BUTTONS
                                                   ? "window_buttons_sub_shown" : "window_buttons_sub_hidden")
                    action: Row {
                        spacing: 4
                        Repeater {
                            model: [[I18n.t(Settings.language, "auto"), 0], [I18n.t(Settings.language, "show"), 1], [I18n.t(Settings.language, "hide"), 2]]
                            delegate: Button {
                                required property var modelData
                                text: modelData[0]
                                checkable: true
                                checked: Settings.windowButtons === modelData[1]
                                onClicked: Settings.windowButtons = modelData[1]
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
                    label: I18n.t(Settings.language, "dynamic_color")
                    sub: I18n.t(Settings.language, "dynamic_color_sub")
                    action: M3Switch { 
                        checked: ThemeManager.dynamicColor 
                        onCheckedChanged: ThemeManager.dynamicColor = checked
                    }
                }
                SettingsRow {
                    id: densityRow
                    label: I18n.t(Settings.language, "mosaic_density")
                    sub: {
                        var names = [I18n.t(Settings.language, "density_dense"),
                                     I18n.t(Settings.language, "density_compact"),
                                     I18n.t(Settings.language, "density_comfortable"),
                                     I18n.t(Settings.language, "density_spacious")]
                        return names[Math.max(0, Math.min(Math.round(densitySlider.value) - 1, 3))]
                    }
                    action: M3Slider {
                        id: densitySlider
                        from: 1; to: 4; stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: Settings.mosaicDensity
                        width: 180
                        onMoved: {
                            var d = Math.round(value)
                            Settings.mosaicDensity = d
                            TimelineModel.numColumns = (7 - d)   // 1→6 … 4→3 columns
                        }
                    }
                }

                SettingsRow {
                    label: I18n.t(Settings.language, "language_label")
                    sub: I18n.t(Settings.language, "language_sub")
                    last: true
                    action: ComboBox {
                        id: langCombo
                        property var langs: [
                            {code:"an",  name:"Andalú"},
                            {code:"ca",  name:"Català"},
                            {code:"de",  name:"Deutsch"},
                            {code:"en",  name:"English"},
                            {code:"es",  name:"Español"},
                            {code:"fil", name:"Filipino"},
                            {code:"fr",  name:"Français"},
                            {code:"gl",  name:"Galego"},
                            {code:"hr",  name:"Hrvatski"},
                            {code:"it",  name:"Italiano"},
                            {code:"ja",  name:"日本語"},
                            {code:"nl",  name:"Nederlands"},
                            {code:"pt",  name:"Português"},
                            {code:"ro",  name:"Română"},
                            {code:"ru",  name:"Русский"},
                            {code:"sr",  name:"Српски"},
                            {code:"tr",  name:"Türkçe"},
                            {code:"vi",  name:"Tiếng Việt"},
                            {code:"zh",  name:"中文"}
                        ]
                        model: langs.map(function(l) { return l.name })
                        implicitWidth: 200
                        implicitHeight: 44
                        currentIndex: {
                            var l = Settings.language
                            for (var i = 0; i < langs.length; i++)
                                if (langs[i].code === l) return i
                            return 3   // unsupported system language: the UI falls back to English
                        }
                        onActivated: Settings.language = langs[currentIndex].code
                        background: Rectangle {
                            radius: 12
                            color: langCombo.pressed
                                   ? Qt.alpha(ThemeManager.primary, 0.12)
                                   : (langCombo.hovered ? Qt.alpha(ThemeManager.onSurface, 0.06) : ThemeManager.surfaceContainerHighest)
                            border.color: langCombo.pressed ? ThemeManager.primary : ThemeManager.outline
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                        }
                        contentItem: Label {
                            leftPadding: 14; rightPadding: 36
                            text: langCombo.displayText
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: ThemeManager.onSurface
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        indicator: M3Icon {
                            name: langCombo.popup.visible ? "expand_less" : "expand_more"
                            size: 20
                            color: ThemeManager.onSurfaceVariant
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_playback")
                key: "playback"
                SettingsRow {
                    label: I18n.t(Settings.language, "use_pulse_audio")
                    sub: I18n.t(Settings.language, "use_pulse_audio_sub")
                    last: true
                    action: M3Switch {
                        checked: Settings.usePulseAudio
                        onCheckedChanged: Settings.usePulseAudio = checked
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_raw")
                key: "raw"

                Column {
                    width: parent.width
                    spacing: 2

                    SettingsRow {
                        label: I18n.t(Settings.language, "show_raw")
                        sub: I18n.t(Settings.language, "show_raw_sub")
                        action: M3Switch {
                            checked: Settings.rawFilter !== 1
                            onCheckedChanged: {
                                if (!checked && Settings.rawFilter !== 1)
                                    Settings.rawFilter = 1
                                else if (checked && Settings.rawFilter === 1)
                                    Settings.rawFilter = 0
                            }
                        }
                    }

                    SettingsRow {
                        label: I18n.t(Settings.language, "file_filter")
                        sub: I18n.t(Settings.language, "file_filter_sub")
                        last: true
                        action: Row {
                            spacing: 4
                            Repeater {
                                model: [[I18n.t(Settings.language, "filter_all"), 0], [I18n.t(Settings.language, "filter_jpeg_only"), 1], [I18n.t(Settings.language, "filter_raw_only"), 2]]
                                delegate: Button {
                                    required property var modelData
                                    text: modelData[0]
                                    checkable: true
                                    checked: Settings.rawFilter === modelData[1]
                                    onClicked: Settings.rawFilter = modelData[1]
                                    implicitWidth: text === "JPEG only" ? 88 : 72
                                    implicitHeight: 34
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
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_privacy")
                key: "privacy"
                SettingsRow {
                    label: I18n.t(Settings.language, "strip_exif")
                    sub: I18n.t(Settings.language, "strip_exif_sub")
                    last: true
                    action: M3Button {
                        kind: "tonal"
                        text: I18n.t(Settings.language, "strip_metadata_btn")
                        enabled: !FileScanner.stripping
                        onClicked: stripDialog.open()
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_map")
                key: "places"
                SettingsRow {
                    label: I18n.t(Settings.language, "use_3d_globe")
                    sub: I18n.t(Settings.language, "use_3d_globe_sub")
                    last: true
                    action: M3Switch {
                        checked: Settings.use3DGlobe
                        onCheckedChanged: Settings.use3DGlobe = checked
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_ai")
                key: "ai"

                // Model status + download
                SettingsRow {
                    label: I18n.t(Settings.language, "faces_setting")
                    sub: Analyzer.downloading ? I18n.t(Settings.language, "people_downloading").arg(Math.round(Analyzer.downloadProgress * 100))
                                              : I18n.t(Settings.language, "faces_setting_sub")
                    action: M3Switch {
                        checked: Analyzer.facesEnabled
                        onToggled: (on) => on ? Analyzer.enableFaces() : Analyzer.disableFaces()
                    }
                }
                SettingsRow {
                    label: I18n.t(Settings.language, "ai_semantic_search")
                    sub: AI.modelsPresent
                         ? (AI.ready ? I18n.t(Settings.language, "ai_model_loaded") : I18n.t(Settings.language, "ai_models_available"))
                         : I18n.t(Settings.language, "ai_download_model")

                    action: Row {
                        spacing: 8

                        // Load / unload
                        Rectangle {
                            visible: AI.modelsPresent && !AI.loading && !AI.downloading
                            width: btn.implicitWidth + 24; height: 36; radius: 18
                            color: AI.ready ? Qt.alpha(ThemeManager.error, 0.1) : ThemeManager.primaryContainer
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Label {
                                id: btn
                                anchors.centerIn: parent
                                text: AI.ready ? I18n.t(Settings.language, "ai_unload") : I18n.t(Settings.language, "ai_load")
                                font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
                                color: AI.ready ? ThemeManager.error : ThemeManager.onPrimaryContainer
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: AI.ready ? AI.unloadModel() : AI.loadModel()
                            }
                        }

                        // Spinner while loading
                        BusyIndicator {
                            visible: AI.loading
                            width: 28; height: 28
                            running: AI.loading
                        }

                        // Download button
                        Rectangle {
                            visible: !AI.modelsPresent && !AI.downloading
                            width: dlLabel.implicitWidth + 24; height: 36; radius: 18
                            color: ThemeManager.primaryContainer
                            Label {
                                id: dlLabel
                                anchors.centerIn: parent
                                text: I18n.t(Settings.language, "ai_download")
                                font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
                                color: ThemeManager.onPrimaryContainer
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: AI.downloadModels()
                            }
                        }

                        // Cancel download
                        Rectangle {
                            visible: AI.downloading
                            width: cancelLabel.implicitWidth + 24; height: 36; radius: 18
                            color: Qt.alpha(ThemeManager.error, 0.1)
                            Label {
                                id: cancelLabel
                                anchors.centerIn: parent
                                text: I18n.t(Settings.language, "cancel")
                                font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
                                color: ThemeManager.error
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: AI.cancelDownload()
                            }
                        }
                    }
                }

                // Download progress bar
                SettingsRow {
                    visible: AI.downloading
                    label: AI.dlStatus
                    sub: Math.round(AI.dlProgress * 100) + "% complete"
                    action: Rectangle {
                        width: 120; height: 6; radius: 3
                        color: ThemeManager.surfaceContainerHighest
                        Rectangle {
                            width: parent.width * AI.dlProgress
                            height: parent.height; radius: parent.radius
                            color: ThemeManager.primary
                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                    }
                }

                // Index library
                SettingsRow {
                    visible: AI.ready
                    label: I18n.t(Settings.language, "ai_index_gallery")
                    sub: {
                        if (AI.indexing)
                            return I18n.t(Settings.language, "ai_photos_embedding").arg(AI.indexedCount).arg(AI.indexTotal)
                        if (AI.indexedCount > 0 && AI.indexTotal > 0)
                            return I18n.t(Settings.language, "ai_photos_done").arg(AI.indexedCount)
                        return I18n.t(Settings.language, "ai_index_gallery_sub")
                    }
                    action: Column {
                        spacing: 6

                        // Progress bar shown while indexing
                        Rectangle {
                            visible: AI.indexing
                            width: 160; height: 6; radius: 3
                            color: ThemeManager.surfaceContainerHighest
                            Rectangle {
                                width: AI.indexTotal > 0
                                    ? Math.max(4, parent.width * AI.indexedCount / AI.indexTotal)
                                    : 0
                                height: parent.height; radius: parent.radius
                                color: ThemeManager.primary
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }

                        Rectangle {
                            width: idxLabel.implicitWidth + 24; height: 36; radius: 18
                            color: AI.indexing
                                ? ThemeManager.surfaceContainerHighest
                                : ThemeManager.secondaryContainer
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Label {
                                id: idxLabel
                                anchors.centerIn: parent
                                text: AI.indexing ? I18n.t(Settings.language, "ai_indexing") : I18n.t(Settings.language, "ai_start_indexing")
                                font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
                                color: AI.indexing
                                    ? ThemeManager.onSurfaceVariant
                                    : ThemeManager.onSecondaryContainer
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: AI.indexing ? Qt.ArrowCursor : Qt.PointingHandCursor
                                enabled: !AI.indexing
                                onClicked: AI.indexAllMedia()
                            }
                        }
                    }
                }

                // Index documents
                SettingsRow {
                    visible: AI.modelsPresent
                    label: I18n.t(Settings.language, "ai_index_documents")
                    sub: {
                        if (!AI.docsEnabled)
                            return I18n.t(Settings.language, "ai_index_documents_sub")
                        if (AI.docIndexing)
                            return I18n.t(Settings.language, "ai_docs_indexing").arg(AI.docIndexedCount).arg(AI.docIndexTotal)
                        if (AI.docIndexedCount > 0 && AI.docIndexTotal > 0)
                            return I18n.t(Settings.language, "ai_docs_done").arg(AI.docIndexedCount)
                        return I18n.t(Settings.language, "ai_docs_ready")
                    }
                    last: true
                    action: Row {
                        spacing: 8

                        // Progress bar while doc indexing
                        Rectangle {
                            visible: AI.docIndexing
                            width: 120; height: 6; radius: 3
                            color: ThemeManager.surfaceContainerHighest
                            Rectangle {
                                width: AI.docIndexTotal > 0
                                    ? Math.max(4, parent.width * AI.docIndexedCount / AI.docIndexTotal)
                                    : 0
                                height: parent.height; radius: parent.radius
                                color: ThemeManager.primary
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }

                        M3Switch {
                            checked: AI.docsEnabled
                            onToggled: AI.setDocsEnabled(checked)
                        }
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_performance")
                key: "performance"
                SettingsRow {
                    label: I18n.t(Settings.language, "resource_usage")
                    sub: I18n.t(Settings.language, "resource_usage_sub")
                    action: Row {
                        spacing: 4
                        Repeater {
                            model: [[I18n.t(Settings.language, "resource_low"), 0],
                                    [I18n.t(Settings.language, "resource_balanced"), 1],
                                    [I18n.t(Settings.language, "resource_full"), 2]]
                            delegate: Button {
                                required property var modelData
                                text: modelData[0]
                                checkable: true
                                checked: Settings.resourceMode === modelData[1]
                                onClicked: Settings.resourceMode = modelData[1]
                                implicitWidth: 84; implicitHeight: 34
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
                    label: I18n.t(Settings.language, "parallel_thumbs")
                    sub: I18n.t(Settings.language, "parallel_thumbs_sub")
                    last: true
                    action: M3Switch {
                        checked: Settings.parallelThumbnails
                        onToggled: Settings.parallelThumbnails = checked
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_updates")
                key: "updates"
                visible: typeof Updater !== "undefined"
                SettingsRow {
                    label: I18n.t(Settings.language, "update_auto")
                    sub: I18n.t(Settings.language, "update_auto_sub")
                    action: M3Switch {
                        checked: Settings.autoUpdate
                        onToggled: Settings.autoUpdate = checked
                    }
                }
                SettingsRow {
                    last: true
                    label: "Kader " + Qt.application.version
                    sub: {
                        if (typeof Updater === "undefined") return ""
                        switch (Updater.state) {
                        case 1: return I18n.t(Settings.language, "update_checking")
                        case 2: case 3: case 4: return I18n.t(Settings.language, "update_available_short").arg(Updater.latestVersion)
                        case 5: return I18n.t(Settings.language, "update_ready_title")
                        case 6: return Updater.error
                        }
                        return settingsUpToDate.visible || Updater.lastChecked === ""
                            ? I18n.t(Settings.language, "update_channel_" + Updater.channel)
                            : I18n.t(Settings.language, "update_last_checked").arg(Updater.lastChecked)
                    }
                    action: Row {
                        spacing: 8
                        Label {
                            id: settingsUpToDate
                            visible: false
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.t(Settings.language, "update_up_to_date")
                            color: ThemeManager.primary
                            font.pixelSize: 12
                            Timer { id: upToDateTimer; interval: 4000; onTriggered: settingsUpToDate.visible = false }
                            Connections {
                                target: typeof Updater !== "undefined" ? Updater : null
                                function onUpToDate() { settingsUpToDate.visible = true; upToDateTimer.restart() }
                            }
                        }
                        M3Button {
                            kind: Updater.available ? "filled" : "tonal"
                            text: Updater.available ? I18n.t(Settings.language, "update_show")
                                                    : I18n.t(Settings.language, "update_check_now")
                            enabled: Updater.state !== 1
                            onClicked: Updater.available ? Updater.updateOffered() : Updater.check(true)
                        }
                    }
                }
            }

            // About
            SettingsSection {
                title: I18n.t(Settings.language, "section_about")
                key: "about"
                SettingsTile {
                    keywords: "kader version about"
                    Item {
                    width: parent.width
                    height: 112
                    Row {
                        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                        spacing: 18
                        Image {
                            width: 64; height: 64
                            source: "qrc:/Kader/assets/icons/kader-128.png"
                            sourceSize: Qt.size(128, 128)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Label { text: "Kader"; font.pixelSize: 24; font.weight: Font.Medium; color: ThemeManager.onSurface }
                            Label { text: I18n.t(Settings.language, "about_version").arg(Qt.application.version); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                            Label { text: I18n.t(Settings.language, "about_tagline"); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                        }
                    }
                }
                }
                SettingsRow {
                    label: I18n.t(Settings.language, "about_support")
                    sub: I18n.t(Settings.language, "about_support_sub")
                    action: M3Button {
                        kind: "filled"
                        text: I18n.t(Settings.language, "donate_kofi")
                        onClicked: Qt.openUrlExternally("https://ko-fi.com/vndreiii")
                    }
                }
                SettingsRow {
                    label: I18n.t(Settings.language, "about_source")
                    sub: "github.com/vndreiii/kader"
                    action: Row {
                        spacing: 4
                        M3Button { text: I18n.t(Settings.language, "about_github"); onClicked: Qt.openUrlExternally("https://github.com/vndreiii/kader") }
                        M3Button { text: I18n.t(Settings.language, "about_issue"); onClicked: Qt.openUrlExternally("https://github.com/vndreiii/kader/issues/new") }
                    }
                }
                SettingsRow {
                    last: true
                    label: I18n.t(Settings.language, "about_licenses")
                    sub: I18n.t(Settings.language, "about_licenses_sub")
                    action: M3Button {
                        kind: "tonal"
                        text: I18n.t(Settings.language, "about_view")
                        onClicked: licensesDialog.open()
                    }
                }
            }
        }
    }

    // ── remove metadata ─────────────────────────────────────────────────────
    Popup {
        id: stripDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        modal: true
        padding: 28
        property bool locationOnly: true
        property string result: ""
        onOpened: result = ""
        background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
        Connections {
            target: FileScanner
            function onStripProgress(done, total) { stripBar.to = Math.max(1, total); stripBar.value = done }
            function onStripFinished(changed, failed) {
                stripDialog.result = I18n.t(Settings.language, "strip_done").arg(changed)
                    + (failed > 0 ? " " + I18n.t(Settings.language, "strip_failed").arg(failed) : "")
            }
        }
        contentItem: Column {
            spacing: 16
            Label { text: I18n.t(Settings.language, "strip_exif"); font.pixelSize: 24; color: ThemeManager.onSurface }
            Label {
                width: parent.width
                text: I18n.t(Settings.language, "strip_body")
                wrapMode: Text.WordWrap
                color: ThemeManager.onSurfaceVariant
            }
            Repeater {
                model: [[I18n.t(Settings.language, "strip_location_only"), true], [I18n.t(Settings.language, "strip_all"), false]]
                delegate: RadioButton {
                    required property var modelData
                    text: modelData[0]
                    checked: stripDialog.locationOnly === modelData[1]
                    enabled: !FileScanner.stripping
                    onClicked: stripDialog.locationOnly = modelData[1]
                }
            }
            Rectangle {
                width: parent.width
                height: warn.implicitHeight + 24
                radius: 12
                color: ThemeManager.errorContainer
                Label {
                    id: warn
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                    text: I18n.t(Settings.language, "strip_warning")
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onErrorContainer
                    font.pixelSize: 13
                }
            }
            ProgressBar { id: stripBar; width: parent.width; visible: FileScanner.stripping; from: 0; to: 1 }
            Label { visible: stripDialog.result.length > 0; text: stripDialog.result; color: ThemeManager.primary }
            Row {
                anchors.right: parent.right
                spacing: 8
                M3Button { text: I18n.t(Settings.language, stripDialog.result.length > 0 ? "done" : "cancel"); onClicked: stripDialog.close() }
                M3Button {
                    visible: stripDialog.result.length === 0
                    kind: "filled"
                    enabled: !FileScanner.stripping
                    text: I18n.t(Settings.language, "strip_confirm")
                    onClicked: FileScanner.stripMetadata(stripDialog.locationOnly)
                }
            }
        }
    }

    // ── open-source licences ────────────────────────────────────────────────
    Popup {
        id: licensesDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 48)
        height: Math.min(700, parent.height - 48)
        modal: true
        padding: 28
        background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
        readonly property var items: [
            ["Kader", "MIT", "https://github.com/vndreiii/kader"],
            ["milfs-connect", "MIT", "https://github.com/vndreiii/milfs-connect"],
            ["Qt 6", "LGPL-3.0", "https://www.qt.io/licensing/open-source-lgpl-obligations"],
            ["libvips", "LGPL-2.1-or-later", "https://github.com/libvips/libvips/blob/master/LICENSE"],
            ["Exiv2", "GPL-2.0-or-later", "https://github.com/Exiv2/exiv2/blob/main/COPYING"],
            ["LibRaw", "LGPL-2.1 / CDDL-1.0", "https://github.com/LibRaw/LibRaw/blob/master/LICENSE.LGPL"],
            ["Poppler", "GPL-2.0-or-later", "https://gitlab.freedesktop.org/poppler/poppler/-/blob/master/COPYING"],
            ["OpenSSL", "Apache-2.0", "https://www.openssl.org/source/license.html"],
            ["SQLite", "Public domain", "https://www.sqlite.org/copyright.html"],
            ["FFmpeg (runtime tool)", "LGPL-2.1-or-later", "https://ffmpeg.org/legal.html"],
            ["llama.cpp / ggml", "MIT", "https://github.com/ggml-org/llama.cpp/blob/master/LICENSE"],
            ["Qwen3-VL-Embedding (model)", "Apache-2.0", "https://huggingface.co/Qwen/Qwen3-VL-Embedding-2B"],
            ["YuNet face detection (model)", "MIT", "https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet"],
            ["SFace face recognition (model)", "Apache-2.0", "https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface"],
            ["Natural Earth", "Public domain", "https://www.naturalearthdata.com/about/terms-of-use/"],
            ["GeoNames", "CC BY 4.0", "https://www.geonames.org/about.html"],
            ["OpenStreetMap / CARTO tiles (2D map)", "ODbL / CC BY 3.0", "https://www.openstreetmap.org/copyright"],
            ["Material Symbols", "Apache-2.0", "https://github.com/google/material-design-icons/blob/master/LICENSE"],
            ["Rust standard library", "MIT / Apache-2.0", "https://github.com/rust-lang/rust/blob/master/COPYRIGHT"]
        ]
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: I18n.t(Settings.language, "about_licenses"); font.pixelSize: 24; color: ThemeManager.onSurface }
            Label {
                Layout.fillWidth: true
                text: I18n.t(Settings.language, "about_licenses_body")
                wrapMode: Text.WordWrap
                color: ThemeManager.onSurfaceVariant
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: licensesDialog.items
                spacing: 2
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    height: 56
                    background: Rectangle { radius: 12; color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.06) : "transparent" }
                    contentItem: RowLayout {
                        spacing: 12
                        Label { Layout.fillWidth: true; text: modelData[0]; color: ThemeManager.onSurface; font.pixelSize: 15; elide: Text.ElideRight }
                        Rectangle {
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: licLbl.implicitWidth + 18
                            radius: 13
                            color: ThemeManager.secondaryContainer
                            Label { id: licLbl; anchors.centerIn: parent; text: modelData[1]; font.pixelSize: 12; color: ThemeManager.onSecondaryContainer }
                        }
                        MaterialSymbol { name: "open_in_new"; size: 18; color: ThemeManager.onSurfaceVariant }
                    }
                    onClicked: Qt.openUrlExternally(modelData[2])
                }
            }
            M3Button { Layout.alignment: Qt.AlignRight; text: I18n.t(Settings.language, "close"); onClicked: licensesDialog.close() }
        }
    }
}
