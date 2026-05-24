#include "AlbumRepository.h"
#include "DatabaseManager.h"
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QDebug>

AlbumRepository::AlbumRepository(DatabaseManager *db) : m_db(db) {}

QVariantList AlbumRepository::getAlbums(bool hideIgnored) {
    QSqlDatabase db = m_db->threadDb();
    QVariantList list;
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
    QSqlQuery q(db);
    if (!q.exec(sql)) {
        qWarning() << "[AlbumRepo] getAlbums failed:" << q.lastError().text();
        return list;
    }
    while (q.next()) {
        QVariantMap map;
        QString fp         = q.value(0).toString();
        QString customName = q.value(4).toString();
        QString coverPath  = q.value(6).toString();
        QString coverFile  = q.value(3).toString();
        map["folder_path"] = fp;
        map["count"]       = q.value(1);
        map["size"]        = q.value(2);
        map["cover_file"]  = coverFile;
        map["cover_path"]  = coverPath;
        map["cover"]       = coverPath.isEmpty() ? coverFile : coverPath;
        map["pinned"]      = q.value(5).toBool();
        map["description"] = q.value(7);
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

QVariantList AlbumRepository::getAlbumList() {
    QSqlDatabase db = m_db->threadDb();
    QVariantList list;
    QSqlQuery q(db);
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

QVariantList AlbumRepository::getIgnoredFolders() {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.exec("SELECT path_prefix FROM albums WHERE is_ignored = 1 ORDER BY path_prefix");
    QVariantList list;
    while (q.next()) {
        QString path = q.value(0).toString();
        QVariantMap map;
        map["path"] = path;
        map["name"] = QDir(path).dirName();
        list.append(map);
    }
    return list;
}

bool AlbumRepository::ignore(const QString &path, bool ignored) {
    QSqlDatabase db = m_db->threadDb();
    {
        QSqlQuery q(db);
        q.prepare("UPDATE albums SET is_ignored = :v WHERE path_prefix = :path");
        q.bindValue(":v", ignored ? 1 : 0);
        q.bindValue(":path", path);
        q.exec();
        if (q.numRowsAffected() > 0) return true;
    }
    QSqlQuery q(db);
    q.prepare("INSERT INTO albums (name, path_prefix, is_ignored) VALUES (:n, :p, :v) "
              "ON CONFLICT(path_prefix) DO UPDATE SET is_ignored = excluded.is_ignored");
    q.bindValue(":n", path);
    q.bindValue(":p", path);
    q.bindValue(":v", ignored ? 1 : 0);
    return q.exec();
}

bool AlbumRepository::pin(const QString &path, bool pinned) {
    QSqlDatabase db = m_db->threadDb();
    {
        QSqlQuery q(db);
        q.prepare("UPDATE albums SET is_pinned = :v WHERE path_prefix = :path");
        q.bindValue(":v", pinned ? 1 : 0);
        q.bindValue(":path", path);
        q.exec();
        if (q.numRowsAffected() > 0) return true;
    }
    QSqlQuery q(db);
    q.prepare("INSERT INTO albums (name, path_prefix, is_pinned) VALUES (:n, :p, :v) "
              "ON CONFLICT(path_prefix) DO UPDATE SET is_pinned = excluded.is_pinned");
    q.bindValue(":n", path);
    q.bindValue(":p", path);
    q.bindValue(":v", pinned ? 1 : 0);
    return q.exec();
}

bool AlbumRepository::trash(const QString &path) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("UPDATE media SET is_trashed = 1 WHERE folder_path = :path");
    q.bindValue(":path", path);
    return q.exec();
}

QString AlbumRepository::createVirtual(const QString &name, const QString &desc, const QString &cover) {
    QSqlDatabase db = m_db->threadDb();
    QString safeName = name.simplified().replace(' ', '_').replace('/', '_');
    QString prefix   = "__virtual__" + safeName;
    QString coverPath = cover;
    if (coverPath.isEmpty()) {
        QSqlQuery rnd(db);
        rnd.exec("SELECT file_path FROM media WHERE is_trashed=0 AND mime_type NOT LIKE 'video/%' "
                 "ORDER BY RANDOM() LIMIT 1");
        if (rnd.next()) coverPath = rnd.value(0).toString();
    }
    QSqlQuery q(db);
    q.prepare("INSERT INTO albums (name, path_prefix, description, cover_path) "
              "VALUES (:n, :p, :d, :c) "
              "ON CONFLICT(path_prefix) DO UPDATE SET "
              "name=excluded.name, description=excluded.description, cover_path=excluded.cover_path");
    q.bindValue(":n", name);
    q.bindValue(":p", prefix);
    q.bindValue(":d", desc);
    q.bindValue(":c", coverPath);
    if (!q.exec()) {
        qWarning() << "createVirtual failed:" << q.lastError().text();
        return {};
    }
    return prefix;
}

bool AlbumRepository::updateMeta(const QString &pathPrefix, const QString &name,
                                  const QString &desc, const QString &cover) {
    QSqlDatabase db = m_db->threadDb();
    {
        QSqlQuery ins(db);
        ins.prepare("INSERT OR IGNORE INTO albums (name, path_prefix) VALUES (:n, :p)");
        ins.bindValue(":n", name.isEmpty() ? pathPrefix : name);
        ins.bindValue(":p", pathPrefix);
        ins.exec();
    }
    QSqlQuery q(db);
    q.prepare("UPDATE albums SET custom_name=:cn, description=:d, cover_path=:c WHERE path_prefix=:p");
    q.bindValue(":cn", name);
    q.bindValue(":d",  desc);
    q.bindValue(":c",  cover);
    q.bindValue(":p",  pathPrefix);
    return q.exec();
}

bool AlbumRepository::moveMediaTo(int mediaId, const QString &targetPath) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery sel(db);
    sel.prepare("SELECT file_path FROM media WHERE id = :id");
    sel.bindValue(":id", mediaId);
    if (!sel.exec() || !sel.next()) return false;
    QString srcPath = sel.value(0).toString();
    QFileInfo fi(srcPath);
    QString destPath = targetPath + "/" + fi.fileName();
    if (QFile::exists(destPath) && destPath != srcPath) {
        QString base = fi.completeBaseName();
        QString ext  = fi.suffix();
        int n = 1;
        do {
            destPath = targetPath + "/" + base + "_" + QString::number(n++)
                       + (ext.isEmpty() ? "" : "." + ext);
        } while (QFile::exists(destPath));
    }
    if (!QFile::rename(srcPath, destPath)) {
        qWarning() << "moveMediaTo: rename failed" << srcPath << "->" << destPath;
        return false;
    }
    {
        QSqlQuery thumbUpd(db);
        thumbUpd.prepare("UPDATE thumbnails SET file_path=:new WHERE file_path=:old");
        thumbUpd.bindValue(":new", destPath);
        thumbUpd.bindValue(":old", srcPath);
        thumbUpd.exec();
    }
    QSqlQuery upd(db);
    upd.prepare("UPDATE media SET file_path=:fp, folder_path=:folder WHERE id=:id");
    upd.bindValue(":fp",     destPath);
    upd.bindValue(":folder", targetPath);
    upd.bindValue(":id",     mediaId);
    return upd.exec();
}

QString AlbumRepository::randomPhotoPath() {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.exec("SELECT file_path FROM media WHERE is_trashed=0 AND mime_type NOT LIKE 'video/%' "
           "ORDER BY RANDOM() LIMIT 1");
    return q.next() ? q.value(0).toString() : QString();
}
