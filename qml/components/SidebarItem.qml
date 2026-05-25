import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: root
    property string icon: ""
    property string label: ""
    property bool active: false
    property bool collapsed: false
    signal clicked()

    width: parent ? parent.width : 0
    height: 56

    // 0=bottom-up  1=top-down  2=left-right  3=right-left
    property int  _fillDir: 0
    property real _progress: 0   // 0=outline, 1=filled; driven by animations below

    NumberAnimation { id: fillIn;  target: root; property: "_progress"; to: 1; duration: 320; easing.type: Easing.OutQuint }
    NumberAnimation { id: fillOut; target: root; property: "_progress"; to: 0; duration: 200; easing.type: Easing.InQuint }

    property bool _ready: false
    Component.onCompleted: {
        _progress = active ? 1 : 0
        _ready = true
    }

    onActiveChanged: {
        if (!_ready) return
        if (active) {
            _fillDir = Math.floor(Math.random() * 4)
            fillOut.stop(); fillIn.restart()
        } else {
            fillIn.stop(); fillOut.restart()
        }
    }

    // ── Active background ─────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 12; anchors.rightMargin: 12
        radius: 28
        color: ThemeManager.secondaryContainer
        opacity: root._progress
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 28
        spacing: 12

        // ── Icon ─────────────────────────────────────────────────────────
        Item {
            id: iconArea
            width: 24; height: 24
            anchors.verticalCenter: parent.verticalCenter

            // Outline — fades out as fill reveals
            M3Icon {
                anchors.fill: parent
                name: root.icon
                size: 24
                color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                opacity: 1 - root._progress
                Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
            }

            // Fill icon — single clip item, directional reveal via _progress + _fillDir
            Item {
                id: fillClip
                clip: true
                // x: right-to-left starts from the right and grows left
                x: root._fillDir === 3 ? (1 - root._progress) * 24 : 0
                // y: bottom-up starts from the bottom and grows up
                y: root._fillDir === 0 ? (1 - root._progress) * 24 : 0
                width:  (root._fillDir === 2 || root._fillDir === 3) ? root._progress * 24 : 24
                height: (root._fillDir === 0 || root._fillDir === 1) ? root._progress * 24 : 24

                M3Icon {
                    // Compensate for clip movement so the icon stays visually fixed
                    x: root._fillDir === 3 ? -(24 - fillClip.width) : 0
                    y: root._fillDir === 0 ? -(24 - fillClip.height) : 0
                    name: root.icon + "_fill"
                    size: 24
                    color: ThemeManager.onSecondaryContainer
                }
            }
        }

        Label {
            visible: !root.collapsed
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.active ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
            font.pixelSize: 14
            font.weight: root.active ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            width: parent.width - 64
            Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
        }
    }

    // ── Hover + press overlay ─────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 12; anchors.rightMargin: 12
        radius: 28
        color: ThemeManager.onSurface
        opacity: mouseArea.pressed ? 0.20 : (mouseArea.containsMouse ? 0.08 : 0)
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
