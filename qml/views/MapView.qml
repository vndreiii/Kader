import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import "../components"

Item {
    id: root
    property var locations: []

    Component.onCompleted: locations = DB.getGeotaggedLocations()

    Connections {
        target: FileScanner
        function onScanFinished() { root.locations = DB.getGeotaggedLocations() }
    }

    Plugin {
        id: mapPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.custom.host";  value: "https://a.basemaps.cartocdn.com/dark_all/" }
        PluginParameter { name: "osm.mapping.copyright";    value: "© OpenStreetMap contributors, © CARTO" }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // Map canvas — layer.enabled clips Map's OpenGL output to the rounded rectangle
        Rectangle {
            id: mapCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: ThemeManager.surfaceContainerLow
            clip: true
            layer.enabled: true

            // Attribution
            Label {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                z: 10
                text: "© OpenStreetMap contributors, © CARTO"
                font.pixelSize: 9
                color: Qt.alpha("white", 0.55)
            }

            // MapView provides pan/pinch/wheel gestures via PointerHandlers (Qt 6.5+)
            MapView {
                id: mapView
                anchors.fill: parent

                map.plugin: mapPlugin
                map.center: QtPositioning.coordinate(20, 0)
                map.zoomLevel: 2

                map.Component.onCompleted: {
                    // Select the custom Carto Dark tile set
                    for (var i = 0; i < map.supportedMapTypes.length; i++) {
                        if (map.supportedMapTypes[i].style === MapType.CustomMap) {
                            map.activeMapType = map.supportedMapTypes[i]
                            break
                        }
                    }
                }

                map.onMapReadyChanged: {
                    if (map.mapReady && root.locations.length > 0)
                        fitToLocations()
                }

                function fitToLocations() {
                    if (root.locations.length === 0) return
                    if (root.locations.length === 1) {
                        map.center = QtPositioning.coordinate(root.locations[0].lat, root.locations[0].lon)
                        map.zoomLevel = 10
                    } else {
                        map.fitViewportToMapItems()
                    }
                }

                // Location pins — must be parented to the underlying Map
                MapItemView {
                    parent: mapView.map
                    model: root.locations
                    delegate: MapQuickItem {
                        coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                        anchorPoint.x: bubble.width / 2
                        anchorPoint.y: bubble.height + 10

                        sourceItem: Rectangle {
                            id: bubble
                            height: 36
                            width: thumbRect.width + countBadge.width + 16
                            radius: 18
                            color: ThemeManager.primary

                            Row {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 6

                                Rectangle {
                                    id: thumbRect
                                    width: 28; height: 28; radius: 14; clip: true
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: ThemeManager.primaryContainer
                                    Image {
                                        anchors.fill: parent
                                        source: modelData.thumb || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }

                                Rectangle {
                                    id: countBadge
                                    width: countLabel.implicitWidth + 10
                                    height: 20; radius: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Qt.alpha("white", 0.22)
                                    Label {
                                        id: countLabel
                                        anchors.centerIn: parent
                                        text: modelData.count
                                        color: "white"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            // Pin tail
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: -6
                                width: 12; height: 12
                                color: parent.color
                                rotation: 45
                            }
                        }
                    }
                }
            }
        }

        // Right panel: places list or empty state
        Rectangle {
            Layout.fillHeight: true
            width: 300
            color: ThemeManager.surfaceContainer
            radius: 16

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

                ColumnLayout {
                    visible: root.locations.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12
                    Item { Layout.fillHeight: true }
                    M3Icon { Layout.alignment: Qt.AlignHCenter; name: "map"; size: 56; color: ThemeManager.onSurfaceVariant; opacity: 0.4 }
                    Label { Layout.alignment: Qt.AlignHCenter; text: "No location data yet"; font.pixelSize: 15; font.weight: Font.Medium; color: ThemeManager.onSurface }
                    Label {
                        Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                        text: "Scan your library to extract GPS coordinates from photo EXIF data."
                        font.pixelSize: 12; color: ThemeManager.onSurfaceVariant; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    }
                    Item { Layout.fillHeight: true }
                }

                ListView {
                    id: placeList
                    Layout.fillWidth: true; Layout.fillHeight: true
                    model: root.locations; clip: true; spacing: 4
                    visible: root.locations.length > 0

                    delegate: Rectangle {
                        width: placeList.width; height: 72; radius: 12
                        color: hoverArea.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.05) : "transparent"

                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 12
                            Rectangle {
                                width: 56; height: 56; radius: 12; color: ThemeManager.surfaceContainerHigh; clip: true
                                Image { anchors.fill: parent; source: modelData.thumb || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Label { text: modelData.lat.toFixed(4) + "°, " + modelData.lon.toFixed(4) + "°"; font.weight: Font.Medium; font.pixelSize: 12; color: ThemeManager.onSurface; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: modelData.count + (modelData.count === 1 ? " photo" : " photos"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                            }
                        }

                        MouseArea {
                            id: hoverArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                mapView.map.center = QtPositioning.coordinate(modelData.lat, modelData.lon)
                                mapView.map.zoomLevel = 13
                            }
                        }
                    }
                }
            }
        }
    }
}
