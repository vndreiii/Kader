import QtQuick

// Drop-in smooth mouse-wheel scrolling for any Flickable / ListView / GridView.
// Declare it as a direct child of the view:   GridView { SmoothWheel {} }
// One 120-unit wheel notch scrolls ~1.3 rows' worth (`notch` px), touchpads
// scroll 1:1; both glide to their target with a frame-rate independent ease.
// Same feel as the main gallery, so scrolling is consistent everywhere.
WheelHandler {
    id: sw
    property Flickable view: parent ? parent.parent : null   // parent is the view's contentItem
    property real notch: 260
    property real rate: 13          // higher = snappier
    property real _target: 0

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    target: null

    readonly property real _minY: view ? view.originY - view.topMargin : 0
    readonly property real _maxY: view ? Math.max(_minY, view.originY + view.contentHeight - view.height + view.bottomMargin) : 0

    onWheel: function(event) {
        if (!view || event.angleDelta.y === 0 && event.pixelDelta.y === 0) return
        // whole 120-unit notches with no scroll phase = a mouse wheel; some mice also
        // fill pixelDelta with a tiny value, which must not win over the notch.
        var isNotch = event.phase === Qt.NoScrollPhase && event.angleDelta.y !== 0
                      && event.angleDelta.y % 120 === 0
        var dy = (!isNotch && event.pixelDelta.y !== 0)
                 ? event.pixelDelta.y
                 : event.angleDelta.y / 120.0 * notch
        if (!anim.running) _target = view.contentY
        _target = Math.max(_minY, Math.min(_maxY, _target - dy))
        view.cancelFlick()
        anim.running = true
        event.accepted = true
    }

    property FrameAnimation anim: FrameAnimation {
        running: false
        onTriggered: {
            if (!sw.view) { running = false; return }
            var cur = sw.view.contentY
            var d = sw._target - cur
            if (Math.abs(d) < 0.5) {
                sw.view.contentY = sw._target
                running = false
                return
            }
            var next = cur + d * (1 - Math.exp(-sw.rate * frameTime))
            sw.view.contentY = next
            // the view refused the move (real bound): stop chasing it
            if (Math.abs(sw.view.contentY - next) > 0.5) {
                sw._target = sw.view.contentY
                running = false
            }
        }
    }
}
