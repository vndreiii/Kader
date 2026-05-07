import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QmlMaterial
import "components"

ApplicationWindow {
    id: window
    width: 1024
    height: 768
    visible: true
    title: qsTr("Kader")

    // Bind QmlMaterial Theme to our ThemeManager
    Component.onCompleted: {
        Theme.primaryColor = ThemeManager.primaryColor
        Theme.backgroundColor = ThemeManager.backgroundColor
        Theme.surfaceColor = ThemeManager.surfaceColor
        Theme.textColor = ThemeManager.textColor
    }

    Connections {
        target: ThemeManager
        function onThemeChanged() {
            Theme.primaryColor = ThemeManager.primaryColor
            Theme.backgroundColor = ThemeManager.backgroundColor
            Theme.surfaceColor = ThemeManager.surfaceColor
            Theme.textColor = ThemeManager.textColor
        }
    }

    background: Rectangle {
        color: Theme.backgroundColor
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Bar
        Rectangle {
            Layout.fillWidth: true
            height: 64
            color: Theme.surfaceColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16

                Label {
                    text: "Kader"
                    font.pixelSize: 22
                    font.bold: true
                    color: Theme.textColor
                }

                Item { Layout.fillWidth: true }

                // Placeholder for Search
                Button {
                    text: "Start Scan"
                    flat: true
                    onClicked: FileScanner.startScan("/home/meh/Builds")
                }
            }
        }

        // Status Bar
        Rectangle {
            Layout.fillWidth: true
            height: 24
            color: Theme.surfaceColor
            Label {
                id: statusLabel
                anchors.centerIn: parent
                text: "Ready"
                font.pixelSize: 12
                color: Theme.textColor
            }
        }

        // Main Content Area
        StackView {
            id: mainStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: timelinePage
        }
    }

    Connections {
        target: FileScanner
        function onScanFinished(paths, dirsScanned, duration) {
            statusLabel.text = "Found " + paths.length + " media files in " + dirsScanned + " dirs (took " + duration.toFixed(3) + "s)"
            console.log("Scan finished: " + paths.length + " files")
        }
    }

    Component {
        id: timelinePage
        MediaGrid {
            anchors.fill: parent
        }
    }
}
