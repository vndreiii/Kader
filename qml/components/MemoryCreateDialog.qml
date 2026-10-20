import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.platform as Platform
import ".."
import "../I18n.js" as I18n
import "../Paths.js" as Paths

// "Create memory": pick a few photos, a song, a title and a date (prefilled from
// the photos, editable) and render one in the same style as the automatic ones.
Popup {
    id: root
    function _t(k) { return I18n.t(Settings.language, k) }

    modal: true
    // fixed top edge: the card grows downwards when the song section opens
    property real _topY: 40
    x: parent ? (parent.width - width) / 2 : 0
    y: _topY
    width: 560
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var  photos: []            // local paths, in slideshow order
    property var  songs: []
    property string song: ""
    property bool _titleEdited: false
    property bool _dateEdited: false
    readonly property bool _dateOk: /^\d{4}-\d{2}-\d{2}$/.test(dateField.text) && !isNaN(Date.parse(dateField.text))
    readonly property bool _canCreate: photos.length >= 2 && song !== "" && _dateOk && !Memories.generating

    function _refill() {
        if (photos.length === 0) return
        if (!_dateEdited) dateField.text = Memories.suggestDate(photos)
        if (!_titleEdited) titleField.text = Memories.defaultTitle(dateField.text)
    }
    function removePhoto(i) {
        var p = photos.slice(); p.splice(i, 1); photos = p
        _refill()
    }

    // ── song section (own songs only) ──────────────────────────────────────
    readonly property bool _ownSong: {
        for (var i = 0; i < songs.length; i++)
            if (songs[i].file === song) return songs[i].mood === "custom"
        return false
    }
    property real songDur: 0            // seconds
    property real memLen: 0             // length of the finished memory
    property real songStart: 0
    property var  wave: []
    readonly property real _secLen: Math.min(memLen, songDur)
    function fmt(sec) {
        sec = Math.max(0, Math.round(sec))
        var m = Math.floor(sec / 60), s = sec % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function _isOwnSong(file) {
        for (var i = 0; i < songs.length; i++)
            if (songs[i].file === file) return songs[i].mood === "custom"
        return false
    }
    // Looks at the song itself, not _ownSong: that binding may not have updated
    // yet when onSongChanged fires.
    function _loadSong() {
        pv.pause()
        songStart = 0
        if (!_isOwnSong(song)) { songDur = 0; wave = []; return }
        songDur = Memories.songDuration(song)
        wave = Memories.waveform(song, 160)
        memLen = Memories.estimateDuration(photos)
    }
    onSongChanged: Qt.callLater(_loadSong)
    onSongsChanged: Qt.callLater(_loadSong)
    onPhotosChanged: {
        memLen = photos.length >= 2 ? Memories.estimateDuration(photos) : 0
        songStart = Math.max(0, Math.min(songStart, songDur - _secLen))
    }
    onClosed: pv.pause()

    MediaPlayer {
        id: pv
        source: root._ownSong ? Paths.fileUrl(root.song) : ""
        audioOutput: AudioOutput { volume: 0.85 }
        onPositionChanged: {
            if (playbackState === MediaPlayer.PlayingState && position >= (root.songStart + root._secLen) * 1000) {
                pause()
                setPosition(root.songStart * 1000)
            }
        }
    }

    onAboutToShow: {
        _topY = Math.max(16, (parent.height - implicitHeight) / 2)
        photos = []; _titleEdited = false; _dateEdited = false
        titleField.text = ""; dateField.text = Qt.formatDate(new Date(), "yyyy-MM-dd")
        songs = Memories.tracks(); _songError = ""
        song = songs.length > 0 ? songs[Math.floor(Math.random() * songs.length)].file : ""
    }

    background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }

    MemoryPhotoPicker {
        id: picker
        chosen: root.photos
        onPicked: function (paths) { root.photos = paths; root._refill() }
    }

    Platform.FileDialog {
        id: songPicker
        title: root._t("memory_add_song")
        fileMode: Platform.FileDialog.OpenFile
        nameFilters: ["Audio (*.mp3 *.ogg *.opus *.flac *.wav *.m4a *.aac)"]
        onAccepted: Memories.importSong(file.toString())
    }

    // portal first; Qt's own dialog where there is none (Windows)
    function addSong() { if (!Memories.pickSongViaPortal()) songPicker.open() }

    property string _songError: ""
    Connections {
        target: Memories
        function onSongAdded(path) { root.songs = Memories.tracks(); root.song = path; root._songError = "" }
        function onSongRejected(name) { root._songError = root._t("memory_song_rejected").arg(name) }
    }

    Column {
        width: parent.width
        padding: 24
        spacing: 16

        RowLayout {
            width: parent.width - parent.padding * 2
            Label {
                text: root._t("memory_create")
                font.family: "Roboto Flex"; font.pixelSize: 20; font.weight: Font.Medium
                color: ThemeManager.onSurface
            }
            Item { Layout.fillWidth: true }
            M3IconButton { icon: "close"; onClicked: root.close() }
        }

        // ── Photos ─────────────────────────────────────────────────────────
        Column {
            width: parent.width - parent.padding * 2
            spacing: 8
            Label { text: root._t("memory_photos").arg(root.photos.length); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: root.photos
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        width: 72; height: 72; radius: 12; clip: true
                        color: ThemeManager.surfaceContainerHighest
                        Image {
                            anchors.fill: parent
                            source: Memories.thumbUrl(parent.modelData)
                            sourceSize.width: 144; sourceSize.height: 144
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 3 }
                            width: 20; height: 20; radius: 10
                            color: Qt.rgba(0, 0, 0, 0.6)
                            M3Icon { anchors.centerIn: parent; name: "close"; size: 14; color: "white" }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.removePhoto(parent.parent.index) }
                        }
                    }
                }
                Rectangle {
                    width: 72; height: 72; radius: 12
                    color: addMa.containsMouse ? Qt.alpha(ThemeManager.primary, 0.14) : Qt.alpha(ThemeManager.primary, 0.08)
                    MaterialSymbol { anchors.centerIn: parent; name: "add_photo_alternate"; size: 28; color: ThemeManager.primary }
                    MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.open() }
                }
            }
        }

        // ── Song ───────────────────────────────────────────────────────────
        Column {
            width: parent.width - parent.padding * 2
            spacing: 4
            Label { text: root._t("memory_song"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
            Rectangle {
                id: songField
                width: parent.width; height: 48; radius: 12
                color: ThemeManager.surfaceContainerHighest
                border.width: songMenu.visible ? 2 : 0
                border.color: ThemeManager.primary
                Label {
                    anchors { left: parent.left; right: arrow.left; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 8 }
                    elide: Text.ElideRight
                    font.pixelSize: 15; color: ThemeManager.onSurface
                    text: {
                        for (var i = 0; i < root.songs.length; i++)
                            if (root.songs[i].file === root.song)
                                return root.songs[i].name + " · " + root._t("mood_" + root.songs[i].mood)
                        return ""
                    }
                }
                MaterialSymbol { id: arrow; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    name: "arrow_drop_down"; size: 24; color: ThemeManager.onSurfaceVariant }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: songMenu.visible ? songMenu.close() : songMenu.popup(songField, 0, songField.height + 4) }

                // the same menu the gallery's view options use
                M3Menu {
                    id: songMenu
                    width: songField.width
                    maxHeight: 340
                    Instantiator {
                        model: root.songs
                        delegate: M3MenuItem {
                            required property var modelData
                            iconName: "music_note"
                            text: modelData.name + " · " + root._t("mood_" + modelData.mood)
                            checkable: true
                            checked: root.song === modelData.file
                            onTriggered: root.song = modelData.file
                        }
                        onObjectAdded: function (i, obj) { songMenu.insertItem(i, obj) }
                        onObjectRemoved: function (i, obj) { songMenu.removeItem(obj) }
                    }
                    M3MenuSeparator {}
                    M3MenuItem {
                        iconName: "upload_file"
                        text: root._t("memory_add_song")
                        onTriggered: root.addSong()
                    }
                }
            }
            Label {
                visible: root._songError !== ""
                width: parent.width
                text: root._songError
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: ThemeManager.error
            }
        }

        // ── Song section (own songs): pick which part of the song plays ────
        Item {
            id: sectionWrap
            width: parent.width - parent.padding * 2
            height: root._ownSong ? sectionCol.implicitHeight : 0
            visible: height > 0
            clip: true
            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Column {
                id: sectionCol
                width: parent.width
                spacing: 8

                RowLayout {
                    width: parent.width
                    Label { text: root._t("memory_section"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                    Item { Layout.fillWidth: true }
                    Label {
                        font.pixelSize: 12; color: ThemeManager.onSurface
                        text: root.songDur <= 0 || root.memLen <= 0 ? ""
                            : root.memLen > root.songDur
                              ? root._t("memory_section_loops").arg(root.fmt(root.songDur)).arg(root.fmt(root.memLen))
                              : root.fmt(root.songStart) + " – " + root.fmt(root.songStart + root.memLen)
                                + " · " + root._t("memory_section_len").arg(root.fmt(root.memLen))
                    }
                }

                Rectangle {
                    id: waveBar
                    width: parent.width; height: 64; radius: 12
                    color: ThemeManager.surfaceContainerHighest
                    clip: true

                    // waveform
                    Row {
                        anchors.fill: parent; anchors.margins: 6
                        spacing: 0
                        Repeater {
                            model: root.wave
                            delegate: Item {
                                required property real modelData
                                width: (waveBar.width - 12) / Math.max(1, root.wave.length)
                                height: parent.height
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Math.max(1, parent.width - 1)
                                    height: Math.max(2, parent.parent.height * parent.modelData)
                                    radius: width / 2
                                    color: ThemeManager.onSurfaceVariant
                                    opacity: 0.55
                                }
                            }
                        }
                    }

                    // the chosen section
                    Rectangle {
                        id: windowRect
                        readonly property real unit: root.songDur > 0 ? (waveBar.width / root.songDur) : 0
                        x: root.songStart * unit
                        width: Math.max(8, root._secLen * unit)
                        height: parent.height
                        radius: 12
                        color: Qt.alpha(ThemeManager.primary, 0.22)
                        border.width: 2
                        border.color: ThemeManager.primary
                    }
                    // playhead
                    Rectangle {
                        visible: pv.playbackState === MediaPlayer.PlayingState
                        x: pv.position / 1000 * windowRect.unit
                        width: 2; height: parent.height
                        color: ThemeManager.onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function _move(mx) {
                            if (root.songDur <= 0) return
                            var centre = Math.max(0, Math.min(1, mx / width)) * root.songDur
                            root.songStart = Math.max(0, Math.min(root.songDur - root._secLen, centre - root._secLen / 2))
                        }
                        onPressed: (m) => _move(m.x)
                        onPositionChanged: (m) => { if (pressed) _move(m.x) }
                        onReleased: if (pv.playbackState === MediaPlayer.PlayingState) pv.setPosition(root.songStart * 1000)
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: 8
                    M3IconButton {
                        icon: pv.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                        color: ThemeManager.primary
                        onClicked: {
                            if (pv.playbackState === MediaPlayer.PlayingState) pv.pause()
                            else { pv.setPosition(root.songStart * 1000); pv.play() }
                        }
                    }
                    Label {
                        font.pixelSize: 13; color: ThemeManager.onSurfaceVariant
                        text: root._t("memory_section_preview") + " " +
                              root.fmt(Math.max(0, pv.position / 1000 - root.songStart)) + " / " + root.fmt(root._secLen)
                    }
                    Item { Layout.fillWidth: true }
                    Label { font.pixelSize: 12; color: ThemeManager.onSurfaceVariant; text: root._t("memory_section_hint") }
                }
            }
        }

        // ── Title + date ───────────────────────────────────────────────────
        RowLayout {
            width: parent.width - parent.padding * 2
            spacing: 12
            Column {
                Layout.fillWidth: true
                spacing: 4
                Label { text: root._t("memory_title"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                Rectangle {
                    width: parent.width; height: 48; radius: 12
                    color: ThemeManager.surfaceContainerHighest
                    border.width: titleField.activeFocus ? 2 : 0
                    border.color: ThemeManager.primary
                    TextInput {
                        id: titleField
                        anchors.fill: parent; anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 15; color: ThemeManager.onSurface; clip: true
                        onTextEdited: root._titleEdited = true
                    }
                }
            }
            Column {
                Layout.preferredWidth: 160
                spacing: 4
                Label { text: root._t("memory_date"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
                Rectangle {
                    width: parent.width; height: 48; radius: 12
                    color: ThemeManager.surfaceContainerHighest
                    border.width: dateField.activeFocus || !root._dateOk ? 2 : 0
                    border.color: root._dateOk ? ThemeManager.primary : ThemeManager.error
                    TextInput {
                        id: dateField
                        anchors.fill: parent; anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 15; color: ThemeManager.onSurface; clip: true
                        inputMethodHints: Qt.ImhDate
                        onTextEdited: { root._dateEdited = true; if (root._dateOk && !root._titleEdited) titleField.text = Memories.defaultTitle(text) }
                    }
                }
            }
        }

        RowLayout {
            width: parent.width - parent.padding * 2
            Item { Layout.fillWidth: true }
            M3Button { text: root._t("cancel"); onClicked: root.close() }
            M3Button {
                kind: "filled"
                text: root._t("memory_create_go")
                enabled: root._canCreate
                onClicked: {
                    if (Memories.createCustom(root.photos, root.song, titleField.text, dateField.text, root._ownSong ? root.songStart : 0))
                        root.close()
                }
            }
        }
        Item { height: 4 }
    }
}
