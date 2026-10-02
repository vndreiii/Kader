import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Kader.Globe 1.0
import "../components"
import "../I18n.js" as I18n

// Places on an interactive 3D globe. Rendering, picking and decluttering are
// done by the Rust geo engine behind `Globe`; this file is presentation only.
Item {
    id: root
    property var locations: []
    // {lat, lon, count, places:[location…], cluster} of the open place card
    property var activePlace: null

    signal openViewer(var data, var items)

    readonly property bool narrow: width < 980
    property bool panelOpen: true
    readonly property bool panelShown: panelOpen && (!narrow || panelToggle.checked)

    property bool _loaded: false
    function _reload() {
        _loaded = true
        locations = DB.getGeotaggedLocations()
    }
    onVisibleChanged: if (visible && !_loaded) _reload()
    Component.onCompleted: if (visible) _reload()
    Connections {
        target: FileScanner
        function onScanFinished() { if (root._loaded) root._reload() }
    }

    function _t(key) { return I18n.t(Settings.language, key) }

    // Offline place label: "Lyon, France", or "Near Manaus, Brazil" when the
    // closest town is far away; coordinates as a last resort.
    function placeLabel(lat, lon) {
        var info = globe.ready ? globe.placeInfo(lat, lon) : ({})
        if (info.name) return info.km > 25 ? _t("place_near").arg(info.name) : info.name
        return lat.toFixed(4) + "°, " + lon.toFixed(4) + "°"
    }

    function selectCluster(cluster) {
        var info = globe.clusterInfo(cluster)
        if (!info.lat && info.lat !== 0) return
        var members = globe.clusterMembers(cluster)
        // Several places merged into one bubble: zoom until they separate,
        // unless we're already at street level.
        if (members.length > 1 && globe.zoomLevel < 13.5) {
            activePlace = null
            globe.expandCluster(cluster)
            return
        }
        activePlace = { lat: info.lat, lon: info.lon, count: info.count, places: members, cluster: cluster }
    }

    function selectLocation(loc) {
        activePlace = { lat: loc.lat, lon: loc.lon, count: loc.count, places: [loc], cluster: -1 }
        globe.flyTo(loc.lat, loc.lon, 60)
    }

    function openPlace(place) {
        if (!place) return
        var items = DB.getMediaForPlaces(place.places)
        if (items.length === 0 && place.places.length > 0) items = [place.places[0]]
        if (items.length > 0) root.openViewer(items[0], items)
    }

    // ── palette: a dark "space" canvas in both themes keeps contrast high ───
    readonly property color _accent: ThemeManager.isDark ? ThemeManager.primary : ThemeManager.inversePrimary
    readonly property color _space: Qt.rgba(0.020, 0.024, 0.040, 1)
    readonly property color _labelInk: "#f4f6fb"
    readonly property color _labelHalo: Qt.rgba(0.02, 0.03, 0.06, 0.92)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ── Globe canvas ─────────────────────────────────────────────────────
        Item {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // deep-space backdrop with a faint accent nebula behind the globe
            Rectangle {
                anchors.fill: parent
                color: root._space
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.max(parent.width, parent.height) * 1.2
                    height: width
                    radius: width / 2
                    opacity: 0.55
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.10) }
                        GradientStop { position: 0.5; color: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.03) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }

            Globe {
                id: globe
                anchors.fill: parent
                focus: true
                locations: root.locations
                autoRotate: true

                oceanColor: Qt.rgba(0.045 + root._accent.r * 0.05, 0.060 + root._accent.g * 0.05, 0.110 + root._accent.b * 0.06, 1)
                oceanEdgeColor: Qt.rgba(0.015, 0.020, 0.040, 1)
                glowColor: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.85)
                landColor: Qt.rgba(0.90, 0.93, 0.98, 0.92)
                coastColor: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.80)
                borderColor: Qt.rgba(1, 1, 1, 0.82)
                stateColor: Qt.rgba(1, 1, 1, 0.36)
                cityColor: "white"
                cityHaloColor: Qt.rgba(0.02, 0.03, 0.06, 0.85)
                casingColor: Qt.rgba(0.015, 0.02, 0.04, 0.92)
                pinSize: Qt.size(52, 62)

                onPinClicked: (cluster) => root.selectCluster(cluster)
                onGlobeClicked: (lat, lon) => root.activePlace = null
            }

            // ── place labels (pooled; positions come from the engine) ───────
            Item {
                anchors.fill: globe
                Repeater {
                    model: globe.labels
                    delegate: Text {
                        required property string ltext
                        required property real lx
                        required property real ly
                        required property real lopacity
                        required property int lclass
                        required property int lanchor
                        required property bool lcapital

                        text: ltext
                        visible: lopacity > 0.01
                        opacity: lopacity
                        x: lanchor === 1 ? lx + 7 : lanchor === 2 ? lx - 7 - width : lx - width / 2
                        y: ly - height / 2
                        renderType: Text.QtRendering
                        style: Text.Outline
                        styleColor: root._labelHalo
                        // class: 0 ocean, 1 country, 2 state, 3 major city, 4 city, 5 town
                        color: lclass === 0 ? Qt.lighter(root._accent, 1.25)
                             : lclass === 2 ? Qt.rgba(1, 1, 1, 0.70)
                             : lclass === 5 ? Qt.rgba(1, 1, 1, 0.86)
                             : root._labelInk
                        font.pixelSize: [12, 12.5, 10, 13.5, 12, 11][lclass]
                        font.italic: lclass === 0
                        font.letterSpacing: [1.5, 1.6, 1.0, 0, 0, 0][lclass]
                        font.capitalization: (lclass === 1 || lclass === 2) ? Font.AllUppercase : Font.MixedCase
                        font.weight: lclass === 1 || lclass === 3 || lcapital ? Font.DemiBold
                                   : lclass === 4 ? Font.Medium : Font.Normal
                    }
                }
            }

            // ── photo pins ──────────────────────────────────────────────────
            Item {
                id: pinLayer
                anchors.fill: globe
                Rectangle {
                    id: pinMask
                    width: 44; height: 44; radius: 13
                    visible: false
                    layer.enabled: true
                }
                Repeater {
                    model: globe.pins
                    delegate: Item {
                        id: pin
                        required property real px
                        required property real py
                        required property real depth
                        required property real popacity
                        required property bool shown
                        required property int count
                        required property int members
                        required property var thumb
                        required property int cluster

                        readonly property bool hot: globe.hoveredCluster === cluster
                        readonly property bool active: root.activePlace !== null && root.activePlace.cluster === cluster

                        visible: shown && popacity > 0.02
                        opacity: popacity
                        width: 52; height: 62
                        x: px - width / 2
                        y: py - height
                        z: depth + (hot || active ? 2 : 0)
                        transformOrigin: Item.Bottom
                        scale: (hot || active ? 1.12 : 1.0) * (0.82 + 0.18 * depth)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        // tail + ground dot mark the exact spot
                        Rectangle {
                            width: 12; height: 12; rotation: 45
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 42
                            color: frame.color
                        }
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            color: root._accent
                            border.color: "white"; border.width: 1.5
                        }
                        Rectangle {
                            id: frame
                            width: 52; height: 52; radius: 16
                            color: pin.active ? root._accent : "white"
                            Rectangle { // placeholder while the thumbnail loads
                                anchors.centerIn: parent
                                width: 44; height: 44; radius: 13
                                color: Qt.rgba(0.12, 0.14, 0.2, 1)
                            }
                            Image {
                                anchors.centerIn: parent
                                width: 44; height: 44
                                source: pin.thumb || ""
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: pinMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                }
                            }
                        }
                        // photo count
                        Rectangle {
                            visible: pin.count > 1
                            anchors { right: frame.right; top: frame.top; rightMargin: -6; topMargin: -6 }
                            height: 22; radius: 11
                            width: Math.max(22, countLbl.implicitWidth + 12)
                            color: root._accent
                            border.color: root._space; border.width: 2
                            Text {
                                id: countLbl
                                anchors.centerIn: parent
                                text: pin.count > 999 ? Math.round(pin.count / 100) / 10 + "k" : pin.count
                                color: ThemeManager.isDark ? ThemeManager.onPrimary : ThemeManager.primary
                                font.pixelSize: 11; font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            // ── place card follows its place across the globe ───────────────
            PlacePopup {
                id: popup
                anchors.fill: globe
                z: 50
                place: root.activePlace
                offlineName: root.activePlace && globe.ready ? root.placeLabel(root.activePlace.lat, root.activePlace.lon) : ""
                property var _proj: ({ x: 0, y: 0, visible: false })
                anchorX: _proj.x
                anchorY: _proj.y
                anchorVisible: _proj.visible
                function track() {
                    if (root.activePlace) _proj = globe.project(root.activePlace.lat, root.activePlace.lon)
                }
                Connections {
                    target: globe
                    function onFrameUpdated() { popup.track() }
                }
                onPlaceChanged: track()
                onOpenRequested: (place) => root.openPlace(place)
                onCloseRequested: root.activePlace = null
            }

            // ── controls ────────────────────────────────────────────────────
            Column {
                anchors { top: parent.top; right: parent.right; margins: 16 }
                spacing: 10
                z: 60

                Rectangle {
                    width: 44; height: zoomCol.height; radius: 22
                    color: Qt.rgba(0.07, 0.08, 0.11, 0.86)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Column {
                        id: zoomCol
                        GlobeButton { icon: "add"; tip: root._t("globe_zoom_in"); onClicked: globe.zoomIn() }
                        Rectangle { width: 24; height: 1; color: Qt.rgba(1, 1, 1, 0.14); anchors.horizontalCenter: parent.horizontalCenter }
                        GlobeButton { icon: "remove"; tip: root._t("globe_zoom_out"); onClicked: globe.zoomOut() }
                    }
                }
                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: Qt.rgba(0.07, 0.08, 0.11, 0.86)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    GlobeButton { icon: "public"; tip: root._t("globe_reset"); onClicked: { root.activePlace = null; globe.resetView() } }
                }
                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: globe.autoRotate ? Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.92) : Qt.rgba(0.07, 0.08, 0.11, 0.86)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    GlobeButton {
                        icon: "3d_rotation"
                        tip: root._t("globe_spin")
                        ink: globe.autoRotate ? (ThemeManager.isDark ? ThemeManager.onPrimary : ThemeManager.primary) : "white"
                        onClicked: globe.autoRotate = !globe.autoRotate
                    }
                }
                Rectangle {
                    visible: root.narrow
                    width: 44; height: 44; radius: 22
                    color: panelToggle.checked ? Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.92) : Qt.rgba(0.07, 0.08, 0.11, 0.86)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    GlobeButton {
                        id: panelToggle
                        property bool checked: false
                        icon: "list"
                        tip: root._t("places")
                        ink: checked ? (ThemeManager.isDark ? ThemeManager.onPrimary : ThemeManager.primary) : "white"
                        onClicked: checked = !checked
                    }
                }
            }

            // coordinate / zoom readout + data attribution
            Row {
                anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
                spacing: 8
                z: 60
                visible: globe.ready
                Rectangle {
                    height: 28; radius: 14
                    width: readout.implicitWidth + 22
                    color: Qt.rgba(0.07, 0.08, 0.11, 0.80)
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                    Text {
                        id: readout
                        anchors.centerIn: parent
                        color: Qt.rgba(1, 1, 1, 0.85)
                        font.pixelSize: 11
                        font.family: "monospace"
                        text: Math.abs(globe.centerLat).toFixed(2) + "° " + (globe.centerLat >= 0 ? "N" : "S") + "  "
                              + Math.abs(globe.centerLon).toFixed(2) + "° " + (globe.centerLon >= 0 ? "E" : "W")
                              + "   z " + globe.zoomLevel.toFixed(1)
                    }
                }
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                z: 60
                text: "Natural Earth · GeoNames (CC BY 4.0)"
                color: Qt.rgba(1, 1, 1, 0.40)
                font.pixelSize: 10
            }

            // loading scaffold until the world dataset is decoded
            Item {
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: globe.ready ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 260 } }
                z: 70
                Rectangle {
                    id: ghost
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.8
                    height: width; radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.35)
                    border.width: 1
                    SequentialAnimation on opacity {
                        running: !globe.ready
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors { top: ghost.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                    text: root._t("globe_loading")
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 12
                }
            }

            // rounded corners without an offscreen pass: paint the page colour
            // into the four corners
            Repeater {
                model: 4
                delegate: Shape {
                    required property int index
                    readonly property real r: 16
                    width: r; height: r
                    z: 80
                    x: (index % 2) ? canvas.width - r : 0
                    y: index >= 2 ? canvas.height - r : 0
                    rotation: [0, 90, 270, 180][index]
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: ThemeManager.surface
                        startX: 0; startY: 0
                        PathLine { x: 16; y: 0 }
                        PathArc { x: 0; y: 16; radiusX: 16; radiusY: 16; direction: PathArc.Counterclockwise }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        // ── Places panel ─────────────────────────────────────────────────────
        Rectangle {
            id: panel
            visible: root.panelShown
            Layout.fillHeight: true
            Layout.preferredWidth: root.narrow ? 280 : 320
            color: ThemeManager.surfaceContainer
            radius: 16

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 20
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Label {
                        text: root._t("places")
                        font.family: "Roboto Flex"
                        font.pixelSize: 20
                        font.weight: Font.Medium
                        color: ThemeManager.onSurface
                        Layout.fillWidth: true
                    }
                    Label {
                        visible: root.locations.length > 0
                        text: root.locations.length
                        color: ThemeManager.onSurfaceVariant
                        font.pixelSize: 13
                        Layout.rightMargin: 8
                    }
                }

                ColumnLayout {
                    visible: root._loaded && root.locations.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12
                    Item { Layout.fillHeight: true }
                    MaterialSymbol { Layout.alignment: Qt.AlignHCenter; name: "travel_explore"; size: 56; color: ThemeManager.onSurfaceVariant; opacity: 0.5 }
                    Label { Layout.alignment: Qt.AlignHCenter; text: root._t("empty_map"); font.pixelSize: 15; font.weight: Font.Medium; color: ThemeManager.onSurface }
                    Label {
                        Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                        text: root._t("empty_map_sub")
                        font.pixelSize: 12; color: ThemeManager.onSurfaceVariant; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    }
                    Item { Layout.fillHeight: true }
                }

                // skeleton rows while the first query runs
                Column {
                    visible: !root._loaded
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: 6
                        Rectangle {
                            width: parent.width; height: 72; radius: 14
                            color: Qt.alpha(ThemeManager.onSurface, 0.05)
                        }
                    }
                }

                ListView {
                    id: placeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.locations
                    clip: true
                    spacing: 4
                    visible: root.locations.length > 0
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool selected: root.activePlace !== null
                            && Math.abs(root.activePlace.lat - modelData.lat) < 1e-6
                            && Math.abs(root.activePlace.lon - modelData.lon) < 1e-6
                        width: placeList.width
                        height: 72
                        radius: 14
                        color: selected ? ThemeManager.secondaryContainer
                             : hoverArea.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.07) : "transparent"
                        Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }

                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                                radius: 12
                                color: ThemeManager.surfaceContainerHigh
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: row.modelData.thumb || ""
                                    sourceSize: Qt.size(112, 112)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    Layout.fillWidth: true
                                    text: globe.ready, root.placeLabel(row.modelData.lat, row.modelData.lon)
                                    font.weight: Font.Medium; font.pixelSize: 13
                                    color: row.selected ? ThemeManager.onSecondaryContainer : ThemeManager.onSurface
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: {
                                        var parts = []
                                        if (row.modelData.creation_date)
                                            parts.push(Qt.formatDateTime(new Date(row.modelData.creation_date * 1000), "d MMM yyyy"))
                                        parts.push(row.modelData.count + " " + (row.modelData.count === 1 ? root._t("photo_one") : root._t("photo_many")))
                                        return parts.join(" · ")
                                    }
                                    font.pixelSize: 11
                                    color: row.selected ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: hoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectLocation(row.modelData)
                            onDoubleClicked: root.openPlace({ places: [row.modelData] })
                        }
                    }
                }
            }
        }
    }

    component GlobeButton: Item {
        id: btn
        property string icon
        property string tip
        property color ink: "white"
        signal clicked()
        width: 44; height: 44
        Rectangle {
            anchors.centerIn: parent
            width: 36; height: 36; radius: 18
            color: Qt.rgba(1, 1, 1, ma.pressed ? 0.22 : ma.containsMouse ? 0.12 : 0)
        }
        MaterialSymbol { anchors.centerIn: parent; name: btn.icon; size: 22; color: btn.ink }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
        ToolTip.visible: ma.containsMouse && btn.tip !== ""
        ToolTip.delay: 500
        ToolTip.text: btn.tip
    }
}
