import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."
import "../I18n.js" as I18n

// Floating card for a place on the globe / map. Follows (anchorX, anchorY),
// flips below the anchor when there is no room above, and fades out when the
// anchor rotates behind the globe.
//
// `place`: { lat, lon, count, places: [location…], name } where each location
// is an entry of DB.getGeotaggedLocations().
Item {
    id: root
    property var    place: null
    property real   anchorX: 0
    property real   anchorY: 0
    property bool   anchorVisible: true
    property real   anchorGap: 58          // clearance for the pin bubble
    property string offlineName: ""         // instant name from the globe dataset

    signal openRequested(var place)
    signal closeRequested()

    readonly property bool shown: place !== null
    readonly property int placeCount: place && place.places ? place.places.length : 0
    readonly property var thumbs: {
        if (!place || !place.places) return []
        var out = []
        for (var i = 0; i < place.places.length && out.length < 3; i++)
            if (place.places[i].thumb) out.push(place.places[i].thumb)
        return out
    }

    // ── reverse geocoding (Nominatim), cached per rounded coordinate ────────
    property string address: ""
    property var _cache: ({})
    property var _xhr: null

    function _key(lat, lon) { return lat.toFixed(3) + "," + lon.toFixed(3) }

    onPlaceChanged: {
        address = ""
        if (!place) return
        var k = _key(place.lat, place.lon)
        if (_cache[k] !== undefined) { address = _cache[k]; return }
        if (_xhr) _xhr.abort()
        var xhr = new XMLHttpRequest()
        _xhr = xhr
        var lat = place.lat, lon = place.lon
        xhr.open("GET", "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat="
                 + lat + "&lon=" + lon + "&zoom=16&addressdetails=1")
        xhr.setRequestHeader("User-Agent", "Kader/" + Qt.application.version + " (photo gallery)")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (root._xhr === xhr) root._xhr = null
            var text = ""
            if (xhr.status === 200) {
                try {
                    var a = (JSON.parse(xhr.responseText).address) || {}
                    var parts = []
                    var street = a.road || a.pedestrian || a.neighbourhood || ""
                    var locality = a.city || a.town || a.village || a.suburb || a.city_district || a.county || ""
                    if (street) parts.push(street)
                    if (locality) parts.push(locality)
                    if (a.country && parts.length < 2) parts.push(a.country)
                    text = parts.join(", ")
                } catch (e) {}
            }
            root._cache[k] = text
            if (root.place && root._key(root.place.lat, root.place.lon) === k) root.address = text
        }
        xhr.send()
    }

    // ── placement ───────────────────────────────────────────────────────────
    readonly property real cardW: 272
    readonly property real cardH: card.implicitHeight
    readonly property bool below: anchorY - anchorGap - cardH < 8

    x: 0; y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: opacity > 0.01
    opacity: shown && anchorVisible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // `card` positions everything; `body` is the visible card with a round
    // bite taken out of its top-right corner where the close button sits.
    Item {
        id: card
        width: root.cardW
        implicitHeight: col.implicitHeight + 24
        height: implicitHeight
        x: Math.max(10, Math.min(root.width - width - 22, root.anchorX - width / 2))
        y: root.below ? Math.min(root.height - height - 10, root.anchorY + 14)
                      : Math.max(22, root.anchorY - root.anchorGap - height)
        scale: root.shown ? 1 : 0.94
        transformOrigin: root.below ? Item.Top : Item.Bottom
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

        readonly property real biteR: 21              // hole radius
        readonly property point biteC: Qt.point(width - 6, 6) // hole / button centre

        // shadow around the bitten shape
        Item {
            id: shadowed
            anchors.fill: parent
            layer.enabled: root.visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.8
                shadowColor: Qt.rgba(0, 0, 0, 0.55)
                shadowVerticalOffset: 6
            }

            Item {
                id: body
                // 12px margin so the pointer tail outside the card isn't clipped
                anchors.fill: parent
                anchors.margins: -12
                layer.enabled: root.visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskInverted: true
                    maskSource: biteMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Rectangle {
                    id: bg
                    anchors.fill: parent
                    anchors.margins: 12
                    radius: 18
                    color: Qt.rgba(0.075, 0.085, 0.115, 1)
                    border.color: Qt.rgba(1, 1, 1, 0.14)
                    border.width: 1
                }

                // pointer towards the pin
                Rectangle {
                    width: 14; height: 14
                    rotation: 45
                    color: bg.color
                    x: 12 + Math.max(16, Math.min(card.width - 30, root.anchorX - card.x - 7))
                    y: 12 + (root.below ? -7 : card.height - 7)
                }

                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 10

                    // Mosaic: one hero + up to two side thumbs
                    Item {
                        width: parent.width
                        height: 128
                        Rectangle {
                            id: hero
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: root.thumbs.length > 1 ? parent.width * 0.64 : parent.width
                            radius: 12; clip: true
                            color: Qt.rgba(1, 1, 1, 0.06)
                            Image {
                                anchors.fill: parent
                                source: root.thumbs.length > 0 ? root.thumbs[0] : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 360
                            }
                        }
                        Column {
                            visible: root.thumbs.length > 1
                            anchors { left: hero.right; leftMargin: 6; right: parent.right; top: parent.top; bottom: parent.bottom }
                            spacing: 6
                            Repeater {
                                model: root.thumbs.slice(1, 3)
                                Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    height: root.thumbs.length > 2 ? (128 - 6) / 2 : 128
                                    radius: 10; clip: true
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    Image {
                                        anchors.fill: parent
                                        source: parent.modelData
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 200
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 2
                        Label {
                            width: parent.width
                            text: root.offlineName !== "" ? root.offlineName
                                  : (root.place ? root.place.lat.toFixed(4) + "°, " + root.place.lon.toFixed(4) + "°" : "")
                            color: "white"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            width: parent.width
                            visible: text !== ""
                            text: root.address
                            color: Qt.rgba(1, 1, 1, 0.78)
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - openBtn.width - 8
                            color: Qt.rgba(1, 1, 1, 0.80)
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            text: {
                                if (!root.place) return ""
                                var n = root.place.count
                                var s = n + " " + (n === 1 ? I18n.t(Settings.language, "photo_one")
                                                           : I18n.t(Settings.language, "photo_many"))
                                if (root.placeCount > 1) s += " · " + root.placeCount + " " + I18n.t(Settings.language, "places_lower")
                                return s
                            }
                        }
                        Rectangle {
                            id: openBtn
                            width: openLbl.implicitWidth + 28; height: 34; radius: 17
                            color: openMa.pressed ? Qt.darker(ThemeManager.primary, 1.15) : ThemeManager.primary
                            Label {
                                id: openLbl
                                anchors.centerIn: parent
                                text: I18n.t(Settings.language, "open_action")
                                color: ThemeManager.onPrimary
                                font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: openMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openRequested(root.place)
                            }
                        }
                    }
                }
            }
        }

        // the bite: a circle at the corner, cut out of `body`
        Item {
            id: biteMask
            anchors.fill: parent
            anchors.margins: -12
            visible: false
            layer.enabled: true
            Rectangle {
                width: card.biteR * 2; height: width; radius: width / 2
                x: 12 + card.biteC.x - card.biteR
                y: 12 + card.biteC.y - card.biteR
            }
        }

        // close button sitting in the bite, half outside the card
        Rectangle {
            width: 30; height: 30; radius: 15
            x: card.biteC.x - width / 2
            y: card.biteC.y - height / 2
            color: closeMa.pressed ? Qt.rgba(0.20, 0.22, 0.28, 1)
                 : closeMa.containsMouse ? Qt.rgba(0.16, 0.18, 0.24, 1) : Qt.rgba(0.11, 0.12, 0.16, 1)
            border.color: Qt.rgba(1, 1, 1, closeMa.containsMouse ? 0.40 : 0.22)
            border.width: 1
            scale: closeMa.containsMouse ? 1.08 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
            MaterialSymbol { anchors.centerIn: parent; name: "close"; size: 17; color: "white" }
            MouseArea {
                id: closeMa
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
            ToolTip.visible: closeMa.containsMouse
            ToolTip.delay: 600
            ToolTip.text: I18n.t(Settings.language, "close")
        }
    }
}
