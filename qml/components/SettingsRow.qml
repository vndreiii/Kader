import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property string label: ""
    property string sub: ""
    property Item action: null
    property bool last: false

    Layout.fillWidth: true
    height: Math.max(64, rowLayout.implicitHeight + 32)
    color: "transparent"

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: root.label
                font.pixelSize: 14
                font.weight: Font.Medium
                color: ThemeManager.onSurface
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Label {
                visible: root.sub !== ""
                text: root.sub
                font.pixelSize: 12
                color: ThemeManager.onSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Item {
            id: actionContainer
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.action ? root.action.implicitWidth : 0
            implicitHeight: root.action ? root.action.implicitHeight : 0
            data: [ root.action ]
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
