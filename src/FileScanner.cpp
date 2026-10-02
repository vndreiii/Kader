#include "FileScanner.h"
#include "DatabaseManager.h"
#include "MediaRepository.h"
#include "ThumbnailGenerator.h"
#include <exiv2/exiv2.hpp>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <algorithm>
#include <thread>
#include <QtConcurrent>
#include <QFileInfo>
#include <QDir>
#include <QUrl>
#include <QCollator>
#include <QVariantMap>
#include <QDateTime>
#include <QMimeDatabase>
#include <QProcess>
#include <QSize>
#include <QDebug>
#include <QSet>
#include <QElapsedTimer>
#include <QTimeZone>
#include "kader_core.h"
// GLib (via libvips) has struct fields named `signals`, which Qt's keyword
// macro would rewrite — shield the include from it.
#pragma push_macro("signals")
#undef signals
#include <vips/vips8>
#pragma pop_macro("signals")

namespace {

// Exiv2 0.28 renamed Value::toLong() to toInt64(); support both (Ubuntu LTS
// still ships 0.27, which the AppImage is built against).
inline long long exivInt(const Exiv2::Value &v) {
#if EXIV2_TEST_VERSION(0, 28, 0)
    return v.toInt64();
#else
    return v.toLong();
#endif
}

// Read true pixel dimensions from an image header (no full decode). Handles the
// formats libvips supports (JPEG/PNG/WebP/TIFF/HEIF/RAW via the native loaders),
// covering the many files that carry no EXIF PixelXDimension tag.
QSize probeImageDimensions(const QString &path) {
    try {
        vips::VImage img = vips::VImage::new_from_file(
            path.toLocal8Bit().constData(),
            vips::VImage::option()->set("access", VIPS_ACCESS_SEQUENTIAL));
        return QSize(img.width(), img.height());
    } catch (...) {
        return QSize();
    }
}

// Probe a video for pixel dimensions and duration via ffprobe. Returns false if
// ffprobe is missing or the file has no video stream. Runs synchronously; the
// scan already executes on a worker thread.
bool probeVideo(const QString &path, int &w, int &h, double &durationSec) {
    QProcess p;
    p.start("ffprobe", {
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height:format=duration",
        "-of", "default=noprint_wrappers=1",
        path
    });
    if (!p.waitForStarted(2000)) return false;
    if (!p.waitForFinished(8000)) { p.kill(); return false; }

    const QString out = QString::fromUtf8(p.readAllStandardOutput());
    bool got = false;
    const QList<QStringView> lines = QStringView(out).split(u'\n', Qt::SkipEmptyParts);
    for (const QStringView &line : lines) {
        const int eq = line.indexOf(u'=');
        if (eq < 0) continue;
        const QStringView key = line.left(eq);
        const QStringView val = line.mid(eq + 1);
        if (key == u"width")        { w = val.toInt(); got = true; }
        else if (key == u"height")  { h = val.toInt(); got = true; }
        else if (key == u"duration") durationSec = val.toDouble();
    }
    return got;
}

// Drop the calling thread to a background scheduling priority. The scan is
// entirely background work — directory walking, EXIF parsing, ffprobe — and it
// runs a worker per core, so at equal priority it competes with the GUI and Qt
// render threads and the window stops responding while a scan is in flight.
// Nice values are per-thread on Linux, so this only affects the scan workers.
void deprioritiseCurrentThread() {
    setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), 10);
}

} // namespace

FileScanner::FileScanner(DatabaseManager *db, QObject *parent) : QObject(parent), m_db(db) {
    // Exiv2 prints a warning to stderr for every slightly non-standard file
    // (thousands per library); only real errors are worth surfacing.
    Exiv2::LogMsg::setLevel(Exiv2::LogMsg::error);
    // scanFinished comes from the worker; count it down on the GUI thread
    connect(this, &FileScanner::scanFinished, this, [this] {
        if (m_activeScans > 0 && --m_activeScans == 0)
            emit scanningChanged();
    }, Qt::QueuedConnection);
    m_mediaExtensions = {
        // Standard images
        ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff", ".tif", ".heic", ".heif",
        // Video
        ".mp4", ".mkv", ".mov", ".avi", ".webm",
        // RAW camera formats
        ".nef", ".cr2", ".cr3", ".arw", ".dng", ".raf", ".orf",
        ".rw2", ".pef", ".srw", ".3fr", ".raw", ".rw1", ".mrw", ".x3f", ".dcr"
    };
}

