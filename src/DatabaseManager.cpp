#include "DatabaseManager.h"
#include "MediaRepository.h"
#include "AlbumRepository.h"
#include "ThumbnailGenerator.h"
#include "Sort.h"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QSqlRecord>
#include <QFile>
#include <QFileInfo>
#include <QThread>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QUrl>
#include <QDesktopServices>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <cmath>
#include <algorithm>

DatabaseManager::DatabaseManager(QObject *parent) : QObject(parent) {
    m_dbPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/gallery.db";
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
    openDatabase();
    m_media = std::make_unique<MediaRepository>(this);
    m_album = std::make_unique<AlbumRepository>(this);
}

DatabaseManager::~DatabaseManager() {
}

// Returns the thread-local QSqlDatabase, opening it on first use.
// Never writes to m_db from background threads — m_db is main-thread only.
static QSqlDatabase openThreadDb(const QString &dbPath) {
    const bool isMain = (QThread::currentThread() == qApp->thread());
    const QString connName = isMain
        ? QLatin1String("qt_sql_default_connection")
        : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));

    if (!QSqlDatabase::contains(connName)) {
        QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", connName);
        db.setDatabaseName(dbPath);
        if (!db.open()) {
            qCritical() << "Error opening DB in thread" << connName << ":" << db.lastError().text();
        } else {
            QSqlQuery wal(db);
            wal.exec("PRAGMA journal_mode=WAL");
            wal.exec("PRAGMA synchronous=NORMAL");
        }
    } else {
        QSqlDatabase db = QSqlDatabase::database(connName);
        if (!db.isOpen()) db.open();
    }
    return QSqlDatabase::database(connName);
}

QSqlDatabase DatabaseManager::threadDb() {
    return openThreadDb(m_dbPath);
}

void DatabaseManager::checkConnection() {
    // Only update m_db on the main thread; background threads must call openThreadDb() directly.
    if (QThread::currentThread() == qApp->thread()) {
        const QString connName = QLatin1String("qt_sql_default_connection");
        if (!QSqlDatabase::contains(connName)) {
            m_db = QSqlDatabase::addDatabase("QSQLITE", connName);
            m_db.setDatabaseName(m_dbPath);
            if (m_db.open()) {
                QSqlQuery wal(m_db);
                wal.exec("PRAGMA journal_mode=WAL");
                wal.exec("PRAGMA synchronous=NORMAL");
                createTables();
            }
        } else {
            m_db = QSqlDatabase::database(connName);
            if (!m_db.isOpen()) m_db.open();
        }
    } else {
        // Background thread: open thread-local connection without touching m_db.
        openThreadDb(m_dbPath);
    }
}

bool DatabaseManager::openDatabase() {
    checkConnection();
    return m_db.isOpen();
}

bool DatabaseManager::createTables() {
    QSqlQuery query(m_db);
    bool success = query.exec(
        "CREATE TABLE IF NOT EXISTS media ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "file_path TEXT UNIQUE,"
        "folder_path TEXT,"
        "file_hash TEXT,"
        "file_size INTEGER,"
        "mime_type TEXT,"
        "creation_date INTEGER,"
        "width INTEGER,"
        "height INTEGER,"
        "is_favorite BOOLEAN DEFAULT 0,"
        "is_trashed BOOLEAN DEFAULT 0"
        ")"
    );

    if (success) {
        query.exec("CREATE INDEX IF NOT EXISTS idx_folder ON media(folder_path)");
    }

    success = query.exec(
        "CREATE TABLE IF NOT EXISTS albums ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT UNIQUE,"
        "path_prefix TEXT,"
        "cover_media_id INTEGER,"
        "is_pinned BOOLEAN DEFAULT 0,"
        "is_ignored BOOLEAN DEFAULT 0,"
        "FOREIGN KEY(cover_media_id) REFERENCES media(id)"
        ")"
    );

    success = query.exec(
        "CREATE TABLE IF NOT EXISTS indexed_directories ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "path TEXT UNIQUE,"
        "item_count INTEGER DEFAULT 0,"
        "last_scan INTEGER,"
        "is_active BOOLEAN DEFAULT 1"
        ")"
    );

    query.exec(
        "CREATE TABLE IF NOT EXISTS thumbnails ("
        "file_path TEXT NOT NULL,"
        "size INTEGER NOT NULL,"
        "blob BLOB NOT NULL,"
        "PRIMARY KEY (file_path, size)"
        ")"
    );

    // Migration: add columns that may be missing when an older DB exists on disk.
    // ALTER TABLE returns an error if the column already exists — that is harmless and expected.
    auto migrate = [&](const QString &tbl, const QString &col, const QString &def) {
        QSqlQuery mq(m_db);
        mq.exec(QString("ALTER TABLE %1 ADD COLUMN %2 %3").arg(tbl, col, def));
    };
    migrate("albums", "is_pinned",   "BOOLEAN DEFAULT 0");
    migrate("albums", "is_ignored",  "BOOLEAN DEFAULT 0");
    migrate("albums", "custom_name", "TEXT");
    migrate("albums", "description", "TEXT");
    migrate("albums", "cover_path",  "TEXT");
    migrate("media",  "is_favorite", "BOOLEAN DEFAULT 0");
    migrate("media",  "is_trashed",  "BOOLEAN DEFAULT 0");
    migrate("media",  "is_hidden",   "BOOLEAN DEFAULT 0");
    migrate("media",  "is_ignored",  "BOOLEAN DEFAULT 0");
    migrate("media",  "latitude",      "REAL");
    migrate("media",  "longitude",     "REAL");
    migrate("media",  "modified_date", "INTEGER DEFAULT 0");
    migrate("media",  "last_viewed",   "INTEGER DEFAULT 0");
    migrate("media",  "duration",      "REAL DEFAULT 0");

    query.exec(
        "CREATE TABLE IF NOT EXISTS scan_exclusions ("
        "pattern TEXT PRIMARY KEY"
        ")"
    );

    query.exec(
        "CREATE TABLE IF NOT EXISTS settings_kv ("
        "key TEXT PRIMARY KEY,"
        "value TEXT NOT NULL DEFAULT ''"
        ")"
    );

    query.exec(
        "CREATE TABLE IF NOT EXISTS ai_embeddings ("
        "media_id  INTEGER PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,"
        "embedding BLOB NOT NULL,"
        "model_ver TEXT NOT NULL,"
        "created_at INTEGER DEFAULT (strftime('%s','now'))"
        ")"
    );

    query.exec(
        "CREATE TABLE IF NOT EXISTS doc_chunks ("
        "id        INTEGER PRIMARY KEY AUTOINCREMENT,"
        "file_path TEXT NOT NULL,"
        "chunk_idx INTEGER NOT NULL,"
        "embedding BLOB NOT NULL,"
        "model_ver TEXT NOT NULL,"
        "UNIQUE(file_path, chunk_idx)"
        ")"
    );
    query.exec("CREATE INDEX IF NOT EXISTS idx_doc_chunks_path ON doc_chunks(file_path)");

    // Ensure path_prefix has a UNIQUE index. Adding an index is safe under WAL
    // and avoids the DDL-heavy table-recreation that would deadlock with open readers.
    {
        QSqlQuery mq(m_db);
        // Remove any duplicate path_prefix rows; keep the latest (highest id).
        mq.exec("DELETE FROM albums WHERE id NOT IN ("
                "SELECT MAX(id) FROM albums WHERE path_prefix IS NOT NULL GROUP BY path_prefix"
                ")");
        mq.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_albums_path_prefix ON albums(path_prefix)");
        // Clean up leftover albums_v2 from a failed earlier migration attempt.
        mq.exec("DROP TABLE IF EXISTS albums_v2");
    }

    return success;
}

