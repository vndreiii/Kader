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

static bool isVideoFile(const QString &filePath) {
    static const QSet<QString> exts = {".mp4", ".mkv", ".mov", ".avi", ".webm"};
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

// Legacy: generate thumbnail and save as plain .jpg file on disk.
QString ThumbnailGenerator::getOrCreateThumbnail(const QString &filePath, int size) {
    QString hash = generateHash(filePath);
    QString thumbPath = m_cacheDir + "/" + hash + "_" + QString::number(size) + ".jpg";

    if (QFile::exists(thumbPath)) {
        return thumbPath;
    }

    if (isVideoFile(filePath)) {
        QProcess proc;
        proc.start("/usr/bin/ffmpegthumbnailer", {
            "-i", filePath,
            "-o", thumbPath,
            "-s", QString::number(size),
            "-t", "10%",
            "-c", "jpeg"
        });
        if (proc.waitForFinished(10000) && QFile::exists(thumbPath))
            return thumbPath;
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
}

QByteArray ThumbnailGenerator::generateVideoThumbnailBytes(const QString &filePath, int size) {
    QString tmpPath = m_cacheDir + "/_vtmp_" + generateHash(filePath) + ".jpg";
    QProcess proc;
    proc.start("/usr/bin/ffmpegthumbnailer", {
        "-i", filePath,
        "-o", tmpPath,
        "-s", QString::number(size),
        "-t", "10%",
        "-c", "jpeg"
    });
    if (!proc.waitForFinished(10000)) {
        proc.kill();
        qWarning() << "ffmpegthumbnailer timed out for" << filePath;
        return {};
    }
    if (proc.exitCode() != 0) {
        qWarning() << "ffmpegthumbnailer failed for" << filePath << ":" << proc.readAllStandardError();
        return {};
    }
    QFile f(tmpPath);
    if (!f.open(QIODevice::ReadOnly)) return {};
    QByteArray data = f.readAll();
    f.close();
    QFile::remove(tmpPath);
    return data;
}

// Generate thumbnail and return raw JPEG bytes.
QByteArray ThumbnailGenerator::generateThumbnailBytes(const QString &filePath, int size) {
    if (isVideoFile(filePath))
        return generateVideoThumbnailBytes(filePath, size);
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
