#include "ThumbnailGenerator.h"
#include "AppPaths.h"
#include <QUrl>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QBuffer>
#include <QProcess>
#include <QDebug>
#include <QtConcurrent>
#include <QThreadPool>
#include <QHash>
#include <QMutex>
#include <algorithm>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <libraw/libraw.h>

static bool isVideoFile(const QString &filePath) {
    static const QSet<QString> exts = {".mp4", ".mkv", ".mov", ".avi", ".webm"};
    int dot = filePath.lastIndexOf('.');
    return dot >= 0 && exts.contains(filePath.mid(dot).toLower());
}

bool ThumbnailGenerator::isRawFile(const QString &filePath) {
    static const QSet<QString> exts = {
        ".nef", ".cr2", ".cr3", ".arw", ".dng", ".raf", ".orf",
        ".rw2", ".pef", ".srw", ".3fr", ".raw", ".rw1", ".mrw",
        ".x3f", ".dcr"
    };
    int dot = filePath.lastIndexOf('.');
    return dot >= 0 && exts.contains(filePath.mid(dot).toLower());
}

static constexpr int AES_IV_SIZE = 16;

// External tool: bundled next to the executable, else PATH; empty when missing.
static QString tool(const char *name) {
    return AppPaths::tool(QString::fromLatin1(name));
}

ThumbnailGenerator::ThumbnailGenerator(QObject *parent) : QObject(parent) {
    if (vips_init("Kader")) {
        qCritical() << "Unable to initialize libvips";
    }
    m_cacheDir = AppPaths::cacheDir() + "/thumbnails";
    QDir().mkpath(m_cacheDir);
}

QString ThumbnailGenerator::generateHash(const QString &filePath) {
    return QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
}

QString ThumbnailGenerator::thumbnailUrl(const QString &filePath) {
    // image://thumbnails/<path without its leading '/'>, percent-encoded so
    // '#', '?' and '%' in file names survive. Works for "/home/…" and
    // "C:/Users/…" alike; ThumbnailProvider::pathFromId() reverses it.
    const QStringView rel = filePath.startsWith(QLatin1Char('/')) ? QStringView(filePath).mid(1)
                                                                  : QStringView(filePath);
    return QStringLiteral("image://thumbnails/")
         + QString::fromLatin1(QUrl::toPercentEncoding(rel.toString(), QByteArrayLiteral("/:")));
}

void ThumbnailGenerator::setParallelMode(bool enabled) {
    m_parallelMode.store(enabled);
    applyVipsConcurrency();
    qDebug() << "ThumbnailGenerator: parallel mode" << (enabled ? "ON" : "OFF");
}

void ThumbnailGenerator::applyVipsConcurrency() {
    // Keep total CPU usage bounded by the worker budget regardless of mode:
    //   parallel  → many tasks, each pinned to 1 libvips thread
    //               (the global thread pool caps how many run at once)
    //   legacy    → one serialized task at a time, allowed to use the full
    //               budget of libvips threads
    const int budget = std::max(1, m_budgetThreads.load());
    vips_concurrency_set(m_parallelMode.load() ? 1 : budget);
}

void ThumbnailGenerator::setResourceBudget(int threads) {
    threads = std::max(1, threads);
    m_budgetThreads.store(threads);

    // The global pool serves both QtConcurrent cache building and the async
    // image provider's on-demand requests; capping it bounds how many
    // thumbnails decode in parallel (CPU) and how many large buffers live at
    // once (RAM).
    QThreadPool::globalInstance()->setMaxThreadCount(threads);

    // Bound the libvips operation cache. It scales with the budget but stays
    // modest so a big library can't balloon resident memory.
    vips_cache_set_max(std::min(64, threads * 8));            // cached operations
    vips_cache_set_max_mem(static_cast<size_t>(threads) * 24 * 1024 * 1024);  // ~24 MB/worker
    vips_cache_set_max_files(std::min(64, threads * 8));

    applyVipsConcurrency();
    qDebug() << "ThumbnailGenerator: resource budget" << threads << "worker threads";
}

