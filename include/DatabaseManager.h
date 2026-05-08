#pragma once

#include <QObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QVariantList>
#include <QString>
#include <QDateTime>

class DatabaseManager : public QObject {
    Q_OBJECT
public:
    explicit DatabaseManager(QObject *parent = nullptr);
    ~DatabaseManager();

    bool openDatabase();
    
    // CRUD operations for media
    bool addOrUpdateMedia(const QString &filePath, const QString &hash, 
                         qint64 size, const QString &mimeType, 
                         const QDateTime &creationDate, int width, int height);

    // Get all media for the models
    QVariantList getAllMedia(bool hideIgnored = true);

    // Get automatically grouped albums (by folder)
    QVariantList getAlbums(bool hideIgnored = true);

    // Ignore an album and its items
    Q_INVOKABLE bool ignoreAlbum(const QString &folderPath, bool ignore = true);

    // Check if a file is already in the database and its modification time
    bool needsUpdate(const QString &filePath, qint64 size);

private:
    bool createTables();
    void checkConnection();
    QSqlDatabase m_db;
    QString m_dbPath;
};
