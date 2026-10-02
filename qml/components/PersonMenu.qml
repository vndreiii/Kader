import QtQuick
import "../I18n.js" as I18n

// Right-click menu for a person (People row in Search, People page).
M3Menu {
    id: root
    property int personId: -1
    property bool hiddenPerson: false
    signal openRequested()
    signal renameRequested()

    M3MenuItem {
        iconName: "person"
        text: I18n.t(Settings.language, "person_open")
        onTriggered: root.openRequested()
    }
    M3MenuItem {
        iconName: "edit"
        text: I18n.t(Settings.language, "person_rename")
        onTriggered: root.renameRequested()
    }
    M3MenuItem {
        iconName: root.hiddenPerson ? "visibility" : "visibility_off"
        text: root.hiddenPerson ? I18n.t(Settings.language, "show_person") : I18n.t(Settings.language, "hide_person")
        onTriggered: Analyzer.setPersonHidden(root.personId, !root.hiddenPerson)
    }
    M3MenuSeparator {}
    M3MenuItem {
        iconName: "person_remove"
        destructive: true
        text: I18n.t(Settings.language, "person_forget")
        onTriggered: Analyzer.forgetPerson(root.personId)
    }
}
