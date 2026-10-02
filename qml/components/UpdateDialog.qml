import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

// "A new version is available" dialog driven by the `Updater` context object
// (UpdateManager). Opens itself when an update is offered; the same dialog
// walks through download → install → restart.
Popup {
    id: root
    modal: true
    anchors.centerIn: parent
    width: Math.min(520, parent ? parent.width - 48 : 520)
    padding: 0
    closePolicy: busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

    readonly property int st: Updater.state
    readonly property bool busy: st === 3 || st === 4          // Downloading, Installing
    readonly property bool done: st === 5                       // Installed
    readonly property bool failed: st === 6
    readonly property bool arch: Updater.channel === "arch"

    function _t(k) { return I18n.t(Settings.language, k) }
    function _size(bytes) {
        if (bytes <= 0) return ""
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB"
        return bytes + " B"
    }

    Connections {
        target: Updater
        function onUpdateOffered() { root.open() }
    }
    onClosed: if (!busy && !done && st === 2) Updater.dismiss()

    background: Rectangle {
        radius: 28
        color: ThemeManager.surfaceContainerHigh
        border.color: Qt.alpha(ThemeManager.outline, 0.25)
    }

    ColumnLayout {
        width: parent.width
        spacing: 0

        // ── header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.bottomMargin: 8
            spacing: 16
            Rectangle {
                Layout.preferredWidth: 48; Layout.preferredHeight: 48
                radius: 16
                color: root.failed ? ThemeManager.errorContainer : ThemeManager.primaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    name: root.done ? "task_alt" : root.failed ? "error" : "system_update_alt"
                    size: 26
                    color: root.failed ? ThemeManager.onErrorContainer : ThemeManager.onPrimaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: root.done ? root._t("update_ready_title")
                        : root.failed ? root._t("update_failed_title")
                        : root._t("update_available_title")
                    font.family: "Roboto Flex"; font.pixelSize: 22; font.weight: Font.Medium
                    color: ThemeManager.onSurface
                    wrapMode: Text.Wrap
                }
                Label {
                    Layout.fillWidth: true
                    text: root._t("update_versions").arg(Updater.latestVersion).arg(Updater.currentVersion)
                          + (Updater.downloadSize > 0 && !root.done ? " · " + root._size(Updater.downloadSize) : "")
                    font.pixelSize: 13
                    color: ThemeManager.onSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── body: release notes / progress / error ──────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 24; Layout.rightMargin: 24
            Layout.preferredHeight: Math.min(260, notes.implicitHeight + 32)
            visible: !root.failed && Updater.notes !== ""
            radius: 16
            color: ThemeManager.surfaceContainerLowest
            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: notes.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Text {
                    id: notes
                    width: parent.width
                    text: Updater.notes
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    color: ThemeManager.onSurface
                    font.pixelSize: 13
                    linkColor: ThemeManager.primary
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.topMargin: 12
            Layout.bottomMargin: 0
            visible: text !== ""
            wrapMode: Text.Wrap
            font.pixelSize: 13
            color: root.failed ? ThemeManager.error : ThemeManager.onSurfaceVariant
            text: root.failed ? Updater.error
                : root.done ? root._t("update_restart_hint")
                : root.st === 4 ? root._t("update_installing_pacman")
                : root.st === 3 ? root._t("update_downloading").arg(Math.round(Updater.progress * 100))
                : !Updater.canInstall ? root._t("update_manual_hint")
                : root.arch ? root._t("update_arch_hint")
                : root._t("update_appimage_hint")
        }

        // progress (determinate while downloading, indeterminate in pacman)
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.topMargin: 12
            Layout.preferredHeight: 6
            visible: root.busy
            Rectangle { anchors.fill: parent; radius: 3; color: ThemeManager.secondaryContainer }
            Rectangle {
                id: bar
                height: parent.height; radius: 3
                color: ThemeManager.primary
                width: root.st === 3 ? parent.width * Updater.progress : parent.width * 0.3
                Behavior on width { enabled: root.st === 3; NumberAnimation { duration: 150 } }
                SequentialAnimation on x {
                    running: root.st === 4
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: bar.parent.width * 0.7; duration: 900; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: bar.parent.width * 0.7; to: 0; duration: 900; easing.type: Easing.InOutQuad }
                }
                onVisibleChanged: x = 0
            }
        }

        // ── actions ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.topMargin: 20
            spacing: 8

            DialogButton {
                visible: !root.busy && !root.done && !root.failed
                text: root._t("update_skip")
                onClicked: { Updater.skip(); root.close() }
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                visible: !root.busy
                text: root.done ? root._t("update_later") : root.failed ? root._t("close") : root._t("update_later")
                onClicked: root.close()
            }
            DialogButton {
                visible: root.failed
                text: root._t("update_open_page")
                onClicked: Updater.openReleasePage()
            }
            DialogButton {
                visible: !root.busy && !root.failed
                filled: true
                text: root.done ? root._t("update_restart")
                    : !Updater.canInstall ? root._t("update_open_page")
                    : root.arch ? root._t("update_fetch_install")
                    : root._t("update_install")
                onClicked: {
                    if (root.done) Updater.restart()
                    else Updater.install()
                }
            }
        }
    }

    component DialogButton: Rectangle {
        id: b
        property string text
        property bool filled: false
        signal clicked()
        implicitHeight: 40
        implicitWidth: lbl.implicitWidth + 48
        radius: 20
        color: filled ? (ma.pressed ? Qt.darker(ThemeManager.primary, 1.12) : ThemeManager.primary)
                      : (ma.containsMouse ? Qt.alpha(ThemeManager.primary, 0.10) : "transparent")
        Label {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: b.filled ? ThemeManager.onPrimary : ThemeManager.primary
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }
}
