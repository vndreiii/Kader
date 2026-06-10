import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    signal openViewer(var mediaData, int index)

    implicitWidth: 800
    implicitHeight: 600

    readonly property real hMargin:  20
    readonly property real gap:      6
    readonly property real contentW: width - hMargin * 2

    // ── Multi-select state ─────────────────────────────────────────────────
    property bool selectionMode: false
    property var  _selSet: ({})

    function isSelected(id)  { return !!_selSet[String(id)] }
    function selectId(id) {
        if (!isSelected(id)) { var s = Object.assign({}, _selSet); s[String(id)] = true; _selSet = s }
    }
    function toggleSelect(id) {
        var s = Object.assign({}, _selSet); var k = String(id)
        if (s[k]) delete s[k]; else s[k] = true; _selSet = s
        if (Object.keys(_selSet).length === 0) selectionMode = false
    }
    function clearSelection() { _selSet = {}; selectionMode = false }
    function selectedIds() { return Object.keys(_selSet).map(Number) }

    Keys.onEscapePressed: if (selectionMode) clearSelection()

    // Push content width to TimelineModel for aspect-ratio row packing.
    // Debounced so window-resize doesn't hammer the model.
    Timer {
        id: widthDebounce
        interval: 120
        onTriggered: TimelineModel.setContentWidth(Math.round(root.contentW))
    }
    onContentWChanged: widthDebounce.restart()
    Component.onCompleted: TimelineModel.setContentWidth(Math.round(contentW))

    // ── Preserve scroll position across model rebuilds ───────────────────
    property real _savedY: 0
    property bool _pendingRestore: false

    // Smooth wheel scroll target — accumulates delta across rapid wheel events.
    property real _scrollTarget: 0

    Connections {
        target: TimelineModel
        function onModelAboutToBeReset() {
            root._savedY = listView.contentY
        }
        function onModelReset() {
            if (root._savedY > 0) {
                Qt.callLater(function() {
                    var newY = Math.min(root._savedY, Math.max(0, listView.contentHeight - listView.height))
                    listView.contentY = newY
                    root._scrollTarget = newY
                })
            }
        }
    }

    // Frame-synced momentum scroll. Each rendered frame eases contentY toward the
    // accumulated wheel target with exponential decay — a smooth, continuous glide
    // with no easing-restart artifacts, and because it's driven by FrameAnimation
    // it's vsync-aligned (never tears, never stutters on a free-spin wheel).
    FrameAnimation {
        id: scrollSmooth
        running: false
        property real rate: 13          // higher = snappier, lower = floatier
        onTriggered: {
            var cur = listView.contentY
            var d   = root._scrollTarget - cur
            if (Math.abs(d) < 0.5) {
                listView.contentY = root._scrollTarget
                running = false
                return
            }
            // frame-rate independent: same feel at 60/120/144 Hz
            var next = cur + d * (1 - Math.exp(-rate * frameTime))
            listView.contentY = next
            // If the Flickable refused the move (we hit its real top/bottom bound,
            // which can differ from contentHeight-height due to margins/originY),
            // snap the target to the actual position and stop. Prevents a dead
            // zone that left scrolling "stuck shifted down" and chasing nothing.
            if (Math.abs(listView.contentY - next) > 0.5) {
                root._scrollTarget = listView.contentY
                running = false
            }
        }
    }

    ListView {
        id: listView
        anchors.fill: parent
        model: TimelineModel
        clip: true
        spacing: root.gap
        leftMargin: hMargin
        rightMargin: hMargin
        topMargin: 0
        bottomMargin: root.selectionMode ? 88 : 40
        cacheBuffer: Math.round(height * 1.5)
        reuseItems: true
        visible: count > 0

        // WheelHandler inside ListView takes priority over Flickable's built-in wheel scroll.
        WheelHandler {
            id: wheelHandler
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            target: null
            onWheel: function(event) {
                if (scrubber._dragging) return
                var dy = event.pixelDelta.y !== 0
                    ? event.pixelDelta.y
                    : event.angleDelta.y / 120.0 * 100
                var maxY = Math.max(0, listView.contentHeight - listView.height)
                // If a previous glide already finished, resync the target to the
                // real position so we don't accumulate drift.
                if (!scrollSmooth.running) root._scrollTarget = listView.contentY
                root._scrollTarget = Math.max(0, Math.min(maxY, root._scrollTarget - dy))
                scrollSmooth.running = true
            }
        }

        pixelAligned: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3000
        maximumFlickVelocity: 4000

        // Keep _scrollTarget in sync when scrubber drags contentY directly.
        onContentYChanged: {
            if (scrubber._dragging)
                root._scrollTarget = listView.contentY
        }

        delegate: Item {
            id: rowItem
            readonly property bool   _isHeader: model.isHeader   || false
            readonly property string _month:    model.monthName  || ""
            readonly property var    _items:    model.items      || []
            // heightMult carries the actual row pixel height from aspect-ratio packing
            readonly property real   _rowH:     model.heightMult || 200

            width:  listView.width - root.hMargin * 2
            height: _isHeader ? 56 : Math.round(_rowH)

            Rectangle {
                visible: rowItem._isHeader
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                height: 30
                width: dateLabel.implicitWidth + 20
                radius: 15
                color: ThemeManager.surfaceContainerHigh
                Label {
                    id: dateLabel
                    anchors.centerIn: parent
                    text: rowItem._month
                    font.family: "Roboto Flex"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: ThemeManager.onSurface
                }
            }

            Row {
                visible: !rowItem._isHeader
                spacing: root.gap

                Repeater {
                    model: rowItem._items

                    Tile {
                        width:  modelData ? (modelData.item_width  || Math.round(rowItem._rowH * 1.33)) : Math.round(rowItem._rowH * 1.33)
                        height: rowItem._rowH
                        tileData: modelData
                        selectable: root.selectionMode
                        selected: modelData ? root.isSelected(modelData.id) : false
                        onOpen: {
                            if (modelData) root.openViewer(modelData, modelData._flat_index || 0)
                        }
                        onToggleFav: {
                            if (modelData) { DB.toggleFavorite(modelData.id); TimelineModel.refresh() }
                        }
                        onSelectToggle: {
                            if (modelData) root.toggleSelect(modelData.id)
                        }
                        onEnterSelectionMode: {
                            if (modelData) { root.selectionMode = true; root.selectId(modelData.id) }
                        }
                    }
                }
            }
        }
    }

    // ── Fast-scroll date scrubber ────────────────────────────────────────
    Rectangle {
        id: scrubber
        visible: listView.count > 0 && listView.contentHeight > listView.height * 1.5
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 44
        color: "transparent"

        property bool   _dragging:   false
        property string _startMonth: ""

        // Current month at the visible scroll position — only computed while dragging.
        // monthAtRow() scans upward from the estimated row to the nearest header.
        readonly property string _currentMonth: {
            if (!_dragging) return ""
            var idx = Math.floor(listView.visibleArea.yPosition * listView.count)
            idx = Math.max(0, Math.min(listView.count - 1, idx))
            return TimelineModel.monthAtRow(idx) || ""
        }

        // Bubble shows immediately on drag, updates as months change
        readonly property bool _showBubble: _dragging && _currentMonth !== ""

        // Handle — y is purely driven by list scroll (no drag.target, no binding conflict)
        Rectangle {
            id: scrubHandle
            width: 32; height: 56
            radius: 16
            anchors.right: parent.right
            color: scrubber._dragging ? ThemeManager.primary : Qt.alpha(ThemeManager.onSurface, 0.2)
            Behavior on color { ColorAnimation { duration: 100 } }

            // Position by scroll fraction (contentY / maxScroll) over the handle's
            // travel range — the SAME mapping the drag uses, so the handle sits
            // exactly under the cursor instead of lagging by an offset.
            y: {
                var maxY = Math.max(1, listView.contentHeight - listView.height)
                var frac = Math.max(0, Math.min(1, listView.contentY / maxY))
                return frac * (scrubber.height - height)
            }

            // Month bubble — fades + scales in after crossing a month boundary
            Rectangle {
                visible: scrubber._dragging
                opacity: scrubber._showBubble ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                scale: scrubber._showBubble ? 1.0 : 0.85
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                transformOrigin: Item.Right

                anchors.right: parent.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: ThemeManager.inverseSurface
                radius: 10
                width: monthLabel.implicitWidth + 20
                height: 36

                Label {
                    id: monthLabel
                    anchors.centerIn: parent
                    text: scrubber._currentMonth
                    color: ThemeManager.inverseOnSurface
                    font.pixelSize: 13; font.weight: Font.Medium
                }
            }
        }

        // Full-height drag area — sets contentY directly, avoids positionViewAtIndex
        // index-mapping issues and eliminates the drag.target / y-binding conflict.
        MouseArea {
            id: scrubDrag
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.SizeVerCursor

            function _applyScroll(my) {
                // Centre the handle on the cursor: map the handle's CENTRE to the
                // mouse over its travel range (height minus the handle's own size).
                var track = Math.max(1, scrubber.height - scrubHandle.height)
                var frac  = Math.max(0, Math.min(1, (my - scrubHandle.height / 2) / track))
                var maxY  = Math.max(0, listView.contentHeight - listView.height)
                listView.contentY = frac * maxY
            }

            onPressed: (mouse) => {
                listView.cancelFlick()
                scrollSmooth.running = false   // hand control to the drag
                var idx = Math.round(listView.visibleArea.yPosition * listView.count)
                idx = Math.max(0, Math.min(listView.count - 1, idx))
                scrubber._startMonth = TimelineModel.data(TimelineModel.index(idx, 0), 258) || ""
                scrubber._dragging = true
                _applyScroll(mouse.y)
            }
            onPositionChanged: (mouse) => {
                if (pressed) _applyScroll(mouse.y)
            }
            onReleased: scrubber._dragging = false
        }
    }

    // ── Selection drag overlay ────────────────────────────────────────────
    MouseArea {
        id: selOverlay
        anchors.fill: listView
        enabled: root.selectionMode
        z: 50
        propagateComposedEvents: false

        property point _pressPos: Qt.point(0, 0)
        property bool  _dragging: false

        onPressed: (mouse) => {
            _pressPos = Qt.point(mouse.x, mouse.y)
            _dragging = false
        }
        onPositionChanged: (mouse) => {
            if (!pressed) return
            var dx = mouse.x - _pressPos.x; var dy = mouse.y - _pressPos.y
            if (Math.sqrt(dx*dx + dy*dy) > 6) _dragging = true
            if (_dragging) _selectAtPos(mouse.x, mouse.y)
        }
        onReleased: (mouse) => {
            if (!_dragging) _toggleAtPos(mouse.x, mouse.y)
            _dragging = false
        }

        function _tileAtPos(mx, my, selectOnly) {
            var pt = selOverlay.mapToItem(listView.contentItem, mx, my)
            var delegate = listView.itemAt(pt.x, pt.y)
            if (!delegate || delegate._isHeader || !delegate._items || !delegate._items.length) return
            var delPt = selOverlay.mapToItem(delegate, mx, my)
            var rowX = 0
            for (var i = 0; i < delegate._items.length; i++) {
                var item = delegate._items[i]
                var w = item.item_width || Math.round(delegate._rowH * 1.33)
                if (delPt.x >= rowX && delPt.x < rowX + w) {
                    if (item.id) {
                        if (selectOnly) root.selectId(item.id)
                        else root.toggleSelect(item.id)
                    }
                    return
                }
                rowX += w + root.gap
            }
        }
        function _selectAtPos(mx, my) { _tileAtPos(mx, my, true) }
        function _toggleAtPos(mx, my) { _tileAtPos(mx, my, false) }
    }

    // ── Selection action bar ──────────────────────────────────────────────
    Rectangle {
        id: selActionBar
        visible: root.selectionMode
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        z: 200
        height: 56
        width: {
            var r = selBarRow; var w = 0
            for (var i = 0; i < r.children.length; i++) { w += r.children[i].width; if (i < r.children.length - 1) w += r.spacing }
            return w + 8
        }
        radius: 28
        color: ThemeManager.inverseSurface
        opacity: root.selectionMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Row {
            id: selBarRow
            anchors.centerIn: parent
            spacing: 4

            Label {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8; rightPadding: 4
                text: Object.keys(root._selSet).length + " selected"
                color: ThemeManager.inverseOnSurface
                font.pixelSize: 14; font.weight: Font.Medium
            }

            Rectangle { width: 1; height: 32; color: Qt.alpha(ThemeManager.inverseOnSurface, 0.2); anchors.verticalCenter: parent.verticalCenter }

            // Favorite
            Rectangle {
                width: 44; height: 44; radius: 22
                color: selFavMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Favorite"; ToolTip.visible: selFavMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "favorite"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: selFavMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var ids = root.selectedIds()
                        for (var i = 0; i < ids.length; i++) DB.toggleFavorite(ids[i])
                        TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Hide (visibility_off reads as "hide" far better than a padlock).
            // Hidden in the Hidden view (where Unhide takes its place).
            Rectangle {
                width: 44; height: 44; radius: 22
                visible: TimelineModel.filterMode !== 3
                color: selHideMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Hide"; ToolTip.visible: selHideMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "visibility_off"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: selHideMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var ids = root.selectedIds()
                        for (var i = 0; i < ids.length; i++) DB.setHidden(ids[i], true)
                        TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Ignore — drop the items from the gallery (managed in Settings).
            // Shown in normal browsing (All / Favorites), not in trash/hidden.
            Rectangle {
                width: 44; height: 44; radius: 22
                visible: TimelineModel.filterMode === 0 || TimelineModel.filterMode === 1
                color: selIgnoreMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Ignore"; ToolTip.visible: selIgnoreMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "block"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: selIgnoreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var ids = root.selectedIds()
                        for (var i = 0; i < ids.length; i++) DB.setIgnored(ids[i], true)
                        TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Unhide — only in the Hidden view
            Rectangle {
                width: 44; height: 44; radius: 22
                visible: TimelineModel.filterMode === 3
                color: selUnhideMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Unhide"; ToolTip.visible: selUnhideMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "visibility"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: selUnhideMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var ids = root.selectedIds()
                        for (var i = 0; i < ids.length; i++) DB.setHidden(ids[i], false)
                        TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Move to trash — shown everywhere EXCEPT the trash view itself.
            // Also clears the hidden flag so a hidden item lands cleanly in trash
            // (otherwise it stays flagged hidden and never leaves the Hidden view).
            Rectangle {
                width: 44; height: 44; radius: 22
                visible: TimelineModel.filterMode !== 2
                color: selTrashMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Move to trash"; ToolTip.visible: selTrashMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "delete"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: selTrashMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var ids = root.selectedIds()
                        for (var i = 0; i < ids.length; i++) { DB.setHidden(ids[i], false); DB.setTrashed(ids[i], true) }
                        TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            // Delete permanently — only in the trash view (where it's the obvious action)
            Rectangle {
                width: 44; height: 44; radius: 22
                visible: TimelineModel.filterMode === 2
                color: selPermDelMa.containsMouse ? Qt.alpha(ThemeManager.error, 0.22) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Delete permanently"; ToolTip.visible: selPermDelMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "delete_forever"; size: 20; color: ThemeManager.inverseOnSurface }
                MouseArea {
                    id: selPermDelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var ids = root.selectedIds()
                        for (var i = 0; i < ids.length; i++) DB.deleteMediaPermanently(ids[i])
                        TimelineModel.refresh(); root.clearSelection()
                    }
                }
            }

            Rectangle { width: 1; height: 32; color: Qt.alpha(ThemeManager.inverseOnSurface, 0.2); anchors.verticalCenter: parent.verticalCenter }

            // Clear / exit selection
            Rectangle {
                width: 44; height: 44; radius: 22
                color: selClearMa.containsMouse ? Qt.alpha(ThemeManager.inverseOnSurface, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                ToolTip.text: "Clear selection"; ToolTip.visible: selClearMa.containsMouse; ToolTip.delay: 400
                M3Icon { anchors.centerIn: parent; name: "close"; size: 20; color: Qt.alpha(ThemeManager.inverseOnSurface, 0.6) }
                MouseArea {
                    id: selClearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearSelection()
                }
            }
        }
    }

    // Empty state
    ColumnLayout {
        anchors.centerIn: parent
        visible: listView.count === 0
        spacing: 16

        readonly property int    mode:    TimelineModel.filterMode
        readonly property bool   isVid:   TimelineModel.mimeFilter === "video/"
        readonly property bool   isAI:    TimelineModel.aiFilterActive
        readonly property bool   aiIndexing: isAI && AI.indexing

        M3Icon {
            Layout.alignment: Qt.AlignHCenter
            name:    parent.isAI     ? "auto_awesome"
                   : parent.mode === 2 ? "delete"
                   : parent.mode === 1 ? "favorite"
                   : parent.isVid ? "video_library"
                   : "schedule"
            size: 96; color: ThemeManager.onSurfaceVariant; opacity: 0.4
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.aiIndexing ? qsTr("AI is indexing your library…")
                 : parent.isAI       ? qsTr("No matches for your AI search")
                 : parent.mode === 2 ? "Trash is empty"
                 : parent.mode === 1 ? "No favorites yet"
                 : parent.isVid      ? "No videos found"
                 :                     "No photos found"
            font.pixelSize: 24; font.weight: Font.Light; color: ThemeManager.onSurface
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text:  parent.aiIndexing ? qsTr("%1 / %2 photos embedded").arg(AI.indexedCount).arg(AI.indexTotal)
                 : parent.isAI       ? qsTr("Try a different description, or wait for indexing to complete.")
                 : parent.mode === 2 ? "Deleted photos will appear here."
                 : parent.mode === 1 ? "Tap the heart on any photo to add it to Favorites."
                 : parent.isVid      ? "Scan a directory containing video files."
                 :                     "Press \"Scan directory\" to discover your photo library."
            font.pixelSize: 14; color: ThemeManager.onSurfaceVariant
        }
    }
}