QStringList DatabaseManager::getIndexedDirectoryPaths() {
    checkConnection();
    QStringList paths;
    QSqlQuery q("SELECT path FROM indexed_directories WHERE is_active=1", m_db);
    while (q.next())
        paths.append(q.value(0).toString());
    return paths;
}

QVariantList DatabaseManager::getIndexedDirectories() {
    checkConnection();
    QVariantList list;
    QSqlQuery query("SELECT path, item_count, last_scan, is_active FROM indexed_directories", m_db);
    while (query.next()) {
        QVariantMap map;
        map["path"] = query.value(0);
        map["count"] = query.value(1);
        map["lastScan"] = query.value(2);
        map["active"] = query.value(3);
        list.append(map);
    }
    return list;
}

bool DatabaseManager::addIndexedDirectory(const QString &path) {
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("INSERT OR IGNORE INTO indexed_directories (path) VALUES (:path)");
    query.bindValue(":path", path);
    return query.exec();
}

bool DatabaseManager::removeIndexedDirectory(const QString &path) {
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM indexed_directories WHERE path = :path");
    query.bindValue(":path", path);
    return query.exec();
}

bool DatabaseManager::updateDirectoryStats(const QString &path, int count) {
    QSqlDatabase db = openThreadDb(m_dbPath);
    QSqlQuery query(db);
    query.prepare("UPDATE indexed_directories SET item_count = :count, last_scan = :now WHERE path = :path");
    query.bindValue(":count", count);
    query.bindValue(":now", QDateTime::currentDateTime().toSecsSinceEpoch());
    query.bindValue(":path", path);
    return query.exec();
}

bool DatabaseManager::ignoreAlbum(const QString &folderPath, bool ignore) {
    checkConnection();
    // Update existing row if one already tracks this path
    {
        QSqlQuery q(m_db);
        q.prepare("UPDATE albums SET is_ignored = :v WHERE path_prefix = :path");
        q.bindValue(":v", ignore ? 1 : 0);
        q.bindValue(":path", folderPath);
        q.exec();
        if (q.numRowsAffected() > 0) return true;
    }
    // No existing row — insert, or update if path_prefix already exists (unique index handles it).
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO albums (name, path_prefix, is_ignored) VALUES (:n, :p, :v) "
              "ON CONFLICT(path_prefix) DO UPDATE SET is_ignored = excluded.is_ignored "
              "ON CONFLICT(name)        DO UPDATE SET path_prefix = excluded.path_prefix, "
              "                                       is_ignored  = excluded.is_ignored");
    q.bindValue(":n", folderPath);
    q.bindValue(":p", folderPath);
    q.bindValue(":v", ignore ? 1 : 0);
    if (!q.exec()) {
        qWarning() << "ignoreAlbum INSERT failed:" << q.lastError().text() << "path:" << folderPath;
        return false;
    }
    return true;
}

