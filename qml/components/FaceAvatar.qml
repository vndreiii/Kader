import QtQuick
import QtQuick.Effects
import ".."

// Round face crop from the analyzer's face image provider.
Item {
    id: root
    property int faceId: -1
    property int revision: 0          // bump to reload after edits
    property bool selected: false
    property bool selectable: false
    implicitWidth: 96
    implicitHeight: 96

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
    }

    Skeleton {
        anchors.fill: parent
        radius: width / 2
        visible: img.status !== Image.Ready
        active: visible && root.faceId >= 0
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.faceId >= 0 ? "image://faces/" + root.faceId + "?" + root.revision : ""
        sourceSize: Qt.size(Math.min(384, width * 2), Math.min(384, height * 2))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: img.status === Image.Ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.faceId < 0
        name: "person"
        size: parent.width * 0.45
        color: ThemeManager.onSurfaceVariant
    }

    // selection ring + check
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: width / 2
        color: "transparent"
        border.width: root.selected ? 3 : 0
        border.color: ThemeManager.primary
        Behavior on border.width { NumberAnimation { duration: ThemeManager.durShort } }
    }
    Rectangle {
        visible: root.selectable || root.selected
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 26; height: 26; radius: 13
        color: root.selected ? ThemeManager.primary : Qt.alpha("black", 0.45)
        border.width: 2
        border.color: "white"
        M3Icon { anchors.centerIn: parent; visible: root.selected; name: "check"; size: 16; color: ThemeManager.onPrimary }
    }
}
