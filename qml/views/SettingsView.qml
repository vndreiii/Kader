import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material

Item {
    id: root
    property alias topPadding: content.topMargin

    ScrollView {
        id: scroll
        anchors.fill: parent
        
        ColumnLayout {
            id: content
            width: scroll.width - 48
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            Label {
                text: "Settings"
                font.pixelSize: 32
                font.bold: true
                color: ThemeManager.textColor
            }

            // General Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16

                Label {
                    text: "Privacy & Visibility"
                    font.pixelSize: 18
                    font.bold: true
                    color: ThemeManager.primaryColor
                }

                RowLayout {
                    Layout.fillWidth: true
                    
                    Column {
                        Layout.fillWidth: true
                        Label {
                            text: "Hide ignored albums in Timeline"
                            color: ThemeManager.textColor
                            font.bold: true
                        }
                        Label {
                            text: "Images from albums marked as 'Ignored' will not appear in the main Timeline view."
                            color: ThemeManager.textColor
                            opacity: 0.6
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            width: parent.width
                        }
                    }

                    Switch {
                        checked: Settings.hideIgnoredInTimeline
                        onToggled: Settings.hideIgnoredInTimeline = checked
                    }
                }
            }

            // ... More sections later
        }
    }
}
