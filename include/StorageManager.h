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

    // ── storage dashboard ─────────────────────────────────────────────────
    // Bytes on the library's disk: {total, free, photos, videos, raw, trash,
    // other} (other = everything on the disk that isn't Kader's library).
    Q_INVOKABLE QVariantMap overview();
    // Largest folders: [{folder, name, bytes, count}]
    Q_INVOKABLE QVariantList byFolder(int limit = 8);
    // Per capture year: [{year, bytes, count}] (oldest first)
    Q_INVOKABLE QVariantList byYear();
    // Per file type: [{ext, bytes, count}] largest first
    Q_INVOKABLE QVariantList byType();
    // Largest files (media maps + thumb)
    Q_INVOKABLE QVariantList largest(int limit = 60);
    // Likely duplicates: same name and size in different folders.
    // [{name, bytes, copies: [media…]}] — wasted bytes first
    Q_INVOKABLE QVariantList duplicates(int limit = 40);
    Q_INVOKABLE QVariantList trashItems(int limit = 200);

    // Everything the dashboard shows, computed on a worker thread so opening
    // it never stalls the UI; answered by dashboardLoaded({overview, folders,
    // years, types, largest, dups, trash}). Overlapping requests: only the
    // latest one is delivered.
    Q_INVOKABLE void loadDashboard();

signals:
    void storageChanged();
    void dashboardLoaded(const QVariantMap &data);

private:
    DatabaseManager *m_db;
    int              m_dashboardGen = 0;
    QStorageInfo     m_storage;
    qint64           m_mediaSizeBytes = 0;
    qint64           m_photoSizeBytes = 0;
    qint64           m_videoSizeBytes = 0;
    int              m_photoCount = 0;
    int              m_videoCount = 0;
};
