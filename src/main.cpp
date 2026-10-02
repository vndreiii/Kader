#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QIcon>
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QtConcurrent>
#include <QTimer>
#include <QFileSystemWatcher>
#include <QDir>
#include <QElapsedTimer>
#include <cstdio>
#include <algorithm>
#include "ThemeManager.h"
#include "FileScanner.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include "ThumbnailProvider.h"
#include "MediaModel.h"
#include "LibraryAnalyzer.h"
#include "TimelineModel.h"
#include "AlbumModel.h"
#include "VideoEditor.h"
#include "SettingsManager.h"
#include "StorageManager.h"
#include "SemanticSearchEngine.h"
#include "GlobeItem.h"
#include "UpdateManager.h"
#include "AppPaths.h"
#if KADER_HAVE_MILFS
#include <MilfsConnect/Connect.h>
#endif

// KADER_TRACE_STARTUP=1 prints milestones of the cold start to stderr.
static QElapsedTimer g_startClock;
static bool g_traceStartup = false;
static void trace(const char *what) {
    if (g_traceStartup)
        fprintf(stderr, "[startup] %6lld ms  %s\n", static_cast<long long>(g_startClock.elapsed()), what);
}
static void traceFirstFrame(QQmlApplicationEngine &engine) {
    if (!g_traceStartup)
        return;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, [](QObject *obj, const QUrl &) {
        trace("root object created");
        if (auto *w = qobject_cast<QQuickWindow *>(obj))
            QObject::connect(w, &QQuickWindow::frameSwapped, w, [] { trace("first frame on screen"); },
                             Qt::SingleShotConnection);
    });
}


// Whether the desktop expects apps to draw their own window buttons. Kader's
// windows are frameless, so on GNOME, KDE, Windows & co. it draws
// minimise/maximise/close; tiling and standalone window managers (Hyprland,
// niri, sway, i3, …) manage windows from the keyboard and get none.
static bool systemWantsWindowButtons() {
#ifdef Q_OS_WIN
    return true;
#else
    for (const char *var : {"HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET", "SWAYSOCK", "I3SOCK"})
        if (qEnvironmentVariableIsSet(var))
            return false;
    const QString desktop = (qEnvironmentVariable("XDG_CURRENT_DESKTOP") + QLatin1Char(':') +
                             qEnvironmentVariable("XDG_SESSION_DESKTOP")).toLower();
    static const char *const tiling[] = {"hyprland", "niri", "sway", "river", "i3", "bspwm", "dwm", "qtile",
                                         "awesome", "xmonad", "herbstluftwm", "spectrwm", "leftwm", "dwl",
                                         "cosmic-comp", "pop-shell", "miracle-wm", "mango"};
    for (const char *wm : tiling)
        if (desktop.contains(QLatin1String(wm)))
            return false;
    // no desktop environment advertised: a bare window manager
    return desktop != QLatin1String(":");
#endif
}

// KADER_SMOKE_TEST=1 (CI, packaged builds): load the UI, open every view,
// check the world data, and exit non-zero on any QML error — catches a
// missing Qt module or plugin in a packaged build.
static int g_qmlProblems = 0;
static QtMessageHandler g_prevHandler = nullptr;
static void smokeMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg) {
    if (type != QtDebugMsg && type != QtInfoMsg
        && (msg.contains(QLatin1String(".qml:")) || msg.contains(QLatin1String("is not installed"))
            || msg.contains(QLatin1String("Cannot load library")))) {
        ++g_qmlProblems;
        // Windows GUI apps send Qt messages to the debugger, so print the
        // ones that fail the test where CI can see them.
        fprintf(stderr, "smoke test problem: %s\n", qPrintable(msg));
        fflush(stderr);
    }
    if (g_prevHandler)
        g_prevHandler(type, ctx, msg);
}

static int runSmokeTest(QGuiApplication &app, QQmlApplicationEngine &engine) {
    if (engine.rootObjects().isEmpty()) {
        fprintf(stderr, "smoke test: main.qml did not load\n");
        return 1;
    }
    if (!kaderWorld().result()) {
        fprintf(stderr, "smoke test: world.kgeo not found or unreadable\n");
        return 2;
    }
    QObject *root = engine.rootObjects().constFirst();
    const QStringList views = {QStringLiteral("albums"), QStringLiteral("search"), QStringLiteral("map"),
                               QStringLiteral("settings"), QStringLiteral("videos"), QStringLiteral("timeline")};
    for (int i = 0; i < views.size(); ++i)
        QTimer::singleShot(800 * (i + 1), root, [root, view = views[i]] {
            QMetaObject::invokeMethod(root, "switchView", Q_ARG(QVariant, view));
        });
    QTimer::singleShot(800 * (views.size() + 2), &app, [&app] {
        fprintf(stderr, "smoke test: %d QML problem(s)\n", g_qmlProblems);
        app.exit(g_qmlProblems ? 3 : 0);
    });
    return app.exec();
}

