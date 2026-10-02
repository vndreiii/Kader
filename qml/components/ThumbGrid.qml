import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."
import "../Paths.js" as Paths

// Square-thumbnail grid for search results and groups. `items` is a list of
// media maps ({ id, file_path, thumb, mime_type, … }).
GridView {
    id: root
    property var items: []
    property real minCell: 150
    property int maxRows: 0           // >0: show at most this many rows (preview)
    property bool loading: false      // show skeleton cells instead
    // Opt-in selection: press-and-hold (or right-click) starts it, then
    // clicks toggle. `selected` maps media id → true.
    property bool selectable: false
    property bool selecting: false
    property var selected: ({})
    readonly property int selectedCount: Object.keys(selected).length
    signal openItem(int index)
    signal mediaChanged()             // the right-click menu changed the library
    // the Flickable a quick drag scrolls: the grid itself, or (for preview
    // grids, which don't scroll) the page around them
    property Flickable scroller: interactive ? root : null
    function _selectAtScene(sx, sy) {
        var p = root.mapFromItem(null, sx, sy)
        var i = root.indexAt(p.x + root.contentX, p.y + root.contentY)
        if (i < 0 || i >= root._shown || !root.items[i]) return
        var id = root.items[i].id
        if (!root.selected[id]) root.toggleSelected(id)
    }
    function toggleSelected(id) {
        var s = Object.assign({}, selected)
        if (s[id]) delete s[id]; else s[id] = true
        selected = s
    }
    function clearSelection() { selected = ({}); selecting = false }

    readonly property int columns: Math.max(2, Math.floor(width / minCell))
    readonly property int _shown: maxRows > 0 ? Math.min(items.length, columns * maxRows) : items.length

    cellWidth: width / columns
    cellHeight: cellWidth
    interactive: maxRows === 0
    clip: maxRows === 0
    implicitHeight: maxRows > 0
        ? Math.ceil((loading ? columns * Math.min(maxRows, 2) : _shown) / columns) * cellHeight
        : contentHeight
    model: loading ? columns * Math.max(1, Math.min(maxRows || 3, 3)) : _shown
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: root.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    delegate: Item {
        id: cell
        required property int index
        readonly property var media: root.loading ? null : root.items[index]
        width: root.cellWidth
        height: root.cellHeight

        Item {
            anchors.fill: parent
            anchors.margins: 3

            Skeleton {
                anchors.fill: parent
                radius: 12
                visible: root.loading || thumb.status !== Image.Ready
                active: visible
            }
            Image {
                id: thumb
                anchors.fill: parent
                source: cell.media ? (cell.media.thumb || Paths.fileUrl(cell.media.file_path)) : ""
                sourceSize: Qt.size(320, 320)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            Rectangle { id: round; anchors.fill: parent; radius: 12; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                source: thumb
                visible: thumb.status === Image.Ready
                maskEnabled: true
                maskSource: round
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                scale: hover.containsMouse ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            }
            Rectangle {
                visible: cell.media && (cell.media.mime_type || "").toString().startsWith("video/")
                anchors { left: parent.left; top: parent.top; margins: 8 }
                width: 24; height: 24; radius: 12
                color: Qt.alpha("black", 0.55)
                M3Icon { anchors.centerIn: parent; name: "play"; size: 14; color: "white" }
            }
            // selection: tint + check badge
            Rectangle {
                anchors.fill: parent
                radius: 12
                visible: root.selecting && cell.media && !!root.selected[cell.media.id]
                color: Qt.alpha(ThemeManager.primary, 0.28)
                border.width: 3
                border.color: ThemeManager.primary
            }
            Rectangle {
                visible: root.selecting && cell.media !== null
                readonly property bool on: cell.media !== null && !!root.selected[cell.media.id]
                anchors { right: parent.right; top: parent.top; margins: 8 }
                width: 26; height: 26; radius: 13
                color: on ? ThemeManager.primary : Qt.alpha("black", 0.45)
                border.width: 2
                border.color: "white"
                M3Icon { anchors.centerIn: parent; visible: parent.on; name: "check"; size: 16; color: ThemeManager.onPrimary }
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.loading
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                // click / hold (300 ms, then drag to select more) / quick drag
                // to scroll — same as the gallery's tiles
                property int _mode: 0          // 0 idle, 1 undecided, 2 scrolling, 3 selecting
                property bool _wasDrag: false
                property real _sx: 0
                property real _sy: 0
                property real _startY: 0
                property real _lastY: 0
                property real _lastT: 0
                property real _vy: 0
                Timer {
                    id: holdTimer
                    interval: 300
                    onTriggered: {
                        if (hover._mode !== 1 || !root.selectable || !cell.media) return
                        hover._mode = 3
                        root.selecting = true
                        if (!root.selected[cell.media.id]) root.toggleSelected(cell.media.id)
                    }
                }
                function _end() { holdTimer.stop(); _wasDrag = _mode >= 2; _mode = 0 }
                onPressed: (mouse) => {
                    _wasDrag = false
                    if (mouse.button !== Qt.LeftButton) return
                    var p = mapToItem(null, mouse.x, mouse.y)
                    _sx = p.x; _sy = p.y; _lastY = p.y; _lastT = Date.now(); _vy = 0
                    _mode = 1
                    if (root.scroller) { root.scroller.cancelFlick(); _startY = root.scroller.contentY }
                    holdTimer.restart()
                }
                onPositionChanged: (mouse) => {
                    if (!pressed || _mode === 0) return
                    var p = mapToItem(null, mouse.x, mouse.y)
                    if (_mode === 1 && Math.abs(p.x - _sx) + Math.abs(p.y - _sy) > 12) { holdTimer.stop(); _mode = 2 }
                    if (_mode === 2 && root.scroller) {
                        var f = root.scroller
                        var maxY = Math.max(f.originY, f.originY + f.contentHeight - f.height)
                        f.contentY = Math.max(f.originY, Math.min(maxY, _startY - (p.y - _sy)))
                        var now = Date.now(), dt = now - _lastT
                        if (dt > 0) _vy = 0.7 * ((p.y - _lastY) / dt * 1000) + 0.3 * _vy
                        _lastY = p.y; _lastT = now
                    } else if (_mode === 3) {
                        root._selectAtScene(p.x, p.y)
                    }
                }
                onReleased: {
                    if (_mode === 2 && root.scroller && Math.abs(_vy) > 150 && Date.now() - _lastT < 90)
                        root.scroller.flick(0, _vy)
                    _end()
                }
                onCanceled: _end()
                onClicked: (mouse) => {
                    if (_wasDrag || !cell.media) return
                    if (root.selecting && root.selectable) {
                        root.toggleSelected(cell.media.id)
                    } else if (mouse.button === Qt.RightButton) {
                        menuLoader.active = true
                        menuLoader.item.popup()
                    } else {
                        root.openItem(cell.index)
                    }
                }
            }
            Loader {
                id: menuLoader
                active: false
                sourceComponent: MediaMenu {
                    media: cell.media
                    onSelectRequested: if (root.selectable && cell.media) {
                        root.selecting = true
                        if (!root.selected[cell.media.id]) root.toggleSelected(cell.media.id)
                    }
                    onChanged: root.mediaChanged()
                }
            }
        }
    }
}
