pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import Qcm.Material as MD

// A Menu that positions itself as a submenu relative to a trigger item.
// Port of m3e's <m3e-menu id="..."> — declared separately from its trigger.
//
// Pair with CascadeMenuItem (the trigger):
//
//   CascadeMenuItem { text: "Fruits with A"; submenu: fruitsMenu }
//
//   CascadeMenu {
//       id: fruitsMenu
//       MenuItem { text: "Apricot" }
//       MenuItem { text: "Avocado" }
//       CascadeMenuItem { text: "Apples"; submenu: applesMenu }
//   }
//
//   CascadeMenu {
//       id: applesMenu
//       MenuItem { text: "Fuji" }
//       MenuItem { text: "Granny Smith" }
//   }

MD.Menu {
    id: root

    // Open anchored to the right side of triggerItem (a CascadeMenuItem).
    // Aligns the menu surface flush with the trigger's top, accounting for
    // the menu's own verticalPadding so the first item sits at trigger-top.
    function openFrom(triggerItem) {
        if (!triggerItem) return
        popup(triggerItem, triggerItem.width - 4, -root.verticalPadding)
    }

    // Slide in from the anchor side — adds depth to the cascade motion.
    enter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                from: 0; to: 1
                duration: MD.Token.duration.short4
                easing: MD.Token.easing.emphasized_decelerate
            }
            NumberAnimation {
                property: "x"
                from: root.x - 10; to: root.x
                duration: MD.Token.duration.short4
                easing: MD.Token.easing.emphasized_decelerate
            }
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: MD.Token.duration.short2
            easing: MD.Token.easing.emphasized_decelerate
        }
    }
}
