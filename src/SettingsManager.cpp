#include "SettingsManager.h"
#include <QGuiApplication>
#include <QClipboard>
#include <QImage>
#include <QDir>
#include <QFileDialog>

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent), m_settings("Kader", "KaderGallery") {
}

int SettingsManager::mosaicDensity() const {
    return m_settings.value("mosaicDensity", 2).toInt();
}
void SettingsManager::setMosaicDensity(int d) {
    if (mosaicDensity() != d) {
        m_settings.setValue("mosaicDensity", d);
        emit mosaicDensityChanged();
    }
}
bool SettingsManager::copyImageToClipboard(const QString &filePath) {
    QImage img(filePath);
    if (img.isNull()) return false;
    QGuiApplication::clipboard()->setImage(img);
    return true;
}

bool SettingsManager::hideIgnoredInTimeline() const {
    return m_settings.value("hideIgnoredInTimeline", true).toBool();
}

void SettingsManager::setHideIgnoredInTimeline(bool hide) {
    if (hideIgnoredInTimeline() != hide) {
        m_settings.setValue("hideIgnoredInTimeline", hide);
        emit hideIgnoredInTimelineChanged();
    }
}
bool SettingsManager::usePulseAudio() const {
    return m_settings.value("usePulseAudio", false).toBool();
}

void SettingsManager::setUsePulseAudio(bool use) {
    if (usePulseAudio() != use) {
        m_settings.setValue("usePulseAudio", use);
        emit usePulseAudioChanged();
    }
}

QString SettingsManager::homePath() const {
    return QDir::homePath();
}

void SettingsManager::openImageFilePicker(const QString &title) {
    QFileDialog *dlg = new QFileDialog(
        nullptr,
        title.isEmpty() ? "Select cover photo" : title
    );
    dlg->setNameFilter("Image files (*.jpg *.jpeg *.png *.webp *.heic *.gif *.bmp *.tiff)");
    dlg->setFileMode(QFileDialog::ExistingFile);
    dlg->setAttribute(Qt::WA_DeleteOnClose);
    connect(dlg, &QFileDialog::fileSelected, this, [this](const QString &file) {
        if (!file.isEmpty()) emit imageFilePicked(file);
    });
    dlg->show();
}
