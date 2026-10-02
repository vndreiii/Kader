import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

// Face-grouping sensitivity: how similar two faces must be to count as the
// same person. Previews the grouping live; Apply re-groups the library.
Popup {
    id: root
    function _t(k) { return I18n.t(Settings.language, k) }
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent.width - 48)
    modal: true
    padding: 28
    property real value: Analyzer.threshold
    property var preview: ({})
    onOpened: { value = Analyzer.threshold; preview = Analyzer.previewThreshold(value) }
    Timer { id: previewTimer; interval: 120; onTriggered: root.preview = Analyzer.previewThreshold(root.value) }

    background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
    contentItem: ColumnLayout {
        spacing: 16
        Label { text: root._t("calibrate_title"); font.pixelSize: 24; color: ThemeManager.onSurface }
        Label {
            Layout.fillWidth: true
            text: root._t("calibrate_body")
            wrapMode: Text.WordWrap
            color: ThemeManager.onSurfaceVariant
        }
        RowLayout {
            Layout.fillWidth: true
            Label { text: root._t("calibrate_looser"); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
            Slider {
                id: slider
                Layout.fillWidth: true
                from: 0.25; to: 0.6; stepSize: 0.01
                value: root.value
                onMoved: { root.value = value; previewTimer.restart() }
            }
            Label { text: root._t("calibrate_stricter"); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            radius: 16
            color: ThemeManager.surfaceContainerHighest
            Label {
                anchors.centerIn: parent
                text: root._t("calibrate_preview").arg(root.preview.groups || 0).arg(root.preview.grouped || 0).arg(root.preview.faces || 0)
                color: ThemeManager.onSurface
                font.pixelSize: 15
            }
        }
        RowLayout {
            Layout.fillWidth: true
            M3Button { flat: true; text: root._t("reset"); onClicked: { root.value = 0.38; slider.value = 0.38; previewTimer.restart() } }
            Item { Layout.fillWidth: true }
            M3Button { flat: true; text: root._t("cancel"); onClicked: root.close() }
            M3Button { highlighted: true; text: root._t("apply"); onClicked: { Analyzer.setThreshold(root.value); root.close() } }
        }
    }
}
