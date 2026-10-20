#include "MemoryManager.h"

#include "AppPaths.h"
#include "ThumbnailGenerator.h"

#ifndef Q_OS_WIN
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#endif
#include <QCoreApplication>
#include <QDate>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QLocale>
#include <QMimeDatabase>
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

#ifndef Q_OS_WIN
// FileChooser filters are a(sa(us)); these let QtDBus marshal them.
struct PortalFilterEntry { uint kind = 0; QString pattern; };
struct PortalFilter { QString name; QList<PortalFilterEntry> entries; };
Q_DECLARE_METATYPE(PortalFilterEntry)
Q_DECLARE_METATYPE(QList<PortalFilterEntry>)
Q_DECLARE_METATYPE(PortalFilter)
Q_DECLARE_METATYPE(QList<PortalFilter>)
static QDBusArgument &operator<<(QDBusArgument &a, const PortalFilterEntry &e) {
    a.beginStructure(); a << e.kind << e.pattern; a.endStructure(); return a;
}
static const QDBusArgument &operator>>(const QDBusArgument &a, PortalFilterEntry &e) {
    a.beginStructure(); a >> e.kind >> e.pattern; a.endStructure(); return a;
}
static QDBusArgument &operator<<(QDBusArgument &a, const PortalFilter &f) {
    a.beginStructure(); a << f.name << f.entries; a.endStructure(); return a;
}
static const QDBusArgument &operator>>(const QDBusArgument &a, PortalFilter &f) {
    a.beginStructure(); a >> f.name >> f.entries; a.endStructure(); return a;
}
#endif

namespace {

constexpr int    kBatchSize     = 5;
constexpr qint64 kLifetimeSecs  = 7 * 24 * 3600;
constexpr double kSlideSecs     = 3.2;   // each photo on screen
constexpr double kCrossfadeSecs = 0.6;   // overlap between photos
constexpr double kClipMaxSecs   = 6.0;   // longest stretch of a video clip
constexpr double kClipMinSecs   = 1.5;
constexpr int    kMaxClips      = 3;     // videos per automatic memory
constexpr double kMusicLevel    = 0.9;
constexpr double kMusicDucked   = 0.25;  // music while a clip's own sound plays
constexpr double kFadeInSecs    = 0.8;
constexpr double kFadeOutSecs   = 1.4;

struct Track { const char *file; const char *mood; };
// Every file is CC0 (see assets/music/LICENSES.md); several per mood.
const Track kTracks[] = {
    { "sunny-morning.ogg", "upbeat" },
    { "still-water.ogg",   "calm" },
    { "golden-hour.ogg",   "nostalgic" },
    { "open-road.ogg",     "energetic" },
    { "daydream.ogg",      "dreamy" },
    { "city-lights.ogg",   "upbeat" },
    { "morning-dew.ogg",   "calm" },
    { "porch-swing.ogg",   "nostalgic" },
    { "tailwind.ogg",      "energetic" },
    { "moonlit.ogg",       "dreamy" },
    { "lazy-sunday.ogg",   "nostalgic" },
    { "harbour-lights.ogg","calm" },
};
constexpr int kTrackCount = int(sizeof(kTracks) / sizeof(kTracks[0]));

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
    // photos a memory was made from (newline-separated paths), so it can be dropped
    // if one of them is later hidden, trashed or ignored. Older rows have none.
    QSqlQuery cols(db);
    bool has = false;
    if (cols.exec(QStringLiteral("PRAGMA table_info(memories)")))
        while (cols.next())
            if (cols.value(1).toString() == QLatin1String("sources")) has = true;
    if (!has) q.exec(QStringLiteral("ALTER TABLE memories ADD COLUMN sources TEXT"));
    // made by hand in the editor: kept until deleted, not replaced by a new batch
    bool hasCustom = false;
    QSqlQuery cols2(db);
    if (cols2.exec(QStringLiteral("PRAGMA table_info(memories)")))
        while (cols2.next())
            if (cols2.value(1).toString() == QLatin1String("custom")) hasCustom = true;
    if (!hasCustom) q.exec(QStringLiteral("ALTER TABLE memories ADD COLUMN custom INTEGER DEFAULT 0"));
}

