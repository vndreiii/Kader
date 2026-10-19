#include "MemoryManager.h"

#include "AppPaths.h"

#include <QCoreApplication>
#include <QDate>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QLocale>
#include <QProcess>
#include <QRandomGenerator>
#include <QSet>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>
#include <QtConcurrent>
#include <algorithm>

namespace {

constexpr int    kBatchSize     = 5;
constexpr qint64 kLifetimeSecs  = 7 * 24 * 3600;
constexpr double kSlideSecs     = 3.2;   // each photo on screen
constexpr double kCrossfadeSecs = 0.6;   // overlap between photos
constexpr double kFadeInSecs    = 0.8;
constexpr double kFadeOutSecs   = 1.4;

struct Track { const char *file; const char *mood; };
// One per mood; every file is CC0 (see assets/music/LICENSES.md).
const Track kTracks[] = {
    { "sunny-morning.ogg", "upbeat" },
    { "still-water.ogg",   "calm" },
    { "golden-hour.ogg",   "nostalgic" },
    { "open-road.ogg",     "energetic" },
    { "daydream.ogg",      "dreamy" },
};

int minPhotosPerDay() {
    bool ok = false;
    const int v = qEnvironmentVariableIntValue("KADER_MEMORIES_MIN_PHOTOS", &ok);
    return ok && v > 0 ? v : 8;
}

QSqlDatabase openDb(const QString &dbPath, const QString &name) {
    if (QSqlDatabase::contains(name))
        return QSqlDatabase::database(name);
    QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), name);
    db.setDatabaseName(dbPath);
    db.setConnectOptions(QStringLiteral("QSQLITE_BUSY_TIMEOUT=5000"));
    if (!db.open())
        qWarning() << "MemoryManager: cannot open db" << db.lastError().text();
    return db;
}

void ensureTable(QSqlDatabase db) {
    QSqlQuery q(db);
    q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS memories ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "date TEXT NOT NULL,"
        "title TEXT NOT NULL,"
        "video_path TEXT NOT NULL,"
        "cover_path TEXT,"
        "mood TEXT,"
        "duration_ms INTEGER DEFAULT 0,"
        "photo_count INTEGER DEFAULT 0,"
        "created_at INTEGER NOT NULL,"
        "expires_at INTEGER NOT NULL)"));
}

QString findMusic(const QString &file) {
    const QString app = QCoreApplication::applicationDirPath();
    QStringList dirs;
    if (qEnvironmentVariableIsSet("KADER_DATA_DIR"))
        dirs << qEnvironmentVariable("KADER_DATA_DIR") + QStringLiteral("/music");
    dirs << app + QStringLiteral("/../share/kader/music") << app + QStringLiteral("/music");
    const QString located = QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                                   QStringLiteral("kader/music"),
                                                   QStandardPaths::LocateDirectory);
    if (!located.isEmpty()) dirs << located;
    for (const QString &d : dirs) {
        const QString p = QDir(d).filePath(file);
        if (QFile::exists(p)) return QDir::cleanPath(p);
    }
    return {};
}

// Runs ffmpeg to completion; false (with the tail of stderr logged) on failure.
bool runFfmpeg(const QStringList &args) {
    QProcess p;
    p.setProgram(AppPaths::tool(QStringLiteral("ffmpeg")));
    p.setArguments(args);
    p.start();
    if (!p.waitForStarted(10000)) return false;
    if (!p.waitForFinished(10 * 60 * 1000)) { p.kill(); p.waitForFinished(); return false; }
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        qWarning() << "MemoryManager: ffmpeg failed:" << p.readAllStandardError().right(600);
        return false;
    }
    return true;
}

struct Rendered { QString video, cover; qint64 durationMs = 0; };

