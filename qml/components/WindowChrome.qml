import QtQuick

// Move/resize for frameless windows. Uses the compositor-driven
// startSystemMove()/startSystemResize(), the only way that works on Wayland
// (and the correct one on X11). Put it under the content: interactive
// controls above it keep their clicks; empty header space drags the window.
Item {
    id: root
    property Window window: Window.window
    property real moveAreaHeight: 72
    property int grip: 6
    // Use twice: once under the content (move: true, edges: false) and once
    // on top of everything (move: false, edges: true).
    property bool move: true
    property bool edges: true
    readonly property bool resizable: window && window.visibility !== Window.Maximized
                                      && window.visibility !== Window.FullScreen
    anchors.fill: parent

    // drag the window from empty header space; double-click maximises
    Item {
        visible: root.move
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.moveAreaHeight
        DragHandler {
            target: null
            onActiveChanged: if (active && root.window) root.window.startSystemMove()
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: {
                if (!root.window) return
                root.window.visibility = root.window.visibility === Window.Maximized
                                       ? Window.Windowed : Window.Maximized
            }
        }
    }

    // edges and corners (on top of everything, but only a few px wide)
    readonly property var edgeModel: [
            { e: Qt.LeftEdge,                 c: Qt.SizeHorCursor },
            { e: Qt.RightEdge,                c: Qt.SizeHorCursor },
            { e: Qt.TopEdge,                  c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge,               c: Qt.SizeVerCursor },
            { e: Qt.TopEdge | Qt.LeftEdge,    c: Qt.SizeFDiagCursor },
            { e: Qt.BottomEdge | Qt.RightEdge, c: Qt.SizeFDiagCursor },
            { e: Qt.TopEdge | Qt.RightEdge,   c: Qt.SizeBDiagCursor },
            { e: Qt.BottomEdge | Qt.LeftEdge, c: Qt.SizeBDiagCursor }
    ]
    Repeater {
        model: root.edges ? root.edgeModel : []
        delegate: MouseArea {
            required property var modelData
            readonly property bool l: modelData.e & Qt.LeftEdge
            readonly property bool r: modelData.e & Qt.RightEdge
            readonly property bool t: modelData.e & Qt.TopEdge
            readonly property bool b: modelData.e & Qt.BottomEdge
            readonly property bool corner: (l || r) && (t || b)
            enabled: root.resizable
            z: 1000 + (corner ? 1 : 0)
            cursorShape: modelData.c
            hoverEnabled: true
            width: (l || r) ? root.grip * (corner ? 2 : 1) : root.width
            height: (t || b) ? root.grip * (corner ? 2 : 1) : root.height
            x: r ? root.width - width : 0
            y: b ? root.height - height : 0
            onPressed: if (root.window) root.window.startSystemResize(modelData.e)
        }
    }
}
