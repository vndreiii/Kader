import QtQuick
import QtQuick.Controls
import "../components"

Item {
    id: root
    property string folderPath: ""
    property string albumName:  ""

    signal openViewer(var mediaData, int index)

    Component.onCompleted: {
        TimelineModel.filterMode = 0
        TimelineModel.setMimeFilter("")
        TimelineModel.setFolderFilter(folderPath)
    }
    Component.onDestruction: {
        TimelineModel.setFolderFilter("")
    }

    MediaGrid {
        anchors.fill: parent
        onOpenViewer: (data, idx) => root.openViewer(data, idx)
    }
}