QVariantList DatabaseManager::getIgnoredFolders() {
    checkConnection();
    QSqlQuery q(m_db);
    // Pull a sample file from each ignored folder for a cover preview.
    q.exec("SELECT a.path_prefix, "
           "  (SELECT m.file_path FROM media m WHERE m.folder_path = a.path_prefix "
           "   ORDER BY m.id LIMIT 1) AS cover "
           "FROM albums a WHERE a.is_ignored = 1 ORDER BY a.path_prefix");
    QVariantList list;
    while (q.next()) {
        const QString path  = q.value(0).toString();
        const QString cover = q.value(1).toString();
        QVariantMap map;
        map["path"]  = path;
        map["name"]  = QDir(path).dirName();
        map["thumb"] = cover.isEmpty() ? QString() : ThumbnailGenerator::thumbnailUrl(cover);
        list.append(map);
    }
    return list;
}

bool DatabaseManager::addOrUpdateMedia(const QString &filePath, const QString &hash,
                                     qint64 size, const QString &mimeType,
                                     const QDateTime &creationDate, int width, int height,
                                     double latitude, double longitude) {
    QSqlDatabase db = openThreadDb(m_dbPath);
    QFileInfo fileInfo(filePath);
    QString folderPath = fileInfo.absolutePath();

    QSqlQuery query(db);
    query.prepare(
        "INSERT INTO media "
        "(file_path, folder_path, file_hash, file_size, mime_type, creation_date, width, height, latitude, longitude) "
        "VALUES (:path, :folder, :hash, :size, :mime, :date, :w, :h, :lat, :lon) "
        "ON CONFLICT(file_path) DO UPDATE SET "
        "folder_path=excluded.folder_path, file_hash=excluded.file_hash, "
        "file_size=excluded.file_size, mime_type=excluded.mime_type, "
        "creation_date=excluded.creation_date, width=excluded.width, height=excluded.height, "
        "latitude=excluded.latitude, longitude=excluded.longitude"
    );
    query.bindValue(":path", filePath);
    query.bindValue(":folder", folderPath);
    query.bindValue(":hash", hash);
    query.bindValue(":size", size);
    query.bindValue(":mime", mimeType);
    query.bindValue(":date", creationDate.isValid() ? creationDate.toSecsSinceEpoch() : 0);
    query.bindValue(":w", width);
    query.bindValue(":h", height);
    query.bindValue(":lat", latitude != 0.0 ? QVariant(latitude) : QVariant(QMetaType::fromType<double>()));
    query.bindValue(":lon", longitude != 0.0 ? QVariant(longitude) : QVariant(QMetaType::fromType<double>()));

    if (!query.exec()) {
        qWarning() << "Error adding/updating media:" << query.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::addOrUpdateMediaBatch(const QVector<MediaEntry> &entries) {
    return m_media->upsertBatch(entries);
}

bool DatabaseManager::needsUpdate(const QString &filePath, qint64 size) {
    QSqlDatabase db = openThreadDb(m_dbPath);
    QSqlQuery query(db);
    query.prepare("SELECT file_size, creation_date, width, height FROM media WHERE file_path = :path");
    query.bindValue(":path", filePath);

    if (query.exec() && query.next()) {
        qint64 storedSize = query.value(0).toLongLong();
        qint64 storedDate = query.value(1).toLongLong();
        int    storedW    = query.value(2).toInt();
        int    storedH    = query.value(3).toInt();
        // Re-index if: size changed, EXIF date missing, or dimensions never extracted.
        return storedSize != size || storedDate == 0 || storedW == 0 || storedH == 0;
    }
    return true; // Not in DB yet — insert it.
}

QHash<QString, qint64> DatabaseManager::indexSnapshot(const QString &rootPath) {
    QSqlDatabase db = openThreadDb(m_dbPath);
    QSqlQuery q(db);
    q.setForwardOnly(true);
    QString prefix = rootPath;
    if (!prefix.endsWith(QLatin1Char('/')))
        prefix += QLatin1Char('/');
    // Range scan on the UNIQUE(file_path) index instead of LIKE (which can't
    // use it): every path starting with "prefix" sorts in [prefix, prefix+U+FFFF).
    q.prepare(QStringLiteral("SELECT file_path, file_size, creation_date, width, height FROM media "
                             "WHERE file_path >= ? AND file_path < ?"));
    q.addBindValue(prefix);
    q.addBindValue(prefix + QChar(0xFFFF));
    QHash<QString, qint64> out;
    if (!q.exec()) {
        qWarning() << "indexSnapshot failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) {
        const bool complete = q.value(2).toLongLong() != 0 && q.value(3).toInt() != 0 && q.value(4).toInt() != 0;
        out.insert(q.value(0).toString(), complete ? q.value(1).toLongLong() : -1);
    }
    return out;
}

QVariantList DatabaseManager::getAlbums(bool hideIgnored) {
    checkConnection();

    QString connName = (QThread::currentThread() == qApp->thread())
                       ? QLatin1String("qt_sql_default_connection")
                       : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);

    QVariantList list;

    // Folder-based albums (grouped from media), joined with albums metadata
    QString sql =
        "SELECT m.folder_path, COUNT(*) AS cnt, SUM(m.file_size) AS sz, "
        "MIN(m.file_path) AS cover_file, "
        "COALESCE(a.custom_name,'') AS custom_name, "
        "COALESCE(a.is_pinned,0) AS is_pinned, "
        "COALESCE(a.cover_path,'') AS cover_path, "
        "COALESCE(a.description,'') AS description "
        "FROM media m "
        "LEFT JOIN albums a ON a.path_prefix = m.folder_path "
        "WHERE m.is_trashed = 0 ";
    if (hideIgnored) {
        sql += "AND COALESCE(m.folder_path,'') NOT IN "
               "(SELECT COALESCE(path_prefix,'') FROM albums WHERE is_ignored = 1) ";
    }
    sql += "GROUP BY m.folder_path HAVING COUNT(*) > 0 "
           "UNION ALL "
           "SELECT a.path_prefix, 0, 0, COALESCE(a.cover_path,''), "
           "COALESCE(a.name,''), COALESCE(a.is_pinned,0), COALESCE(a.cover_path,''), "
           "COALESCE(a.description,'') "
           "FROM albums a WHERE a.path_prefix LIKE '__virtual__%' "
           "ORDER BY 1 ASC";

    QSqlQuery query(db);
    if (!query.exec(sql)) {
        qWarning() << "[DB] getAlbums query failed:" << query.lastError().text();
        return list;
    }
    while (query.next()) {
        QVariantMap map;
        QString fp          = query.value(0).toString();
        QString customName  = query.value(4).toString();
        QString coverPath   = query.value(6).toString();
        QString coverFile   = query.value(3).toString();

        map["folder_path"]  = fp;
        map["count"]        = query.value(1);
        map["size"]         = query.value(2);
        map["cover_file"]   = coverFile;
        map["cover_path"]   = coverPath;
        map["cover"]        = coverPath.isEmpty() ? coverFile : coverPath;
        map["pinned"]       = query.value(5).toBool();
        map["description"]  = query.value(7);

        if (!customName.isEmpty())
            map["name"] = customName;
        else if (fp.startsWith("__virtual__"))
            map["name"] = fp.mid(11);
        else
            map["name"] = QDir(fp).dirName();

        list.append(map);
    }
    return list;
}

QVariantList DatabaseManager::getGeotaggedLocations() {
    checkConnection();
    QSqlDatabase db = QSqlDatabase::database(
        QThread::currentThread() == qApp->thread()
            ? QLatin1String("qt_sql_default_connection")
            : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()))
    );

    QVariantList list;
    // Group photos within ~1km radius (2 decimal places ≈ 1.1 km).
    // JOIN back to media to get full sample-photo fields for viewer + date display.
    QSqlQuery query(db);
    if (!query.exec(
            "SELECT g.lat, g.lon, g.cnt, "
            "m.id, m.file_path, m.mime_type, m.creation_date, "
            "m.is_favorite, m.is_trashed, m.is_hidden "
            "FROM ("
            "  SELECT ROUND(latitude,2) AS lat, ROUND(longitude,2) AS lon, "
            "         COUNT(*) AS cnt, MIN(file_path) AS sample_path "
            "  FROM media "
            "  WHERE latitude IS NOT NULL AND longitude IS NOT NULL "
            "    AND latitude != 0 AND longitude != 0 "
            "    AND is_trashed = 0 "
            "  GROUP BY lat, lon "
            "  ORDER BY cnt DESC "
            "  LIMIT 500"
            ") g JOIN media m ON m.file_path = g.sample_path")) {
        qWarning() << "getGeotaggedLocations failed:" << query.lastError().text();
        return list;
    }
    while (query.next()) {
        QVariantMap m;
        QString fp = query.value("file_path").toString();
        m["lat"]           = query.value("lat").toDouble();
        m["lon"]           = query.value("lon").toDouble();
        m["count"]         = query.value("cnt").toInt();
        m["id"]            = query.value("id").toInt();
        m["file_path"]     = fp;
        m["mime_type"]     = query.value("mime_type").toString();
        m["creation_date"] = query.value("creation_date").toLongLong();
        m["is_favorite"]   = query.value("is_favorite").toBool();
        m["is_trashed"]    = query.value("is_trashed").toBool();
        m["is_hidden"]     = query.value("is_hidden").toBool();
        m["path"]          = "file://" + fp;
        m["thumb"]         = ThumbnailGenerator::thumbnailUrl(fp);
        list.append(m);
    }
    return list;
}

