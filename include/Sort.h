#pragma once

#include <QString>
#include <QVariantList>

// ─────────────────────────────────────────────────────────────────────────────
// Reusable, UI-agnostic sorting core.
//
// This module is the single source of truth for "how things sort" in Kader.
// It is deliberately decoupled from any specific model so it can be reused by
// future panels (e.g. a dashboard) without dragging in the media schema.
//
// Two layers, per the "reuse the logic, not the execution" principle:
//
//   • mediaOrderClause()  — builds a SQL ORDER BY fragment for the (large)
//                           media table. The timeline stays SQL-backed so it
//                           never has to read 20k rows into memory to sort.
//
//   • sortList()          — a generic in-memory stable sort over a
//                           QVariantList of QVariantMaps, keyed by an arbitrary
//                           field name. Used by the (small) album list today and
//                           reusable by any future QVariantList-backed view.
//
// Neither layer ever fetches data — they only order what they are given — so a
// view that has already filtered out hidden items cannot leak them by sorting.
// ─────────────────────────────────────────────────────────────────────────────
namespace Sort {

// Canonical media sort fields. Values 0-4 are frozen for backward compatibility
// with sort preferences already persisted in settings_kv; append new fields only.
enum MediaRole {
    ByCreated     = 0,  // creation_date (EXIF capture date, falls back to mtime)
    ByModified    = 1,  // modified_date (filesystem mtime)
    ByName        = 2,  // file name
    BySize        = 3,  // file_size
    ByViewed      = 4,  // last_viewed
    ByType        = 5,  // mime_type
    ByWidth       = 6,  // pixel width
    ByHeight      = 7,  // pixel height
    ByDimensions  = 8,  // pixel area (width × height)
    ByOrientation = 9   // landscape → square → portrait
};

enum Order { Descending = 0, Ascending = 1 };

// How to compare a field's values during an in-memory sort.
enum ValueType { Text, Number };

// Returns a SQL ORDER BY fragment (without the "ORDER BY" keyword) for the media
// table. `ascending` true → ASC, false → DESC. Always appends a stable tiebreak.
QString mediaOrderClause(int role, bool ascending);

// Generic stable in-memory sort of a list of QVariantMaps by `field`.
//   field       — map key to compare on (e.g. "name", "file_size", "count")
//   type        — Text (case-insensitive) or Number
//   ascending   — sort direction
//   pinnedField — optional bool field; rows where it is true always sort first,
//                 preserving their relative order (used for pinned albums).
void sortList(QVariantList &list, const QString &field, ValueType type,
              bool ascending, const QString &pinnedField = QString());

} // namespace Sort
