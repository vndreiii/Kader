#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QUrl>
#include <QFile>
#include <QtConcurrent>
#include <QTimer>
#include "ThemeManager.h"
#include "FileScanner.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include "ThumbnailProvider.h"
#include "MediaModel.h"
#include "TimelineModel.h"
#include "AlbumModel.h"
#include "SettingsManager.h"
#include "StorageManager.h"

int main(int argc, char *argv[]) {
    // Prefer Qt's FFmpeg multimedia backend over GStreamer for better codec
    // compatibility and stability (avoids GStreamer plugin crashes on VAAPI/VDPAU).
    if (qgetenv("QT_MEDIA_BACKEND").isEmpty())
        qputenv("QT_MEDIA_BACKEND", "ffmpeg");

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
                startupFile = arg;
        }
    }

    app.setOrganizationName("Kader");
    app.setOrganizationDomain("kader.app");
    app.setApplicationName("Kader");
    app.setWindowIcon(QIcon(":/Kader/assets/icon.svg"));

    DatabaseManager dbManager;
    SettingsManager settingsManager;
    ThemeManager themeManager;
    StorageManager storageManager(&dbManager);
    ThumbnailGenerator thumbGenerator;
    FileScanner fileScanner(&dbManager);
    fileScanner.setThumbnailGenerator(&thumbGenerator);
    MediaModel mediaModel(&dbManager, &thumbGenerator);
    TimelineModel timelineModel(&dbManager);
    AlbumModel albumModel(&dbManager, &thumbGenerator);

    // Prune helper: runs off-thread, refreshes models on main thread if anything was removed.
    auto runPrune = [&]() {
        QtConcurrent::run([&]() {
            int pruned = dbManager.pruneOrphanedMedia();
            if (pruned > 0) {
                QMetaObject::invokeMethod(&app, [&]() {
                    mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
                    timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
                    albumModel.refresh(true);
                    storageManager.refresh();
                }, Qt::QueuedConnection);
            }
        });
    };

    // Auto-scan indexed directories on startup (delayed so UI loads first).
    QTimer::singleShot(800, &app, [&]() {
        QVariantList dirs = dbManager.getIndexedDirectories();
        for (const QVariant &dir : dirs) {
            QString path = dir.toMap().value("path").toString();
            if (!path.isEmpty())
                fileScanner.startScan(path);
        }
    });

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

    // Apply saved mosaic density
    {
        int d = settingsManager.mosaicDensity();
        timelineModel.setNumColumns(d == 1 ? 5 : d == 3 ? 3 : 4);
    }

    // Context object (&app) ensures the lambda runs on the main thread via a queued connection.
    QObject::connect(&fileScanner, &FileScanner::scanFinished, &app, [&](const QStringList &, int, double, const QString &) {
        mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
        albumModel.refresh(true);
        storageManager.refresh();
    });

    // Handle settings changes
    QObject::connect(&settingsManager, &SettingsManager::hideIgnoredInTimelineChanged, [&]() {
        mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
        timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
    });
    QObject::connect(&settingsManager, &SettingsManager::mosaicDensityChanged, &app, [&]() {
        int d = settingsManager.mosaicDensity();
        timelineModel.setNumColumns(d == 1 ? 5 : d == 3 ? 3 : 4);
    });

    QQmlApplicationEngine engine;

    // Register the encrypted thumbnail image provider.
    engine.addImageProvider("thumbnails", new ThumbnailProvider(&dbManager, &thumbGenerator));

    engine.addImportPath("qrc:/");
    engine.addImportPath(app.applicationDirPath() + "/qml_modules");
    engine.addImportPath(QString(CMAKE_SOURCE_DIR) + "/lib/QmlMaterial");

    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("StorageManager", &storageManager);
    engine.rootContext()->setContextProperty("FileScanner", &fileScanner);
    engine.rootContext()->setContextProperty("DB", &dbManager);
    engine.rootContext()->setContextProperty("Settings", &settingsManager);
    engine.rootContext()->setContextProperty("MediaModel", &mediaModel);
    engine.rootContext()->setContextProperty("TimelineModel", &timelineModel);
    engine.rootContext()->setContextProperty("AlbumModel", &albumModel);
    engine.rootContext()->setContextProperty("ThumbGen", &thumbGenerator);
    engine.rootContext()->setContextProperty("CMAKE_SOURCE_DIR", CMAKE_SOURCE_DIR);
    engine.rootContext()->setContextProperty("STARTUP_FILE", startupFile);

    const QUrl url(u"qrc:/Kader/qml/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
