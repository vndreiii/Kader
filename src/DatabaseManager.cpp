#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QSqlRecord>
#include <QFileInfo>
#include <QThread>
#include <QCoreApplication>

DatabaseManager::DatabaseManager(QObject *parent) : QObject(parent) {
    m_dbPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/gallery.db";
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
    openDatabase();
}

DatabaseManager::~DatabaseManager() {
}

void DatabaseManager::checkConnection() {
    QString connectionName = "qt_sql_default_connection";
    if (QThread::currentThread() != qApp->thread()) {
        connectionName = QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    }

    if (QSqlDatabase::contains(connectionName)) {
        m_db = QSqlDatabase::database(connectionName);
    } else {
        m_db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
        m_db.setDatabaseName(m_dbPath);
    }

    if (!m_db.isOpen()) {
        if (!m_db.open()) {
            qCritical() << "Error opening database in thread" << connectionName << ":" << m_db.lastError().text();
        } else {
            createTables();
        }
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
    migrate("media",  "is_favorite", "BOOLEAN DEFAULT 0");
    migrate("media",  "is_trashed",  "BOOLEAN DEFAULT 0");
    migrate("media",  "latitude",    "REAL");
    migrate("media",  "longitude",   "REAL");

    return success;
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
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("UPDATE indexed_directories SET item_count = :count, last_scan = :now WHERE path = :path");
    query.bindValue(":count", count);
    query.bindValue(":now", QDateTime::currentDateTime().toSecsSinceEpoch());
    query.bindValue(":path", path);
    return query.exec();
}

bool DatabaseManager::ignoreAlbum(const QString &folderPath, bool ignore) {
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("INSERT INTO albums (name, path_prefix, is_ignored) "
                  "VALUES (:name, :path, :ignored) "
                  "ON CONFLICT(path_prefix) DO UPDATE SET is_ignored = :ignored");
    query.bindValue(":name", QDir(folderPath).dirName());
    query.bindValue(":path", folderPath);
    query.bindValue(":ignored", ignore ? 1 : 0);
    return query.exec();
}

bool DatabaseManager::addOrUpdateMedia(const QString &filePath, const QString &hash,
                                     qint64 size, const QString &mimeType,
                                     const QDateTime &creationDate, int width, int height,
                                     double latitude, double longitude) {
    checkConnection();
    QFileInfo fileInfo(filePath);
    QString folderPath = fileInfo.absolutePath();

    QSqlQuery query(m_db);
    query.prepare(
        "INSERT OR REPLACE INTO media "
        "(file_path, folder_path, file_hash, file_size, mime_type, creation_date, width, height, latitude, longitude) "
        "VALUES (:path, :folder, :hash, :size, :mime, :date, :w, :h, :lat, :lon)"
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

bool DatabaseManager::needsUpdate(const QString &filePath, qint64 size) {
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("SELECT file_size, creation_date FROM media WHERE file_path = :path");
    query.bindValue(":path", filePath);

    if (query.exec() && query.next()) {
        qint64 storedSize = query.value(0).toLongLong();
        qint64 storedDate = query.value(1).toLongLong();
        // Re-index if size changed or if EXIF was never extracted (date is 0).
        return storedSize != size || storedDate == 0;
    }
    return true; // Not in DB yet — insert it.
}

QVariantList DatabaseManager::getAlbums(bool hideIgnored) {
    checkConnection();

    QString connName = (QThread::currentThread() == qApp->thread())
                       ? QLatin1String("qt_sql_default_connection")
                       : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);

    QVariantList list;
    QString sql = "SELECT folder_path, COUNT(*), SUM(file_size), MIN(file_path) FROM media ";
    if (hideIgnored) {
        sql += "WHERE COALESCE(folder_path,'') NOT IN "
               "(SELECT COALESCE(path_prefix,'') FROM albums WHERE is_ignored = 1) ";
    }
    sql += "GROUP BY folder_path ORDER BY folder_path ASC";

    QSqlQuery query(db);
    if (!query.exec(sql)) {
        qWarning() << "[DB] getAlbums query failed:" << query.lastError().text();
        return list;
    }
    while (query.next()) {
        QVariantMap map;
        map["folder_path"] = query.value(0);
        map["count"] = query.value(1);
        map["size"] = query.value(2);
        map["cover"] = query.value(3);
        map["name"] = QDir(query.value(0).toString()).dirName();
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
    QSqlQuery query(db);
    if (!query.exec(
            "SELECT ROUND(latitude,2) AS lat, ROUND(longitude,2) AS lon, "
            "COUNT(*) AS cnt, MIN(file_path) AS sample "
            "FROM media "
            "WHERE latitude IS NOT NULL AND longitude IS NOT NULL "
            "  AND latitude != 0 AND longitude != 0 "
            "GROUP BY lat, lon "
            "ORDER BY cnt DESC "
            "LIMIT 500")) {
        qWarning() << "getGeotaggedLocations failed:" << query.lastError().text();
        return list;
    }
    while (query.next()) {
        QVariantMap m;
        m["lat"]   = query.value(0).toDouble();
        m["lon"]   = query.value(1).toDouble();
        m["count"] = query.value(2).toInt();
        m["thumb"] = ThumbnailGenerator::thumbnailUrl(query.value(3).toString());
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
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO albums (name, path_prefix, is_pinned) VALUES (:name, :path, :pin) "
              "ON CONFLICT(path_prefix) DO UPDATE SET is_pinned = :pin");
    q.bindValue(":name", QDir(folderPath).dirName());
    q.bindValue(":path", folderPath);
    q.bindValue(":pin",  pinned ? 1 : 0);
    return q.exec();
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

QVariantList DatabaseManager::getAllMedia(bool hideIgnored) {
    checkConnection();

    // Resolve the thread-local connection by name to avoid sharing m_db across threads.
    QString connName = (QThread::currentThread() == qApp->thread())
                       ? QLatin1String("qt_sql_default_connection")
                       : QString("connection_%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    QSqlDatabase db = QSqlDatabase::database(connName);

    QVariantList list;
    QString sql = "SELECT * FROM media ";
    if (hideIgnored) {
        sql += "WHERE COALESCE(folder_path,'') NOT IN "
               "(SELECT COALESCE(path_prefix,'') FROM albums WHERE is_ignored = 1) ";
    }
    sql += "ORDER BY creation_date DESC";

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
