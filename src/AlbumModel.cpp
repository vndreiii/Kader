#include "AlbumModel.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <algorithm>

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
        case NameRole:        return item.value("name");
        case PathRole:        return item.value("folder_path");
        case CountRole:       return item.value("count");
        case PinnedRole:      return item.value("pinned");
        case DescriptionRole: return item.value("description");
        case CoverPathRole:   return item.value("cover");
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
    roles[NameRole]        = "name";
    roles[PathRole]        = "path";
    roles[CountRole]       = "count";
    roles[SizeRole]        = "size";
    roles[CoverRole]       = "cover";
    roles[PinnedRole]      = "pinned";
    roles[DescriptionRole] = "description";
    roles[CoverPathRole]   = "coverPath";
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
    applySort();
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

// Sort the already-loaded album list in place. Operates purely on m_data, so it
// never touches the SQL/hidden filtering — hidden media can't leak in here.
void AlbumModel::applySort() {
    const bool asc = (m_sortOrder == 1);
    std::stable_sort(m_data.begin(), m_data.end(),
        [&](const QVariant &av, const QVariant &bv) {
            const QVariantMap a = av.toMap();
            const QVariantMap b = bv.toMap();
            // Pinned albums always come first, regardless of sort field/order.
            const bool pa = a.value("pinned").toBool();
            const bool pb = b.value("pinned").toBool();
            if (pa != pb) return pa;

            int cmp = 0;
            switch (m_sortRole) {
            case ByCount: {
                const qlonglong x = a.value("count").toLongLong();
                const qlonglong y = b.value("count").toLongLong();
                cmp = (x < y) ? -1 : (x > y) ? 1 : 0;
                break;
            }
            case BySize: {
                const qlonglong x = a.value("size").toLongLong();
                const qlonglong y = b.value("size").toLongLong();
                cmp = (x < y) ? -1 : (x > y) ? 1 : 0;
                break;
            }
            default: // ByName
                cmp = QString::compare(a.value("name").toString(),
                                       b.value("name").toString(),
                                       Qt::CaseInsensitive);
                break;
            }
            return asc ? (cmp < 0) : (cmp > 0);
        });
}

void AlbumModel::setSortRole(int role) {
    if (m_sortRole == role) return;
    m_sortRole = role;
    emit sortRoleChanged();
    beginResetModel();
    applySort();
    endResetModel();
}

void AlbumModel::setSortOrder(int order) {
    if (m_sortOrder == order) return;
    m_sortOrder = order;
    emit sortOrderChanged();
    beginResetModel();
    applySort();
    endResetModel();
}
