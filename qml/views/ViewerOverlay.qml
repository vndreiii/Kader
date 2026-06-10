import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import "../components"
import "../I18n.js" as I18n

Rectangle {
    id: root
    anchors.fill: parent
    color: "#F5000000"  // 96% opaque black — enough to hide sidebar/topbar
    z: 1000
    visible: active

    property bool active: false
    property var  mediaData: null
    property int  currentIndex: -1
    property var  allItems: []
    property bool infoPanelOpen: false
    property bool viewerOnlyMode: false
    property bool _isFullscreen: false
    property bool _videoFullscreen: false
    property bool _controlsVisible: true  // auto-hides in video fullscreen

    // ── Minimal video editing (trim + audio toggle + save-as-copy) ──────────
    property bool   _editMode:    false
    property real   _trimStartMs: 0
    property real   _trimEndMs:   0
    property bool   _keepAudio:   true
    property string _toast:       ""

    function _fmt(ms) {
        var s = Math.floor(ms / 1000)
        var m = Math.floor(s / 60); s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function _enterEdit() {
        _trimStartMs = 0
        _trimEndMs   = videoPlayer.duration
        _keepAudio   = true
        _editMode    = true
        videoPlayer.pause()
    }

    // True when the user is in cinema/video fullscreen — drives chrome visibility
    readonly property bool _vidFs: _videoFullscreen && _isVideo

    function toggleVideoFullscreen() {
        if (_videoFullscreen) {
            ApplicationWindow.window.showNormal()
            _videoFullscreen = false
            _controlsVisible = true
            controlsHideTimer.stop()
        } else {
            ApplicationWindow.window.showFullScreen()
            _videoFullscreen = true
            _controlsVisible = true
            controlsHideTimer.restart()
        }
    }

    // Auto-hide controls after 3 s of no mouse movement in video fullscreen
    Timer {
        id: controlsHideTimer
        interval: 3000
        onTriggered: root._controlsVisible = false
    }

    onActiveChanged: {
        if (!active) {
            videoPlayer.stop()
            videoPlayer.source = ""
            if (_videoFullscreen) { ApplicationWindow.window.showNormal(); _videoFullscreen = false }
            if (_isFullscreen)    { ApplicationWindow.window.showNormal(); _isFullscreen = false }
            controlsHideTimer.stop()
            if (viewerOnlyMode) Qt.quit()
        }
    }

    // ── Zoom / pan state ──────────────────────────────────────────────────
    property real _zoom: 1.0
    property real _panX: 0
    property real _panY: 0

    readonly property bool _isVideo: {
        var m = root.mediaData ? (root.mediaData.mime_type || "") : ""
        return m.indexOf("video/") === 0
    }
    readonly property bool _isGif: {
        var m = root.mediaData ? (root.mediaData.mime_type || "") : ""
        return m === "image/gif"
    }

    function resetZoom() { _zoom = 1.0; _panX = 0; _panY = 0 }
    onMediaDataChanged: {
        resetZoom()
        deleteConfirm.showing = false
        // Compute isVid directly — _isVideo binding may not be recomputed yet at this point
        var isVid = root.mediaData ? (root.mediaData.mime_type || "").indexOf("video/") === 0 : false
        videoPlayer.source = (isVid && root.mediaData) ? "file://" + root.mediaData.file_path : ""
    }

    focus: active
    Keys.onEscapePressed: {
        if (root._videoFullscreen) toggleVideoFullscreen()
        else root.active = false
    }
    Keys.onLeftPressed:   { if (!root._vidFs) navigatePrev() }
    Keys.onRightPressed:  { if (!root._vidFs) navigateNext() }

    // ── Navigation ────────────────────────────────────────────────────────
    function navigatePrev() {
        if (currentIndex > 0) {
            _transition(-1)
            currentIndex--
            mediaData = allItems[currentIndex]
        }
    }
    function navigateNext() {
        if (currentIndex < allItems.length - 1) {
            _transition(1)
            currentIndex++
            mediaData = allItems[currentIndex]
        }
    }

    // direction: -1 = going left (prev), 1 = going right (next)
    property int _dir: 0
    function _transition(dir) {
        resetZoom()
        _dir = dir
        outImg.source = (root._isVideo || root._isGif)
            ? (root.mediaData && root.mediaData.thumb ? root.mediaData.thumb : "")
            : mainImg.source
        outImg.opacity = 1.0
        outAnim.restart()
    }

    // ── Backdrop dismiss (only when not zoomed) ───────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: { if (root._zoom <= 1.0) root.active = false }
        onWheel: (wheel) => {
            if (wheel.angleDelta.y !== 0) {
                var factor = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15)
                root._zoom = Math.max(1.0, Math.min(8.0, root._zoom * factor))
                if (root._zoom <= 1.02) root.resetZoom()
                wheel.accepted = true
            }
            // Horizontal scroll navigates prev/next when not zoomed in
            if (wheel.angleDelta.x !== 0 && root._zoom <= 1.0 && !root._vidFs) {
                if (wheel.angleDelta.x > 0) root.navigateNext()
                else root.navigatePrev()
                wheel.accepted = true
            }
        }
    }

    // ── Image display area ────────────────────────────────────────────────
    Item {
        id: imgArea
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.topMargin:    root._vidFs ? 0 : 72
        anchors.leftMargin:   root._vidFs ? 0 : 72
        anchors.rightMargin:  root._vidFs ? 0 : 72
        anchors.bottomMargin: root._vidFs ? 0 : 80
        clip: true

        Behavior on anchors.topMargin    { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        Behavior on anchors.leftMargin   { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        Behavior on anchors.rightMargin  { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }

        // Mouse tracker for auto-hide + double-click-to-fullscreen in video fullscreen mode
        MouseArea {
            id: videoFsTracker
            anchors.fill: parent
            visible: root._isVideo
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            z: 10
            propagateComposedEvents: true
            onMouseXChanged: { root._controlsVisible = true; controlsHideTimer.restart() }
            onMouseYChanged: { root._controlsVisible = true; controlsHideTimer.restart() }
            cursorShape: (root._vidFs && !root._controlsVisible) ? Qt.BlankCursor : Qt.ArrowCursor
        }
        // Double-click toggles video fullscreen
        MouseArea {
            anchors.fill: parent
            visible: root._isVideo
            acceptedButtons: Qt.LeftButton
            z: 9
            propagateComposedEvents: true
            onDoubleClicked: root.toggleVideoFullscreen()
            onClicked: (m) => m.accepted = false
        }

        // Outgoing image — sits on top (z:5), fades out as crossfade over the incoming image
        Image {
            id: outImg
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            autoTransform: true
            opacity: 0
            z: 5

            NumberAnimation {
                id: outAnim
                target: outImg
                property: "opacity"
                from: 1.0; to: 0.0
                duration: 260
                easing.type: Easing.OutQuint
            }
        }

        // Main / incoming image with zoom + pan
        Image {
            id: mainImg
            anchors.centerIn: parent
            width:  Math.min(imgArea.width,  implicitWidth  > 0 ? implicitWidth  : imgArea.width)
            height: Math.min(imgArea.height, implicitHeight > 0 ? implicitHeight : imgArea.height)
            source: (!root._isVideo && !root._isGif && root.mediaData) ? "file://" + root.mediaData.file_path : ""
            visible: !root._isVideo && !root._isGif
            fillMode: Image.PreserveAspectFit
            autoTransform: true
            asynchronous: true

            scale: root._zoom
            transformOrigin: Item.Center
            transform: Translate { x: root._panX; y: root._panY }

            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
        }

        // Animated GIF viewer — loops silently, supports zoom + pan
        AnimatedImage {
            id: gifViewer
            anchors.centerIn: parent
            width:  Math.min(imgArea.width,  implicitWidth  > 0 ? implicitWidth  : imgArea.width)
            height: Math.min(imgArea.height, implicitHeight > 0 ? implicitHeight : imgArea.height)
            source: root._isGif && root.mediaData ? "file://" + root.mediaData.file_path : ""
            visible: root._isGif
            fillMode: Image.PreserveAspectFit
            playing: root._isGif
            asynchronous: true
            cache: false

            scale: root._zoom
            transformOrigin: Item.Center
            transform: Translate { x: root._panX; y: root._panY }

            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
        }

        // ── Video player (shown instead of image when _isVideo) ──────────
        MediaPlayer {
            id: videoPlayer
            videoOutput: videoOut
            audioOutput: audioOut
            loops: videoLoopBtn.looping ? MediaPlayer.Infinite : 1
            property bool hasError: false
            onErrorOccurred: (error, errorString) => { console.error("Video error:", errorString); hasError = true }
            onSourceChanged: { hasError = false }
            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)
                    play()
            }
        }

        AudioOutput {
            id: audioOut
            volume: 0.5
        }

        // Apply PulseAudio device preference when the setting is toggled
        Connections {
            target: Settings
            function onUsePulseAudioChanged() { audioOut.device = _pulseDevice() }
        }
        Component.onCompleted: {
            if (Settings.usePulseAudio) {
                var d = _pulseDevice()
                if (d) audioOut.device = d
            }
        }

        function _pulseDevice() {
            var devs = MediaDevices.audioOutputs
            if (!devs || !devs.length) return MediaDevices.defaultAudioOutput
            for (var i = 0; i < devs.length; i++)
                if (devs[i].description.toLowerCase().indexOf("pulse") >= 0) return devs[i]
            return MediaDevices.defaultAudioOutput
        }

        VideoOutput {
            id: videoOut
            anchors.fill: parent
            visible: true
            opacity: root._isVideo ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
            scale: root._zoom
            transformOrigin: Item.Center
            transform: Translate { x: root._panX; y: root._panY }
        }

        // Error overlay for videos that fail to load
        Rectangle {
            visible: root._isVideo && videoPlayer.hasError
            anchors.centerIn: parent
            width: errLbl.implicitWidth + 48; height: 56; radius: 12
            color: Qt.alpha("black", 0.65)
            Column {
                anchors.centerIn: parent; spacing: 4
                Label { id: errLbl; anchors.horizontalCenter: parent.horizontalCenter; text: "Failed to play video"; color: "white"; font.pixelSize: 14 }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Open externally"
                    color: Qt.alpha("white", 0.65); font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.mediaData) Qt.openUrlExternally("file://" + root.mediaData.file_path) }
                }
            }
        }

        // Video controls overlay — controls row (top) + scrubber (bottom)
        Rectangle {
            id: videoControls
            visible: root._isVideo
            z: 11
            opacity: root._vidFs ? (root._controlsVisible ? 1.0 : 0.0) : 1.0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: Math.min(Math.max(400, parent.width * 0.65), 640)
            height: 80
            radius: 20
            color: Qt.alpha("black", 0.70)

            Column {
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 14
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8

                // ── Controls row (TOP) ────────────────────────────────────
                Item {
                    width: parent.width
                    height: 28

                    Rectangle {
                        id: ppBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 14
                        color: Qt.alpha("white", ppMa.containsMouse ? 0.20 : 0.12)
                        Behavior on color { ColorAnimation { duration: 80 } }
                        M3Icon {
                            anchors.centerIn: parent
                            name: videoPlayer.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                            size: 16; color: "white"
                        }
                        MouseArea {
                            id: ppMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: videoPlayer.playbackState === MediaPlayer.PlayingState
                                       ? videoPlayer.pause() : videoPlayer.play()
                        }
                    }

                    Label {
                        anchors.left: ppBtn.right; anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            function fmt(ms) {
                                var s = Math.floor(ms / 1000)
                                var m = Math.floor(s / 60); s = s % 60
                                return m + ":" + (s < 10 ? "0" : "") + s
                            }
                            return fmt(videoPlayer.position) + " / " + fmt(videoPlayer.duration)
                        }
                        color: Qt.alpha("white", 0.75)
                        font.pixelSize: 12; font.weight: Font.Medium
                        font.family: "JetBrains Mono"
                    }

                    // Right side: edit + loop + volume + video-fullscreen
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // Trim / edit
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 14
                            color: Qt.alpha("white", root._editMode ? 0.28 : (editMa.containsMouse ? 0.20 : 0.12))
                            Behavior on color { ColorAnimation { duration: 80 } }
                            M3Icon { anchors.centerIn: parent; name: "content_cut"; size: 15; color: "white" }
                            MouseArea {
                                id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root._editMode ? (root._editMode = false) : root._enterEdit()
                            }
                        }

                        // Loop toggle
                        Rectangle {
                            id: videoLoopBtn
                            property bool looping: true
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 14
                            color: Qt.alpha("white", looping ? 0.25 : (loopMa.containsMouse ? 0.16 : 0.12))
                            Behavior on color { ColorAnimation { duration: 80 } }
                            M3Icon { anchors.centerIn: parent; name: "repeat"; size: 15
                                color: videoLoopBtn.looping ? "white" : Qt.alpha("white", 0.55) }
                            MouseArea { id: loopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: videoLoopBtn.looping = !videoLoopBtn.looping }
                        }

                        Item {
                            id: volWrapper
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            width: volHoverMa.containsMouse ? (30 + 6 + 80) : 30
                            clip: true
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                            MouseArea {
                                id: volHoverMa
                                anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Item {
                                    width: 80; height: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: volHoverMa.containsMouse ? (audioOut.muted ? 0.35 : 1.0) : 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 4; radius: 2
                                        color: Qt.alpha("white", 0.25)
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: audioOut.muted ? 0 : audioOut.volume * parent.width
                                        height: 4; radius: 2; color: "white"
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: (audioOut.muted ? 0 : audioOut.volume) * (parent.width - 12)
                                        width: 12; height: 12; radius: 6; color: "white"
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: (m) => {
                                            audioOut.muted = false
                                            audioOut.volume = Math.max(0, Math.min(1, m.x / width))
                                        }
                                        onPositionChanged: (m) => {
                                            if (pressed) {
                                                audioOut.muted = false
                                                audioOut.volume = Math.max(0, Math.min(1, m.x / width))
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    color: Qt.alpha("white", muteMa.containsMouse ? 0.20 : 0.12)
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                    M3Icon {
                                        anchors.centerIn: parent
                                        name: audioOut.muted ? "volume_off" : "volume_up"
                                        size: 15; color: "white"
                                    }
                                    MouseArea {
                                        id: muteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: audioOut.muted = !audioOut.muted
                                    }
                                }
                            }
                        }

                        // Video fullscreen (system-level)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 14
                            color: Qt.alpha("white", vfsMa.containsMouse ? 0.20 : 0.12)
                            Behavior on color { ColorAnimation { duration: 80 } }
                            M3Icon {
                                anchors.centerIn: parent
                                name: root._videoFullscreen ? "fullscreen_exit" : "fullscreen"
                                size: 15; color: "white"
                            }
                            MouseArea {
                                id: vfsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleVideoFullscreen()
                            }
                        }
                    }
                }

                // ── Scrubber track with M3-style stadium thumb (BOTTOM) ───
                Item {
                    id: seekTrack
                    width: parent.width
                    height: 20

                    readonly property real _playRatio:
                        videoPlayer.duration > 0
                        ? Math.min(1.0, videoPlayer.position / videoPlayer.duration) : 0
                    readonly property real _ratio:
                        seekDrag.pressed ? seekDrag._seekRatio : _playRatio

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4; radius: 2
                        color: Qt.alpha("white", 0.20)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: seekTrack._ratio * parent.width
                        height: 4; radius: 2; color: "white"
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: seekTrack._ratio * (seekTrack.width - width)
                        width: seekDrag.pressed ? 20 : 12
                        height: 12; radius: 6; color: "white"
                        Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutQuart } }
                    }

                    MouseArea {
                        id: seekDrag
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        hoverEnabled: false
                        property real _seekRatio: seekTrack._playRatio

                        onPressed: (m) => {
                            _seekRatio = Math.max(0, Math.min(1, m.x / width))
                            if (videoPlayer.duration > 0)
                                videoPlayer.position = Math.round(_seekRatio * videoPlayer.duration)
                        }
                        onPositionChanged: (m) => {
                            if (pressed) {
                                _seekRatio = Math.max(0, Math.min(1, m.x / width))
                                if (videoPlayer.duration > 0)
                                    videoPlayer.position = Math.round(_seekRatio * videoPlayer.duration)
                            }
                        }
                    }
                }
            }
        }

        // ── Trim / edit panel (above the video controls) ──────────────────
        Rectangle {
            id: editPanel
            visible: root._editMode && root._isVideo
            z: 12
            opacity: visible ? (root._vidFs ? (root._controlsVisible ? 1 : 0) : 1) : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: videoControls.top
            anchors.bottomMargin: 10
            height: 52
            radius: 16
            color: Qt.alpha("black", 0.82)
            width: editRow.implicitWidth + 28

            component MiniBtn: Rectangle {
                property alias label: t.text
                property bool filled: false
                property bool on: false
                signal clicked()
                width: t.implicitWidth + 22; height: 30; radius: 15
                color: filled ? ThemeManager.primary
                              : Qt.alpha("white", on ? 0.28 : (ma.containsMouse ? 0.20 : 0.12))
                Behavior on color { ColorAnimation { duration: 80 } }
                Label { id: t; anchors.centerIn: parent; color: parent.filled ? ThemeManager.onPrimary : "white"
                        font.pixelSize: 12; font.weight: Font.Medium }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: parent.clicked() }
            }

            Row {
                id: editRow
                anchors.centerIn: parent
                spacing: 8

                Row {
                    spacing: 6; anchors.verticalCenter: parent.verticalCenter
                    Label { text: I18n.t(Settings.language, "editor_start"); color: Qt.alpha("white", 0.6); font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter }
                    Label { text: root._fmt(root._trimStartMs); color: "white"; font.pixelSize: 13
                            font.family: "JetBrains Mono"; anchors.verticalCenter: parent.verticalCenter }
                    MiniBtn { anchors.verticalCenter: parent.verticalCenter; label: I18n.t(Settings.language, "editor_set")
                              onClicked: root._trimStartMs = Math.min(videoPlayer.position, root._trimEndMs - 100) }
                }
                Rectangle { width: 1; height: 26; color: Qt.alpha("white", 0.15); anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 6; anchors.verticalCenter: parent.verticalCenter
                    Label { text: I18n.t(Settings.language, "editor_end"); color: Qt.alpha("white", 0.6); font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter }
                    Label { text: root._fmt(root._trimEndMs); color: "white"; font.pixelSize: 13
                            font.family: "JetBrains Mono"; anchors.verticalCenter: parent.verticalCenter }
                    MiniBtn { anchors.verticalCenter: parent.verticalCenter; label: I18n.t(Settings.language, "editor_set")
                              onClicked: root._trimEndMs = Math.max(videoPlayer.position, root._trimStartMs + 100) }
                }
                Rectangle { width: 1; height: 26; color: Qt.alpha("white", 0.15); anchors.verticalCenter: parent.verticalCenter }

                // Audio keep / drop
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 30; radius: 15
                    color: Qt.alpha("white", audMa.containsMouse ? 0.20 : 0.12)
                    Behavior on color { ColorAnimation { duration: 80 } }
                    M3Icon { anchors.centerIn: parent; size: 15; color: "white"
                             name: root._keepAudio ? "volume_up" : "volume_off" }
                    MouseArea { id: audMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root._keepAudio = !root._keepAudio }
                }

                MiniBtn { anchors.verticalCenter: parent.verticalCenter; label: I18n.t(Settings.language, "cancel")
                          onClicked: root._editMode = false }
                MiniBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    filled: true
                    opacity: (VideoEditor.busy || root._trimEndMs <= root._trimStartMs) ? 0.5 : 1
                    label: VideoEditor.busy ? I18n.t(Settings.language, "editor_exporting") : I18n.t(Settings.language, "editor_save_copy")
                    onClicked: {
                        if (VideoEditor.busy || root._trimEndMs <= root._trimStartMs) return
                        VideoEditor.trim(videoPlayer.source,
                                         Math.round(root._trimStartMs),
                                         Math.round(root._trimEndMs),
                                         !root._keepAudio)
                    }
                }
            }
        }

        // ── Transient toast (export result) ───────────────────────────────
        Rectangle {
            visible: root._toast !== ""
            z: 30
            opacity: root._toast !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 120
            height: 40; radius: 20
            color: Qt.alpha("black", 0.85)
            width: toastLbl.implicitWidth + 32
            Label { id: toastLbl; anchors.centerIn: parent; text: root._toast
                    color: "white"; font.pixelSize: 13; font.weight: Font.Medium }
        }
        Timer { id: toastTimer; interval: 4000; onTriggered: root._toast = "" }

        Connections {
            target: VideoEditor
            function onFinished(outputPath) {
                root._editMode = false
                root._toast = I18n.t(Settings.language, "editor_saved") + outputPath.split("/").pop()
                toastTimer.restart()
            }
            function onFailed(err) {
                root._toast = I18n.t(Settings.language, "editor_export_failed") + err
                toastTimer.restart()
            }
        }

        // Double-click zoom toggle + pan drag handler (images only)
        MouseArea {
            id: imgMouseArea
            anchors.fill: parent
            z: 2
            hoverEnabled: false
            acceptedButtons: Qt.LeftButton

            property real _dragStartX:    0
            property real _dragStartY:    0
            property real _dragStartPanX: 0
            property real _dragStartPanY: 0
            property bool _wasDrag:       false

            onDoubleClicked: {
                if (root._zoom > 1.05) root.resetZoom()
                else root._zoom = 2.5
            }

            onPressed: {
                _wasDrag = false
                if (root._zoom > 1.05) {
                    _dragStartX    = mouseX; _dragStartY    = mouseY
                    _dragStartPanX = root._panX; _dragStartPanY = root._panY
                }
            }

            onPositionChanged: {
                if (pressed && root._zoom > 1.05) {
                    _wasDrag = true
                    root._panX = _dragStartPanX + (mouseX - _dragStartX)
                    root._panY = _dragStartPanY + (mouseY - _dragStartY)
                }
            }

            onClicked: {
                if (root._isVideo) return  // never dismiss viewer by clicking video area
                if (!_wasDrag && root._zoom <= 1.05) root.active = false
            }

            cursorShape: root._zoom > 1.05 ? Qt.OpenHandCursor : Qt.ArrowCursor
        }
    }

    // ── Prev ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.left: parent.left; anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52; radius: 26
        color: Qt.alpha("white", prevMa.pressed ? 0.28 : prevMa.containsMouse ? 0.20 : 0.14)
        border.color: Qt.alpha("white", 0.08); border.width: 1
        opacity: root._vidFs ? 0 : (root.currentIndex > 0 ? 1.0 : 0.25)
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on color { ColorAnimation { duration: 80 } }
        scale: prevMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        M3Icon { anchors.centerIn: parent; name: "chevron_left"; size: 26; color: "white" }
        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.currentIndex > 0; onClicked: root.navigatePrev() }
    }

    // ── Next ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 52; height: 52; radius: 26
        color: Qt.alpha("white", nextMa.pressed ? 0.28 : nextMa.containsMouse ? 0.20 : 0.14)
        border.color: Qt.alpha("white", 0.08); border.width: 1
        opacity: root._vidFs ? 0 : (root.currentIndex < root.allItems.length - 1 ? 1.0 : 0.25)
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on color { ColorAnimation { duration: 80 } }
        scale: nextMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        M3Icon { anchors.centerIn: parent; name: "chevron_right"; size: 26; color: "white" }
        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.currentIndex < root.allItems.length - 1; onClicked: root.navigateNext() }
    }

    // ── Close ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 24
        width: 48; height: 48; radius: 24
        color: Qt.alpha("white", closeMa.pressed ? 0.28 : closeMa.containsMouse ? 0.20 : 0.14)
        opacity: root._vidFs ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on color { ColorAnimation { duration: 80 } }
        scale: closeMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
        M3Icon { anchors.centerIn: parent; name: "close"; size: 22; color: "white" }
        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.active = false }
    }

    // ── Filename + date ───────────────────────────────────────────────────
    Column {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 28
        anchors.right: zoomRow.left; anchors.rightMargin: 16
        spacing: 4
        opacity: root._vidFs ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Label {
            width: parent.width
            text: root.mediaData ? root.mediaData.file_path.split('/').pop() : "Untitled"
            color: "white"; font.family: "Roboto Flex"; font.pixelSize: 18; font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Label {
            text: root.mediaData && root.mediaData.creation_date
                  ? Qt.formatDateTime(new Date(root.mediaData.creation_date * 1000), "dd MMMM yyyy")
                  : ""
            color: Qt.alpha("white", 0.65); font.pixelSize: 13
        }
    }

    // ── Zoom controls (centered at bottom) ───────────────────────────────
    Row {
        id: zoomRow
        anchors.horizontalCenter: imgArea.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        spacing: 8
        opacity: root._vidFs ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", zoomOutMa.pressed ? 0.28 : zoomOutMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: zoomOutMa.pressed ? 0.92 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "remove"; size: 22; color: "white" }
            MouseArea { id: zoomOutMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { root._zoom = Math.max(1.0, root._zoom / 1.5); if (root._zoom <= 1.02) root.resetZoom() } }
        }

        Rectangle {
            width: 72; height: 48; radius: 24
            color: Qt.alpha("white", zoomResetMa.pressed ? 0.28 : zoomResetMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: zoomResetMa.pressed ? 0.92 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            Label { anchors.centerIn: parent; text: Math.round(root._zoom * 100) + "%"; color: "white"; font.pixelSize: 14; font.weight: Font.Medium }
            MouseArea { id: zoomResetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resetZoom() }
        }

        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", zoomInMa.pressed ? 0.28 : zoomInMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: zoomInMa.pressed ? 0.92 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "add"; size: 22; color: "white" }
            MouseArea { id: zoomInMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root._zoom = Math.min(8.0, root._zoom * 1.5) }
        }
    }

    // ── Action buttons ────────────────────────────────────────────────────
    Row {
        id: actionRow
        anchors.right: root.infoPanelOpen ? infoPanel.left : parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        spacing: 8
        opacity: root._vidFs ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        property bool isFav: root.mediaData ? !!root.mediaData.is_favorite : false

        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", favMa.pressed ? 0.28 : favMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: favMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: actionRow.isFav ? "favorite_fill" : "favorite"; size: 22; color: "white" }
            MouseArea { id: favMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (!root.mediaData) return; DB.toggleFavorite(root.mediaData.id); root.mediaData = DB.getMediaById(root.mediaData.id); TimelineModel.refresh() } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", trashMa.pressed ? 0.28 : trashMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: trashMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "delete"; size: 22; color: "white" }
            MouseArea { id: trashMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (!root.mediaData) return; DB.setTrashed(root.mediaData.id, true); root.active = false; TimelineModel.refresh() } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", folderMa.pressed ? 0.28 : folderMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: folderMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "folder_open"; size: 22; color: "white" }
            MouseArea { id: folderMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.mediaData) Qt.openUrlExternally("file://" + root.mediaData.folder_path) } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", infoMa.pressed ? 0.28 : root.infoPanelOpen ? 0.28 : infoMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: infoMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "info"; size: 22; color: "white" }
            MouseArea { id: infoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.infoPanelOpen = !root.infoPanelOpen }
        }
        Rectangle {
            visible: !root._isVideo
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", copyMa.pressed ? 0.28 : copyMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: copyMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "content_copy"; size: 22; color: "white" }
            MouseArea { id: copyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.mediaData) Settings.copyImageToClipboard(root.mediaData.file_path) } }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", fsMa.pressed ? 0.28 : fsMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: fsMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon {
                anchors.centerIn: parent
                name: root._isFullscreen ? "fullscreen_exit" : "fullscreen"
                size: 22; color: "white"
            }
            MouseArea { id: fsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root._isFullscreen) { ApplicationWindow.window.showNormal(); root._isFullscreen = false }
                    else { ApplicationWindow.window.showFullScreen(); root._isFullscreen = true }
                }
            }
        }
        Rectangle {
            width: 48; height: 48; radius: 24
            color: Qt.alpha("white", delMa.pressed ? 0.28 : delMa.containsMouse ? 0.20 : 0.14)
            Behavior on color { ColorAnimation { duration: 80 } }
            scale: delMa.pressed ? 0.90 : 1.0; Behavior on scale { NumberAnimation { duration: 80 } }
            M3Icon { anchors.centerIn: parent; name: "delete_forever"; size: 22; color: "#ffd8e4" }
            MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: deleteConfirm.showing = !deleteConfirm.showing }
        }
    }

    // ── Delete confirmation ───────────────────────────────────────────────
    Rectangle {
        id: deleteConfirm
        property bool showing: false
        anchors.left: actionRow.left
        anchors.right: actionRow.right
        anchors.bottom: actionRow.top
        anchors.bottomMargin: showing ? 10 : 4
        height: 52; radius: 14
        color: ThemeManager.errorContainer
        opacity: showing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 8; spacing: 8
            Label {
                Layout.fillWidth: true; text: "Delete permanently?"
                color: ThemeManager.onErrorContainer; font.pixelSize: 13
            }
            Rectangle {
                height: 36; radius: 18; implicitWidth: cancelConfLbl.implicitWidth + 24
                color: cancelConfMa.containsMouse ? Qt.alpha(ThemeManager.onErrorContainer, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                Label { id: cancelConfLbl; anchors.centerIn: parent; text: "Cancel"; color: ThemeManager.onErrorContainer; font.pixelSize: 13 }
                MouseArea { id: cancelConfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: deleteConfirm.showing = false }
            }
            Rectangle {
                height: 36; radius: 18; implicitWidth: deleteConfLbl.implicitWidth + 24
                color: deleteConfMa.containsMouse ? Qt.darker(ThemeManager.error, 1.1) : ThemeManager.error
                Behavior on color { ColorAnimation { duration: 80 } }
                Label { id: deleteConfLbl; anchors.centerIn: parent; text: "Delete"; color: "white"; font.pixelSize: 13; font.weight: Font.Medium }
                MouseArea {
                    id: deleteConfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.mediaData) { DB.deleteMediaPermanently(root.mediaData.id); root.active = false; TimelineModel.refresh() }
                        deleteConfirm.showing = false
                    }
                }
            }
            Item { width: 4 }
        }
    }

    // ── Info panel ────────────────────────────────────────────────────────
    MediaInfoPanel {
        id: infoPanel
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: 380
        mediaData: root.mediaData

        opacity: root.infoPanelOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

        transform: Translate {
            x: root.infoPanelOpen ? 0 : 380
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
        }
    }
}
