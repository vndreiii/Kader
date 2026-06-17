#pragma once

#include <QObject>
#include <QStorageInfo>
#include "DatabaseManager.h"

class StorageManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(double totalGb       READ totalGb       NOTIFY storageChanged)
    Q_PROPERTY(double freeGb        READ freeGb        NOTIFY storageChanged)
    Q_PROPERTY(double mediaGb       READ mediaGb       NOTIFY storageChanged)
    Q_PROPERTY(double photoGb       READ photoGb       NOTIFY storageChanged)
    Q_PROPERTY(double videoGb       READ videoGb       NOTIFY storageChanged)
    Q_PROPERTY(int    mediaPercent  READ mediaPercent  NOTIFY storageChanged)
    Q_PROPERTY(qint64 mediaSizeBytes READ mediaSizeBytes NOTIFY storageChanged)
    Q_PROPERTY(int    photoCount    READ photoCount    NOTIFY storageChanged)
    Q_PROPERTY(int    videoCount    READ videoCount    NOTIFY storageChanged)

public:
    explicit StorageManager(DatabaseManager *db, QObject *parent = nullptr);

    double totalGb()  const;
    double freeGb()   const;
    double mediaGb()  const;
    double photoGb()  const;
    double videoGb()  const;
    int    mediaPercent() const;
    qint64 mediaSizeBytes() const { return m_mediaSizeBytes; }
    int    photoCount() const { return m_photoCount; }
    int    videoCount() const { return m_videoCount; }

    Q_INVOKABLE void refresh();

signals:
    void storageChanged();

private:
    DatabaseManager *m_db;
    QStorageInfo     m_storage;
    qint64           m_mediaSizeBytes = 0;
    qint64           m_photoSizeBytes = 0;
    qint64           m_videoSizeBytes = 0;
    int              m_photoCount = 0;
    int              m_videoCount = 0;
};
