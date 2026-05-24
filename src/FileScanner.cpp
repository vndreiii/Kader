#include "FileScanner.h"
#include "DatabaseManager.h"
#include "MediaRepository.h"
#include "ThumbnailGenerator.h"
#include <exiv2/exiv2.hpp>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <dirent.h>
#include <string.h>
#include <algorithm>
#include <thread>
#include <mutex>
#include <queue>
#include <condition_variable>
#include <chrono>
#include <QtConcurrent>
#include <QFileInfo>
#include <QDateTime>
#include <QMimeDatabase>
#include <QDebug>

struct linux_dirent64 {
    unsigned long long d_ino;
    long long          d_off;
    unsigned short     d_reclen;
    unsigned char      d_type;
    char               d_name[];
};

class InternalWorkQueue {
    std::queue<std::string> queue;
    std::mutex mutex;
    std::condition_variable cv;
    std::atomic<int> active_workers{0};
    bool stop = false;

public:
    void push(std::string path) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            queue.push(std::move(path));
        }
        cv.notify_one();
    }

    bool pop(std::string& path) {
        std::unique_lock<std::mutex> lock(mutex);
        cv.wait(lock, [this] { return !queue.empty() || stop; });
        if (stop && queue.empty()) return false;
        path = std::move(queue.front());
        queue.pop();
        active_workers++;
        return true;
    }

    void worker_done() {
        active_workers--;
        if (active_workers == 0 && queue.empty()) {
            {
                std::lock_guard<std::mutex> lock(mutex);
                stop = true;
            }
            cv.notify_all();
        }
    }
};

FileScanner::FileScanner(DatabaseManager *db, QObject *parent) : QObject(parent), m_db(db) {
    m_mediaExtensions = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".mp4", ".mkv", ".mov", ".avi", ".webm"};
}

FileScanner::~FileScanner() {
    if (m_scanFuture.isRunning())
        m_scanFuture.waitForFinished();
}

void FileScanner::startScan(const QString &rootPath) {
    qDebug() << "Start scan requested for:" << rootPath;
    emit scanStarted(rootPath);
    QStringList qExclusions = m_db->getScanExclusions();
    std::vector<std::string> exclusions;
    for (const QString &p : qExclusions)
        exclusions.push_back(p.toStdString());
    m_scanFuture = QtConcurrent::run([this, rootPath, exclusions]() {
        runScan(rootPath.toStdString(), exclusions);
    });
}

