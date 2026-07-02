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

signals:
    void scanStarted(const QString &rootPath);
    void scanFinished(const QStringList &paths, int dirsScanned, double duration, const QString &rootPath);
    void scanProgress(int filesFound);

private:
    void runScan(const std::string &rootPath, const std::vector<std::string> &exclusions);

    std::set<std::string> m_mediaExtensions;
    DatabaseManager      *m_db;
    ThumbnailGenerator   *m_thumbGen = nullptr;
    QFuture<void>         m_scanFuture;
    std::atomic<int>      m_maxThreads{0};   // 0 = auto (all cores)
};
