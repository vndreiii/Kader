import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.alpha("black", 0.45)
    visible: active
    z: 2000
    
    property bool active: false
    property bool isAll: true
    signal confirmed()
    signal closed()

    MouseArea { anchors.fill: parent; onClicked: root.closed() }

    Rectangle {
        id: dialog
        width: 480
        height: column.implicitHeight + 48
        radius: 28
        color: ThemeManager.surfaceContainerHigh
        anchors.centerIn: parent
        
        MouseArea { anchors.fill: parent } // Prevent click through

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16
            
            M3Icon {
                Layout.alignment: Qt.AlignHCenter
                name: "delete" // Placeholder for shredder
                size: 24; color: ThemeManager.primary
            }
            
            Label {
                text: root.isAll ? "Strip all photos from EXIF data?" : "Strip EXIF data from this photo?"
                font.family: "Roboto Flex"
                font.pixelSize: 24
                font.weight: Font.Normal
                color: ThemeManager.onSurface
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            
            Label {
                text: root.isAll ? "This will permanently remove location, camera model, lens, exposure and timestamp metadata from every photo in your library. Original pixel data is untouched. This cannot be undone." : "Permanently removes location, camera model, lens, exposure and timestamp metadata from this photo."
                font.pixelSize: 14
                color: ThemeManager.onSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            
            Rectangle {
                Layout.fillWidth: true; height: 100; radius: 12; color: ThemeManager.surfaceContainer
                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Label { text: "· GPS coordinates"; color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                    Label { text: "· Camera make & model"; color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                    Label { text: "· Capture date & time"; color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                }
            }
            
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Button {
                    text: I18n.t(Settings.language, "cancel")
                    onClicked: root.closed()
                    flat: true
                }
                Button {
                    text: root.isAll ? "Strip all" : "Strip metadata"
                    onClicked: root.confirmed()
                    background: Rectangle { radius: 20; color: ThemeManager.error }
                    contentItem: Label { text: parent.text; color: "white"; padding: 8; horizontalAlignment: Text.AlignHCenter }
                }
            }
        }
    }
}
