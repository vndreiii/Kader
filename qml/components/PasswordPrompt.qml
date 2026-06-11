import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../I18n.js" as I18n

// Modal password prompt for the Hidden section.
// Emits accepted() on correct password or first-time setup.
// Emits rejected() if the user dismisses without success.
Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.alpha("black", 0.55)
    z: 300
    visible: false

    signal accepted()
    signal rejected()

    property bool _settingUp: false  // true when no password is set yet (first visit)

    function open() {
        _settingUp = !DB.hasHiddenPassword()
        pinInput.text = ""
        confirmInput.text = ""
        errorLabel.text = ""
        visible = true
        Qt.callLater(function() { pinInput.forceActiveFocus() })
    }

    function close() {
        visible = false
        pinInput.text = ""
        confirmInput.text = ""
        errorLabel.text = ""
    }

    MouseArea { anchors.fill: parent; onClicked: { close(); root.rejected() } }

    Rectangle {
        anchors.centerIn: parent
        width: 360
        height: promptCol.implicitHeight + 48
        radius: 28
        color: ThemeManager.surfaceContainerHigh
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: promptCol
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 28
            spacing: 16

            M3Icon {
                Layout.alignment: Qt.AlignHCenter
                name: "lock"; size: 40
                color: ThemeManager.primary
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root._settingUp ? "Create a PIN" : "Enter your PIN"
                font.pixelSize: 20; font.weight: Font.Medium
                color: ThemeManager.onSurface
            }
            Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                text: root._settingUp
                      ? "Set a PIN to protect your hidden photos."
                      : "Enter your PIN to view hidden photos."
                font.pixelSize: 13; color: ThemeManager.onSurfaceVariant
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            TextField {
                id: pinInput
                Layout.fillWidth: true
                placeholderText: root._settingUp ? "New PIN" : "PIN"
                echoMode: TextInput.Password
                font.pixelSize: 16
                inputMethodHints: Qt.ImhDigitsOnly
                background: Rectangle {
                    radius: 12
                    color: ThemeManager.surfaceContainerHighest
                    border.color: pinInput.activeFocus ? ThemeManager.primary : ThemeManager.outline
                    border.width: pinInput.activeFocus ? 2 : 1
                }
                color: ThemeManager.onSurface
                leftPadding: 16; rightPadding: 16; topPadding: 14; bottomPadding: 14
                Keys.onReturnPressed: root._settingUp ? confirmInput.forceActiveFocus() : submitBtn.clicked()
            }

            TextField {
                id: confirmInput
                visible: root._settingUp
                Layout.fillWidth: true
                placeholderText: I18n.t(Settings.language, "confirm_pin")
                echoMode: TextInput.Password
                font.pixelSize: 16
                inputMethodHints: Qt.ImhDigitsOnly
                background: Rectangle {
                    radius: 12
                    color: ThemeManager.surfaceContainerHighest
                    border.color: confirmInput.activeFocus ? ThemeManager.primary : ThemeManager.outline
                    border.width: confirmInput.activeFocus ? 2 : 1
                }
                color: ThemeManager.onSurface
                leftPadding: 16; rightPadding: 16; topPadding: 14; bottomPadding: 14
                Keys.onReturnPressed: submitBtn.clicked()
            }

            Label {
                id: errorLabel
                Layout.fillWidth: true
                text: ""
                visible: text !== ""
                color: ThemeManager.error
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: errorLabel; property: "x"; from: 0; to: -8; duration: 50 }
                    NumberAnimation { target: errorLabel; property: "x"; from: -8; to: 8; duration: 50 }
                    NumberAnimation { target: errorLabel; property: "x"; from: 8; to: -8; duration: 50 }
                    NumberAnimation { target: errorLabel; property: "x"; from: -8; to: 0; duration: 50 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    background: Rectangle { radius: 20; color: ThemeManager.surfaceContainerHighest }
                    contentItem: Label {
                        text: I18n.t(Settings.language, "cancel"); color: ThemeManager.onSurface; font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        topPadding: 8; bottomPadding: 8
                    }
                    onClicked: { root.close(); root.rejected() }
                }

                Button {
                    id: submitBtn
                    Layout.fillWidth: true
                    background: Rectangle { radius: 20; color: ThemeManager.primary }
                    contentItem: Label {
                        text: root._settingUp ? "Set PIN" : "Unlock"
                        color: ThemeManager.onPrimary; font.pixelSize: 14; font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        topPadding: 8; bottomPadding: 8
                    }
                    onClicked: {
                        var pin = pinInput.text.trim()
                        if (pin.length < 4) {
                            errorLabel.text = "PIN must be at least 4 digits."
                            shakeAnim.restart()
                            return
                        }
                        if (root._settingUp) {
                            if (pin !== confirmInput.text.trim()) {
                                errorLabel.text = "PINs do not match."
                                shakeAnim.restart()
                                return
                            }
                            DB.setHiddenPassword(pin)
                            root.close()
                            root.accepted()
                        } else {
                            if (!DB.checkHiddenPassword(pin)) {
                                errorLabel.text = "Incorrect PIN."
                                shakeAnim.restart()
                                pinInput.text = ""
                                return
                            }
                            root.close()
                            root.accepted()
                        }
                    }
                }
            }

            Item { height: 4 }
        }
    }
}
