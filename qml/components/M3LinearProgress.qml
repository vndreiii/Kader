import QtQuick

// Material 3 (Expressive) linear progress indicator: a rounded active
// indicator, a small gap, the remaining track, and a stop dot marking the
// end. `indeterminate` slides a segment along the track instead.
Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    property bool indeterminate: false
    property color color: ThemeManager.primary
    property color trackColor: ThemeManager.secondaryContainer
    property real thickness: 4
    readonly property real gap: 4
    readonly property real fraction: Math.max(0, Math.min(1, (value - from) / Math.max(1e-9, to - from)))

    implicitWidth: 240
    implicitHeight: thickness

    // ── determinate ──────────────────────────────────────────────────────
    Rectangle {
        id: active
        visible: !root.indeterminate && width > 0
        anchors.verticalCenter: parent.verticalCenter
        height: root.thickness
        radius: height / 2
        color: root.color
        width: root.fraction > 0 ? Math.max(height, root.fraction * root.width) : 0
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        visible: !root.indeterminate && width > 0
        anchors.verticalCenter: parent.verticalCenter
        x: active.width > 0 ? active.width + root.gap : 0
        width: Math.max(0, root.width - x)
        height: root.thickness
        radius: height / 2
        color: root.trackColor
    }
    Rectangle {   // stop indicator
        visible: !root.indeterminate && root.fraction < 1
        anchors.verticalCenter: parent.verticalCenter
        x: root.width - width
        width: root.thickness
        height: root.thickness
        radius: width / 2
        color: root.color
    }

    // ── indeterminate ────────────────────────────────────────────────────
    Item {
        visible: root.indeterminate
        anchors.fill: parent
        clip: true
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.thickness
            radius: height / 2
            color: root.trackColor
        }
        Rectangle {
            id: seg
            anchors.verticalCenter: parent.verticalCenter
            height: root.thickness
            radius: height / 2
            color: root.color
            width: root.width * 0.35
            NumberAnimation on x {
                running: root.indeterminate && root.visible
                loops: Animation.Infinite
                from: -root.width * 0.35
                to: root.width
                duration: 1500
                easing.type: Easing.InOutCubic
            }
        }
    }
}
