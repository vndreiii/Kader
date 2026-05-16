#include "AlbumModel.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"

AlbumModel::AlbumModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent)
    : QAbstractListModel(parent), m_db(db), m_thumb(thumb) {
    refresh();
}

int AlbumModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return m_data.count();
}

QVariant AlbumModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_data.count())
        return QVariant();

    const QVariantMap &item = m_data.at(index.row()).toMap();

    switch (role) {
        case NameRole: return item.value("name");
        case PathRole: return item.value("folder_path");
        case CountRole: return item.value("count");
        case SizeRole: {
            qint64 bytes = item.value("size").toLongLong();
            if (bytes < 1024) return QString::number(bytes) + " B";
            if (bytes < 1024 * 1024) return QString::number(bytes / 1024.0, 'f', 1) + " KB";
            if (bytes < 1024 * 1024 * 1024) return QString::number(bytes / (1024.0 * 1024.0), 'f', 1) + " MB";
            return QString::number(bytes / (1024.0 * 1024.0 * 1024.0), 'f', 1) + " GB";
        }
        case CoverRole: {
            QString coverPath = item.value("cover").toString();
            QString thumb = m_thumb->getOrCreateThumbnail(coverPath);
            return thumb.isEmpty() ? "" : "file://" + thumb;
        }
        default: return QVariant();
    }
}

QHash<int, QByteArray> AlbumModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[NameRole] = "name";
    roles[PathRole] = "path";
    roles[CountRole] = "count";
    roles[SizeRole] = "size";
    roles[CoverRole] = "cover";
    return roles;
}

void AlbumModel::refresh(bool hideIgnored) {
    beginResetModel();
    m_data = m_db->getAlbums(hideIgnored);
    if (!m_searchFilter.isEmpty()) {
        const QString q = m_searchFilter.toLower();
        QVariantList filtered;
        for (const QVariant &v : m_data)
            if (v.toMap().value("name").toString().toLower().contains(q))
                filtered.append(v);
        m_data = filtered;
    }
    qDebug() << "Album refresh: loaded" << m_data.size() << "albums";
    endResetModel();
}

void AlbumModel::setSearchFilter(const QString &query) {
    if (m_searchFilter != query) {
        m_searchFilter = query;
        emit searchFilterChanged();
        refresh();
    }
}
