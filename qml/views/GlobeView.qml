import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"
import "../I18n.js" as I18n

Item {
    id: root
    property var    locations:    []
    property var    activePin:    null
    property string activePinAddr: ""
    property point  _pinScreenPos: Qt.point(0, 0)

    signal openViewer(var data)

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

    function fetchAddress(lat, lon) {
        activePinAddr = ""
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://nominatim.openstreetmap.org/reverse?format=json&lat="
                 + lat + "&lon=" + lon + "&zoom=18&addressdetails=1")
        xhr.setRequestHeader("User-Agent", "KaderGallery/1.0")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var d = JSON.parse(xhr.responseText)
                        var a = d.address || {}
                        var parts = []
                        if (a.road) parts.push(a.road)
                        var locality = a.city_district || a.suburb || a.town || a.city || a.county || ""
                        if (locality) parts.push(locality)
                        activePinAddr = parts.length > 0 ? parts.join(", ") : (d.display_name || "")
                    } catch(e) { activePinAddr = lat.toFixed(4) + "°, " + lon.toFixed(4) + "°" }
                } else {
                    activePinAddr = lat.toFixed(4) + "°, " + lon.toFixed(4) + "°"
                }
            }
        }
        xhr.send()
    }

    Connections {
        target: FileScanner
        function onScanFinished() { if (root._loaded) root.locations = DB.getGeotaggedLocations() }
    }

    // ── Globe state — direct port of cobe's (https://github.com/shuding/cobe)
    // phi/theta/scale/offset model. The globe itself is not a 3D mesh; it's
    // rendered entirely by shaders/globe.frag, a fullscreen fragment shader
    // that raymarches a sphere and procedurally places a Fibonacci-lattice
    // dot field on it — exactly how cobe renders. ─────────────────────────
    readonly property real globeR: 0.8
    readonly property real markerElevation: 0.05
    property real phi: 0.0
    property real theta: 0.35
    property real zoomScale: 1.0
    property vector2d panOffset: Qt.vector2d(0, 0)
    property bool autoRotate: true
    property bool dragging: false
    property real _lastMouseX: 0
    property real _lastMouseY: 0
    property real _velPhi: 0
    property real _velTheta: 0
    property string debugText: ""
    property var  markerPositions: []   // [{x, y, loc}]

    function latLonTo3D(lat, lon) {
        var latRad = lat * Math.PI / 180
        var lonRad = lon * Math.PI / 180 - Math.PI
        var cosLat = Math.cos(latRad)
        return [-cosLat * Math.cos(lonRad), Math.sin(latRad), cosLat * Math.sin(lonRad)]
    }

    // Same rotation + screen-space projection cobe's own JS side uses to
    // place markers, kept in lockstep with the phi/theta/scale/offset the
    // fragment shader uses to render the dot field.
    function applyRotation(p) {
        var cx = Math.cos(root.theta)
        var cy = Math.cos(root.phi)
        var sx = Math.sin(root.theta)
        var sy = Math.sin(root.phi)

        var w = Math.max(1, globeArea.width)
        var h = Math.max(1, globeArea.height)
        var aspect = w / h

        var rx = cy * p[0] + sy * p[2]
        var ry = sy * sx * p[0] + cx * p[1] - cy * sx * p[2]
        var rz = -sy * cx * p[0] + sx * p[1] + cy * cx * p[2]

        return {
            x: ((rx / aspect) * root.zoomScale + root.panOffset.x * root.zoomScale / w + 1) / 2 * w,
            y: (-ry * root.zoomScale + root.panOffset.y * root.zoomScale / h + 1) / 2 * h,
            // Strict front-hemisphere-only: cobe's own lenient rule (rz>=0 OR far from
            // center) is tuned for its tiny cosmetic dot markers wrapping smoothly
            // around the horizon — for our large clickable photo badges it let markers
            // dangle disconnected from the visible globe when barely on the far side.
            visible: rz >= 0,
            rz: rz // TEMP debug field, remove with the debug readout
        }
    }

    function project(lat, lon) {
        var pos3D = latLonTo3D(lat, lon)
        var r = root.globeR + root.markerElevation
        return root.applyRotation([pos3D[0] * r, pos3D[1] * r, pos3D[2] * r])
    }

    function _updateMarkers() {
        if (locations.length === 0) {
            if (markerPositions.length !== 0) markerPositions = []
            return
        }
        var out = []
        for (var i = 0; i < locations.length; i++) {
            var loc = locations[i]
            var p = root.project(loc.lat, loc.lon)
            if (i === 0) {
                root.debugText = "lat=" + loc.lat.toFixed(2) + " lon=" + loc.lon.toFixed(2) +
                    " phi=" + root.phi.toFixed(3) + " theta=" + root.theta.toFixed(3) +
                    " zoom=" + root.zoomScale.toFixed(2) +
                    " w=" + Math.round(Math.max(1, globeArea.width)) + " h=" + Math.round(Math.max(1, globeArea.height)) +
                    " x=" + p.x.toFixed(1) + " y=" + p.y.toFixed(1) + " vis=" + p.visible + " rz=" + p.rz.toFixed(3)
            }
            if (!p.visible) continue
            out.push({ x: p.x, y: p.y, loc: loc })
        }
        markerPositions = out
        if (root.activePin) root._updatePinPopupPos()
    }

    function _updatePinPopupPos() {
        if (!activePin) return
        var p = root.project(activePin.lat, activePin.lon)
        _pinScreenPos = Qt.point(p.x, p.y)
    }

    // Drive idle auto-rotation / drag inertia and keep marker overlay
    // positions in sync every frame, mirroring cobe's own rAF render loop.
    Timer {
        interval: 16
        running: root.visible
        repeat: true
        onTriggered: {
            if (!root.dragging) {
                if (Math.abs(root._velPhi) > 0.0001 || Math.abs(root._velTheta) > 0.0001) {
                    root.phi += root._velPhi
                    // No clamp: rotate() is plain sin/cos, well-defined for any theta —
                    // cobe's own drag handler doesn't clamp either, so orbit is free
                    // past the poles instead of hitting an artificial wall there.
                    root.theta += root._velTheta
                    root._velPhi *= 0.95
                    root._velTheta *= 0.95
                } else if (root.autoRotate) {
                    root.phi += 0.005
                }
            }
            root._updateMarkers()
        }
    }

    // Solved from applyRotation: to bring (lat,lon) to dead-center (rx=0, ry=0,
    // rz=max), phi must be pi/2 - lonRad, not just -lonRad — the missing pi/2
    // term was why focused pins landed near the rim instead of centered.
    function focusLocation(lat, lon) {
        var lonRad = lon * Math.PI / 180 - Math.PI
        root.phi = Math.PI / 2 - lonRad
        root.theta = Math.max(-1.55, Math.min(1.55, lat * Math.PI / 180))
        root.zoomScale = Math.max(root.zoomScale, 1.6)
        root._velPhi = 0
        root._velTheta = 0
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ── Globe canvas ──────────────────────────────────────────────
        Item {
            id: globeCanvasRoot
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: ThemeManager.surfaceContainerLow
            }

            Item {
                id: globeContentLayer
                anchors.fill: parent
                clip: true

                Item {
                    id: globeArea
                    anchors.fill: parent

                    // TEMP debug readout — remove once marker placement is confirmed fixed.
                    Text {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 8
                        z: 999
                        text: root.debugText
                        color: "red"
                        font.pixelSize: 16
                        font.bold: true
                        style: Text.Outline
                        styleColor: "white"
                    }

                    // Equirectangular land/ocean mask sampled per-fragment by the globe
                    // shader — cobe's own bundled world texture (src/texture.png), not a
                    // hand-approximated polygon fill (which rendered as an unrecognizable
                    // blob at only ~15-30 points per continent).
                    Image {
                        id: landMaskImage
                        source: "qrc:/Kader/assets/globe-world-mask.png"
                        width: 256
                        height: 128
                        smooth: true
                        visible: true
                    }

                    ShaderEffectSource {
                        id: landMaskSource
                        sourceItem: landMaskImage
                        hideSource: true
                        live: false
                        wrapMode: ShaderEffectSource.ClampToEdge
                    }

                    ShaderEffect {
                        id: globeShader
                        anchors.fill: parent

                        property vector2d uResolution: Qt.vector2d(width, height)
                        property vector2d offset: root.panOffset
                        property vector2d rotation: Qt.vector2d(root.phi, root.theta)
                        property real dots: 16000
                        property real scale: root.zoomScale
                        // cobe's own default showcase config (page.tsx): baseColor/glowColor
                        // both pure white, dark: 0 — not theme-tinted.
                        property vector3d baseColor: Qt.vector3d(1.0, 1.0, 1.0)
                        property vector3d glowColor: Qt.vector3d(1.0, 1.0, 1.0)
                        property vector4d renderParams: Qt.vector4d(6.0, 1.2, 0.0, 1.0) // brightness, diffuse, dark, opacity
                        property real mapBaseBrightness: 0.0
                        property variant uTexture: landMaskSource

                        fragmentShader: "qrc:/shaders/globe.frag.qsb"
                    }

                    // ── Drag-to-orbit / scroll-to-zoom ──────────────────
                    // Direct port of cobe's own pointer handling
                    // (deltaX/300 → phi, deltaY/300 → theta), so the feel
                    // matches the reference implementation exactly.
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onPressed: (mouse) => {
                            root.dragging = true
                            root._velPhi = 0
                            root._velTheta = 0
                            root._lastMouseX = mouse.x
                            root._lastMouseY = mouse.y
                        }
                        onPositionChanged: (mouse) => {
                            if (!root.dragging) return
                            var dx = mouse.x - root._lastMouseX
                            var dy = mouse.y - root._lastMouseY
                            root._velPhi = dx / 300
                            // Negated: dragging down should bring the far side of the
                            // globe down toward the viewer (content follows the pointer),
                            // not the reverse.
                            root._velTheta = -dy / 300
                            root.phi += root._velPhi
                            root.theta += root._velTheta
                            root._lastMouseX = mouse.x
                            root._lastMouseY = mouse.y
                        }
                        onReleased: root.dragging = false
                        onWheel: (wheel) => {
                            var factor = Math.exp(wheel.angleDelta.y * 0.0012)
                            root.zoomScale = Math.max(0.6, Math.min(3.5, root.zoomScale * factor))
                        }
                    }

                    // ── Pause/resume auto-rotation ──────────────────────
                    Rectangle {
                        id: rotateToggle
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 14
                        z: 70
                        width: 36; height: 36; radius: 18
                        color: Qt.rgba(0.08, 0.08, 0.10, 0.85)
                        M3Icon {
                            anchors.centerIn: parent
                            name: root.autoRotate ? "pause" : "play"
                            size: 18
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.autoRotate = !root.autoRotate
                                root._velPhi = 0
                                root._velTheta = 0
                            }
                        }
                    }

                    // ── Location pins (2D overlay projected from the globe) ─
                    Repeater {
                        model: root.markerPositions
                        delegate: Item {
                            required property var modelData
                            x: modelData.x - width / 2
                            y: modelData.y - height
                            z: 20
                            width: pinRow.width + 16
                            height: 32
                            // Inverse to zoom: bigger when zoomed out (globe small, need
                            // legibility), smaller when zoomed in (already close-up).
                            transformOrigin: Item.Bottom
                            scale: Math.max(0.6, Math.min(1.6, 1 / root.zoomScale))

                            Rectangle {
                                id: pinBody
                                anchors.fill: parent
                                radius: 16
                                color: Qt.rgba(0.08, 0.08, 0.10, 0.92)

                                Row {
                                    id: pinRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    leftPadding: 5
                                    rightPadding: 8

                                    Rectangle {
                                        width: 22; height: 22; radius: 7
                                        color: Qt.rgba(1, 1, 1, 0.12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: modelData.loc.thumb || ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                    }
                                    Label {
                                        text: modelData.loc.count
                                        color: "white"
                                        font.pixelSize: ThemeManager.fontLabelM
                                        font.weight: Font.SemiBold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: pinBody
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activePin = modelData.loc
                                    root._updatePinPopupPos()
                                    root.fetchAddress(modelData.loc.lat, modelData.loc.lon)
                                }
                            }
                        }
                    }

                    // ── Pin popup card ──────────────────────────────────
                    Rectangle {
                        id: pinPopup
                        visible: root.activePin !== null
                        z: 60
                        width: 210
                        height: 220
                        radius: 14
                        color: Qt.rgba(0.07, 0.07, 0.09, 0.95)

                        x: Math.min(Math.max(8, root._pinScreenPos.x - width / 2),
                                    parent.width - width - 8)
                        y: Math.max(8, root._pinScreenPos.y - height - 40)

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowBlur: 0.6
                            shadowColor: Qt.rgba(0, 0, 0, 0.5)
                            shadowVerticalOffset: 4
                        }

                        Column {
                            id: popupCol
                            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
                            spacing: 8

                            Rectangle {
                                width: parent.width; height: 110; radius: 8; clip: true
                                color: Qt.rgba(1, 1, 1, 0.06)
                                Image {
                                    anchors.fill: parent
                                    source: root.activePin ? (root.activePin.thumb || "") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            Label {
                                width: parent.width
                                text: root.activePinAddr !== ""
                                      ? root.activePinAddr
                                      : (root.activePin
                                         ? root.activePin.lat.toFixed(4) + "°,  " + root.activePin.lon.toFixed(4) + "°"
                                         : "")
                                color: "white"; font.pixelSize: ThemeManager.fontLabelM
                                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                            }

                            Row {
                                width: parent.width; spacing: 8

                                Label {
                                    text: root.activePin
                                          ? root.activePin.count + (root.activePin.count === 1 ? " photo" : " photos")
                                          : ""
                                    color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - openBtn.width - 8
                                }

                                Rectangle {
                                    id: openBtn
                                    width: 60; height: 28; radius: 14
                                    color: ThemeManager.primary
                                    Label {
                                        anchors.centerIn: parent
                                        text: I18n.t(Settings.language, "open_action"); color: ThemeManager.onPrimary
                                        font.pixelSize: 12; font.weight: Font.Medium
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (root.activePin) root.openViewer(root.activePin); root.activePin = null }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 7
                            width: 22; height: 22; radius: 11; color: Qt.rgba(1, 1, 1, 0.13)
                            Label { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activePin = null }
                        }
                    }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    maskSource: globeRoundMask
                }
            }

            Rectangle {
                id: globeRoundMask
                anchors.fill: globeContentLayer
                radius: 16
                color: "white"
                visible: false
                layer.enabled: true
            }
        }

        // ── Right panel: places list ────────────────────────────────────
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
                                root.focusLocation(modelData.lat, modelData.lon)
                                // TEMP: openViewer disabled so the globe pin landing is
                                // visible for verification. Re-enable once confirmed.
                                // if (modelData.file_path) root.openViewer(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
