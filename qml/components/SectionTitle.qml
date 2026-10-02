import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

// Section heading for the Search tab: title, optional count, and a text
// action ("Show all", "Manage") on the right.
RowLayout {
    id: root
    property string text: ""
    property int count: -1              // -1: no count shown
    property string showAllText: I18n.t(Settings.language, "show_all")
    property bool actionVisible: count > 0
    signal showAll()

    Layout.fillWidth: true
    spacing: 10
    Label {
        text: root.text
        font.pixelSize: 22
        font.weight: Font.Medium
        color: ThemeManager.onSurface
    }
    Rectangle {
        visible: root.count > 0
        Layout.preferredHeight: 24
        Layout.preferredWidth: countLabel.implicitWidth + 16
        radius: 12
        color: ThemeManager.surfaceContainerHighest
        Label {
            id: countLabel
            anchors.centerIn: parent
            text: root.count
            font.pixelSize: 12
            color: ThemeManager.onSurfaceVariant
        }
    }
    Item { Layout.fillWidth: true }
    M3Button {
        visible: root.actionVisible
        flat: true
        text: root.showAllText
        onClicked: root.showAll()
    }
}
