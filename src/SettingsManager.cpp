#include "SettingsManager.h"
#include <QThread>
#include <algorithm>
#include <cmath>
#include <QGuiApplication>
#include <QClipboard>
#include <QImage>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QLocale>
#include <QStandardPaths>
#include <QUrl>
#include <QFileInfo>
#include <QDesktopServices>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>

static QString settingsFilePath() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/kader";
    QDir().mkpath(dir);
    return dir + "/settings.json";
}

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent), m_path(settingsFilePath()) {
    load();
}

void SettingsManager::load() {
    QFile f(m_path);
    if (f.open(QIODevice::ReadOnly)) {
        auto doc = QJsonDocument::fromJson(f.readAll());
        if (doc.isObject())
            m_data = doc.object();
    }
}

void SettingsManager::save() const {
    QFile f(m_path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(m_data).toJson());
}

bool SettingsManager::hideIgnoredInTimeline() const {
    return m_data.value("hideIgnoredInTimeline").toBool(true);
}
void SettingsManager::setHideIgnoredInTimeline(bool hide) {
    if (hideIgnoredInTimeline() != hide) {
        m_data["hideIgnoredInTimeline"] = hide;
        save();
        emit hideIgnoredInTimelineChanged();
    }
}

bool SettingsManager::usePulseAudio() const {
    return m_data.value("usePulseAudio").toBool(false);
}
void SettingsManager::setUsePulseAudio(bool use) {
    if (usePulseAudio() != use) {
        m_data["usePulseAudio"] = use;
        save();
        emit usePulseAudioChanged();
    }
}

int SettingsManager::mosaicDensity() const {
    return m_data.value("mosaicDensity").toInt(2);
}
void SettingsManager::setMosaicDensity(int d) {
    if (mosaicDensity() != d) {
        m_data["mosaicDensity"] = d;
        save();
        emit mosaicDensityChanged();
    }
}

int SettingsManager::rawFilter() const {
    return m_data.value("rawFilter").toInt(0);
}
void SettingsManager::setRawFilter(int f) {
    if (rawFilter() != f) {
        m_data["rawFilter"] = f;
        save();
        emit rawFilterChanged();
    }
}

QString SettingsManager::language() const {
    QString saved = m_data.value("language").toString();
    if (saved.isEmpty())
        return QLocale::system().name().section('_', 0, 0);
    return saved;
}
void SettingsManager::setLanguage(const QString &lang) {
    if (language() != lang) {
        m_data["language"] = lang;
        save();
        emit languageChanged();
    }
}

bool SettingsManager::parallelThumbnails() const {
    return m_data.value("parallelThumbnails").toBool(false);
}
void SettingsManager::setParallelThumbnails(bool p) {
    if (parallelThumbnails() != p) {
        m_data["parallelThumbnails"] = p;
        save();
        emit parallelThumbnailsChanged();
    }
}

int SettingsManager::resourceMode() const {
    return m_data.value("resourceMode").toInt(0);  // default: Low
}
void SettingsManager::setResourceMode(int m) {
    m = std::max(0, std::min(m, 2));
    if (resourceMode() != m) {
        m_data["resourceMode"] = m;
        save();
        emit resourceModeChanged();
    }
}

bool SettingsManager::autoUpdate() const {
    return m_data.value("autoUpdate").toBool(true);
}
void SettingsManager::setAutoUpdate(bool on) {
    if (autoUpdate() != on) {
        m_data["autoUpdate"] = on;
        save();
        emit autoUpdateChanged();
    }
}

bool SettingsManager::autoScan() const {
    return m_data.value("autoScan").toBool(true);
}
void SettingsManager::setAutoScan(bool on) {
    if (autoScan() != on) {
        m_data["autoScan"] = on;
        save();
        emit autoScanChanged();
    }
}

int SettingsManager::windowButtons() const {
    return m_data.value("windowButtons").toInt(0);
}
void SettingsManager::setWindowButtons(int mode) {
    if (windowButtons() != mode) {
        m_data["windowButtons"] = mode;
        save();
        emit windowButtonsChanged();
    }
}

int SettingsManager::trashRetentionDays() const {
    return m_data.value("trashRetentionDays").toInt(30);
}
void SettingsManager::setTrashRetentionDays(int days) {
    days = std::max(0, days);
    if (trashRetentionDays() != days) {
        m_data["trashRetentionDays"] = days;
        save();
        emit trashRetentionDaysChanged();
    }
}

QString SettingsManager::skippedVersion() const {
    return m_data.value("skippedVersion").toString();
}
void SettingsManager::setSkippedVersion(const QString &v) {
    if (skippedVersion() != v) {
        m_data["skippedVersion"] = v;
        save();
        emit skippedVersionChanged();
    }
}

bool SettingsManager::use3DGlobe() const {
    return m_data.value("use3DGlobe").toBool(true);
}
void SettingsManager::setUse3DGlobe(bool use) {
    if (use3DGlobe() != use) {
        m_data["use3DGlobe"] = use;
        save();
        emit use3DGlobeChanged();
    }
}

bool SettingsManager::placesPanelCompact() const {
    return m_data.value("placesPanelCompact").toBool(false);
}
void SettingsManager::setPlacesPanelCompact(bool compact) {
    if (placesPanelCompact() != compact) {
        m_data["placesPanelCompact"] = compact;
        save();
        emit placesPanelCompactChanged();
    }
}

int SettingsManager::workerThreads() const {
    int cores = QThread::idealThreadCount();
    if (cores < 1) cores = 1;

    double frac;
    switch (resourceMode()) {
        case 2:  frac = 0.85; break;  // Full
        case 1:  frac = 0.60; break;  // Balanced
        default: frac = 0.35; break;  // Low (default)
    }

    int n = static_cast<int>(std::lround(cores * frac));
    n = std::max(1, n);
    // Never claim every core, even in Full mode, so the desktop stays usable.
    n = std::min(n, std::max(1, cores - 1));
    return n;
}

bool SettingsManager::copyImageToClipboard(const QString &filePath) {
    QImage img(filePath);
    if (img.isNull()) return false;
    QGuiApplication::clipboard()->setImage(img);
    return true;
}

QString SettingsManager::homePath() const {
    return QDir::homePath();
}

void SettingsManager::revealInFolder(const QString &filePath) {
    if (filePath.isEmpty()) return;

    const QString uri = QUrl::fromLocalFile(filePath).toString();

    // Preferred: ask the file manager to show (and select) the item.
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.FileManager1"),
        QStringLiteral("/org/freedesktop/FileManager1"),
        QStringLiteral("org.freedesktop.FileManager1"),
        QStringLiteral("ShowItems"));
    msg << QStringList{uri} << QString();

    QDBusMessage reply = QDBusConnection::sessionBus().call(msg);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        // Fallback: just open the containing directory.
        QDesktopServices::openUrl(
            QUrl::fromLocalFile(QFileInfo(filePath).absolutePath()));
    }
}