QVariantList DatabaseManager::getMediaForPlaces(const QVariantList &places) {
    checkConnection();
    QVariantList list;
    if (places.isEmpty())
        return list;
    // Bound the statement size; a cluster rarely has more than a few dozen places.
    const int n = std::min<int>(places.size(), 400);
    QStringList clauses;
    clauses.reserve(n);
    for (int i = 0; i < n; ++i)
        clauses << QStringLiteral("(ROUND(latitude,2) = ? AND ROUND(longitude,2) = ?)");
    QSqlQuery q(threadDb());
    q.prepare(QStringLiteral(
        "SELECT * FROM media WHERE is_trashed = 0 AND COALESCE(is_hidden,0) = 0 "
        "AND COALESCE(is_ignored,0) = 0 AND latitude IS NOT NULL AND (")
        + clauses.join(QStringLiteral(" OR ")) + QStringLiteral(") ORDER BY creation_date DESC LIMIT 5000"));
    for (int i = 0; i < n; ++i) {
        const QVariantMap p = places[i].toMap();
        // Same rounding as getGeotaggedLocations() so the groups match exactly.
        q.addBindValue(std::round(p.value(QStringLiteral("lat")).toDouble() * 100.0) / 100.0);
        q.addBindValue(std::round(p.value(QStringLiteral("lon")).toDouble() * 100.0) / 100.0);
    }
    if (!q.exec()) {
        qWarning() << "getMediaForPlaces failed:" << q.lastError().text();
        return list;
    }
    const QSqlRecord rec = q.record();
    const int fpCol = rec.indexOf(QStringLiteral("file_path"));
    while (q.next()) {
        QVariantMap m;
        for (int i = 0; i < rec.count(); ++i)
            m.insert(rec.fieldName(i), q.value(i));
        const QString fp = q.value(fpCol).toString();
        m.insert(QStringLiteral("thumb"), ThumbnailGenerator::thumbnailUrl(fp));
        m.insert(QStringLiteral("path"), QStringLiteral("file://") + fp);
        list.append(m);
    }
    return list;
}

