#include "Sort.h"

#include <QCollator>
#include <QVariantMap>
#include <algorithm>

namespace Sort {

QString mediaOrderClause(int role, bool ascending) {
    const QString dir = ascending ? QStringLiteral("ASC") : QStringLiteral("DESC");

    switch (role) {
    case ByModified:
        return "modified_date " + dir + ", id " + dir;
    case ByName:
        return "LOWER(file_path) " + dir + ", id " + dir;
    case BySize:
        return "file_size " + dir + ", id " + dir;
    case ByViewed:
        return "last_viewed " + dir + ", id " + dir;
    case ByType:
        // Group by mime type, then keep newest-first within each type.
        return "LOWER(COALESCE(mime_type,'')) " + dir + ", creation_date DESC, id DESC";
    case ByWidth:
        return "COALESCE(width,0) " + dir + ", id " + dir;
    case ByHeight:
        return "COALESCE(height,0) " + dir + ", id " + dir;
    case ByDimensions:
        return "(COALESCE(width,0) * COALESCE(height,0)) " + dir + ", id " + dir;
    case ByOrientation:
        // Ascending = landscape (0) → square (1) → portrait (2); larger images
        // first within each bucket so the strongest example of each leads.
        return "CASE "
               "WHEN COALESCE(width,0) = 0 OR COALESCE(height,0) = 0 THEN 3 "
               "WHEN width > height THEN 0 "
               "WHEN width = height THEN 1 "
               "ELSE 2 END " + dir +
               ", (COALESCE(width,0) * COALESCE(height,0)) DESC, id DESC";
    case ByCreated:
    default:
        return "creation_date " + dir + ", id " + dir;
    }
}

void sortList(QVariantList &list, const QString &field, ValueType type,
              bool ascending, const QString &pinnedField) {
    // Natural, locale-aware, case-insensitive comparison for text fields so
    // "img2" sorts before "img10" and accents behave sensibly.
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);

    std::stable_sort(list.begin(), list.end(),
                     [&](const QVariant &av, const QVariant &bv) {
        const QVariantMap a = av.toMap();
        const QVariantMap b = bv.toMap();

        // Pinned rows always precede unpinned ones, regardless of direction.
        if (!pinnedField.isEmpty()) {
            const bool ap = a.value(pinnedField).toBool();
            const bool bp = b.value(pinnedField).toBool();
            if (ap != bp) return ap;            // pinned (true) comes first
        }

        int cmp;
        if (type == Number) {
            const double an = a.value(field).toDouble();
            const double bn = b.value(field).toDouble();
            cmp = (an < bn) ? -1 : (an > bn) ? 1 : 0;
        } else {
            cmp = collator.compare(a.value(field).toString(),
                                   b.value(field).toString());
        }
        return ascending ? (cmp < 0) : (cmp > 0);
    });
}

} // namespace Sort
