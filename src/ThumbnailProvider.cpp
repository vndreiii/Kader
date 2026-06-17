#include "ThumbnailProvider.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <QImage>
#include <QDebug>

ThumbnailProvider::ThumbnailProvider(DatabaseManager *db, ThumbnailGenerator *gen)
    : QQuickImageProvider(QQuickImageProvider::Image,
                          QQuickImageProvider::ForceAsynchronousImageLoading)
    , m_db(db)
    , m_gen(gen)
{}

QImage ThumbnailProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    Q_UNUSED(requestedSize)
    // Qt Quick strips one leading '/' from the URL path; restore it for absolute paths.
    const QString filePath = id.startsWith('/') ? id : '/' + id;

    // Use the disk-based thumbnail cache — same path as AlbumModel covers, proven to work.
    // getOrCreateThumbnail is thread-safe via libvips and writes to ~/.cache/Kader/thumbnails/.
    QString thumbPath = m_gen->getOrCreateThumbnail(filePath, kThumbSize);
    if (!thumbPath.isEmpty()) {
        QImage img(thumbPath);
        if (!img.isNull()) {
            if (size) *size = img.size();
            return img;
        }
    }

    // Fallback: Qt's own image loader (handles formats libvips doesn't)
    QImage fallback(filePath);
    if (!fallback.isNull()) {
        fallback = fallback.scaled(kThumbSize, kThumbSize,
                                   Qt::KeepAspectRatioByExpanding,
                                   Qt::SmoothTransformation);
        if (size) *size = fallback.size();
        return fallback;
    }

    return {};
}
