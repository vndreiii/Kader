pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// Material 3 styled menu item — the local replacement for QmlMaterial's
// MD.MenuItem + StateMenuItem. Fully themed from ThemeManager tokens so menus
// stop falling back to Qt's unstyled Basic look.
//
// Mirrors M3 spec: 48px row, label-large text, on_surface foreground, a
// translucent state layer for hover/press (instead of a solid highlight), and
// a leading check indicator for checkable rows.
T.MenuItem {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding,
                            implicitIndicatorWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding,
                             implicitIndicatorHeight + topPadding + bottomPadding)

    padding: 12
    spacing: 12

    icon.width: 24
    icon.height: 24

    // M3 "label large"
    font.pixelSize: 14
    font.weight: Font.Medium
    font.letterSpacing: 0.1

    // Leading check indicator — only for checkable rows (sort order, type filter).
    indicator: Rectangle {
        x: control.mirrored ? control.width - width - control.leftPadding : control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        implicitWidth: control.checkable ? 20 : 0
        implicitHeight: 20
        visible: control.checkable
        radius: 6
        color: control.checked ? ThemeManager.primary : "transparent"
        border.width: control.checked ? 0 : 2
        border.color: ThemeManager.onSurfaceVariant
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

        M3Icon {
            anchors.centerIn: parent
            name: "check"
            size: 14
            color: ThemeManager.onPrimary
            visible: control.checked
        }
    }

    contentItem: Text {
        readonly property real _lead: control.checkable ? (20 + control.spacing) : 0
        readonly property real _trail: control.subMenu ? (22 + control.spacing) : 0
        leftPadding: control.mirrored ? _trail : _lead
        rightPadding: control.mirrored ? _lead : _trail
        text: control.text
        font: control.font
        color: control.enabled ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant
        opacity: control.enabled ? 1.0 : 0.38
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
    }

    arrow: M3Icon {
        x: control.mirrored ? control.padding : control.width - width - control.padding
        y: control.topPadding + (control.availableHeight - height) / 2
        visible: control.subMenu
        size: 22
        name: "chevron_right"
        color: ThemeManager.onSurfaceVariant
    }

    background: Rectangle {
        implicitWidth: 224
        implicitHeight: 44
        color: "transparent"

        // M3 state layer: translucent on_surface overlay for hover / press /
        // keyboard highlight — replaces Basic's harsh solid accent fill.
        Rectangle {
            anchors.fill: parent
            color: ThemeManager.onSurface
            opacity: !control.enabled ? 0
                   : control.down ? 0.10
                   : (control.hovered || control.highlighted) ? 0.08
                   : 0
            Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
        }
    }
}
