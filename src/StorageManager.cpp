#include "StorageManager.h"
#include <QDir>
#include <QFileInfo>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QVariantMap>
#include "ThumbnailGenerator.h"

StorageManager::StorageManager(DatabaseManager *db, QObject *parent)
    : QObject(parent), m_db(db), m_storage(QDir::homePath()) {
    refresh();
}

double StorageManager::totalGb() const {
    return static_cast<double>(m_storage.bytesTotal()) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::freeGb() const {
    return static_cast<double>(m_storage.bytesAvailable()) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::mediaGb() const {
    return static_cast<double>(m_mediaSizeBytes) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::photoGb() const {
    return static_cast<double>(m_photoSizeBytes) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::videoGb() const {
    return static_cast<double>(m_videoSizeBytes) / (1024.0 * 1024.0 * 1024.0);
}

int StorageManager::mediaPercent() const {
    const double total = totalGb();
    if (total <= 0) return 0;
    return static_cast<int>((mediaGb() / total) * 100.0);
}

void StorageManager::refresh() {
    // measure the disk the library lives on, not necessarily $HOME's
    const QStringList dirs = m_db->getIndexedDirectoryPaths();
    if (!dirs.isEmpty() && QFileInfo::exists(dirs.first()))
        m_storage.setPath(dirs.first());
    m_storage.refresh();
    m_mediaSizeBytes = m_db->getTotalMediaSizeBytes();
    m_photoSizeBytes = m_db->getPhotoSizeBytes();
    m_videoSizeBytes = m_db->getVideoSizeBytes();
    m_photoCount     = m_db->getPhotoCount();
    m_videoCount     = m_db->getVideoCount();
    emit storageChanged();
}

// ── dashboard queries ─────────────────────────────────────────────────────────

namespace {
const char *kLive = "COALESCE(is_trashed,0) = 0";
// lower-case extension without the dot
const char *kExt = "lower(replace(file_path, rtrim(file_path, replace(file_path, '.', '')), ''))";
const QStringList kRaw = {"cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "dng", "orf", "rw2", "raf", "pef", "srw", "x3f", "3fr", "iiq", "erf", "kdc", "mrw", "rwl"};

QString rawList() {
    QStringList q;
    for (const QString &e : kRaw)
        q << QLatin1Char('\'') + e + QLatin1Char('\'');
    return q.join(QLatin1Char(','));
}

QVariantMap mediaRow(const QSqlQuery &q, const QSqlRecord &rec) {
    QVariantMap m;
    for (int i = 0; i < rec.count(); ++i)
        m.insert(rec.fieldName(i), q.value(i));
    const QString fp = m.value(QStringLiteral("file_path")).toString();
    m.insert(QStringLiteral("thumb"), ThumbnailGenerator::thumbnailUrl(fp));
    m.insert(QStringLiteral("path"), QStringLiteral("file://") + fp);
    return m;
}
} // namespace

QVariantMap StorageManager::overview() {
    m_storage.refresh();
    QSqlQuery q(m_db->threadDb());
    qint64 photos = 0, videos = 0, raw = 0, trash = 0;
    q.exec(QStringLiteral(
        "SELECT "
        " COALESCE(SUM(CASE WHEN %1 AND mime_type LIKE 'video/%' THEN file_size END),0),"
        " COALESCE(SUM(CASE WHEN %1 AND mime_type NOT LIKE 'video/%' AND %2 NOT IN (%3) THEN file_size END),0),"
        " COALESCE(SUM(CASE WHEN %1 AND %2 IN (%3) THEN file_size END),0),"
        " COALESCE(SUM(CASE WHEN NOT (%1) THEN file_size END),0) FROM media")
               .arg(QLatin1String(kLive), QLatin1String(kExt), rawList()));
    if (q.next()) {
        videos = q.value(0).toLongLong();
        photos = q.value(1).toLongLong();
        raw = q.value(2).toLongLong();
        trash = q.value(3).toLongLong();
    }
    const qint64 total = m_storage.bytesTotal();
    const qint64 free = m_storage.bytesAvailable();
    const qint64 other = std::max<qint64>(0, total - free - photos - videos - raw - trash);
    return {{QStringLiteral("total"), total}, {QStringLiteral("free"), free}, {QStringLiteral("photos"), photos},
            {QStringLiteral("videos"), videos}, {QStringLiteral("raw"), raw}, {QStringLiteral("trash"), trash},
            {QStringLiteral("other"), other}, {QStringLiteral("disk"), m_storage.displayName()}};
}

QVariantList StorageManager::byFolder(int limit) {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT folder_path, SUM(file_size) AS b, COUNT(*) FROM media WHERE %1 "
                          "GROUP BY folder_path ORDER BY b DESC LIMIT %2")
               .arg(QLatin1String(kLive)).arg(limit));
    while (q.next()) {
        const QString f = q.value(0).toString();
        out << QVariantMap{{QStringLiteral("folder"), f}, {QStringLiteral("name"), f.section(QLatin1Char('/'), -1)},
                           {QStringLiteral("bytes"), q.value(1)}, {QStringLiteral("count"), q.value(2)}};
    }
    return out;
}

QVariantList StorageManager::byYear() {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT strftime('%Y', creation_date, 'unixepoch', 'localtime') AS y, SUM(file_size), COUNT(*) "
                          "FROM media WHERE %1 AND creation_date > 0 GROUP BY y ORDER BY y")
               .arg(QLatin1String(kLive)));
    while (q.next())
        out << QVariantMap{{QStringLiteral("year"), q.value(0)}, {QStringLiteral("bytes"), q.value(1)},
                           {QStringLiteral("count"), q.value(2)}};
    return out;
}

QVariantList StorageManager::byType() {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT %1 AS e, SUM(file_size) AS b, COUNT(*) FROM media WHERE %2 GROUP BY e ORDER BY b DESC")
               .arg(QLatin1String(kExt), QLatin1String(kLive)));
    while (q.next()) {
        const QString e = q.value(0).toString();
        out << QVariantMap{{QStringLiteral("ext"), e}, {QStringLiteral("raw"), kRaw.contains(e)},
                           {QStringLiteral("bytes"), q.value(1)}, {QStringLiteral("count"), q.value(2)}};
    }
    return out;
}