int main(int argc, char *argv[]) {
    if (qEnvironmentVariableIsSet("KADER_SMOKE_TEST"))
        g_prevHandler = qInstallMessageHandler(smokeMessageHandler);
    g_startClock.start();
    g_traceStartup = qEnvironmentVariableIsSet("KADER_TRACE_STARTUP");
#ifndef Q_OS_WIN
    // Prefer Qt's FFmpeg multimedia backend over GStreamer for better codec
    // compatibility and stability (avoids GStreamer plugin crashes on VAAPI/VDPAU).
    // (Windows picks FFmpeg by default and falls back to Media Foundation.)
    if (qgetenv("QT_MEDIA_BACKEND").isEmpty())
        qputenv("QT_MEDIA_BACKEND", "ffmpeg");
#endif

    // Kader draws its own Material 3 controls on top of Qt Quick Controls,
    // which needs a style that allows customisation. The platform default
    // doesn't on Windows (native style) and can differ on KDE, so pin
    // Fusion everywhere — what most Linux desktops already use.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE"))
        qputenv("QT_QUICK_CONTROLS_STYLE", "Fusion");

    // The frameless ApplicationWindow renders its own rounded-corner
    // background in QML; without an alpha-enabled surface the window itself
    // stays an opaque rectangle, showing through as a white border/corners
    // around the rounded content. Must be called before QGuiApplication.
    QQuickWindow::setDefaultAlphaBuffer(true);

    QGuiApplication app(argc, argv);
    trace("QGuiApplication");
    AppPaths::init();

    // File passed on the command line (e.g. "kader /path/to/photo.jpg" or via .desktop %U)
    QString startupFile;
    {
        QStringList args = app.arguments();
        if (args.size() > 1) {
            QString arg = args[1];
            if (arg.startsWith("file://"))
                arg = QUrl(arg).toLocalFile();
            if (QFile::exists(arg))
                // Canonicalise to an absolute path so it matches the entries
                // returned by FileScanner::listSiblingMedia (folder browsing).
                startupFile = QFileInfo(arg).absoluteFilePath();
        }
    }

    app.setOrganizationName("Kader");
    app.setOrganizationDomain("kader.app");
    app.setApplicationName("Kader");
    app.setApplicationVersion(QStringLiteral(KADER_VERSION));
    // Pre-sized icons, registered with their sizes so Qt decodes only the one
    // the platform asks for (the 2183px master took ~40% of QML load time).
    {
        QIcon icon;
        for (int px : {48, 128, 256})
            icon.addFile(QStringLiteral(":/Kader/assets/icons/kader-%1.png").arg(px), QSize(px, px));
        app.setWindowIcon(icon);
    }
    app.setDesktopFileName(QStringLiteral("kader"));

    qmlRegisterType<GlobeItem>("Kader.Globe", 1, 0, "Globe");

    // ── Standalone-viewer fast path ───────────────────────────────────────
    // When launched with a file (e.g. from a file manager), show ONLY that
    // image/video and let the user scroll through the rest of its folder. None
    // of the gallery backend (database, models, scanner, AI, thumbnailer) is
    // constructed — this keeps cold-open latency to an absolute minimum.
    if (!startupFile.isEmpty()) {
        SettingsManager settingsManager;
        ThemeManager    themeManager;
        VideoEditor     videoEditor;
        FileScanner     fileScanner(nullptr);   // only listSiblingMedia() is used; no DB needed

        trace("viewer backend");
        QQmlApplicationEngine engine;
        traceFirstFrame(engine);
        engine.addImportPath("qrc:/");
        engine.addImportPath(app.applicationDirPath() + "/qml_modules");
        engine.rootContext()->setContextProperty("Settings", &settingsManager);
        engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
        engine.rootContext()->setContextProperty("VideoEditor", &videoEditor);
        engine.rootContext()->setContextProperty("FileScanner", &fileScanner);
        engine.rootContext()->setContextProperty("STARTUP_FILE", startupFile);
        engine.rootContext()->setContextProperty("SYSTEM_WINDOW_BUTTONS", systemWantsWindowButtons());

        const QUrl url(QStringLiteral("qrc:/Kader/qml/views/ViewerWindow.qml"));
        QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                         &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        }, Qt::QueuedConnection);
        engine.load(url);
        return app.exec();
    }

    DatabaseManager dbManager;
    SettingsManager settingsManager;
    ThemeManager themeManager;
    StorageManager storageManager(&dbManager);
    ThumbnailGenerator thumbGenerator;
    SemanticSearchEngine semanticSearch(&dbManager, &thumbGenerator);
    LibraryAnalyzer analyzer(&dbManager, &thumbGenerator);
    FileScanner fileScanner(&dbManager);
    fileScanner.setThumbnailGenerator(&thumbGenerator);

