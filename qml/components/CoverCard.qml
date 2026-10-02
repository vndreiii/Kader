import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."

// A group card: photo cover (one large image, or a 2×2 mosaic), title and
// subtitle on a scrim, optional colour swatch. Used for memories, places,
// scenes and colours in the Search tab.
Item {
    id: root
    property var covers: []           // thumbnail URLs
    property string title: ""
    property string subtitle: ""
    property color swatch: "transparent"
    property bool mosaic: covers.length >= 4
    property bool loading: false
    signal clicked()

    implicitWidth: 240
    implicitHeight: 168

    Rectangle { id: mask; anchors.fill: parent; radius: 20; visible: false; layer.enabled: true }

    Skeleton { anchors.fill: parent; radius: 20; visible: root.loading; active: visible }

    Item {
        id: content
        anchors.fill: parent
        visible: !root.loading
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle { anchors.fill: parent; color: ThemeManager.surfaceContainerHigh }

        Grid {
            anchors.fill: parent
            columns: root.mosaic ? 2 : 1
            spacing: root.mosaic ? 2 : 0
            scale: hover.containsMouse ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutQuint } }
            Repeater {
                model: root.mosaic ? 4 : Math.min(1, root.covers.length)
                Image {
                    required property int index
                    width: root.mosaic ? (root.width - 2) / 2 : root.width
                    height: root.mosaic ? (root.height - 2) / 2 : root.height
                    source: root.covers[index] || ""
                    sourceSize: Qt.size(400, 400)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
        }

        // scrim for the label
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.6
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            spacing: 10
            Rectangle {
                visible: root.swatch.a > 0
                width: 22; height: 22; radius: 11
                anchors.verticalCenter: parent.verticalCenter
                color: root.swatch
                border.width: 2; border.color: "white"
            }
            Column {
                width: parent.width - (root.swatch.a > 0 ? 32 : 0)
                spacing: 2
                Label {
                    width: parent.width
                    text: root.title
                    color: "white"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    visible: text.length > 0
                    text: root.subtitle
                    color: Qt.rgba(1, 1, 1, 0.82)
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.loading
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
