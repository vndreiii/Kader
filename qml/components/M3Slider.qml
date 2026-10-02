import QtQuick
import QtQuick.Controls
import ".."

// Material 3 Expressive slider: thick rounded track split by a slim handle,
// with stop dots for stepped values.
Slider {
    id: root
    implicitHeight: 44
    hoverEnabled: true
    readonly property real _gap: 6
    readonly property real _hx: leftPadding + visualPosition * (availableWidth - handle.width)

    background: Item {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 16
        // active part
        Rectangle {
            x: 0
            width: Math.max(0, root._hx - root.leftPadding - root._gap)
            height: parent.height
            radius: 8
            color: root.enabled ? ThemeManager.primary : Qt.alpha(ThemeManager.onSurface, 0.38)
        }
        // inactive part
        Rectangle {
            x: root._hx - root.leftPadding + root.handle.width + root._gap
            width: Math.max(0, parent.width - x)
            height: parent.height
            radius: 8
            color: ThemeManager.secondaryContainer
        }
        // stops
        Repeater {
            model: root.stepSize > 0 ? Math.round((root.to - root.from) / root.stepSize) + 1 : 0
            Rectangle {
                required property int index
                readonly property real pos: index / Math.max(1, Math.round((root.to - root.from) / root.stepSize))
                width: 4; height: 4; radius: 2
                x: pos * (parent.width - root.handle.width) + root.handle.width / 2 - 2
                y: parent.height / 2 - 2
                visible: Math.abs(pos - root.visualPosition) > 0.01
                color: pos < root.visualPosition ? ThemeManager.onPrimary : ThemeManager.onSecondaryContainer
            }
        }
    }
    handle: Rectangle {
        x: root._hx
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.pressed ? 2 : 4
        height: 44
        radius: 2
        color: ThemeManager.primary
        Behavior on width { NumberAnimation { duration: 120 } }
    }
}
