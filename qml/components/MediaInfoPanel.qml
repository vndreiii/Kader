import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    property var mediaData: null

    color: ThemeManager.surfaceContainerHigh
    radius: 28

    // Flush right edge into window frame (no visible gap at edge)
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        anchors.rightMargin: 40
        spacing: 20

        Label {
            text: "Info"
            font.family: "Roboto Flex"
            font.pixelSize: 20
            font.weight: Font.Medium
            color: ThemeManager.onSurface
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 16

            model: root.mediaData ? [
                { label: "File",       value: root.mediaData.file_path ? root.mediaData.file_path.split('/').pop() : "—", mono: true },
                { label: "Dimensions", value: (root.mediaData.width && root.mediaData.height) ? root.mediaData.width + " × " + root.mediaData.height + " px" : "—", mono: false },
                { label: "File size",  value: root.formatSize(root.mediaData.file_size), mono: false },
                { label: "Type",       value: root.mediaData.mime_type || "—", mono: false },
                { label: "Date taken", value: root.mediaData.creation_date ? Qt.formatDateTime(new Date(root.mediaData.creation_date * 1000), "dd MMM yyyy · HH:mm") : "—", mono: false },
                { label: "GPS",        value: root.formatCoords(root.mediaData.latitude, root.mediaData.longitude), mono: false },
                { label: "Folder",     value: root.mediaData.folder_path || "—", mono: true }
            ] : []

            delegate: Column {
                width: ListView.view.width
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
                    font.pixelSize: 13
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
