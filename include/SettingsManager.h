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

    Q_INVOKABLE bool copyImageToClipboard(const QString &filePath);
    Q_INVOKABLE void openImageFilePicker(const QString &title = QString());

    QString homePath() const;

signals:
    void hideIgnoredInTimelineChanged();
    void usePulseAudioChanged();
    void mosaicDensityChanged();
    void rawFilterChanged();
    void languageChanged();
    void parallelThumbnailsChanged();
    void imageFilePicked(const QString &path);

private:
    void load();
    void save() const;

    QString m_path;
    QJsonObject m_data;
};
