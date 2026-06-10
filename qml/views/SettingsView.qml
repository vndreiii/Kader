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

    function refreshDirs() {
        indexedDirs = DB.getIndexedDirectories()
    }

    function refreshIgnored() {
        ignoredFolders = DB.getIgnoredFolders()
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

                // Scrollable list
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.maximumHeight: root.height - 300
                    contentHeight: ignoredList.implicitHeight
                    clip: true

                    Column {
                        id: ignoredList
                        width: parent.width

                        Repeater {
                            model: root.ignoredFolders
                            delegate: Item {
                                width: parent.width
                                height: 64

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 12

                                    Rectangle {
                                        width: 36; height: 36; radius: 12
                                        color: ThemeManager.surfaceContainerHighest
                                        M3Icon { anchors.centerIn: parent; name: "folder"; size: 18; color: ThemeManager.onSurfaceVariant }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            width: parent.width
                                            text: modelData.name || modelData.path.split("/").filter(Boolean).pop()
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            color: ThemeManager.onSurface
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            width: parent.width
                                            text: modelData.path
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: 11
                                            color: ThemeManager.onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Button {
                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 32
                                        background: Rectangle {
                                            radius: 16
                                            color: parent.hovered ? Qt.alpha(ThemeManager.primary, 0.12) : Qt.alpha(ThemeManager.primary, 0.06)
                                        }
                                        contentItem: Label {
                                            text: I18n.t(Settings.language, "unignore")
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            color: ThemeManager.primary
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            DB.ignoreAlbum(modelData.path, false)
                                            root.refreshIgnored()
                                            AlbumModel.refresh()
                                            TimelineModel.refresh()
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: ThemeManager.outlineVariant
                                    opacity: 0.5
                                }
                            }
                        }

                        // Empty state
                        Item {
                            width: parent.width
                            height: 80
                            visible: root.ignoredFolders.length === 0
                            Label {
                                anchors.centerIn: parent
                                text: I18n.t(Settings.language, "no_ignored_folders")
                                font.pixelSize: 14
                                color: ThemeManager.onSurfaceVariant
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: ThemeManager.outlineVariant
                }

                Item { height: 16 }

                Button {
                    Layout.alignment: Qt.AlignRight
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
                    label: qsTr("Semantic Search")
                    sub: AI.modelsPresent
                         ? (AI.ready ? qsTr("Model loaded — ready to search") : qsTr("Models available — click to load"))
                         : qsTr("Download Qwen3-VL-Embedding-2B (~1.9 GB) to enable AI-powered search")

                    action: RowLayout {
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
                                text: AI.ready ? qsTr("Unload") : qsTr("Load")
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
                                text: qsTr("Download")
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
                                text: qsTr("Cancel")
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
                    label: qsTr("Index Gallery")
                    sub: {
                        if (AI.indexing)
                            return qsTr("%1 / %2 photos embedded…").arg(AI.indexedCount).arg(AI.indexTotal)
                        if (AI.indexedCount > 0 && AI.indexTotal > 0)
                            return qsTr("Done — %1 photos indexed").arg(AI.indexedCount)
                        return qsTr("Generate embeddings so you can search by description (GPU accelerated)")
                    }
                    action: ColumnLayout {
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
                                text: AI.indexing ? qsTr("Indexing…") : qsTr("Start Indexing")
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
                    label: qsTr("Index Documents")
                    sub: {
                        if (!AI.docsEnabled)
                            return qsTr("Enable to search PDF, TXT and Markdown files by content (uses AI embeddings)")
                        if (AI.docIndexing)
                            return qsTr("%1 / %2 documents indexed…").arg(AI.docIndexedCount).arg(AI.docIndexTotal)
                        if (AI.docIndexedCount > 0 && AI.docIndexTotal > 0)
                            return qsTr("Done — %1 documents indexed").arg(AI.docIndexedCount)
                        return qsTr("Ready — click to re-index documents")
                    }
                    last: true
                    action: RowLayout {
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
                title: qsTr("Performance")
                SettingsRow {
                    label: qsTr("Parallel Thumbnail Generation (BETA)")
                    sub: qsTr("Use multiple CPU cores during scan. Each worker uses 1 libvips thread to avoid overload. Takes effect on next scan.")
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
