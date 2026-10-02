import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T

// Material 3 button for every Button in the app. Buttons that bring their
// own background and content keep them, but all share the motion: a quick
// squash on press that springs back on release.
T.Button {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: 10
    leftPadding: 20
    rightPadding: 20
    font.pixelSize: 14
    font.weight: Font.Medium
    hoverEnabled: true

    scale: down ? 0.94 : 1
    Behavior on scale {
        NumberAnimation { duration: control.down ? 90 : 320; easing.type: control.down ? Easing.OutCubic : Easing.OutBack; easing.overshoot: 2.2 }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: !control.enabled ? Qt.alpha(ThemeManager.onSurface, 0.38)
             : control.checked || control.highlighted ? ThemeManager.onSecondaryContainer : ThemeManager.primary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        implicitWidth: 64
        implicitHeight: 40
        // pressed buttons square off a little (M3 Expressive shape morph)
        radius: control.down ? 12 : height / 2
        Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        color: control.checked || control.highlighted ? ThemeManager.secondaryContainer : "transparent"
        border.width: control.flat || control.checked || control.highlighted ? 0 : 1
        border.color: ThemeManager.outline
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: ThemeManager.onSurface
            opacity: control.down ? 0.10 : control.hovered ? 0.08 : 0
        }
    }
}
