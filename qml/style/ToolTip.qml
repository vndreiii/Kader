import QtQuick
import QtQuick.Templates as T

// Material 3 plain tooltip for every `ToolTip.text:` in the app: a small
// inverse-surface pill above the control, fading in.
T.ToolTip {
    id: control

    x: parent ? (parent.width - implicitWidth) / 2 : 0
    y: -implicitHeight - 6

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding)

    margins: 8
    topPadding: 5
    bottomPadding: 5
    leftPadding: 10
    rightPadding: 10
    delay: 450

    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    contentItem: Text {
        text: control.text
        font.pixelSize: 12
        font.letterSpacing: 0.4
        color: ThemeManager.inverseOnSurface
        wrapMode: Text.Wrap
    }

    background: Rectangle {
        implicitHeight: 24
        radius: 6
        color: ThemeManager.inverseSurface
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 160; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 }
    }
}
