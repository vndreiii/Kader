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
                         const QDateTime &creationDate, int width, int height,
                         double latitude = 0.0, double longitude = 0.0);

    // Returns [{file_path, latitude, longitude, photo_count, thumb_path}] grouped ~1km.
    Q_INVOKABLE QVariantList getGeotaggedLocations();

    // Get all media for the models
    QVariantList getAllMedia(bool hideIgnored = true);

    // Get automatically grouped albums (by folder)
    QVariantList getAlbums(bool hideIgnored = true);

    // Ignore an album and its items
    Q_INVOKABLE bool ignoreAlbum(const QString &folderPath, bool ignore = true);

    // Indexed Directories
    Q_INVOKABLE QVariantList getIndexedDirectories();
    Q_INVOKABLE bool addIndexedDirectory(const QString &path);
    Q_INVOKABLE bool removeIndexedDirectory(const QString &path);
    bool updateDirectoryStats(const QString &path, int count);

    // Returns true if the file needs (re-)indexing: new, size changed, or missing EXIF.
    bool needsUpdate(const QString &filePath, qint64 size);

    // Encrypted thumbnail blob storage
    QByteArray getThumbnailBlob(const QString &filePath, int size); // non-const: calls checkConnection()
    bool storeThumbnailBlob(const QString &filePath, int size, const QByteArray &encryptedBlob);

    // Media actions
    Q_INVOKABLE bool toggleFavorite(int mediaId);
    Q_INVOKABLE bool setTrashed(int mediaId, bool trashed);
    Q_INVOKABLE bool deleteMediaPermanently(int mediaId);
    Q_INVOKABLE QVariantMap getMediaById(int mediaId);

    // Album actions
    Q_INVOKABLE bool pinAlbum(const QString &folderPath, bool pinned);
    Q_INVOKABLE bool trashAlbum(const QString &folderPath);

    // Remove media rows for files that no longer exist on disk. Returns count pruned.
    Q_INVOKABLE int pruneOrphanedMedia();

    // Storage stats
    Q_INVOKABLE qint64 getTotalMediaSizeBytes();

private:
    bool createTables();
    void checkConnection();
    QSqlDatabase m_db;
    QString m_dbPath;
};
