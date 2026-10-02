#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QFuture>
#include <set>
#include <string>
#include <vector>
#include <atomic>

class DatabaseManager;
class ThumbnailGenerator;

class FileScanner : public QObject {
    Q_OBJECT
    // true while any scan is running — views show loading skeletons instead
    // of an "empty library" message during the first discovery
    Q_PROPERTY(bool scanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(bool stripping READ isStripping NOTIFY strippingChanged)
public:
    explicit FileScanner(DatabaseManager *db, QObject *parent = nullptr);
    ~FileScanner();

    struct ScanResult {
        QStringList mediaPaths;
        size_t directoriesScanned;
        double durationSeconds;
    };

    // Performs a high-performance parallel scan
    Q_INVOKABLE void startScan(const QString &rootPath);

    // Synchronously lists every supported media file in the same directory as
    // `filePath`, sorted case-insensitively by name. Returns a list of maps
    // ({ file_path, mime_type, id:-1, is_favorite:false, is_trashed:false })
    // ready to drop straight into the viewer's allItems model. Cheap enough to
    // call on the UI thread — it's a single directory listing, no recursion.
    Q_INVOKABLE QVariantList listSiblingMedia(const QString &filePath) const;

    void setThumbnailGenerator(ThumbnailGenerator *gen) { m_thumbGen = gen; }

    // Cap the number of directory-traversal worker threads. 0 = auto (all cores).
    void setMaxThreads(int n) { m_maxThreads.store(n > 0 ? n : 0); }

    bool isScanning() const { return m_activeScans > 0; }
    bool isStripping() const { return m_stripping; }

    // Rewrites the library's photos (JPEG, PNG, WebP, TIFF) in place without
    // their location (locationOnly) or without EXIF/IPTC/XMP entirely.
    // Runs in the background; RAW, HEIC and video files are left untouched.
    Q_INVOKABLE void stripMetadata(bool locationOnly);

signals:
    void scanStarted(const QString &rootPath);
    // Carries the file count, not the paths: no consumer ever used the list for
    // anything but its size, and handing a QStringList to a QML handler converts
    // every entry into a JS string on the GUI thread — a whole-library
    // allocation once per scanned directory.
    void scanFinished(int fileCount, int dirsScanned, double duration, const QString &rootPath);
    // Emitted before scanFinished when the scan added, updated or pruned rows.
    void libraryChanged(const QString &rootPath);
    void scanProgress(int filesFound);
    void scanningChanged();
    void strippingChanged();
    void stripProgress(int done, int total);
    void stripFinished(int changed, int failed);

private:
    void runScan(const std::string &rootPath, const std::vector<std::string> &exclusions);

    std::set<std::string> m_mediaExtensions;
    DatabaseManager      *m_db;
    ThumbnailGenerator   *m_thumbGen = nullptr;
    QFuture<void>         m_scanFuture;
    std::atomic<int>      m_maxThreads{0};   // 0 = auto (all cores)
    int                   m_activeScans = 0; // GUI thread only
    bool                  m_stripping = false;
};
