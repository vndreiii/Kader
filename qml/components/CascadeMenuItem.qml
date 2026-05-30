pragma ComponentBehavior: Bound
import QtQuick
import Qcm.Material as MD

// A MenuItem that opens a CascadeMenu on hover and click.
// Port of m3e's <m3e-menu-trigger for="..."> — references its submenu by direct property.
//
// Usage (mirrors m3e: trigger + separately-declared target):
//
//   CascadeMenuItem { text: "Fruits with A"; submenu: fruitsMenu }
//   CascadeMenu { id: fruitsMenu; ... }

MD.MenuItem {
    id: root

    property CascadeMenu submenu: null

    // Always show the right-arrow indicator when a submenu is wired up
    arrow: MD.Icon {
        x: root.mirrored ? root.padding : root.width - width - root.padding
        y: root.topPadding + (root.availableHeight - height) / 2
        visible: !!root.submenu
        size: 24
        name: MD.Token.icon.arrow_right
        color: root.mdState.textColor
    }

    // Open submenu on hover (desktop — feels instant and natural)
    onHoveredChanged: {
        if (hovered && submenu) submenu.openFrom(root)
    }

    // Also open on click/tap so keyboard and touch navigation works
    onClicked: {
        if (submenu) submenu.openFrom(root)
    }
}
