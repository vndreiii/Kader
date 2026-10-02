import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../I18n.js" as I18n
import "../Paths.js" as Paths

// The Search tab: one box that searches people, places, colours, dates,
// albums and file names instantly, plus visual (AI) matches; and, before
// you type, the library grouped for browsing — people, memories, places,
// things, colours.
Item {
    id: root
    signal openViewer(var data, var items)

    function _t(k) { return I18n.t(Settings.language, k) }

    // ── state ───────────────────────────────────────────────────────────
    property string query: ""
    property var result: ({})          // Analyzer.search()
    property var aiItems: []
    property var aiDocs: []
    property bool aiBusy: false
    property bool _searchedAi: false

    property var peopleList: []
    property var memoriesList: []
    property var placesList: []
    property var colorList: []
    property bool _loaded: false

    // ── selection (one grid at a time) ─────────────────────────────────
    property var selGrid: null
    readonly property int subDepth: stack.depth   // sub-pages open (people, a person, a group)
    function _gridSel(g) {
        if (g.selecting) {
            if (selGrid && selGrid !== g) selGrid.clearSelection()
            selGrid = g
        } else if (selGrid === g) {
            selGrid = null
        }
    }
    // re-read results after the library changed (menu or selection actions)
    function refreshResults() {
        if (query.length > 0) result = Analyzer.search(query)
        if (aiItems.length > 0) aiItems = Analyzer.mediaByIds(aiItems.map(function (m) { return m.id }))
    }
    function _selItems() {
        if (!selGrid) return []
        var out = []
        for (var i = 0; i < selGrid.items.length; i++)
            if (selGrid.selected[selGrid.items[i].id]) out.push(selGrid.items[i])
        return out
    }
    function _applySel(fn) {
        var list = _selItems()
        for (var i = 0; i < list.length; i++) fn(list[i])
        selGrid.clearSelection()
        TimelineModel.refresh()
        refreshResults()
    }

    function reload() {
        peopleList = Analyzer.people()
        memoriesList = Analyzer.memories()
        placesList = Analyzer.places(24)
        colorList = Analyzer.colorGroups()
        _loaded = true
        if (AI.ready && AI.scenes.length === 0 && !AI.scenesBusy)
            AI.computeScenes()
    }
    // first open: let the skeleton paint, then query
    onVisibleChanged: if (visible && !_loaded) loadTimer.start()
    Component.onCompleted: if (visible) loadTimer.start()
    Timer { id: loadTimer; interval: 30; onTriggered: root.reload() }
    Connections {
        target: Analyzer
        function onRevisionChanged() {
            if (root._loaded) root.reload()
            if (root.query.length > 0) root.result = Analyzer.search(root.query)
        }
    }

    // Esc (window-wide "back"): the open sub-page's own step, then back to
    // the Search home, then clear the search
    function handleBack() {
        if (selGrid) { selGrid.clearSelection(); return true }
        var cur = stack.currentItem
        if (cur && typeof cur.handleBack === "function" && cur.handleBack()) return true
        if (stack.depth > 1) { stack.pop(); return true }
        if (query.length > 0) { root.boxText(""); runSearch("", false); return true }
        return false
    }
    // The box lives in the home page's Component, out of reach by id:
    // these tell it what to show / to take focus.
    signal boxText(string text)
    signal focusBox()
    function setQuery(q) {
        root.boxText(q)
        runSearch(q, true)
        root.focusBox()
    }
    function runSearch(q, withAi) {
        query = q.trim()
        if (stack.depth > 1) stack.pop(null, StackView.Immediate)
        if (query.length === 0) {
            result = ({}); aiItems = []; aiDocs = []; aiBusy = false
            return
        }
        result = Analyzer.search(query)
        if (withAi) startAi()
        else aiTimer.restart()
    }
    function startAi() {
        aiTimer.stop()
        if (query.length === 0 || !AI.modelsPresent) return
        aiBusy = true
        _searchedAi = true
        AI.searchByText(query)
    }
    Timer { id: aiTimer; interval: 650; onTriggered: root.startAi() }
    Connections {
        target: AI
        function onSearchFinished(results) {
            if (!root.aiBusy) return
            root.aiBusy = false
            var ids = [], docs = []
            for (var i = 0; i < results.length; i++) {
                if (results[i].type === "doc") docs.push(results[i])
                else ids.push(results[i].id)
            }
            root.aiItems = Analyzer.mediaByIds(ids)
            root.aiDocs = docs
        }
        function onEngineError(msg) { root.aiBusy = false }
    }

    function openGroup(title, subtitle, items) {
        stack.push(groupPage, { title: title, subtitle: subtitle, items: items })
    }
    function openKey(title, subtitle, key) {
        if (key.indexOf("scene:") === 0)
            openGroup(title, subtitle, Analyzer.mediaByIds(AI.sceneMediaIds(key)))
        else
            openGroup(title, subtitle, Analyzer.mediaForKey(key))
    }
    function openPerson(id) { stack.push(personPage, { personId: id }) }
    function memoryTitle(m) {
        if (m.kind === "onthisday") return m.years === 1 ? _t("mem_year_ago") : _t("mem_years_ago").arg(m.years)
        return m.title
    }
    function memorySubtitle(m) {
        if (m.kind === "trip") return m.subtitle + " · " + _t("mem_days").arg(m.days)
        if (m.kind === "year") return _t("n_items").arg(m.count)
        return m.subtitle
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homePage
        pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed } }
        pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durShort } }
        popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ThemeManager.durMed } }
        popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: ThemeManager.durShort } }
    }

    // ── home: search box + explore / results ─────────────────────────────
    Component {
        id: homePage
        Flickable {
            id: home
            contentWidth: width
            contentHeight: col.implicitHeight + 64
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: col
                x: 28
                width: home.width - 56
                spacing: 28

                Item { Layout.preferredHeight: 4 }

                // search box
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 30
                    color: ThemeManager.surfaceContainerHigh
                    border.width: searchBox.activeFocus ? 2 : 0
                    border.color: ThemeManager.primary
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 10
                        spacing: 12
                        MaterialSymbol { name: "search"; size: 26; color: ThemeManager.onSurfaceVariant }
                        TextField {
                            id: searchBox
                            Layout.fillWidth: true
                            background: null
                            font.pixelSize: 18
                            color: ThemeManager.onSurface
                            placeholderText: root._t("search_placeholder")
                            placeholderTextColor: ThemeManager.onSurfaceVariant
                            onTextEdited: root.runSearch(text, false)
                            onAccepted: root.runSearch(text, true)
                            Component.onCompleted: text = root.query
                            Connections {
                                target: root
                                function onBoxText(t) { searchBox.text = t }
                                function onFocusBox() { searchBox.forceActiveFocus() }
                            }
                        }
                        // visual-search state
                        Rectangle {
                            visible: AI.modelsPresent
                            Layout.preferredHeight: 36
                            Layout.preferredWidth: aiRow.implicitWidth + 24
                            radius: 18
                            color: AI.ready ? ThemeManager.secondaryContainer : "transparent"
                            border.width: AI.ready ? 0 : 1
                            border.color: ThemeManager.outlineVariant
                            Row {
                                id: aiRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol { name: "auto_awesome"; size: 18; color: ThemeManager.onSecondaryContainer; anchors.verticalCenter: parent.verticalCenter }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: AI.loading ? root._t("ai_loading_short")
                                        : AI.indexing ? root._t("ai_indexing_short").arg(AI.indexedCount).arg(AI.indexTotal)
                                        : root._t("ai_visual_on")
                                    font.pixelSize: 13
                                    color: ThemeManager.onSecondaryContainer
                                }
                            }
                        }
                        RoundButton {
                            visible: searchBox.text.length > 0
                            flat: true
                            icon.source: ""
                            contentItem: MaterialSymbol { name: "close"; size: 20; color: ThemeManager.onSurfaceVariant }
                            background: Rectangle { radius: width / 2; color: parent.pressed ? Qt.alpha(ThemeManager.onSurface, 0.12) : parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent" }
                            onClicked: { searchBox.text = ""; root.runSearch("", false) }
                        }
                    }
                }

                // analysis progress
                RowLayout {
                    visible: Analyzer.running && Analyzer.total > 0
                    Layout.fillWidth: true
                    spacing: 12
                    M3CircularProgress { running: parent.visible; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                    Label {
                        text: root._t("analyzing").arg(Analyzer.done).arg(Analyzer.total)
                        color: ThemeManager.onSurfaceVariant
                        font.pixelSize: 13
                    }
                    M3LinearProgress {
                        Layout.fillWidth: true
                        from: 0; to: Math.max(1, Analyzer.total); value: Analyzer.done
                    }
                }

                // ── results ───────────────────────────────────────────────
                ColumnLayout {
                    visible: root.query.length > 0
                    Layout.fillWidth: true
                    spacing: 18

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: (root.result.chips || []).length > 0
                        Repeater {
                            model: root.result.chips || []
                            delegate: Rectangle {
                                required property var modelData
                                height: 40
                                width: chipRow.implicitWidth + 28
                                radius: 12
                                color: chipMa.containsMouse ? ThemeManager.secondaryContainer : ThemeManager.surfaceContainerHigh
                                border.width: 1
                                border.color: ThemeManager.outlineVariant
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    FaceAvatar {
                                        visible: modelData.kind === "person"
                                        width: 26; height: 26
                                        faceId: modelData.face !== undefined ? modelData.face : -1
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    MaterialSymbol {
                                        visible: modelData.kind !== "person"
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 18
                                        color: ThemeManager.onSurfaceVariant
                                        name: ({ place: "location_on", color: "palette", year: "calendar_month",
                                                 month: "calendar_month", album: "folder" })[modelData.kind] || "search"
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        font.pixelSize: 14
                                        color: ThemeManager.onSurface
                                    }
                                }
                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: (modelData.key || "").length > 0
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: modelData.kind === "person"
                                        ? root.openPerson(parseInt(modelData.key.split(":")[1]))
                                        : root.openKey(modelData.label, "", modelData.key)
                                }
                            }
                        }
                    }

                    SectionTitle {
                        visible: (root.result.media || []).length > 0
                        text: root.result.structured ? root._t("search_matches") : root._t("search_files")
                        count: (root.result.media || []).length
                        onShowAll: root.openGroup(root.query, "", root.result.media)
                    }
                    ThumbGrid {
                        Layout.fillWidth: true
                        visible: (root.result.media || []).length > 0
                        items: root.result.media || []
                        maxRows: 2
                        selectable: true
                        scroller: home
                        onSelectingChanged: root._gridSel(this)
                        onMediaChanged: root.refreshResults()
                        onOpenItem: (i) => root.openViewer(items[i], items)
                    }

                    SectionTitle {
                        visible: AI.modelsPresent
                        text: root._t("search_visual")
                        count: root.aiBusy ? -1 : root.aiItems.length
                        onShowAll: root.openGroup(root.query, root._t("search_visual"), root.aiItems)
                    }
                    ThumbGrid {
                        Layout.fillWidth: true
                        visible: AI.modelsPresent && (root.aiBusy || root.aiItems.length > 0)
                        loading: root.aiBusy
                        items: root.aiItems
                        maxRows: 3
                        selectable: true
                        scroller: home
                        onSelectingChanged: root._gridSel(this)
                        onMediaChanged: root.refreshResults()
                        onOpenItem: (i) => root.openViewer(items[i], items)
                    }
                    Label {
                        visible: AI.modelsPresent && !root.aiBusy && root._searchedAi && root.aiItems.length === 0
                        text: root._t("ai_no_matches")
                        color: ThemeManager.onSurfaceVariant
                    }
                    InfoCard {
                        visible: !AI.modelsPresent
                        Layout.fillWidth: true
                        icon: "auto_awesome"
                        title: root._t("search_visual_cta")
                        body: root._t("search_visual_cta_body")
                        action: root._t("open_settings")
                        onTriggered: window.switchView("settings")
                    }

                    SectionTitle {
                        visible: root.aiDocs.length > 0
                        text: root._t("documents_count").arg(root.aiDocs.length)
                        count: -1
                    }
                    Repeater {
                        model: root.aiDocs
                        delegate: ItemDelegate {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.name
                            icon.name: "text-x-generic"
                            onClicked: Qt.openUrlExternally(Paths.fileUrl(modelData.file_path))
                        }
                    }
                    Label {
                        visible: (root.result.media || []).length === 0 && (root.result.chips || []).length === 0
                                 && !AI.modelsPresent
                        text: root._t("search_nothing")
                        color: ThemeManager.onSurfaceVariant
                    }
                }

                // ── explore ───────────────────────────────────────────────
                ColumnLayout {
                    visible: root.query.length === 0
                    Layout.fillWidth: true
                    spacing: 30

                    // People
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        SectionTitle {
                            text: root._t("people")
                            count: Analyzer.facesEnabled ? root.peopleList.length : -1
                            actionVisible: Analyzer.facesEnabled
                            showAllText: root._t("manage")
                            onShowAll: stack.push(peoplePage)
                        }
                        ListView {
                            visible: Analyzer.facesEnabled && (root.peopleList.length > 0 || !root._loaded)
                            Layout.fillWidth: true
                            // room around the faces for their hover grow (the
                            // list clips); the negative margin keeps them aligned
                            Layout.preferredHeight: 156
                            Layout.leftMargin: -8
                            Layout.rightMargin: -8
                            leftMargin: 8
                            rightMargin: 8
                            topMargin: 6
                            orientation: ListView.Horizontal
                            spacing: 18
                            clip: true
                            model: root._loaded ? root.peopleList : 8
                            delegate: Column {
                                required property var modelData
                                readonly property bool _ph: !root._loaded
                                width: 104
                                spacing: 8
                                FaceAvatar {
                                    width: 104; height: 104
                                    faceId: parent._ph ? -1 : (modelData.cover !== undefined ? modelData.cover : -1)
                                    revision: Analyzer.revision
                                    scale: faceMa.containsMouse ? 1.05 : 1
                                    Behavior on scale { NumberAnimation { duration: ThemeManager.durShort } }
                                    MouseArea {
                                        id: faceMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (m) => {
                                            if (parent.parent._ph) return
                                            if (m.button === Qt.RightButton) personMenu.popup()
                                            else root.openPerson(modelData.id)
                                        }
                                        onPressAndHold: if (!parent.parent._ph) personMenu.popup()
                                    }
                                    PersonMenu {
                                        id: personMenu
                                        personId: modelData && modelData.id !== undefined ? modelData.id : -1
                                        hiddenPerson: !!(modelData && modelData.hidden)
                                        onOpenRequested: root.openPerson(modelData.id)
                                        onRenameRequested: nameLbl.startEdit()
                                    }
                                }
                                NameLabel {
                                    id: nameLbl
                                    width: parent.width
                                    visible: !parent._ph
                                    name: modelData.name || ""
                                    placeholder: root._t("add_name")
                                    pixelSize: 14
                                    onRenamed: (n) => Analyzer.renamePerson(modelData.id, n)
                                }
                            }
                        }
                        Label {
                            visible: Analyzer.facesEnabled && root._loaded && root.peopleList.length === 0
                            text: Analyzer.running ? root._t("people_finding") : root._t("people_none")
                            color: ThemeManager.onSurfaceVariant
                        }
                        InfoCard {
                            visible: !Analyzer.facesEnabled || Analyzer.downloading || (Analyzer.error.length > 0 && Analyzer.facesEnabled)
                            Layout.fillWidth: true
                            icon: "face"
                            title: Analyzer.downloading ? root._t("people_downloading").arg(Math.round(Analyzer.downloadProgress * 100))
                                 : Analyzer.error.length > 0 ? Analyzer.error
                                 : root._t("people_cta")
                            body: root._t("people_cta_body")
                            action: Analyzer.downloading ? "" : (Analyzer.error.length > 0 ? root._t("retry") : root._t("set_up"))
                            progress: Analyzer.downloading ? Analyzer.downloadProgress : -1
                            onTriggered: Analyzer.enableFaces()
                        }
                    }

                    // Memories
                    ColumnLayout {
                        visible: !root._loaded || root.memoriesList.length > 0
                        Layout.fillWidth: true
                        spacing: 12
                        SectionTitle { text: root._t("memories"); count: -1 }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 200
                            orientation: ListView.Horizontal
                            spacing: 14
                            clip: true
                            model: root._loaded ? root.memoriesList : 4
                            delegate: CoverCard {
                                required property var modelData
                                width: 300; height: 200
                                loading: !root._loaded
                                covers: root._loaded ? modelData.covers : []
                                title: root._loaded ? root.memoryTitle(modelData) : ""
                                subtitle: root._loaded ? root.memorySubtitle(modelData) : ""
                                onClicked: root.openKey(title, subtitle, modelData.key)
                            }
                        }
                    }

                    // Places
                    ColumnLayout {
                        visible: !root._loaded || root.placesList.length > 0
                        Layout.fillWidth: true
                        spacing: 12
                        SectionTitle {
                            text: root._t("places")
                            count: root.placesList.length
                            actionVisible: true
                            showAllText: root._t("open_globe")
                            onShowAll: window.switchView("map")
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            orientation: ListView.Horizontal
                            spacing: 14
                            clip: true
                            model: root._loaded ? root.placesList : 5
                            delegate: CoverCard {
                                required property var modelData
                                width: 200; height: 160
                                loading: !root._loaded
                                covers: root._loaded && modelData.cover ? [modelData.cover] : []
                                title: root._loaded ? modelData.name.split(", ")[0] : ""
                                subtitle: root._loaded ? (modelData.name.split(", ").slice(1).join(", ") + " · " + modelData.count) : ""
                                onClicked: root.openKey(modelData.name, root._t("n_items").arg(modelData.count), "place:" + modelData.name)
                            }
                        }
                    }

                    // Things (visual AI)
                    ColumnLayout {
                        visible: AI.scenes.length > 0 || AI.scenesBusy
                        Layout.fillWidth: true
                        spacing: 12
                        SectionTitle { text: root._t("things"); count: AI.scenes.length; actionVisible: false }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            orientation: ListView.Horizontal
                            spacing: 14
                            clip: true
                            model: AI.scenesBusy ? 5 : AI.scenes
                            delegate: CoverCard {
                                required property var modelData
                                width: 200; height: 160
                                loading: AI.scenesBusy
                                covers: AI.scenesBusy ? [] : Analyzer.mediaByIds(modelData.coverIds).map(m => m.thumb)
                                title: AI.scenesBusy ? "" : modelData.name
                                subtitle: AI.scenesBusy ? "" : root._t("n_items").arg(modelData.count)
                                onClicked: root.openKey(modelData.name, subtitle, modelData.key)
                            }
                        }
                    }

                    // Colours
                    ColumnLayout {
                        visible: !root._loaded || root.colorList.length > 0
                        Layout.fillWidth: true
                        spacing: 12
                        SectionTitle { text: root._t("colours"); count: root.colorList.length; actionVisible: false }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 14
                            Repeater {
                                model: root._loaded ? root.colorList : 6
                                delegate: CoverCard {
                                    required property var modelData
                                    width: 176; height: 132
                                    loading: !root._loaded
                                    covers: root._loaded ? modelData.covers : []
                                    swatch: root._loaded && modelData.swatch ? modelData.swatch : "transparent"
                                    title: root._loaded ? root._t("color_" + modelData.name) : ""
                                    subtitle: root._loaded ? root._t("n_items").arg(modelData.count) : ""
                                    onClicked: root.openKey(title, subtitle, "color:" + modelData.bucket)
                                }
                            }
                        }
                    }

                    // Quick collections
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        SectionTitle { text: root._t("collections"); count: -1 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            Repeater {
                                model: [
                                    { icon: "favorite", label: root._t("favorites"), key: "favorite:" },
                                    { icon: "videocam", label: root._t("videos"), key: "video:" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: collRow.implicitWidth + 36
                                    height: 48
                                    radius: 16
                                    color: collMa.containsMouse ? ThemeManager.secondaryContainer : ThemeManager.surfaceContainerHigh
                                    Row {
                                        id: collRow
                                        anchors.centerIn: parent
                                        spacing: 10
                                        MaterialSymbol { name: modelData.icon; size: 22; color: ThemeManager.onSurfaceVariant; anchors.verticalCenter: parent.verticalCenter }
                                        Label { text: modelData.label; font.pixelSize: 15; color: ThemeManager.onSurface; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    MouseArea {
                                        id: collMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openKey(modelData.label, "", modelData.key)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── a group of photos ────────────────────────────────────────────────
    Component {
        id: groupPage
        Item {
            property string title: ""
            property string subtitle: ""
            property var items: []
            PageHeader {
                id: gh
                title: parent.title
                subtitle: parent.subtitle.length > 0 ? parent.subtitle : root._t("n_items").arg(parent.items.length)
                onBack: stack.pop()
            }
            ThumbGrid {
                anchors { top: gh.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24 }
                items: parent.items
                minCell: 170
                selectable: true
                onSelectingChanged: root._gridSel(this)
                onOpenItem: (i) => root.openViewer(items[i], items)
            }
        }
    }

    Component { id: personPage; PersonPage { onBack: stack.pop(); onOpenViewer: (d, items) => root.openViewer(d, items); onOpenPerson: (id) => { stack.pop(StackView.Immediate); root.openPerson(id) } } }
    Component { id: peoplePage; PeoplePage { onBack: stack.pop(); onOpenPerson: (id) => root.openPerson(id) } }

    // ── selection bar ────────────────────────────────────────────────────
    Rectangle {
        id: selBar
        visible: opacity > 0
        opacity: root.selGrid ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 24 }
        z: 100
        height: 56
        width: selRow.implicitWidth + 24
        radius: 28
        color: ThemeManager.surfaceContainerHighest
        border.color: ThemeManager.outlineVariant
        border.width: 1
        RowLayout {
            id: selRow
            anchors.centerIn: parent
            spacing: 4
            M3Button {
                flat: true
                text: "✕"
                onClicked: if (root.selGrid) root.selGrid.clearSelection()
            }
            Label {
                text: root._t("n_selected").arg(root.selGrid ? root.selGrid.selectedCount : 0)
                color: ThemeManager.onSurface
                font.pixelSize: 15
                rightPadding: 8
            }
            M3Button {
                flat: true
                text: "Favorite"
                onClicked: root._applySel(function (m) { if (!m.is_favorite) DB.toggleFavorite(m.id) })
            }
            M3Button {
                flat: true
                text: "Hide"
                onClicked: root._applySel(function (m) { DB.setHidden(m.id, true) })
            }
            M3Button {
                flat: true
                text: "Move to Trash"
                onClicked: root._applySel(function (m) { DB.setTrashed(m.id, true) })
            }
        }
    }
}
