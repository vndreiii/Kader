#include "TimelineModel.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <QDateTime>
#include <QDebug>

TimelineModel::TimelineModel(DatabaseManager *db, QObject *parent)
    : QAbstractListModel(parent), m_db(db) {
    refresh();
}

int TimelineModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_rows.count();
}

QVariant TimelineModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_rows.count())
        return {};
    const Row &row = m_rows.at(index.row());
    switch (role) {
    case IsHeaderRole:  return row.isHeader;
    case MonthNameRole: return row.monthName;
    case ItemsRole:     return row.items;
    default:            return {};
    }
}

QHash<int, QByteArray> TimelineModel::roleNames() const {
    return {
        { IsHeaderRole,  "isHeader"  },
        { MonthNameRole, "monthName" },
        { ItemsRole,     "items"     }
    };
}

void TimelineModel::setFilterMode(FilterMode mode) {
    if (m_filterMode != mode) {
        m_filterMode = mode;
        emit filterModeChanged();
        refresh();
    }
}

void TimelineModel::setNumColumns(int n) {
    if (n > 0 && n != m_numColumns) {
        m_numColumns = n;
        emit numColumnsChanged();
        refresh();
    }
}

void TimelineModel::setFolderFilter(const QString &folder) {
    if (m_folderFilter != folder) {
        m_folderFilter = folder;
        emit folderFilterChanged();
        refresh();
    }
}

void TimelineModel::setSearchFilter(const QString &query) {
    if (m_searchFilter != query) {
        m_searchFilter = query;
        emit searchFilterChanged();
        refresh();
    }
}

QVariantList TimelineModel::getFlatMediaList() const {
    QVariantList flat;
    for (const Row &row : m_rows)
        if (!row.isHeader)
            flat.append(row.items);
    return flat;
}

void TimelineModel::refresh(bool hideIgnored) {
    beginResetModel();
    m_rows.clear();

    QVariantList allMedia = m_db->getAllMedia(hideIgnored);

    // In-memory folder filter
    if (!m_folderFilter.isEmpty()) {
        QVariantList filtered;
        for (const QVariant &v : allMedia)
            if (v.toMap().value("folder_path").toString() == m_folderFilter)
                filtered.append(v);
        allMedia = filtered;
    }

    // In-memory search filter (filename match)
    if (!m_searchFilter.isEmpty()) {
        const QString q = m_searchFilter.toLower();
        QVariantList filtered;
        for (const QVariant &v : allMedia)
            if (v.toMap().value("file_path").toString().toLower().contains(q))
                filtered.append(v);
        allMedia = filtered;
    }

    // Mosaic patterns: column spans cycling per row, reset at each month boundary.
    // Each pattern's spans must sum to m_numColumns (4).
    static const QVector<QVector<int>> kPatterns = {
        {1, 1, 1, 1},  // four equal tiles
        {2, 1, 1},     // one wide left + two small
        {1, 1, 2},     // two small + one wide right
        {2, 2},        // two wide
    };

    int patternIdx = 0;
    int flatIdx    = 0;
    QString      currentMonth;
    QVariantList rowBuf;

    auto flushRow = [&]() {
        if (rowBuf.isEmpty()) return;
        const auto &pat = kPatterns[patternIdx % kPatterns.size()];
        QVariantList rowItems;
        for (int i = 0; i < rowBuf.size(); ++i) {
            QVariantMap m = rowBuf.at(i).toMap();
            m["col_span"] = (i < pat.size()) ? pat[i] : 1;
            rowItems.append(m);
        }
        m_rows.append({false, {}, rowItems});
        rowBuf.clear();
        patternIdx++;
    };

    for (const QVariant &v : allMedia) {
        QVariantMap map = v.toMap();

        const bool isFav     = map.value("is_favorite", false).toBool();
        const bool isTrashed = map.value("is_trashed",  false).toBool();

        if (m_filterMode == FavoritesMode && (!isFav || isTrashed)) continue;
        if (m_filterMode == TrashMode     && !isTrashed)            continue;
        if (m_filterMode == AllMode       &&  isTrashed)            continue;

        const QString fp    = map.value("file_path").toString();
        const qint64  ts    = map.value("creation_date").toLongLong();
        const QString month = QDateTime::fromSecsSinceEpoch(ts).toString("MMMM yyyy");

        if (month != currentMonth) {
            if (!rowBuf.isEmpty()) flushRow();
            currentMonth = month;
            patternIdx   = 0; // restart mosaic pattern at each month
            m_rows.append({true, month, {}});
        }

        map["thumb"]       = ThumbnailGenerator::thumbnailUrl(fp);
        map["path"]        = "file://" + fp;
        map["_flat_index"] = flatIdx++;
        rowBuf.append(map);

        const auto &pat = kPatterns[patternIdx % kPatterns.size()];
        if (rowBuf.size() >= pat.size())
            flushRow();
    }
    if (!rowBuf.isEmpty()) flushRow();

    qDebug() << "Timeline refresh:" << m_rows.size() << "rows ("
             << allMedia.size() << "items," << m_numColumns << "cols)";
    endResetModel();
}
