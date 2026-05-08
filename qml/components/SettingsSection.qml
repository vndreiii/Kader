import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: root
    property string title: ""
    default property alias content: sectionRect.data

    Layout.fillWidth: true
    spacing: 0
    
    Label {
        text: root.title
        font.family: "Roboto Flex"
        font.pixelSize: 18
        font.weight: Font.Medium
        color: ThemeManager.onSurface
        Layout.margins: 4
        Layout.leftMargin: 4
        Layout.bottomMargin: 12
    }
    
    Rectangle {
        id: sectionRect
        Layout.fillWidth: true
        Layout.preferredHeight: contentChildrenLayout.implicitHeight
        radius: 16
        color: ThemeManager.surfaceContainer
        clip: true
        
        ColumnLayout {
            id: contentChildrenLayout
            anchors.fill: parent
            spacing: 0
        }
    }
}
