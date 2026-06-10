#pragma once
#include <QString>
#include <QDateTime>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class DatabaseManager;

// Shared data carrier used by FileScanner → MediaRepository batch path.
struct MediaEntry {
    QString   filePath;
    QString   folderPath;
    qint64    fileSize    = 0;
    QString   mimeType;
    QDateTime creationDate;
    QDateTime modifiedDate;
    int       width       = 0;
    int       height      = 0;
    double    latitude    = 0.0;
    double    longitude   = 0.0;
    double    duration    = 0.0;  // seconds; videos only (0 for images)
};

class MediaRepository {
public:
    explicit MediaRepository(DatabaseManager *db);

    // Single upsert (wraps upsertBatch for convenience).
    bool upsert(const MediaEntry &entry);

    // Batch upsert — all rows committed in one transaction.
    // Crash-safe: SQLite WAL rolls back the whole batch on failure/crash;
    // needsUpdate() skips already-committed rows on the next scan.
    bool upsertBatch(const QVector<MediaEntry> &entries);

    bool needsUpdate(const QString &filePath, qint64 size);

    QVariantList getAll(bool hideIgnored = true);
    QVariantMap  getById(int mediaId);

    bool setHidden(int mediaId, bool hidden);
    bool setTrashed(int mediaId, bool trashed);
    bool toggleFavorite(int mediaId);
    bool deletePermanently(int mediaId);

    QVariantList getGeotaggedLocations();
    qint64       totalSizeBytes();
    qint64       photoSizeBytes();
    qint64       videoSizeBytes();

    int pruneOrphaned();
    int emptyTrash();

private:
    DatabaseManager *m_db;
};
