#pragma once

#include <QObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QVariantList>
#include <QString>
#include <QDateTime>
#include <memory>
#include <QHash>
#include "MediaRepository.h"
#include "AlbumRepository.h"

class DatabaseManager : public QObject {
    Q_OBJECT
public:
    // Mirrors Sort::MediaRole — keep values in sync (0-4 frozen for saved prefs).
    enum SortRole  { ByCreated = 0, ByModified = 1, ByName = 2, BySize = 3, ByViewed = 4,
                     ByType = 5, ByWidth = 6, ByHeight = 7, ByDimensions = 8, ByOrientation = 9 };
    enum SortOrder { Descending = 0, Ascending = 1 };
    Q_ENUM(SortRole)
    Q_ENUM(SortOrder)

    explicit DatabaseManager(QObject *parent = nullptr);
    ~DatabaseManager();

    // Thread-local SQLite connection (safe to call from any thread).
    QSqlDatabase threadDb();

    bool openDatabase();
    
    // CRUD operations for media
    bool addOrUpdateMedia(const QString &filePath, const QString &hash,
                         qint64 size, const QString &mimeType,
                         const QDateTime &creationDate, int width, int height,
                         double latitude = 0.0, double longitude = 0.0);

    // Batch upsert — all rows in one SQLite transaction (crash-safe via WAL).
    bool addOrUpdateMediaBatch(const QVector<MediaEntry> &entries);

    // Returns [{file_path, latitude, longitude, photo_count, thumb_path}] grouped ~1km.
    Q_INVOKABLE QVariantList getGeotaggedLocations();

    // Every non-trashed, non-hidden photo/video of the given places (entries of
    // getGeotaggedLocations(): {lat, lon} rounded to 2 decimals), newest first,
    // in the viewer's item format.
    Q_INVOKABLE QVariantList getMediaForPlaces(const QVariantList &places);

    // Get all media for the models.
    // rawFilter: 0=all, 1=JPEG-only (exclude RAW), 2=RAW-only
    // excludeTrashed/excludeHidden: when true, also filter out is_trashed/is_hidden rows.
    // Defaulted to false so existing callers (TimelineModel's Trash/Hidden filter modes) are unaffected.
    QVariantList getAllMedia(bool hideIgnored = true,
                             SortRole role   = ByCreated,
                             SortOrder order = Descending,
                             bool excludeTrashed = false,
                             bool excludeHidden = false);

    // Returns all non-trashed file paths (for background thumbnail pre-generation).
    QStringList getAllMediaPaths();
    Q_INVOKABLE void setRawFilter(int filter);

    // Per-view sort preference persistence (stored in settings_kv).
    Q_INVOKABLE void        setSortPref(const QString &view, int role, int order);
    Q_INVOKABLE QVariantMap getSortPref(const QString &view);

    // Get automatically grouped albums (by folder)
    QVariantList getAlbums(bool hideIgnored = true);

    // Ignore an album and its items
    Q_INVOKABLE bool ignoreAlbum(const QString &folderPath, bool ignore = true);

    // Returns [{path, name}] for all currently-ignored folders
    Q_INVOKABLE QVariantList getIgnoredFolders();

    // Per-item ignore (independent of folder ignore). Ignored media never appear
    // in any timeline view; manage/undo them via the Settings "ignored items" list.
    Q_INVOKABLE bool         setIgnored(int mediaId, bool ignored);
    Q_INVOKABLE QVariantList getIgnoredMedia();   // [{id, path, name, isMedia:true}]

    // Indexed Directories
    Q_INVOKABLE QVariantList getIndexedDirectories();
    QStringList getIndexedDirectoryPaths();
    Q_INVOKABLE bool addIndexedDirectory(const QString &path);
    Q_INVOKABLE bool removeIndexedDirectory(const QString &path);
    bool updateDirectoryStats(const QString &path, int count);

