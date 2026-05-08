#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include "ThemeManager.h"
#include "FileScanner.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include "MediaModel.h"
#include "TimelineModel.h"
#include "AlbumModel.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    app.setOrganizationName("Kader");
    app.setOrganizationDomain("kader.app");
    app.setApplicationName("Kader");
    app.setWindowIcon(QIcon(":/Kader/assets/icon.svg"));

    DatabaseManager dbManager;
    ThemeManager themeManager;
    ThumbnailGenerator thumbGenerator;
    FileScanner fileScanner(&dbManager);
    MediaModel mediaModel(&dbManager, &thumbGenerator);
    TimelineModel timelineModel(&dbManager);
    AlbumModel albumModel(&dbManager, &thumbGenerator);

    QObject::connect(&fileScanner, &FileScanner::scanFinished, &mediaModel, &MediaModel::refresh);
    QObject::connect(&fileScanner, &FileScanner::scanFinished, &timelineModel, &TimelineModel::refresh);
    QObject::connect(&fileScanner, &FileScanner::scanFinished, &albumModel, &AlbumModel::refresh);

    QQmlApplicationEngine engine;

    // Add QmlMaterial to import paths
    engine.addImportPath("qrc:/");
    engine.addImportPath(app.applicationDirPath() + "/qml_modules");
    // Also check current source dir for development
    engine.addImportPath(QString(CMAKE_SOURCE_DIR) + "/lib/QmlMaterial");

    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("FileScanner", &fileScanner);
    engine.rootContext()->setContextProperty("DB", &dbManager);
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
