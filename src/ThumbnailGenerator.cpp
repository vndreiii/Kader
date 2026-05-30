#include "ThumbnailGenerator.h"
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QCryptographicHash>
#include <QBuffer>
#include <QProcess>
#include <QDebug>
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

ThumbnailGenerator::ThumbnailGenerator(QObject *parent) : QObject(parent) {
    if (vips_init("Kader")) {
        qCritical() << "Unable to initialize libvips";
    }
    m_cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/thumbnails";
    QDir().mkpath(m_cacheDir);
}

QString ThumbnailGenerator::generateHash(const QString &filePath) {
    return QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
}

QString ThumbnailGenerator::thumbnailUrl(const QString &filePath) {
    // filePath is absolute (starts with /). Qt Quick strips one leading / from the
    // URL path when passing id to requestImage, so do NOT add an extra slash here.
    // requestImage restores the leading / to reconstruct the absolute path.
    return "image://thumbnails" + filePath;
}

void ThumbnailGenerator::setParallelMode(bool enabled) {
    m_parallelMode.store(enabled);
    // When parallel: limit each vips task to 1 thread so multiple concurrent
    // calls don't create a thread explosion (N tasks × M vips threads).
    // When legacy: restore auto mode so the single serialized task uses all cores.
    vips_concurrency_set(enabled ? 1 : 0);
    qDebug() << "ThumbnailGenerator: parallel mode" << (enabled ? "ON" : "OFF");
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
            if (QProcess::execute("/usr/bin/ffmpegthumbnailer", {
                    "-i", filePath, "-o", thumbPath,
                    "-s", QString::number(size), "-t", "10%", "-c", "jpeg"
                }) == 0 && QFile::exists(thumbPath) && QFile(thumbPath).size() > 0)
                return thumbPath;
            QFile::remove(thumbPath);

            if (QProcess::execute("/usr/bin/ffmpeg", {
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
            return "";
        }

        try {
            vips::VImage thumb = vips::VImage::thumbnail(filePath.toLocal8Bit().constData(), size);
            thumb.write_to_file(thumbPath.toLocal8Bit().constData());
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
    if (QProcess::execute("/usr/bin/ffmpegthumbnailer", {
            "-i", filePath, "-o", tmpPath,
            "-s", QString::number(size), "-t", "10%", "-c", "jpeg"
        }) == 0) {
        auto data = readAndRemove(tmpPath);
        if (!data.isEmpty()) return data;
    }
    QFile::remove(tmpPath);

    // Fallback: ffmpeg
    if (QProcess::execute("/usr/bin/ffmpeg", {
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
    // One LibRaw instance per call — not thread-safe to share across threads.
    LibRaw raw;
    raw.set_progress_handler(nullptr, nullptr);

    if (raw.open_file(filePath.toLocal8Bit().constData()) != LIBRAW_SUCCESS) {
        qWarning() << "LibRaw: cannot open" << filePath;
        return {};
    }

    // Primary path: extract embedded JPEG thumbnail (fast, avoids full decode).
    if (raw.unpack_thumb() == LIBRAW_SUCCESS) {
        int ret = 0;
        libraw_processed_image_t *thumb = raw.dcraw_make_mem_thumb(&ret);
        if (thumb && ret == LIBRAW_SUCCESS) {
            QByteArray result;
            try {
                if (thumb->type == LIBRAW_IMAGE_JPEG) {
                    // Pass JPEG bytes directly to vips — libjpeg-turbo shrink-on-load.
                    vips::VImage img = vips::VImage::thumbnail_buffer(
                        thumb->data, thumb->data_size, size,
                        vips::VImage::option()->set("height", size));
                    void *buf = nullptr; size_t len = 0;
                    img.write_to_buffer(".jpg", &buf, &len);
                    result = QByteArray(static_cast<const char *>(buf), static_cast<int>(len));
                    g_free(buf);
                } else {
                    // Bitmap thumbnail — wrap as raw pixels and resize.
                    vips::VImage img = vips::VImage::new_from_memory(
                        thumb->data, thumb->data_size,
                        thumb->width, thumb->height, thumb->colors, VIPS_FORMAT_UCHAR);
                    vips::VImage resized = img.thumbnail_image(size,
                        vips::VImage::option()->set("height", size));
                    void *buf = nullptr; size_t len = 0;
                    resized.write_to_buffer(".jpg", &buf, &len);
                    result = QByteArray(static_cast<const char *>(buf), static_cast<int>(len));
                    g_free(buf);
                }
            } catch (vips::VError &e) {
                qWarning() << "LibRaw+vips resize error for" << filePath << ":" << e.what();
            }
            LibRaw::dcraw_clear_mem(thumb);
            if (!result.isEmpty()) return result;
        }
    }

    // Fallback: half-size decode (fast; avoids full demosaic).
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
        vips::VImage vimg = vips::VImage::new_from_memory(
            img->data, img->data_size,
            img->width, img->height, img->colors,
            img->bits == 16 ? VIPS_FORMAT_USHORT : VIPS_FORMAT_UCHAR);
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
    if (isRawFile(filePath))
        return generateRawThumbnailBytes(filePath, size);
    try {
        vips::VImage thumb = vips::VImage::thumbnail(filePath.toLocal8Bit().constData(), size);
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

// Derive a 32-byte AES key from the machine ID + a fixed app salt.
QByteArray ThumbnailGenerator::deriveKey() {
    QByteArray machineId;
    QFile f("/etc/machine-id");
    if (f.open(QIODevice::ReadOnly)) {
        machineId = f.readAll().trimmed();
        f.close();
    } else {
        machineId = "kader-fallback-id";
    }
    QByteArray material = machineId + "KaderGallery-thumb-v1";
    return QCryptographicHash::hash(material, QCryptographicHash::Sha256);
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
