import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.platform as Platform
import ".."
import "../I18n.js" as I18n
import "../Paths.js" as Paths

// Search → "Memory videos": the auto-generated weekly slideshow reels (see
// MemoryManager). Cards play in a popup; each has Save as… and Delete.
ColumnLayout {
    id: root
    function _t(k) { return I18n.t(Settings.language, k) }

    property var items: []
    property var current: null          // memory shown in the player
    function reload() { items = Memories.list() }
    Component.onCompleted: reload()
    Connections { target: Memories; function onRevisionChanged() { root.reload() } }

    function fmtDuration(ms) {
        var s = Math.round(ms / 1000)
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }
    function sub(m) { return root._t("mood_" + m.mood) + " · " + fmtDuration(m.durationMs) }

    function saveAs(m) { current = m; saveDialog.folder = Platform.StandardPaths.writableLocation(Platform.StandardPaths.MoviesLocation); saveDialog.currentFile = saveDialog.folder + "/" + Memories.suggestedFileName(m.id); saveDialog.open() }
    function askDelete(m) { current = m; confirmDelete.open() }

    visible: items.length > 0 || Memories.generating
    Layout.fillWidth: true
    spacing: 12

    SectionTitle { text: root._t("memory_videos"); count: -1 }

    Label {
        visible: root.items.length === 0 && Memories.generating
        text: root._t("memory_generating")
        color: ThemeManager.onSurfaceVariant
    }

    ListView {
        visible: root.items.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 200
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        model: root.items
        delegate: CoverCard {
            id: card
            required property var modelData
            width: 300; height: 200
            covers: modelData.cover ? [modelData.cover] : []
            title: modelData.title
            subtitle: root.sub(modelData)
            onClicked: { root.current = modelData; player.open() }

            Rectangle {   // play badge
                anchors.centerIn: parent
                width: 52; height: 52; radius: 26
                color: Qt.rgba(0, 0, 0, 0.45)
                MaterialSymbol { anchors.centerIn: parent; name: "play_arrow"; size: 32; color: "white" }
            }
            M3IconButton {
                anchors { top: parent.top; right: parent.right; margins: 8 }
                icon: "more_vert"; color: "white"
                onClicked: cardMenu.popup()
            }
            M3Menu {
                id: cardMenu
                M3MenuItem { iconName: "play_arrow"; text: root._t("memory_play"); onTriggered: { root.current = card.modelData; player.open() } }
                M3MenuItem { iconName: "download"; text: root._t("memory_save"); onTriggered: root.saveAs(card.modelData) }
                M3MenuItem { iconName: "delete"; text: root._t("memory_delete"); onTriggered: root.askDelete(card.modelData) }
            }
        }
    }

    Platform.FileDialog {
        id: saveDialog
        title: root._t("memory_save")
        fileMode: Platform.FileDialog.SaveFile
        nameFilters: ["MP4 video (*.mp4)"]
        onAccepted: if (root.current) Memories.exportTo(root.current.id, file.toString())
    }

    Popup {
        id: confirmDelete
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: 24
        background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
        ColumnLayout {
            spacing: 18
            Label { text: root._t("memory_delete_q"); font.pixelSize: 20; color: ThemeManager.onSurface }
            Label { text: root._t("memory_delete_body"); color: ThemeManager.onSurfaceVariant }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                M3Button { flat: true; text: root._t("cancel"); onClicked: confirmDelete.close() }
                M3Button { text: root._t("memory_delete"); onClicked: { if (root.current) Memories.remove(root.current.id); confirmDelete.close() } }
            }
        }
    }

    Popup {
        id: player
        parent: Overlay.overlay
        x: 0; y: 0
        width: parent ? parent.width : 0; height: parent ? parent.height : 0
        modal: true
        padding: 0
        background: Rectangle { color: Qt.rgba(0, 0, 0, 0.92) }
        onOpened: mp.play()
        onClosed: mp.stop()

        MediaPlayer {
            id: mp
            source: root.current && player.visible ? root.current.video : ""
            videoOutput: vo
            audioOutput: AudioOutput { volume: 0.7 }
            loops: MediaPlayer.Infinite
        }
        VideoOutput {
            id: vo
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: bar.top; margins: 24 }
            fillMode: VideoOutput.PreserveAspectFit
            MouseArea {
                anchors.fill: parent
                onClicked: mp.playbackState === MediaPlayer.PlayingState ? mp.pause() : mp.play()
            }
        }
        Rectangle {
            id: bar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 72
            color: "transparent"
            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                spacing: 12
                M3IconButton {
                    icon: mp.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"; color: "white"; iconSize: 28
                    onClicked: mp.playbackState === MediaPlayer.PlayingState ? mp.pause() : mp.play()
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0; to: Math.max(1, mp.duration)
                    value: mp.position
                    onMoved: mp.setPosition(value)
                }
                Label {
                    text: root.current ? root.current.title : ""
                    color: "white"; elide: Text.ElideRight; Layout.maximumWidth: 320
                }
                M3IconButton { icon: "download"; color: "white"; onClicked: { player.close(); if (root.current) root.saveAs(root.current) } }
                M3IconButton { icon: "delete"; color: "white"; onClicked: { player.close(); if (root.current) root.askDelete(root.current) } }
                M3IconButton { icon: "close"; color: "white"; onClicked: player.close() }
            }
        }
    }
}
