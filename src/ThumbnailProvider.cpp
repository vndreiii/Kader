#include "ThumbnailProvider.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <QImage>
#include <QBuffer>
#include <QDebug>

ThumbnailProvider::ThumbnailProvider(DatabaseManager *db, ThumbnailGenerator *gen)
    : QQuickImageProvider(QQuickImageProvider::Image)
    , m_db(db)
    , m_gen(gen)
{}

QImage ThumbnailProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    // id is the file path (everything after "image://thumbnails/")
    const QString filePath = id;
    const int thumbSize = (requestedSize.width() > 0 && requestedSize.width() <= 512)
                              ? requestedSize.width()
                              : kThumbSize;

    // Try to load encrypted blob from DB.
    QByteArray encBlob = m_db->getThumbnailBlob(filePath, thumbSize);

    QByteArray jpegBytes;
    if (!encBlob.isEmpty()) {
        jpegBytes = ThumbnailGenerator::decrypt(encBlob);
    }

    if (jpegBytes.isEmpty()) {
        // Generate, encrypt, and store.
        jpegBytes = m_gen->generateThumbnailBytes(filePath, thumbSize);
        if (!jpegBytes.isEmpty()) {
            QByteArray encrypted = ThumbnailGenerator::encrypt(jpegBytes);
            if (!encrypted.isEmpty()) {
                m_db->storeThumbnailBlob(filePath, thumbSize, encrypted);
            }
        }
    }

    if (jpegBytes.isEmpty()) {
        // libvips failed — fall back to Qt's own loader
        QImage fallback(filePath);
        if (!fallback.isNull()) {
            fallback = fallback.scaled(thumbSize, thumbSize,
                                       Qt::KeepAspectRatioByExpanding,
                                       Qt::SmoothTransformation);
            QBuffer buf;
            buf.open(QIODevice::WriteOnly);
            fallback.save(&buf, "JPEG", 80);
            jpegBytes = buf.data();
            if (!jpegBytes.isEmpty()) {
                QByteArray enc = ThumbnailGenerator::encrypt(jpegBytes);
                if (!enc.isEmpty())
                    m_db->storeThumbnailBlob(filePath, thumbSize, enc);
            }
        }
    }

    if (jpegBytes.isEmpty()) {
        qWarning() << "ThumbnailProvider: no thumbnail for" << filePath;
        return {};
    }

    QImage img;
    img.loadFromData(jpegBytes, "JPEG");

    if (size) {
        *size = img.size();
    }
    return img;
}
