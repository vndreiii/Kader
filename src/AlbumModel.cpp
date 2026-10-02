#include "AlbumModel.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include "Sort.h"

AlbumModel::AlbumModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent)
    : QAbstractListModel(parent), m_db(db), m_thumb(thumb) {
    // Populated by main.cpp; the standalone viewer never needs albums.
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
            // Image-provider URL, not an inline decode: see the matching note in
            // MediaModel::data(). Generating the cover here blocked the GUI
            // thread on libvips (or ffmpegthumbnailer) for every album that
            // scrolled into view, and on the shared generator mutex whenever the
            // background cache builder held it.
            const QString coverPath = item.value("cover").toString();
            return coverPath.isEmpty() ? QString() : ThumbnailGenerator::thumbnailUrl(coverPath);
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
    if (!m_loaded) {
        m_loaded = true;
        emit loadedChanged();
    }
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

    // Map the album-specific sort role to a field name + comparison type, then
    // hand off to the shared Sort core (the same engine a future dashboard uses).
    // Pinned albums always lead, regardless of field/order.
    QString field;
    Sort::ValueType type;
    switch (m_sortRole) {
    case ByCount: field = "count"; type = Sort::Number; break;
    case BySize:  field = "size";  type = Sort::Number; break;
    default:      field = "name";  type = Sort::Text;   break; // ByName
    }
    Sort::sortList(m_data, field, type, asc, "pinned");
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