#if KADER_HAVE_MILFS
    // Sibling-app integration (see milfs-connect): ingest media announced by
    // other apps (e.g. Recamara) live, without waiting for the next startup scan.
    MilfsConnect::Bus bus(QStringLiteral("kader"));
    bus.subscribe([&](const QString &, const QString &eventType, const QVariantMap &payload) {
        if (eventType != QStringLiteral("media.added"))
            return;
        const QString path = payload.value(QStringLiteral("path")).toString();
        if (path.isEmpty() || !QFile::exists(path))
            return;
        const QString dir = QFileInfo(path).absolutePath();
        const QStringList indexedDirs = dbManager.getIndexedDirectoryPaths();
        const bool alreadyIndexed = std::any_of(indexedDirs.begin(), indexedDirs.end(), [&](const QString &indexed) {
            return dir == indexed || dir.startsWith(indexed + "/");
        });
        if (!alreadyIndexed)
            dbManager.addIndexedDirectory(dir);
        fileScanner.startScan(dir);
    });
#endif
    UpdateManager updater(&settingsManager);
    updater.start();

    MediaModel mediaModel(&dbManager, &thumbGenerator);
    TimelineModel timelineModel(&dbManager);
    AlbumModel albumModel(&dbManager, &thumbGenerator);
    VideoEditor videoEditor;

    // In vieweronly mode we only display a single file — skip all heavy startup work.
    const bool viewerOnly = !startupFile.isEmpty();

    // Refreshing the models is three full-table queries plus an O(n) mosaic
    // relayout, all on the GUI thread. Scans finish once per indexed directory
    // and milfs-connect starts a scan per announced file, so refreshing eagerly
    // meant one multi-hundred-millisecond stall per scan, back to back. Funnel
    // every request through one single-shot timer instead: a burst of scans
    // collapses into a single refresh once the burst settles.
    QTimer *refreshTimer = new QTimer(&app);
    refreshTimer->setSingleShot(true);
    refreshTimer->setInterval(500);

    // Kick off a thumbnail cache build. getAllMediaPaths() is a full-table query
    // and startCacheBuilding() then stats every path, so both go off-thread.
    auto rebuildThumbnailCache = [&]() {
        if (viewerOnly)
            return;
        QtConcurrent::run([&]() {
            thumbGenerator.startCacheBuilding(dbManager.getAllMediaPaths(), 768);
        });
    };

    // The flat MediaModel only backs the dashboard; leave it empty until that
    // has loaded it once.
    auto refreshMediaModel = [&]() {
        if (mediaModel.rowCount() > 0)
            mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
    };

    QObject::connect(refreshTimer, &QTimer::timeout, &app, [&]() {
        refreshMediaModel();
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
        albumModel.refresh(true);
        storageManager.refresh();
        rebuildThumbnailCache();
    });

    // Prune helper: runs off-thread, refreshes models on main thread if anything was removed.
    auto runPrune = [&]() {
        QtConcurrent::run([&]() {
            int pruned = dbManager.pruneOrphanedMedia();
            if (pruned > 0)
                QMetaObject::invokeMethod(refreshTimer, qOverload<>(&QTimer::start), Qt::QueuedConnection);
        });
    };

    if (!viewerOnly) {
        // Auto-load semantic model in background if already downloaded.
        if (semanticSearch.modelsPresent()) {
            QTimer::singleShot(2500, &app, [&]() {
                semanticSearch.loadModel();
            });
        }

        // Auto-scan (Settings → Library): scan the indexed folders at startup,
        // when a watched folder changes, and every 10 minutes (no-op rescans
        // take milliseconds and don't refresh anything).
        auto scanAll = [&]() {
            for (const QVariant &dir : dbManager.getIndexedDirectories()) {
                const QString path = dir.toMap().value("path").toString();
                if (!path.isEmpty())
                    fileScanner.startScan(path);
            }
        };
        auto *folderWatcher = new QFileSystemWatcher(&app);
        auto *watchDebounce = new QTimer(&app);
        watchDebounce->setSingleShot(true);
        watchDebounce->setInterval(3000);
        QObject::connect(watchDebounce, &QTimer::timeout, &app, [&, scanAll]() {
            if (settingsManager.autoScan())
                scanAll();
        });
        QObject::connect(folderWatcher, &QFileSystemWatcher::directoryChanged, watchDebounce,
                         qOverload<>(&QTimer::start));
        // Indexed roots and their direct subfolders (album folders); inotify
        // watches are a shared resource, so this stays bounded.
        auto rewatch = [&dbManager, folderWatcher]() {
            if (!folderWatcher->directories().isEmpty())
                folderWatcher->removePaths(folderWatcher->directories());
            QStringList paths;
            for (const QVariant &dir : dbManager.getIndexedDirectories()) {
                const QString root = dir.toMap().value("path").toString();
                if (root.isEmpty())
                    continue;
                paths << root;
                const QStringList subs = QDir(root).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
                for (const QString &sub : subs) {
                    if (paths.size() >= 512)
                        break;
                    paths << root + QLatin1Char('/') + sub;
                }
            }
            if (!paths.isEmpty())
                folderWatcher->addPaths(paths);
        };
        QTimer::singleShot(800, &app, [&, scanAll, rewatch]() {
            if (settingsManager.autoScan()) {
                scanAll();
                rewatch();
            }
        });
        auto *rescanTimer = new QTimer(&app);
        rescanTimer->setInterval(10 * 60 * 1000);
        QObject::connect(rescanTimer, &QTimer::timeout, &app, [&, scanAll]() {
            if (settingsManager.autoScan())
                scanAll();
        });
        rescanTimer->start();
        QObject::connect(&settingsManager, &SettingsManager::autoScanChanged, &app, [&, scanAll, rewatch, folderWatcher]() {
            if (settingsManager.autoScan()) {
                scanAll();
                rewatch();
            } else if (!folderWatcher->directories().isEmpty()) {
                folderWatcher->removePaths(folderWatcher->directories());
            }
        });

        // Trash retention: purge items older than the chosen period at
        // startup, daily, and when the period is shortened.
        auto purgeTrash = [&]() {
            const int days = settingsManager.trashRetentionDays();
            if (days > 0 && dbManager.purgeTrash(days) > 0)
                refreshTimer->start();
        };
        QTimer::singleShot(10000, &app, purgeTrash);
        auto *purgeTimer = new QTimer(&app);
        purgeTimer->setInterval(24 * 60 * 60 * 1000);
        QObject::connect(purgeTimer, &QTimer::timeout, &app, purgeTrash);
        purgeTimer->start();
        QObject::connect(&settingsManager, &SettingsManager::trashRetentionDaysChanged, &app, purgeTrash);

        // Colour (and, when enabled, face) analysis of new media, in the
        // background once the UI has settled and the startup scan is done.
        QTimer::singleShot(6000, &app, [&]() { analyzer.start(); });

        // Pre-generate 768px disk thumbnails for all known media.
        // Runs after a short delay so the UI renders first.
        QTimer::singleShot(1500, &app, rebuildThumbnailCache);

        // Run once at startup, then every 30 minutes to catch external file deletions.
        runPrune();
        QTimer *pruneTimer = new QTimer(&app);
        pruneTimer->setInterval(30 * 60 * 1000);  // scans prune their own roots; this catches the rest
        QObject::connect(pruneTimer, &QTimer::timeout, &app, runPrune);
        pruneTimer->start();

    }

    // Saved RAW filter and mosaic density go in before the first refresh, so
    // the timeline is queried and laid out once instead of three times.
    dbManager.setRawFilter(settingsManager.rawFilter());
    {
        int d = settingsManager.mosaicDensity();
        timelineModel.setNumColumns(7 - std::max(1, std::min(d, 4)));  // 1→6 … 4→3 columns
    }

    // Initial refresh runs once the window has shown its first frame (see
    // below), so the user sees the loading skeleton immediately instead of a
    // window that appears only after the library query. The flat MediaModel
    // only backs the dashboard, which loads it when first opened.
    auto initialRefresh = [&]() {
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
        albumModel.refresh(true);
    };

    // Context object (&app) ensures the lambda runs on the main thread via a queued connection.
    // Restarting the timer coalesces the scans of several indexed directories
    // into one refresh (which also re-runs the cache builder for the new files).
    QObject::connect(&fileScanner, &FileScanner::libraryChanged, &app,
                     [refreshTimer, &analyzer](const QString &) {
        refreshTimer->start();
        analyzer.start();
    });

    // Apply the resource budget: bounds CPU (scan threads, thumbnail concurrency)
    // and RAM (libvips cache) so background work can't saturate the machine.
    auto applyResourceBudget = [&]() {
        int threads = settingsManager.workerThreads();
        int mode = settingsManager.resourceMode();
        thumbGenerator.setResourceBudget(threads);
        fileScanner.setMaxThreads(threads);
        semanticSearch.setResourceBudget(mode);
        analyzer.setResourceBudget(threads);
    };
    applyResourceBudget();
    QObject::connect(&settingsManager, &SettingsManager::resourceModeChanged, &app, applyResourceBudget);

    // Apply saved parallel thumbnail mode (must come after the budget so the
    // libvips concurrency is sized correctly for the chosen mode).
    thumbGenerator.setParallelMode(settingsManager.parallelThumbnails());
    QObject::connect(&settingsManager, &SettingsManager::parallelThumbnailsChanged, [&]() {
        thumbGenerator.setParallelMode(settingsManager.parallelThumbnails());
    });

    // Handle settings changes
    QObject::connect(&settingsManager, &SettingsManager::hideIgnoredInTimelineChanged, [&]() {
        refreshMediaModel();
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
    });
    QObject::connect(&settingsManager, &SettingsManager::mosaicDensityChanged, &app, [&]() {
        int d = settingsManager.mosaicDensity();
        timelineModel.setNumColumns(7 - std::max(1, std::min(d, 4)));  // 1→6 … 4→3 columns
    });
    QObject::connect(&settingsManager, &SettingsManager::rawFilterChanged, &app, [&]() {
        dbManager.setRawFilter(settingsManager.rawFilter());
        refreshMediaModel();
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
    });

    trace("gallery backend");
    QQmlApplicationEngine engine;
    traceFirstFrame(engine);

    // Register the encrypted thumbnail image provider.
    engine.addImageProvider("thumbnails", new ThumbnailProvider(&dbManager, &thumbGenerator));
    engine.addImageProvider("faces", new FaceImageProvider(&analyzer));

    engine.addImportPath("qrc:/");
    engine.addImportPath(app.applicationDirPath() + "/qml_modules");

    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("StorageManager", &storageManager);
    engine.rootContext()->setContextProperty("FileScanner", &fileScanner);
    engine.rootContext()->setContextProperty("DB", &dbManager);
    engine.rootContext()->setContextProperty("Settings", &settingsManager);
    engine.rootContext()->setContextProperty("MediaModel", &mediaModel);
    engine.rootContext()->setContextProperty("TimelineModel", &timelineModel);
    engine.rootContext()->setContextProperty("AlbumModel", &albumModel);
    engine.rootContext()->setContextProperty("VideoEditor", &videoEditor);
    engine.rootContext()->setContextProperty("ThumbGen", &thumbGenerator);
    engine.rootContext()->setContextProperty("STARTUP_FILE", startupFile);
    engine.rootContext()->setContextProperty("AI", &semanticSearch);
    engine.rootContext()->setContextProperty("SYSTEM_WINDOW_BUTTONS", systemWantsWindowButtons());
    engine.rootContext()->setContextProperty("Analyzer", &analyzer);
    engine.rootContext()->setContextProperty("Updater", &updater);

    const QUrl url(QStringLiteral("qrc:/Kader/qml/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    // First library query after the first frame (queued, so it runs on the
    // GUI thread once the frame is out).
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [&](QObject *obj, const QUrl &) {
        auto *w = qobject_cast<QQuickWindow *>(obj);
        if (!w) {
            initialRefresh();
            return;
        }
        QObject::connect(w, &QQuickWindow::frameSwapped, &app, initialRefresh,
                         static_cast<Qt::ConnectionType>(Qt::QueuedConnection | Qt::SingleShotConnection));
    });
    engine.load(url);

    if (qEnvironmentVariableIsSet("KADER_SMOKE_TEST"))
        return runSmokeTest(app, engine);
    return app.exec();
}
