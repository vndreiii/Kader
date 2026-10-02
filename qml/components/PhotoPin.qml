import QtQuick
import QtQuick.Effects

// A map pin for photos, shared by the 3D globe and the 2D map: a squircle
// photo on a short stem with a ground shadow; clusters show a stack of photos
// behind and a count badge; hovered / active pins lift and get an accent ring
// with a pulse at the exact spot. The pin's bottom centre is the location.
Item {
    id: pin
    property string photo: ""
    property int photos: 1
    property bool stacked: photos > 1
    property bool hot: false
    property bool active: false
    property color accent: ThemeManager.primary
    property color badgeBorder: Qt.rgba(0.02, 0.024, 0.04, 1)
    readonly property color ring: active ? accent : "white"

    width: 56
    height: 70
    transformOrigin: Item.Bottom

    Rectangle {
        id: pinMask
        width: 46; height: 46; radius: 14
        visible: false
        layer.enabled: true
    }

    // ground shadow + exact spot
    Rectangle {
        width: 20; height: 7; radius: 3.5
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -2
        color: Qt.rgba(0, 0, 0, 0.45)
    }
    Rectangle {
        id: spot
        width: 7; height: 7; radius: 3.5
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        color: pin.active ? pin.accent : "white"
    }
    // pulse at the spot while active
    Rectangle {
        visible: pin.active
        anchors.centerIn: spot
        width: 7; height: 7; radius: width / 2
        color: "transparent"
        border.color: pin.accent
        border.width: 1.5
        SequentialAnimation on width {
            running: pin.active
            loops: Animation.Infinite
            NumberAnimation { from: 7; to: 30; duration: 1200; easing.type: Easing.OutCubic }
        }
        opacity: 1.0 - (width - 7) / 23
    }
    // stem
    Rectangle {
        width: 2.5; height: 14
        radius: 1.25
        anchors.horizontalCenter: parent.horizontalCenter
        y: 50
        color: pin.ring
    }

    // stack of photos behind a cluster
    Repeater {
        model: pin.stacked ? 2 : 0
        Rectangle {
            required property int index
            width: 50; height: 50; radius: 16
            x: 3 + (index + 1) * 4
            y: 1 - (index + 1) * 3
            color: Qt.rgba(1, 1, 1, index === 0 ? 0.55 : 0.30)
            z: -1 - index
        }
    }

    // photo in a ring
    Rectangle {
        id: frame
        x: 3; y: 1
        width: 50; height: 50; radius: 16
        color: pin.ring
        Rectangle { // placeholder while the thumbnail loads
            anchors.centerIn: parent
            width: 46; height: 46; radius: 14
            color: Qt.rgba(0.12, 0.14, 0.2, 1)
        }
        Image {
            anchors.centerIn: parent
            width: 46; height: 46
            source: pin.photo
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: pinMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
    }

    // photo count
    Rectangle {
        visible: pin.photos > 1
        anchors { horizontalCenter: frame.right; verticalCenter: frame.top; horizontalCenterOffset: -6; verticalCenterOffset: 6 }
        height: 20; radius: 10
        width: Math.max(20, countLbl.implicitWidth + 10)
        color: pin.accent
        border.color: pin.badgeBorder; border.width: 2
        Text {
            id: countLbl
            anchors.centerIn: parent
            text: pin.photos > 999 ? Math.round(pin.photos / 100) / 10 + "k" : pin.photos
            color: ThemeManager.isDark ? ThemeManager.onPrimary : ThemeManager.primary
            font.pixelSize: 11; font.weight: Font.Bold
        }
    }
}
