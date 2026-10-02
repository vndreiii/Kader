import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T

// Material 3 dropdown (exposed field + menu) for every ComboBox in the app.
T.ComboBox {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding, 48)

    leftPadding: 16
    rightPadding: 44
    font.pixelSize: 15

    FontLoader { id: symbols; source: "qrc:/Kader/assets/MaterialSymbolsRounded.ttf" }

    indicator: Text {
        x: control.width - width - 12
        y: (control.height - height) / 2
        text: "expand_more"
        font.family: symbols.name
        font.pixelSize: 22
        color: control.activeFocus || control.popup.visible ? ThemeManager.primary : ThemeManager.onSurfaceVariant
        rotation: control.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled ? ThemeManager.onSurface : Qt.alpha(ThemeManager.onSurface, 0.38)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 48
        radius: 12
        color: ThemeManager.surfaceContainerHighest
        border.width: control.activeFocus || control.popup.visible ? 2 : 1
        border.color: control.activeFocus || control.popup.visible ? ThemeManager.primary : ThemeManager.outline
        Rectangle {   // state layer
            anchors.fill: parent
            radius: parent.radius
            color: ThemeManager.onSurface
            opacity: control.pressed ? 0.10 : control.hovered ? 0.06 : 0
        }
    }

    delegate: T.ItemDelegate {
        id: item
        required property int index
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: 44
        leftPadding: 16
        rightPadding: 16
        highlighted: control.highlightedIndex === index
        readonly property bool current: control.currentIndex === index
        contentItem: Text {
            text: control.textRole
                  ? (Array.isArray(control.model) ? item.modelData[control.textRole] : item.modelData)
                  : item.modelData
            font.pixelSize: 15
            font.weight: item.current ? Font.DemiBold : Font.Normal
            color: item.current ? ThemeManager.onSecondaryContainer : ThemeManager.onSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 10
            color: item.current ? ThemeManager.secondaryContainer : "transparent"
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: ThemeManager.onSurface
                opacity: item.pressed ? 0.12 : (item.highlighted || item.hovered) ? 0.08 : 0
            }
        }
    }

    popup: T.Popup {
        y: control.height + 4
        width: control.width
        height: Math.min(contentItem.implicitHeight + topPadding + bottomPadding,
                         control.Window.height - 32)
        padding: 6
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: 16
            color: ThemeManager.surfaceContainer
            border.color: ThemeManager.outlineVariant
            border.width: 1
        }
    }
}
