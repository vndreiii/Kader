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
        radius: 16
        color: root.checked ? ThemeManager.primary : ThemeManager.surfaceContainerHighest
        border.color: root.checked ? "transparent" : ThemeManager.outline
        border.width: root.checked ? 0 : 2
        
        Behavior on color { ColorAnimation { duration: 200 } }
    }
    
    contentItem: Item {
        Rectangle {
            id: thumb
            // OFF: x=8, size=16 (centered vertically: (32-16)/2 = 8)
            // ON: x=26, size=24 (centered vertically: (32-24)/2 = 4)
            // User said "right side padding is a bit too big" when on. 
            // 52 - 24 - 4 (left) = 24? No.
            // Let's use 6px padding from edges.
            // OFF: x=6, size=16. Center Y = 8.
            // ON: x=52-6-24 = 22? No, M3 is usually 52x32.
            
            x: root.checked ? 24 : 8
            y: root.checked ? 4 : 8
            width: root.checked ? 24 : 16
            height: root.checked ? 24 : 16
            radius: width / 2
            color: root.checked ? ThemeManager.onPrimary : ThemeManager.outline
            
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.checked = !root.checked
            root.toggled(root.checked)
        }
    }
}
