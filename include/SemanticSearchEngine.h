#pragma once

#include <QObject>
#include <QThread>
#include <QString>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFile>
#include <QMutex>
#include <functional>

class DatabaseManager;

// Internal worker — lives on a background thread
class SemanticWorker : public QObject {
    Q_OBJECT
public:
    explicit SemanticWorker(DatabaseManager *db, QObject *parent = nullptr);
    ~SemanticWorker();

public slots:
    void loadModel(const QString &modelPath, const QString &mmprojPath);
    void unloadModel();
    void generateTextEmbedding(const QString &text, int queryId);
    void indexPendingMedia();

signals:
    void loaded(bool ok);
    void unloaded();
    void textEmbeddingReady(int queryId, QByteArray embedding);
    void indexProgress(int current, int total);
    void workerError(QString message);

private:
    std::vector<float> embedImage(const QString &imagePath);
    std::vector<float> embedText(const QString &text);
    void storeEmbedding(int mediaId, const std::vector<float> &embd);

    DatabaseManager *m_db;

    // llama.cpp opaque handles — defined as void* to avoid including llama.h in header
    void *m_model   = nullptr;
    void *m_ctx     = nullptr;
    void *m_mtmd    = nullptr;
    int   m_nEmbd   = 0;

    QMutex m_mutex;
};

// Public API — lives on the main thread
class SemanticSearchEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready          READ ready          NOTIFY readyChanged)
    Q_PROPERTY(bool modelsPresent  READ modelsPresent  NOTIFY modelsPresentChanged)
    Q_PROPERTY(bool loading        READ loading        NOTIFY loadingChanged)
    Q_PROPERTY(bool downloading    READ downloading    NOTIFY downloadingChanged)
    Q_PROPERTY(QString dlStatus    READ dlStatus       NOTIFY dlStatusChanged)
    Q_PROPERTY(double  dlProgress  READ dlProgress     NOTIFY dlProgressChanged)
    Q_PROPERTY(int indexedCount    READ indexedCount   NOTIFY indexedCountChanged)
    Q_PROPERTY(int indexTotal      READ indexTotal     NOTIFY indexTotalChanged)
    Q_PROPERTY(bool indexing       READ indexing       NOTIFY indexingChanged)

public:
    explicit SemanticSearchEngine(DatabaseManager *db, QObject *parent = nullptr);
    ~SemanticSearchEngine();

    bool ready()         const { return m_ready; }
    bool modelsPresent() const;
    bool loading()       const { return m_loading; }
    bool downloading()   const { return m_downloading; }
    QString dlStatus()   const { return m_dlStatus; }
    double  dlProgress() const { return m_dlProgress; }
    int indexedCount()   const { return m_indexedCount; }
    int indexTotal()     const { return m_indexTotal; }
    bool indexing()      const { return m_indexing; }

    // Models are stored here
    static QString modelsDir();
    static QString modelPath();
    static QString mmprojPath();

    Q_INVOKABLE void loadModel();
    Q_INVOKABLE void unloadModel();
    Q_INVOKABLE void downloadModels();
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void indexAllMedia();

    // Async cosine-similarity search; emits searchFinished([{id, score}]) when done
    Q_INVOKABLE void searchByText(const QString &query);

signals:
    void readyChanged();
    void modelsPresentChanged();
    void loadingChanged();
    void downloadingChanged();
    void dlStatusChanged();
    void dlProgressChanged();
    void indexedCountChanged();
    void indexTotalChanged();
    void indexingChanged();
    void searchFinished(QVariantList results);
    void engineError(QString message);

private slots:
    void onWorkerLoaded(bool ok);
    void onTextEmbeddingReady(int queryId, QByteArray embedding);
    void onIndexProgress(int cur, int total);
    void onWorkerError(QString msg);
    void downloadNext();
    void onDownloadProgress(qint64 recv, qint64 total);
    void onDownloadFinished();

private:
    DatabaseManager         *m_db;
    QThread                 *m_thread  = nullptr;
    SemanticWorker          *m_worker  = nullptr;
    QNetworkAccessManager   *m_nam     = nullptr;
    QNetworkReply           *m_reply   = nullptr;
    QFile                   *m_dlFile  = nullptr;

    bool    m_ready        = false;
    bool    m_loading      = false;
    bool    m_downloading  = false;
    bool    m_dlCancel     = false;
    bool    m_indexing     = false;
    QString m_dlStatus;
    double  m_dlProgress   = 0.0;
    int     m_indexedCount = 0;
    int     m_indexTotal   = 0;

    // Download queue: pairs of (url, local-path)
    QList<QPair<QString,QString>> m_dlQueue;
    int m_dlIdx = 0;
    qint64 m_dlTotalBytes = 0;
    qint64 m_dlRecvBytes  = 0;

    // Pending text-query callbacks: queryId → lambda
    QHash<int, std::function<void(QByteArray)>> m_textCbs;
    int m_nextQueryId = 0;

    static float cosine(const float *a, const float *b, int n);
};