QByteArray DatabaseManager::getThumbnailBlob(const QString &filePath, int size) {
    checkConnection(); // opens thread-local connection if called from image loading thread
    const QString connName = (QThread::currentThread() == qApp->thread())
        ? QLatin1String("qt_sql_default_connection")
        : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);
    if (!db.isOpen()) return {};

    QSqlQuery query(db);
    query.prepare("SELECT blob FROM thumbnails WHERE file_path = :path AND size = :size");
    query.bindValue(":path", filePath);
    query.bindValue(":size", size);
    if (query.exec() && query.next())
        return query.value(0).toByteArray();
    return {};
}

bool DatabaseManager::storeThumbnailBlob(const QString &filePath, int size, const QByteArray &encryptedBlob) {
    checkConnection();
    const QString connName = (QThread::currentThread() == qApp->thread())
        ? QLatin1String("qt_sql_default_connection")
        : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);
    QSqlQuery query(db);
    query.prepare("INSERT OR REPLACE INTO thumbnails (file_path, size, blob) VALUES (:path, :size, :blob)");
    query.bindValue(":path", filePath);
    query.bindValue(":size", size);
    query.bindValue(":blob", encryptedBlob);
    return query.exec();
}

bool DatabaseManager::toggleFavorite(int mediaId) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("UPDATE media SET is_favorite = NOT is_favorite WHERE id = :id");
    q.bindValue(":id", mediaId);
    return q.exec();
}

bool DatabaseManager::setTrashed(int mediaId, bool trashed) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("UPDATE media SET is_trashed = :v WHERE id = :id");
    q.bindValue(":v", trashed ? 1 : 0);
    q.bindValue(":id", mediaId);
    return q.exec();
}

bool DatabaseManager::trashMedia(const QString &filePath) {
    if (filePath.isEmpty()) return false;
    checkConnection();
    // Callers may pass a file:// URL (e.g. straight from a QML model's path role);
    // normalize to a plain local path since file_path is stored unprefixed.
    const QString normalized = filePath.startsWith(QLatin1String("file://"))
                                    ? QUrl(filePath).toLocalFile()
                                    : filePath;
    QSqlQuery q(m_db);
    q.prepare("UPDATE media SET is_trashed = 1 WHERE file_path = :path");
    q.bindValue(":path", normalized);
    return q.exec();
}

bool DatabaseManager::deleteMediaPermanently(int mediaId) {
    checkConnection();
    QSqlQuery pathQ(m_db);
    pathQ.prepare("SELECT file_path FROM media WHERE id = :id");
    pathQ.bindValue(":id", mediaId);
    if (pathQ.exec() && pathQ.next()) {
        QSqlQuery thumbQ(m_db);
        thumbQ.prepare("DELETE FROM thumbnails WHERE file_path = :path");
        thumbQ.bindValue(":path", pathQ.value(0).toString());
        thumbQ.exec();
    }
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM media WHERE id = :id");
    q.bindValue(":id", mediaId);
    return q.exec();
}

QVariantMap DatabaseManager::getMediaById(int mediaId) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("SELECT * FROM media WHERE id = :id");
    q.bindValue(":id", mediaId);
    if (q.exec() && q.next()) {
        QVariantMap map;
        QSqlRecord rec = q.record();
        for (int i = 0; i < rec.count(); ++i)
            map[rec.fieldName(i)] = q.value(i);
        map["thumb"] = ThumbnailGenerator::thumbnailUrl(map["file_path"].toString());
        map["path"]  = "file://" + map["file_path"].toString();
        return map;
    }
    return {};
}

bool DatabaseManager::pinAlbum(const QString &folderPath, bool pinned) {
    checkConnection();
    {
        QSqlQuery q(m_db);
        q.prepare("UPDATE albums SET is_pinned = :v WHERE path_prefix = :path");
        q.bindValue(":v", pinned ? 1 : 0);
        q.bindValue(":path", folderPath);
        q.exec();
        if (q.numRowsAffected() > 0) return true;
    }
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO albums (name, path_prefix, is_pinned) VALUES (:n, :p, :v) "
              "ON CONFLICT(path_prefix) DO UPDATE SET is_pinned = excluded.is_pinned "
              "ON CONFLICT(name)        DO UPDATE SET path_prefix = excluded.path_prefix, "
              "                                       is_pinned  = excluded.is_pinned");
    q.bindValue(":n", folderPath);
    q.bindValue(":p", folderPath);
    q.bindValue(":v", pinned ? 1 : 0);
    if (!q.exec()) {
        qWarning() << "pinAlbum INSERT failed:" << q.lastError().text() << "path:" << folderPath;
        return false;
    }
    return true;
}

bool DatabaseManager::trashAlbum(const QString &folderPath) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("UPDATE media SET is_trashed = 1 WHERE folder_path = :path");
    q.bindValue(":path", folderPath);
    return q.exec();
}

qint64 DatabaseManager::getTotalMediaSizeBytes() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT COALESCE(SUM(file_size), 0) FROM media WHERE is_trashed = 0");
    return q.next() ? q.value(0).toLongLong() : 0;
}

