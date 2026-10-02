#include "ThumbnailProvider.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"
#include <QImage>
#include <QUrl>
#include <QDebug>

// Inverse of ThumbnailGenerator::thumbnailUrl(). Qt Quick hands over the URL
// path without its leading '/'; Unix paths get it back, drive paths
// ("C:/…") are complete, and on Windows a remaining leading '/' is a UNC path.
QString ThumbnailProvider::pathFromId(const QString &id) {
    const QString p = QUrl::fromPercentEncoding(id.toUtf8());
#ifdef Q_OS_WIN
    if (p.size() >= 2 && p.at(1) == QLatin1Char(':'))
        return p;
#endif
    return QLatin1Char('/') + p;
}

ThumbnailProvider::ThumbnailProvider(DatabaseManager *db, ThumbnailGenerator *gen)
    : QQuickImageProvider(QQuickImageProvider::Image,
                          QQuickImageProvider::ForceAsynchronousImageLoading)
    , m_db(db)
    , m_gen(gen)
{}

QImage ThumbnailProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    Q_UNUSED(requestedSize)
    const QString filePath = pathFromId(id);

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
