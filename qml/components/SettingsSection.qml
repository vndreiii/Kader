import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// One settings page (or, while searching, one group of results). Its rows
// draw themselves as an M3 Expressive segmented group.
Column {
    id: root
    property string title: ""
    property string key: ""
    property bool searchHit: true
    property bool searching: false
    default property alias content: contentChildren.data

    width: parent ? parent.width : 0
    spacing: 0

    Label {
        width: parent.width
        text: root.title
        font.pixelSize: root.searching ? 18 : 30
        font.weight: root.searching ? Font.Medium : Font.Normal
        color: ThemeManager.onSurface
        topPadding: root.searching ? 8 : 4
        bottomPadding: root.searching ? 12 : 22
        leftPadding: 4
    }

    Column {
        id: contentChildren
        width: parent.width
        spacing: 2
    }

    Item { width: 1; height: 28 }

    // any row/tile below matches the current search
    function updateHit() {
        function walk(item) {
            for (var i = 0; i < item.children.length; i++) {
                var c = item.children[i]
                if (c.matches !== undefined) { if (c.matches) return true; continue }
                if (walk(c)) return true
            }
            return false
        }
        searchHit = walk(contentChildren)
    }
}
