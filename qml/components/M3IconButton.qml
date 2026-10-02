import QtQuick
import QtQuick.Controls
import ".."

// Material 3 standard icon button: a 40 px circle with the icon centred and
// a state layer in the icon's colour.
Item {
    id: root
    property string icon: ""
    property color color: ThemeManager.onSurfaceVariant
    property real iconSize: 20
    property string tip: ""
    signal clicked()
    implicitWidth: 40
    implicitHeight: 40
    scale: ma.pressed ? 0.86 : 1
    Behavior on scale {
        NumberAnimation { duration: ma.pressed ? 90 : 320; easing.type: ma.pressed ? Easing.OutCubic : Easing.OutBack; easing.overshoot: 2.4 }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width, root.height); height: width
        radius: width / 2
        color: root.color
        opacity: ma.pressed ? 0.12 : ma.containsMouse ? 0.08 : 0
        Behavior on opacity { NumberAnimation { duration: ThemeManager.durShort } }
    }
    MaterialSymbol {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        color: root.color
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    ToolTip.text: root.tip
    ToolTip.visible: root.tip !== "" && ma.containsMouse
    ToolTip.delay: 500
}
