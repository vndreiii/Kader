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
    // The open place: {lat, lon, count, thumb, places: [...]} — a single
    // location or a cluster of them, like the globe's.
    property var    activePlace:  null
    // Esc (window-wide "back"): close the place card
    function handleBack() {
        if (!activePlace) return false
        placePopup.close()
        return true
    }
    property point  _pinScreenPos: Qt.point(0, 0)
    // Screen-space clusters of the locations, rebuilt as the map moves:
    // [{x, y, lat, lon, count, members, thumb, places, key}]
    property var    clusters: []
    readonly property real clusterCell: 64

    function _updatePinPos() {
        if (!activePlace) return
        _pinScreenPos = mapView.map.fromCoordinate(
            QtPositioning.coordinate(activePlace.lat, activePlace.lon), false)
    }
    function placeOf(loc) {
        return { lat: loc.lat, lon: loc.lon, count: loc.count, thumb: loc.thumb || "", places: [loc] }
    }

    // Group pins that would overlap on screen (cells of clusterCell px),
    // weighted by photo count; the busiest location leads (photo + anchor).
    function recluster() {
        var m = mapView.map
        if (!m || !m.mapReady) { clusters = []; return }
        var cells = {}, out = []
        var w = mapCanvasRoot.width, h = mapCanvasRoot.height
        for (var i = 0; i < locations.length; i++) {
            var loc = locations[i]
            var p = m.fromCoordinate(QtPositioning.coordinate(loc.lat, loc.lon), false)
            if (isNaN(p.x) || p.x < -80 || p.y < -80 || p.x > w + 80 || p.y > h + 120) continue
            var key = Math.floor(p.x / clusterCell) + ":" + Math.floor(p.y / clusterCell)
            var c = cells[key]
            if (!c) {
                c = { sx: 0, sy: 0, count: 0, members: 0, places: [], lead: loc, key: key }
                cells[key] = c
                out.push(c)
            }
            var n = Math.max(1, loc.count)
            c.sx += p.x * n; c.sy += p.y * n
            c.count += loc.count
            c.members++
            c.places.push(loc)
            if (loc.count > c.lead.count) c.lead = loc
        }
        for (var j = 0; j < out.length; j++) {
            var cl = out[j]
            var lp = m.fromCoordinate(QtPositioning.coordinate(cl.lead.lat, cl.lead.lon), false)
            // a single location sits exactly on its spot; a cluster on its lead
            cl.x = lp.x; cl.y = lp.y
            cl.lat = cl.lead.lat; cl.lon = cl.lead.lon
            cl.thumb = cl.lead.thumb || ""
        }
        clusters = out
    }
    function _scheduleRecluster() { Qt.callLater(root.recluster) }
    function _isActive(c) {
        if (!activePlace) return false
        for (var i = 0; i < c.places.length; i++)
            if (c.places[i].lat === activePlace.lat && c.places[i].lon === activePlace.lon) return true
        return false
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

    // Keep pins and the popup on their places as the map pans/zooms
    Connections {
        target: mapView.map
        function onCenterChanged()    { root._updatePinPos(); root._scheduleRecluster() }
        function onZoomLevelChanged() { root._updatePinPos(); root._scheduleRecluster() }
        function onWidthChanged()     { root._scheduleRecluster() }
        function onHeightChanged()    { root._scheduleRecluster() }
    }
    onLocationsChanged: _scheduleRecluster()

    // OpenStreetMap's own tiles: no API key (CARTO's basemaps now require
    // one). OSM's tile policy asks apps to identify themselves.
    Plugin {
        id: mapPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.custom.host";  value: "https://tile.openstreetmap.org/" }
        PluginParameter { name: "osm.mapping.copyright";    value: "© OpenStreetMap contributors" }
        PluginParameter { name: "osm.useragent";            value: "Kader/" + Qt.application.version + " (+https://github.com/vndreiii/kader)" }
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
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
                        root._scheduleRecluster()
                    }

                    function fitToLocations() {
                        if (root.locations.length === 0) return
                        if (root.locations.length === 1) {
                            map.center = QtPositioning.coordinate(root.locations[0].lat, root.locations[0].lon)
                            map.zoomLevel = 10
                        } else {
                            var lats = root.locations.map(l => l.lat), lons = root.locations.map(l => l.lon)
                            var r = QtPositioning.rectangle(
                                QtPositioning.coordinate(Math.max.apply(null, lats), Math.min.apply(null, lons)),
                                QtPositioning.coordinate(Math.min.apply(null, lats), Math.max.apply(null, lons)))
                            map.visibleRegion = r
                            map.zoomLevel = Math.max(map.minimumZoomLevel, map.zoomLevel - 0.4)
                        }
                    }

                }

                // ── photo pins: the globe's PhotoPin, clustered on screen ──
                Item {
                    id: pinOverlay
                    anchors.fill: parent
                    z: 20
                    Repeater {
                        model: root.clusters
                        delegate: PhotoPin {
                            required property var modelData
                            readonly property bool isActive: root._isActive(modelData)
                            photo: modelData.thumb
                            photos: modelData.count
                            stacked: modelData.members > 1 || modelData.count > 1
                            hot: pinHover.hovered
                            active: isActive
                            accent: ThemeManager.primary
                            // while open, the pin *is* the card (it morphed into it)
                            visible: !isActive
                            x: modelData.x - width / 2
                            y: modelData.y - height
                            z: hot ? 2 : 0
                            scale: hot ? 1.14 : 1.0
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            HoverHandler { id: pinHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    var c = modelData
                                    root.activePlace = { lat: c.lat, lon: c.lon, count: c.count, thumb: c.thumb, places: c.places }
                                    root._updatePinPos()
                                }
                            }
                        }
                    }
                }

                // Touchpad two-finger scroll pans the map (the map's own handler
                // would zoom); pinch and Ctrl+wheel still zoom, a mouse wheel
                // still zooms. Takes no clicks.
                MouseArea {
                    anchors.fill: mapView
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        var touchpad = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0
                        if (!touchpad || (wheel.modifiers & Qt.ControlModifier)) {
                            wheel.accepted = false   // let the map zoom
                            return
                        }
                        mapView.map.pan(-wheel.pixelDelta.x, -wheel.pixelDelta.y)
                        wheel.accepted = true
                    }
                }

                // ── Pin popup card (shared with the globe) ───────────────
                PlacePopup {
                    id: placePopup
                    anchors.fill: parent
                    z: 60
                    place: root.activePlace
                    pinThumb: root.activePlace ? root.activePlace.thumb : ""
                    anchorX: root._pinScreenPos.x
                    anchorY: root._pinScreenPos.y
                    onOpenRequested: (place) => root.openPlaces(place.places)
                    onOpenItems: (items, i) => root.openViewer(items[i], items)
                    onCloseRequested: root.activePlace = null
                }

                // Attribution
                Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    z: 10
                    text: "© OpenStreetMap contributors"
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
                                root.activePlace = root.placeOf(modelData)
                                root._updatePinPos()
                            }
                        }
                    }
                }
            }
        }
    }
}
