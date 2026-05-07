#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include "ThemeManager.h"
#include "FileScanner.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    app.setOrganizationName("Kader");
    app.setOrganizationDomain("kader.app");
    app.setApplicationName("Kader");
    app.setWindowIcon(QIcon(":/assets/icon.svg"));

    ThemeManager themeManager;
    FileScanner fileScanner;

    QQmlApplicationEngine engine;

    // Add QmlMaterial to import paths
    engine.addImportPath("qrc:/");
    engine.addImportPath(app.applicationDirPath() + "/lib/QmlMaterial");
    // Also check current source dir for development
    engine.addImportPath(QString(CMAKE_SOURCE_DIR) + "/lib/QmlMaterial");

    engine.rootContext()->setContextProperty("ThemeManager", &themeManager);
    engine.rootContext()->setContextProperty("FileScanner", &fileScanner);

    const QUrl url(u"qrc:/qml/main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
