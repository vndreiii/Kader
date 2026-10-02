import QtQuick
import QtQuick.Controls
import QtQuick.Window
import ".."

// Minimise / maximise-restore / close for Kader's frameless windows. `glass`
// draws them as a dark translucent pill for use over photos (the viewer).
Rectangle {
    id: root
    property bool glass: false
    readonly property var win: Window.window
    readonly property bool maximized: win && (win.visibility === Window.Maximized || win.visibility === Window.FullScreen)

    // Settings → Appearance → Window buttons (auto follows the desktop)
    visible: Settings.windowButtons === 1
             || (Settings.windowButtons === 0 && typeof SYSTEM_WINDOW_BUTTONS !== "undefined" && SYSTEM_WINDOW_BUTTONS)
    implicitWidth: row.implicitWidth + (glass ? 8 : 0)
    implicitHeight: glass ? 48 : 40
    radius: height / 2
    color: glass ? Qt.rgba(0, 0, 0, 0.44) : "transparent"
    border.width: glass ? 1 : 0
    border.color: Qt.alpha("white", 0.24)

    component WinButton: Rectangle {
        id: b
        property string icon
        property bool danger: false
        signal clicked()
        width: root.glass ? 44 : 40
        height: root.glass ? 40 : 36
        radius: height / 2
        color: ma.pressed ? (danger ? "#c62828" : Qt.alpha(root.glass ? "white" : ThemeManager.onSurface, 0.20))
             : ma.containsMouse ? (danger ? "#e53935" : Qt.alpha(root.glass ? "white" : ThemeManager.onSurface, 0.10))
             : "transparent"
        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
        MaterialSymbol {
            anchors.centerIn: parent
            name: b.icon
            size: 20
            color: (b.danger && ma.containsMouse) || root.glass ? "white" : ThemeManager.onSurfaceVariant
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
        WinButton {
            icon: "remove"
            onClicked: root.win.showMinimized()
        }
        WinButton {
            icon: root.maximized ? "filter_none" : "crop_square"
            onClicked: root.maximized ? root.win.showNormal() : root.win.showMaximized()
        }
        WinButton {
            icon: "close"
            danger: true
            onClicked: root.win.close()
        }
    }
}
