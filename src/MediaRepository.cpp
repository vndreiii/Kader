#include "MediaRepository.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QFileInfo>
#include <QFile>
#include <QDebug>

MediaRepository::MediaRepository(DatabaseManager *db) : m_db(db) {}

bool MediaRepository::needsUpdate(const QString &filePath, qint64 size) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("SELECT file_size, creation_date, width, height FROM media WHERE file_path = :path");
    q.bindValue(":path", filePath);
    if (q.exec() && q.next()) {
        return q.value(0).toLongLong() != size
            || q.value(1).toLongLong() == 0
            || q.value(2).toInt() == 0
            || q.value(3).toInt() == 0;
    }
    return true;
}

bool MediaRepository::upsert(const MediaEntry &entry) {
    return upsertBatch({entry});
}

bool MediaRepository::upsertBatch(const QVector<MediaEntry> &entries) {
    if (entries.isEmpty()) return true;
    QSqlDatabase db = m_db->threadDb();
    if (!db.transaction()) {
        qWarning() << "upsertBatch: begin failed:" << db.lastError().text();
        return false;
    }
    QSqlQuery q(db);
    q.prepare(
        "INSERT INTO media "
        "(file_path, folder_path, file_hash, file_size, mime_type, creation_date, modified_date, width, height, latitude, longitude) "
        "VALUES (:path, :folder, :hash, :size, :mime, :date, :mdate, :w, :h, :lat, :lon) "
        "ON CONFLICT(file_path) DO UPDATE SET "
        "folder_path=excluded.folder_path, file_hash=excluded.file_hash, "
        "file_size=excluded.file_size, mime_type=excluded.mime_type, "
        "creation_date=excluded.creation_date, modified_date=excluded.modified_date, "
        "width=excluded.width, height=excluded.height, "
        "latitude=excluded.latitude, longitude=excluded.longitude"
    );
    for (const MediaEntry &e : entries) {
        q.bindValue(":path",   e.filePath);
        q.bindValue(":folder", e.folderPath);
        q.bindValue(":hash",   QString());
        q.bindValue(":size",   e.fileSize);
        q.bindValue(":mime",   e.mimeType);
        q.bindValue(":date",   e.creationDate.isValid()  ? e.creationDate.toSecsSinceEpoch()  : 0LL);
        q.bindValue(":mdate",  e.modifiedDate.isValid()  ? e.modifiedDate.toSecsSinceEpoch()  : 0LL);
        q.bindValue(":w",      e.width);
        q.bindValue(":h",      e.height);
        q.bindValue(":lat",    e.latitude  != 0.0 ? QVariant(e.latitude)  : QVariant(QMetaType::fromType<double>()));
        q.bindValue(":lon",    e.longitude != 0.0 ? QVariant(e.longitude) : QVariant(QMetaType::fromType<double>()));
        if (!q.exec()) {
            qWarning() << "upsertBatch row failed:" << q.lastError().text();
            db.rollback();
            return false;
        }
    }
    return db.commit();
}

QVariantList MediaRepository::getAll(bool hideIgnored) {
    QSqlDatabase db = m_db->threadDb();
    QVariantList list;
    QString sql = "SELECT * FROM media ";
    if (hideIgnored) {
        sql += "WHERE COALESCE(folder_path,'') NOT IN "
               "(SELECT COALESCE(path_prefix,'') FROM albums WHERE is_ignored = 1) ";
    }
    sql += "ORDER BY creation_date DESC";
    QSqlQuery q(db);
    if (!q.exec(sql)) {
        qWarning() << "getAll failed:" << q.lastError().text();
        return list;
    }
    while (q.next()) {
        QVariantMap map;
        QSqlRecord rec = q.record();
        for (int i = 0; i < rec.count(); ++i)
            map[rec.fieldName(i)] = q.value(i);
        list.append(map);
    }
    return list;
}

QVariantMap MediaRepository::getById(int mediaId) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
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

bool MediaRepository::setHidden(int mediaId, bool hidden) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("UPDATE media SET is_hidden = :v WHERE id = :id");
    q.bindValue(":v", hidden ? 1 : 0);
    q.bindValue(":id", mediaId);
    return q.exec();
}

