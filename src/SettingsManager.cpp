#include "SettingsManager.h"

SettingsManager::SettingsManager(QObject *parent) 
    : QObject(parent), m_settings("Kader", "KaderGallery") {
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
