import QtQuick
import QtQuick.Controls
import ".."

// Filled text field in the app's style.
TextField {
    id: root
    color: ThemeManager.onSurface
    placeholderTextColor: ThemeManager.onSurfaceVariant
    selectionColor: Qt.alpha(ThemeManager.primary, 0.35)
    leftPadding: 16; rightPadding: 16; topPadding: 12; bottomPadding: 12
    background: Rectangle {
        radius: 12
        color: ThemeManager.surfaceContainerHighest
        border.color: root.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant
        border.width: root.activeFocus ? 2 : 1
    }
}