// Legacy: generate thumbnail and save as plain .jpg file on disk.
QString ThumbnailGenerator::getOrCreateThumbnail(const QString &filePath, int size) {
    QString hash = generateHash(filePath);
    QString thumbPath = m_cacheDir + "/" + hash + "_" + QString::number(size) + ".jpg";

    // Fast path: thumbnail already on disk — no lock needed either way.
    if (QFile::exists(thumbPath)) {
        if (QFile(thumbPath).size() > 0)
            return thumbPath;
        QFile::remove(thumbPath);
    }

    // Core generation logic, invoked either locked (legacy) or directly (parallel).
    auto generate = [&]() -> QString {
        // Double-check: another thread may have finished while we were waiting.
        if (QFile::exists(thumbPath)) {
            if (QFile(thumbPath).size() > 0) return thumbPath;
            QFile::remove(thumbPath);
        }

        if (isVideoFile(filePath)) {
            if (QProcess::execute(tool("ffmpegthumbnailer"), {
                    "-i", filePath, "-o", thumbPath,
                    "-s", QString::number(size), "-t", "10%", "-c", "jpeg"
                }) == 0 && QFile::exists(thumbPath) && QFile(thumbPath).size() > 0)
                return thumbPath;
            QFile::remove(thumbPath);

            if (QProcess::execute(tool("ffmpeg"), {
                    "-y", "-hide_banner", "-loglevel", "error",
                    "-i", filePath, "-ss", "00:00:02", "-frames:v", "1",
                    "-vf", QString("scale=%1:-1").arg(size), "-q:v", "2", thumbPath
                }) == 0 && QFile::exists(thumbPath) && QFile(thumbPath).size() > 0)
                return thumbPath;
            QFile::remove(thumbPath);
            return "";
        }

        if (isRawFile(filePath)) {
            QByteArray bytes = generateRawThumbnailBytes(filePath, size);
            if (!bytes.isEmpty()) {
                QFile f(thumbPath);
                if (f.open(QIODevice::WriteOnly)) { f.write(bytes); f.close(); return thumbPath; }
            }
            // LibRaw failed — fall through to libvips native RAW loader
        }

        try {
            vips::VImage thumb = vips::VImage::thumbnail(QFile::encodeName(filePath).constData(), size);
            thumb.write_to_file(QFile::encodeName(thumbPath).constData());
            return thumbPath;
        } catch (vips::VError &e) {
            qWarning() << "libvips error for" << filePath << ":" << e.what();
        } catch (...) {
            qWarning() << "Unknown error generating thumbnail for" << filePath;
        }
        return "";
    };

    if (m_parallelMode.load()) {
        // Parallel mode: libvips is thread-safe with concurrency=1 per task.
        // Multiple threads can generate different thumbnails concurrently.
        return generate();
    } else {
        // Legacy mode: serialize all vips/ffmpeg calls to prevent heap issues
        // from concurrent glib/libc allocators.
        QMutexLocker lock(&m_genMutex);
        return generate();
    }
}

static QByteArray readAndRemove(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) { QFile::remove(path); return {}; }
    QByteArray data = f.readAll();
    f.close();
    QFile::remove(path);
    return data.size() > 0 ? data : QByteArray{};
}

QByteArray ThumbnailGenerator::generateVideoThumbnailBytes(const QString &filePath, int size) {
    QString tmpPath = m_cacheDir + "/_vtmp_" + generateHash(filePath) + ".jpg";

    // Try ffmpegthumbnailer first (QProcess::execute is thread-safe / blocking)
    if (QProcess::execute(tool("ffmpegthumbnailer"), {
            "-i", filePath, "-o", tmpPath,
            "-s", QString::number(size), "-t", "10%", "-c", "jpeg"
        }) == 0) {
        auto data = readAndRemove(tmpPath);
        if (!data.isEmpty()) return data;
    }
    QFile::remove(tmpPath);

    // Fallback: ffmpeg
    if (QProcess::execute(tool("ffmpeg"), {
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", filePath, "-ss", "00:00:02", "-frames:v", "1",
            "-vf", QString("scale=%1:-1").arg(size), "-q:v", "2", tmpPath
        }) == 0) {
        auto data = readAndRemove(tmpPath);
        if (!data.isEmpty()) return data;
    }
    QFile::remove(tmpPath);
    qWarning() << "All video thumbnail methods failed for" << filePath;
    return {};
}

