pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import QtQuick.Controls as C

// Material 3 styled menu surface — the local replacement for QmlMaterial's
// MD.Menu. Themed from ThemeManager tokens so menus get the M3 surface,
// rounding and grow/fade motion instead of Qt's unstyled Basic popup.
T.Menu {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding)

    margins: 0
    padding: 0
    verticalPadding: 8
    overlap: 0

    // Items added via Action / model paths get themed too.
    delegate: M3MenuItem {}

    // M3 grow + fade (emphasized-decelerate ≈ OutQuint / OutCubic).
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: ThemeManager.durShort; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale";  from: 0.92; to: 1.0; duration: ThemeManager.durMed; easing.type: Easing.OutQuint }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: ThemeManager.durShort; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale";  from: 1.0; to: 0.92; duration: ThemeManager.durShort; easing.type: Easing.OutQuint }
    }

    contentItem: ListView {
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: Window.window ? contentHeight + control.topPadding + control.bottomPadding > Window.window.height : false
        clip: true
        currentIndex: control.currentIndex
        keyNavigationEnabled: false
        T.ScrollIndicator.vertical: C.ScrollIndicator {}
    }

    background: Rectangle {
        implicitWidth: 220
        implicitHeight: 44
        radius: 8
        // Tonal elevation: a lifted surface tint reads as "raised" on dark themes,
        // and a hairline keeps it crisp against the content behind it.
        color: ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: ThemeManager.outlineVariant
    }
}
