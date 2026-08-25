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
#include <algorithm>
#include "ThemeManager.h"
#include "FileScanner.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include "ThumbnailProvider.h"
#include "MediaModel.h"
#include "TimelineModel.h"
#include "AlbumModel.h"
#include "VideoEditor.h"
#include "SettingsManager.h"
#include "StorageManager.h"
#include "SemanticSearchEngine.h"
#include <MilfsConnect/Connect.h>

int main(int argc, char *argv[]) {
    // Prefer Qt's FFmpeg multimedia backend over GStreamer for better codec
    // compatibility and stability (avoids GStreamer plugin crashes on VAAPI/VDPAU).
    if (qgetenv("QT_MEDIA_BACKEND").isEmpty())
        qputenv("QT_MEDIA_BACKEND", "ffmpeg");

    // The frameless ApplicationWindow renders its own rounded-corner
    // background in QML; without an alpha-enabled surface the window itself
    // stays an opaque rectangle, showing through as a white border/corners
    // around the rounded content. Must be called before QGuiApplication.
    QQuickWindow::setDefaultAlphaBuffer(true);

    QGuiApplication app(argc, argv);

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
    app.setWindowIcon(QIcon(":/Kader/assets/KaderPNGicon.png"));

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

        QQmlApplicationEngine engine;
        engine.addImportPath("qrc:/");
        engine.addImportPath(app.applicationDirPath() + "/qml_modules");
        engine.rootContext()->setContextProperty("Settings", &settingsManager);
        engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
        engine.rootContext()->setContextProperty("VideoEditor", &videoEditor);
        engine.rootContext()->setContextProperty("FileScanner", &fileScanner);
        engine.rootContext()->setContextProperty("STARTUP_FILE", startupFile);

        const QUrl url(u"qrc:/Kader/qml/views/ViewerWindow.qml"_qs);
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
    SemanticSearchEngine semanticSearch(&dbManager);
    ThumbnailGenerator thumbGenerator;
    FileScanner fileScanner(&dbManager);
    fileScanner.setThumbnailGenerator(&thumbGenerator);

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

    QObject::connect(refreshTimer, &QTimer::timeout, &app, [&]() {
        mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
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

        // Auto-scan indexed directories on startup (delayed so UI loads first).
        QTimer::singleShot(800, &app, [&]() {
            QVariantList dirs = dbManager.getIndexedDirectories();
            for (const QVariant &dir : dirs) {
                QString path = dir.toMap().value("path").toString();
                if (!path.isEmpty())
                    fileScanner.startScan(path);
            }
        });

        // Pre-generate 768px disk thumbnails for all known media.
        // Runs after a short delay so the UI renders first.
        QTimer::singleShot(1500, &app, rebuildThumbnailCache);

        // Run once at startup, then every 3 minutes to catch external file deletions.
        runPrune();
        QTimer *pruneTimer = new QTimer(&app);
        pruneTimer->setInterval(3 * 60 * 1000);
        QObject::connect(pruneTimer, &QTimer::timeout, &app, runPrune);
        pruneTimer->start();

        // Initial refresh with settings
        mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
        albumModel.refresh(true);
    }

    // Apply saved mosaic density
    {
        int d = settingsManager.mosaicDensity();
        timelineModel.setNumColumns(7 - std::max(1, std::min(d, 4)));  // 1→6 … 4→3 columns
    }

    // Apply saved RAW filter
    dbManager.setRawFilter(settingsManager.rawFilter());

    // Context object (&app) ensures the lambda runs on the main thread via a queued connection.
    // Restarting the timer coalesces the scans of several indexed directories
    // into one refresh (which also re-runs the cache builder for the new files).
    QObject::connect(&fileScanner, &FileScanner::scanFinished, &app,
                     [refreshTimer](int, int, double, const QString &) {
        refreshTimer->start();
    });

    // Apply the resource budget: bounds CPU (scan threads, thumbnail concurrency)
    // and RAM (libvips cache) so background work can't saturate the machine.
    auto applyResourceBudget = [&]() {
        int threads = settingsManager.workerThreads();
        int mode = settingsManager.resourceMode();
        thumbGenerator.setResourceBudget(threads);
        fileScanner.setMaxThreads(threads);
        semanticSearch.setResourceBudget(mode);
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
        mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
    });
    QObject::connect(&settingsManager, &SettingsManager::mosaicDensityChanged, &app, [&]() {
        int d = settingsManager.mosaicDensity();
        timelineModel.setNumColumns(7 - std::max(1, std::min(d, 4)));  // 1→6 … 4→3 columns
    });
    QObject::connect(&settingsManager, &SettingsManager::rawFilterChanged, &app, [&]() {
        dbManager.setRawFilter(settingsManager.rawFilter());
        mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
    });

    QQmlApplicationEngine engine;

    // Register the encrypted thumbnail image provider.
    engine.addImageProvider("thumbnails", new ThumbnailProvider(&dbManager, &thumbGenerator));

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
    engine.rootContext()->setContextProperty("CMAKE_SOURCE_DIR", CMAKE_SOURCE_DIR);
    engine.rootContext()->setContextProperty("STARTUP_FILE", startupFile);
    engine.rootContext()->setContextProperty("AI", &semanticSearch);

    const QUrl url(u"qrc:/Kader/qml/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
