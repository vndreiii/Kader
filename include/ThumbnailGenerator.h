#pragma once

#include <QObject>
#include <QImage>
#include <QString>
#include <QByteArray>
#include <QMutex>
#include <QFuture>
#include <atomic>
#include <vips/vips8>

class ThumbnailGenerator : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool   thumbCaching     READ thumbCaching     NOTIFY thumbCachingChanged)
    Q_PROPERTY(int    thumbCacheDone   READ thumbCacheDone   NOTIFY thumbCacheProgressChanged)
    Q_PROPERTY(int    thumbCacheTotal  READ thumbCacheTotal  NOTIFY thumbCacheProgressChanged)

public:
    explicit ThumbnailGenerator(QObject *parent = nullptr);

    // Enable/disable parallel generation (set before scanning).
    // When enabled: vips_concurrency_set(1) per task, global mutex dropped.
    void setParallelMode(bool enabled);
    bool parallelMode() const { return m_parallelMode.load(); }

    // Apply a resource budget (worker-thread count). Caps the global thread pool
    // that serves on-demand thumbnails and cache building, sizes libvips per-op
    // concurrency, and bounds the libvips operation cache so RAM stays in check.
    void setResourceBudget(int threads);

    // Legacy file-based path (used by AlbumModel CoverRole synchronously).
    Q_INVOKABLE QString getOrCreateThumbnail(const QString &filePath, int size = 256);

    // Generate thumbnail as raw JPEG bytes (not encrypted).
    QByteArray generateThumbnailBytes(const QString &filePath, int size = 256);

    // Generate thumbnail from a RAW camera file using LibRaw.
    QByteArray generateRawThumbnailBytes(const QString &filePath, int size = 256);

    // Generate video thumbnail via ffmpegthumbnailer.
    QByteArray generateVideoThumbnailBytes(const QString &filePath, int size = 256);

    // Pre-generate disk-cached thumbnails for all paths at the given size.
    // Skips files that already have a cached thumbnail. Shows progress via signals.
    Q_INVOKABLE void startCacheBuilding(const QStringList &paths, int size = 768);
    Q_INVOKABLE void cancelCacheBuilding();

    bool thumbCaching()    const { return m_thumbCaching.load(); }
    int  thumbCacheDone()  const { return m_thumbCacheDone.load(); }
    int  thumbCacheTotal() const { return m_thumbCacheTotal.load(); }

    static bool isRawFile(const QString &filePath);

    // Encrypt / decrypt using AES-256-CBC with a machine-derived key.
    static QByteArray encrypt(const QByteArray &plaintext);
    static QByteArray decrypt(const QByteArray &ciphertext);

    // Returns the URL to pass as an Image source in QML: "image://thumbnails/<path>"
    static QString thumbnailUrl(const QString &filePath);

signals:
    void thumbCachingChanged();
    void thumbCacheProgressChanged();
    void thumbCacheFinished();

private:
    static QByteArray deriveKey();
    QString generateHash(const QString &filePath);
    void applyVipsConcurrency();   // sets vips_concurrency from mode + budget
    QString m_cacheDir;
    QMutex m_genMutex;         // serializes vips/ffmpeg calls in legacy mode
    std::atomic<bool> m_parallelMode{false};
    std::atomic<int>  m_budgetThreads{1};  // worker-thread budget (see setResourceBudget)

    std::atomic<bool> m_thumbCaching{false};
    // Bumped on every startCacheBuilding()/cancelCacheBuilding(). A running
    // cache worker compares it against the generation it was started with and
    // bails out as soon as it sees a newer one — this replaces waiting on the
    // previous QFuture, which used to block whichever thread asked for a new
    // cache build (the GUI thread, on startup and after every scan).
    std::atomic<quint64> m_cacheGeneration{0};
    std::atomic<int>  m_thumbCacheDone{0};
    std::atomic<int>  m_thumbCacheTotal{0};
    QMutex            m_cacheFutureMutex;  // guards m_cacheFuture (assigned off-thread)
    QFuture<void>     m_cacheFuture;
};
