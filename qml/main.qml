import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import "components"
import "views"
import "I18n.js" as I18n

ApplicationWindow {
    id: window
    width: 1480
    height: 940
    visible: true
    color: "transparent"
    // _pendingView is set the moment the password dialog opens (before auth),
    // so the window title reports "Hidden" immediately for IPC / screen-share scripts.
    property string _pendingView: ""
    title: {
        var v = (_pendingView !== "") ? _pendingView : currentView
        var suffix = ({ "albums": "Albums", "videos": "Videos", "map": "Places",
                        "favorites": "Favorites", "hidden": "Hidden",
                        "trash": "Trash", "settings": "Settings" })[v]
        if (!suffix) return "Kader"
        if (v === "albums" && detailTitle !== "") return "Kader — " + detailTitle
        return "Kader — " + suffix
    }
    flags: Qt.Window | Qt.FramelessWindowHint

    property string currentView: "timeline"
    property bool sidebarCollapsed: false
    property string detailTitle: ""
    property int _photoCount: 0

    function _refreshPhotoCount() { _photoCount = DB.getPhotoCount() }
    property bool viewerOnlyMode: false   // true when launched via argv[1]

    property real timelineScrollY: 0

    onCurrentViewChanged: {
        if (searchPill._aiMode) {
            searchPill._aiMode = false
            TimelineModel.clearAiFilter()
            window._aiDocResults = []
        }
    }

    // Restore sort preference for the given view key
    function applyViewSort(view) {
        var pref = DB.getSortPref(view)
        // Property assignment, not setSortRole(): TimelineModel's setters are plain
        // WRITE accessors (not Q_INVOKABLE), so the function-call form silently fails.
        if (view === "albums") {
            AlbumModel.sortRole  = pref.role
            AlbumModel.sortOrder = pref.order
        } else {
            TimelineModel.sortRole  = pref.role
            TimelineModel.sortOrder = pref.order
        }
    }

    property var _aiDocResults: []
    
    FontLoader {
        id: materialSymbolsFont
        source: "qrc:/Kader/assets/MaterialSymbolsRounded.ttf"
    }
    Connections {
        target: AI
        function onSearchFinished(results) {
            searchPill._aiSearching = false
            var imageIds = []
            var docs = []
            for (var i = 0; i < results.length; i++) {
                var r = results[i]
                if (r.type === "doc") docs.push(r)
                else imageIds.push(r.id)
            }
            window._aiDocResults = docs
            TimelineModel.setAiFilter(imageIds)
            var tl = window._tlViewInst
            if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
            window.currentView = "timeline"
        }
        function onEngineError(msg) {
            searchPill._aiSearching = false
            aiErrorToast.message = msg
            aiErrorToast.visible = true
            aiErrorToastTimer.restart()
        }
    }

    // Cached view instances — created once, reused across switches
    property Item _tlViewInst:       null
    property Item _albumsViewInst:   null
    property Item _mapViewInst:      null
    property Item _settingsViewInst: null

    Component.onCompleted: {
        var isViewerOnly = (typeof STARTUP_FILE === "string" && STARTUP_FILE !== "")

        window._refreshPhotoCount()

        // In vieweronly mode the stack and sidebar are never shown — skip expensive view creation.
        // Other views are created lazily on first navigation to avoid blocking startup.
        if (!isViewerOnly) Qt.callLater(() => {
            _tlViewInst = timelineView.createObject(null)
            mainStack.replace(_tlViewInst, StackView.Immediate)
        })

        if (isViewerOnly) {
            // NOTE: the standalone viewer fast path is handled by ViewerWindow.qml
            // (a minimal window that skips the gallery backend entirely). This
            // branch only runs if main.qml is ever loaded with a startup file,
            // which the current main.cpp no longer does.
            var mime = ""
            var fp = STARTUP_FILE
            if (/\.(mp4|mkv|mov|avi|webm)$/i.test(fp)) mime = "video/mp4"
            else mime = "image/jpeg"
            viewerOnlyMode = true
            viewerOverlay.allItems = [{ file_path: fp, mime_type: mime, id: -1, is_favorite: false, is_trashed: false }]
            viewerOverlay.currentIndex = 0
            viewerOverlay.mediaData = viewerOverlay.allItems[0]
            viewerOverlay.active = true
        }
    }

    // ── AI document results panel ────────────────────────────────────────
    Rectangle {
        id: docResultsPanel
        visible: window._aiDocResults.length > 0 && window.currentView === "timeline" && !window.viewerOnlyMode
        anchors.left: parent.left
        anchors.leftMargin: sidebar.width + 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        z: 200
        height: visible ? 96 : 0
        radius: ThemeManager.radiusLg
        color: ThemeManager.surfaceContainerHigh

        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            Label {
                text: I18n.t(Settings.language, "documents_count").arg(window._aiDocResults.length)
                font.pixelSize: ThemeManager.fontLabelS; font.weight: Font.Medium
                color: ThemeManager.onSurfaceVariant
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: window._aiDocResults

                delegate: Rectangle {
                    required property var modelData
                    width: Math.min(220, docResultsPanel.width / 3 - 12)
                    height: 44
                    radius: ThemeManager.radiusMd
                    color: docHover.containsMouse
                        ? Qt.alpha(ThemeManager.primary, 0.12)
                        : Qt.alpha(ThemeManager.primary, 0.06)
                    Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        M3Icon {
                            name: modelData.name && modelData.name.endsWith(".pdf") ? "picture_as_pdf" : "description"
                            size: 20
                            color: ThemeManager.primary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: modelData.name || ""
                                font.pixelSize: ThemeManager.fontLabelM; font.weight: Font.Medium
                                color: ThemeManager.onSurface
                                elide: Text.ElideRight
                            }
                            Label {
                                text: Math.round((modelData.score || 0) * 100) + "% match"
                                font.pixelSize: 10
                                color: ThemeManager.onSurfaceVariant
                            }
                        }
                    }

                    MouseArea {
                        id: docHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally("file://" + modelData.file_path)
                    }
                }
            }
        }
    }

    // ── AI error toast ───────────────────────────────────────────────────
    Rectangle {
        id: aiErrorToast
        property string message: ""
        visible: false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        z: 9999
        width: Math.min(aiErrorLabel.implicitWidth + 48, parent.width * 0.85)
        height: 48; radius: ThemeManager.radiusSm
        color: ThemeManager.inverseSurface
        Label {
            id: aiErrorLabel
            anchors.centerIn: parent
            text: aiErrorToast.message
            font.pixelSize: ThemeManager.fontBodyM
            color: ThemeManager.inverseOnSurface
        }
        Timer {
            id: aiErrorToastTimer
            interval: 4000
            onTriggered: aiErrorToast.visible = false
        }
    }

    // ── Folder picker (FAB + Settings "Add directory") ───────────────────
    function openFolderPickerForSettings() { mainFolderPicker.open() }

    Platform.FolderDialog {
        id: mainFolderPicker
        title: "Choose a directory to scan"
        onAccepted: {
            var path = folder.toString().replace(/^file:\/\//, "")
            DB.addIndexedDirectory(path)
            FileScanner.startScan(path)
        }
    }

    // Scan state
    property bool isScanning: false
    property string scanFolder: ""
    property int scanFileCount: 0
    property bool scanDone: false

    // Thumbnail cache state
    property bool isThumbCaching: false
    property int  thumbCacheDone:  0
    property int  thumbCacheTotal: 0
    property bool thumbCacheDoneFlag: false

    Connections {
        target: ThumbGen
        function onThumbCachingChanged() {
            window.isThumbCaching = ThumbGen.thumbCaching
            if (!ThumbGen.thumbCaching && window.thumbCacheTotal > 0) {
                window.thumbCacheDoneFlag = true
                thumbCacheBannerTimer.restart()
            }
        }
        function onThumbCacheProgressChanged() {
            window.thumbCacheDone  = ThumbGen.thumbCacheDone
            window.thumbCacheTotal = ThumbGen.thumbCacheTotal
        }
        function onThumbCacheFinished() {
            window.thumbCacheDone = window.thumbCacheTotal
        }
    }

    Timer {
        id: thumbCacheBannerTimer
        interval: 3000
        onTriggered: window.thumbCacheDoneFlag = false
    }

    Connections {
        target: FileScanner
        function onScanStarted(path) {
            window.isScanning = true
            window.scanDone = false
            window.scanFolder = path
            window.scanFileCount = 0
            scanBannerTimer.stop()
        }
        function onScanProgress(count) {
            window.scanFileCount = count
        }
        function onScanFinished(paths, dirsScanned, duration, rootPath) {
            window.scanFileCount = paths.length
            window.isScanning = false
            window.scanDone = true
            scanBannerTimer.restart()
            window._refreshPhotoCount()
        }
    }

    Timer {
        id: scanBannerTimer
        interval: 3000
        onTriggered: window.scanDone = false
    }

    background: Rectangle {
        color: window.viewerOnlyMode ? "black" : ThemeManager.surface
        radius: window.viewerOnlyMode ? 0 : ThemeManager.radiusLg
        border.color: window.viewerOnlyMode ? "transparent" : Qt.alpha("black", 0.1)
        border.width: window.viewerOnlyMode ? 0 : 1
    }

    // Mouse back/forward buttons — navigate stack or viewer
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        propagateComposedEvents: true
        z: 9999
        onClicked: (mouse) => {
            if (mouse.button === Qt.BackButton) {
                if (viewerOverlay.active) {
                    viewerOverlay.navigatePrev()
                } else if (mainStack.depth > 1) {
                    mainStack.pop()
                    if (window.currentView === "hidden" || window.currentView === "trash" ||
                        window.currentView === "favorites") {
                        window.currentView = "timeline"
                        window.detailTitle = ""
                        TimelineModel.setFolderFilter("")
                        TimelineModel.setMimeFilter("")
                        TimelineModel.filterMode = 0
                    }
                }
            } else if (mouse.button === Qt.ForwardButton) {
                if (viewerOverlay.active) viewerOverlay.navigateNext()
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1 // For border
        spacing: 0
        visible: !window.viewerOnlyMode

        Sidebar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: width
            collapsed: window.sidebarCollapsed
            currentView: window.currentView
            onViewChanged: (view) => {
                if (view === "hidden") {
                    window._pendingView = "hidden"
                    passwordPrompt.open()
                    return
                }
                window.currentView = view
                window.detailTitle = ""
                TimelineModel.setFolderFilter("")

                var tl = window._tlViewInst

                if (view === "timeline") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.setMimeFilter("")
                    TimelineModel.filterMode = 0
                    window.applyViewSort("timeline")
                } else if (view === "videos") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.filterMode = 0
                    TimelineModel.setMimeFilter("video/")
                    window.applyViewSort("videos")
                } else if (view === "favorites") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.setMimeFilter("")
                    TimelineModel.filterMode = 1
                    window.applyViewSort("favorites")
                } else if (view === "trash") {
                    if (tl && mainStack.currentItem !== tl) mainStack.replace(tl)
                    TimelineModel.setMimeFilter("")
                    TimelineModel.filterMode = 2
                    window.applyViewSort("trash")
                } else if (view === "albums") {
                    if (!window._albumsViewInst) window._albumsViewInst = albumsView.createObject(null)
                    mainStack.replace(window._albumsViewInst)
                    window.applyViewSort("albums")
                } else if (view === "map") {
                    if (!window._mapViewInst) window._mapViewInst = mapView.createObject(null)
                    mainStack.replace(window._mapViewInst)
                } else if (view === "settings") {
                    if (!window._settingsViewInst) window._settingsViewInst = settingsView.createObject(null)
                    mainStack.replace(window._settingsViewInst)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Topbar
            Rectangle {
                id: topbar
                Layout.fillWidth: true
                height: 72
                color: ThemeManager.surface
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 16

                    // Sidebar toggle
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: foldHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                        M3Icon { anchors.centerIn: parent; name: window.sidebarCollapsed ? "menu" : "sidebar"; size: 24; color: ThemeManager.onSurfaceVariant }
                        MouseArea { id: foldHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.sidebarCollapsed = !window.sidebarCollapsed }
                    }

                    // Back button — Rectangle+MouseArea avoids Material style interference
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        visible: mainStack.depth > 1
                        color: backHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                        M3Icon { anchors.centerIn: parent; name: "arrow_back"; size: 24; color: ThemeManager.onSurfaceVariant }
                        MouseArea {
                            id: backHover
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mainStack.pop()
                                // If we were in a filtered view and there's nothing left to go back to,
                                // the stack top is now the real previous view — infer currentView from it.
                                if (window.currentView === "hidden" || window.currentView === "trash" ||
                                    window.currentView === "favorites") {
                                    // These views replace the whole stack; back here means we ended up
                                    // on a stale page — reset to a clean state.
                                    window.currentView = "timeline"
                                    window.detailTitle = ""
                                    TimelineModel.setFolderFilter("")
                                    TimelineModel.setMimeFilter("")
                                    TimelineModel.filterMode = 0
                                }
                            }
                        }
                    }

                    Column {
                        spacing: 2
                        Label {
                            text: {
                                var base = mainStack.depth > 1 && window.detailTitle !== ""
                                    ? window.detailTitle
                                    : (viewTitles[window.currentView] || "")
                                if (window.currentView === "timeline" && window._photoCount > 0)
                                    return base + " · " + window._photoCount.toLocaleString()
                                return base
                            }
                            font.family: "Roboto Flex"
                            font.pixelSize: 28
                            font.weight: Font.Medium
                            color: ThemeManager.onSurface
                        }
                        Label {
                            visible: mainStack.depth > 1 && window.detailTitle !== ""
                            text: viewTitles[window.currentView] || ""
                            font.pixelSize: 14
                            color: ThemeManager.onSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // ── Density button (mosaic columns) ───────────────────────
                    Rectangle {
                        id: densityBtn
                        readonly property var _views: ["timeline","videos","favorites","trash","hidden","albums"]
                        visible: _views.indexOf(window.currentView) >= 0
                        height: 48; width: 48
                        Layout.rightMargin: -8   // match the sort↔search gap (equal spacing)
                        radius: densityMenu.opened ? ThemeManager.radiusLg : 24
                        Behavior on radius { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        color: densityMenu.opened
                               ? Qt.alpha(ThemeManager.primary, 0.10)
                               : (densityBtnMA.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.06)
                                                             : ThemeManager.surfaceContainer)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        M3Icon {
                            anchors.centerIn: parent
                            name: "grid_view"; size: 20
                            color: densityMenu.opened ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        ToolTip.text: I18n.t(Settings.language, "mosaic_density")
                        ToolTip.visible: densityBtnMA.containsMouse && !densityMenu.opened
                        ToolTip.delay: 500

                        MouseArea {
                            id: densityBtnMA
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: densityMenu.popup(densityBtn, 0, densityBtn.height + 4)
                        }

                        M3Menu {
                            id: densityMenu
                            M3MenuItem { text: I18n.t(Settings.language, "density_dense");       checkable: true; checked: Settings.mosaicDensity === 1; onTriggered: Settings.mosaicDensity = 1 }
                            M3MenuItem { text: I18n.t(Settings.language, "density_compact");     checkable: true; checked: Settings.mosaicDensity === 2; onTriggered: Settings.mosaicDensity = 2 }
                            M3MenuItem { text: I18n.t(Settings.language, "density_comfortable"); checkable: true; checked: Settings.mosaicDensity === 3; onTriggered: Settings.mosaicDensity = 3 }
                            M3MenuItem { text: I18n.t(Settings.language, "density_spacious");    checkable: true; checked: Settings.mosaicDensity === 4; onTriggered: Settings.mosaicDensity = 4 }
                        }
                    }

                    // ── Sort button (pill matching the search bar) ────────────
                    Rectangle {
                        id: sortBtn
                        readonly property var _sortableViews: ["timeline","videos","favorites","trash","hidden","albums"]
                        visible: _sortableViews.indexOf(window.currentView) >= 0
                        height: 48
                        // Squares off when active/open (a pressed-in "toggled on" look).
                        radius: sortMenu.opened ? ThemeManager.radiusLg : 24
                        Behavior on radius { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        width: sortRow.implicitWidth + 36
                        // Sit closer to the search bar (trim the inter-item gap).
                        Layout.rightMargin: -8
                        color: sortMenu.opened
                               ? Qt.alpha(ThemeManager.primary, 0.10)
                               : (sortBtnMA.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.06)
                                                          : ThemeManager.surfaceContainer)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: sortRow
                            anchors.centerIn: parent
                            spacing: 8

                            M3Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "sort"
                                size: 20
                                color: sortMenu.opened ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t(Settings.language, "sort_by")
                                font.pixelSize: 16
                                color: sortMenu.opened ? ThemeManager.primary : ThemeManager.onSurface
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        MouseArea {
                            id: sortBtnMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sortMenu.popup(sortBtn, 0, sortBtn.height + 4)
                        }

                        // ── Primary sort menu (reusable SortMenu component) ───
                        SortMenu {
                            id: sortMenu
                            readonly property bool _alb: window.currentView === "albums"

                            // Most views share one field set; albums get their own.
                            readonly property var _mediaFields: [
                                { key: 0, label: I18n.t(Settings.language, "k_date_taken") },
                                { key: 1, label: I18n.t(Settings.language, "k_date_modified") },
                                { key: 2, label: I18n.t(Settings.language, "k_name") },
                                { key: 3, label: I18n.t(Settings.language, "k_size") },
                                { key: 5, label: I18n.t(Settings.language, "k_type") },
                                { key: 4, label: I18n.t(Settings.language, "k_last_viewed") },
                                { key: 8, label: I18n.t(Settings.language, "k_dimensions") },
                                { key: 6, label: I18n.t(Settings.language, "k_width") },
                                { key: 7, label: I18n.t(Settings.language, "k_height") },
                                { key: 9, label: I18n.t(Settings.language, "k_orientation") }
                            ]
                            readonly property var _albumFields: [
                                { key: 0, label: I18n.t(Settings.language, "k_name") },
                                { key: 1, label: I18n.t(Settings.language, "k_item_count") },
                                { key: 2, label: I18n.t(Settings.language, "k_size") }
                            ]

                            fields:     _alb ? _albumFields : _mediaFields
                            currentKey: _alb ? AlbumModel.sortRole  : TimelineModel.sortRole
                            ascending:  (_alb ? AlbumModel.sortOrder : TimelineModel.sortOrder) === 1

                            // Text fields read "A → Z / Z → A"; everything else Ascending/Descending.
                            readonly property bool _textKey: _alb ? (currentKey === 0)
                                                                  : (currentKey === 2 || currentKey === 5)
                            ascLabel:  _textKey ? I18n.t(Settings.language, "sort_az") : I18n.t(Settings.language, "sort_ascending")
                            descLabel: _textKey ? I18n.t(Settings.language, "sort_za") : I18n.t(Settings.language, "sort_descending")

                            // Use property assignment (not setSortRole(): on TimelineModel
                            // that's a plain WRITE accessor, not Q_INVOKABLE, so calling it
                            // as a function silently fails — which is why timeline sorting
                            // never took effect while albums did).
                            onPick: (key) => {
                                if (_alb) AlbumModel.sortRole = key; else TimelineModel.sortRole = key
                                DB.setSortPref(window.currentView, key,
                                               (_alb ? AlbumModel.sortOrder : TimelineModel.sortOrder))
                            }
                            onOrderPicked: (asc) => {
                                var o = asc ? 1 : 0
                                if (_alb) AlbumModel.sortOrder = o; else TimelineModel.sortOrder = o
                                DB.setSortPref(window.currentView,
                                               (_alb ? AlbumModel.sortRole : TimelineModel.sortRole), o)
                            }

                            // ── Type filter — a real Qt submenu (cascade is managed
                            //    as one focus unit, so it no longer fights the parent). ──
                            MenuSeparator {
                                visible: ["timeline","favorites"].indexOf(window.currentView) >= 0
                                height: visible ? implicitHeight : 0
                            }
                            M3Menu {
                                id: typeMenu
                                title: I18n.t(Settings.language, "filter_by_type")
                                enabled: ["timeline","favorites"].indexOf(window.currentView) >= 0
                                property var _types: []
                                onAboutToShow: _types = TimelineModel.getAvailableMimeTypes()

                                M3MenuItem {
                                    text: I18n.t(Settings.language, "filter_all_types")
                                    checkable: true
                                    checked: TimelineModel.mimeFilter === ""
                                    onTriggered: TimelineModel.setMimeFilter("")
                                }
                                M3MenuSeparator {}

                                Instantiator {
                                    model: typeMenu._types
                                    delegate: M3MenuItem {
                                        required property string modelData
                                        text: {
                                            var m = {
                                                "image/jpeg":"JPEG","image/png":"PNG","image/gif":"GIF",
                                                "image/webp":"WebP","image/heic":"HEIC","image/heif":"HEIF",
                                                "image/tiff":"TIFF","image/bmp":"BMP","image/avif":"AVIF",
                                                "image/x-canon-cr2":"Canon RAW","image/x-nikon-nef":"Nikon RAW",
                                                "image/x-sony-arw":"RAW","image/x-adobe-dng":"DNG","video/mp4":"MP4",
                                                "video/quicktime":"MOV","video/x-msvideo":"AVI",
                                                "video/webm":"WebM","video/x-matroska":"MKV"
                                            }
                                            return m[modelData] || modelData.split("/").pop().toUpperCase()
                                        }
                                        checkable: true
                                        checked: TimelineModel.mimeFilter === modelData
                                        onTriggered: TimelineModel.setMimeFilter(modelData)
                                    }
                                    onObjectAdded: (index, obj) => typeMenu.insertItem(index + 2, obj)
                                    onObjectRemoved: (index, obj) => typeMenu.removeItem(obj)
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: searchPill
                        property bool _aiMode: false
                        property bool _aiSearching: false
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: searchField.forceActiveFocus()
                        }
                        width: 360
                        height: 48
                        radius: 24
                        color: searchPill._aiMode
                            ? Qt.alpha(ThemeManager.primary, 0.08)
                            : ThemeManager.surfaceContainer
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            spacing: 12

                            M3Icon {
                                name: searchPill._aiMode ? "auto_awesome" : "search"
                                size: 20
                                color: searchPill._aiMode ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Item {
                                Layout.fillWidth: true
                                height: 28

                                Text {
                                    anchors.fill: parent
                                    text: searchPill._aiMode
                                        ? I18n.t(Settings.language, "ai_search_placeholder")
                                        : I18n.t(Settings.language, "search_placeholder")
                                    color: ThemeManager.onSurfaceVariant
                                    font.pixelSize: 16
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchField.text.length === 0
                                }

                                TextInput {
                                    id: searchField
                                    objectName: "searchField"
                                    anchors.fill: parent
                                    color: ThemeManager.onSurface
                                    font.pixelSize: 16
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    onTextChanged: {
                                        if (!searchPill._aiMode) {
                                            TimelineModel.setSearchFilter(text)
                                            AlbumModel.setSearchFilter(text)
                                        }
                                    }
                                    Keys.onReturnPressed: {
                                        if (searchPill._aiMode && text.length > 0) {
                                            searchPill._aiSearching = true
                                            AI.searchByText(text)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: searchField.text !== ""
                                width: 28; height: 28; radius: 14
                                color: clearHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                                M3Icon { anchors.centerIn: parent; name: "close"; size: 18; color: ThemeManager.onSurfaceVariant }
                                MouseArea {
                                    id: clearHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchField.text = ""
                                        if (searchPill._aiMode) TimelineModel.clearAiFilter()
                                    }
                                }
                            }

                            Rectangle {
                                id: aiToggleBtn
                                width: 32; height: 32; radius: 16
                                color: searchPill._aiMode
                                    ? Qt.alpha(ThemeManager.primary, 0.18)
                                    : (aiToggleHover.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }
                                M3Icon {
                                    anchors.centerIn: parent
                                    name: "auto_awesome"
                                    size: 18
                                    color: searchPill._aiMode ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    id: aiToggleHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchPill._aiMode = !searchPill._aiMode
                                        if (!searchPill._aiMode) {
                                            searchPill._aiSearching = false
                                            TimelineModel.clearAiFilter()
                                            window._aiDocResults = []
                                            TimelineModel.setSearchFilter(searchField.text)
                                            AlbumModel.setSearchFilter(searchField.text)
                                        } else {
                                            TimelineModel.setSearchFilter("")
                                            AlbumModel.setSearchFilter("")
                                            // Auto-load the model when AI mode is enabled
                                            if (!AI.ready && !AI.loading && AI.modelsPresent)
                                                AI.loadModel()
                                        }
                                        searchField.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Content Stack
            StackView {
                id: mainStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: timelineView
                
                pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
                pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
                popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
                popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
                replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
                replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
            }
        }
    }
    
    // Timeline FAB — two-part: Refresh left, Add directory right
    Row {
        id: fabRow
        visible: !window.viewerOnlyMode && window.currentView === "timeline"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        z: 10
        spacing: 8

        // Left FAB — Refresh (icon always centered in 56px, label fades in to the right)
        Rectangle {
            id: fabRefresh
            property bool hovered: fabRefreshMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + refreshLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "sync"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: refreshLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "refresh_library")
                font.weight: Font.Medium; font.pixelSize: ThemeManager.fontBodyM; color: ThemeManager.onPrimaryContainer
                opacity: fabRefresh.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: fabRefreshMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var dirs = DB.getIndexedDirectories()
                    for (var i = 0; i < dirs.length; i++) {
                        var p = dirs[i].path || ""
                        if (p) FileScanner.startScan(p)
                    }
                }
            }
        }

        // Right FAB — Add directory
        Rectangle {
            id: fabAdd
            property bool hovered: fabAddMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + addLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "add"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: addLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "add_directory")
                font.weight: Font.Medium; font.pixelSize: ThemeManager.fontBodyM; color: ThemeManager.onPrimaryContainer
                opacity: fabAdd.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: fabAddMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: mainFolderPicker.open()
            }
        }
    }

    // Trash FAB — Empty trash (bottom-right, only in trash view)
    Row {
        id: trashFabRow
        visible: !window.viewerOnlyMode && window.currentView === "trash"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        z: 10

        Rectangle {
            id: fabEmptyTrash
            property bool hovered: fabEmptyTrashMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + emptyTrashLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.errorContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "delete_forever"; size: 24; color: ThemeManager.onErrorContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: emptyTrashLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "empty_trash")
                font.weight: Font.Medium; font.pixelSize: ThemeManager.fontBodyM; color: ThemeManager.onErrorContainer
                opacity: fabEmptyTrash.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: fabEmptyTrashMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    DB.emptyTrash()
                    TimelineModel.refresh()
                }
            }
        }
    }

    // Albums FAB — refresh left, new album right
    Row {
        id: albumFabRow
        visible: !window.viewerOnlyMode && window.currentView === "albums"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        z: 10
        spacing: 8

        Rectangle {
            id: fabAlbumRefresh
            property bool hovered: fabAlbumRefreshMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + albumRefreshLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "sync"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: albumRefreshLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "refresh_library")
                font.weight: Font.Medium; font.pixelSize: ThemeManager.fontBodyM; color: ThemeManager.onPrimaryContainer
                opacity: fabAlbumRefresh.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            MouseArea {
                id: fabAlbumRefreshMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: AlbumModel.refresh()
            }
        }

        Rectangle {
            id: fabAlbumNew
            property bool hovered: fabAlbumNewMa.containsMouse
            height: 56
            width: hovered ? 16 + 24 + 10 + albumNewLabel.implicitWidth + 16 : 56
            radius: 16
            color: ThemeManager.primaryContainer
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

            M3Icon {
                name: "add"; size: 24; color: ThemeManager.onPrimaryContainer
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: albumNewLabel
                anchors.left: parent.left; anchors.leftMargin: 16 + 24 + 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t(Settings.language, "new_album")
                font.weight: Font.Medium; font.pixelSize: ThemeManager.fontBodyM; color: ThemeManager.onPrimaryContainer
                opacity: fabAlbumNew.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            MouseArea {
                id: fabAlbumNewMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: newAlbumModal.open()
            }
        }
    }

    AlbumEditModal {
        id: newAlbumModal
        parent: Overlay.overlay
        onSaved: AlbumModel.refresh()
    }

    readonly property var viewTitles: ({
        "timeline":  I18n.t(Settings.language, "timeline"),
        "albums":    I18n.t(Settings.language, "albums"),
        "videos":    I18n.t(Settings.language, "videos"),
        "map":       I18n.t(Settings.language, "places"),
        "favorites": I18n.t(Settings.language, "favorites"),
        "hidden":    I18n.t(Settings.language, "hidden"),
        "trash":     I18n.t(Settings.language, "trash"),
        "settings":  I18n.t(Settings.language, "settings")
    })

    Component {
        id: timelineView
        MediaGrid {
            // Restore saved scroll when the grid is created (view switch back)
            Component.onCompleted: {
                if (window.timelineScrollY > 0)
                    Qt.callLater(() => { _savedY = window.timelineScrollY; _pendingRestore = true; restoreTimer.restart() })
            }
            // Save scroll position when this instance is about to be destroyed
            Component.onDestruction: window.timelineScrollY = _savedY

            onOpenViewer: (data, idx) => {
                viewerOverlay.mediaData = data
                viewerOverlay.currentIndex = idx
                viewerOverlay.allItems = TimelineModel.getFlatMediaList()
                viewerOverlay.active = true
            }
        }
    }

    Component {
        id: albumsView
        AlbumListView {
            onOpenAlbum: (folderPath, albumName) => {
                window.detailTitle = albumName
                var detail = mainStack.push(Qt.resolvedUrl("views/AlbumDetailView.qml"), {
                    folderPath: folderPath,
                    albumName: albumName
                })
                detail.openViewer.connect(function(data, idx) {
                    viewerOverlay.mediaData = data
                    viewerOverlay.currentIndex = idx
                    viewerOverlay.allItems = TimelineModel.getFlatMediaList()
                    viewerOverlay.active = true
                })
            }
        }
    }

    Component {
        id: mapView
        MapView {
            onOpenViewer: (data) => {
                viewerOverlay.mediaData = data
                viewerOverlay.currentIndex = 0
                viewerOverlay.allItems = [data]
                viewerOverlay.active = true
            }
        }
    }

    Component {
        id: settingsView
        SettingsView {}
    }

    // Scan progress banner
    Rectangle {
        id: scanBanner
        visible: window.isScanning || window.scanDone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 50
        width: Math.min(560, parent.width - 48)
        height: 64
        radius: 20
        color: window.scanDone ? ThemeManager.primaryContainer : ThemeManager.inverseSurface

        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
        transform: Translate { y: scanBanner.visible ? 0 : 24 }

        // Animated scan indicator bar (only while scanning)
        Rectangle {
            visible: window.isScanning
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 10
            height: 3
            radius: 1.5
            color: Qt.alpha(ThemeManager.inverseOnSurface, 0.2)

            Rectangle {
                id: progressPill
                height: parent.height
                width: 80
                radius: parent.radius
                color: ThemeManager.inverseOnSurface
                SequentialAnimation on x {
                    running: window.isScanning
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: scanBanner.width - 112; duration: 1200; easing.type: Easing.InOutQuart }
                    NumberAnimation { from: scanBanner.width - 112; to: 0; duration: 1200; easing.type: Easing.InOutQuart }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: window.isScanning ? 16 : 0
            spacing: 12

            M3Icon {
                name: window.scanDone ? "check" : "schedule"
                size: 20
                color: window.scanDone ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface
            }

            Column {
                Layout.fillWidth: true
                spacing: 1
                Label {
                    text: window.scanDone
                        ? "Scan complete — " + window.scanFileCount.toLocaleString() + " files found"
                        : "Scanning " + window.scanFolder.replace(Settings.homePath, "~")
                    color: window.scanDone ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface
                    font.pixelSize: ThemeManager.fontLabelL
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    visible: window.isScanning
                    text: window.scanFileCount.toLocaleString() + " media files found so far…"
                    color: Qt.alpha(window.scanDone ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface, 0.7)
                    font.pixelSize: 11
                }
            }
        }
    }

    // Thumbnail cache progress banner
    Rectangle {
        id: thumbCacheBanner
        visible: window.isThumbCaching || window.thumbCacheDoneFlag
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: scanBanner.visible ? scanBanner.top : parent.bottom
        anchors.bottomMargin: scanBanner.visible ? 8 : 24
        z: 50
        width: Math.min(560, parent.width - 48)
        height: 64
        radius: 20
        color: window.thumbCacheDoneFlag ? ThemeManager.primaryContainer : ThemeManager.inverseSurface

        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0] } }
        transform: Translate { y: thumbCacheBanner.visible ? 0 : 24 }

        // Deterministic progress bar (fills left → right)
        Rectangle {
            visible: window.isThumbCaching && window.thumbCacheTotal > 0
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.bottomMargin: 10
            height: 3; radius: 1.5
            color: Qt.alpha(ThemeManager.inverseOnSurface, 0.2)

            Rectangle {
                height: parent.height; radius: parent.radius
                color: ThemeManager.inverseOnSurface
                width: window.thumbCacheTotal > 0
                    ? parent.width * Math.min(1, window.thumbCacheDone / window.thumbCacheTotal)
                    : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16; anchors.rightMargin: 16
            anchors.bottomMargin: window.isThumbCaching ? 16 : 0
            spacing: 12

            M3Icon {
                name: window.thumbCacheDoneFlag ? "check" : "photo_library"
                size: 20
                color: window.thumbCacheDoneFlag ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface
            }

            Column {
                Layout.fillWidth: true
                spacing: 1
                Label {
                    text: window.thumbCacheDoneFlag
                        ? "Thumbnail cache ready"
                        : "Generating thumbnail cache"
                    color: window.thumbCacheDoneFlag ? ThemeManager.onPrimaryContainer : ThemeManager.inverseOnSurface
                    font.pixelSize: ThemeManager.fontLabelL; font.weight: Font.Medium
                    elide: Text.ElideRight; width: parent.width
                }
                Label {
                    visible: window.isThumbCaching
                    text: window.thumbCacheDone.toLocaleString() + " / " + window.thumbCacheTotal.toLocaleString()
                    color: Qt.alpha(ThemeManager.inverseOnSurface, 0.7)
                    font.pixelSize: 11
                }
            }
        }
    }

    PasswordPrompt {
        id: passwordPrompt
        parent: Overlay.overlay
        anchors.fill: parent
        onAccepted: {
            window._pendingView = ""
            window.currentView = "hidden"
            window.detailTitle = ""
            TimelineModel.setFolderFilter("")
            TimelineModel.setMimeFilter("")
            TimelineModel.filterMode = 3
            window.applyViewSort("hidden")
            // Clear any sub-pages so back button never appears inside Hidden
            while (mainStack.depth > 1)
                mainStack.pop(null, StackView.Immediate)
            mainStack.replace(timelineView)
        }
        onRejected: { window._pendingView = "" }
    }

    ViewerOverlay {
        id: viewerOverlay
        parent: Overlay.overlay
        anchors.fill: parent
        viewerOnlyMode: window.viewerOnlyMode
    }
}
