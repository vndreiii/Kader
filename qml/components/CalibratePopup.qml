import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import ".."
import "../I18n.js" as I18n

// Calibrate face grouping by answering "is this <person>?" on a deck of
// cards: drag a card right for yes, left for no. The deck holds the faces
// the grouping is least sure about; every answer pins or excludes that face
// and is kept as a labelled example, from which the grouping threshold is
// re-learnt when the round ends — the more rounds, the better it gets.
// The old threshold slider stays available under "Fine-tune by hand".
Popup {
    id: root
    function _t(k) { return I18n.t(Settings.language, k) }
    property int personId: -1          // -1: a mix of everyone
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent.width - 48)
    height: Math.min(720, parent.height - 48)
    modal: true
    padding: 24
    focus: true

    property var queue: []
    property int index: 0
    property int answered: 0
    property bool fineTune: false
    readonly property var card: index < queue.length ? queue[index] : null
    readonly property bool finished: queue.length > 0 && index >= queue.length
    readonly property string who: card && card.personName ? card.personName : root._t("review_this_person")

    function load() {
        queue = Analyzer.reviewQueue(root.personId, 24)
        index = 0
    }
    onOpened: { answered = 0; fineTune = false; load(); value = Analyzer.threshold; preview = Analyzer.previewThreshold(value) }
    onClosed: if (answered > 0) { Analyzer.finishReview(); answered = 0 }

    function answer(same) {
        if (!card) return
        Analyzer.answerReview(card.faceId, card.personId, same, card.similarity)
        answered++
        index++
    }

    // ── fine-tune (the previous slider) ─────────────────────────────────
    property real value: Analyzer.threshold
    property var preview: ({})
    Timer { id: previewTimer; interval: 120; onTriggered: root.preview = Analyzer.previewThreshold(root.value) }

    background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }

    contentItem: Item {
        focus: true
        Keys.onLeftPressed: top.fling(false)
        Keys.onRightPressed: top.fling(true)

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: root.finished || root.queue.length === 0 ? root._t("calibrate_title")
                                                                   : root._t("review_title").arg(root.who)
                    font.pixelSize: 24
                    color: ThemeManager.onSurface
                    elide: Text.ElideRight
                }
                Label {
                    visible: root.card !== null
                    text: root._t("review_progress").arg(root.index + 1).arg(root.queue.length)
                    color: ThemeManager.onSurfaceVariant
                    font.pixelSize: 13
                }
            }
            Label {
                Layout.fillWidth: true
                visible: !root.fineTune
                text: root.queue.length === 0 ? root._t("review_empty")
                    : root.finished ? root._t("review_done").arg(root.answered)
                    : root._t("review_hint")
                wrapMode: Text.WordWrap
                color: ThemeManager.onSurfaceVariant
            }

            // ── the deck ────────────────────────────────────────────────
            Item {
                id: deck
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.fineTune && root.card !== null
                clip: false

                // the next card, waiting underneath
                FaceCard {
                    width: deck.width; height: deck.height
                    data_: root.index + 1 < root.queue.length ? root.queue[root.index + 1] : null
                    visible: data_ !== null
                    scale: 0.94 + 0.06 * Math.min(1, Math.abs(top.x) / (deck.width * 0.3))
                    opacity: 0.7
                }
                FaceCard {
                    id: top
                    width: deck.width; height: deck.height
                    data_: root.card
                    property bool flying: false
                    rotation: x / deck.width * 14
                    // drag progress: -1 (no) … 1 (yes)
                    readonly property real lean: Math.max(-1, Math.min(1, x / (deck.width * 0.3)))
                    yesOpacity: Math.max(0, lean)
                    noOpacity: Math.max(0, -lean)

                    Behavior on x { enabled: !drag.active && !top.flying; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    Behavior on y { enabled: !drag.active && !top.flying; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

                    function fling(same) {
                        if (!root.card || flying) return
                        flying = true
                        flyOut.to = same ? deck.width * 1.6 : -deck.width * 1.6
                        flyOut.same = same
                        flyOut.start()
                    }
                    NumberAnimation {
                        id: flyOut
                        property bool same: false
                        target: top; property: "x"; duration: 220; easing.type: Easing.InCubic
                        onFinished: {
                            root.answer(same)
                            top.flying = false
                            top.x = 0; top.y = 0
                        }
                    }
                    DragHandler {
                        id: drag
                        enabled: !top.flying
                        cursorShape: Qt.ClosedHandCursor
                        onActiveChanged: {
                            if (active) return
                            if (top.x > deck.width * 0.3) top.fling(true)
                            else if (top.x < -deck.width * 0.3) top.fling(false)
                            else { top.x = 0; top.y = 0 }
                        }
                    }
                    HoverHandler { cursorShape: Qt.OpenHandCursor }
                }
            }

            // ── empty / finished ────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.fineTune && root.card === null
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 18
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        name: root.finished ? "task_alt" : "face"
                        size: 64
                        color: ThemeManager.primary
                    }
                    M3Button {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.finished
                        highlighted: true
                        text: root._t("review_more")
                        onClicked: { Analyzer.finishReview(); root.answered = 0; root.load() }
                    }
                }
            }

            // ── fine-tune by hand ───────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.fineTune
                spacing: 16
                Label {
                    Layout.fillWidth: true
                    text: root._t("calibrate_body")
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onSurfaceVariant
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: root._t("calibrate_looser"); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                    M3Slider {
                        id: slider
                        Layout.fillWidth: true
                        from: 0.25; to: 0.6; stepSize: 0.01
                        value: root.value
                        onMoved: { root.value = value; previewTimer.restart() }
                    }
                    Label { text: root._t("calibrate_stricter"); color: ThemeManager.onSurfaceVariant; font.pixelSize: 13 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: 16
                    color: ThemeManager.surfaceContainerHighest
                    Label {
                        anchors.centerIn: parent
                        text: root._t("calibrate_preview").arg(root.preview.groups || 0).arg(root.preview.grouped || 0).arg(root.preview.faces || 0)
                        color: ThemeManager.onSurface
                        font.pixelSize: 15
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    M3Button { text: root._t("reset"); onClicked: { root.value = 0.38; slider.value = 0.38; previewTimer.restart() } }
                    Item { Layout.fillWidth: true }
                    M3Button { highlighted: true; text: root._t("apply"); onClicked: { Analyzer.setThreshold(root.value); root.close() } }
                }
                Item { Layout.fillHeight: true }
            }

            RowLayout {
                Layout.fillWidth: true
                M3Button {
                    text: root.fineTune ? root._t("calibrate_title") : root._t("review_fine_tune")
                    onClicked: {
                        root.fineTune = !root.fineTune
                        if (root.fineTune) { root.value = Analyzer.threshold; slider.value = root.value; previewTimer.restart() }
                    }
                }
                Item { Layout.fillWidth: true }
                M3Button { text: root._t("review_close"); onClicked: root.close() }
            }
        }
    }

    // One card: the photo, the face in question, and who it's being compared to.
    component FaceCard: Item {
        id: fc
        property var data_: null
        property real yesOpacity: 0
        property real noOpacity: 0

        Rectangle { id: cardMask; anchors.fill: parent; radius: 28; visible: false; layer.enabled: true }
        Item {
            id: cardBody
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; color: ThemeManager.surfaceContainerHighest }
            Image {
                id: photo
                anchors.fill: parent
                source: fc.data_ ? fc.data_.thumb : ""
                sourceSize: Qt.size(768, 768)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {   // legibility gradient
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * 0.5
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.alpha("black", 0.75) }
                }
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: cardBody
            maskEnabled: true
            maskSource: cardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            shadowEnabled: true
            shadowOpacity: 0.35
            shadowBlur: 0.6
            shadowVerticalOffset: 6
        }

        // the face in question, large, bottom-left
        Rectangle {
            anchors { left: parent.left; bottom: parent.bottom; margins: 20 }
            width: 132; height: 132; radius: 66
            color: "white"
            FaceAvatar {
                anchors.fill: parent
                anchors.margins: 4
                faceId: fc.data_ ? fc.data_.faceId : -1
            }
        }
        // who it's compared with, top-left
        Rectangle {
            visible: fc.data_ !== null
            anchors { left: parent.left; top: parent.top; margins: 16 }
            height: 44
            width: whoRow.implicitWidth + 16
            radius: 22
            color: Qt.alpha("black", 0.55)
            Row {
                id: whoRow
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 8
                FaceAvatar {
                    width: 32; height: 32
                    faceId: fc.data_ && fc.data_.personCover !== undefined ? fc.data_.personCover : -1
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: fc.data_ && fc.data_.personName ? fc.data_.personName : I18n.t(Settings.language, "review_this_person")
                    color: "white"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    rightPadding: 6
                }
            }
        }

        // answer stamps, fading in with the drag
        Rectangle {
            anchors { right: parent.right; top: parent.top; margins: 22 }
            opacity: fc.yesOpacity
            rotation: 12
            radius: 14
            color: Qt.alpha(ThemeManager.primary, 0.9)
            width: yesLbl.implicitWidth + 28; height: 48
            Label { id: yesLbl; anchors.centerIn: parent; text: I18n.t(Settings.language, "review_yes"); color: ThemeManager.onPrimary; font.pixelSize: 18; font.weight: Font.Bold }
        }
        Rectangle {
            anchors { right: parent.right; top: parent.top; margins: 22 }
            opacity: fc.noOpacity
            rotation: -12
            radius: 14
            color: Qt.alpha(ThemeManager.error, 0.9)
            width: noLbl.implicitWidth + 28; height: 48
            Label { id: noLbl; anchors.centerIn: parent; text: I18n.t(Settings.language, "review_no"); color: ThemeManager.onError; font.pixelSize: 18; font.weight: Font.Bold }
        }
    }
}
