import QtQuick
import QtQuick.Controls

// A person's name under their face. Click it ("Add a name" when unnamed)
// to type the name in place; Enter or clicking away saves, Esc cancels.
Item {
    id: root
    property string name: ""
    property string placeholder: ""
    property int pixelSize: 14
    property bool editing: false
    signal renamed(string name)

    implicitWidth: 120
    implicitHeight: Math.max(lbl.implicitHeight, 30)

    function startEdit() {
        field.text = root.name
        root.editing = true
        field.forceActiveFocus()
        field.selectAll()
    }
    function commit() {
        if (!root.editing)
            return
        const t = field.text.trim()
        root.editing = false
        if (t !== root.name)
            root.renamed(t)
    }

    Label {
        id: lbl
        visible: !root.editing
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.name || root.placeholder
        color: root.name ? ThemeManager.onSurface : ThemeManager.primary
        font.pixelSize: root.pixelSize
        font.weight: Font.Medium
        font.underline: !root.name && nameMa.containsMouse
        elide: Text.ElideRight
        MouseArea {
            id: nameMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onClicked: root.startEdit()
        }
    }

    TextField {
        id: field
        visible: root.editing
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: root.pixelSize
        color: ThemeManager.onSurface
        selectionColor: ThemeManager.primary
        selectedTextColor: ThemeManager.onPrimary
        selectByMouse: true
        leftPadding: 6; rightPadding: 6; topPadding: 2; bottomPadding: 2
        placeholderText: root.placeholder
        placeholderTextColor: ThemeManager.onSurfaceVariant
        background: Rectangle {
            radius: 8
            color: ThemeManager.surfaceContainerHighest
            border.width: 2
            border.color: ThemeManager.primary
        }
        onAccepted: root.commit()
        Keys.onEscapePressed: root.editing = false
        onActiveFocusChanged: if (!activeFocus) root.commit()
    }
}
