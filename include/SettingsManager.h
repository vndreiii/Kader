#pragma once

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hideIgnoredInTimeline READ hideIgnoredInTimeline WRITE setHideIgnoredInTimeline NOTIFY hideIgnoredInTimelineChanged)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    bool hideIgnoredInTimeline() const;
    void setHideIgnoredInTimeline(bool hide);

signals:
    void hideIgnoredInTimelineChanged();

private:
    QSettings m_settings;
};
