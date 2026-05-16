import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import "../components"

Item {
    id: root

    property var locations: []

    Component.onCompleted: {
        locations = DB.getGeotaggedLocations()
    }

    Connections {
        target: FileScanner
        function onScanFinished() {
            root.locations = DB.getGeotaggedLocations()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // Map Canvas
        Rectangle {
            id: mapCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 24
            color: ThemeManager.surfaceContainerLow
            clip: true

            // Attribution (CARTO/OSM requirement)
            Label {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                z: 10
                text: "© OpenStreetMap contributors, © CARTO"
                font.pixelSize: 9
                color: Qt.alpha("white", 0.55)
            }

            Plugin {
                id: mapPlugin
                name: "osm"
                PluginParameter {
                    name: "osm.mapping.custom.host"
                    value: "https://a.basemaps.cartocdn.com/dark_all/"
                }
                PluginParameter {
                    name: "osm.mapping.copyright"
                    value: "© OpenStreetMap contributors, © CARTO"
                }
            }

            Map {
                id: map
                anchors.fill: parent
                plugin: mapPlugin
                center: QtPositioning.coordinate(20, 0)
                zoomLevel: 2
                gesture.enabled: true
                gesture.acceptedGestures: MapGestureArea.PanGesture | MapGestureArea.PinchGesture | MapGestureArea.FlickGesture

                Component.onCompleted: {
                    for (var i = 0; i < supportedMapTypes.length; i++) {
                        if (supportedMapTypes[i].style === MapType.CustomMap) {
                            activeMapType = supportedMapTypes[i]
                            break
                        }
                    }
                }

                // Fit map to actual photo locations once data loads
                onMapReadyChanged: {
                    if (mapReady && root.locations.length > 0) fitToLocations()
                }

                function fitToLocations() {
                    if (root.locations.length === 0) return
                    var minLat = 90, maxLat = -90, minLon = 180, maxLon = -180
                    for (var i = 0; i < root.locations.length; i++) {
                        var l = root.locations[i]
                        if (l.lat < minLat) minLat = l.lat
                        if (l.lat > maxLat) maxLat = l.lat
                        if (l.lon < minLon) minLon = l.lon
                        if (l.lon > maxLon) maxLon = l.lon
                    }
                    if (root.locations.length === 1) {
                        center = QtPositioning.coordinate(root.locations[0].lat, root.locations[0].lon)
                        zoomLevel = 10
                    } else {
                        fitViewportToMapItems()
                    }
                }

                MapItemView {
                    model: root.locations
                    delegate: MapQuickItem {
                        coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                        anchorPoint.x: bubble.width / 2
                        anchorPoint.y: bubble.height + 10

                        sourceItem: Rectangle {
                            id: bubble
                            height: 36
                            width: countBadge.width + thumbRect.width + 12
                            radius: 18
                            color: ThemeManager.primary

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 6

                                Rectangle {
                                    id: thumbRect
                                    width: 28; height: 28; radius: 14; clip: true
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

                            // Drop-shadow tail
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

                // Empty state — shown here in the panel, map stays visible
                ColumnLayout {
                    visible: root.locations.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    Item { Layout.fillHeight: true }

                    M3Icon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "map"
                        size: 56
                        color: ThemeManager.onSurfaceVariant
                        opacity: 0.4
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No location data yet"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        color: ThemeManager.onSurface
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: "Scan your library to extract GPS coordinates from photo EXIF data."
                        font.pixelSize: 12
                        color: ThemeManager.onSurfaceVariant
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Item { Layout.fillHeight: true }
                }

                ListView {
                    id: placeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.locations
                    clip: true
                    spacing: 4
                    visible: root.locations.length > 0

                    delegate: Rectangle {
                        width: placeList.width
                        height: 72
                        radius: 12
                        color: hoverArea.containsMouse
                               ? Qt.alpha(ThemeManager.onSurface, 0.05)
                               : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 12

                            Rectangle {
                                width: 56; height: 56; radius: 12
                                color: ThemeManager.surfaceContainerHigh
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: modelData.thumb || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    text: modelData.lat.toFixed(4) + "°, " + modelData.lon.toFixed(4) + "°"
                                    font.weight: Font.Medium
                                    font.pixelSize: 12
                                    color: ThemeManager.onSurface
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: modelData.count + (modelData.count === 1 ? " photo" : " photos")
                                    font.pixelSize: 12
                                    color: ThemeManager.onSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: hoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                map.center = QtPositioning.coordinate(modelData.lat, modelData.lon)
                                map.zoomLevel = 13
                            }
                        }
                    }
                }
            }
        }
    }
}