bool MediaRepository::setTrashed(int mediaId, bool trashed) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("UPDATE media SET is_trashed = :v WHERE id = :id");
    q.bindValue(":v", trashed ? 1 : 0);
    q.bindValue(":id", mediaId);
    return q.exec();
}

bool MediaRepository::toggleFavorite(int mediaId) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("UPDATE media SET is_favorite = NOT is_favorite WHERE id = :id");
    q.bindValue(":id", mediaId);
    return q.exec();
}

bool MediaRepository::deletePermanently(int mediaId) {
    QSqlDatabase db = m_db->threadDb();
    {
        QSqlQuery pathQ(db);
        pathQ.prepare("SELECT file_path FROM media WHERE id = :id");
        pathQ.bindValue(":id", mediaId);
        if (pathQ.exec() && pathQ.next()) {
            QSqlQuery thumbQ(db);
            thumbQ.prepare("DELETE FROM thumbnails WHERE file_path = :path");
            thumbQ.bindValue(":path", pathQ.value(0).toString());
            thumbQ.exec();
        }
    }
    QSqlQuery q(db);
    q.prepare("DELETE FROM media WHERE id = :id");
    q.bindValue(":id", mediaId);
    return q.exec();
}

QVariantList MediaRepository::getGeotaggedLocations() {
    QSqlDatabase db = m_db->threadDb();
    QVariantList list;
    QSqlQuery q(db);
    if (!q.exec(
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
        qWarning() << "getGeotaggedLocations failed:" << q.lastError().text();
        return list;
    }
    while (q.next()) {
        QVariantMap m;
        QString fp = q.value("file_path").toString();
        m["lat"]           = q.value("lat").toDouble();
        m["lon"]           = q.value("lon").toDouble();
        m["count"]         = q.value("cnt").toInt();
        m["id"]            = q.value("id").toInt();
        m["file_path"]     = fp;
        m["mime_type"]     = q.value("mime_type").toString();
        m["creation_date"] = q.value("creation_date").toLongLong();
        m["is_favorite"]   = q.value("is_favorite").toBool();
        m["is_trashed"]    = q.value("is_trashed").toBool();
        m["is_hidden"]     = q.value("is_hidden").toBool();
        m["path"]          = "file://" + fp;
        m["thumb"]         = ThumbnailGenerator::thumbnailUrl(fp);
        list.append(m);
    }
    return list;
}

qint64 MediaRepository::totalSizeBytes() {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.exec("SELECT COALESCE(SUM(file_size), 0) FROM media WHERE is_trashed = 0");
    return q.next() ? q.value(0).toLongLong() : 0;
}

qint64 MediaRepository::photoSizeBytes() {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.exec("SELECT COALESCE(SUM(file_size), 0) FROM media WHERE is_trashed = 0 AND mime_type NOT LIKE 'video/%'");
    return q.next() ? q.value(0).toLongLong() : 0;
}

qint64 MediaRepository::videoSizeBytes() {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.exec("SELECT COALESCE(SUM(file_size), 0) FROM media WHERE is_trashed = 0 AND mime_type LIKE 'video/%'");
    return q.next() ? q.value(0).toLongLong() : 0;
}

int MediaRepository::pruneOrphaned() {
    QSqlDatabase db = m_db->threadDb();
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
    qDebug() << "pruneOrphaned: removed" << missing.size() << "entries";
    return missing.size();
}

int MediaRepository::emptyTrash() {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery sel(db);
    sel.exec("SELECT id, file_path FROM media WHERE is_trashed = 1");
    QList<QPair<int, QString>> trashed;
    while (sel.next())
        trashed.append({sel.value(0).toInt(), sel.value(1).toString()});
    if (trashed.isEmpty()) return 0;
    db.transaction();
    QSqlQuery delMedia(db);
    delMedia.prepare("DELETE FROM media WHERE id = ?");
    QSqlQuery delThumb(db);
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
    db.commit();
    qDebug() << "emptyTrash: permanently deleted" << deleted << "files";
    return deleted;
}
