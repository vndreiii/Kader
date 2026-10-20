import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

// Full-window gallery in select mode: tap photos, Done hands their paths back
// and the page underneath (the memory editor) is exactly as it was left.
Popup {
    id: root
    function _t(k) { return I18n.t(Settings.language, k) }

    parent: Overlay.overlay
    x: 0; y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    modal: true
    padding: 0
    closePolicy: Popup.CloseOnEscape

    property var chosen: []             // paths already in the memory
    signal picked(var paths)

    property var _items: []

    onAboutToShow: {
        _items = Memories.libraryPhotos()
        var sel = {}
        for (var i = 0; i < _items.length; i++)
            if (chosen.indexOf(_items[i].file_path) >= 0) sel[_items[i].id] = true
        grid.selected = sel
        grid.selecting = true
    }

    background: Rectangle { color: ThemeManager.surface }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 16
            spacing: 12
            M3IconButton { icon: "close"; onClicked: root.close() }
            Label {
                Layout.fillWidth: true
                text: root._t("memory_select_photos")
                font.pixelSize: 20; font.weight: Font.Medium
                color: ThemeManager.onSurface
            }
            Label { text: grid.selectedCount; color: ThemeManager.onSurfaceVariant; font.pixelSize: 15 }
            M3Button {
                kind: "filled"
                text: root._t("done")
                onClicked: {
                    var out = []
                    for (var i = 0; i < root._items.length; i++)
                        if (grid.selected[root._items[i].id]) out.push(root._items[i].file_path)
                    // keep the order photos were first added in, new ones after
                    var ordered = root.chosen.filter(function (p) { return out.indexOf(p) >= 0 })
                    out.forEach(function (p) { if (ordered.indexOf(p) < 0) ordered.push(p) })
                    root.picked(ordered)
                    root.close()
                }
            }
        }

        ThumbGrid {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 12; Layout.rightMargin: 12
            items: root._items
            selectable: true
            selecting: true
            // taps toggle (selecting stays on); opening the viewer is not wanted here
            onOpenItem: function (index) { if (root._items[index]) grid.toggleSelected(root._items[index].id) }
        }
    }
}
