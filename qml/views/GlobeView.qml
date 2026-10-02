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
    readonly property bool compact: Settings.placesPanelCompact && !narrow
    property string placeSort: "recent"
    // list rows: names resolved once per reload, then filtered and sorted
    property var _rowsAll: []
    function _buildRows() {
        var out = []
        for (var i = 0; i < locations.length; i++) {
            var l = locations[i]
            var info = globe.ready ? globe.placeInfo(l.lat, l.lon) : ({})
            // remote spots: name the nearest town within a few hundred km
            if (!info.name && globe.ready) info = globe.placeInfo(l.lat, l.lon, 600)
            var coords = Math.abs(l.lat).toFixed(2) + "° " + (l.lat >= 0 ? "N" : "S") + ", "
                       + Math.abs(l.lon).toFixed(2) + "° " + (l.lon >= 0 ? "E" : "W")
            var parts = info.name ? info.name.split(", ") : []
            var near = info.km > 25
            out.push({ loc: l,
                       title: parts.length ? (near ? _t("place_near").arg(parts[0]) : parts[0]) : coords,
                       sub: parts.length ? parts.slice(1).join(", ") : "",
                       key: ((info.name || "") + " " + coords).toLowerCase() })
        }
        _rowsAll = out
    }
    onLocationsChanged: _buildRows()
    Connections { target: globe; function onReadyChanged() { root._buildRows() } }
    readonly property var placeRows: {
        var q = placeFilter.text.trim().toLowerCase()
        var rows = q.length ? _rowsAll.filter(r => r.key.indexOf(q) >= 0) : _rowsAll.slice()
        if (placeSort === "count") rows.sort((a, b) => b.loc.count - a.loc.count)
        else if (placeSort === "name") rows.sort((a, b) => a.title.localeCompare(b.title))
        else rows.sort((a, b) => (b.loc.creation_date || 0) - (a.loc.creation_date || 0))
        return rows
    }
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
        function onLibraryChanged() { if (root._loaded) root._reload() }
    }

    function _t(key) { return I18n.t(Settings.language, key) }

    // Offline place label: "Lyon, France", or "Near Manaus, Brazil" when the
    // closest town is far away; coordinates as a last resort.
    function placeLabel(lat, lon) {
        var info = globe.ready ? globe.placeInfo(lat, lon) : ({})
        if (!info.name && globe.ready) info = globe.placeInfo(lat, lon, 600)
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
        activePlace = { lat: info.lat, lon: info.lon, count: info.count, places: members, cluster: cluster,
                        // the photo the pin shows, so the morph starts from it
                        thumb: (info.lead >= 0 && root.locations[info.lead] ? root.locations[info.lead].thumb : "")
                               || (members.length > 0 ? members[0].thumb : "") }
    }

    function selectLocation(loc) {
        activePlace = { lat: loc.lat, lon: loc.lon, count: loc.count, places: [loc], cluster: -1, thumb: loc.thumb || "" }
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
    readonly property color _labelHalo: Qt.rgba(0.01, 0.015, 0.035, 0.97)

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
                // soft, cool halftone: brighter where you look, fading into the
                // accent towards the limb, so white labels keep the contrast
                landColor: Qt.rgba(0.80, 0.85, 0.95, 0.58)
                landEdgeColor: Qt.rgba(0.35 + root._accent.r * 0.35, 0.38 + root._accent.g * 0.35, 0.50 + root._accent.b * 0.35, 0.20)
                coastColor: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.80)
                borderColor: Qt.rgba(1, 1, 1, 0.82)
                stateColor: Qt.rgba(1, 1, 1, 0.36)
                cityColor: "white"
                cityHaloColor: Qt.rgba(0.02, 0.03, 0.06, 0.85)
                casingColor: Qt.rgba(0.015, 0.02, 0.04, 0.92)
                pinSize: Qt.size(56, 70)

                onPinClicked: (cluster) => root.selectCluster(cluster)
                onGlobeClicked: (lat, lon) => popup.close()
            }

            // ── place labels (pooled; positions come from the engine) ───────
            // One soft dark glow over the whole layer (a single effect pass)
            // lifts the text off the halftone without per-label effects.
            Item {
                anchors.fill: globe
                layer.enabled: globe.ready
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.95)
                    shadowBlur: 0.35
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    shadowScale: 1.02
                }
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

            // ── photo pins (PhotoPin, shared with the 2D map) ───────────────
            Item {
                id: pinLayer
                anchors.fill: globe
                Repeater {
                    model: globe.pins
                    delegate: PhotoPin {
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

                        hot: globe.hoveredCluster === cluster
                        active: root.activePlace !== null && root.activePlace.cluster === cluster
                        stacked: members > 1 || count > 1
                        accent: root._accent
                        badgeBorder: root._space
                        photo: pin.thumb || ""
                        photos: count

                        // while open, the pin *is* the card (it morphed into it)
                        visible: shown && popacity > 0.02 && !active
                        opacity: popacity
                        x: px - width / 2
                        y: py - height
                        z: depth + (hot || active ? 2 : 0)
                        scale: (hot || active ? 1.14 : 1.0) * (0.80 + 0.20 * depth)
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    }
                }
            }

            // ── place card follows its place across the globe ───────────────
            PlacePopup {
                id: popup
                anchors.fill: globe
                z: 50
                place: root.activePlace
                pinThumb: root.activePlace && root.activePlace.thumb ? root.activePlace.thumb : ""
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
                onOpenItems: (items, i) => root.openViewer(items[i], items)
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

        // ── Places panel: full list, or a compact rail of photos ─────────────
        Rectangle {
            id: panel
            visible: root.panelShown
            Layout.fillHeight: true
            Layout.preferredWidth: root.compact ? 84 : (root.narrow ? 300 : 340)
            Behavior on Layout.preferredWidth { NumberAnimation { duration: ThemeManager.durMed; easing.type: Easing.OutCubic } }
            color: ThemeManager.surfaceContainer
            radius: 20
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.compact ? 10 : 16
                anchors.topMargin: 14
                spacing: 12

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label {
                        visible: !root.compact
                        text: root._t("places")
                        font.pixelSize: 20
                        font.weight: Font.Medium
                        color: ThemeManager.onSurface
                        Layout.leftMargin: 6
                    }
                    Rectangle {
                        visible: !root.compact && root.locations.length > 0
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: cntLbl.implicitWidth + 14
                        radius: 11
                        color: ThemeManager.surfaceContainerHighest
                        Label { id: cntLbl; anchors.centerIn: parent; text: root.locations.length; font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                    }
                    Item { Layout.fillWidth: true; visible: !root.compact }
                    RoundButton {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 44; Layout.preferredHeight: 44
                        flat: true
                        contentItem: MaterialSymbol {
                            name: root.compact ? "left_panel_open" : "right_panel_close"
                            size: 22
                            color: ThemeManager.onSurfaceVariant
                        }
                        background: Rectangle { radius: 22; color: parent.hovered ? Qt.alpha(ThemeManager.onSurface, 0.08) : "transparent" }
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: root.compact ? root._t("panel_expand") : root._t("panel_collapse")
                        onClicked: Settings.placesPanelCompact = !Settings.placesPanelCompact
                    }
                }

                // search + sort (full mode)
                M3TextField {
                    id: placeFilter
                    visible: !root.compact && root.locations.length > 6
                    Layout.fillWidth: true
                    placeholderText: root._t("places_filter")
                    font.pixelSize: 14
                }
                Row {
                    visible: !root.compact && root.locations.length > 1
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{ k: "recent", t: root._t("sort_recent") }, { k: "count", t: root._t("sort_most") }, { k: "name", t: root._t("sort_az") }]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.placeSort === modelData.k
                            height: 32; radius: 8
                            width: chipTxt.implicitWidth + (on ? 40 : 24)
                            color: on ? ThemeManager.secondaryContainer : "transparent"
                            border.width: on ? 0 : 1
                            border.color: ThemeManager.outlineVariant
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol { visible: parent.parent.on; name: "check"; size: 16; color: ThemeManager.onSecondaryContainer; anchors.verticalCenter: parent.verticalCenter }
                                Label {
                                    id: chipTxt
                                    text: modelData.t
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: parent.parent.on ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.placeSort = modelData.k }
                        }
                    }
                }

                ColumnLayout {
                    visible: root._loaded && root.locations.length === 0 && !root.compact
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
                    spacing: 8
                    Repeater {
                        model: 7
                        Skeleton { width: parent.width; height: root.compact ? 56 : 76; radius: root.compact ? 28 : 16 }
                    }
                }

                ListView {
                    id: placeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.placeRows
                    clip: true
                    spacing: root.compact ? 10 : 4
                    visible: root.locations.length > 0
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: root.compact ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

                    delegate: Item {
                        id: row
                        required property var modelData
                        readonly property var loc: modelData.loc
                        readonly property bool selected: root.activePlace !== null
                            && Math.abs(root.activePlace.lat - loc.lat) < 1e-6
                            && Math.abs(root.activePlace.lon - loc.lon) < 1e-6
                        width: placeList.width
                        height: root.compact ? 56 : 76

                        Rectangle {
                            anchors.fill: parent
                            visible: !root.compact
                            radius: 16
                            color: row.selected ? ThemeManager.secondaryContainer
                                 : hoverArea.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: ThemeManager.durShort } }
                        }
                        // selection bar
                        Rectangle {
                            visible: row.selected && !root.compact
                            width: 4; height: 36; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: 2
                            color: ThemeManager.primary
                        }

                        // thumbnail (round in the rail, rounded square in the list)
                        Item {
                            id: thumbBox
                            width: root.compact ? 52 : 60
                            height: width
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.compact ? (parent.width - width) / 2 : 10
                            Rectangle { id: tmask; anchors.fill: parent; radius: root.compact ? width / 2 : 14; visible: false; layer.enabled: true }
                            Skeleton { anchors.fill: parent; radius: tmask.radius; visible: tImg.status !== Image.Ready; active: visible }
                            Image {
                                id: tImg
                                anchors.fill: parent
                                source: row.loc.thumb || ""
                                sourceSize: Qt.size(128, 128)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: false
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: tImg
                                visible: tImg.status === Image.Ready
                                maskEnabled: true
                                maskSource: tmask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: tmask.radius
                                color: "transparent"
                                border.width: row.selected ? 3 : 0
                                border.color: ThemeManager.primary
                            }
                            // count badge in the rail
                            Rectangle {
                                visible: root.compact && row.loc.count > 1
                                anchors { right: parent.right; top: parent.top; rightMargin: -4; topMargin: -4 }
                                height: 18; radius: 9
                                width: Math.max(18, railCnt.implicitWidth + 8)
                                color: ThemeManager.primary
                                border.width: 2; border.color: ThemeManager.surfaceContainer
                                Label { id: railCnt; anchors.centerIn: parent; text: row.loc.count; font.pixelSize: 10; font.weight: Font.Bold; color: ThemeManager.onPrimary }
                            }
                        }

                        ColumnLayout {
                            visible: !root.compact
                            anchors { left: thumbBox.right; leftMargin: 14; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 3
                            Label {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                font.weight: Font.DemiBold; font.pixelSize: 15
                                color: row.selected ? ThemeManager.onSecondaryContainer : ThemeManager.onSurface
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: row.modelData.sub
                                font.pixelSize: 12
                                color: row.selected ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: 6
                                Rectangle {
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: metaCnt.implicitWidth + 14
                                    radius: 10
                                    color: row.selected ? Qt.alpha(ThemeManager.onSecondaryContainer, 0.12) : ThemeManager.surfaceContainerHighest
                                    Label {
                                        id: metaCnt
                                        anchors.centerIn: parent
                                        text: row.loc.count + " " + (row.loc.count === 1 ? root._t("photo_one") : root._t("photo_many"))
                                        font.pixelSize: 11; font.weight: Font.Medium
                                        color: row.selected ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                                    }
                                }
                                Label {
                                    visible: !!row.loc.creation_date
                                    text: row.loc.creation_date ? Qt.formatDateTime(new Date(row.loc.creation_date * 1000), "d MMM yyyy") : ""
                                    font.pixelSize: 11
                                    color: row.selected ? ThemeManager.onSecondaryContainer : ThemeManager.onSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: hoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectLocation(row.loc)
                            onDoubleClicked: root.openPlace({ places: [row.loc] })
                        }
                        ToolTip.visible: root.compact && hoverArea.containsMouse
                        ToolTip.delay: 300
                        ToolTip.text: row.modelData.title + (row.modelData.sub ? " · " + row.modelData.sub : "")
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
