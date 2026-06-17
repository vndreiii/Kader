import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Item {
    id: root
    property string label: ""
    property string sub: ""
    property Item action: null
    property bool last: false

    width: parent ? parent.width : 0
    height: Math.max(64, infoColumn.height + 32)

    Row {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 16

        Column {
            id: infoColumn
            width: parent.width - (root.action ? Math.max(root.action.width, root.action.implicitWidth) + 16 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            
            Label {
                width: parent.width
                text: root.label
                font.pixelSize: 14
                font.weight: Font.Medium
                color: ThemeManager.onSurface
                wrapMode: Text.Wrap
            }
            Label {
                width: parent.width
                visible: root.sub !== ""
                text: root.sub
                font.pixelSize: 12
                color: ThemeManager.onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }

        Item {
            width: root.action ? Math.max(root.action.width, root.action.implicitWidth) : 0
            height: parent.height
            data: [ root.action ]
            
            onChildrenChanged: {
                if (children.length > 0) {
                    children[0].anchors.verticalCenter = children[0].parent.verticalCenter
                    children[0].anchors.right = children[0].parent.right
                }
            }
        }
    }

    Rectangle {
        visible: !root.last
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 1
        color: ThemeManager.outlineVariant
        opacity: 0.5
    }
}
