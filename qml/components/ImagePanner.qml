import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string source: ""
    property string thumbSource: ""

    Image {
        id: thumb
        anchors.fill: parent
        source: root.thumbSource
        fillMode: Image.PreserveAspectFit
        opacity: highRes.status !== Image.Ready ? 1.0 : 0.0
        
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: highRes.width * highRes.scale
        contentHeight: highRes.height * highRes.scale
        clip: true

        Image {
            id: highRes
            source: root.source
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            
            width: flick.width
            height: flick.height
            
            property real scale: 1.0
            
            transform: Scale {
                origin.x: highRes.width / 2
                origin.y: highRes.height / 2
                xScale: highRes.scale
                yScale: highRes.scale
            }
        }

        MouseArea {
            anchors.fill: parent
            onDoubleClicked: {
                if (highRes.scale > 1.0) highRes.scale = 1.0
                else highRes.scale = 3.0
            }
        }
    }
}
