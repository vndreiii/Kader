#pragma once

#include <QObject>
#include <QJsonObject>

class SettingsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hideIgnoredInTimeline READ hideIgnoredInTimeline WRITE setHideIgnoredInTimeline NOTIFY hideIgnoredInTimelineChanged)
    Q_PROPERTY(bool usePulseAudio READ usePulseAudio WRITE setUsePulseAudio NOTIFY usePulseAudioChanged)
    Q_PROPERTY(int  mosaicDensity READ mosaicDensity WRITE setMosaicDensity NOTIFY mosaicDensityChanged)
    Q_PROPERTY(int  rawFilter READ rawFilter WRITE setRawFilter NOTIFY rawFilterChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(bool parallelThumbnails READ parallelThumbnails WRITE setParallelThumbnails NOTIFY parallelThumbnailsChanged)
    Q_PROPERTY(int  resourceMode READ resourceMode WRITE setResourceMode NOTIFY resourceModeChanged)
    Q_PROPERTY(bool use3DGlobe READ use3DGlobe WRITE setUse3DGlobe NOTIFY use3DGlobeChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    bool hideIgnoredInTimeline() const;
    void setHideIgnoredInTimeline(bool hide);

    bool usePulseAudio() const;
    void setUsePulseAudio(bool use);

    int  mosaicDensity() const;
    void setMosaicDensity(int d);

    // 0 = all, 1 = JPEG-only (hide RAW), 2 = RAW-only (hide JPEG)
    int  rawFilter() const;
    void setRawFilter(int f);

    QString language() const;
    void setLanguage(const QString &lang);

    bool parallelThumbnails() const;
    void setParallelThumbnails(bool p);

    // Resource budget: 0 = Low (~35% of cores, default), 1 = Balanced (~60%),
    // 2 = Full (~85%, never the whole machine). Controls scan threads, thumbnail
    // concurrency, and the libvips cache ceiling.
    int  resourceMode() const;
    void setResourceMode(int m);

    // Places view: true = 3D rotating globe, false = classic 2D map.
    bool use3DGlobe() const;
    void setUse3DGlobe(bool use);

    // Number of worker threads to use for the current resource mode, derived
    // from the CPU core count. Always >= 1 and capped below the core count so
    // the desktop stays responsive.
    Q_INVOKABLE int workerThreads() const;

    Q_INVOKABLE bool copyImageToClipboard(const QString &filePath);

    // Open the system file manager with `filePath` selected (freedesktop
    // FileManager1, with a plain "open parent folder" fallback). Lives here so
    // the standalone viewer can reveal files without the database backend.
    Q_INVOKABLE void revealInFolder(const QString &filePath);

    QString homePath() const;

signals:
    void hideIgnoredInTimelineChanged();
    void usePulseAudioChanged();
    void mosaicDensityChanged();
    void rawFilterChanged();
    void languageChanged();
    void parallelThumbnailsChanged();
    void resourceModeChanged();
    void use3DGlobeChanged();

private:
    void load();
    void save() const;

    QString m_path;
    QJsonObject m_data;
};
