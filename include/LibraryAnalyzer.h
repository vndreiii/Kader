#pragma once

#include <QFuture>
#include <QHash>
#include <QImage>
#include <QObject>
#include <QQuickImageProvider>
#include <QVariantList>
#include <atomic>
#include <mutex>

class DatabaseManager;
class ThumbnailGenerator;
class QNetworkAccessManager;
class QNetworkReply;
struct KfDetector;
struct KfRecognizer;
struct KgWorld;

// Background understanding of the library, and the queries the Search tab
// is built from:
//
//   * colour — dominant colour bucket + palette of every photo (always on);
//   * faces  — detection + identity embeddings, grouped into people (opt-in:
//              the two small ONNX models are downloaded on first use);
//   * people editing — rename, hide, merge, remove/add faces, sensitivity;
//   * explore — colour groups, memories (on this day, trips, years), places,
//              and a structured search over people/places/colours/dates/files.
//
// Analysis reads the 768px thumbnail cache, so RAW/HEIC/video work like
// everything else, and runs on a bounded thread pool at background priority.
class LibraryAnalyzer : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int done READ done NOTIFY progressChanged)
    Q_PROPERTY(int total READ total NOTIFY progressChanged)
    Q_PROPERTY(bool facesEnabled READ facesEnabled NOTIFY facesEnabledChanged)
    Q_PROPERTY(bool faceModelsPresent READ faceModelsPresent NOTIFY faceModelsPresentChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadingChanged)
    Q_PROPERTY(double downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(double threshold READ threshold NOTIFY thresholdChanged)
    // Bumped whenever people/colour/place data changes; views re-query on it.
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    LibraryAnalyzer(DatabaseManager *db, ThumbnailGenerator *thumbs, QObject *parent = nullptr);
    ~LibraryAnalyzer() override;

    bool running() const { return m_running; }
    int done() const { return m_done; }
    int total() const { return m_total; }
    bool facesEnabled() const { return m_facesEnabled; }
    bool faceModelsPresent() const;
    bool downloading() const { return m_reply != nullptr; }
    double downloadProgress() const { return m_dlProgress; }
    QString error() const { return m_error; }
    double threshold() const { return m_threshold; }
    int revision() const { return m_revision; }

    void setResourceBudget(int threads);

    // ── analysis ──────────────────────────────────────────────────────────
    Q_INVOKABLE void start();          // analyse whatever is pending
    Q_INVOKABLE void stop();
    Q_INVOKABLE void enableFaces();    // downloads the models if needed
    Q_INVOKABLE void disableFaces();

    // ── people ────────────────────────────────────────────────────────────
    Q_INVOKABLE QVariantList people(bool includeHidden = false);
    Q_INVOKABLE QVariantMap person(int id);
    Q_INVOKABLE QVariantList personFaces(int id);
    Q_INVOKABLE QVariantList personMedia(int id);
    Q_INVOKABLE QVariantList suggestedFaces(int id, int limit = 48);
    Q_INVOKABLE void renamePerson(int id, const QString &name);
    Q_INVOKABLE void setPersonHidden(int id, bool hidden);
    Q_INVOKABLE void removeFaces(const QVariantList &faceIds);
    Q_INVOKABLE void assignFaces(const QVariantList &faceIds, int personId);
    Q_INVOKABLE int newPerson(const QVariantList &faceIds, const QString &name);
    Q_INVOKABLE void mergePeople(int from, int into);
    Q_INVOKABLE void setCover(int personId, int faceId);
    Q_INVOKABLE void setThreshold(double t);
    // Groups and grouped-face count the clustering would give at `t`.
    Q_INVOKABLE QVariantMap previewThreshold(double t);
    Q_INVOKABLE void recluster();

    // ── explore ───────────────────────────────────────────────────────────
    Q_INVOKABLE QVariantList colorGroups();
    Q_INVOKABLE QVariantList colorMedia(int bucket);
    Q_INVOKABLE QVariantList memories();
    Q_INVOKABLE QVariantList memoryMedia(const QString &key);
    Q_INVOKABLE QVariantList places(int limit = 30);
    Q_INVOKABLE QVariantList placeMedia(const QString &name);
    // {chips: [{kind,label,key}], media: [...], residual: "words no
    // structured filter matched" (for semantic search)}
    Q_INVOKABLE QVariantMap search(const QString &query);
    Q_INVOKABLE QVariantList mediaByIds(const QVariantList &ids);
    Q_INVOKABLE QVariantList mediaForKey(const QString &key);

    // Square crop around a face from the thumbnail cache (image provider).
    QImage faceImage(int faceId, int size);

    static QString modelsDir();

signals:
    void runningChanged();
    void progressChanged();
    void facesEnabledChanged();
    void faceModelsPresentChanged();
    void downloadingChanged();
    void downloadProgressChanged();
    void errorChanged();
    void thresholdChanged();
    void revisionChanged();

private:
    struct Result;
    void runLoop();
    Result analyze(int mediaId, const QString &path) const;
    bool loadFaceModels();
    void reclusterNow();          // worker thread
    void bump();
    void setError(const QString &e);
    void downloadNext();
    void ensurePlaces();
    QString placeOf(double lat, double lon, double maxKm = 60) const;
    QVariantList mediaWhere(const QString &where, const QVariantList &binds,
                            const QString &order = QStringLiteral("m.creation_date DESC"), int limit = 5000);
    void setSetting(const QString &key, const QString &value);
    QString setting(const QString &key, const QString &def) const;

    DatabaseManager *m_db;
    ThumbnailGenerator *m_thumbs;

    // models (immutable once loaded; Rust inference is re-entrant)
    KfDetector *m_detector = nullptr;
    KfRecognizer *m_recognizer = nullptr;
    std::mutex m_modelMutex;

    QFuture<void> m_loop;
    std::atomic<bool> m_cancel{false};
    std::atomic<bool> m_restart{false};
    std::atomic<int> m_threads{2};
    bool m_running = false;
    int m_done = 0;
    int m_total = 0;
    bool m_facesEnabled = false;
    double m_threshold = 0.38;
    int m_revision = 0;
    QString m_error;

    // downloads
    QNetworkAccessManager *m_nam = nullptr;
    QNetworkReply *m_reply = nullptr;
    int m_dlIndex = 0;
    double m_dlProgress = 0;

    // places: media id → "City, Country" (computed lazily from GPS)
    KgWorld *m_world = nullptr;
    bool m_worldRequested = false;
    QHash<int, QString> m_placeOf;
    int m_placesRevision = -1;
};

class FaceImageProvider : public QQuickImageProvider {
public:
    explicit FaceImageProvider(LibraryAnalyzer *a)
        : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading),
          m_analyzer(a) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;

private:
    LibraryAnalyzer *m_analyzer;
};
