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
                    text: "Ignored folders"
                    font.pixelSize: 22
                    font.weight: Font.Medium
                    color: ThemeManager.onSurface
                    bottomPadding: 4
                }
                Label {
                    text: "These folders are hidden from your timeline and albums."
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
                                            text: "Unignore"
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
                                text: "No ignored folders"
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
                    text: "Done"
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
                            Label { anchors.verticalCenter: parent.verticalCenter; text: "Manage ignored folders"; font.pixelSize: 14; font.weight: Font.Medium; color: ThemeManager.onSurfaceVariant }
                        }
                        onClicked: { root.refreshIgnored(); ignoredModal.open = true }
                    }

                    // Scan exclusion patterns
                    Label {
                        text: "Scan exclusion filters"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: ThemeManager.onSurfaceVariant
                        topPadding: 16
                        bottomPadding: 4
                        leftPadding: 20
                    }
                    Label {
                        text: "Directories whose path contains any of these substrings will be skipped during scan."
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
                title: I18n.t(Settings.language, "section_appearance")
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
                    action: MD.Slider {
                        id: densitySlider
                        from: 1; to: 3; stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: Settings.mosaicDensity
                        width: 120
                        onMoved: {
                            var d = Math.round(value)
                            Settings.mosaicDensity = d
                            TimelineModel.numColumns = (d === 1 ? 5 : d === 3 ? 3 : 4)
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
                            {code:"en",  name:"English"},
                            {code:"es",  name:"Español"},
                            {code:"ro",  name:"Română"},
                            {code:"fr",  name:"Français"},
                            {code:"pt",  name:"Português"},
                            {code:"ja",  name:"日本語"},
                            {code:"zh",  name:"中文"},
                            {code:"tr",  name:"Türkçe"},
                            {code:"ca",  name:"Català"},
                            {code:"gl",  name:"Galego"},
                            {code:"an",  name:"Andalú"},
                            {code:"nl",  name:"Nederlands"},
                            {code:"de",  name:"Deutsch"},
                            {code:"vi",  name:"Tiếng Việt"},
                            {code:"ru",  name:"Русский"},
                            {code:"hr",  name:"Hrvatski"},
                            {code:"sr",  name:"Српски"},
                            {code:"it",  name:"Italiano"},
                            {code:"fil", name:"Filipino"}
                        ]
                        model: langs.map(function(l) { return l.name })
                        implicitWidth: 150
                        currentIndex: {
                            var l = Settings.language
                            for (var i = 0; i < langs.length; i++)
                                if (langs[i].code === l) return i
                            return 0
                        }
                        onActivated: Settings.language = langs[currentIndex].code
                        background: Rectangle {
                            radius: 10
                            color: ThemeManager.surfaceContainerHighest
                            border.color: ThemeManager.outline; border.width: 1
                        }
                        contentItem: Label {
                            leftPadding: 12; rightPadding: 8
                            text: langCombo.displayText
                            font.pixelSize: 13
                            color: ThemeManager.onSurface
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            SettingsSection {
                title: I18n.t(Settings.language, "section_playback")
                SettingsRow {
                    label: "Use PulseAudio output"
                    sub: "Enables Discord to capture audio; switch off to use PipeWire directly"
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
                        label: "Show RAW files"
                        sub: "Include RAW camera formats (.NEF, .CR2, .ARW, .DNG…) in your library"
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
                        label: "File filter"
                        sub: "Choose which formats appear in Timeline and Albums"
                        last: true
                        action: Row {
                            spacing: 4
                            Repeater {
                                model: [["All", 0], ["JPEG only", 1], ["RAW only", 2]]
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
                title: I18n.t(Settings.language, "section_ai")
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
