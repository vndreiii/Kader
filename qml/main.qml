import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import "components"
import "views"
import "I18n.js" as I18n
import "Paths.js" as Paths

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

    // Places view: swaps between the 3D globe and the classic 2D map
    // depending on Settings.use3DGlobe, lazily instantiating whichever is needed.
    function _activatePlacesView() {
        var inst
        if (Settings.use3DGlobe) {
            if (!window._globeViewInst) window._globeViewInst = window._fitStack(globeView.createObject(null))
            inst = window._globeViewInst
        } else {
            if (!window._mapViewInst) {
                // Loaded by URL so QtLocation is only pulled in when the classic
                // map is actually used (and is optional at runtime).
                var comp = Qt.createComponent("qrc:/Kader/qml/views/MapView.qml")
                if (comp.status === Component.Ready) {
                    window._mapViewInst = window._fitStack(comp.createObject(null))
                    window._mapViewInst.openViewer.connect(window._openPlaceItems)
                } else {
                    console.warn("2D map unavailable (QtLocation missing?):", comp.errorString())
                }
            }
            inst = window._mapViewInst
            if (!inst) {
                if (!window._globeViewInst) window._globeViewInst = window._fitStack(globeView.createObject(null))
                inst = window._globeViewInst
            }
        }
        mainStack.replace(inst)
    }
    Connections {
        target: Settings
        function onUse3DGlobeChanged() {
            if (window.currentView === "map") window._activatePlacesView()
        }
    }

    property var _aiDocResults: []

    // Search tab (people, memories, places, things, colours + unified search)
    property Item _searchViewInst: null
    function _activateSearchView() {
        if (!window._searchViewInst) window._searchViewInst = window._fitStack(searchView.createObject(null))
        if (mainStack.currentItem !== window._searchViewInst) mainStack.replace(window._searchViewInst)
    }
    // Sidebar navigation (also used by views that link to another tab)
    function switchView(view) {
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
            if (!window._albumsViewInst) window._albumsViewInst = window._fitStack(albumsView.createObject(null))
            mainStack.replace(window._albumsViewInst)
            window.applyViewSort("albums")
        } else if (view === "search") {
            window._activateSearchView()
        } else if (view === "map") {
            window._activatePlacesView()
        } else if (view === "settings") {
            if (!window._settingsViewInst) window._settingsViewInst = window._fitStack(settingsView.createObject(null))
            mainStack.replace(window._settingsViewInst)
        }
    }

    // Views created once and reused across tab switches must track the stack's
    // size themselves: StackView only resizes items whose size it set the
    // first time, and on the second push it takes its own earlier size for an
    // explicit one — so a reused view kept the window's old size (cut off
    // after maximising).
    function _fitStack(item) {
        if (!item) return item
        item.width = Qt.binding(function () { return mainStack.width })
        item.height = Qt.binding(function () { return mainStack.height })
        return item
    }

    // Leave a pushed page (album detail …) — the top bar's back arrow.
    function popPage() {
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

    // Esc is "back" everywhere, one step at a time. Popups and menus close
    // themselves on Esc (the shortcut below is blocked while one is open);
    // everything else goes through here, innermost first:
    //   viewer → whatever has focus (inline rename, a text field) → the
    //   current page's own steps (selection, place card, sub-page, search
    //   text) → a pushed page → back to the gallery.
    // A view takes part by defining handleBack(), returning true when it
    // consumed the press.
    // ── predictive back (emulated on desktop) ──────────────────────────────
    // A back gesture (mouse back button held, touchpad swipe right) shows a
    // preview: the page shrinks and slides right. Past halfway it commits —
    // the page finishes leaving and the previous one grows back in;
    // otherwise it springs back. Esc plays the arrival half.
    property real _backProgress: 0
    property bool _backDragging: false
    Behavior on _backProgress {
        enabled: !window._backDragging
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }
    function _canBack() {
        return !viewerOverlay.active && (mainStack.depth > 1 || window.currentView !== "timeline"
            || (window._searchViewInst && mainStack.currentItem === window._searchViewInst && window._searchViewInst.subDepth > 1))
    }
    function _pageKey() {
        return mainStack.depth + "|" + window.currentView + "|"
            + (window._searchViewInst ? window._searchViewInst.subDepth : 0)
    }
    // the page that just came back grows in from where the old one left
    function _arrive() {
        window._backDragging = true
        window._backProgress = 0.3
        window._backDragging = false
        window._backProgress = 0
    }
    function backWithMotion() {
        var before = _pageKey()
        goBack()
        if (_pageKey() !== before) _arrive()
    }
    function _finishBackGesture() {
        if (window._backProgress > 0.5) {
            backCommit.start()
        } else {
            window._backDragging = false
            window._backProgress = 0
        }
    }
    SequentialAnimation {
        id: backCommit
        NumberAnimation { target: window; property: "_backProgress"; to: 1; duration: 110; easing.type: Easing.InCubic }
        ScriptAction {
            script: {
                window.goBack()
                window._arrive()
            }
        }
    }

    function goBack() {
        if (viewerOverlay.active) { viewerOverlay.handleBack(); return }
        var f = window.activeFocusItem
        for (var p = f; p; p = p.parent)
            if (typeof p.handleBack === "function" && p.handleBack()) return
        if (f && f.cursorPosition !== undefined && f.activeFocus) {
            // a text field: the top search clears first; an empty field just
            // lets go of focus and the press carries on going back
            if (f === searchField && searchField.text.length > 0) { searchField.text = ""; return }
            mainStack.forceActiveFocus()
        }
        if (searchPill._aiMode) { searchField.text = ""; window.exitAiSearch(); return }
        var cur = mainStack.currentItem
        if (cur && typeof cur.handleBack === "function" && cur.handleBack()) return
        if (mainStack.depth > 1) { window.popPage(); return }
        if (window.currentView !== "timeline") window.switchView("timeline")
    }

    // The top bar's sparkle: smart-search the gallery for what's typed (the
    // results replace the grid until cleared). With nothing typed it toggles
    // AI mode, so Enter searches by meaning instead of by file name. Without
    // the AI models it falls back to the Search tab.
    function runAiSearch(q) {
        q = (q || "").trim()
        if (!AI.modelsPresent) {
            searchField.text = ""
            window.openSearch(q)
            return
        }
        if (q.length === 0) {
            searchPill._aiMode = !searchPill._aiMode
            if (!searchPill._aiMode) { TimelineModel.clearAiFilter(); window._aiDocResults = [] }
            searchField.forceActiveFocus()
            return
        }
        if (!AI.ready && !AI.loading) AI.loadModel()
        if (["timeline", "videos", "favorites"].indexOf(window.currentView) < 0) window.switchView("timeline")
        TimelineModel.setSearchFilter("")
        AlbumModel.setSearchFilter("")
        searchPill._aiMode = true
        searchPill._aiSearching = true
        AI.searchByText(q)
    }
    function exitAiSearch() {
        searchPill._aiMode = false
        searchPill._aiSearching = false
        TimelineModel.clearAiFilter()
        window._aiDocResults = []
    }
    Connections {
        target: AI
        function onSearchFinished(results) {
            if (!searchPill._aiSearching) return
            searchPill._aiSearching = false
            var ids = [], docs = []
            for (var i = 0; i < results.length; i++) {
                if (results[i].type === "doc") docs.push(results[i])
                else ids.push(results[i].id)
            }
            TimelineModel.setAiFilter(ids)
            window._aiDocResults = docs
        }
        function onEngineError(msg) { searchPill._aiSearching = false }
    }

    // From the top bar: open the Search tab with `q` (and search it now)
    function openSearch(q) {
        window.currentView = "search"
        window.detailTitle = ""
        window._activateSearchView()
        window._searchViewInst.setQuery(q || "")
    }

    // Open the viewer on every photo of a place (globe / map pin cards).
    function _openPlaceItems(data, items) {
        var list = (items && items.length > 0) ? items : [data]
        var idx = 0
        for (var i = 0; i < list.length; i++)
            if (list[i].id === data.id) { idx = i; break }
        viewerOverlay.allItems = list
        viewerOverlay.currentIndex = idx
        viewerOverlay.mediaData = list[idx]
        viewerOverlay.active = true
    }

    FontLoader {
        id: materialSymbolsFont
        source: "qrc:/Kader/assets/MaterialSymbolsRounded.ttf"
    }
    Connections {
        target: AI
        function onEngineError(msg) {
            searchPill._aiSearching = false
            aiErrorToast.message = msg
            aiErrorToast.visible = true
            aiErrorToastTimer.restart()
        }
    }

    // Frameless window: drag from empty header space (under everything)…
    WindowChrome { z: -1; edges: false; moveAreaHeight: 76 }
    // …and resize from the edges (above everything). Needed on Wayland,
    // where only the compositor may move or resize windows.
    WindowChrome { z: 100000; move: false }

    // Cached view instances — created once, reused across switches
    property Item _tlViewInst:       null
    property Item _albumsViewInst:   null
    property Item _mapViewInst:      null
    property Item _globeViewInst:    null
    property Item _settingsViewInst: null

    Component.onCompleted: {
        var isViewerOnly = (typeof STARTUP_FILE === "string" && STARTUP_FILE !== "")

        window._refreshPhotoCount()

        // The timeline is created here, not as the StackView's initialItem:
        // StackView destroys items it created itself as soon as they are
        // replaced, so after the first visit to Search, Map or Settings the
        // Gallery view was gone and its sidebar entry did nothing. Created
        // once at the stack's size (so the grid lays out once) and pushed as
        // an object, it survives every view switch. Other views are still
        // created lazily on first navigation.
        if (!isViewerOnly) {
            _tlViewInst = window._fitStack(timelineView.createObject(null))
            mainStack.push(_tlViewInst, {}, StackView.Immediate)
        }

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
                        onClicked: Qt.openUrlExternally(Paths.fileUrl(modelData.file_path))
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
            var path = Paths.localPath(folder)
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
        function onScanFinished(fileCount, dirsScanned, duration, rootPath) {
            window.scanFileCount = fileCount
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

    // Mouse back/forward buttons. In the viewer: previous / next photo.
    // Elsewhere back is predictive: hold to preview, release to go.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        z: 9999
        onPressed: (mouse) => {
            if (mouse.button === Qt.ForwardButton) {
                if (viewerOverlay.active) viewerOverlay.navigateNext()
                return
            }
            if (viewerOverlay.active) { viewerOverlay.navigatePrev(); return }
            if (!window._canBack()) { window.backWithMotion(); return }
            window._backDragging = false
            window._backProgress = 0.6
        }
        onReleased: (mouse) => {
            if (mouse.button === Qt.BackButton && window._backProgress > 0) backCommit.start()
        }
        onCanceled: { window._backDragging = false; window._backProgress = 0 }
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
            onViewChanged: (view) => window.switchView(view)
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
                            onClicked: window.popPage()
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

                    // ── View button: layout (mosaic / grid / list) + size ─────
                    Rectangle {
                        id: densityBtn
                        readonly property var _views: ["timeline","videos","favorites","trash","hidden","albums"]
                        // layouts apply to the photo views; albums only have sizes
                        readonly property bool _layouts: window.currentView !== "albums"
                        readonly property var _layoutIcons: ["view_quilt", "grid_view", "view_list"]
                        visible: _views.indexOf(window.currentView) >= 0
                        height: 48; width: 48
                        Layout.rightMargin: -8   // match the sort↔search gap (equal spacing)
                        radius: densityMenu.opened ? ThemeManager.radiusLg : 24
                        Behavior on radius { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        // state layer on top of the container (not instead of it), so
                        // hovering darkens nothing and the neighbour never looks lit
                        color: densityMenu.opened
                               ? Qt.alpha(ThemeManager.primary, 0.10)
                               : (densityBtnMA.containsMouse ? Qt.tint(ThemeManager.surfaceContainer, Qt.alpha(ThemeManager.onSurface, 0.08))
                                                             : ThemeManager.surfaceContainer)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            name: densityBtn._layoutIcons[densityBtn._layouts ? Settings.galleryLayout : 1]
                            size: 22
                            color: densityMenu.opened ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        ToolTip.text: I18n.t(Settings.language, "view_options")
                        ToolTip.visible: densityBtnMA.containsMouse && !densityMenu.opened
                        ToolTip.delay: 500

                        MouseArea {
                            id: densityBtnMA
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: densityMenu.popup(densityBtn, 0, densityBtn.height + 4)
                        }

                        M3Menu {
                            id: densityMenu
                            M3MenuItem { visible: densityBtn._layouts; height: visible ? implicitHeight : 0; iconName: "view_quilt"; text: I18n.t(Settings.language, "layout_mosaic"); checkable: true; checked: Settings.galleryLayout === 0; onTriggered: Settings.galleryLayout = 0 }
                            M3MenuItem { visible: densityBtn._layouts; height: visible ? implicitHeight : 0; iconName: "grid_view";  text: I18n.t(Settings.language, "layout_grid");   checkable: true; checked: Settings.galleryLayout === 1; onTriggered: Settings.galleryLayout = 1 }
                            M3MenuItem { visible: densityBtn._layouts; height: visible ? implicitHeight : 0; iconName: "view_list";  text: I18n.t(Settings.language, "layout_list");   checkable: true; checked: Settings.galleryLayout === 2; onTriggered: Settings.galleryLayout = 2 }
                            M3MenuSeparator { visible: densityBtn._layouts; height: visible ? implicitHeight : 0 }
                            M3MenuItem { iconName: "density_small";  text: I18n.t(Settings.language, "density_dense");       checkable: true; checked: Settings.mosaicDensity === 1; onTriggered: Settings.mosaicDensity = 1 }
                            M3MenuItem { iconName: "density_medium"; text: I18n.t(Settings.language, "density_compact");     checkable: true; checked: Settings.mosaicDensity === 2; onTriggered: Settings.mosaicDensity = 2 }
                            M3MenuItem { iconName: "density_large";  text: I18n.t(Settings.language, "density_comfortable"); checkable: true; checked: Settings.mosaicDensity === 3; onTriggered: Settings.mosaicDensity = 3 }
                            M3MenuItem { iconName: "crop_square";    text: I18n.t(Settings.language, "density_spacious");    checkable: true; checked: Settings.mosaicDensity === 4; onTriggered: Settings.mosaicDensity = 4 }
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
                               : (sortBtnMA.containsMouse ? Qt.tint(ThemeManager.surfaceContainer, Qt.alpha(ThemeManager.onSurface, 0.08))
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
                                { key: 0, label: I18n.t(Settings.language, "k_date_taken"), icon: "photo_camera" },
                                { key: 1, label: I18n.t(Settings.language, "k_date_modified"), icon: "edit_calendar" },
                                { key: 2, label: I18n.t(Settings.language, "k_name"), icon: "sort_by_alpha" },
                                { key: 3, label: I18n.t(Settings.language, "k_size"), icon: "straighten" },
                                { key: 5, label: I18n.t(Settings.language, "k_type"), icon: "category" },
                                { key: 4, label: I18n.t(Settings.language, "k_last_viewed"), icon: "visibility" },
                                { key: 8, label: I18n.t(Settings.language, "k_dimensions"), icon: "aspect_ratio" },
                                { key: 6, label: I18n.t(Settings.language, "k_width"), icon: "width" },
                                { key: 7, label: I18n.t(Settings.language, "k_height"), icon: "height" },
                                { key: 9, label: I18n.t(Settings.language, "k_orientation"), icon: "crop_rotate" }
                            ]
                            readonly property var _albumFields: [
                                { key: 0, label: I18n.t(Settings.language, "k_name"), icon: "sort_by_alpha" },
                                { key: 1, label: I18n.t(Settings.language, "k_item_count"), icon: "tag" },
                                { key: 2, label: I18n.t(Settings.language, "k_size"), icon: "straighten" }
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
                            M3MenuSeparator {
                                visible: ["timeline","favorites"].indexOf(window.currentView) >= 0
                                height: visible ? implicitHeight : 0
                            }
                            M3Menu {
                                id: typeMenu
                                title: I18n.t(Settings.language, "filter_by_type")
                                iconName: "filter_alt"
                                enabled: ["timeline","favorites"].indexOf(window.currentView) >= 0
                                property var _types: []
                                onAboutToShow: _types = TimelineModel.availableTypes()

                                M3MenuItem {
                                    iconName: "filter_list"
                                    text: I18n.t(Settings.language, "filter_all_types")
                                    checkable: true
                                    checked: TimelineModel.mimeFilter === ""
                                    onTriggered: TimelineModel.setMimeFilter("")
                                }
                                M3MenuSeparator {}

                                Instantiator {
                                    model: typeMenu._types
                                    delegate: M3MenuItem {
                                        iconName: modelData.filter.indexOf("video/") === 0 ? "movie" : "image"
                                        required property var modelData
                                        text: modelData.label
                                        checkable: true
                                        checked: TimelineModel.mimeFilter === modelData.filter
                                        onTriggered: TimelineModel.setMimeFilter(modelData.filter)
                                    }
                                    onObjectAdded: (index, obj) => typeMenu.insertItem(index + 2, obj)
                                    onObjectRemoved: (index, obj) => typeMenu.removeItem(obj)
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: searchPill
                        // the Search tab has its own, larger box
                        visible: window.currentView !== "search"
                        property bool _aiMode: false
                        property bool _aiSearching: false
                        property bool _picking: false

                        function submit() {
                            if (suggestBox.opened && suggestBox.highlighted >= 0) {
                                pick(suggestBox.items[suggestBox.highlighted])
                                return
                            }
                            suggestBox.close()
                            var q = searchField.text.trim()
                            if (q.length === 0) return
                            if (_aiMode) { window.runAiSearch(q); return }
                            TimelineModel.setSearchFilter("")
                            AlbumModel.setSearchFilter("")
                            searchField.text = ""
                            window.openSearch(q)
                        }
                        // a suggestion completes the text and searches it
                        function pick(s) {
                            _picking = true
                            searchField.text = s.text
                            _picking = false
                            suggestBox.close()
                            submit()
                        }
                        Timer {
                            id: suggestTimer
                            interval: 120
                            onTriggered: {
                                var list = searchField.text.trim().length > 0 ? Analyzer.suggest(searchField.text, 7) : []
                                suggestBox.items = list
                                if (list.length > 0 && searchField.activeFocus) suggestBox.open()
                                else suggestBox.close()
                            }
                        }

                        // ── autocomplete dropdown ─────────────────────────────
                        Popup {
                            id: suggestBox
                            property var items: []
                            property int highlighted: -1
                            y: searchPill.height + 6
                            width: searchPill.width
                            padding: 6
                            focus: false          // typing stays in the search field
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                            background: Rectangle {
                                radius: 20
                                color: ThemeManager.surfaceContainerHigh
                                border.color: ThemeManager.outlineVariant
                                border.width: 1
                            }
                            enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
                            exit:  Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }
                            contentItem: Column {
                                spacing: 2
                                Repeater {
                                    model: suggestBox.items
                                    Rectangle {
                                        id: sugRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool hot: suggestBox.highlighted === index || sugMa.containsMouse
                                        width: suggestBox.availableWidth
                                        height: 44
                                        radius: 14
                                        color: hot ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent"
                                        Row {
                                            anchors.left: parent.left; anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 12
                                            Item {
                                                width: 28; height: 28
                                                anchors.verticalCenter: parent.verticalCenter
                                                FaceAvatar {
                                                    anchors.fill: parent
                                                    visible: sugRow.modelData.kind === "person"
                                                    faceId: sugRow.modelData.face !== undefined ? sugRow.modelData.face : -1
                                                }
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: sugRow.modelData.kind !== "person"
                                                    size: 20
                                                    color: ThemeManager.onSurfaceVariant
                                                    name: ({ place: "location_on", album: "folder", color: "palette",
                                                             month: "calendar_month", year: "event" })[sugRow.modelData.kind] || "search"
                                                }
                                            }
                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: suggestBox.availableWidth - 120
                                                text: sugRow.modelData.text
                                                elide: Text.ElideRight
                                                color: ThemeManager.onSurface
                                                font.pixelSize: 15
                                            }
                                        }
                                        Label {
                                            anchors.right: parent.right; anchors.rightMargin: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.t(Settings.language, "suggest_" + sugRow.modelData.kind)
                                            color: ThemeManager.onSurfaceVariant
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            id: sugMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: searchPill.pick(sugRow.modelData)
                                        }
                                    }
                                }
                            }
                        }
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
                                        suggestBox.highlighted = -1
                                        if (searchPill._picking) return
                                        suggestTimer.restart()
                                    }
                                    onActiveFocusChanged: if (!activeFocus) suggestBox.close()
                                    // ↑/↓ walk the suggestions, Enter takes one
                                    Keys.onDownPressed: if (suggestBox.opened) suggestBox.highlighted = Math.min(suggestBox.highlighted + 1, suggestBox.items.length - 1)
                                    Keys.onUpPressed:   if (suggestBox.opened) suggestBox.highlighted = Math.max(suggestBox.highlighted - 1, -1)
                                    // Enter: in AI mode, smart-search the gallery; otherwise
                                    // the full search (people, places, colours, dates,
                                    // visual matches) in the Search tab
                                    Keys.onReturnPressed: searchPill.submit()
                                    Keys.onEnterPressed:  searchPill.submit()
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
                                        if (searchPill._aiMode) { TimelineModel.clearAiFilter(); window._aiDocResults = [] }
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
                                M3CircularProgress {
                                    anchors.centerIn: parent
                                    width: 20; height: 20
                                    visible: searchPill._aiSearching
                                    running: visible
                                }
                                M3Icon {
                                    anchors.centerIn: parent
                                    visible: !searchPill._aiSearching
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
                                    onClicked: { suggestBox.close(); window.runAiSearch(searchField.text) }
                                }
                            }
                        }
                    }

                    // the window is frameless: its own minimise/maximise/close
                    WindowControls {
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            // Content Stack
            StackView {
                id: mainStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                // Material motion. Tabs: fade through (the old page fades out
                // fast, the new one fades in while growing slightly). Pages
                // opened from a page: shared X axis (in from the right, back
                // to the right).
                readonly property var _emph: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                replaceExit: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 90; easing.type: Easing.InCubic }
                }
                replaceEnter: Transition {
                    SequentialAnimation {
                        PropertyAction { property: "opacity"; value: 0 }
                        PropertyAction { property: "x"; value: 0 }
                        PauseAnimation { duration: 60 }
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 1; duration: 210; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 320; easing.type: Easing.Bezier; easing.bezierCurve: mainStack._emph }
                        }
                    }
                }
                pushEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "x"; from: mainStack.width * 0.08; to: 0; duration: 340; easing.type: Easing.Bezier; easing.bezierCurve: mainStack._emph }
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }
                }
                pushExit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "x"; to: -mainStack.width * 0.04; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: mainStack._emph }
                        NumberAnimation { property: "opacity"; to: 0; duration: 120 }
                    }
                }
                popEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "x"; from: -mainStack.width * 0.04; to: 0; duration: 340; easing.type: Easing.Bezier; easing.bezierCurve: mainStack._emph }
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }
                }
                popExit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "x"; to: mainStack.width * 0.08; duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: mainStack._emph }
                        NumberAnimation { property: "opacity"; to: 0; duration: 140 }
                    }
                }

                // predictive back: the page shrinks and slides as a preview
                transformOrigin: Item.Center
                transform: [
                    Scale {
                        origin.x: mainStack.width / 2; origin.y: mainStack.height / 2
                        xScale: 1 - 0.08 * window._backProgress; yScale: xScale
                    },
                    Translate { x: 36 * window._backProgress }
                ]
                opacity: 1 - 0.35 * window._backProgress

                // touchpad: a two-finger swipe right previews going back
                MouseArea {
                    anchors.fill: parent
                    z: 1000
                    acceptedButtons: Qt.NoButton
                    property bool _swiping: false
                    property real _acc: 0
                    Timer {
                        id: swipeBackEnd
                        interval: 160
                        onTriggered: { parent._swiping = false; window._finishBackGesture() }
                    }
                    onWheel: (wheel) => {
                        var dx = wheel.pixelDelta.x, dy = wheel.pixelDelta.y
                        if (!_swiping) {
                            // the map and globe use horizontal swipes to pan
                            if (dx > 0 && Math.abs(dx) > Math.abs(dy) * 1.5 && window.currentView !== "map" && window._canBack()) {
                                _swiping = true
                                _acc = 0
                                window._backDragging = true
                            } else {
                                wheel.accepted = false
                                return
                            }
                        }
                        _acc = Math.max(0, _acc + dx)
                        window._backProgress = Math.min(1, _acc / 320)
                        swipeBackEnd.restart()
                        wheel.accepted = true
                    }
                }
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
        "settings":  I18n.t(Settings.language, "settings"),
        "search":    I18n.t(Settings.language, "search")
    })

    Component {
        id: timelineView
        MediaGrid {
            // Restore saved scroll when the grid is created (view switch back)
            Component.onCompleted: {
                if (window.timelineScrollY > 0)
                    // MediaGrid's onLayoutChanged handler performs the restore;
                    // arming the flags is all that is needed. (There is no
                    // restoreTimer — calling one here threw a ReferenceError
                    // that aborted the restore before it could take effect.)
                    Qt.callLater(() => { _savedY = window.timelineScrollY; _pendingRestore = true })
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
        id: globeView
        GlobeView {
            onOpenViewer: (data, items) => window._openPlaceItems(data, items)
        }
    }

    Component {
        id: settingsView
        SettingsView {}
    }

    Component {
        id: searchView
        SearchView {
            onOpenViewer: (data, items) => window._openPlaceItems(data, items)
        }
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

    // Window-wide Esc. Lives on an Item so Qt blocks it while a popup or
    // menu is open — those close on Esc themselves.
    Item {
        Shortcut {
            sequences: [StandardKey.Cancel]
            onActivated: window.backWithMotion()
        }
    }

    ViewerOverlay {
        id: viewerOverlay
        parent: Overlay.overlay
        anchors.fill: parent
        viewerOnlyMode: window.viewerOnlyMode
    }

    // Self-update prompt (GitHub releases, signed manifests)
    UpdateDialog {
        id: updateDialog
        parent: Overlay.overlay
    }
}
