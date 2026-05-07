import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QmlMaterial

Item {
    id: root
    property alias topPadding: listView.topMargin

    ListView {
        id: listView
        anchors.fill: parent
        model: TimelineModel
        clip: true
        spacing: 24
        leftMargin: 24
        rightMargin: 24
        bottomMargin: 40

        delegate: ColumnLayout {
            width: listView.width - listView.leftMargin - listView.rightMargin
            spacing: 12

            Label {
                text: model.name
                font.pixelSize: 20
                font.bold: true
                color: Theme.textColor
                Layout.topMargin: 12
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: items // The QVariantList from TimelineModel

                    delegate: Item {
                        width: Math.floor((listView.width - listView.leftMargin - listView.rightMargin - (columns - 1) * 8) / columns)
                        height: width
                        property int columns: Math.max(3, Math.floor(listView.width / 180))

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Theme.surfaceColor
                            clip: true

                            Image {
                                anchors.fill: parent
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
                                anchors.margins: 8
                                width: 24
                                height: 24
                                radius: 12
                                color: "#80000000"
                                
                                Label {
                                    anchors.centerIn: parent
                                    text: "▶"
                                    color: "white"
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: console.log("Clicked:", modelData.file_path)
                            }
                        }
                    }
                }
            }
        }
    }
}
