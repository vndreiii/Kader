#pragma once

#include <QObject>
#include <QString>
#include <QFuture>
#include <vips/vips8>

class ThumbnailGenerator : public QObject {
    Q_OBJECT
public:
    explicit ThumbnailGenerator(QObject *parent = nullptr);
    
    // Generates a thumbnail for a given file and returns the cache path
    QString getOrCreateThumbnail(const QString &filePath, int size = 256);

private:
    QString m_cacheDir;
    QString generateHash(const QString &filePath);
};
