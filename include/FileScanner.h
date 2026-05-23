#pragma once

#include <QObject>
#include <QStringList>
#include <QFuture>
#include <set>
#include <string>
#include <vector>
#include <atomic>

class DatabaseManager;

class FileScanner : public QObject {
    Q_OBJECT
public:
    explicit FileScanner(DatabaseManager *db, QObject *parent = nullptr);

    struct ScanResult {
        QStringList mediaPaths;
        size_t directoriesScanned;
        double durationSeconds;
    };

    // Performs a high-performance parallel scan
    Q_INVOKABLE void startScan(const QString &rootPath);

signals:
    void scanStarted(const QString &rootPath);
    void scanFinished(const QStringList &paths, int dirsScanned, double duration, const QString &rootPath);
    void scanProgress(int filesFound);

private:
    void runScan(const std::string &rootPath, const std::vector<std::string> &exclusions);

    std::set<std::string> m_mediaExtensions;
    DatabaseManager *m_db;
};