bool renderSlideshow(const QStringList &photos, const QString &musicFile,
                     const QString &outPath, const QString &coverPath, Rendered &out) {
    const int n = photos.size();
    if (n < 2) return false;
    const double total = n * kSlideSecs - (n - 1) * kCrossfadeSecs;

    QStringList args{ "-y", "-hide_banner", "-loglevel", "error", "-threads", "2" };
    for (const QString &p : photos)
        args << "-framerate" << "30" << "-loop" << "1" << "-t" << QString::number(kSlideSecs, 'f', 2) << "-i" << p;
    args << "-stream_loop" << "-1" << "-i" << musicFile;

    // Each photo: blurred, cropped copy as backdrop + the whole photo on top,
    // so portrait and landscape shots both fill the 16:9 frame.
    QStringList f;
    for (int i = 0; i < n; ++i) {
        f << QString("[%1:v]split[a%1][b%1];"
                     "[a%1]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,boxblur=28:3[bg%1];"
                     "[b%1]scale=1280:720:force_original_aspect_ratio=decrease[fg%1];"
                     "[bg%1][fg%1]overlay=(W-w)/2:(H-h)/2,setsar=1,fps=30,format=yuv420p[v%1]").arg(i);
    }
    QString last = "v0";
    for (int i = 1; i < n; ++i) {
        const QString next = i == n - 1 ? "vx" : QString("x%1").arg(i);
        f << QString("[%1][v%2]xfade=transition=fade:duration=%3:offset=%4[%5]")
                 .arg(last).arg(i).arg(kCrossfadeSecs).arg(i * (kSlideSecs - kCrossfadeSecs), 0, 'f', 2).arg(next);
        last = next;
    }
    f << QString("[%1]fade=t=in:st=0:d=%2,fade=t=out:st=%3:d=%4[vout]")
             .arg(last).arg(kFadeInSecs).arg(total - kFadeOutSecs, 0, 'f', 2).arg(kFadeOutSecs);
    f << QString("[%1:a]atrim=0:%2,asetpts=PTS-STARTPTS,afade=t=in:d=1.5,afade=t=out:st=%3:d=2,volume=0.9[aout]")
             .arg(n).arg(total, 0, 'f', 2).arg(total - 2.0, 0, 'f', 2);

    args << "-filter_complex" << f.join(";")
         << "-map" << "[vout]" << "-map" << "[aout]"
         << "-t" << QString::number(total, 'f', 2)
         << "-c:v" << "libx264" << "-preset" << "veryfast" << "-crf" << "23" << "-pix_fmt" << "yuv420p"
         << "-c:a" << "aac" << "-b:a" << "160k"
         << "-movflags" << "+faststart" << "-f" << "mp4" << outPath;
    if (!runFfmpeg(args)) { QFile::remove(outPath); return false; }

    // Cover: a frame from inside the first photo's slide.
    runFfmpeg({ "-y", "-hide_banner", "-loglevel", "error", "-ss", "1.0", "-i", outPath,
                "-frames:v", "1", "-vf", "scale=640:-2", "-q:v", "3", coverPath });

    out.video = outPath;
    out.cover = QFile::exists(coverPath) ? coverPath : QString();
    out.durationMs = qRound64(total * 1000);
    return true;
}