void FileScanner::runScan(const std::string &rootPath, const std::vector<std::string> &exclusions) {
    auto start = std::chrono::high_resolution_clock::now();
    
    InternalWorkQueue wq;
    wq.push(rootPath);

    std::atomic<size_t> dirsScanned{0};
    std::mutex pathsMutex;
    struct FoundFileInfo {
        QString path;
        qint64 size;
    };
    QList<FoundFileInfo> foundFiles;
    
    int numThreads = std::thread::hardware_concurrency();
    std::vector<std::thread> workers;

    for (int i = 0; i < numThreads; ++i) {
        workers.emplace_back([this, &wq, &dirsScanned, &pathsMutex, &foundFiles, &exclusions]() {
            std::string path;
            while (wq.pop(path)) {
                int fd = open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
                if (fd != -1) {
                    dirsScanned++;
                    char buf[32768];
                    while (true) {
                        long nread = syscall(SYS_getdents64, fd, buf, sizeof(buf));
                        if (nread <= 0) break;

                        for (long bpos = 0; bpos < nread; ) {
                            struct linux_dirent64 *d = (struct linux_dirent64 *) (buf + bpos);
                            if (strcmp(d->d_name, ".") != 0 && strcmp(d->d_name, "..") != 0) {
                                std::string fullPath = path;
                                if (fullPath.back() != '/') fullPath += "/";
                                fullPath += d->d_name;

                                bool isDir = (d->d_type == DT_DIR);
                                bool isReg = (d->d_type == DT_REG);

                                if (d->d_type == DT_UNKNOWN) {
                                    struct stat st;
                                    if (stat(fullPath.c_str(), &st) == 0) {
                                        isDir = S_ISDIR(st.st_mode);
                                        isReg = S_ISREG(st.st_mode);
                                    }
                                }

                                if (isDir) {
                                    bool excluded = false;
                                    for (const auto &pat : exclusions)
                                        if (!pat.empty() && fullPath.find(pat) != std::string::npos) { excluded = true; break; }
                                    if (excluded) { bpos += d->d_reclen; continue; }
                                    wq.push(fullPath);
                                } else if (isReg) {
                                    const char* dot = strrchr(d->d_name, '.');
                                    if (dot) {
                                        std::string ext = dot;
                                        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                                        if (m_mediaExtensions.count(ext)) {
                                            struct stat st;
                                            if (stat(fullPath.c_str(), &st) == 0) {
                                                int newCount;
                                                {
                                                    std::lock_guard<std::mutex> lock(pathsMutex);
                                                    foundFiles.append({QString::fromStdString(fullPath), (qint64)st.st_size});
                                                    newCount = foundFiles.size();
                                                }
                                                if (newCount % 50 == 0) {
                                                    emit scanProgress(newCount);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            bpos += d->d_reclen;
                        }
                    }
                    close(fd);
                }
                wq.worker_done();
            }
        });
    }

    for (auto& t : workers) t.join();

    qDebug() << "Scan found" << foundFiles.size() << "candidate files in" << dirsScanned.load() << "directories";

    QStringList finalPaths;
    QMimeDatabase mimeDb;
    QVector<MediaEntry> newEntries;

    auto parseGPS = [](const Exiv2::ExifData &exif,
                       const char *latKey, const char *latRefKey,
                       const char *lonKey, const char *lonRefKey,
                       double &lat, double &lon) {
        auto itLat    = exif.findKey(Exiv2::ExifKey(latKey));
        auto itLatRef = exif.findKey(Exiv2::ExifKey(latRefKey));
        auto itLon    = exif.findKey(Exiv2::ExifKey(lonKey));
        auto itLonRef = exif.findKey(Exiv2::ExifKey(lonRefKey));
        if (itLat == exif.end() || itLon == exif.end()) return false;

        auto toDeg = [](const Exiv2::Value &v) {
            double d = static_cast<double>(v.toRational(0).first) / v.toRational(0).second;
            double m = static_cast<double>(v.toRational(1).first) / v.toRational(1).second;
            double s = static_cast<double>(v.toRational(2).first) / v.toRational(2).second;
            return d + m / 60.0 + s / 3600.0;
        };

        lat = toDeg(itLat->value());
        lon = toDeg(itLon->value());
        if (itLatRef != exif.end() && itLatRef->toString() == "S") lat = -lat;
        if (itLonRef != exif.end() && itLonRef->toString() == "W") lon = -lon;
        return true;
    };

    // Collect entries that need updating; parse EXIF here before the batch write.
    for (const auto& info : foundFiles) {
        finalPaths.append(info.path);
        if (!m_db->needsUpdate(info.path, info.size)) continue;

        QFileInfo fi(info.path);
        MediaEntry entry;
        entry.filePath   = info.path;
        entry.folderPath = fi.absolutePath();
        entry.fileSize   = info.size;
        entry.mimeType   = mimeDb.mimeTypeForFile(fi).name();
        entry.creationDate = fi.lastModified();

        if (entry.mimeType.startsWith("image/")) {
            try {
                auto image = Exiv2::ImageFactory::open(info.path.toStdString());
                image->readMetadata();
                const Exiv2::ExifData &exif = image->exifData();

                for (const char *key : {"Exif.Photo.DateTimeOriginal", "Exif.Image.DateTime"}) {
                    auto it = exif.findKey(Exiv2::ExifKey(key));
                    if (it != exif.end()) {
                        QDateTime dt = QDateTime::fromString(
                            QString::fromStdString(it->toString()), "yyyy:MM:dd HH:mm:ss");
                        if (dt.isValid()) { entry.creationDate = dt; break; }
                    }
                }

                parseGPS(exif,
                         "Exif.GPSInfo.GPSLatitude",    "Exif.GPSInfo.GPSLatitudeRef",
                         "Exif.GPSInfo.GPSLongitude",   "Exif.GPSInfo.GPSLongitudeRef",
                         entry.latitude, entry.longitude);

                auto itW = exif.findKey(Exiv2::ExifKey("Exif.Photo.PixelXDimension"));
                auto itH = exif.findKey(Exiv2::ExifKey("Exif.Photo.PixelYDimension"));
                if (itW != exif.end()) entry.width  = static_cast<int>(itW->value().toInt64());
                if (itH != exif.end()) entry.height = static_cast<int>(itH->value().toInt64());

            } catch (...) {}
        }

        newEntries.append(entry);
    }

    // One transaction for all new/updated rows — crash-safe via WAL.
    if (!newEntries.isEmpty())
        m_db->addOrUpdateMediaBatch(newEntries);

    // Pre-generate thumbnails so the timeline shows them without a placeholder flash.
    if (m_thumbGen && !newEntries.isEmpty()) {
        for (const MediaEntry &e : newEntries) {
            QByteArray bytes = e.mimeType.startsWith("video/")
                ? m_thumbGen->generateVideoThumbnailBytes(e.filePath)
                : m_thumbGen->generateThumbnailBytes(e.filePath);
            if (!bytes.isEmpty())
                m_db->storeThumbnailBlob(e.filePath, 256, ThumbnailGenerator::encrypt(bytes));
        }
    }

    m_db->updateDirectoryStats(QString::fromStdString(rootPath), finalPaths.size());

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end - start;

    emit scanFinished(finalPaths, (int)dirsScanned.load(), diff.count(), QString::fromStdString(rootPath));
}
