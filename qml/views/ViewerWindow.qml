import QtQuick
import QtQuick.Window
import "../components"
import "../Paths.js" as Paths

// Minimal standalone-viewer window. Used when Kader is launched with a file
// (e.g. from a file manager). It hosts only the ViewerOverlay and pulls in the
// rest of the opened file's folder so the user can scroll through siblings —
// none of the gallery backend (database, models, scanner, AI) is constructed.
Window {
    id: viewerWindow
    // Generous default size; the photo uses the whole window.
    width: Math.round(Screen.desktopAvailableWidth * 0.82)
    height: Math.round(Screen.desktopAvailableHeight * 0.86)
    visible: true
    color: "black"
    title: "Kader"
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property string _file: typeof STARTUP_FILE === "string" ? STARTUP_FILE : ""
    readonly property string _mime: /\.(mp4|mkv|mov|avi|webm)$/i.test(_file) ? "video/mp4"
                                  : /\.gif$/i.test(_file) ? "image/gif" : "image/jpeg"

    // First frame: just the photo, decoded straight to window size. The full
    // viewer (controls, info panel, video stack) is built asynchronously
    // behind it and takes over once ready, so opening a file from the file
    // manager shows the picture as soon as the window exists.
    Image {
        id: instant
        anchors.fill: parent
        visible: !overlayLoader.ready
        fillMode: Image.PreserveAspectFit
        autoTransform: true
        asynchronous: false
        cache: false
        source: viewerWindow._mime === "image/jpeg" && viewerWindow._file !== "" ? Paths.fileUrl(viewerWindow._file) : ""
        sourceSize: Qt.size(Math.ceil(Screen.width * Screen.devicePixelRatio),
                            Math.ceil(Screen.height * Screen.devicePixelRatio))
    }

    Loader {
        id: overlayLoader
        readonly property bool ready: status === Loader.Ready && item && item.active
        anchors.fill: parent
        asynchronous: true
        // By URL, not an inline component: the viewer's types and imports
        // (QtMultimedia, Controls) are then compiled off the critical path too.
        source: "qrc:/Kader/qml/views/ViewerOverlay.qml"
        onLoaded: { item.viewerOnlyMode = true; viewerWindow._start(item) }
    }
    WindowChrome { z: 100000; move: false }

    Component.onCompleted: if (_file === "") Qt.quit()

    function _start(viewerOverlay) {
        var fp = _file
        // A single-item model first so nothing waits on a directory listing.
        viewerOverlay.allItems = [{ file_path: fp, mime_type: _mime, id: -1, is_favorite: false, is_trashed: false }]
        viewerOverlay.currentIndex = 0
        viewerOverlay.mediaData = viewerOverlay.allItems[0]
        viewerOverlay.active = true
        viewerOverlay.forceActiveFocus()

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