// Worker: builds up to kBatchSize memories, then retires the previous batch.
int generateBatch(const QString &dbPath, const QString &dir) {
    AppPaths::lowerThreadPriority();
    const QString conn = QStringLiteral("kader_memories_w_%1").arg(quintptr(QThread::currentThreadId()));
    int made = 0;
    {
        QSqlDatabase db = openDb(dbPath, conn);
        ensureTable(db);
        QDir().mkpath(dir);

        // Days with enough usable photos, skipping days the previous batch used.
        QSet<QString> used;
        {
            QSqlQuery q(QStringLiteral("SELECT date FROM memories"), db);
            while (q.next()) used.insert(q.value(0).toString());
        }
        QStringList days;
        {
            QSqlQuery q(db);
            q.prepare(QStringLiteral(
                "SELECT date(creation_date,'unixepoch','localtime') AS d, COUNT(*) AS c FROM media "
                "WHERE is_trashed = 0 AND COALESCE(is_hidden,0) = 0 AND COALESCE(is_ignored,0) = 0 "
                "AND creation_date > 0 AND mime_type IN ('image/jpeg','image/webp') "
                "GROUP BY d HAVING c >= ?"));
            q.addBindValue(minPhotosPerDay());
            if (!q.exec()) qWarning() << "MemoryManager: day query failed" << q.lastError().text();
            while (q.next()) days << q.value(0).toString();
        }
        QStringList fresh, stale;
        for (const QString &d : days) (used.contains(d) ? stale : fresh).append(d);
        auto shuffle = [](QStringList &l) { std::shuffle(l.begin(), l.end(), *QRandomGenerator::global()); };
        shuffle(fresh); shuffle(stale);
        QStringList picked = fresh + stale;

        QList<int> moods{0, 1, 2, 3, 4};
        std::shuffle(moods.begin(), moods.end(), *QRandomGenerator::global());

        const qint64 now = QDateTime::currentSecsSinceEpoch();
        QList<qint64> newIds;
        for (int di = 0; di < picked.size() && made < kBatchSize; ++di) {
            const QString day = picked.at(di);
            QSqlQuery q(db);
            q.prepare(QStringLiteral(
                "SELECT file_path FROM media WHERE is_trashed = 0 AND COALESCE(is_hidden,0) = 0 "
                "AND COALESCE(is_ignored,0) = 0 AND mime_type IN ('image/jpeg','image/webp') "
                "AND date(creation_date,'unixepoch','localtime') = ? ORDER BY RANDOM()"));
            q.addBindValue(day);
            QStringList photos;
            const int want = 8 + QRandomGenerator::global()->bounded(5);   // 8..12
            q.exec();
            while (q.next() && photos.size() < want) {
                const QString p = q.value(0).toString();
                if (QFile::exists(p)) photos << p;
            }
            if (photos.size() < std::min(minPhotosPerDay(), 6)) continue;

            const Track &track = kTracks[moods.at(made % moods.size())];
            const QString music = findMusic(QString::fromLatin1(track.file));
            if (music.isEmpty()) { qWarning() << "MemoryManager: music missing:" << track.file; continue; }

            const QString stem = QStringLiteral("%1/%2-%3").arg(dir, day).arg(now);
            Rendered r;
            if (!renderSlideshow(photos, music, stem + ".part.mp4", stem + ".jpg", r)) continue;
            const QString finalPath = stem + ".mp4";
            QFile::remove(finalPath);
            if (!QFile::rename(r.video, finalPath)) { QFile::remove(r.video); continue; }

            const QDate date = QDate::fromString(day, Qt::ISODate);
            QSqlQuery ins(db);
            ins.prepare(QStringLiteral(
                "INSERT INTO memories (date,title,video_path,cover_path,mood,duration_ms,photo_count,created_at,expires_at) "
                "VALUES (?,?,?,?,?,?,?,?,?)"));
            ins.addBindValue(day);
            ins.addBindValue(QLocale().toString(date, QStringLiteral("dddd, d MMMM yyyy")));
            ins.addBindValue(finalPath);
            ins.addBindValue(r.cover);
            ins.addBindValue(QString::fromLatin1(track.mood));
            ins.addBindValue(r.durationMs);
            ins.addBindValue(photos.size());
            ins.addBindValue(now);
            ins.addBindValue(now + kLifetimeSecs);
            if (!ins.exec()) { QFile::remove(finalPath); continue; }
            newIds << ins.lastInsertId().toLongLong();
            ++made;
        }

        // Retire the previous batch only once a replacement exists.
        if (made > 0) {
            QSqlQuery old(db);
            old.prepare(QStringLiteral("SELECT id, video_path, cover_path FROM memories WHERE created_at < ?"));
            old.addBindValue(now);
            old.exec();
            QList<qint64> gone;
            while (old.next()) {
                QFile::remove(old.value(1).toString());
                QFile::remove(old.value(2).toString());
                gone << old.value(0).toLongLong();
            }
            for (qint64 id : gone) {
                QSqlQuery del(db);
                del.prepare(QStringLiteral("DELETE FROM memories WHERE id = ?"));
                del.addBindValue(id);
                del.exec();
            }
        }

        // Sweep orphans (half-written renders, files whose row was removed).
        QSet<QString> known;
        QSqlQuery all(QStringLiteral("SELECT video_path, cover_path FROM memories"), db);
        while (all.next()) { known.insert(all.value(0).toString()); known.insert(all.value(1).toString()); }
        for (const QFileInfo &fi : QDir(dir).entryInfoList(QDir::Files))
            if (!known.contains(fi.absoluteFilePath())) QFile::remove(fi.absoluteFilePath());
    }
    QSqlDatabase::removeDatabase(conn);
    return made;
}

} // namespace

