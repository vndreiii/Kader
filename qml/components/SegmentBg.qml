import QtQuick
import ".."

// Material 3 Expressive segmented-list container: each item is its own
// surface; the first and last visible items of a group get large outer
// corners, adjoining edges small inner ones (24 / 4 px), 2 px apart.
Rectangle {
    id: bg
    property Item target: parent
    property bool hovered: false
    readonly property var _sibs: target && target.parent ? target.parent.visibleChildren : []
    readonly property bool first: _sibs.length > 0 && _sibs[0] === target
    readonly property bool last: _sibs.length > 0 && _sibs[_sibs.length - 1] === target
    anchors.fill: parent
    z: -1
    topLeftRadius: first ? 24 : 4
    topRightRadius: first ? 24 : 4
    bottomLeftRadius: last ? 24 : 4
    bottomRightRadius: last ? 24 : 4
    color: ThemeManager.surfaceContainer
    Rectangle {
        anchors.fill: parent
        topLeftRadius: parent.topLeftRadius; topRightRadius: parent.topRightRadius
        bottomLeftRadius: parent.bottomLeftRadius; bottomRightRadius: parent.bottomRightRadius
        color: ThemeManager.onSurface
        opacity: bg.hovered ? 0.04 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
    }
}
