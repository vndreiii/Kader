import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."
import "../I18n.js" as I18n
import "../Paths.js" as Paths

Item {
    id: root
    property var tileData: null
    property bool selectable: false
    property bool selected: false
    signal open()
    signal toggleFav()
    signal selectToggle()
    signal enterSelectionMode()
    // hold-then-drag: select every tile the pointer passes (scene coordinates)
    signal dragSelectAt(real sceneX, real sceneY)
    property bool _dragSelecting: false
    // the Flickable the tile sits in: a quick drag scrolls it (see MouseArea)
    property Flickable scroller: null
    signal scrollingChanged(bool on)
    // List view: a row with a small thumbnail and the file's details
    property bool listMode: false
    readonly property real _radius: listMode ? 10 : 16

    readonly property var _d: (tileData !== null && tileData !== undefined) ? tileData : ({})
    readonly property bool _isGif: (root._d.mime_type || "").toString() === "image/gif"

    // Whichever media element is active — used to gate layer FBO allocation
    readonly property int _activeStatus: root._isGif ? gifImg.status : img.status

    // ── List row: hover / selected background behind the whole row ─────────
    Rectangle {
        visible: root.listMode
        anchors.fill: parent
        radius: 14
        color: root.selected ? Qt.alpha(ThemeManager.primary, 0.14)
             : mouseArea.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
    }

    // The picture's box: the whole tile, or a square at the left of a list row
    Item {
        id: frame
        x: root.listMode ? 6 : 0
        y: root.listMode ? 4 : 0
        width: root.listMode ? height : root.width
        height: root.listMode ? root.height - 8 : root.height
    }

    // ── Loading placeholder: pulses until the thumbnail is decoded ────────
    Skeleton {
        anchors.fill: frame
        radius: root._radius
        active: root._activeStatus === Image.Loading || root._activeStatus === Image.Null
    }

    // ── Round mask shape — feeds MultiEffect below ────────────────────────
    Rectangle {
        id: roundMask
        anchors.fill: frame
        radius: root._radius
        color: "white"
        visible: false
        // Only allocate the FBO once the active media element is loaded
        layer.enabled: root._activeStatus === Image.Ready
    }

    // ── All content — clipped to rounded rect via MultiEffect ─────────────
    Item {
        id: contentLayer
        anchors.fill: frame

        Image {
            id: img
            anchors.fill: parent
            visible: !root._isGif
            // Always use the async 768px thumbnail provider. Never decode the
            // full-resolution original in the grid — that was the main scroll
            // stutter (a 20MP decode + huge texture upload per wide tile mid-fling).
            source: {
                if (root._isGif) return ""
                var p = root._d.thumb || ""           // "image://thumbnails/<path>"
                if (p) return p
                var fp = root._d.file_path || ""
                return Paths.fileUrl(fp)
            }
            // Cap decode resolution so even the file:// fallback can't upload a
            // giant texture. 768 matches the cached thumbnail's longest edge.
            sourceSize.height: 768
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            autoTransform: true
            cache: true

            scale: mouseArea.containsMouse ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        }

        // Animated GIF — plays directly from file, loops automatically
        AnimatedImage {
            id: gifImg
            anchors.fill: parent
            visible: root._isGif
            source: root._isGif ? Paths.fileUrl(root._d.file_path) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            playing: root._isGif
            cache: false

            scale: mouseArea.containsMouse ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
        }

        // Video badge
        Rectangle {
            visible: root._d.mime_type ? root._d.mime_type.toString().startsWith("video/") : false
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            width: 24; height: 24; radius: 12
            color: Qt.alpha("black", 0.55)
            M3Icon { anchors.centerIn: parent; name: "play"; size: 14; color: "white" }
        }

        // GIF badge
        Rectangle {
            visible: root._isGif
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            height: 18; radius: 9; width: gifLabel.implicitWidth + 10
            color: Qt.alpha("black", 0.55)
            Label { id: gifLabel; anchors.centerIn: parent; text: "GIF"; color: "white"; font.pixelSize: 9; font.weight: Font.Bold }
        }

        // Selection checkmark — z above the privacy cover so hidden tiles stay
        // selectable (restore/delete) even while their thumbnail is covered.
        Rectangle {
            z: 10
            visible: root.selectable || root.selected
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: root.listMode ? 4 : 8
            width: 24; height: 24; radius: 12
            // empty ring until picked; filled + check only when selected
            color: root.selected ? ThemeManager.primary : Qt.alpha("black", 0.35)
            border.width: root.selected ? 0 : 2
            border.color: "white"
            Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
            M3Icon { anchors.centerIn: parent; visible: root.selected; name: "check"; size: 16; color: ThemeManager.onPrimary }
        }

        // Favorite button — 28dp visual chip inside a 48dp hit area (centered).
        // Reveal-on-hover still follows the whole-tile MouseArea (below), only
        // the click target itself is enlarged.
        Item {
            visible: !root.listMode
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8 - (48 - 28) / 2
            width: 48; height: 48

            Rectangle {
                id: favButton
                anchors.centerIn: parent
                width: 28; height: 28; radius: 14
                color: Qt.alpha("black", 0.45)
                opacity: (mouseArea.containsMouse || (root._d.is_favorite ? true : false)) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                M3Icon {
                    anchors.centerIn: parent
                    name: (root._d.is_favorite ? true : false) ? "favorite_fill" : "favorite"
                    size: 16
                    color: (root._d.is_favorite ? true : false) ? ThemeManager.tertiaryContainer : "white"
                }
            }
        }

        // Date meta on hover
        Rectangle {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            anchors.leftMargin: 28; anchors.bottomMargin: 8
            height: 24; radius: 12
            color: Qt.alpha("black", 0.4)
            visible: !root.listMode && mouseArea.containsMouse && !!root._d.creation_date
            Row {
                anchors.centerIn: parent; leftPadding: 8; rightPadding: 8
                Label {
                    text: {
                        var d = root._d.creation_date
                        if (!d) return ""
                        return Qt.formatDateTime(new Date(d * 1000), "dd MMM")
                    }
                    color: "white"; font.pixelSize: ThemeManager.fontLabelS; font.weight: Font.Medium
                }
            }
        }

        // Privacy cover — hidden items shown OUTSIDE the Hidden view (e.g. still
        // mixed into All/Favorites/Trash) must never reveal their thumbnail.
        // Opaque, sits above the image/badges/favorite button/date label but
        // below the selection checkmark (z: 10 above) so the tile stays
        // selectable for restore/delete without ever exposing the media.
        Rectangle {
            id: privacyCover
            z: 5
            visible: root._isHidden && TimelineModel.filterMode !== 3 /* HiddenMode */
            anchors.fill: parent
            radius: root._radius
            color: "black"
            M3Icon {
                anchors.centerIn: parent
                name: "visibility_off"
                size: 28
                color: "white"
            }
        }

        // Skip the FBO entirely while the placeholder is showing — no media loaded yet
        layer.enabled: root._activeStatus === Image.Ready
        layer.effect: MultiEffect {
            maskEnabled: true
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            maskSource: roundMask
        }
    }

    // ── Selection border (outside clip so ring is fully visible) ──────────
    Rectangle {
        anchors.fill: frame; radius: root._radius
        color: "transparent"
        border.width: root.selected && !root.listMode ? 3 : 0
        border.color: ThemeManager.primary
        visible: root.selected
    }

    // ── List row details: name · date · type, size, dimensions ────────────
    Loader {
        active: root.listMode
        z: 2   // above the tile's MouseArea so the favourite toggle gets clicks
        anchors { left: frame.right; leftMargin: 16; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        height: parent.height
        sourceComponent: Item {
            readonly property string _path: root._d.file_path || ""
            readonly property bool _two: root.height < 60   // dense: one line
            function _size(b) {
                if (!b) return ""
                var u = ["B", "KB", "MB", "GB"], i = 0
                while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
                return (i === 0 ? b : b.toFixed(1)) + " " + u[i]
            }
            readonly property string _details: [
                root._d.type_label || "",
                _size(root._d.file_size),
                root._d.width > 0 && root._d.height > 0 ? root._d.width + " × " + root._d.height : ""
            ].filter(function (t) { return t !== "" }).join("  ·  ")
            readonly property string _date: root._d.creation_date
                ? Qt.formatDateTime(new Date(root._d.creation_date * 1000), "d MMM yyyy, hh:mm") : ""

            Column {
                anchors.left: parent.left
                anchors.right: favBtn.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    width: parent.width
                    text: _path.substring(_path.lastIndexOf("/") + 1)
                    elide: Text.ElideMiddle
                    color: ThemeManager.onSurface
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }
                Label {
                    width: parent.width
                    visible: !_two
                    text: _date + (_details !== "" ? "  ·  " + _details : "")
                    elide: Text.ElideRight
                    color: ThemeManager.onSurfaceVariant
                    font.pixelSize: 13
                }
            }
            // favourite toggle at the end of the row
            Item {
                id: favBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40
                opacity: (mouseArea.containsMouse || favMa.containsMouse || root._d.is_favorite) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
                M3Icon {
                    anchors.centerIn: parent
                    name: root._d.is_favorite ? "favorite_fill" : "favorite"
                    size: 20
                    color: root._d.is_favorite ? ThemeManager.tertiary : ThemeManager.onSurfaceVariant
                }
                MouseArea { id: favMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFav() }
            }
        }
    }

    // ── Context menu ──────────────────────────────────────────────────────
    property string _filePath:   root._d.file_path   || ""
    property int    _mediaId:    root._d.id          || 0
    property bool   _isFav:      root._d.is_favorite ? true : false
    property bool   _isTrashed:  root._d.is_trashed  ? true : false
    property bool   _isHidden:   root._d.is_hidden   ? true : false
    property string _folderPath: root._d.folder_path || ""

    // Context menu (shared with the Search page), created on first use —
    // instantiating it for every tile hurt scrolling as delegates recycle.
    function _showMenu() {
        menuLoader.active = true
        menuLoader.item.popup()
    }
    Loader {
        id: menuLoader
        active: false
        sourceComponent: MediaMenu {
            media: root._d
            onSelectRequested: root.enterSelectionMode()
        }
    }

    // ── Mouse area ────────────────────────────────────────────────────────
    // A press is a click, a hold or a drag, decided here rather than by the
    // Flickable, so touchpad wobble can't turn a hold into a scroll:
    //   • still for 300 ms → selection starts here; keep holding and drag to
    //     select everything passed over
    //   • moves more than 12 px first → scrolls the grid (with a fling)
    //   • neither → a click
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true

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
                if (mouseArea._mode !== 1) return
                mouseArea._mode = 3
                root._dragSelecting = true
                if (root.selectable) { if (!root.selected) root.selectToggle() }
                else root.enterSelectionMode()
            }
        }
        function _end() {
            holdTimer.stop()
            if (_mode === 2) root.scrollingChanged(false)
            _wasDrag = _mode >= 2
            _mode = 0
            root._dragSelecting = false
        }

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
            if (_mode === 1 && Math.abs(p.x - _sx) + Math.abs(p.y - _sy) > 12) {
                holdTimer.stop()
                _mode = 2
                root.scrollingChanged(true)
            }
            if (_mode === 2 && root.scroller) {
                var f = root.scroller
                var maxY = Math.max(f.originY, f.originY + f.contentHeight - f.height)
                f.contentY = Math.max(f.originY, Math.min(maxY, _startY - (p.y - _sy)))
                var now = Date.now(), dt = now - _lastT
                if (dt > 0) _vy = 0.7 * ((p.y - _lastY) / dt * 1000) + 0.3 * _vy
                _lastY = p.y; _lastT = now
            } else if (_mode === 3) {
                root.dragSelectAt(p.x, p.y)
            }
        }
        onReleased: {
            if (_mode === 2 && root.scroller && Math.abs(_vy) > 150 && Date.now() - _lastT < 90)
                root.scroller.flick(0, _vy)
            _end()
        }
        onCanceled: _end()
        onClicked: (mouse) => {
            if (_wasDrag) return
            if (mouse.button === Qt.RightButton) {
                if (root.selectable) root.selectToggle()
                else root._showMenu()
            } else if (root.selectable) {
                root.selectToggle()
            } else if (!privacyCover.visible) {
                root.open()
            }
        }
    }

    // Favourite toggle's click target, above the tile's MouseArea (the heart
    // itself is drawn inside the clipped picture). Hover passes through.
    MouseArea {
        visible: !root.listMode
        anchors { top: frame.top; right: frame.right }
        width: 48; height: 48
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleFav()
    }
}
