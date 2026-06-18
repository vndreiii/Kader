pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// Themed menu divider to match M3Menu/M3MenuItem — a hairline in outline_variant.
T.MenuSeparator {
    id: control

    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: implicitContentHeight + topPadding + bottomPadding

    leftPadding: 12
    rightPadding: 12
    topPadding: 6
    bottomPadding: 6

    contentItem: Rectangle {
        implicitWidth: 200
        implicitHeight: 1
        color: ThemeManager.outlineVariant
    }
}