QByteArray ThumbnailGenerator::generateRawThumbnailBytes(const QString &filePath, int size) {
    LibRaw raw;
    raw.set_progress_handler(nullptr, nullptr);

    if (raw.open_file(QFile::encodeName(filePath).constData()) != LIBRAW_SUCCESS) {
        qWarning() << "LibRaw: cannot open" << filePath;
        return {};
    }

    // Primary: extract embedded JPEG thumbnail (fast, avoids full decode).
    if (raw.unpack_thumb() == LIBRAW_SUCCESS) {
        int ret = 0;
        libraw_processed_image_t *thumb = raw.dcraw_make_mem_thumb(&ret);
        if (thumb && ret == LIBRAW_SUCCESS) {
            QByteArray result;
            try {
                if (thumb->type == LIBRAW_IMAGE_JPEG) {
                    // VipsBlob overload: the (data, size) one needs libvips 8.13+
                    // and the AppImage builds against 8.12. The blob borrows
                    // thumb->data, which outlives the call.
                    VipsBlob *blob = vips_blob_new(nullptr, thumb->data, thumb->data_size);
                    vips::VImage img = vips::VImage::thumbnail_buffer(
                        blob, size, vips::VImage::option()->set("height", size));
                    vips_area_unref(VIPS_AREA(blob));
                    void *buf = nullptr; size_t len = 0;
                    img.write_to_buffer(".jpg", &buf, &len);
                    result = QByteArray(static_cast<const char *>(buf), static_cast<int>(len));
                    g_free(buf);
                } else {
                    VipsBandFormat fmt = (thumb->bits == 16) ? VIPS_FORMAT_USHORT : VIPS_FORMAT_UCHAR;
                    vips::VImage img = vips::VImage::new_from_memory(
                        thumb->data, thumb->data_size,
                        thumb->width, thumb->height, thumb->colors, fmt);
                    img = img.copy(vips::VImage::option()
                        ->set("interpretation", static_cast<int>(VIPS_INTERPRETATION_sRGB)));
                    vips::VImage resized = img.thumbnail_image(size,
                        vips::VImage::option()->set("height", size));
                    void *buf = nullptr; size_t len = 0;
                    resized.write_to_buffer(".jpg", &buf, &len);
                    result = QByteArray(static_cast<const char *>(buf), static_cast<int>(len));
                    g_free(buf);
                }
            } catch (vips::VError &e) {
                qWarning() << "LibRaw+vips thumb error for" << filePath << ":" << e.what();
            }
            LibRaw::dcraw_clear_mem(thumb);
            if (!result.isEmpty()) return result;
        }
    }

    // Fallback: half-size decode. unpack() is required before dcraw_process().
    if (raw.unpack() != LIBRAW_SUCCESS) {
        qWarning() << "LibRaw: unpack failed for" << filePath;
        return {};
    }
    raw.imgdata.params.half_size      = 1;
    raw.imgdata.params.use_camera_wb  = 1;
    raw.imgdata.params.no_auto_bright = 1;
    raw.imgdata.params.output_color   = 1; // sRGB
    if (raw.dcraw_process() != LIBRAW_SUCCESS) {
        qWarning() << "LibRaw: dcraw_process failed for" << filePath;
        return {};
    }
    int ret = 0;
    libraw_processed_image_t *img = raw.dcraw_make_mem_image(&ret);
    if (!img || ret != LIBRAW_SUCCESS) return {};

    QByteArray result;
    try {
        VipsBandFormat fmt = (img->bits == 16) ? VIPS_FORMAT_USHORT : VIPS_FORMAT_UCHAR;
        vips::VImage vimg = vips::VImage::new_from_memory(
            img->data, img->data_size,
            img->width, img->height, img->colors, fmt);
        vimg = vimg.copy(vips::VImage::option()
            ->set("interpretation", static_cast<int>(VIPS_INTERPRETATION_sRGB)));
        vips::VImage resized = vimg.thumbnail_image(size,
            vips::VImage::option()->set("height", size));
        void *buf = nullptr; size_t len = 0;
        resized.write_to_buffer(".jpg", &buf, &len);
        result = QByteArray(static_cast<const char *>(buf), static_cast<int>(len));
        g_free(buf);
    } catch (vips::VError &e) {
        qWarning() << "LibRaw fallback vips error for" << filePath << ":" << e.what();
    }
    LibRaw::dcraw_clear_mem(img);
    return result;
}

