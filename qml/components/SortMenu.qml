pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Reusable, UI-agnostic sort dropdown. Themed via M3Menu/M3MenuItem.
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
M3Menu {
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

    // ── Sort fields ──────────────────────────────────────────────────────────
    Instantiator {
        model: root.fields
        delegate: M3MenuItem {
            required property var modelData
            text: modelData.label
            checkable: true
            checked: root.currentKey === modelData.key
            onTriggered: root.pick(modelData.key)
        }
        onObjectAdded: (index, object) => root.insertItem(index, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }

    M3MenuSeparator {}

    // ── Order ────────────────────────────────────────────────────────────────
    M3MenuItem {
        text: root.ascLabel
        checkable: true
        checked: root.ascending
        onTriggered: root.orderPicked(true)
    }
    M3MenuItem {
        text: root.descLabel
        checkable: true
        checked: !root.ascending
        onTriggered: root.orderPicked(false)
    }
}
