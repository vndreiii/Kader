import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material as MD
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

    Component.onCompleted: { refreshDirs(); refreshIgnored(); refreshExclusions() }

    Connections {
        target: FileScanner
        function onScanFinished(paths, dirsScanned, duration, rootPath) {
            refreshDirs()
            // Also refresh other models
            TimelineModel.refresh()
            AlbumModel.refresh()
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
                    font.pixelSize: 22
                    font.weight: Font.Medium
                    color: ThemeManager.onSurface
                    bottomPadding: 4
                }
                Label {
                    text: I18n.t(Settings.language, "ignored_folders_sub")
                    font.pixelSize: 13
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
                title: I18n.t(Settings.language, "section_library")
                
                Column {
                    width: parent.width
                    spacing: 0

                    Label {
                        text: I18n.t(Settings.language, "indexed_dirs")
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

                    // Scan exclusion patterns
                    Label {
                        text: I18n.t(Settings.language, "scan_exclusions")
                        font.pixelSize: 13
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
                                    font.pixelSize: 13
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
                            font.pixelSize: 13
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

                    SettingsRow {
                        label: I18n.t(Settings.language, "auto_scan")
                        sub: I18n.t(Settings.language, "auto_scan_sub")
                        action: M3Switch { checked: true }
                    }
                    SettingsRow {
                        label: I18n.t(Settings.language, "trash_retention")
                        sub: I18n.t(Settings.language, "trash_retention_sub")
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
                title: I18n.t(Settings.language, "section_appearance")
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
                    label: I18n.t(Settings.language, "dynamic_color")
                    sub: I18n.t(Settings.language, "dynamic_color_sub")
                    action: M3Switch { checked: true }
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
                    action: MD.Slider {
                        id: densitySlider
                        from: 1; to: 4; stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: Settings.mosaicDensity
                        width: 140
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
                            return 0
                        }
                        onActivated: Settings.language = langs[currentIndex].code
                        background: Rectangle {
                            radius: 12
                            color: langCombo.pressed
                                   ? Qt.alpha(ThemeManager.primary, 0.12)
                                   : (langCombo.hovered ? Qt.alpha(ThemeManager.onSurface, 0.06) : ThemeManager.surfaceContainerHighest)
                            border.color: langCombo.pressed ? ThemeManager.primary : ThemeManager.outline
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 80 } }
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

                Column {
                    width: parent.width
                    spacing: 0

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
                SettingsRow {
                    label: I18n.t(Settings.language, "strip_exif")
                    sub: I18n.t(Settings.language, "strip_exif_sub")
                    last: true
                    action: Button {
                        text: I18n.t(Settings.language, "strip_metadata_btn")
                        onClicked: console.log("Strip EXIF")
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_ai")

                // Model status + download
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
                                font.pixelSize: 13; font.weight: Font.Medium
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
                                font.pixelSize: 13; font.weight: Font.Medium
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
                                font.pixelSize: 13; font.weight: Font.Medium
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
                                font.pixelSize: 13; font.weight: Font.Medium
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
        }
    }
}
