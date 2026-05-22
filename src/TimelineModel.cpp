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

void TimelineModel::setContentWidth(int px) {
    if (px > 0 && qAbs(px - m_contentWidth) > 8) {
        m_contentWidth = px;
        emit contentWidthChanged();
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

    // ── Aspect-ratio row packing (Google Photos style) ──────────────────────
    // Photos keep their real aspect ratios. We pack them into rows so the total
    // width equals contentWidth at a target height, then scale up/down to fill exactly.
    //
    // Row height varies naturally: a row of wide landscape photos is short;
    // a row with a portrait photo and a small square is tall.
    // The result: every row is different, every tile has a natural size.

    const float cw     = qMax(400, m_contentWidth);  // available pixel width
    const float gap    = 6.0f;
    const float target = 260.0f; // target row height in pixels
    const float minH   = 140.0f;
    const float maxH   = 520.0f;

    // Per-item aspect ratio: use stored EXIF dimensions when available.
    // When missing (w=0/h=0), cycle through a variety of common photo ratios
    // so the mosaic looks naturally varied even without EXIF data.
    static const float kVarietyRatios[] = {
        4.0f/3,   // landscape standard
        3.0f/2,   // DSLR landscape
        16.0f/9,  // widescreen
        1.0f,     // square
        3.0f/4,   // portrait standard
        2.0f/3,   // portrait DSLR
        5.0f/4,   // slightly landscape
        4.0f/5,   // slightly portrait
        3.0f/2,
        16.0f/9,
    };
    static constexpr int kRatioCount = sizeof(kVarietyRatios) / sizeof(kVarietyRatios[0]);

    auto aspectRatio = [](const QVariantMap &m, int idx) -> float {
        int w = m.value("width",  0).toInt();
        int h = m.value("height", 0).toInt();
        if (w > 0 && h > 0) return float(w) / float(h);
        return kVarietyRatios[idx % kRatioCount];
    };

    // Flush accumulated rowBuf: compute per-item pixel widths and row height.
    int  flatIdx = 0;
    QString      currentMonth;
    QVariantList rowBuf;       // items being packed into the current row
    float        rowArSum = 0; // sum of aspect-ratios in rowBuf (for width calc)

    auto flushRow = [&](bool isLastRow) {
        if (rowBuf.isEmpty()) return;
        int  n = rowBuf.size();
        // Total gaps between n items
        float gaps = gap * (n - 1);
        // Height that makes items fill cw exactly
        float h = (cw - gaps) / qMax(0.01f, rowArSum);
        // Clamp: last row shouldn't expand wildly if it has few items
        h = qBound(minH, h, isLastRow ? target : maxH);
        // Recompute item widths at the chosen h
        QVariantList rowItems;
        for (int i = 0; i < n; ++i) {
            QVariantMap m = rowBuf.at(i).toMap();
            // Use the _flat_index already stored to look up the variety ratio consistently
            int fi = m.value("_flat_index", i).toInt();
            float ar = aspectRatio(m, fi);
            m["item_width"]  = qRound(ar * h);
            m["item_height"] = qRound(h);
            rowItems.append(m);
        }
        m_rows.append({false, {}, rowItems, h});
        rowBuf.clear();
        rowArSum = 0;
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
            flushRow(false);
            currentMonth = month;
            m_rows.append({true, month, {}, 0});
        }

        map["thumb"]       = ThumbnailGenerator::thumbnailUrl(fp);
        map["path"]        = "file://" + fp;
        map["_flat_index"] = flatIdx++;
        rowBuf.append(map);
        rowArSum += aspectRatio(map, flatIdx - 1);

        // Flush when the projected row width reaches or exceeds cw
        float projectedWidth = rowArSum * target + gap * (rowBuf.size() - 1);
        if (projectedWidth >= cw)
            flushRow(false);
    }
    flushRow(true); // last partial row

    qDebug() << "Timeline refresh:" << m_rows.size() << "rows ("
             << allMedia.size() << "items," << m_numColumns << "cols)";
    endResetModel();
}
