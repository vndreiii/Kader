#include "ThumbnailGenerator.h"
#include <QStandardPaths>
#include <QDir>
#include <QCryptographicHash>
#include <QDebug>
#include <QFile>

ThumbnailGenerator::ThumbnailGenerator(QObject *parent) : QObject(parent) {
    // VIPS_INIT expects the program name
    if (vips_init("Kader")) {
        qCritical() << "Unable to initialize libvips";
    }
    m_cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/thumbnails";
    QDir().mkpath(m_cacheDir);
}

QString ThumbnailGenerator::generateHash(const QString &filePath) {
    return QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
}

QString ThumbnailGenerator::getOrCreateThumbnail(const QString &filePath, int size) {
    QString hash = generateHash(filePath);
    QString thumbPath = m_cacheDir + "/" + hash + "_" + QString::number(size) + ".jpg";

    if (QFile::exists(thumbPath)) {
        return thumbPath;
    }

    try {
        // Simple thumbnail generation
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
