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

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    app.setOrganizationName("Kader");
    app.setOrganizationDomain("kader.app");
    app.setApplicationName("Kader");
    app.setWindowIcon(QIcon(":/assets/icon.svg"));

    DatabaseManager dbManager;
    ThemeManager themeManager;
    ThumbnailGenerator thumbGenerator;
    FileScanner fileScanner(&dbManager);
    MediaModel mediaModel(&dbManager, &thumbGenerator);
    TimelineModel timelineModel(&dbManager);

    QObject::connect(&fileScanner, &FileScanner::scanFinished, &mediaModel, &MediaModel::refresh);
    QObject::connect(&fileScanner, &FileScanner::scanFinished, &timelineModel, &TimelineModel::refresh);

    QQmlApplicationEngine engine;

    // Add QmlMaterial to import paths
    engine.addImportPath("qrc:/");
    engine.addImportPath(app.applicationDirPath() + "/lib/QmlMaterial");
    // Also check current source dir for development
    engine.addImportPath(QString(CMAKE_SOURCE_DIR) + "/lib/QmlMaterial");

    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("FileScanner", &fileScanner);
    engine.rootContext()->setContextProperty("DB", &dbManager);
    engine.rootContext()->setContextProperty("MediaModel", &mediaModel);
    engine.rootContext()->setContextProperty("TimelineModel", &timelineModel);
    engine.rootContext()->setContextProperty("ThumbGen", &thumbGenerator);

    const QUrl url(u"qrc:/qml/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
