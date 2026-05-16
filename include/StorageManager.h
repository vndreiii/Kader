#pragma once

#include <QObject>
#include <QStorageInfo>
#include "DatabaseManager.h"

class StorageManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(double totalGb       READ totalGb       NOTIFY storageChanged)
    Q_PROPERTY(double freeGb        READ freeGb        NOTIFY storageChanged)
    Q_PROPERTY(double mediaGb       READ mediaGb       NOTIFY storageChanged)
    Q_PROPERTY(int    mediaPercent  READ mediaPercent  NOTIFY storageChanged)
    Q_PROPERTY(qint64 mediaSizeBytes READ mediaSizeBytes NOTIFY storageChanged)

public:
    explicit StorageManager(DatabaseManager *db, QObject *parent = nullptr);

    double totalGb()  const;
    double freeGb()   const;
    double mediaGb()  const;
    int    mediaPercent() const;
    qint64 mediaSizeBytes() const { return m_mediaSizeBytes; }

    Q_INVOKABLE void refresh();

signals:
    void storageChanged();

private:
    DatabaseManager *m_db;
    QStorageInfo     m_storage;
    qint64           m_mediaSizeBytes = 0;
};