QVariantList StorageManager::largest(int limit) {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT * FROM media WHERE %1 ORDER BY file_size DESC LIMIT %2").arg(QLatin1String(kLive)).arg(limit));
    const QSqlRecord rec = q.record();
    while (q.next())
        out << mediaRow(q, rec);
    return out;
}

QVariantList StorageManager::duplicates(int limit) {
    QVariantList out;
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery g(db);
    // same file name and byte size, more than one copy
    g.exec(QStringLiteral(
        "SELECT replace(file_path, rtrim(file_path, replace(file_path, '/', '')), '') AS n, file_size, COUNT(*) AS c "
        "FROM media WHERE %1 AND file_size > 0 GROUP BY n, file_size HAVING c > 1 "
        "ORDER BY file_size * (c - 1) DESC LIMIT %2")
               .arg(QLatin1String(kLive)).arg(limit));
    while (g.next()) {
        const QString name = g.value(0).toString();
        const qint64 size = g.value(1).toLongLong();
        QSqlQuery m(db);
        m.prepare(QStringLiteral("SELECT * FROM media WHERE %1 AND file_size = ? AND file_path LIKE ? ORDER BY creation_date")
                      .arg(QLatin1String(kLive)));
        m.addBindValue(size);
        m.addBindValue(QStringLiteral("%/") + name);
        m.exec();
        const QSqlRecord rec = m.record();
        QVariantList copies;
        while (m.next())
            copies << mediaRow(m, rec);
        if (copies.size() > 1)
            out << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("bytes"), size},
                               {QStringLiteral("wasted"), size * (copies.size() - 1)}, {QStringLiteral("copies"), copies}};
    }
    return out;
}

QVariantList StorageManager::trashItems(int limit) {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT * FROM media WHERE NOT (%1) ORDER BY file_size DESC LIMIT %2").arg(QLatin1String(kLive)).arg(limit));
    const QSqlRecord rec = q.record();
    while (q.next())
        out << mediaRow(q, rec);
    return out;
}
