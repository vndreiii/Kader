import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// A call-to-action / status card (feature set-up, downloads, errors).
Rectangle {
    id: root
    property string icon: "info"
    property string title: ""
    property string body: ""
    property string action: ""
    property real progress: -1          // 0..1 shows a progress bar
    signal triggered()

    implicitHeight: row.implicitHeight + 40
    radius: 24
    color: ThemeManager.surfaceContainerLow
    border.width: 1
    border.color: ThemeManager.outlineVariant

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 20 }
        spacing: 18
        Rectangle {
            Layout.preferredWidth: 52; Layout.preferredHeight: 52
            Layout.alignment: Qt.AlignTop
            radius: 26
            color: ThemeManager.primaryContainer
            MaterialSymbol { anchors.centerIn: parent; name: root.icon; size: 26; color: ThemeManager.onPrimaryContainer }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Label {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: 17
                font.weight: Font.Medium
                color: ThemeManager.onSurface
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                visible: root.body.length > 0
                text: root.body
                font.pixelSize: 14
                color: ThemeManager.onSurfaceVariant
                wrapMode: Text.WordWrap
            }
            M3LinearProgress {
                visible: root.progress >= 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                from: 0; to: 1; value: Math.max(0, root.progress)
            }
        }
        M3Button {
            visible: root.action.length > 0
            text: root.action
            highlighted: true
            onClicked: root.triggered()
        }
    }
}
