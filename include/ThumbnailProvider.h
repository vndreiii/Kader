#pragma once

#include <QQuickImageProvider>

class DatabaseManager;
class ThumbnailGenerator;

class ThumbnailProvider : public QQuickImageProvider {
public:
    explicit ThumbnailProvider(DatabaseManager *db, ThumbnailGenerator *gen);

    // Called by Qt Quick when an Image source is "image://thumbnails/<file_path>"
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    DatabaseManager *m_db;
    ThumbnailGenerator *m_gen;
    static constexpr int kThumbSize = 512;
};
