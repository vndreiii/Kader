pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Templates as T
import QtQuick.Controls as C

// 1:1 local port of QmlMaterial's MD.Menu — no Qcm.Material dependency.
//
//   surface_container surface · extra_small (4dp) corners · 8px vertical padding
//   elevation level-2 drop shadow · grow(0.8→1)+fade, emphasized-decelerate 300ms
T.Menu {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding)

    margins: 0
    padding: 0
    // Match the corner radius so the first/last row's full-width fill (selection /
    // hover state layer) sits entirely in the straight-edge zone and never pokes
    // into the rounded corners.
    verticalPadding: cornerRadius
    overlap: 0

    // Single source of truth for the rounded corner (see background).
    property int cornerRadius: 20

    // Render in-scene so the elevation shadow isn't clipped by a tight popup window.
    popupType: T.Popup.Item

    transformOrigin: !cascade ? Item.Top : (mirrored ? Item.TopRight : Item.TopLeft)

    // Items added via Action / model paths get themed too.
    // icon for this menu's entry when it's a submenu (see M3MenuItem.iconName)
    property string iconName: ""
    delegate: M3MenuItem {
        iconName: subMenu && subMenu.iconName !== undefined ? subMenu.iconName : ""
    }

    // M3 grow + fade (emphasized-decelerate, medium2 = 300ms).
    enter: Transition {
        NumberAnimation {
            property: "opacity"; from: 0.0; to: 1.0; duration: 300
            easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
        NumberAnimation {
            property: "scale"; from: 0.8; to: 1.0; duration: 300
            easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"; from: 1.0; to: 0.0; duration: 300
            easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
        NumberAnimation {
            property: "scale"; from: 1.0; to: 0.8; duration: 300
            easing.type: Easing.Bezier; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
    }

    contentItem: ListView {
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: Window.window ? contentHeight + control.topPadding + control.bottomPadding > Window.window.height : false
        clip: true
        currentIndex: control.currentIndex
        keyNavigationEnabled: false
        T.ScrollIndicator.vertical: C.ScrollIndicator {}
    }

    background: Rectangle {
        implicitWidth: 220
        implicitHeight: 44
        // Rounded to match the "Ordenar por" pill button.
        radius: control.cornerRadius
        color: ThemeManager.surfaceContainer

        // Elevation level-2 drop shadow (QmlMaterial ElevationRectangle equivalent).
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.32)
            shadowBlur: 0.5
            shadowVerticalOffset: 3
            blurMax: 32
            autoPaddingEnabled: true
        }
    }
}
