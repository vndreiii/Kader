import QtQuick
import ".."

// A free-form block inside a settings group (lists, editors), drawn as one
// segment of the group. `keywords` make it findable from settings search.
Item {
    id: root
    property string keywords: ""
    default property alias content: inner.data
    readonly property Item _view: {
        var p = parent
        while (p && p.settingsQuery === undefined) p = p.parent
        return p
    }
    readonly property string _q: _view ? _view.settingsQuery.toLowerCase() : ""
    readonly property bool matches: _q === "" || keywords.toLowerCase().indexOf(_q) >= 0
    visible: matches
    width: parent ? parent.width : 0
    implicitHeight: inner.implicitHeight
    height: implicitHeight
    SegmentBg { target: root }
    Column {
        id: inner
        width: parent.width
    }
}
