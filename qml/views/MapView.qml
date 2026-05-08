import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    
    RowLayout {
        anchors.fill: parent
        spacing: 0
        
        // Map Canvas
        Rectangle {
            id: mapCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 24
            color: ThemeManager.surfaceContainerLow
            
            // Flatten right and bottom
            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 24; color: parent.color }
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 24; color: parent.color }
            
            clip: true
            
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: ThemeManager.surfaceContainerLow }
                    GradientStop { position: 1; color: ThemeManager.surfaceDim }
                }
            }
            
            // Grid lines
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.strokeStyle = Qt.alpha(ThemeManager.onSurface, 0.06);
                    ctx.lineWidth = 1;
                    for (var x = 0; x < width; x += 60) {
                        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                    }
                    for (var y = 0; y < height; y += 60) {
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                    }
                }
            }
            
            // Mock pins
            Repeater {
                model: [
                    { name: "Tokyo", x: 0.8, y: 0.4, count: 12 },
                    { name: "Paris", x: 0.3, y: 0.3, count: 8 },
                    { name: "Lisbon", x: 0.2, y: 0.5, count: 15 }
                ]
                delegate: Item {
                    x: modelData.x * mapCanvas.width
                    y: modelData.y * mapCanvas.height
                    
                    Rectangle {
                        id: bubble
                        width: label.width + 64; height: 40; radius: 20
                        color: ThemeManager.primary
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 12
                        
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 4; anchors.leftMargin: 6; anchors.rightMargin: 12; spacing: 8
                            Rectangle { 
                                width: 32; height: 32; radius: 16; color: "white"; clip: true 
                                Image { anchors.fill: parent; source: "https://picsum.photos/seed/" + modelData.name + "/80/80"; fillMode: Image.PreserveAspectCrop }
                            }
                            Label { id: label; text: modelData.name; color: "white"; font.weight: Font.Medium; font.pixelSize: 13 }
                            Rectangle { 
                                width: 24; height: 20; radius: 10; color: Qt.alpha("white", 0.25)
                                Label { text: modelData.count; anchors.centerIn: parent; color: "white"; font.pixelSize: 11; font.weight: Font.Bold }
                            }
                        }
                        
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: -6
                            width: 12; height: 12; color: parent.color; rotation: 45
                        }

                        Behavior on scale { NumberAnimation { duration: 150 } }
                        scale: mouseAreaPin.containsMouse ? 1.06 : 1.0
                    }
                    
                    MouseArea {
                        id: mouseAreaPin
                        anchors.fill: bubble
                        hoverEnabled: true
                        onClicked: console.log("Pin clicked:", modelData.name)
                    }
                }
            }
        }
        
        // Map List (Right Column)
        Rectangle {
            Layout.fillHeight: true
            width: 320
            color: ThemeManager.surfaceContainer
            radius: 28
            
            // Flatten right
            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 28; color: parent.color }
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 24
                spacing: 12
                
                Label {
                    text: "Places"
                    font.family: "Roboto Flex"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: ThemeManager.onSurface
                    Layout.leftMargin: 8
                }
                
                ListView {
                    id: listView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: ["Tokyo, Japan", "Paris, France", "Lisbon, Portugal", "Lyon, France", "Berlin, Germany"]
                    clip: true
                    spacing: 4
                    
                    delegate: Rectangle {
                        width: listView.width
                        height: 72
                        radius: 12
                        color: mouseAreaList.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.04) : "transparent"
                        
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 12
                            Rectangle { 
                                width: 56; height: 56; radius: 12; color: ThemeManager.surfaceContainerHigh; clip: true 
                                Image { anchors.fill: parent; source: "https://picsum.photos/seed/" + index + "/120/120"; fillMode: Image.PreserveAspectCrop }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: modelData; font.weight: Font.Medium; color: ThemeManager.onSurface; font.pixelSize: 14 }
                                Label { text: (10 + index * 5) + " photos"; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                            }
                            M3Icon { name: "schedule"; size: 20; color: ThemeManager.onSurfaceVariant; opacity: 0.5 } // Chevron placeholder
                        }
                        
                        MouseArea {
                            id: mouseAreaList
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }
        }
    }
}