// true while every photo the memory was made from is still visible in the library
bool sourcesStillVisible(QSqlDatabase db, const QString &sources) {
    if (sources.isEmpty()) return true;
    const QStringList paths = sources.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &p : paths) {
        QSqlQuery q(db);
        q.prepare(QStringLiteral("SELECT 1 FROM media WHERE file_path = ? AND is_trashed = 0 "
                                 "AND COALESCE(is_hidden,0) = 0 AND COALESCE(is_ignored,0) = 0"));
        q.addBindValue(p);
        if (!q.exec() || !q.next()) return false;
    }
    return true;
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

bool isVideoFile(const QString &path) {
    return QMimeDatabase().mimeTypeForFile(path, QMimeDatabase::MatchExtension).name().startsWith(QLatin1String("video/"));
}

// Runs ffprobe and returns its stdout ("" on failure).
QString probe(const QStringList &args) {
    QProcess p;
    p.setProgram(AppPaths::tool(QStringLiteral("ffprobe")));
    p.setArguments(args);
    p.start();
    if (!p.waitForStarted(5000) || !p.waitForFinished(15000) || p.exitCode() != 0) return {};
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}

struct Clip { QString path; bool video = false; bool audio = false; double len = kSlideSecs; double start = 0; };

// Photos hold for kSlideSecs; videos play from their start (up to kClipMaxSecs)
// with their own sound, during which the music is ducked. `total` is the length
// of the finished memory.
QList<Clip> buildClips(const QStringList &paths, double &total) {
    QList<Clip> clips;
    for (const QString &p : paths) {
        Clip c; c.path = p;
        if (isVideoFile(p)) {
            const double d = probe({ "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p }).toDouble();
            if (d < kClipMinSecs) continue;               // unreadable or too short to be worth it
            c.video = true;
            c.len = std::min(d, kClipMaxSecs);
            c.audio = probe({ "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type",
                              "-of", "csv=p=0", p }).contains(QLatin1String("audio"));
        }
        clips << c;
    }
    total = 0;
    for (int i = 0; i < clips.size(); ++i) {
        clips[i].start = total;                            // where it begins in the output
        total += clips[i].len - (i + 1 < clips.size() ? kCrossfadeSecs : 0);
    }
    return clips;
}

// musicStart: seconds into the song where the soundtrack begins.
bool renderSlideshow(const QStringList &paths, const QString &musicFile,
                     const QString &outPath, const QString &coverPath, Rendered &out,
                     double musicStart = 0) {
    double total = 0;
    const QList<Clip> clips = buildClips(paths, total);
    const int n = clips.size();
    if (n < 2) return false;

    QStringList args{ "-y", "-hide_banner", "-loglevel", "error", "-threads", "2" };
    for (const Clip &c : clips) {
        if (c.video) args << "-t" << QString::number(c.len, 'f', 2) << "-i" << c.path;
        else args << "-framerate" << "30" << "-loop" << "1" << "-t" << QString::number(c.len, 'f', 2) << "-i" << c.path;
    }
    if (musicStart > 0.01) args << "-ss" << QString::number(musicStart, 'f', 2);
    args << "-stream_loop" << "-1" << "-i" << musicFile;

    // Each item: blurred, cropped copy as backdrop + the whole frame on top,
    // so portrait and landscape shots both fill the 16:9 frame.
    QStringList f;
    for (int i = 0; i < n; ++i) {
        f << QString("[%1:v]setpts=PTS-STARTPTS,split[a%1][b%1];"
                     "[a%1]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,boxblur=28:3[bg%1];"
                     "[b%1]scale=1280:720:force_original_aspect_ratio=decrease[fg%1];"
                     "[bg%1][fg%1]overlay=(W-w)/2:(H-h)/2,setsar=1,fps=30,format=yuv420p[v%1]").arg(i);
    }
    QString last = "v0";
    for (int i = 1; i < n; ++i) {
        const QString next = i == n - 1 ? "vx" : QString("x%1").arg(i);
        f << QString("[%1][v%2]xfade=transition=fade:duration=%3:offset=%4[%5]")
                 .arg(last).arg(i).arg(kCrossfadeSecs).arg(clips[i].start, 0, 'f', 2).arg(next);
        last = next;
    }
    f << QString("[%1]fade=t=in:st=0:d=%2,fade=t=out:st=%3:d=%4[vout]")
             .arg(last).arg(kFadeInSecs).arg(total - kFadeOutSecs, 0, 'f', 2).arg(kFadeOutSecs);

    // Music: faded at both ends, and pulled down under every clip that has sound.
    QString duck;                                          // 0 (full) … 1 (ducked), as an expression of t
    QStringList voices;
    for (int i = 0; i < n; ++i) {
        if (!clips[i].audio) continue;
        const double a = clips[i].start, b = clips[i].start + clips[i].len;
        const QString ramp = QString("min(1,max(0,min((t-%1)/0.3,(%2-t)/0.3)))").arg(a - 0.3, 0, 'f', 2).arg(b + 0.3, 0, 'f', 2);
        duck = duck.isEmpty() ? ramp : QString("max(%1,%2)").arg(duck, ramp);
        const int ms = qRound(a * 1000);
        f << QString("[%1:a]aresample=44100,aformat=channel_layouts=stereo,afade=t=in:d=0.25,afade=t=out:st=%2:d=0.25,"
                     "adelay=%3|%3[va%1]").arg(i).arg(clips[i].len - 0.25, 0, 'f', 2).arg(ms);
        voices << QString("[va%1]").arg(i);
    }
    const QString music = QString("[%1:a]atrim=0:%2,asetpts=PTS-STARTPTS,aformat=sample_rates=44100:channel_layouts=stereo,"
                                  "afade=t=in:d=1.5,afade=t=out:st=%3:d=2").arg(n).arg(total, 0, 'f', 2).arg(total - 2.0, 0, 'f', 2);
    if (voices.isEmpty()) {
        f << music + QString(",volume=%1[aout]").arg(kMusicLevel);
    } else {
        f << music + QString(",volume='%1-%2*(%3)':eval=frame[mus]").arg(kMusicLevel).arg(kMusicLevel - kMusicDucked).arg(duck);
        f << QString("[mus]%1amix=inputs=%2:duration=first:normalize=0:dropout_transition=0,alimiter=limit=0.95[aout]")
                 .arg(voices.join(QString())).arg(voices.size() + 1);
    }

    args << "-filter_complex" << f.join(";")
         << "-map" << "[vout]" << "-map" << "[aout]"
         << "-t" << QString::number(total, 'f', 2)
         << "-c:v" << "libx264" << "-preset" << "veryfast" << "-crf" << "23" << "-pix_fmt" << "yuv420p"
         << "-c:a" << "aac" << "-b:a" << "160k"
         << "-movflags" << "+faststart" << "-f" << "mp4" << outPath;
    if (!runFfmpeg(args)) { QFile::remove(outPath); return false; }

    // Cover: a frame from inside the first slide.
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

        // Candidates: single days with enough photos, plus whole months (a
        // sample from across the month). Previous batch's picks come last, and a
        // batch uses each month once where it can, so it is not all one stretch.
        struct Cand { QString key; QString month; bool isMonth; };
        QSet<QString> used;
        {
            QSqlQuery q(QStringLiteral("SELECT date FROM memories"), db);
            while (q.next()) used.insert(q.value(0).toString());
        }
        const QString usable = QStringLiteral(
            "is_trashed = 0 AND COALESCE(is_hidden,0) = 0 AND COALESCE(is_ignored,0) = 0 "
            "AND creation_date > 0 AND (mime_type IN ('image/jpeg','image/webp') OR mime_type LIKE 'video/%')");
        QList<Cand> freshC, staleC;
        auto add = [&](const QString &key, const QString &month, bool isMonth) {
            (used.contains(key) ? staleC : freshC).append({ key, month, isMonth });
        };
        {
            QSqlQuery q(db);
            q.prepare(QStringLiteral("SELECT date(creation_date,'unixepoch','localtime') AS d, COUNT(*) AS c FROM media "
                                     "WHERE ") + usable + QStringLiteral(" GROUP BY d HAVING c >= ?"));
            q.addBindValue(minPhotosPerDay());
            if (!q.exec()) qWarning() << "MemoryManager: day query failed" << q.lastError().text();
            while (q.next()) add(q.value(0).toString(), q.value(0).toString().left(7), false);
        }
        {
            QSqlQuery q(db);
            q.prepare(QStringLiteral("SELECT strftime('%Y-%m',creation_date,'unixepoch','localtime') AS m, COUNT(*) AS c FROM media "
                                     "WHERE ") + usable + QStringLiteral(" GROUP BY m HAVING c >= ?"));
            q.addBindValue(minPhotosPerDay() * 2);
            if (q.exec())
                while (q.next()) add(q.value(0).toString(), q.value(0).toString(), true);
        }
        auto shuffle = [](QList<Cand> &l) { std::shuffle(l.begin(), l.end(), *QRandomGenerator::global()); };
        shuffle(freshC); shuffle(staleC);
        const QList<Cand> pool = freshC + staleC;
        QList<Cand> picked;
        QSet<QString> months;
        for (const Cand &c : pool)                       // one per month first…
            if (!months.contains(c.month)) { months.insert(c.month); picked << c; }
        QSet<QString> have;
        for (const Cand &c : picked) have.insert(c.key);
        for (const Cand &c : pool)                       // …then whatever is left
            if (!have.contains(c.key)) picked << c;

        // each track once per batch, in random order
        QList<int> trackOrder;
        for (int i = 0; i < kTrackCount; ++i) trackOrder << i;
        std::shuffle(trackOrder.begin(), trackOrder.end(), *QRandomGenerator::global());

        const qint64 now = QDateTime::currentSecsSinceEpoch();
        QList<qint64> newIds;
        for (int di = 0; di < picked.size() && made < kBatchSize; ++di) {
            const Cand &cand = picked.at(di);
            const QString day = cand.key;
            QSqlQuery q(db);
            q.prepare(QStringLiteral("SELECT file_path, mime_type FROM media WHERE ") + usable + QStringLiteral(" AND ") +
                      (cand.isMonth ? QStringLiteral("strftime('%Y-%m',creation_date,'unixepoch','localtime') = ? ")
                                    : QStringLiteral("date(creation_date,'unixepoch','localtime') = ? ")) +
                      QStringLiteral("ORDER BY RANDOM()"));
            q.addBindValue(day);
            QStringList photos;
            const int want = 8 + QRandomGenerator::global()->bounded(5);   // 8..12
            q.exec();
            int clipsTaken = 0;
            while (q.next() && photos.size() < want) {
                const QString p = q.value(0).toString();
                const bool video = q.value(1).toString().startsWith(QLatin1String("video/"));
                if (video && clipsTaken >= kMaxClips) continue;
                if (!QFile::exists(p)) continue;
                photos << p;
                if (video) ++clipsTaken;
            }
            if (photos.size() < std::min(minPhotosPerDay(), 6)) continue;

            const Track &track = kTracks[trackOrder.at(di % trackOrder.size())];
            const QString music = findMusic(QString::fromLatin1(track.file));
            if (music.isEmpty()) { qWarning() << "MemoryManager: music missing:" << track.file; continue; }

            const QString stem = QStringLiteral("%1/%2-%3").arg(dir, day).arg(now);
            Rendered r;
            if (!renderSlideshow(photos, music, stem + ".part.mp4", stem + ".jpg", r)) continue;
            const QString finalPath = stem + ".mp4";
            QFile::remove(finalPath);
            if (!QFile::rename(r.video, finalPath)) { QFile::remove(r.video); continue; }

            const QDate date = cand.isMonth ? QDate::fromString(day + QStringLiteral("-01"), Qt::ISODate)
                                            : QDate::fromString(day, Qt::ISODate);
            QSqlQuery ins(db);
            ins.prepare(QStringLiteral(
                "INSERT INTO memories (date,title,video_path,cover_path,mood,duration_ms,photo_count,created_at,expires_at,sources) "
                "VALUES (?,?,?,?,?,?,?,?,?,?)"));
            ins.addBindValue(day);
            ins.addBindValue(QLocale().toString(date, cand.isMonth ? QStringLiteral("MMMM yyyy")
                                                               : QStringLiteral("dddd, d MMMM yyyy")));
            ins.addBindValue(finalPath);
            ins.addBindValue(r.cover);
            ins.addBindValue(QString::fromLatin1(track.mood));
            ins.addBindValue(r.durationMs);
            ins.addBindValue(photos.size());
            ins.addBindValue(now);
            ins.addBindValue(now + kLifetimeSecs);
            ins.addBindValue(photos.join(QLatin1Char('\n')));
            if (!ins.exec()) { QFile::remove(finalPath); continue; }
            newIds << ins.lastInsertId().toLongLong();
            ++made;
        }

        // Retire the previous batch only once a replacement exists.
        if (made > 0) {
            QSqlQuery old(db);
            old.prepare(QStringLiteral("SELECT id, video_path, cover_path FROM memories WHERE created_at < ? AND COALESCE(custom,0) = 0"));
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

QString defaultTitleFor(const QString &isoDate) {
    const QDate d = QDate::fromString(isoDate, Qt::ISODate);
    return d.isValid() ? QLocale().toString(d, QStringLiteral("dddd, d MMMM yyyy")) : QString();
}

// Worker for the editor: renders the chosen photos with the chosen song.
int renderCustom(const QString &dbPath, const QString &dir, const QStringList &photos,
                 const QString &trackFile, const QString &title, const QString &isoDate, double musicStart) {
    const QString conn = QStringLiteral("kader_memories_c_%1").arg(quintptr(QThread::currentThreadId()));
    int made = 0;
    {
        QSqlDatabase db = openDb(dbPath, conn);
        ensureTable(db);
        QDir().mkpath(dir);

        const bool own = QFileInfo(trackFile).isAbsolute();   // a song the user added
        const QString music = own ? (QFile::exists(trackFile) ? trackFile : QString()) : findMusic(trackFile);
        const char *mood = own ? "custom" : "upbeat";
        for (const Track &t : kTracks)
            if (trackFile == QLatin1String(t.file)) mood = t.mood;
        if (!music.isEmpty()) {
            const qint64 now = QDateTime::currentSecsSinceEpoch();
            const QString stem = QStringLiteral("%1/%2-custom-%3").arg(dir, isoDate).arg(now);
            Rendered r;
            if (renderSlideshow(photos, music, stem + ".part.mp4", stem + ".jpg", r, musicStart)) {
                const QString finalPath = stem + ".mp4";
                QFile::remove(finalPath);
                if (QFile::rename(r.video, finalPath)) {
                    // only library photos can be watched for hide/trash
                    QStringList tracked;
                    for (const QString &p : photos) {
                        QSqlQuery q(db);
                        q.prepare(QStringLiteral("SELECT 1 FROM media WHERE file_path = ?"));
                        q.addBindValue(p);
                        if (q.exec() && q.next()) tracked << p;
                    }
                    QSqlQuery ins(db);
                    ins.prepare(QStringLiteral(
                        "INSERT INTO memories (date,title,video_path,cover_path,mood,duration_ms,photo_count,created_at,expires_at,sources,custom) "
                        "VALUES (?,?,?,?,?,?,?,?,?,?,1)"));
                    ins.addBindValue(isoDate);
                    ins.addBindValue(title);
                    ins.addBindValue(finalPath);
                    ins.addBindValue(r.cover);
                    ins.addBindValue(QString::fromLatin1(mood));
                    ins.addBindValue(r.durationMs);
                    ins.addBindValue(photos.size());
                    ins.addBindValue(now);
                    ins.addBindValue(now + 100LL * 365 * 24 * 3600);
                    ins.addBindValue(tracked.join(QLatin1Char('\n')));
                    if (ins.exec()) made = 1; else QFile::remove(finalPath);
                } else {
                    QFile::remove(r.video);
                }
            }
        } else {
            qWarning() << "MemoryManager: music missing:" << trackFile;
        }
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
        q.prepare(QStringLiteral("SELECT COUNT(*) FROM memories WHERE expires_at > ? AND COALESCE(custom,0) = 0"));
        q.addBindValue(QDateTime::currentSecsSinceEpoch());
        if (q.exec() && q.next() && q.value(0).toInt() >= kBatchSize)
            return;                                   // a full live batch exists
    }

    startBatch();
}

void MemoryManager::regenerate() {
    if (!m_generating) startBatch();
}

void MemoryManager::startBatch() {
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
    QSqlQuery q(QStringLiteral("SELECT id,date,title,video_path,cover_path,mood,duration_ms,photo_count,expires_at,sources "
                               "FROM memories ORDER BY date DESC"), db);
    QList<int> stale;
    while (q.next()) {
        const QString video = q.value(3).toString();
        if (!QFile::exists(video)) continue;
        if (!sourcesStillVisible(db, q.value(9).toString())) { stale << q.value(0).toInt(); continue; }
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
    q.finish();
    // a photo behind these was hidden/trashed/ignored since: don't keep a video of it
    for (int id : stale) const_cast<MemoryManager *>(this)->remove(id);
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

#ifdef Q_OS_WIN
bool MemoryManager::saveViaPortal(int) { return false; }   // QML uses the native Windows dialogs
bool MemoryManager::pickSongViaPortal() { return false; }
bool MemoryManager::callFileChooser(const char *, const QString &, QVariantMap) { return false; }
void MemoryManager::onPortalResponse(uint, const QVariantMap &) {}
#else
// Calls org.freedesktop.portal.FileChooser.<method>; the answer arrives later as
// Request::Response on onPortalResponse(). False if the portal can't be reached.
bool MemoryManager::callFileChooser(const char *method, const QString &title, QVariantMap options) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) return false;

    // Request objects live at .../request/<our unique name>/<handle_token>; listen
    // before calling so the Response signal cannot be missed (portal spec).
    const QString token = QStringLiteral("kader_fc_%1").arg(QRandomGenerator::global()->generate());
    QString sender = bus.baseService();
    sender.remove(0, 1);
    sender.replace(QLatin1Char('.'), QLatin1Char('_'));
    const QString handle = QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
    const auto connectOrNot = [&](bool on) {
        return on ? bus.connect(QStringLiteral("org.freedesktop.portal.Desktop"), handle,
                                QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
                                this, SLOT(onPortalResponse(uint, QVariantMap)))
                  : bus.disconnect(QStringLiteral("org.freedesktop.portal.Desktop"), handle,
                                   QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
                                   this, SLOT(onPortalResponse(uint, QVariantMap)));
    };
    if (!connectOrNot(true)) return false;

    options.insert(QStringLiteral("handle_token"), token);
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.portal.Desktop"), QStringLiteral("/org/freedesktop/portal/desktop"),
        QStringLiteral("org.freedesktop.portal.FileChooser"), QString::fromLatin1(method));
    msg << QString() << title << options;                  // parent_window "" = none
    const QDBusMessage reply = bus.call(msg, QDBus::Block, 5000);
    if (reply.type() != QDBusMessage::ReplyMessage) {
        qWarning() << "MemoryManager: FileChooser portal unavailable:" << reply.errorMessage();
        connectOrNot(false);
        return false;
    }
    m_pendingHandle = handle;
    return true;
}

bool MemoryManager::saveViaPortal(int id) {
    if (m_pendingSaveId >= 0 || m_pendingSong) return true;   // a dialog is already open
    QVariantMap options;
    options.insert(QStringLiteral("current_name"), suggestedFileName(id));
    options.insert(QStringLiteral("current_folder"),
                   QStandardPaths::writableLocation(QStandardPaths::MoviesLocation).toLocal8Bit() + '\0');
    if (!callFileChooser("SaveFile", tr("Save as…"), options)) return false;
    m_pendingSaveId = id;
    return true;
}

bool MemoryManager::pickSongViaPortal() {
    if (m_pendingSaveId >= 0 || m_pendingSong) return true;
    static const bool registered = [] {
        qDBusRegisterMetaType<PortalFilterEntry>();
        qDBusRegisterMetaType<QList<PortalFilterEntry>>();
        qDBusRegisterMetaType<PortalFilter>();
        qDBusRegisterMetaType<QList<PortalFilter>>();
        return true;
    }();
    Q_UNUSED(registered)
    // filters a(sa(us)): (name, [(0 = glob | 1 = mime type, pattern)])
    PortalFilter audio{ tr("Audio files"), { { 1, QStringLiteral("audio/*") } } };
    QVariantMap options;
    options.insert(QStringLiteral("filters"), QVariant::fromValue(QList<PortalFilter>{ audio }));
    options.insert(QStringLiteral("multiple"), false);
    const QString music = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (!music.isEmpty()) options.insert(QStringLiteral("current_folder"), music.toLocal8Bit() + '\0');
    if (!callFileChooser("OpenFile", tr("Choose a song"), options)) return false;
    m_pendingSong = true;
    return true;
}

void MemoryManager::onPortalResponse(uint response, const QVariantMap &results) {
    QDBusConnection::sessionBus().disconnect(QStringLiteral("org.freedesktop.portal.Desktop"), m_pendingHandle,
                                             QStringLiteral("org.freedesktop.portal.Request"),
                                             QStringLiteral("Response"), this,
                                             SLOT(onPortalResponse(uint, QVariantMap)));
    const int saveId = m_pendingSaveId;
    const bool song = m_pendingSong;
    m_pendingSaveId = -1;
    m_pendingSong = false;
    m_pendingHandle.clear();
    if (response != 0) return;                            // cancelled or failed
    const QStringList uris = results.value(QStringLiteral("uris")).toStringList();
    if (uris.isEmpty()) return;
    if (song) {
        importSong(uris.first());                         // emits songAdded / songRejected
    } else if (saveId >= 0) {
        const QString written = exportTo(saveId, uris.first());
        if (!written.isEmpty()) emit saved(written);
    }
}
#endif

QVariantList MemoryManager::tracks() const {
    QVariantList out;
    const QDir own(m_dir + QStringLiteral("/../memory-music"));
    for (const QFileInfo &fi : own.entryInfoList(QDir::Files, QDir::Name)) {
        QVariantMap m;
        m["file"] = fi.absoluteFilePath();
        m["name"] = fi.completeBaseName();
        m["mood"] = QStringLiteral("custom");
        out << m;
    }
    for (const Track &t : kTracks) {
        const QString file = QString::fromLatin1(t.file);
        if (findMusic(file).isEmpty()) continue;
        QStringList words = QFileInfo(file).completeBaseName().split(QLatin1Char('-'), Qt::SkipEmptyParts);
        for (QString &w : words) w[0] = w[0].toUpper();
        QVariantMap m;
        m["file"] = file;
        m["name"] = words.join(QLatin1Char(' '));
        m["mood"] = QString::fromLatin1(t.mood);
        out << m;
    }
    return out;
}

QString MemoryManager::suggestDate(const QStringList &photos) const {
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    QList<qint64> times;
    for (const QString &p : photos) {
        qint64 t = 0;
        QSqlQuery q(db);
        q.prepare(QStringLiteral("SELECT creation_date FROM media WHERE file_path = ?"));
        q.addBindValue(p);
        if (q.exec() && q.next()) t = q.value(0).toLongLong();
        if (t <= 0) t = QFileInfo(p).lastModified().toSecsSinceEpoch();
        if (t > 0) times << t;
    }
    if (times.isEmpty()) return QDate::currentDate().toString(Qt::ISODate);
    std::sort(times.begin(), times.end());
    return QDateTime::fromSecsSinceEpoch(times.at(times.size() / 2)).date().toString(Qt::ISODate);
}

QString MemoryManager::defaultTitle(const QString &isoDate) const { return defaultTitleFor(isoDate); }

bool MemoryManager::createCustom(const QStringList &photos, const QString &trackFile,
                                 const QString &title, const QString &isoDate, double musicStart) {
    if (m_generating || photos.size() < 2 || !QDate::fromString(isoDate, Qt::ISODate).isValid()) return false;
    const QString name = title.trimmed().isEmpty() ? defaultTitleFor(isoDate) : title.trimmed();
    m_generating = true;
    emit generatingChanged();
    auto *watcher = new QFutureWatcher<int>(this);
    connect(watcher, &QFutureWatcher<int>::finished, this, [this, watcher] {
        const int made = watcher->result();
        watcher->deleteLater();
        finishBatch(made);
    });
    watcher->setFuture(QtConcurrent::run(renderCustom, m_dbPath, m_dir, photos, trackFile, name, isoDate, musicStart));
    return true;
}

QString MemoryManager::importSong(const QString &urlOrPath) {
    const QString src = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QString fileName = QFileInfo(src).fileName();
    if (!QFileInfo::exists(src)) { emit songRejected(fileName); return {}; }

    // must hold an audio stream ffmpeg can decode (the slideshow's soundtrack)
    QProcess probe;
    probe.setProgram(AppPaths::tool(QStringLiteral("ffprobe")));
    probe.setArguments({ "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type",
                         "-of", "csv=p=0", src });
    probe.start();
    const bool isAudio = probe.waitForStarted(5000) && probe.waitForFinished(15000)
                         && probe.exitCode() == 0
                         && probe.readAllStandardOutput().contains("audio");
    if (!isAudio) { emit songRejected(fileName); return {}; }

    const QString dir = QDir::cleanPath(m_dir + QStringLiteral("/../memory-music"));
    QDir().mkpath(dir);
    const QString dest = dir + QLatin1Char('/') + fileName;
    if (QFile::exists(dest)) QFile::remove(dest);
    if (!QFile::copy(src, dest)) { emit songRejected(fileName); return {}; }
    const QString stored = QFileInfo(dest).absoluteFilePath();
    emit songAdded(stored);
    return stored;
}

QVariantList MemoryManager::libraryPhotos() const {
    QVariantList out;
    QSqlDatabase db = openDb(m_dbPath, QStringLiteral("kader_memories_main"));
    QSqlQuery q(QStringLiteral(
        "SELECT id,file_path,mime_type FROM media WHERE is_trashed = 0 AND COALESCE(is_hidden,0) = 0 "
        "AND COALESCE(is_ignored,0) = 0 AND (mime_type IN ('image/jpeg','image/webp','image/png') OR mime_type LIKE 'video/%') "
        "ORDER BY creation_date DESC LIMIT 6000"), db);
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["file_path"] = q.value(1).toString();
        m["mime_type"] = q.value(2).toString();
        m["thumb"] = ThumbnailGenerator::thumbnailUrl(q.value(1).toString());
        out << m;
    }
    return out;
}

QString MemoryManager::thumbUrl(const QString &path) const { return ThumbnailGenerator::thumbnailUrl(path); }

double MemoryManager::songDuration(const QString &path) const {
    return probe({ "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path }).toDouble();
}

double MemoryManager::estimateDuration(const QStringList &paths) const {
    double total = 0;
    buildClips(paths, total);
    return total;
}

// Peak level (0..1) of `buckets` equal slices of the song, for drawing the section picker.
QVariantList MemoryManager::waveform(const QString &path, int buckets) const {
    QVariantList out;
    if (buckets < 8) return out;
    QProcess p;
    p.setProgram(AppPaths::tool(QStringLiteral("ffmpeg")));
    p.setArguments({ "-v", "error", "-i", path, "-vn", "-ac", "1", "-ar", "4000", "-f", "s16le", "-" });
    p.start();
    if (!p.waitForStarted(5000) || !p.waitForFinished(60000) || p.exitCode() != 0) return out;
    const QByteArray raw = p.readAllStandardOutput();
    const auto *smp = reinterpret_cast<const qint16 *>(raw.constData());
    const qsizetype count = raw.size() / 2;
    if (count < buckets) return out;
    QList<double> peaks(buckets, 0.0);
    double top = 1e-6;
    for (int b = 0; b < buckets; ++b) {
        const qsizetype from = count * b / buckets, to = count * (b + 1) / buckets;
        qint16 m = 0;
        for (qsizetype i = from; i < to; ++i) m = std::max<qint16>(m, qint16(std::abs(int(smp[i]))));
        peaks[b] = m;
        top = std::max(top, peaks[b]);
    }
    for (double v : peaks) out << v / top;
    return out;
}
