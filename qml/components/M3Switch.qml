import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Control {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 52
    implicitHeight: 32
    
    padding: 0
    
    background: Rectangle {
        implicitWidth: 52
        implicitHeight: 32
        radius: ThemeManager.radiusLg
        color: root.checked ? ThemeManager.primary : ThemeManager.surfaceContainerHighest
        border.color: root.checked ? "transparent" : ThemeManager.outline
        border.width: root.checked ? 0 : 2

        Behavior on color { ColorAnimation { duration: 200 } }
    }

    contentItem: Item {
        // Hover/press state layer — a disc centered on the handle that
        // overflows the track slightly, matching M3 switch behavior.
        Rectangle {
            id: stateLayer
            anchors.centerIn: thumb
            width: 40; height: 40
            radius: 20
            color: root.checked ? ThemeManager.primary : ThemeManager.onSurface
            opacity: switchMa.pressed ? ThemeManager.pressOpacity
                   : switchMa.containsMouse ? ThemeManager.hoverOpacity : 0
            Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
        }

        Rectangle {
            id: thumb
            // OFF: 16dp, ON: 24dp, pressed (either state): grows to 28dp —
            // all centered on the same fixed on/off center point so the
            // press-grow reads as an expansion rather than a jump.
            readonly property int _size: switchMa.pressed ? 28 : (root.checked ? 24 : 16)
            width: _size
            height: _size
            x: (root.checked ? 36 : 16) - _size / 2
            y: 16 - _size / 2
            radius: width / 2
            color: root.checked ? ThemeManager.onPrimary : ThemeManager.outline

            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
        }
    }

    MouseArea {
        id: switchMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            root.checked = !root.checked
            root.toggled(root.checked)
        }
    }
}