FileScanner::~FileScanner() {
    if (m_scanFuture.isRunning())
        m_scanFuture.waitForFinished();
}

QVariantList FileScanner::listSiblingMedia(const QString &filePath) const {
    QVariantList out;

    QString path = filePath;
    if (path.startsWith("file://"))
        path = QUrl(path).toLocalFile();

    QFileInfo info(path);
    QDir dir = info.absoluteDir();
    if (!dir.exists())
        return out;

    // Build name filters ("*.jpg", …) from the same extension set used by the
    // recursive scanner so the viewer sees exactly what the gallery would.
    QStringList filters;
    for (const std::string &ext : m_mediaExtensions)
        filters << ("*" + QString::fromStdString(ext));

    QFileInfoList entries = dir.entryInfoList(filters, QDir::Files);

    // Natural, case-insensitive sort ("img2" before "img10") to match how a
    // file manager presents the folder.
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(entries.begin(), entries.end(),
              [&collator](const QFileInfo &a, const QFileInfo &b) {
                  return collator.compare(a.fileName(), b.fileName()) < 0;
              });

    static const QStringList kVideoExts = {"mp4", "mkv", "mov", "avi", "webm"};
    for (const QFileInfo &fi : entries) {
        const QString suffix = fi.suffix().toLower();
        QString mime;
        if (suffix == "gif")                 mime = "image/gif";
        else if (kVideoExts.contains(suffix)) mime = "video/mp4";
        else                                  mime = "image/jpeg";

        QVariantMap m;
        m["file_path"]   = fi.absoluteFilePath();
        m["mime_type"]   = mime;
        m["id"]          = -1;
        m["is_favorite"] = false;
        m["is_trashed"]  = false;
        out.append(m);
    }
    return out;
}

void FileScanner::startScan(const QString &rootPath) {
    qDebug() << "Start scan requested for:" << rootPath;
    if (m_activeScans++ == 0)
        emit scanningChanged();
    emit scanStarted(rootPath);
    // getScanExclusions() is a SQL round-trip and startScan() is called from the
    // GUI thread (startup timer, QML, and the milfs-connect callback), so read
    // the exclusions on the worker instead of before dispatching.
    m_scanFuture = QtConcurrent::run([this, rootPath]() {
        std::vector<std::string> exclusions;
        for (const QString &p : m_db->getScanExclusions())
            exclusions.push_back(p.toStdString());
        runScan(rootPath.toStdString(), exclusions);
    });
}

namespace {

// GPS from Exiv2 (fallback path for formats the Rust probe doesn't read).
bool exivGps(const Exiv2::ExifData &exif, double &lat, double &lon) {
    auto itLat    = exif.findKey(Exiv2::ExifKey("Exif.GPSInfo.GPSLatitude"));
    auto itLatRef = exif.findKey(Exiv2::ExifKey("Exif.GPSInfo.GPSLatitudeRef"));
    auto itLon    = exif.findKey(Exiv2::ExifKey("Exif.GPSInfo.GPSLongitude"));
    auto itLonRef = exif.findKey(Exiv2::ExifKey("Exif.GPSInfo.GPSLongitudeRef"));
    if (itLat == exif.end() || itLon == exif.end()) return false;
    auto toDeg = [](const Exiv2::Value &v) {
        double out = 0, div = 1;
        for (int i = 0; i < 3 && i < static_cast<int>(v.count()); ++i, div *= 60) {
            const auto r = v.toRational(i);
            if (r.second != 0) out += static_cast<double>(r.first) / r.second / div;
        }
        return out;
    };
    lat = toDeg(itLat->value());
    lon = toDeg(itLon->value());
    if (itLatRef != exif.end() && itLatRef->toString() == "S") lat = -lat;
    if (itLonRef != exif.end() && itLonRef->toString() == "W") lon = -lon;
    return true;
}

// Slow path for files the Rust probe could not fully read (CR3, exotic RAW,
// MKV/AVI…): Exiv2 for EXIF, libvips for pixel size, ffprobe for video.
void fillWithFallbacks(MediaEntry &entry) {
    if (entry.mimeType.startsWith(QLatin1String("image/"))) {
        try {
            auto image = Exiv2::ImageFactory::open(entry.filePath.toStdString());
            image->readMetadata();
            const Exiv2::ExifData &exif = image->exifData();
            if (!entry.creationDate.isValid() || entry.creationDate == entry.modifiedDate) {
                for (const char *key : {"Exif.Photo.DateTimeOriginal", "Exif.Image.DateTime"}) {
                    auto it = exif.findKey(Exiv2::ExifKey(key));
                    if (it != exif.end()) {
                        QDateTime dt = QDateTime::fromString(QString::fromStdString(it->toString()),
                                                             QStringLiteral("yyyy:MM:dd HH:mm:ss"));
                        if (dt.isValid()) { entry.creationDate = dt; break; }
                    }
                }
            }
            if (entry.latitude == 0.0 && entry.longitude == 0.0)
                exivGps(exif, entry.latitude, entry.longitude);
            if (entry.width <= 0 || entry.height <= 0) {
                auto itW = exif.findKey(Exiv2::ExifKey("Exif.Photo.PixelXDimension"));
                auto itH = exif.findKey(Exiv2::ExifKey("Exif.Photo.PixelYDimension"));
                if (itW != exif.end()) entry.width  = static_cast<int>(exivInt(itW->value()));
                if (itH != exif.end()) entry.height = static_cast<int>(exivInt(itH->value()));
            }
        } catch (...) {}
        if (entry.width <= 0 || entry.height <= 0) {
            const QSize sz = probeImageDimensions(entry.filePath);
            if (sz.isValid()) { entry.width = sz.width(); entry.height = sz.height(); }
        }
    } else if (entry.mimeType.startsWith(QLatin1String("video/"))) {
        int vw = 0, vh = 0;
        double dur = 0.0;
        if (probeVideo(entry.filePath, vw, vh, dur)) {
            entry.width = vw; entry.height = vh; entry.duration = dur;
        }
    }
}

struct ProgressCtx { FileScanner *scanner; };

} // namespace

