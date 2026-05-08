import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Column {
    id: root
    property string title: ""
    default property alias content: contentChildren.data

    width: parent ? parent.width : 0
    spacing: 0
    
    Label {
        width: parent.width
        text: root.title
        font.family: "Roboto Flex"
        font.pixelSize: 18
        font.weight: Font.Medium
        color: ThemeManager.onSurface
        bottomPadding: 12
        leftPadding: 4
    }
    
    Rectangle {
        width: parent.width
        height: contentChildren.height
        radius: 16
        color: ThemeManager.surfaceContainer
        clip: true
        
        Column {
            id: contentChildren
            width: parent.width
            spacing: 0
        }
    }

    // Bottom margin for the whole section
    Item { width: 1; height: 24 }
}