qint64 DatabaseManager::getPhotoSizeBytes() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT COALESCE(SUM(file_size), 0) FROM media WHERE is_trashed = 0 AND mime_type NOT LIKE 'video/%'");
    return q.next() ? q.value(0).toLongLong() : 0;
}

qint64 DatabaseManager::getVideoSizeBytes() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT COALESCE(SUM(file_size), 0) FROM media WHERE is_trashed = 0 AND mime_type LIKE 'video/%'");
    return q.next() ? q.value(0).toLongLong() : 0;
}

int DatabaseManager::getPhotoCount() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT COUNT(*) FROM media "
           "WHERE is_trashed=0 AND is_hidden=0 AND mime_type NOT LIKE 'video/%'");
    return q.next() ? q.value(0).toInt() : 0;
}

int DatabaseManager::getVideoCount() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT COUNT(*) FROM media "
           "WHERE is_trashed=0 AND is_hidden=0 AND mime_type LIKE 'video/%'");
    return q.next() ? q.value(0).toInt() : 0;
}

void DatabaseManager::setRawFilter(int filter) {
    m_rawFilter = filter;
}

// Extensions considered "RAW camera format" for rawFilter logic.
static QString rawGlobClause(bool invert) {
    static const QStringList exts = {
        "%.nef", "%.cr2", "%.cr3", "%.arw", "%.dng", "%.raf", "%.orf",
        "%.rw2", "%.pef", "%.srw", "%.3fr", "%.raw", "%.rw1", "%.mrw", "%.x3f", "%.dcr"
    };
    QStringList parts;
    for (const QString &e : exts)
        parts << QString("LOWER(file_path) LIKE '%1'").arg(e);
    QString combined = "(" + parts.join(" OR ") + ")";
    return invert ? ("NOT " + combined) : combined;
}

QVariantList DatabaseManager::getAllMedia(bool hideIgnored, SortRole role, SortOrder order,
                                           bool excludeTrashed, bool excludeHidden) {
    checkConnection();

    // Resolve the thread-local connection by name to avoid sharing m_db across threads.
    QString connName = (QThread::currentThread() == qApp->thread())
                       ? QLatin1String("qt_sql_default_connection")
                       : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);

    QVariantList list;
    QStringList conditions;
    // Per-item ignored media are excluded from every timeline view, always.
    conditions << "COALESCE(is_ignored,0) = 0";
    if (hideIgnored)
        conditions << "COALESCE(folder_path,'') NOT IN "
                      "(SELECT COALESCE(path_prefix,'') FROM albums WHERE is_ignored = 1)";
    if (m_rawFilter == 1)
        conditions << rawGlobClause(true);
    else if (m_rawFilter == 2)
        conditions << rawGlobClause(false);
    if (excludeTrashed)
        conditions << "COALESCE(is_trashed,0) = 0";
    if (excludeHidden)
        conditions << "COALESCE(is_hidden,0) = 0";

    const QString orderClause = Sort::mediaOrderClause(role, order == Ascending);

    QString sql = "SELECT * FROM media";
    if (!conditions.isEmpty())
        sql += " WHERE " + conditions.join(" AND ");
    sql += " ORDER BY " + orderClause;

    QSqlQuery query(db);
    if (!query.exec(sql)) {
        qWarning() << "getAllMedia query failed:" << query.lastError().text();
        return list;
    }
    while (query.next()) {
        QVariantMap map;
        QSqlRecord record = query.record();
        for (int i = 0; i < record.count(); ++i) {
            map[record.fieldName(i)] = query.value(i);
        }
        list.append(map);
    }
    return list;
}

QStringList DatabaseManager::getAllMediaPaths() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT file_path FROM media WHERE is_trashed = 0");
    QStringList paths;
    while (q.next())
        paths << q.value(0).toString();
    return paths;
}

void DatabaseManager::setSortPref(const QString &view, int role, int order) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO settings_kv (key, value) VALUES (:k, :v) "
              "ON CONFLICT(key) DO UPDATE SET value = excluded.value");
    q.bindValue(":k", "sort_pref_" + view);
    q.bindValue(":v", QString("%1,%2").arg(role).arg(order));
    q.exec();
}

QVariantMap DatabaseManager::getSortPref(const QString &view) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("SELECT value FROM settings_kv WHERE key = :k");
    q.bindValue(":k", "sort_pref_" + view);
    QVariantMap result;
    result["role"]  = 0; // ByCreated
    result["order"] = 0; // Descending
    if (q.exec() && q.next()) {
        QStringList parts = q.value(0).toString().split(',');
        if (parts.size() == 2) {
            result["role"]  = parts[0].toInt();
            result["order"] = parts[1].toInt();
        }
    }
    return result;
}

int DatabaseManager::emptyTrash() {
    checkConnection();
    QSqlQuery sel(m_db);
    sel.exec("SELECT id, file_path FROM media WHERE is_trashed = 1");

    QList<QPair<int, QString>> trashed;
    while (sel.next())
        trashed.append({sel.value(0).toInt(), sel.value(1).toString()});

    if (trashed.isEmpty()) return 0;

    m_db.transaction();
    QSqlQuery delMedia(m_db);
    delMedia.prepare("DELETE FROM media WHERE id = ?");
    QSqlQuery delThumb(m_db);
    delThumb.prepare("DELETE FROM thumbnails WHERE file_path = ?");

    int deleted = 0;
    for (auto &[id, path] : trashed) {
        QFile::remove(path);
        delMedia.addBindValue(id);
        delMedia.exec();
        delThumb.addBindValue(path);
        delThumb.exec();
        ++deleted;
    }
    m_db.commit();

    qDebug() << "emptyTrash: permanently deleted" << deleted << "files";
    return deleted;
}

