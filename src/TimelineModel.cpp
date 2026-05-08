#include "TimelineModel.h"
#include "DatabaseManager.h"
#include <QDateTime>

TimelineModel::TimelineModel(DatabaseManager *db, QObject *parent)
    : QAbstractListModel(parent), m_db(db) {
    refresh();
}

int TimelineModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return m_groups.count();
}

QVariant TimelineModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_groups.count())
        return QVariant();

    const MonthGroup &group = m_groups.at(index.row());

    switch (role) {
        case NameRole: return group.name;
        case ItemsRole: return group.items;
        default: return QVariant();
    }
}

QHash<int, QByteArray> TimelineModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[NameRole] = "name";
    roles[ItemsRole] = "items";
    return roles;
}

void TimelineModel::refresh(bool hideIgnored) {
    beginResetModel();
    m_groups.clear();

    QVariantList allMedia = m_db->getAllMedia(hideIgnored);
    
    QString currentMonth;
    MonthGroup *currentGroup = nullptr;

    for (const QVariant &v : allMedia) {
        QVariantMap item = v.toMap();
        qint64 timestamp = item.value("creation_date").toLongLong();
        QDateTime dt = QDateTime::fromSecsSinceEpoch(timestamp);
        QString month = dt.toString("MMMM yyyy");

        if (month != currentMonth) {
            currentMonth = month;
            m_groups.append({month, QVariantList()});
            currentGroup = &m_groups.last();
        }

        if (currentGroup) {
            // Add useful fields for QML
            item["thumb"] = item.value("file_path").toString(); // Generator handles hashing
            item["path"] = "file://" + item.value("file_path").toString();
            currentGroup->items.append(item);
        }
    }

    endResetModel();
}
