import QtQuick
import QtQuick.Controls
import ".."
import "../I18n.js" as I18n
import "../Paths.js" as Paths

Rectangle {
    id: root
    property var mediaData: null

    color: ThemeManager.surfaceContainerHigh
    radius: 28
    implicitHeight: mainCol.implicitHeight + 48

    // Flush right rounded-corner gap
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 28
        color: parent.color
    }

    function formatSize(bytes) {
        if (!bytes || bytes === 0) return "—"
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / 1048576).toFixed(1) + " MB"
    }

    function formatCoords(lat, lon) {
        if (!lat || lat === 0) return "—"
        return lat.toFixed(5) + "°, " + lon.toFixed(5) + "°"
    }

    function formatOrientation(w, h) {
        if (!w || !h) return "—"
        if (w > h) return I18n.t(Settings.language, "orient_landscape")
        if (w < h) return I18n.t(Settings.language, "orient_portrait")
        return I18n.t(Settings.language, "orient_square")
    }

    function formatMegapixels(w, h) {
        if (!w || !h) return "—"
        return (w * h / 1000000).toFixed(1) + " MP"
    }

    function formatDuration(sec) {
        if (!sec || sec <= 0) return "—"
        var s = Math.round(sec)
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var ss = s % 60
        var pad = function(n) { return (n < 10 ? "0" : "") + n }
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(ss)) : (m + ":" + pad(ss))
    }

    Column {
        id: mainCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 24
        anchors.rightMargin: 40
        spacing: 20

        Label {
            text: I18n.t(Settings.language, "info_title")
            font.family: "Roboto Flex"
            font.pixelSize: 20
            font.weight: Font.Medium
            color: ThemeManager.onSurface
        }

        Column {
            width: parent.width
            spacing: 16

            Repeater {
                model: {
                    if (!root.mediaData) return []
                    var d = root.mediaData
                    var isVideo = (d.mime_type || "").indexOf("video/") === 0
                    var rows = [
                        { label: I18n.t(Settings.language, "info_file"),        value: d.file_path ? Paths.fileName(d.file_path) : "—", mono: true },
                        { label: I18n.t(Settings.language, "k_dimensions"),  value: (d.width && d.height) ? d.width + " × " + d.height + " px" : "—", mono: false },
                        { label: I18n.t(Settings.language, "info_megapixels"),  value: root.formatMegapixels(d.width, d.height), mono: false },
                        { label: I18n.t(Settings.language, "k_orientation"), value: root.formatOrientation(d.width, d.height), mono: false }
                    ]
                    if (isVideo)
                        rows.push({ label: I18n.t(Settings.language, "info_duration"), value: root.formatDuration(d.duration), mono: false })
                    rows.push(
                        { label: I18n.t(Settings.language, "info_file_size"),  value: root.formatSize(d.file_size), mono: false },
                        { label: I18n.t(Settings.language, "k_type"),       value: d.mime_type || "—", mono: false },
                        { label: I18n.t(Settings.language, "k_date_taken"), value: d.creation_date ? Qt.formatDateTime(new Date(d.creation_date * 1000), "dd MMM yyyy · HH:mm") : "—", mono: false },
                        { label: "GPS",        value: root.formatCoords(d.latitude, d.longitude), mono: false },
                        { label: I18n.t(Settings.language, "info_folder"),     value: d.folder_path || "—", mono: true }
                    )
                    return rows
                }

                delegate: Column {
                    width: parent ? parent.width : 0
                    spacing: 3

                    Label {
                        text: modelData.label
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: ThemeManager.onSurfaceVariant
                    }
                    Label {
                        width: parent.width
                        text: modelData.value
                        font.pixelSize: ThemeManager.fontLabelL
                        font.family: modelData.mono ? "JetBrains Mono" : ""
                        color: ThemeManager.onSurface
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }
                }
            }
        }
    }
}
