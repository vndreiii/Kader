import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// Back button + title/subtitle for pages pushed inside a tab.
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    default property alias actions: actionRow.data
    signal back()

    anchors { left: parent.left; right: parent.right; top: parent.top }
    height: 84

    RowLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 24 }
        spacing: 12
        RoundButton {
            flat: true
            Layout.preferredWidth: 48; Layout.preferredHeight: 48
            contentItem: MaterialSymbol { name: "arrow_back"; size: 24; color: ThemeManager.onSurface }
            onClicked: root.back()
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: 26
                font.weight: Font.Medium
                color: ThemeManager.onSurface
                elide: Text.ElideRight
            }
            Label {
                visible: text.length > 0
                text: root.subtitle
                font.pixelSize: 14
                color: ThemeManager.onSurfaceVariant
            }
        }
        RowLayout { id: actionRow; spacing: 8 }
    }
}
