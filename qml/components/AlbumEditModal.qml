import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

Popup {
    id: root
    modal: true
    anchors.centerIn: parent
    width: 460
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Set before open(): empty folderPath = new virtual album
    property string folderPath: ""
    property string initName:   ""
    property string initDesc:   ""
    property string initCover:  ""

    readonly property bool isNew: folderPath === ""
    property string _selectedCover: ""

    signal saved()

    Connections {
        target: Settings
        function onImageFilePicked(path) {
            if (root.visible) root._selectedCover = path
        }
    }

    onAboutToShow: {
        nameField.text = initName
        descField.text = initDesc
        _selectedCover = initCover
        if (_selectedCover === "" && isNew)
            _selectedCover = DB.getRandomPhotoPath()
    }

    background: Rectangle {
        radius: 28
        color: ThemeManager.surfaceContainerHigh
    }

    Column {
        id: contentCol
        width: parent.width
        padding: 24
        spacing: 16

        // ── Header ─────────────────────────────────────────────────────────
        RowLayout {
            width: parent.width - parent.padding * 2
            Label {
                text: root.isNew ? I18n.t(Settings.language, "new_album") : I18n.t(Settings.language, "edit_album")
                font.family: "Roboto Flex"; font.pixelSize: 20; font.weight: Font.Medium
                color: ThemeManager.onSurface
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 32; height: 32; radius: 16
                color: closeMa.containsMouse ? Qt.alpha(ThemeManager.onSurface, 0.1) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                M3Icon { anchors.centerIn: parent; name: "close"; size: 18; color: ThemeManager.onSurfaceVariant }
                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
            }
        }

        // ── Name field ─────────────────────────────────────────────────────
        Column {
            width: parent.width - parent.padding * 2
            spacing: 4
            Label { text: I18n.t(Settings.language, "field_name"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
            Rectangle {
                width: parent.width; height: 48; radius: 12
                color: ThemeManager.surfaceContainerHighest
                border.width: nameField.activeFocus ? 2 : 0
                border.color: ThemeManager.primary
                Behavior on border.width { NumberAnimation { duration: 80 } }
                TextInput {
                    id: nameField
                    anchors.fill: parent; anchors.margins: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 15; color: ThemeManager.onSurface; clip: true
                }
            }
        }

        // ── Description field ──────────────────────────────────────────────
        Column {
            width: parent.width - parent.padding * 2
            spacing: 4
            Label { text: I18n.t(Settings.language, "field_desc_optional"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
            Rectangle {
                width: parent.width; height: 88; radius: 12
                color: ThemeManager.surfaceContainerHighest
                border.width: descField.activeFocus ? 2 : 0
                border.color: ThemeManager.primary
                Behavior on border.width { NumberAnimation { duration: 80 } }
                TextEdit {
                    id: descField
                    anchors.fill: parent; anchors.margins: 12
                    font.pixelSize: 13; color: ThemeManager.onSurface
                    wrapMode: TextEdit.Wrap; clip: true
                }
            }
        }

        // ── Cover photo ────────────────────────────────────────────────────
        Column {
            width: parent.width - parent.padding * 2
            spacing: 8
            Label { text: I18n.t(Settings.language, "cover_photo"); font.pixelSize: 12; color: ThemeManager.onSurfaceVariant }
            Row {
                spacing: 14
                Rectangle {
                    width: 80; height: 80; radius: 14
                    color: ThemeManager.surfaceContainerHighest
                    clip: true
                    M3Icon {
                        anchors.centerIn: parent; name: "image"; size: 32
                        color: ThemeManager.onSurfaceVariant; opacity: 0.4
                        visible: root._selectedCover === ""
                    }
                    Image {
                        anchors.fill: parent
                        source: root._selectedCover !== "" ? "file://" + root._selectedCover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: root._selectedCover !== ""
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: changeRow.implicitWidth + 24; height: 40; radius: 20
                    color: addPhotoMa.containsMouse ? Qt.alpha(ThemeManager.primary, 0.14) : Qt.alpha(ThemeManager.primary, 0.08)
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Row {
                        id: changeRow
                        anchors.centerIn: parent; spacing: 6
                        M3Icon { name: "image"; size: 18; color: ThemeManager.primary; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: I18n.t(Settings.language, "change_photo"); font.pixelSize: 13; color: ThemeManager.primary }
                    }
                    MouseArea {
                        id: addPhotoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.openImageFilePicker("Select cover photo")
                    }
                }
            }
        }

        // ── Action buttons ─────────────────────────────────────────────────
        RowLayout {
            width: parent.width - parent.padding * 2
            Item { Layout.fillWidth: true }
            Rectangle {
                width: cancelLbl.implicitWidth + 32; height: 40; radius: 20
                color: cancelMa.containsMouse ? Qt.alpha(ThemeManager.primary, 0.08) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                Label { id: cancelLbl; anchors.centerIn: parent; text: I18n.t(Settings.language, "cancel"); color: ThemeManager.primary; font.pixelSize: 14 }
                MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
            }
            Rectangle {
                width: saveLbl.implicitWidth + 32; height: 40; radius: 20
                color: saveMa.containsMouse ? Qt.alpha(ThemeManager.primary, 0.85) : ThemeManager.primary
                opacity: nameField.text.trim().length > 0 ? 1 : 0.4
                Behavior on color { ColorAnimation { duration: 80 } }
                Label { id: saveLbl; anchors.centerIn: parent; text: root.isNew ? I18n.t(Settings.language, "create_album") : I18n.t(Settings.language, "save"); color: ThemeManager.onPrimary; font.pixelSize: 14; font.weight: Font.Medium }
                MouseArea {
                    id: saveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    enabled: nameField.text.trim().length > 0
                    onClicked: {
                        if (root.isNew)
                            DB.createVirtualAlbum(nameField.text.trim(), descField.text.trim(), root._selectedCover)
                        else
                            DB.updateAlbumMeta(root.folderPath, nameField.text.trim(), descField.text.trim(), root._selectedCover)
                        AlbumModel.refresh()
                        root.saved()
                        root.close()
                    }
                }
            }
        }

        Item { height: 4 }
    }
}