int DatabaseManager::pruneOrphanedMedia() {
    // Safe to call from any thread: uses checkConnection() + thread-local db handle
    // (same pattern as getAllMedia), never touches m_db from a foreign thread.
    checkConnection();
    const QString connName = (QThread::currentThread() == qApp->thread())
        ? QLatin1String("qt_sql_default_connection")
        : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);
    if (!db.isOpen()) return 0;

    QSqlQuery sel(db);
    sel.exec("SELECT file_path FROM media");

    QStringList missing;
    while (sel.next()) {
        const QString fp = sel.value(0).toString();
        if (!QFileInfo::exists(fp))
            missing.append(fp);
    }

    if (missing.isEmpty()) return 0;

    db.transaction();
    QSqlQuery del(db);
    del.prepare("DELETE FROM media WHERE file_path = ?");
    QSqlQuery delThumb(db);
    delThumb.prepare("DELETE FROM thumbnails WHERE file_path = ?");
    for (const QString &fp : missing) {
        del.addBindValue(fp);
        del.exec();
        delThumb.addBindValue(fp);
        delThumb.exec();
    }
    db.commit();

    qDebug() << "pruneOrphanedMedia: removed" << missing.size() << "entries for missing files";
    return missing.size();
}

// ── Scan exclusion patterns ───────────────────────────────────────────────────

QStringList DatabaseManager::getScanExclusions() {
    QSqlDatabase db = openThreadDb(m_dbPath);
    QSqlQuery q(db);
    q.exec("SELECT pattern FROM scan_exclusions ORDER BY pattern");
    QStringList list;
    while (q.next())
        list.append(q.value(0).toString());
    return list;
}

bool DatabaseManager::addScanExclusion(const QString &pattern) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("INSERT OR IGNORE INTO scan_exclusions (pattern) VALUES (:p)");
    q.bindValue(":p", pattern.trimmed());
    return q.exec();
}

bool DatabaseManager::removeScanExclusion(const QString &pattern) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM scan_exclusions WHERE pattern = :p");
    q.bindValue(":p", pattern);
    return q.exec();
}

// ── Hidden media ──────────────────────────────────────────────────────────────

bool DatabaseManager::setHidden(int mediaId, bool hidden) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("UPDATE media SET is_hidden = :v WHERE id = :id");
    q.bindValue(":v", hidden ? 1 : 0);
    q.bindValue(":id", mediaId);
    return q.exec();
}

bool DatabaseManager::setIgnored(int mediaId, bool ignored) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("UPDATE media SET is_ignored = :v WHERE id = :id");
    q.bindValue(":v", ignored ? 1 : 0);
    q.bindValue(":id", mediaId);
    return q.exec();
}

QVariantList DatabaseManager::getIgnoredMedia() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT id, file_path FROM media WHERE is_ignored = 1 ORDER BY file_path");
    QVariantList list;
    while (q.next()) {
        const QString path = q.value(1).toString();
        QVariantMap map;
        map["id"]      = q.value(0).toInt();
        map["path"]    = path;
        map["name"]    = QFileInfo(path).fileName();
        map["thumb"]   = ThumbnailGenerator::thumbnailUrl(path);
        map["isMedia"] = true;   // distinguishes single files from folder ignores
        list.append(map);
    }
    return list;
}

bool DatabaseManager::hasHiddenPassword() {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("SELECT value FROM settings_kv WHERE key = 'hidden_password_hash'");
    q.exec();
    return q.next() && !q.value(0).toString().isEmpty();
}

bool DatabaseManager::checkHiddenPassword(const QString &password) {
    checkConnection();
    QSqlQuery q(m_db);
    q.prepare("SELECT value FROM settings_kv WHERE key = 'hidden_password_hash'");
    q.exec();
    if (!q.next()) return false;
    QString stored = q.value(0).toString();
    QString hash = QString::fromLatin1(
        QCryptographicHash::hash(password.toUtf8(), QCryptographicHash::Sha256).toHex());
    return hash == stored;
}

bool DatabaseManager::setHiddenPassword(const QString &password) {
    checkConnection();
    QString hash = QString::fromLatin1(
        QCryptographicHash::hash(password.toUtf8(), QCryptographicHash::Sha256).toHex());
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO settings_kv (key, value) VALUES ('hidden_password_hash', :h) "
              "ON CONFLICT(key) DO UPDATE SET value = :h");
    q.bindValue(":h", hash);
    return q.exec();
}

// ── Album metadata & virtual albums ──────────────────────────────────────────

QString DatabaseManager::getRandomPhotoPath() {
    checkConnection();
    QSqlQuery q(m_db);
    q.exec("SELECT file_path FROM media WHERE is_trashed=0 AND mime_type NOT LIKE 'video/%' "
           "ORDER BY RANDOM() LIMIT 1");
    return q.next() ? q.value(0).toString() : QString();
}

