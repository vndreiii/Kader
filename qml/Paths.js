.pragma library

// Local paths <-> file URLs that work on Linux ("/home/a/b.jpg") and Windows
// ("C:/Users/a/b.jpg", "//server/share/b.jpg"). Paths in Kader always use
// forward slashes (Qt's convention on every platform).

// Path -> URL for Image.source, Qt.openUrlExternally, … Anything that already
// is a URL (file://, image://, qrc:, http…) is returned unchanged.
function fileUrl(p) {
    if (!p)
        return ""
    p = String(p)
    if (/^[A-Za-z][A-Za-z0-9+.-]+:/.test(p) && !/^[A-Za-z]:[\/\\]/.test(p))
        return p
    p = p.replace(/\\/g, "/")
    // encode each segment so '#', '?' and '%' in file names survive
    var enc = p.split("/").map(encodeURIComponent).join("/").replace(/^([A-Za-z])%3A/, "$1:")
    if (p.indexOf("//") === 0)
        return "file:" + enc            // UNC: //server/share/…
    return p.charAt(0) === "/" ? "file://" + enc : "file:///" + enc
}

// URL (e.g. from a FileDialog/FolderDialog) -> local path with forward slashes.
function localPath(u) {
    if (!u)
        return ""
    u = String(u)
    if (u.indexOf("file:") !== 0)
        return u
    var s = u.replace(/^file:(\/\/(localhost)?)?/, "")
    if (s.indexOf("/") !== 0)
        s = "//" + s                    // file://server/share → //server/share
    s = decodeURIComponent(s)
    if (/^\/[A-Za-z]:/.test(s))
        s = s.substring(1)              // /C:/… → C:/…
    return s
}

// Last path component ("C:/a/b.jpg" → "b.jpg").
function fileName(p) {
    p = String(p || "").replace(/\\/g, "/").replace(/\/+$/, "")
    return p.substring(p.lastIndexOf("/") + 1)
}