// Generate thumbnail and return raw JPEG bytes.
QByteArray ThumbnailGenerator::generateThumbnailBytes(const QString &filePath, int size) {
    if (isVideoFile(filePath))
        return generateVideoThumbnailBytes(filePath, size);
    if (isRawFile(filePath)) {
        QByteArray bytes = generateRawThumbnailBytes(filePath, size);
        if (!bytes.isEmpty()) return bytes;
        // LibRaw failed — fall through to libvips native RAW loader
    }
    try {
        vips::VImage thumb = vips::VImage::thumbnail(QFile::encodeName(filePath).constData(), size);
        void *buf = nullptr;
        size_t len = 0;
        thumb.write_to_buffer(".jpg", &buf, &len);
        QByteArray result(static_cast<const char *>(buf), static_cast<int>(len));
        g_free(buf);
        return result;
    } catch (vips::VError &e) {
        qWarning() << "libvips error for" << filePath << ":" << e.what();
    } catch (...) {
        qWarning() << "Unknown thumbnail error for" << filePath;
    }
    return {};
}

void ThumbnailGenerator::startCacheBuilding(const QStringList &paths, int size) {
    // Supersede any run already in flight. We deliberately never wait for it
    // here: this is called from the GUI thread (the startup timer, and again
    // after every scan finishes) and the item in flight can be a multi-second
    // RAW decode or an ffmpegthumbnailer subprocess. The old worker sees the
    // bumped generation and drops out by itself; a brief overlap costs nothing
    // because thumbnail generation is idempotent and disk-cache guarded.
    const quint64 generation = m_cacheGeneration.fetch_add(1) + 1;

    m_thumbCaching.store(true);
    m_thumbCacheDone.store(0);
    m_thumbCacheTotal.store(0);
    QMetaObject::invokeMethod(this, "thumbCachingChanged",       Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "thumbCacheProgressChanged", Qt::QueuedConnection);

    QFuture<void> future = QtConcurrent::run([this, paths, size, generation]() {
        // Deciding which paths still need a thumbnail is one stat() per file.
        // Over a large library that is tens of thousands of syscalls, competing
        // with a running scan for the disk — it belongs here, not on the caller.
        QStringList uncached;
        uncached.reserve(paths.size());
        for (const QString &p : paths) {
            if (m_cacheGeneration.load() != generation) return;
            const QFileInfo tp(m_cacheDir + "/" + generateHash(p) + "_" + QString::number(size) + ".jpg");
            if (!tp.exists() || tp.size() == 0)
                uncached << p;
        }

        m_thumbCacheTotal.store(uncached.size());
        QMetaObject::invokeMethod(this, "thumbCacheProgressChanged", Qt::QueuedConnection);

        for (const QString &p : uncached) {
            if (m_cacheGeneration.load() != generation) return;
            getOrCreateThumbnail(p, size);
            const int done = m_thumbCacheDone.fetch_add(1) + 1;
            if (done % 10 == 0 || done == m_thumbCacheTotal.load())
                QMetaObject::invokeMethod(this, "thumbCacheProgressChanged", Qt::QueuedConnection);
        }

        // Only the newest run owns the "finished" transition.
        if (m_cacheGeneration.load() != generation) return;
        m_thumbCaching.store(false);
        QMetaObject::invokeMethod(this, "thumbCachingChanged",  Qt::QueuedConnection);
        QMetaObject::invokeMethod(this, "thumbCacheFinished",   Qt::QueuedConnection);
    });

    QMutexLocker lock(&m_cacheFutureMutex);
    m_cacheFuture = future;
}

