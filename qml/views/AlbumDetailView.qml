import QtQuick
import QtQuick.Controls
import "../components"

Item {
    id: root
    property string folderPath: ""
    property string albumName:  ""

    signal openViewer(var mediaData, int index)

    Component.onCompleted: {
        TimelineModel.setFolderFilter(folderPath)
    }
    Component.onDestruction: {
        TimelineModel.setFolderFilter("")
        // Clear topbar title — walk up to find ApplicationWindow
        var win = parent
        while (win && win.detailTitle === undefined) win = win.parent
        if (win) win.detailTitle = ""
    }

    MediaGrid {
        anchors.fill: parent
        onOpenViewer: (data, idx) => root.openViewer(data, idx)
    }
}
