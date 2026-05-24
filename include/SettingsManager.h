#pragma once

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hideIgnoredInTimeline READ hideIgnoredInTimeline WRITE setHideIgnoredInTimeline NOTIFY hideIgnoredInTimelineChanged)
    Q_PROPERTY(bool usePulseAudio READ usePulseAudio WRITE setUsePulseAudio NOTIFY usePulseAudioChanged)
    Q_PROPERTY(int  mosaicDensity READ mosaicDensity WRITE setMosaicDensity NOTIFY mosaicDensityChanged)
    Q_PROPERTY(int  rawFilter READ rawFilter WRITE setRawFilter NOTIFY rawFilterChanged)
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

    Q_INVOKABLE bool copyImageToClipboard(const QString &filePath);
    Q_INVOKABLE void openImageFilePicker(const QString &title = QString());

    QString homePath() const;

signals:
    void hideIgnoredInTimelineChanged();
    void usePulseAudioChanged();
    void mosaicDensityChanged();
    void rawFilterChanged();
    void imageFilePicked(const QString &path);

private:
    QSettings m_settings;
};
