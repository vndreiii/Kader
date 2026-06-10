pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Qcm.Material

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
//       onPick:        (key) => model.setSortRole(key)
//       onOrderPicked: (asc) => model.setSortOrder(asc ? 1 : 0)
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
