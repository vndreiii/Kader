import QtQuick
import QtQuick.Templates as T

// Material 3 outlined text field for every TextField in the app (fields that
// set their own background keep it).
T.TextField {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            placeholder.implicitWidth + leftPadding + rightPadding, 120)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding, 48)

    leftPadding: 16
    rightPadding: 16
    topPadding: 12
    bottomPadding: 12
    font.pixelSize: 15
    verticalAlignment: TextInput.AlignVCenter
    color: enabled ? ThemeManager.onSurface : Qt.alpha(ThemeManager.onSurface, 0.38)
    selectionColor: Qt.alpha(ThemeManager.primary, 0.35)
    selectedTextColor: ThemeManager.onSurface
    placeholderTextColor: ThemeManager.onSurfaceVariant

    Text {
        id: placeholder
        x: control.leftPadding
        y: control.topPadding
        width: control.width - (control.leftPadding + control.rightPadding)
        height: control.height - (control.topPadding + control.bottomPadding)
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        verticalAlignment: control.verticalAlignment
        elide: Text.ElideRight
        visible: !control.length && !control.preeditText
    }

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 48
        radius: 12
        color: ThemeManager.surfaceContainerHighest
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? ThemeManager.primary
                    : control.hovered ? ThemeManager.onSurface : ThemeManager.outline
    }
}