void ThumbnailGenerator::cancelCacheBuilding() {
    // Same contract as above: signal, never wait.
    m_cacheGeneration.fetch_add(1);
    if (m_thumbCaching.exchange(false))
        QMetaObject::invokeMethod(this, "thumbCachingChanged", Qt::QueuedConnection);
}

// Derive a 32-byte AES key from the machine ID + a fixed app salt. Computed
// once: it used to re-read /etc/machine-id and re-hash it for every thumbnail.
QByteArray ThumbnailGenerator::deriveKey() {
    static const QByteArray key = [] {
        QByteArray machineId;
        QFile f(QStringLiteral("/etc/machine-id"));
        if (f.open(QIODevice::ReadOnly))
            machineId = f.readAll().trimmed();
        else
            machineId = "kader-fallback-id";
        return QCryptographicHash::hash(machineId + "KaderGallery-thumb-v1", QCryptographicHash::Sha256);
    }();
    return key;
}

QByteArray ThumbnailGenerator::encrypt(const QByteArray &plaintext) {
    QByteArray key = deriveKey();

    QByteArray iv(AES_IV_SIZE, 0);
    if (RAND_bytes(reinterpret_cast<unsigned char *>(iv.data()), AES_IV_SIZE) != 1) {
        qWarning() << "RAND_bytes failed";
        return {};
    }

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return {};

    EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), nullptr,
                       reinterpret_cast<const unsigned char *>(key.constData()),
                       reinterpret_cast<const unsigned char *>(iv.constData()));

    QByteArray ciphertext(plaintext.size() + EVP_MAX_BLOCK_LENGTH, '\0');
    int outLen1 = 0, outLen2 = 0;
    EVP_EncryptUpdate(ctx,
                      reinterpret_cast<unsigned char *>(ciphertext.data()), &outLen1,
                      reinterpret_cast<const unsigned char *>(plaintext.constData()), plaintext.size());
    EVP_EncryptFinal_ex(ctx,
                        reinterpret_cast<unsigned char *>(ciphertext.data()) + outLen1, &outLen2);
    EVP_CIPHER_CTX_free(ctx);

    ciphertext.resize(outLen1 + outLen2);
    return iv + ciphertext;
}

QByteArray ThumbnailGenerator::decrypt(const QByteArray &ciphertext) {
    if (ciphertext.size() <= AES_IV_SIZE) return {};
    QByteArray key = deriveKey();

    QByteArray iv = ciphertext.left(AES_IV_SIZE);
    QByteArray actual = ciphertext.mid(AES_IV_SIZE);

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return {};

    EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), nullptr,
                       reinterpret_cast<const unsigned char *>(key.constData()),
                       reinterpret_cast<const unsigned char *>(iv.constData()));

    QByteArray plaintext(actual.size() + EVP_MAX_BLOCK_LENGTH, '\0');
    int outLen1 = 0, outLen2 = 0;
    EVP_DecryptUpdate(ctx,
                      reinterpret_cast<unsigned char *>(plaintext.data()), &outLen1,
                      reinterpret_cast<const unsigned char *>(actual.constData()), actual.size());
    int finalRet = EVP_DecryptFinal_ex(ctx,
                      reinterpret_cast<unsigned char *>(plaintext.data()) + outLen1, &outLen2);
    EVP_CIPHER_CTX_free(ctx);

    if (finalRet != 1) {
        qWarning() << "AES decryption failed (wrong key or corrupted data)";
        return {};
    }
    plaintext.resize(outLen1 + outLen2);
    return plaintext;
}
