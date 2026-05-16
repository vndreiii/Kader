#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
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
    QGuiApplication app(argc, argv);

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
    MediaModel mediaModel(&dbManager, &thumbGenerator);
    TimelineModel timelineModel(&dbManager);
    AlbumModel albumModel(&dbManager, &thumbGenerator);

    // Initial refresh with settings
    mediaModel.refresh(settingsManager.hideIgnoredInTimeline());
    timelineModel.refresh(settingsManager.hideIgnoredInTimeline());
    albumModel.refresh(true); // Albums usually always hide ignored unless in settings

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

    const QUrl url(u"qrc:/Kader/qml/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
