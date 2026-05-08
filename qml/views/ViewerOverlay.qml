import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material
import "../components"

Rectangle {
    id: root
    anchors.fill: parent
    color: "black"
    z: 1000
    visible: active
    
    property bool active: false
    property var mediaData: null
    
    // Close on Escape
    focus: active
    Keys.onEscapePressed: root.active = false

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            height: 64
            color: "#40000000"
            z: 10
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                
                Button {
                    text: "←"
                    onClicked: root.active = false
                    background: null
                    contentItem: Label { text: parent.text; color: "white"; font.pixelSize: 24 }
                }
                
                Label {
                    text: root.mediaData ? root.mediaData.file_path.split('/').pop() : ""
                    color: "white"
                    font.bold: true
                    Layout.fillWidth: true
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            ImagePanner {
                anchors.fill: parent
                source: root.mediaData ? "file://" + root.mediaData.file_path : ""
                thumbSource: root.mediaData ? "file://" + ThumbGen.getOrCreateThumbnail(root.mediaData.file_path) : ""
            }
        }
    }
}
