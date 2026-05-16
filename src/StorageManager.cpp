#include "StorageManager.h"
#include <QDir>

StorageManager::StorageManager(DatabaseManager *db, QObject *parent)
    : QObject(parent), m_db(db), m_storage(QDir::root()) {
    refresh();
}

double StorageManager::totalGb() const {
    return static_cast<double>(m_storage.bytesTotal()) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::freeGb() const {
    return static_cast<double>(m_storage.bytesAvailable()) / (1024.0 * 1024.0 * 1024.0);
}

double StorageManager::mediaGb() const {
    return static_cast<double>(m_mediaSizeBytes) / (1024.0 * 1024.0 * 1024.0);
}

int StorageManager::mediaPercent() const {
    const double total = totalGb();
    if (total <= 0) return 0;
    return static_cast<int>((mediaGb() / total) * 100.0);
}

void StorageManager::refresh() {
    m_storage.refresh();
    m_mediaSizeBytes = m_db->getTotalMediaSizeBytes();
    emit storageChanged();
}
