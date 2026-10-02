import QtQuick
import QtQuick.Shapes

// Material 3 circular progress indicator. Indeterminate (the default): an
// arc that grows, shrinks and rotates; with `indeterminate: false` it shows
// `value` (0…1) as a sweep over the track.
Item {
    id: root
    property bool indeterminate: true
    property bool running: true
    property real value: 0
    property color color: ThemeManager.primary
    property color trackColor: indeterminate ? "transparent" : ThemeManager.secondaryContainer
    property real thickness: Math.max(2.5, width / 10)

    implicitWidth: 24
    implicitHeight: 24

    property real _sweep: indeterminate ? 40 : 360 * Math.max(0, Math.min(1, value))
    property real _start: -90

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {   // track
            strokeColor: root.trackColor
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: (root.width - root.thickness) / 2; radiusY: radiusX
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {   // indicator
            strokeColor: root.color
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: (root.width - root.thickness) / 2; radiusY: radiusX
                startAngle: root._start; sweepAngle: root._sweep
            }
        }
    }

    // grow/shrink the arc while the whole thing turns
    SequentialAnimation {
        running: root.indeterminate && root.running && root.visible
        loops: Animation.Infinite
        ParallelAnimation {
            NumberAnimation { target: root; property: "_sweep"; from: 20; to: 270; duration: 700; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "_start"; from: -90; to: 90; duration: 700; easing.type: Easing.Linear }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_sweep"; from: 270; to: 20; duration: 700; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "_start"; from: 90; to: 520; duration: 700; easing.type: Easing.InOutCubic }
        }
    }
}
