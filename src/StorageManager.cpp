#include "StorageManager.h"
#include <QDir>

StorageManager::StorageManager(QObject *parent)
    : QObject(parent), m_storage(QDir::root()) {
}

double StorageManager::totalGb() const {
    return static_cast<double>(m_storage.bytesTotal()) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::freeGb() const {
    return static_cast<double>(m_storage.bytesAvailable()) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::mediaGb() const {
    // For now, return a mock value or 5% of total
    return totalGb() * 0.05;
}

int StorageManager::mediaPercent() const {
    double total = totalGb();
    if (total <= 0) return 0;
    return static_cast<int>((mediaGb() / total) * 100.0);
}

void StorageManager::refresh() {
    m_storage.refresh();
    emit storageChanged();
}
