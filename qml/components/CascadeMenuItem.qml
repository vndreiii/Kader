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

    // Always show the right-arrow indicator when a submenu is wired up.
    // Uses our SVG-path M3Icon (the MD icon font has no glyph here → renders tofu).
    arrow: M3Icon {
        x: root.mirrored ? root.padding : root.width - width - root.padding
        y: root.topPadding + (root.availableHeight - height) / 2
        visible: !!root.submenu
        size: 18
        name: "chevron_right"
        color: root.mdState.textColor
    }

    // Open submenu on hover, and feed hover state to it so it can decide when to
    // close (the submenu stays open while either the trigger or itself is hovered).
    onHoveredChanged: {
        if (!submenu) return
        submenu.triggerHovered = hovered
        if (hovered) submenu.openFrom(root)
    }

    // Also open on click/tap so keyboard and touch navigation works
    onClicked: {
        if (submenu) submenu.openFrom(root)
    }
}
