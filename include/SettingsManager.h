#pragma once

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hideIgnoredInTimeline READ hideIgnoredInTimeline WRITE setHideIgnoredInTimeline NOTIFY hideIgnoredInTimelineChanged)
    Q_PROPERTY(bool usePulseAudio READ usePulseAudio WRITE setUsePulseAudio NOTIFY usePulseAudioChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    bool hideIgnoredInTimeline() const;
    void setHideIgnoredInTimeline(bool hide);

    bool usePulseAudio() const;
    void setUsePulseAudio(bool use);

    QString homePath() const;

signals:
    void hideIgnoredInTimelineChanged();
    void usePulseAudioChanged();

private:
    QSettings m_settings;
};
