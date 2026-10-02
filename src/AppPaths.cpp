#include "AppPaths.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QUrl>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QMutex>
#include <QSettings>
#include <QStandardPaths>

#include <cerrno>

#ifdef Q_OS_WIN
#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#else
#include <QDBusConnection>
#include <QDBusMessage>
#include <sys/resource.h>
#include <unistd.h>
#ifdef Q_OS_LINUX
#include <sys/syscall.h>
#endif
#endif

namespace AppPaths {

namespace {

QString appDir() {
    return QCoreApplication::applicationDirPath();
}

QString portableRoot() {
    return appDir() + QStringLiteral("/data");
}

QString ensure(const QString &dir) {
    QDir().mkpath(dir);
    return dir;
}

#ifndef Q_OS_WIN
// Per-thread nice value: on Linux setpriority(PRIO_PROCESS, tid) affects
// only that thread; elsewhere it would renice the whole process, so skip.
int currentTid() {
#ifdef Q_OS_LINUX
    return int(syscall(SYS_gettid));
#else
    return -1;
#endif
}
thread_local int t_savedNice = 0;
#endif

} // namespace

bool portable() {
    static const bool p = QFileInfo::exists(appDir() + QStringLiteral("/portable.txt"));
    return p;
}

void init() {
    if (portable()) {
        // QSettings (theme) follows the rest of the data into the folder.
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, ensure(configDir()));
    }
#ifdef Q_OS_WIN
    // HEIC/AVIF decoders are libheif plugins shipped in lib/libheif.
    const QString heifPlugins = appDir() + QStringLiteral("/lib/libheif");
    if (!qEnvironmentVariableIsSet("LIBHEIF_PLUGIN_PATH") && QFileInfo(heifPlugins).isDir())
        qputenv("LIBHEIF_PLUGIN_PATH", QDir::toNativeSeparators(heifPlugins).toLocal8Bit());
#endif
}

QString dataDir() {
    if (portable())
        return ensure(portableRoot());
#ifdef Q_OS_WIN
    // Local, not Roaming: the library database can be large.
    return ensure(QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation));
#else
    return ensure(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
#endif
}

QString localDataDir() {
    if (portable())
        return ensure(portableRoot());
    return ensure(QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation));
}

QString cacheDir() {
    if (portable())
        return ensure(portableRoot() + QStringLiteral("/cache"));
    return ensure(QStandardPaths::writableLocation(QStandardPaths::CacheLocation));
}

QString configDir() {
    if (portable())
        return ensure(portableRoot() + QStringLiteral("/config"));
    return ensure(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/kader"));
}

QString tool(const QString &name) {
    static QHash<QString, QString> cache;
    static QMutex mutex;
    QMutexLocker lock(&mutex);
    auto it = cache.constFind(name);
    if (it != cache.constEnd())
        return it.value();
#ifdef Q_OS_WIN
    const QString bundled = appDir() + QLatin1Char('/') + name + QStringLiteral(".exe");
#else
    const QString bundled = appDir() + QLatin1Char('/') + name;
#endif
    QString found = QFileInfo(bundled).isExecutable() ? bundled : QStandardPaths::findExecutable(name);
    cache.insert(name, found);
    return found;
}

QString displayPath(const QString &path) {
    return QDir::toNativeSeparators(path);
}

void revealInFileManager(const QString &filePath) {
    if (filePath.isEmpty())
        return;
#ifdef Q_OS_WIN
    const std::wstring native = QDir::toNativeSeparators(QFileInfo(filePath).absoluteFilePath()).toStdWString();
    const HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    bool shown = false;
    if (PIDLIST_ABSOLUTE item = ILCreateFromPathW(native.c_str())) {
        shown = SUCCEEDED(SHOpenFolderAndSelectItems(item, 0, nullptr, 0));
        ILFree(item);
    }
    if (SUCCEEDED(co))
        CoUninitialize();
    if (shown)
        return;
#else
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
        QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    msg << QStringList{QUrl::fromLocalFile(filePath).toString()} << QString();
    if (QDBusConnection::sessionBus().call(msg).type() != QDBusMessage::ErrorMessage)
        return;
#endif
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(filePath).absolutePath()));
}

void lowerThreadPriority() {
#ifdef Q_OS_WIN
    // Background mode lowers CPU, I/O and memory priority together.
    SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_BEGIN);
#else
    const int tid = currentTid();
    if (tid < 0)
        return;
    errno = 0;
    t_savedNice = getpriority(PRIO_PROCESS, id_t(tid));
    setpriority(PRIO_PROCESS, id_t(tid), 10);
#endif
}

void restoreThreadPriority() {
#ifdef Q_OS_WIN
    SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_END);
#else
    const int tid = currentTid();
    if (tid >= 0)
        setpriority(PRIO_PROCESS, id_t(tid), t_savedNice);
#endif
}

} // namespace AppPaths