void FileScanner::runScan(const std::string &rootPath, const std::vector<std::string> &exclusions) {
    QElapsedTimer clock;
    clock.start();

    // This body also runs the metadata pass. It runs on a shared QtConcurrent
    // pool thread, so restore the original priority on the way out rather
    // than leaving the thread niced for whatever task the pool hands it next.
    const int callerPriority = getpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)));
    deprioritiseCurrentThread();
    struct PriorityRestore {
        int priority;
        ~PriorityRestore() { setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), priority); }
    } restorePriority{callerPriority};

    const int threads = std::max(1, m_maxThreads.load() > 0 ? m_maxThreads.load()
                                                          : int(std::thread::hardware_concurrency()));

    // 1. Parallel walk (Rust): every media file with its size and mtime.
    std::vector<const char *> exts, excl;
    for (const std::string &e : m_mediaExtensions) exts.push_back(e.c_str());
    for (const std::string &e : exclusions) excl.push_back(e.c_str());
    ProgressCtx ctx{this};
    KsScan *scan = ks_scan_dir(rootPath.c_str(), exts.data(), exts.size(), excl.data(), excl.size(),
                               uint32_t(threads),
                               [](void *user, size_t found) {
                                   emit static_cast<ProgressCtx *>(user)->scanner->scanProgress(int(found));
                               },
                               &ctx);
    const size_t found = ks_scan_count(scan);
    const size_t dirs = ks_scan_dirs(scan);
    qDebug() << "Scan found" << found << "candidate files in" << dirs << "directories in"
             << clock.elapsed() << "ms";

    // 2. One query for everything the index already has under this root.
    const QString root = QString::fromStdString(rootPath);
    const QHash<QString, qint64> known = m_db->indexSnapshot(root);

    struct Pending { QByteArray path; qint64 size; qint64 mtime; };
    std::vector<Pending> pending;
    pending.reserve(found / 8 + 16);
    QSet<QString> present;
    present.reserve(qsizetype(found));
    for (size_t i = 0; i < found; ++i) {
        const uint8_t *p = nullptr; size_t len = 0; uint64_t size = 0; int64_t mtime = 0;
        if (!ks_scan_entry(scan, i, &p, &len, &size, &mtime)) continue;
        const QByteArray path(reinterpret_cast<const char *>(p), qsizetype(len));
        const QString qpath = QFile::decodeName(path);
        present.insert(qpath);
        const auto it = known.constFind(qpath);
        if (it != known.cend() && it.value() == qint64(size)) continue; // unchanged and complete
        pending.push_back({path, qint64(size), mtime});
    }
    ks_scan_free(scan);

    // Files indexed under this root that the walk no longer sees were deleted
    // or moved: prune them now (the periodic sweep used to stat every file).
    // Skipped when the walk found nothing at all, e.g. an unmounted drive.
    int pruned = 0;
    if (found > 0) {
        QStringList gone;
        for (auto it = known.cbegin(); it != known.cend(); ++it)
            if (!present.contains(it.key()))
                gone << it.key();
        if (!gone.isEmpty()) {
            pruned = m_db->removeMediaPaths(gone);
            qDebug() << "Scan pruned" << pruned << "missing files";
        }
    }

    // 3. Metadata for new/changed files: Rust probes in parallel batches,
    //    falling back to Exiv2/libvips/ffprobe only where needed.
    QMimeDatabase mimeDb;
    QVector<MediaEntry> newEntries;
    newEntries.reserve(int(pending.size()));
    constexpr size_t kBatch = 512;
    int fallbacks = 0;
    for (size_t base = 0; base < pending.size(); base += kBatch) {
        const size_t n = std::min(kBatch, pending.size() - base);
        std::vector<const uint8_t *> ptrs(n);
        std::vector<size_t> lens(n);
        for (size_t i = 0; i < n; ++i) {
            ptrs[i] = reinterpret_cast<const uint8_t *>(pending[base + i].path.constData());
            lens[i] = size_t(pending[base + i].path.size());
        }
        std::vector<KsMeta> metas(n);
        ks_probe_batch(ptrs.data(), lens.data(), n, uint32_t(threads), metas.data());

        for (size_t i = 0; i < n; ++i) {
            const Pending &f = pending[base + i];
            const KsMeta &m = metas[i];
            MediaEntry entry;
            entry.filePath = QFile::decodeName(f.path);
            const int slash = entry.filePath.lastIndexOf(QLatin1Char('/'));
            entry.folderPath = slash > 0 ? entry.filePath.left(slash) : QStringLiteral("/");
            entry.fileSize = f.size;
            // by extension only: never sniff file contents here
            entry.mimeType = mimeDb.mimeTypeForFile(entry.filePath, QMimeDatabase::MatchExtension).name();
            entry.modifiedDate = QDateTime::fromSecsSinceEpoch(f.mtime);
            entry.creationDate = entry.modifiedDate;
            if (m.flags & KS_DATE) {
                const QDate d(m.year, m.month, m.day);
                const QTime t(m.hour, m.minute, m.second);
                const QDateTime dt = (m.flags & KS_DATE_UTC) ? QDateTime(d, t, QTimeZone::UTC).toLocalTime()
                                                             : QDateTime(d, t);
                if (dt.isValid()) entry.creationDate = dt;
            }
            if (m.flags & KS_SIZE) { entry.width = int(m.width); entry.height = int(m.height); }
            if (m.flags & KS_GPS) { entry.latitude = m.lat; entry.longitude = m.lon; }
            if (m.flags & KS_DURATION) entry.duration = m.duration;

            const bool isVideo = entry.mimeType.startsWith(QLatin1String("video/"));
            const bool complete = (m.flags & KS_KNOWN) && (m.flags & KS_SIZE) && (!isVideo || (m.flags & KS_DURATION));
            if (!complete) {
                fillWithFallbacks(entry);
                ++fallbacks;
            }
            newEntries.append(std::move(entry));
        }
        emit scanProgress(int(found));
    }

    // 4. One transaction for all new/updated rows — crash-safe via WAL.
    if (!newEntries.isEmpty())
        m_db->addOrUpdateMediaBatch(newEntries);
    m_db->updateDirectoryStats(root, int(found));

    qDebug() << "Scan of" << root << ":" << newEntries.size() << "new/changed," << fallbacks
             << "needed fallbacks," << clock.elapsed() << "ms total";

    // Emit first so the UI refreshes immediately with the new items. A rescan
    // that changed nothing doesn't make every model re-query the library.
    if (!newEntries.isEmpty() || pruned > 0)
        emit libraryChanged(root);
    emit scanFinished(int(found), int(dirs), clock.elapsed() / 1000.0, root);

    // Pre-generate thumbnails after the UI has already updated.
    // Runs in a separate detached task so it never blocks the main thread.
    if (m_thumbGen && !newEntries.isEmpty()) {
        ThumbnailGenerator *gen = m_thumbGen;
        DatabaseManager    *db  = m_db;
        QtConcurrent::run([gen, db, entries = std::move(newEntries)]() {
            for (const MediaEntry &e : entries) {
                QByteArray bytes = e.mimeType.startsWith("video/")
                    ? gen->generateVideoThumbnailBytes(e.filePath)
                    : gen->generateThumbnailBytes(e.filePath);
                if (!bytes.isEmpty())
                    db->storeThumbnailBlob(e.filePath, 256, ThumbnailGenerator::encrypt(bytes));
            }
        });
    }
}
