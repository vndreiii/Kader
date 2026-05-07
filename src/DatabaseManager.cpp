#include "DatabaseManager.h"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QSqlRecord>

DatabaseManager::DatabaseManager(QObject *parent) : QObject(parent) {
    m_dbPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/gallery.db";
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
    openDatabase();
}

DatabaseManager::~DatabaseManager() {
    if (m_db.isOpen()) {
        m_db.close();
    }
}

bool DatabaseManager::openDatabase() {
    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName(m_dbPath);

    if (!m_db.open()) {
        qCritical() << "Error opening database:" << m_db.lastError().text();
        return false;
    }

    return createTables();
}

bool DatabaseManager::createTables() {
    QSqlQuery query;
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

    if (!success) {
        qCritical() << "Error creating media table:" << query.lastError().text();
        return false;
    }

    success = query.exec(
        "CREATE TABLE IF NOT EXISTS albums ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT UNIQUE,"
        "path_prefix TEXT,"
        "cover_media_id INTEGER,"
        "is_pinned BOOLEAN DEFAULT 0,"
        "FOREIGN KEY(cover_media_id) REFERENCES media(id)"
        ")"
    );

    if (!success) {
        qCritical() << "Error creating albums table:" << query.lastError().text();
    }

    return success;
}

bool DatabaseManager::addOrUpdateMedia(const QString &filePath, const QString &hash, 
                                     qint64 size, const QString &mimeType, 
                                     const QDateTime &creationDate, int width, int height) {
    QFileInfo fileInfo(filePath);
    QString folderPath = fileInfo.absolutePath();

    QSqlQuery query;
    query.prepare(
        "INSERT OR REPLACE INTO media (file_path, folder_path, file_hash, file_size, mime_type, creation_date, width, height) "
        "VALUES (:path, :folder, :hash, :size, :mime, :date, :w, :h)"
    );
    query.bindValue(":path", filePath);
    query.bindValue(":folder", folderPath);
    query.bindValue(":hash", hash);
    query.bindValue(":size", size);
    query.bindValue(":mime", mimeType);
    query.bindValue(":date", creationDate.toSecsSinceEpoch());
    query.bindValue(":w", width);
    query.bindValue(":h", height);

    if (!query.exec()) {
        qWarning() << "Error adding/updating media:" << query.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::needsUpdate(const QString &filePath, qint64 size) {
    QSqlQuery query;
    query.prepare("SELECT file_size FROM media WHERE file_path = :path");
    query.bindValue(":path", filePath);

    if (query.exec() && query.next()) {
        qint64 storedSize = query.value(0).toLongLong();
        return storedSize != size;
    }
    return true; // Not found, needs insert
}

QVariantList DatabaseManager::getAlbums() {
    QVariantList list;
    QSqlQuery query(
        "SELECT folder_path, COUNT(*), SUM(file_size), MIN(file_path) "
        "FROM media GROUP BY folder_path ORDER BY folder_path ASC"
    );

    while (query.next()) {
        QVariantMap map;
        map["folder_path"] = query.value(0);
        map["count"] = query.value(1);
        map["size"] = query.value(2);
        map["cover"] = query.value(3);
        
        // Extract album name from path
        QString path = query.value(0).toString();
        map["name"] = QDir(path).dirName();
        
        list.append(map);
    }
    return list;
}

QVariantList DatabaseManager::getAllMedia() {
    QVariantList list;
    QSqlQuery query("SELECT * FROM media ORDER BY creation_date DESC");

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