MemoryManager::MemoryManager(QObject *parent)
    : QObject(parent),
      m_dbPath(AppPaths::dataDir() + QStringLiteral("/gallery.db")),
      m_dir(AppPaths::dataDir() + QStringLiteral("/memories")) {}

void MemoryManager::ensureBatch() {
    if (m_generating) return;
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    ensureTable(db);

    if (!qEnvironmentVariableIsSet("KADER_MEMORIES_FORCE")) {
        QSqlQuery q(db);
        q.prepare(QStringLiteral("SELECT COUNT(*) FROM memories WHERE expires_at > ?"));
        q.addBindValue(QDateTime::currentSecsSinceEpoch());
        if (q.exec() && q.next() && q.value(0).toInt() > 0)
            return;                                   // a live batch exists
    }

    m_generating = true;
    emit generatingChanged();
    auto *watcher = new QFutureWatcher<int>(this);
    connect(watcher, &QFutureWatcher<int>::finished, this, [this, watcher] {
        const int made = watcher->result();
        watcher->deleteLater();
        finishBatch(made);
    });
    watcher->setFuture(QtConcurrent::run(generateBatch, m_dbPath, m_dir));
}

void MemoryManager::finishBatch(int made) {
    qInfo() << "MemoryManager: generated" << made << "memories";
    m_generating = false;
    emit generatingChanged();
    ++m_revision;
    emit revisionChanged();
}

QVariantList MemoryManager::list() const {
    QVariantList out;
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    ensureTable(db);
    QSqlQuery q(QStringLiteral("SELECT id,date,title,video_path,cover_path,mood,duration_ms,photo_count,expires_at "
                               "FROM memories ORDER BY date DESC"), db);
    while (q.next()) {
        const QString video = q.value(3).toString();
        if (!QFile::exists(video)) continue;
        const QString cover = q.value(4).toString();
        QVariantMap m;
        m["id"]         = q.value(0).toInt();
        m["date"]       = q.value(1).toString();
        m["title"]      = q.value(2).toString();
        m["video"]      = QUrl::fromLocalFile(video).toString();
        m["cover"]      = cover.isEmpty() ? QString() : QUrl::fromLocalFile(cover).toString();
        m["mood"]       = q.value(5).toString();
        m["durationMs"] = q.value(6).toLongLong();
        m["photoCount"] = q.value(7).toInt();
        m["expiresAt"]  = q.value(8).toLongLong();
        out << m;
    }
    return out;
}

QString MemoryManager::suggestedFileName(int id) const {
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    QSqlQuery q(db);
    q.prepare(QStringLiteral("SELECT date FROM memories WHERE id = ?"));
    q.addBindValue(id);
    const QString date = q.exec() && q.next() ? q.value(0).toString() : QString::number(id);
    return QStringLiteral("Kader Memory %1.mp4").arg(date);
}

QString MemoryManager::exportTo(int id, const QString &destUrl) const {
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    QSqlQuery q(db);
    q.prepare(QStringLiteral("SELECT video_path FROM memories WHERE id = ?"));
    q.addBindValue(id);
    if (!q.exec() || !q.next()) return {};
    const QString src = q.value(0).toString();

    QString dest = destUrl.startsWith(QStringLiteral("file:")) ? QUrl(destUrl).toLocalFile() : destUrl;
    if (dest.isEmpty() || !QFile::exists(src)) return {};
    if (QFileInfo(dest).isDir())
        dest = QDir(dest).filePath(suggestedFileName(id));
    if (QFileInfo(dest).suffix().isEmpty()) dest += QStringLiteral(".mp4");
    if (QFile::exists(dest)) QFile::remove(dest);
    return QFile::copy(src, dest) ? dest : QString();
}

bool MemoryManager::remove(int id) {
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    QSqlQuery q(db);
    q.prepare(QStringLiteral("SELECT video_path, cover_path FROM memories WHERE id = ?"));
    q.addBindValue(id);
    if (!q.exec() || !q.next()) return false;
    QFile::remove(q.value(0).toString());
    QFile::remove(q.value(1).toString());
    QSqlQuery d(db);
    d.prepare(QStringLiteral("DELETE FROM memories WHERE id = ?"));
    d.addBindValue(id);
    const bool ok = d.exec();
    ++m_revision;
    emit revisionChanged();
    return ok;
}
