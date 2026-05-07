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
        default: return QVariant();
    }
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
    return roles;
}

void MediaModel::refresh() {
    beginResetModel();
    m_data = m_db->getAllMedia();
    endResetModel();
}
