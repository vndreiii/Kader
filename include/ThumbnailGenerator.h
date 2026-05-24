#pragma once

#include <QObject>
#include <QImage>
#include <QString>
#include <QByteArray>
#include <QMutex>
#include <vips/vips8>

class ThumbnailGenerator : public QObject {
    Q_OBJECT
public:
    explicit ThumbnailGenerator(QObject *parent = nullptr);

    // Legacy file-based path (used by AlbumModel CoverRole synchronously).
    Q_INVOKABLE QString getOrCreateThumbnail(const QString &filePath, int size = 256);

    // Generate thumbnail as raw JPEG bytes (not encrypted).
    QByteArray generateThumbnailBytes(const QString &filePath, int size = 256);

    // Generate thumbnail from a RAW camera file using LibRaw.
    QByteArray generateRawThumbnailBytes(const QString &filePath, int size = 256);

    // Generate video thumbnail via ffmpegthumbnailer.
    QByteArray generateVideoThumbnailBytes(const QString &filePath, int size = 256);

    static bool isRawFile(const QString &filePath);

    // Encrypt / decrypt using AES-256-CBC with a machine-derived key.
    static QByteArray encrypt(const QByteArray &plaintext);
    static QByteArray decrypt(const QByteArray &ciphertext);

    // Returns the URL to pass as an Image source in QML: "image://thumbnails/<path>"
    static QString thumbnailUrl(const QString &filePath);

private:
    static QByteArray deriveKey();
    QString generateHash(const QString &filePath);
    QString m_cacheDir;
    QMutex m_genMutex;  // serializes vips/ffmpeg calls across threads
};