    // Returns true if the file needs (re-)indexing: new, size changed, or missing EXIF.
    bool needsUpdate(const QString &filePath, qint64 size);

    // What the index already knows about every file under `rootPath`, in one
    // query (the scanner used to issue one query per file). Value: file size,
    // or -1 when the row is incomplete (no date or no dimensions) and must be
    // re-read. Safe to call from any thread.
    QHash<QString, qint64> indexSnapshot(const QString &rootPath);
    // Drops rows (and cached thumbnails) of files that no longer exist.
    int removeMediaPaths(const QStringList &paths);

    // Encrypted thumbnail blob storage
    QByteArray getThumbnailBlob(const QString &filePath, int size); // non-const: calls checkConnection()
    bool storeThumbnailBlob(const QString &filePath, int size, const QByteArray &encryptedBlob);

    // Media actions
    Q_INVOKABLE bool toggleFavorite(int mediaId);
    Q_INVOKABLE bool setTrashed(int mediaId, bool trashed);
    Q_INVOKABLE bool trashMedia(const QString &filePath);   // move to trash by path (dashboard list)
    Q_INVOKABLE bool deleteMediaPermanently(int mediaId);
    Q_INVOKABLE QVariantMap getMediaById(int mediaId);

    // Album actions
    Q_INVOKABLE bool pinAlbum(const QString &folderPath, bool pinned);
    Q_INVOKABLE bool trashAlbum(const QString &folderPath);

    // Album metadata (name, description, cover) — works for folder-based and virtual albums
    Q_INVOKABLE QString getRandomPhotoPath();
    Q_INVOKABLE QString createVirtualAlbum(const QString &name, const QString &desc, const QString &coverPath);
    Q_INVOKABLE bool    updateAlbumMeta(const QString &pathPrefix, const QString &customName,
                                        const QString &desc, const QString &coverPath);

    // Move a media file physically to a target folder, updating the DB record.
    Q_INVOKABLE bool moveMediaToAlbum(int mediaId, const QString &targetFolderPath);

    // Open the system file manager with the given file pre-selected, via the
    // portable org.freedesktop.FileManager1 D-Bus interface (Dolphin, Nautilus,
    // Nemo, …). Falls back to opening the containing folder if unavailable.
    Q_INVOKABLE void revealInFolder(const QString &filePath);

    // Simple flat list of {path, name} for all non-ignored folder albums — used by "Send to" UI.
    Q_INVOKABLE QVariantList getAlbumList();

    // Permanently delete all trashed files from disk and DB. Returns count deleted.
    Q_INVOKABLE int emptyTrash();

    // Remove media rows for files that no longer exist on disk. Returns count pruned.
    Q_INVOKABLE int pruneOrphanedMedia();

    // Storage stats
    Q_INVOKABLE qint64 getTotalMediaSizeBytes();
    Q_INVOKABLE qint64 getPhotoSizeBytes();
    Q_INVOKABLE qint64 getVideoSizeBytes();
    Q_INVOKABLE int    getPhotoCount();
    Q_INVOKABLE int    getVideoCount();

    // Scan exclusion patterns (substring match against full dir path)
    Q_INVOKABLE QStringList getScanExclusions();
    Q_INVOKABLE bool addScanExclusion(const QString &pattern);
    Q_INVOKABLE bool removeScanExclusion(const QString &pattern);

    // Hidden media
    Q_INVOKABLE bool setHidden(int mediaId, bool hidden);
    Q_INVOKABLE bool hasHiddenPassword();
    Q_INVOKABLE bool checkHiddenPassword(const QString &password);
    Q_INVOKABLE bool setHiddenPassword(const QString &password);

private:
    bool createTables();
    void checkConnection();
    QSqlDatabase m_db;
    QString m_dbPath;
    int m_rawFilter = 0;
    std::unique_ptr<MediaRepository> m_media;
    std::unique_ptr<AlbumRepository> m_album;
};
