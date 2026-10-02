#pragma once

#include <QString>

// Where Kader keeps its files, per platform and install type.
//
// Normally the platform's per-user locations (XDG dirs on Linux,
// %LOCALAPPDATA%\Kader on Windows). A portable install — a `portable.txt`
// file next to the executable, as shipped in the Windows portable .zip —
// keeps everything in a `data` folder beside the program instead, so the
// whole folder can live on a USB stick.
namespace AppPaths {

// Call once right after the Q(Gui)Application is constructed.
void init();

bool portable();

QString dataDir();      // library database
QString localDataDir(); // downloaded AI models
QString cacheDir();     // thumbnails, staged updates
QString configDir();    // settings.json

// An external helper program (ffmpeg, ffprobe, …): the copy bundled next to
// the executable first, then PATH. Empty when it isn't available.
QString tool(const QString &name);

// Native separators for showing a path to the user ("C:\Users\…" on Windows).
QString displayPath(const QString &path);

// Open the system file manager with `filePath` selected (Explorer on
// Windows, the freedesktop FileManager1 service on Linux), falling back to
// opening the containing folder.
void revealInFileManager(const QString &filePath);

// Lower the calling thread's CPU (and on Windows, I/O) priority for
// background work; restoreThreadPriority() undoes it.
void lowerThreadPriority();
void restoreThreadPriority();

} // namespace AppPaths
