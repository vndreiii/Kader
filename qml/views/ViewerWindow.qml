import QtQuick
import QtQuick.Controls
import "../components"
import "../I18n.js" as I18n

// Minimal standalone-viewer window. Used when Kader is launched with a file
// (e.g. from a file manager). It hosts only the ViewerOverlay and pulls in the
// rest of the opened file's folder so the user can scroll through siblings —
// none of the gallery backend (database, models, scanner, AI) is constructed.
ApplicationWindow {
    id: viewerWindow
    width: 1480
    height: 940
    visible: true
    color: "black"
    title: "Kader"
    flags: Qt.Window | Qt.FramelessWindowHint

    ViewerOverlay {
        id: viewerOverlay
        anchors.fill: parent
        viewerOnlyMode: true
    }

    Component.onCompleted: {
        var fp = STARTUP_FILE
        if (typeof fp !== "string" || fp === "") { Qt.quit(); return }

        var mime = ""
        if (/\.(mp4|mkv|mov|avi|webm)$/i.test(fp)) mime = "video/mp4"
        else if (/\.gif$/i.test(fp))               mime = "image/gif"
        else                                       mime = "image/jpeg"

        // Paint the opened file immediately — a single-item model so nothing
        // blocks the first frame on a directory listing.
        viewerOverlay.allItems = [{ file_path: fp, mime_type: mime, id: -1, is_favorite: false, is_trashed: false }]
        viewerOverlay.currentIndex = 0
        viewerOverlay.mediaData = viewerOverlay.allItems[0]
        viewerOverlay.active = true

        // Then enumerate the rest of the folder off the critical path so the
        // user can scroll through siblings without reopening the app.
        Qt.callLater(() => {
            var siblings = FileScanner.listSiblingMedia(fp)
            if (!siblings || siblings.length <= 1) return
            var idx = -1
            for (var i = 0; i < siblings.length; i++) {
                if (siblings[i].file_path === fp) { idx = i; break }
            }
            if (idx < 0) return  // opened file not in listing — keep single item
            viewerOverlay.allItems = siblings
            viewerOverlay.currentIndex = idx
            viewerOverlay.mediaData = siblings[idx]
        })
    }
}
