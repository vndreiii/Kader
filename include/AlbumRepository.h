#pragma once
#include <QString>
#include <QVariantList>

class DatabaseManager;

class AlbumRepository {
public:
    explicit AlbumRepository(DatabaseManager *db);

    QVariantList getAlbums(bool hideIgnored = true);
    QVariantList getAlbumList();
    QVariantList getIgnoredFolders();

    bool    ignore(const QString &path, bool ignored);
    bool    pin(const QString &path, bool pinned);
    bool    trash(const QString &path);
    QString createVirtual(const QString &name, const QString &desc, const QString &cover);
    bool    updateMeta(const QString &pathPrefix, const QString &name,
                       const QString &desc, const QString &cover);
    bool    moveMediaTo(int mediaId, const QString &targetPath);
    QString randomPhotoPath();

private:
    DatabaseManager *m_db;
};
