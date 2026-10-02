import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtLocation
import QtPositioning
import "../components"
import "../I18n.js" as I18n

Item {
    id: root
    property var    locations:    []
    property var    activePin:    null
        property point  _pinScreenPos: Qt.point(0, 0)

    function _updatePinPos() {
        if (!activePin) return
        _pinScreenPos = mapView.map.fromCoordinate(
            QtPositioning.coordinate(activePin.lat, activePin.lon), false)
    }

    signal openViewer(var data, var items)

    function openPlaces(places) {
        var items = DB.getMediaForPlaces(places)
        if (items.length === 0 && places.length > 0) items = [places[0]]
        if (items.length > 0) root.openViewer(items[0], items)
    }

    property bool _loaded: false

    onVisibleChanged: {
        if (visible && !_loaded) {
            _loaded = true
            locations = DB.getGeotaggedLocations()
        }
    }
    Component.onCompleted: {
        if (visible) {
            _loaded = true
            locations = DB.getGeotaggedLocations()
        }
    }

    Connections {
        target: FileScanner
        function onLibraryChanged() { if (root._loaded) root.locations = DB.getGeotaggedLocations() }
    }

    // Keep popup anchored to the pin as the map pans/zooms
    Connections {
        target: mapView.map
        function onCenterChanged()    { if (root.activePin) root._updatePinPos() }
        function onZoomLevelChanged() { if (root.activePin) root._updatePinPos() }
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

        // ── Map canvas with MultiEffect rounded corners ───────────────────
        Item {
            id: mapCanvasRoot
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Loading placeholder, on top until the map plugin is ready
            Skeleton {
                z: 5
                anchors.fill: parent
                radius: 16
                visible: !mapView.map.mapReady
                active: visible
            }

            // Round mask — fed into MultiEffect below
            Rectangle {
                id: mapRoundMask
                anchors.fill: mapContentLayer
                radius: 16
                color: "white"
                visible: false
                layer.enabled: true
            }

            // Map + overlay content captured as a layer so MultiEffect can clip it
            Item {
                id: mapContentLayer
                anchors.fill: parent

                MapView {
                    id: mapView
                    anchors.fill: parent

                    map.plugin: mapPlugin
                    map.center: QtPositioning.coordinate(51, 10)
                    map.zoomLevel: 4

                    map.Component.onCompleted: {
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

                    // Location pins
                    MapItemView {
                        parent: mapView.map
                        model: root.locations
                        delegate: MapQuickItem {
                            coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                            anchorPoint.x: pinBubble.width / 2
                            anchorPoint.y: pinBubble.height + 8

                            sourceItem: Item {
                                id: pinBubble
                                width: pinRow.width + 16
                                height: 44

                                // Drop shadow
                                Rectangle {
                                    anchors.fill: pinBody
                                    anchors.margins: -1
                                    radius: pinBody.radius + 1
                                    color: Qt.alpha("black", 0.35)
                                    anchors.topMargin: 3
                                    z: -1
                                }

                                // Dark pill body
                                Rectangle {
                                    id: pinBody
                                    anchors.fill: parent
                                    radius: 22
                                    color: Qt.rgba(0.08, 0.08, 0.10, 0.92)

                                    Row {
                                        id: pinRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        leftPadding: 6
                                        rightPadding: 10

                                        // Thumbnail with rounded corners
                                        Rectangle {
                                            width: 32; height: 32; radius: 10
                                            color: Qt.rgba(1,1,1,0.12)
                                            anchors.verticalCenter: parent.verticalCenter
                                            clip: true
                                            Image {
                                                anchors.fill: parent
                                                source: modelData.thumb || ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }
                                        }

                                        Label {
                                            text: modelData.count
                                            color: "white"
                                            font.pixelSize: ThemeManager.fontLabelL
                                            font.weight: Font.SemiBold
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // Pin tail
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: pinBody.bottom
                                    anchors.topMargin: -6
                                    width: 10; height: 10
                                    color: pinBody.color
                                    rotation: 45
                                }

                                MouseArea {
                                    anchors.fill: pinBody
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activePin = modelData
                                        root._updatePinPos()
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Pin popup card (shared with the globe) ───────────────
                PlacePopup {
                    anchors.fill: parent
                    z: 60
                    place: root.activePin ? { lat: root.activePin.lat, lon: root.activePin.lon,
                                              count: root.activePin.count, places: [root.activePin] } : null
                    anchorX: root._pinScreenPos.x
                    anchorY: root._pinScreenPos.y
                    anchorGap: 60
                    onOpenRequested: (place) => root.openPlaces(place.places)
                    onCloseRequested: root.activePin = null
                }

                // Attribution
                Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    z: 10
                    text: "© OpenStreetMap contributors, © CARTO"
                    font.pixelSize: 9
                    color: Qt.alpha("white", 0.45)
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    maskSource: mapRoundMask
                }
            }
        }

        // ── Right panel: places list ──────────────────────────────────────
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
                    text: I18n.t(Settings.language, "places")
                    font.family: "Roboto Flex"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: ThemeManager.onSurface
                    Layout.leftMargin: 8
                }

                // Empty state
                ColumnLayout {
                    visible: root.locations.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12
                    Item { Layout.fillHeight: true }
                    M3Icon { Layout.alignment: Qt.AlignHCenter; name: "map"; size: 56; color: ThemeManager.onSurfaceVariant; opacity: 0.4 }
                    Label { Layout.alignment: Qt.AlignHCenter; text: I18n.t(Settings.language, "empty_map"); font.pixelSize: 15; font.weight: Font.Medium; color: ThemeManager.onSurface }
                    Label {
                        Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                        text: I18n.t(Settings.language, "empty_map_sub")
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
                        width: placeList.width; height: 76; radius: 12
                        color: hoverArea.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.07) : "transparent"
                        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 12

                            // Thumbnail
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
                                Layout.fillWidth: true; spacing: 3

                                Label {
                                    text: modelData.lat.toFixed(4) + "°, " + modelData.lon.toFixed(4) + "°"
                                    font.weight: Font.Medium; font.pixelSize: 12
                                    color: ThemeManager.onSurface
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }

                                Label {
                                    visible: !!modelData.creation_date
                                    text: Qt.formatDateTime(new Date(modelData.creation_date * 1000), "d MMM yyyy")
                                    font.pixelSize: 11; color: ThemeManager.onSurfaceVariant
                                }

                                Label {
                                    text: modelData.count + (modelData.count === 1 ? " photo" : " photos")
                                    font.pixelSize: 11; color: ThemeManager.onSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: hoverArea; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mapView.map.center = QtPositioning.coordinate(modelData.lat, modelData.lon)
                                mapView.map.zoomLevel = 13
                                root.activePin = modelData
                                root._updatePinPos()
                            }
                        }
                    }
                }
            }
        }
    }
}
