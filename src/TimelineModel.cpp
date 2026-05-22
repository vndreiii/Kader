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
    case IsHeaderRole:   return row.isHeader;
    case MonthNameRole:  return row.monthName;
    case ItemsRole:      return row.items;
    case HeightMultRole: return row.heightMult;
    default:             return {};
    }
}

QHash<int, QByteArray> TimelineModel::roleNames() const {
    return {
        { IsHeaderRole,   "isHeader"   },
        { MonthNameRole,  "monthName"  },
        { ItemsRole,      "items"      },
        { HeightMultRole, "heightMult" }
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

void TimelineModel::setMimeFilter(const QString &prefix) {
    if (m_mimeFilter != prefix) {
        m_mimeFilter = prefix;
        emit mimeFilterChanged();
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

    // In-memory MIME prefix filter (e.g. "video/" shows only videos)
    if (!m_mimeFilter.isEmpty()) {
        QVariantList filtered;
        for (const QVariant &v : allMedia)
            if (v.toMap().value("mime_type").toString().startsWith(m_mimeFilter))
                filtered.append(v);
        allMedia = filtered;
    }

    // Mosaic patterns: each entry has column-spans (sum = numCols) + height multiplier.
    // Patterns with large heightMult + narrow colSpans create portrait-feel tiles.
    struct Pattern { QVector<int> spans; float hMult; };
    const int nc = m_numColumns;

    // Build a rich pattern set scaled to the current column count.
    // All span-sums equal nc. hMult drives the row's pixel height relative to a square tile.
    QVector<Pattern> patterns;
    if (nc == 4) {
        patterns = {
            {{1,1,1,1}, 0.75f},   // four small square tiles (short row)
            {{2,1,1},   1.0f},    // wide + two small
            {{1,1,2},   1.0f},    // two small + wide
            {{2,2},     1.35f},   // two wide landscape tiles
            {{1,3},     1.65f},   // narrow + very wide  → narrow tile looks portrait
            {{3,1},     1.65f},   // very wide + narrow  → idem
            {{1,2,1},   1.2f},    // small + wide + small
            {{2,1,1},   1.4f},    // wide + two small, taller pass
            {{1,1,2},   1.4f},    // two small + wide, taller
            {{2,2},     0.85f},   // two wide, shorter (panoramic)
        };
    } else if (nc == 3) {
        patterns = {
            {{1,1,1},   0.8f},
            {{2,1},     1.0f},
            {{1,2},     1.0f},
            {{1,1,1},   1.4f},
            {{2,1},     1.5f},
            {{3},       0.55f},
        };
    } else {
        // Generic fallback
        for (int i = 0; i < 5; ++i)
            patterns.append({{nc}, i % 2 == 0 ? 0.75f : 1.2f});
        patterns.append({{nc/2, nc-nc/2}, 1.0f});
    }

    int patternIdx = 0;
    int flatIdx    = 0;
    QString      currentMonth;
    QVariantList rowBuf;

    auto flushRow = [&]() {
        if (rowBuf.isEmpty()) return;
        const Pattern &pat = patterns[patternIdx % patterns.size()];
        QVariantList rowItems;
        for (int i = 0; i < rowBuf.size(); ++i) {
            QVariantMap m = rowBuf.at(i).toMap();
            m["col_span"] = (i < pat.spans.size()) ? pat.spans[i] : 1;
            rowItems.append(m);
        }
        m_rows.append({false, {}, rowItems, pat.hMult});
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

        const Pattern &pat = patterns[patternIdx % patterns.size()];
        if (rowBuf.size() >= pat.spans.size())
            flushRow();
    }
    if (!rowBuf.isEmpty()) flushRow();

    qDebug() << "Timeline refresh:" << m_rows.size() << "rows ("
             << allMedia.size() << "items," << m_numColumns << "cols)";
    endResetModel();
}
