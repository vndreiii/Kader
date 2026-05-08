import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qcm.Material

Item {
    id: root
    property alias topPadding: listView.topMargin
    signal openViewer(var mediaData)

    // Selection handling
    property var selectedPaths: ([])
    property bool selectionMode: selectedPaths.length > 0

    ListView {
        id: listView
        anchors.fill: parent
        model: TimelineModel
        clip: true
        spacing: 32
        leftMargin: 24
        rightMargin: 48 // Extra margin for the custom scrollbar
        bottomMargin: 40
        
        // Fast scroll logic
        onContentYChanged: {
            if (!fastScroll.pressed) {
                updateCurrentMonth()
            }
        }

        function updateCurrentMonth() {
            var idx = indexAt(24, contentY + topPadding + 50)
            if (idx >= 0) {
                var item = model.data(model.index(idx, 0), 0x0101) // NameRole
                fastScroll.currentMonth = item || ""
            }
        }

        delegate: ColumnLayout {
            width: listView.width - listView.leftMargin - listView.rightMargin
            spacing: 16

            Label {
                text: model.name
                font.pixelSize: 22
                font.bold: true
                color: ThemeManager.textColor
                opacity: 0.9
                Layout.topMargin: 12
            }

            Flow {
                id: flowGrid
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: items 

                    delegate: Item {
                        id: cellItem
                        width: Math.floor((listView.width - listView.leftMargin - listView.rightMargin - (columns - 1) * 8) / columns)
                        height: width
                        property int columns: Math.max(3, Math.floor(listView.width / 180))

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: ThemeManager.surfaceColor
                            clip: true
                            border.width: root.selectedPaths.includes(modelData.file_path) ? 4 : 0
                            border.color: ThemeManager.primaryColor

                            Image {
                                anchors.fill: parent
                                anchors.margins: root.selectedPaths.includes(modelData.file_path) ? 4 : 0
                                source: "file://" + ThumbGen.getOrCreateThumbnail(modelData.file_path)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }

                            // Video indicator
                            Rectangle {
                                visible: modelData.mime_type.startsWith("video/")
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.margins: 12
                                width: 28
                                height: 28
                                radius: 14
                                color: "#A0000000"
                                
                                Label {
                                    anchors.centerIn: parent
                                    text: "▶"
                                    color: "white"
                                    font.pixelSize: 12
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    contextMenu.popupTarget = modelData
                                    contextMenu.popup()
                                } else {
                                    root.openViewer(modelData)
                                }
                            }

                            // Marquee selection start
                            onPressed: (mouse) => {
                                if (mouse.button === Qt.LeftButton) {
                                    selectionTimer.start()
                                }
                            }
                            onReleased: selectionTimer.stop()
                        }
                    }
                }
            }
        }
    }

    // --- Custom Fast Scrollbar ---
    Item {
        id: fastScroll
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 40
        
        property string currentMonth: ""
        property bool pressed: mouseArea.pressed

        Rectangle {
            id: handle
            width: 4
            height: Math.max(40, (listView.visibleArea.heightRatio * parent.height))
            radius: 2
            color: ThemeManager.textColor
            opacity: fastScroll.pressed ? 0.8 : 0.2
            anchors.horizontalCenter: parent.horizontalCenter
            y: listView.visibleArea.yPosition * parent.height

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // The "Blob"
        Rectangle {
            id: blob
            height: 48
            width: monthLabel.width + 32
            radius: 24
            color: ThemeManager.primaryColor
            anchors.right: handle.left
            anchors.rightMargin: 16
            y: handle.y + handle.height/2 - height/2
            visible: fastScroll.pressed
            
            Label {
                id: monthLabel
                anchors.centerIn: parent
                text: fastScroll.currentMonth
                color: "white"
                font.bold: true
            }
            
            // Animation for growing blob
            scale: visible ? 1.0 : 0.5
            Behavior on scale { NumberAnimation { duration: 100 } }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            preventStealing: true
            
            function doScroll(mouseY) {
                var pos = Math.max(0, Math.min(1.0, mouseY / height))
                listView.contentY = pos * (listView.contentHeight - listView.height)
                listView.updateCurrentMonth()
            }

            onPressed: doScroll(mouse.y)
            onPositionChanged: doScroll(mouse.y)
        }
    }

    // --- Context Menu ---
    Menu {
        id: contextMenu
        property var popupTarget: null
        
        MenuItem {
            text: "Favorite"
            onTriggered: console.log("Favorite:", contextMenu.popupTarget.file_path)
        }
        MenuItem {
            text: "Delete"
            onTriggered: console.log("Delete:", contextMenu.popupTarget.file_path)
        }
    }

    // Marquee Selection Logic (Simplified placeholder)
    Timer {
        id: selectionTimer
        interval: 100
        onTriggered: console.log("Selection drag active")
    }
}
