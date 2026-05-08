#include "DatabaseManager.h"
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

    return success;
}

bool DatabaseManager::ignoreAlbum(const QString &folderPath, bool ignore) {
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("INSERT INTO albums (name, path_prefix, is_ignored) "
                  "VALUES (:name, :path, :ignored) "
                  "ON CONFLICT(name) DO UPDATE SET is_ignored = :ignored");
    query.bindValue(":name", QDir(folderPath).dirName());
    query.bindValue(":path", folderPath);
    query.bindValue(":ignored", ignore);
    bool ok = query.exec();
    if (ok) {
        // Emit a signal later or just rely on manual refresh
    }
    return ok;
}

bool DatabaseManager::addOrUpdateMedia(const QString &filePath, const QString &hash, 
                                     qint64 size, const QString &mimeType, 
                                     const QDateTime &creationDate, int width, int height) {
    checkConnection();
    QFileInfo fileInfo(filePath);
    QString folderPath = fileInfo.absolutePath();

    QSqlQuery query(m_db);
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
    checkConnection();
    QSqlQuery query(m_db);
    query.prepare("SELECT file_size FROM media WHERE file_path = :path");
    query.bindValue(":path", filePath);

    if (query.exec() && query.next()) {
        qint64 storedSize = query.value(0).toLongLong();
        return storedSize != size;
    }
    return true;
}

QVariantList DatabaseManager::getAlbums() {
    checkConnection();
    QVariantList list;
    QSqlQuery query(
        "SELECT folder_path, COUNT(*), SUM(file_size), MIN(file_path) "
        "FROM media "
        "WHERE folder_path NOT IN (SELECT path_prefix FROM albums WHERE is_ignored = 1) "
        "GROUP BY folder_path ORDER BY folder_path ASC", m_db
    );

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

QVariantList DatabaseManager::getAllMedia() {
    checkConnection();
    QVariantList list;
    QSqlQuery query(
        "SELECT * FROM media "
        "WHERE folder_path NOT IN (SELECT path_prefix FROM albums WHERE is_ignored = 1) "
        "ORDER BY creation_date DESC", m_db
    );

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
