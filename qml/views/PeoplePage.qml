import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../I18n.js" as I18n

// Everyone found in the library, hidden people included on request, with
// face-grouping calibration.
Item {
    id: root
    signal back()
    signal openPerson(int id)
    function _t(k) { return I18n.t(Settings.language, k) }

    property bool showHidden: false
    property var list: []
    function reload() { list = Analyzer.people(showHidden) }
    onShowHiddenChanged: reload()
    Component.onCompleted: reload()
    Connections { target: Analyzer; function onRevisionChanged() { root.reload() } }

    PageHeader {
        id: header
        title: root._t("people")
        subtitle: root._t("n_people").arg(root.list.length)
        onBack: root.back()
        Label { text: root._t("show_hidden"); color: ThemeManager.onSurfaceVariant }
        Switch { checked: root.showHidden; onToggled: root.showHidden = checked }
        M3Button { flat: true; text: root._t("calibrate_title"); onClicked: calibrate.open() }
        M3Button { flat: true; text: root._t("turn_off"); onClicked: { Analyzer.disableFaces(); root.back() } }
    }

    GridView {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 28; rightMargin: 28 }
        clip: true
        cellWidth: 150; cellHeight: 186
        model: root.list
        delegate: Column {
            required property var modelData
            width: 150
            spacing: 8
            opacity: modelData.hidden ? 0.5 : 1
            FaceAvatar {
                width: 120; height: 120
                anchors.horizontalCenter: parent.horizontalCenter
                faceId: modelData.cover !== undefined ? modelData.cover : -1
                revision: Analyzer.revision
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openPerson(modelData.id) }
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: modelData.name || root._t("add_name")
                color: modelData.name ? ThemeManager.onSurface : ThemeManager.primary
                font.pixelSize: 15
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root._t("n_photos").arg(modelData.photos)
                color: ThemeManager.onSurfaceVariant
                font.pixelSize: 12
            }
        }
    }

    CalibratePopup { id: calibrate }
}
