pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Qcm.Material
import Qcm.Material as MD

// Reusable, UI-agnostic sort dropdown.
//
// Feed it a declarative `fields` list and bind the current selection; it emits
// which field/order the user picked. Any view — or a future dashboard — reuses
// it by passing a different `fields` array. It owns no model state of its own.
//
//   SortMenu {
//       fields: [{ key: 0, label: "Name" }, { key: 1, label: "Size" }]
//       currentKey: model.sortRole
//       ascending:  model.sortOrder === 1
//       onPick:        (key) => model.sortRole = key
//       onOrderPicked: (asc) => model.sortOrder = asc ? 1 : 0
//   }
//
// Extra items (e.g. a type filter) may be nested in the instance; they appear
// after the order rows.
Menu {
    id: root

    property var    fields: []             // [{ key: int, label: string }]
    property int    currentKey: 0
    property bool   ascending: false
    property string ascLabel:  "Ascending"
    property string descLabel: "Descending"

    signal pick(int key)
    signal orderPicked(bool ascending)

    // Cascade submenus (e.g. the type filter) open to the side as one focus unit.
    cascade: true

    // Override the Menu's item delegate purely to swap the submenu arrow: the MD
    // icon-font glyph (arrow_right) renders as a tofu box in this build, so we use
    // the SVG-path M3Icon instead. Mirrors MD.Menu's default delegate otherwise.
    // (Only submenu-trigger items use this delegate; field/order items are explicit
    // instances created elsewhere and keep their own behavior.)
    delegate: MD.MenuItem {
        id: m_item
        arrow: M3Icon {
            x: m_item.mirrored ? m_item.padding : m_item.width - width - m_item.padding
            y: m_item.topPadding + (m_item.availableHeight - height) / 2
            visible: !!m_item.subMenu
            size: 18
            name: "chevron_right"
            color: m_item.mdState.textColor
        }
        function clickedCB() {
            if ((action as MD.Action)?.closeMenu || root.autoClose)
                triggered();
        }
        Component.onCompleted: {
            MD.Util.disconnectAll(m_item, "clicked()");
            m_item.clicked.connect(clickedCB);
        }
    }

    // ── Sort fields ──────────────────────────────────────────────────────────
    Instantiator {
        model: root.fields
        delegate: MenuItem {
            required property var modelData
            text: modelData.label
            checkable: true
            checked: root.currentKey === modelData.key
            onTriggered: root.pick(modelData.key)
        }
        onObjectAdded: (index, object) => root.insertItem(index, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }

    MenuSeparator {}

    // ── Order ────────────────────────────────────────────────────────────────
    MenuItem {
        text: root.ascLabel
        checkable: true
        checked: root.ascending
        onTriggered: root.orderPicked(true)
    }
    MenuItem {
        text: root.descLabel
        checkable: true
        checked: !root.ascending
        onTriggered: root.orderPicked(false)
    }
}
