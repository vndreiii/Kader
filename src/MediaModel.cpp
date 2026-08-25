#include "MediaModel.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <algorithm>
#include <QDateTime>
#include <QString>
#include <QUrl>

MediaModel::MediaModel(DatabaseManager *db, ThumbnailGenerator *thumb, QObject *parent)
    : QAbstractListModel(parent), m_db(db), m_thumb(thumb) {
    refresh();
}

int MediaModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return m_data.count();
}

QVariant MediaModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_data.count())
        return QVariant();

    const QVariantMap &item = m_data.at(index.row()).toMap();

    switch (role) {
        case IdRole: return item.value("id");
        case PathRole: return "file://" + item.value("file_path").toString();
        case ThumbRole:
            // Hand back the image-provider URL rather than generating here:
            // data() runs on the GUI thread, and getOrCreateThumbnail() decodes
            // the image inline (libvips/LibRaw, or an ffmpegthumbnailer
            // subprocess for video) behind a mutex the background cache builder
            // also holds. Routing through ThumbnailProvider — registered with
            // ForceAsynchronousImageLoading, same as TimelineModel already does
            // — keeps the decode off the GUI thread entirely.
            return ThumbnailGenerator::thumbnailUrl(item.value("file_path").toString());
        case DateRole: return item.value("creation_date");
        case MimeRole: return item.value("mime_type");
        case WidthRole: return item.value("width");
        case HeightRole: return item.value("height");
        case SectionRole: {
            qint64 timestamp = item.value("creation_date").toLongLong();
            QDateTime dt = QDateTime::fromSecsSinceEpoch(timestamp);
            return dt.toString("MMMM yyyy");
        }
        case SelectedRole: return item.value("selected", false);
        case FavoriteRole: return item.value("is_favorite", 0).toBool();
        case TrashedRole: return item.value("is_trashed", 0).toBool();
        case SizeRole: return item.value("file_size");
        case HiddenRole: return item.value("is_hidden", 0).toBool();
        case IgnoredRole: return item.value("is_ignored", 0).toBool();
        default: return QVariant();
    }
}

bool MediaModel::setData(const QModelIndex &index, const QVariant &value, int role) {
    if (!index.isValid() || index.row() >= m_data.count())
        return false;

    if (role == SelectedRole) {
        QVariantMap map = m_data.at(index.row()).toMap();
        map["selected"] = value.toBool();
        m_data[index.row()] = map;
        emit dataChanged(index, index, {role});
        return true;
    }
    return false;
}

QHash<int, QByteArray> MediaModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[PathRole] = "path";
    roles[ThumbRole] = "thumb";
    roles[DateRole] = "date";
    roles[MimeRole] = "mimeType";
    roles[WidthRole] = "width";
    roles[HeightRole] = "height";
    roles[SectionRole] = "section";
    roles[SelectedRole] = "isSelected";
    roles[FavoriteRole] = "isFavorite";
    roles[TrashedRole] = "isTrashed";
    roles[SizeRole] = "fileSize";
    roles[HiddenRole] = "isHidden";
    roles[IgnoredRole] = "isIgnored";
    return roles;
}

void MediaModel::clearSelection() {
    for (int i = 0; i < m_data.count(); ++i) {
        QVariantMap map = m_data.at(i).toMap();
        if (map.value("selected", false).toBool()) {
            map["selected"] = false;
            m_data[i] = map;
            emit dataChanged(index(i, 0), index(i, 0), {SelectedRole});
        }
    }
}

void MediaModel::selectAll() {
    for (int i = 0; i < m_data.count(); ++i) {
        QVariantMap map = m_data.at(i).toMap();
        if (!map.value("selected", false).toBool()) {
            map["selected"] = true;
            m_data[i] = map;
            emit dataChanged(index(i, 0), index(i, 0), {SelectedRole});
        }
    }
}

void MediaModel::sortBy(int field, bool ascending) {
    beginResetModel();
    std::stable_sort(m_data.begin(), m_data.end(),
                     [field, ascending](const QVariant &a, const QVariant &b) {
        const QVariantMap ma = a.toMap();
        const QVariantMap mb = b.toMap();
        int cmp = 0;
        switch (field) {
            case 0: { // Name (file name, case-insensitive)
                const QString na = ma.value("file_path").toString().section('/', -1).toLower();
                const QString nb = mb.value("file_path").toString().section('/', -1).toLower();
                cmp = QString::compare(na, nb);
                break;
            }
            case 2: { // Size
                const qint64 sa = ma.value("file_size").toLongLong();
                const qint64 sb = mb.value("file_size").toLongLong();
                cmp = (sa < sb) ? -1 : (sa > sb) ? 1 : 0;
                break;
            }
            case 3: { // Format (mime type)
                cmp = QString::compare(ma.value("mime_type").toString(),
                                       mb.value("mime_type").toString());
                break;
            }
            case 1:
            default: { // Date
                const qint64 da = ma.value("creation_date").toLongLong();
                const qint64 db = mb.value("creation_date").toLongLong();
                cmp = (da < db) ? -1 : (da > db) ? 1 : 0;
                break;
            }
        }
        return ascending ? (cmp < 0) : (cmp > 0);
    });
    endResetModel();
}

QStringList MediaModel::getSelectedPaths() const {
    QStringList paths;
    for (const auto& v : m_data) {
        QVariantMap map = v.toMap();
        if (map.value("selected", false).toBool()) {
            paths.append(map.value("file_path").toString());
        }
    }
    return paths;
}

void MediaModel::refresh(bool hideIgnored) {
    beginResetModel();
    // Dashboard's flat list must never show trashed/hidden rows, and must never
    // let them reappear after a delete — filter both out at the source.
    m_data = m_db->getAllMedia(hideIgnored, DatabaseManager::ByCreated,
                                DatabaseManager::Descending,
                                /*excludeTrashed=*/true, /*excludeHidden=*/true);
    endResetModel();
}

// Normalize a "file://"-prefixed path (as returned by PathRole) to a plain
// local path so it can be compared against the stored file_path values.
static QString normalizedLocalPath(const QString &path) {
    return path.startsWith(QLatin1String("file://")) ? QUrl(path).toLocalFile() : path;
}

void MediaModel::removeByPath(const QString &path) {
    const QString target = normalizedLocalPath(path);
    for (int i = 0; i < m_data.count(); ++i) {
        const QVariantMap map = m_data.at(i).toMap();
        if (map.value("file_path").toString() == target) {
            beginRemoveRows(QModelIndex(), i, i);
            m_data.removeAt(i);
            endRemoveRows();
            return;
        }
    }
}

void MediaModel::removeSelected() {
    for (int i = m_data.count() - 1; i >= 0; --i) {
        const QVariantMap map = m_data.at(i).toMap();
        if (map.value("selected", false).toBool()) {
            beginRemoveRows(QModelIndex(), i, i);
            m_data.removeAt(i);
            endRemoveRows();
        }
    }
}
