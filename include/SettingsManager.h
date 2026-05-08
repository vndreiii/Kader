#pragma once

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hideIgnoredInTimeline READ hideIgnoredInTimeline WRITE setHideIgnoredInTimeline NOTIFY hideIgnoredInTimelineChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    bool hideIgnoredInTimeline() const;
    void setHideIgnoredInTimeline(bool hide);

    QString homePath() const;

signals:
    void hideIgnoredInTimelineChanged();

private:
    QSettings m_settings;
};
