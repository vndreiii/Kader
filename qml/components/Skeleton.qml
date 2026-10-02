import QtQuick
import ".."

// Loading placeholder: a rounded block that pulses gently while `active`.
// The pulse is an OpacityAnimator, so it runs on the render thread and keeps
// breathing even while the GUI thread is busy (a library query, a QML load).
Rectangle {
    id: root
    property bool active: true
    // The pulse's low point; the block never fully fades.
    property real dim: 0.45

    radius: 12
    color: ThemeManager.surfaceContainerHigh

    SequentialAnimation on opacity {
        running: root.active && root.visible
        loops: Animation.Infinite
        alwaysRunToEnd: true
        OpacityAnimator { from: 1; to: root.dim; duration: 700; easing.type: Easing.InOutSine }
        OpacityAnimator { from: root.dim; to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
}
