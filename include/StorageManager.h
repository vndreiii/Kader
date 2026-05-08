#pragma once

#include <QObject>
#include <QStorageInfo>

class StorageManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(double totalGb READ totalGb NOTIFY storageChanged)
    Q_PROPERTY(double freeGb READ freeGb NOTIFY storageChanged)
    Q_PROPERTY(double mediaGb READ mediaGb NOTIFY storageChanged)
    Q_PROPERTY(int mediaPercent READ mediaPercent NOTIFY storageChanged)

public:
    explicit StorageManager(QObject *parent = nullptr);

    double totalGb() const;
    double freeGb() const;
    double mediaGb() const; // Mocked for now, could sum DB sizes
    int mediaPercent() const;

    Q_INVOKABLE void refresh();

signals:
    void storageChanged();

private:
    QStorageInfo m_storage;
};
