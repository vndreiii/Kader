import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../I18n.js" as I18n

// One person: name, the faces grouped under them (select to remove or set
// the cover), suggestions to add, merge, hide, calibrate; then their photos.
Item {
    id: root
    property int personId: -1
    signal back()
    signal openViewer(var data, var items)
    signal openPerson(int id)
    function _t(k) { return I18n.t(Settings.language, k) }

    property var info: ({})
    property var faces: []
    property var media: []
    property bool selecting: false
    property var selected: ({})
    readonly property int selectedCount: Object.keys(selected).length

    function reload() {
        info = Analyzer.person(personId)
        faces = Analyzer.personFaces(personId)
        media = Analyzer.personMedia(personId)
        if (!info.id && faces.length === 0) root.back() // merged away / emptied
    }
    onPersonIdChanged: reload()
    Connections { target: Analyzer; function onRevisionChanged() { root.reload() } }
    function toggle(id) {
        var s = Object.assign({}, selected)
        if (s[id]) delete s[id]; else s[id] = true
        selected = s
    }
    function clearSel() { selected = ({}); selecting = false }

    PageHeader {
        id: header
        title: root.info.name || root._t("unnamed_person")
        subtitle: root._t("n_photos").arg(root.media.length)
        onBack: root.back()
        M3Button { flat: true; text: root._t("add_faces"); onClicked: addPopup.open() }
        M3Button { flat: true; text: root._t("merge"); onClicked: mergePopup.open() }
        M3Button {
            flat: true
            text: root.info.hidden ? root._t("show_person") : root._t("hide_person")
            onClicked: Analyzer.setPersonHidden(root.personId, !root.info.hidden)
        }
        RoundButton {
            flat: true
            contentItem: MaterialSymbol { name: "tune"; size: 22; color: ThemeManager.onSurfaceVariant }
            ToolTip.text: root._t("calibrate_title"); ToolTip.visible: hovered
            onClicked: calibrate.open()
        }
    }

    ColumnLayout {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 28; rightMargin: 28 }
        spacing: 18

        // identity row
        RowLayout {
            Layout.fillWidth: true
            spacing: 22
            FaceAvatar {
                Layout.preferredWidth: 112; Layout.preferredHeight: 112
                faceId: root.info.cover !== undefined ? root.info.cover : -1
                revision: Analyzer.revision
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                M3TextField {
                    id: nameField
                    Layout.preferredWidth: 360
                    font.pixelSize: 22
                    placeholderText: root._t("add_name")
                    text: root.info.name || ""
                    onAccepted: { Analyzer.renamePerson(root.personId, text); focus = false }
                    onActiveFocusChanged: if (!activeFocus && text !== (root.info.name || "")) Analyzer.renamePerson(root.personId, text)
                }
                Label {
                    text: root._t("name_hint")
                    color: ThemeManager.onSurfaceVariant
                    font.pixelSize: 13
                }
            }
        }

        // faces strip
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Label { text: root._t("faces_count").arg(root.faces.length); font.pixelSize: 17; font.weight: Font.Medium; color: ThemeManager.onSurface }
            Item { Layout.fillWidth: true }
            M3Button {
                visible: root.selecting && root.selectedCount === 1
                flat: true
                text: root._t("make_cover")
                onClicked: { Analyzer.setCover(root.personId, parseInt(Object.keys(root.selected)[0])); root.clearSel() }
            }
            M3Button {
                visible: root.selecting && root.selectedCount > 0
                flat: true
                text: root._t("not_this_person").arg(root.selectedCount)
                onClicked: { Analyzer.removeFaces(Object.keys(root.selected).map(Number)); root.clearSel() }
            }
            M3Button {
                flat: true
                text: root.selecting ? root._t("done") : root._t("select")
                onClicked: root.selecting ? root.clearSel() : (root.selecting = true)
            }
        }
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            orientation: ListView.Horizontal
            spacing: 14
            clip: true
            model: root.faces
            delegate: FaceAvatar {
                required property var modelData
                width: 84; height: 84
                y: 4
                faceId: modelData.faceId
                selectable: root.selecting
                selected: !!root.selected[modelData.faceId]
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selecting ? root.toggle(modelData.faceId) : (root.selecting = true, root.toggle(modelData.faceId))
                }
            }
        }

        Label { text: root._t("photos_title"); font.pixelSize: 17; font.weight: Font.Medium; color: ThemeManager.onSurface }
        ThumbGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            items: root.media
            minCell: 160
            onOpenItem: (i) => root.openViewer(items[i], items)
        }
    }

    // ── add faces: suggestions most similar to this person ───────────────
    Popup {
        id: addPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 48)
        height: Math.min(620, parent.height - 48)
        modal: true
        padding: 24
        property var suggestions: []
        property var picked: ({})
        onOpened: { suggestions = Analyzer.suggestedFaces(root.personId, 60); picked = ({}) }
        background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: root._t("add_faces_title").arg(root.info.name || root._t("unnamed_person")); font.pixelSize: 22; color: ThemeManager.onSurface }
            Label {
                Layout.fillWidth: true
                text: addPopup.suggestions.length > 0 ? root._t("add_faces_body") : root._t("add_faces_none")
                wrapMode: Text.WordWrap
                color: ThemeManager.onSurfaceVariant
            }
            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 104; cellHeight: 124
                model: addPopup.suggestions
                delegate: Column {
                    required property var modelData
                    width: 104
                    spacing: 4
                    FaceAvatar {
                        width: 84; height: 84
                        anchors.horizontalCenter: parent.horizontalCenter
                        faceId: modelData.faceId
                        selectable: true
                        selected: !!addPopup.picked[modelData.faceId]
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var p = Object.assign({}, addPopup.picked)
                                if (p[modelData.faceId]) delete p[modelData.faceId]; else p[modelData.faceId] = true
                                addPopup.picked = p
                            }
                        }
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(modelData.similarity * 100) + "%"
                        font.pixelSize: 12
                        color: ThemeManager.onSurfaceVariant
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                M3Button { flat: true; text: root._t("cancel"); onClicked: addPopup.close() }
                M3Button {
                    highlighted: true
                    enabled: Object.keys(addPopup.picked).length > 0
                    text: root._t("add_n_faces").arg(Object.keys(addPopup.picked).length)
                    onClicked: { Analyzer.assignFaces(Object.keys(addPopup.picked).map(Number), root.personId); addPopup.close() }
                }
            }
        }
    }

    // ── merge into another person ────────────────────────────────────────
    Popup {
        id: mergePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(720, parent.width - 48)
        height: Math.min(560, parent.height - 48)
        modal: true
        padding: 24
        property var others: []
        onOpened: others = Analyzer.people(true).filter(p => p.id !== root.personId)
        background: Rectangle { radius: 28; color: ThemeManager.surfaceContainerHigh }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: root._t("merge_title"); font.pixelSize: 22; color: ThemeManager.onSurface }
            Label { Layout.fillWidth: true; text: root._t("merge_body"); wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant }
            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 120; cellHeight: 140
                model: mergePopup.others
                delegate: Column {
                    required property var modelData
                    width: 120
                    spacing: 6
                    FaceAvatar {
                        width: 92; height: 92
                        anchors.horizontalCenter: parent.horizontalCenter
                        faceId: modelData.cover !== undefined ? modelData.cover : -1
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var into = modelData.id
                                Analyzer.mergePeople(root.personId, into)
                                mergePopup.close()
                                root.openPerson(into)
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name || root._t("n_photos").arg(modelData.photos)
                        elide: Text.ElideRight
                        color: ThemeManager.onSurface
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                M3Button { flat: true; text: root._t("cancel"); onClicked: mergePopup.close() }
            }
        }
    }

    CalibratePopup { id: calibrate }
}
