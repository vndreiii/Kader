#include "MediaModel.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"

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
        case ThumbRole: {
            QString path = item.value("file_path").toString();
            QString thumb = m_thumb->getOrCreateThumbnail(path);
            return thumb.isEmpty() ? "" : "file://" + thumb;
        }
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
    m_data = m_db->getAllMedia(hideIgnored);
    endResetModel();
}