void DatabaseManager::revealInFolder(const QString &filePath) {
    if (filePath.isEmpty()) return;

    const QString uri = QUrl::fromLocalFile(filePath).toString();

    // Preferred: portable freedesktop file-manager interface — selects the file
    // in whatever file manager is the session default (Dolphin on KDE, etc.).
    QDBusInterface fm(QStringLiteral("org.freedesktop.FileManager1"),
                      QStringLiteral("/org/freedesktop/FileManager1"),
                      QStringLiteral("org.freedesktop.FileManager1"),
                      QDBusConnection::sessionBus());
    QDBusReply<void> reply = fm.call(QStringLiteral("ShowItems"),
                                     QStringList{uri}, QString());
    if (reply.isValid()) return;

    // Fallback: no FileManager1 provider — just open the containing folder.
    qWarning() << "revealInFolder: FileManager1 unavailable, opening parent dir."
               << reply.error().message();
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(filePath).absolutePath()));
}

QString DatabaseManager::createVirtualAlbum(const QString &name, const QString &desc,
                                             const QString &coverPath) {
    checkConnection();
    QString safeName = name.simplified().replace(' ', '_').replace('/', '_');
    QString prefix   = "__virtual__" + safeName;

    QString cover = coverPath;
    if (cover.isEmpty()) {
        QSqlQuery rnd(m_db);
        rnd.exec("SELECT file_path FROM media WHERE is_trashed=0 AND mime_type NOT LIKE 'video/%' "
                 "ORDER BY RANDOM() LIMIT 1");
        if (rnd.next()) cover = rnd.value(0).toString();
    }

    QSqlQuery q(m_db);
    q.prepare("INSERT INTO albums (name, path_prefix, description, cover_path) "
              "VALUES (:n, :p, :d, :c) "
              "ON CONFLICT(path_prefix) DO UPDATE SET "
              "name=excluded.name, description=excluded.description, cover_path=excluded.cover_path");
    q.bindValue(":n", name);
    q.bindValue(":p", prefix);
    q.bindValue(":d", desc);
    q.bindValue(":c", cover);
    if (!q.exec()) {
        qWarning() << "createVirtualAlbum failed:" << q.lastError().text();
        return {};
    }
    return prefix;
}

bool DatabaseManager::updateAlbumMeta(const QString &pathPrefix, const QString &customName,
                                       const QString &desc, const QString &coverPath) {
    checkConnection();
    // Ensure row exists before updating
    {
        QSqlQuery ins(m_db);
        ins.prepare("INSERT OR IGNORE INTO albums (name, path_prefix) VALUES (:n, :p)");
        ins.bindValue(":n", customName.isEmpty() ? pathPrefix : customName);
        ins.bindValue(":p", pathPrefix);
        ins.exec();
    }
    QSqlQuery q(m_db);
    q.prepare("UPDATE albums SET custom_name=:cn, description=:d, cover_path=:c "
              "WHERE path_prefix=:p");
    q.bindValue(":cn", customName);
    q.bindValue(":d",  desc);
    q.bindValue(":c",  coverPath);
    q.bindValue(":p",  pathPrefix);
    return q.exec();
}

bool DatabaseManager::moveMediaToAlbum(int mediaId, const QString &targetFolderPath) {
    checkConnection();
    QSqlQuery sel(m_db);
    sel.prepare("SELECT file_path FROM media WHERE id = :id");
    sel.bindValue(":id", mediaId);
    if (!sel.exec() || !sel.next()) return false;

    QString srcPath = sel.value(0).toString();
    QFileInfo fi(srcPath);
    QString destPath = targetFolderPath + "/" + fi.fileName();

    // Resolve name collision
    if (QFile::exists(destPath) && destPath != srcPath) {
        QString base = fi.completeBaseName();
        QString ext  = fi.suffix();
        int n = 1;
        do {
            destPath = targetFolderPath + "/" + base + "_" + QString::number(n++)
                       + (ext.isEmpty() ? "" : "." + ext);
        } while (QFile::exists(destPath));
    }

    if (!QFile::rename(srcPath, destPath)) {
        qWarning() << "moveMediaToAlbum: rename failed" << srcPath << "->" << destPath;
        return false;
    }

    // Also move any stored thumbnail blobs
    QSqlQuery thumbUpd(m_db);
    thumbUpd.prepare("UPDATE thumbnails SET file_path=:new WHERE file_path=:old");
    thumbUpd.bindValue(":new", destPath);
    thumbUpd.bindValue(":old", srcPath);
    thumbUpd.exec();

    QSqlQuery upd(m_db);
    upd.prepare("UPDATE media SET file_path=:fp, folder_path=:folder WHERE id=:id");
    upd.bindValue(":fp",     destPath);
    upd.bindValue(":folder", targetFolderPath);
    upd.bindValue(":id",     mediaId);
    return upd.exec();
}

QVariantList DatabaseManager::getAlbumList() {
    checkConnection();
    QVariantList list;
    QSqlQuery q(m_db);
    // Folder-based, non-ignored
    q.exec("SELECT DISTINCT m.folder_path, COALESCE(a.custom_name,'') "
           "FROM media m "
           "LEFT JOIN albums a ON a.path_prefix = m.folder_path "
           "WHERE m.is_trashed = 0 "
           "AND COALESCE(m.folder_path,'') NOT IN "
           "  (SELECT COALESCE(path_prefix,'') FROM albums WHERE is_ignored = 1) "
           "ORDER BY m.folder_path");
    while (q.next()) {
        QVariantMap m;
        QString fp         = q.value(0).toString();
        QString customName = q.value(1).toString();
        m["path"] = fp;
        m["name"] = customName.isEmpty() ? QDir(fp).dirName() : customName;
        list.append(m);
    }
    return list;
}
