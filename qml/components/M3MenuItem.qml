pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// 1:1 local port of QmlMaterial's MD.MenuItem + StateMenuItem — no Qcm.Material
// dependency. Driven by ThemeManager tokens.
//
//   row height 48 · padding 16 · spacing 16 · label-large (14 / Medium / +0.1)
//   text on_surface · selected row = secondary_container fill
//   hover/press = on_surface state layer (8% / 10%) + center ripple
T.MenuItem {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding,
                            implicitIndicatorWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: 16
    verticalPadding: 0
    spacing: 16

    icon.width: 24
    icon.height: 24

    // label_large
    font.pixelSize: 14
    font.weight: Font.Medium
    font.letterSpacing: 0.1

    // QmlMaterial's MenuItem had its CheckIndicator disabled; selection is shown
    // by the secondary_container row fill (see background), so no leading box.
    indicator: null

    // Leading icon (Material Symbols name); every menu item should have one
    // so menus can be scanned at a glance.
    property string iconName: ""
    // destructive actions (delete, …) in the error colour
    property bool destructive: false
    readonly property color _fg: destructive ? ThemeManager.error
                                 : control.checked ? ThemeManager.onSecondaryContainer : ThemeManager.onSurface

    contentItem: Item {
        readonly property real _trail: control.subMenu ? (22 + control.spacing) : 0
        implicitWidth: (icon.visible ? icon.width + control.spacing : 0) + label.implicitWidth + _trail
        implicitHeight: Math.max(24, label.implicitHeight)
        opacity: control.enabled ? 1.0 : 0.38
        MaterialSymbol {
            id: icon
            visible: control.iconName !== ""
            anchors.verticalCenter: parent.verticalCenter
            x: control.mirrored ? parent.width - width : 0
            name: control.iconName
            size: 22
            fill: control.checked ? 1 : 0
            color: control.destructive ? ThemeManager.error
                 : control.checked ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            x: control.mirrored ? parent._trail : (icon.visible ? icon.width + control.spacing : 0)
            width: parent.width - (icon.visible ? icon.width + control.spacing : 0) - parent._trail
            text: control.text
            font: control.font
            color: control._fg
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }
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
        implicitHeight: 48
        // Selected row fill (StateMenuItem.backgroundColor).
        color: control.checked ? ThemeManager.secondaryContainer : "transparent"
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

        // State + ripple layer, clipped to the row.
        Item {
            anchors.fill: parent
            clip: true

            // Hover / focus / press state layer (on_surface).
            Rectangle {
                anchors.fill: parent
                color: ThemeManager.onSurface
                opacity: !control.enabled ? 0
                       : control.down ? 0.10
                       : (control.hovered || control.highlighted) ? 0.08
                       : 0
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
            }

            // Press ripple — expands from centre, fades on release.
            Rectangle {
                id: ripple
                anchors.centerIn: parent
                width: parent.width * 1.8
                height: width
                radius: width / 2
                color: ThemeManager.onSurface
                opacity: control.down ? 0.10 : 0.0
                scale: control.down ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutCubic } }
                Behavior on scale  { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutCubic } }
            }
        }
    }
}
