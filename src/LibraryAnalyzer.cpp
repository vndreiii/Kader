#include "LibraryAnalyzer.h"
#include <QUrl>
#include "AppPaths.h"

#include "DatabaseManager.h"
#include "GlobeItem.h"
#include "ThumbnailGenerator.h"
#include "kader_core.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFutureWatcher>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSet>
#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QStandardPaths>
#include <QThreadPool>
#include <QtConcurrent>
#include <algorithm>
#include <climits>
#include <cmath>
#include <map>

namespace {

// OpenCV Zoo models (MIT / Apache-2.0), pinned by content hash.
struct ModelFile {
    const char *url;
    const char *name;
    const char *sha256;
};
constexpr ModelFile kModels[] = {
    {"https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_detection_yunet/"
     "face_detection_yunet_2023mar.onnx",
     "face_detection_yunet_2023mar.onnx", "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"},
    {"https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_recognition_sface/"
     "face_recognition_sface_2021dec.onnx",
     "face_recognition_sface_2021dec.onnx", "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"},
};

constexpr int kThumb = 768;              // analysis reads the grid's thumbnail cache
constexpr float kDetectScore = 0.82f;    // YuNet confidence (animals mostly score lower)
constexpr float kMinFacePx = 28.0f;      // in thumbnail pixels: smaller faces don't recognise well
constexpr int kAnalysisVersion = 1;

const char *kAlive = "m.is_trashed = 0 AND COALESCE(m.is_hidden,0) = 0 AND COALESCE(m.is_ignored,0) = 0";

QVariantMap rowToMedia(const QSqlQuery &q, const QSqlRecord &rec) {
    QVariantMap m;
    for (int i = 0; i < rec.count(); ++i)
        m.insert(rec.fieldName(i), q.value(i));
    const QString fp = m.value(QStringLiteral("file_path")).toString();
    m.insert(QStringLiteral("thumb"), ThumbnailGenerator::thumbnailUrl(fp));
    m.insert(QStringLiteral("path"), QUrl::fromLocalFile(fp).toString());
    return m;
}

QString placeholders(int n) {
    QStringList p;
    p.reserve(n);
    for (int i = 0; i < n; ++i)
        p << QStringLiteral("?");
    return p.join(QLatin1Char(','));
}

QString bucketName(int b) {
    const char *n = kc_bucket_name(uint32_t(b));
    return n ? QString::fromLatin1(n) : QString();
}

QByteArray fileSha256(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    QCryptographicHash h(QCryptographicHash::Sha256);
    h.addData(&f);
    return h.result().toHex();
}

} // namespace

struct LibraryAnalyzer::Result {
    int mediaId = 0;
    bool ok = false;
    KcStats color{};
    bool facesRan = false;
    struct F {
        KfFace face;
        float emb[KF_EMBED_DIM];
    };
    QVector<F> faces;
    int width = 0, height = 0;
};

QString LibraryAnalyzer::modelsDir() {
    return AppPaths::localDataDir() + QStringLiteral("/models");
}

LibraryAnalyzer::LibraryAnalyzer(DatabaseManager *db, ThumbnailGenerator *thumbs, QObject *parent)
    : QObject(parent), m_db(db), m_thumbs(thumbs) {
    m_facesEnabled = setting(QStringLiteral("faces_enabled"), QStringLiteral("0")) == QLatin1String("1");
    m_threshold = setting(QStringLiteral("faces_threshold"), QStringLiteral("0.38")).toDouble();
    if (m_threshold < 0.2 || m_threshold > 0.8)
        m_threshold = 0.38;
}

LibraryAnalyzer::~LibraryAnalyzer() {
    m_cancel = true;
    m_loop.waitForFinished();
    kf_detector_free(m_detector);
    kf_recognizer_free(m_recognizer);
}

void LibraryAnalyzer::setSetting(const QString &key, const QString &value) {
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("INSERT INTO settings_kv (key,value) VALUES (?,?) "
                             "ON CONFLICT(key) DO UPDATE SET value=excluded.value"));
    q.addBindValue(key);
    q.addBindValue(value);
    q.exec();
}

QString LibraryAnalyzer::setting(const QString &key, const QString &def) const {
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("SELECT value FROM settings_kv WHERE key=?"));
    q.addBindValue(key);
    if (q.exec() && q.next())
        return q.value(0).toString();
    return def;
}

void LibraryAnalyzer::bump() {
    ++m_revision;
    emit revisionChanged();
}

void LibraryAnalyzer::setError(const QString &e) {
    if (m_error == e)
        return;
    m_error = e;
    emit errorChanged();
}

void LibraryAnalyzer::setResourceBudget(int threads) {
    m_threads = std::clamp(threads > 0 ? threads / 2 : 2, 1, 8);
}

// ── models ───────────────────────────────────────────────────────────────────

bool LibraryAnalyzer::faceModelsPresent() const {
    for (const auto &m : kModels)
        if (!QFile::exists(modelsDir() + QLatin1Char('/') + QLatin1String(m.name)))
            return false;
    return true;
}

bool LibraryAnalyzer::loadFaceModels() {
    std::lock_guard lk(m_modelMutex);
    if (m_detector && m_recognizer)
        return true;
    auto read = [](const QString &p) {
        QFile f(p);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    };
    char err[256] = {0};
    const QByteArray det = read(modelsDir() + QLatin1Char('/') + QLatin1String(kModels[0].name));
    const QByteArray rec = read(modelsDir() + QLatin1Char('/') + QLatin1String(kModels[1].name));
    if (!m_detector)
        m_detector = kf_detector_load(reinterpret_cast<const uint8_t *>(det.constData()), size_t(det.size()), err, sizeof err);
    if (!m_recognizer && m_detector)
        m_recognizer = kf_recognizer_load(reinterpret_cast<const uint8_t *>(rec.constData()), size_t(rec.size()), err, sizeof err);
    if (!m_detector || !m_recognizer) {
        const QString msg = QStringLiteral("Face models failed to load: ") + QString::fromUtf8(err);
        qWarning() << msg;
        QMetaObject::invokeMethod(this, [this, msg] { setError(msg); }, Qt::QueuedConnection);
        return false;
    }
    return true;
}

void LibraryAnalyzer::enableFaces() {
    if (!m_facesEnabled) {
        m_facesEnabled = true;
        setSetting(QStringLiteral("faces_enabled"), QStringLiteral("1"));
        emit facesEnabledChanged();
    }
    setError({});
    if (faceModelsPresent()) {
        start();
        return;
    }
    if (m_reply)
        return;
    QDir().mkpath(modelsDir());
    if (!m_nam)
        m_nam = new QNetworkAccessManager(this);
    m_dlIndex = 0;
    downloadNext();
}

void LibraryAnalyzer::disableFaces() {
    if (!m_facesEnabled)
        return;
    m_facesEnabled = false;
    setSetting(QStringLiteral("faces_enabled"), QStringLiteral("0"));
    emit facesEnabledChanged();
    bump();
}

void LibraryAnalyzer::downloadNext() {
    while (m_dlIndex < int(std::size(kModels)) &&
           QFile::exists(modelsDir() + QLatin1Char('/') + QLatin1String(kModels[m_dlIndex].name)))
        ++m_dlIndex;
    if (m_dlIndex >= int(std::size(kModels))) {
        m_dlProgress = 1;
        emit downloadProgressChanged();
        emit faceModelsPresentChanged();
        start();
        return;
    }
    const ModelFile &mf = kModels[m_dlIndex];
    QNetworkRequest req{QUrl(QString::fromLatin1(mf.url))};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_nam->get(req);
    emit downloadingChanged();
    const QString part = modelsDir() + QLatin1Char('/') + QLatin1String(mf.name) + QStringLiteral(".part");
    auto *file = new QFile(part, m_reply);
    file->open(QIODevice::WriteOnly | QIODevice::Truncate);
    connect(m_reply, &QNetworkReply::readyRead, this, [this, file] { file->write(m_reply->readAll()); });
    connect(m_reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        const double f = total > 0 ? double(got) / double(total) : 0;
        m_dlProgress = (m_dlIndex + f) / double(std::size(kModels));
        emit downloadProgressChanged();
    });
    connect(m_reply, &QNetworkReply::finished, this, [this, file, part, mf] {
        file->write(m_reply->readAll());
        file->close();
        const bool ok = m_reply->error() == QNetworkReply::NoError;
        const QString err = m_reply->errorString();
        m_reply->deleteLater();
        m_reply = nullptr;
        emit downloadingChanged();
        const QString final = modelsDir() + QLatin1Char('/') + QLatin1String(mf.name);
        if (!ok) {
            QFile::remove(part);
            setError(QStringLiteral("Download failed: ") + err);
            return;
        }
        if (fileSha256(part) != QByteArray(mf.sha256)) {
            QFile::remove(part);
            setError(QStringLiteral("Downloaded face model failed verification"));
            return;
        }
        QFile::remove(final);
        QFile::rename(part, final);
        ++m_dlIndex;
        downloadNext();
    });
}

// ── analysis loop ────────────────────────────────────────────────────────────

void LibraryAnalyzer::start() {
    m_placeOf.clear();
    m_placesRevision = -1;
    if (m_running) {
        m_restart = true; // pick up newly added media after this pass
        return;
    }
    m_cancel = false;
    m_restart = false;
    m_running = true;
    emit runningChanged();
    m_loop = QtConcurrent::run([this] { runLoop(); });
}

void LibraryAnalyzer::stop() {
    m_cancel = true;
}

LibraryAnalyzer::Result LibraryAnalyzer::analyze(int mediaId, const QString &path) const {
    Result r;
    r.mediaId = mediaId;
    const QString thumb = m_thumbs->getOrCreateThumbnail(path, kThumb);
    QImage img = thumb.isEmpty() ? QImage() : QImage(thumb);
    if (img.isNull())
        return r; // unreadable: recorded as analysed so it isn't retried forever
    img = img.convertToFormat(QImage::Format_RGB888);
    const auto *px = img.constBits();
    const uint32_t w = uint32_t(img.width()), h = uint32_t(img.height()), stride = uint32_t(img.bytesPerLine());
    r.width = img.width();
    r.height = img.height();
    r.ok = kc_color_stats(px, w, h, stride, &r.color) == 0;
    if (m_facesEnabled && m_detector && m_recognizer) {
        KfFace found[32];
        const int n = kf_detect(m_detector, px, w, h, stride, kThumb, kDetectScore, found, 32);
        r.facesRan = n >= 0;
        for (int i = 0; i < n; ++i) {
            if (std::min(found[i].w, found[i].h) < kMinFacePx)
                continue;
            Result::F f;
            f.face = found[i];
            if (kf_embed(m_recognizer, px, w, h, stride, &found[i], f.emb) == 0)
                r.faces.push_back(f);
        }
    }
    return r;
}

void LibraryAnalyzer::runLoop() {
    QSqlDatabase db = m_db->threadDb();
    const bool faces = m_facesEnabled && faceModelsPresent() && loadFaceModels();
    kn_set_threads(1); // parallelism comes from analysing several photos at once

    QThreadPool pool;
    pool.setMaxThreadCount(m_threads);
    pool.setThreadPriority(QThread::LowestPriority);

    const QString pendingWhere = QStringLiteral(
        "FROM media m LEFT JOIN media_analysis a ON a.media_id = m.id WHERE %1 "
        "AND (a.media_id IS NULL OR a.version < %2 %3)")
        .arg(QLatin1String(kAlive)).arg(kAnalysisVersion)
        .arg(faces ? QStringLiteral("OR a.faces_done = 0") : QString());

    int total = 0;
    {
        QSqlQuery c(db);
        if (c.exec(QStringLiteral("SELECT COUNT(*) ") + pendingWhere) && c.next())
            total = c.value(0).toInt();
    }
    QMetaObject::invokeMethod(this, [this, total] {
        m_done = 0;
        m_total = total;
        emit progressChanged();
    }, Qt::QueuedConnection);

    int done = 0;
    int newFaces = 0;
    while (!m_cancel) {
        QVector<QPair<int, QString>> batch;
        {
            QSqlQuery q(db);
            q.exec(QStringLiteral("SELECT m.id, m.file_path ") + pendingWhere +
                   QStringLiteral(" ORDER BY m.creation_date DESC LIMIT 48"));
            while (q.next())
                batch.push_back({q.value(0).toInt(), q.value(1).toString()});
        }
        if (batch.isEmpty())
            break;
        const QList<Result> results = QtConcurrent::blockingMapped<QList<Result>>(
            &pool, batch, [this](const QPair<int, QString> &it) { return analyze(it.first, it.second); });

        db.transaction();
        QSqlQuery up(db), delFaces(db), insFace(db);
        up.prepare(QStringLiteral(
            "INSERT OR REPLACE INTO media_analysis (media_id, color_bucket, color_frac, avg_rgb, palette, faces_done, version) "
            "VALUES (?,?,?,?,?,?,?)"));
        delFaces.prepare(QStringLiteral("DELETE FROM faces WHERE media_id=? AND confirmed=0"));
        insFace.prepare(QStringLiteral(
            "INSERT INTO faces (media_id, x, y, w, h, score, embedding) VALUES (?,?,?,?,?,?,?)"));
        for (const Result &r : results) {
            QByteArray palette(15, 0);
            for (int i = 0; i < 5; ++i)
                for (int c = 0; c < 3; ++c)
                    palette[i * 3 + c] = char(r.color.palette[i][c]);
            up.addBindValue(r.mediaId);
            up.addBindValue(r.ok ? int(r.color.bucket) : 0);
            up.addBindValue(r.ok ? double(r.color.bucket_frac) : 0.0);
            up.addBindValue(r.ok ? (int(r.color.average[0]) << 16 | int(r.color.average[1]) << 8 | int(r.color.average[2])) : 0);
            up.addBindValue(palette);
            up.addBindValue((faces && (r.facesRan || !r.ok)) ? 1 : 0);
            up.addBindValue(kAnalysisVersion);
            up.exec();
            if (r.facesRan) {
                delFaces.addBindValue(r.mediaId);
                delFaces.exec();
                for (const auto &f : r.faces) {
                    const double W = std::max(1, r.width), H = std::max(1, r.height);
                    insFace.addBindValue(r.mediaId);
                    insFace.addBindValue(f.face.x / W);
                    insFace.addBindValue(f.face.y / H);
                    insFace.addBindValue(f.face.w / W);
                    insFace.addBindValue(f.face.h / H);
                    insFace.addBindValue(double(f.face.score));
                    insFace.addBindValue(QByteArray(reinterpret_cast<const char *>(f.emb), int(sizeof f.emb)));
                    insFace.exec();
                    ++newFaces;
                }
            }
        }
        db.commit();
        done += int(results.size());
        QMetaObject::invokeMethod(this, [this, done] {
            m_done = done;
            emit progressChanged();
            // refresh views every few hundred photos while a big library runs
            if (done % 480 < 48)
                bump();
        }, Qt::QueuedConnection);
    }

    if (faces && newFaces > 0 && !m_cancel)
        reclusterNow();

    QMetaObject::invokeMethod(this, [this] {
        m_running = false;
        emit runningChanged();
        bump();
        if (m_restart.exchange(false) && !m_cancel)
            start();
    }, Qt::QueuedConnection);
}

// ── clustering ───────────────────────────────────────────────────────────────

void LibraryAnalyzer::reclusterNow() {
    QSqlDatabase db = m_db->threadDb();
    struct Row {
        int id;
        int person;
        bool confirmed;
        int excluded;
    };
    QVector<Row> rows;
    std::vector<float> embs;
    {
        QSqlQuery q(db);
        q.exec(QStringLiteral(
            "SELECT f.id, COALESCE(f.person_id,-1), f.confirmed, f.excluded_person, f.embedding FROM faces f "
            "JOIN media m ON m.id = f.media_id WHERE %1 ORDER BY f.confirmed DESC, f.score DESC")
                   .arg(QLatin1String(kAlive)));
        while (q.next()) {
            const QByteArray e = q.value(4).toByteArray();
            if (e.size() != int(KF_EMBED_DIM * sizeof(float)))
                continue;
            rows.push_back({q.value(0).toInt(), q.value(1).toInt(), q.value(2).toBool(), q.value(3).toInt()});
            const auto *f = reinterpret_cast<const float *>(e.constData());
            embs.insert(embs.end(), f, f + KF_EMBED_DIM);
        }
    }
    const size_t n = size_t(rows.size());
    if (n == 0)
        return;
    std::vector<int64_t> fixed(n), exclude(n), clusterPerson(n);
    std::vector<uint32_t> labels(n);
    for (size_t i = 0; i < n; ++i) {
        fixed[i] = rows[int(i)].confirmed ? rows[int(i)].person : -1;
        exclude[i] = rows[int(i)].excluded;
    }
    const int64_t k = kf_cluster(embs.data(), n, fixed.data(), exclude.data(), float(m_threshold), labels.data(),
                                 clusterPerson.data());
    if (k < 0)
        return;

    // members per cluster
    std::vector<std::vector<int>> members;
    members.resize(static_cast<size_t>(k));
    for (size_t i = 0; i < n; ++i)
        members[labels[i]].push_back(int(i));

    db.transaction();
    QSet<int> claimed;
    for (int64_t c = 0; c < k; ++c)
        if (clusterPerson[size_t(c)] >= 0)
            claimed.insert(int(clusterPerson[size_t(c)]));
    QSqlQuery setPerson(db), newPerson(db);
    setPerson.prepare(QStringLiteral("UPDATE faces SET person_id=? WHERE id=? AND confirmed=0"));
    for (int64_t c = 0; c < k; ++c) {
        const auto &mem = members[size_t(c)];
        QVariant pid;
        if (clusterPerson[size_t(c)] >= 0) {
            pid = int(clusterPerson[size_t(c)]);
        } else if (mem.size() >= 2) {
            // keep the id this group had before, so names and links survive
            std::map<int, int> votes;
            for (int i : mem)
                if (rows[i].person >= 0 && !claimed.contains(rows[i].person))
                    ++votes[rows[i].person];
            int best = -1, bestVotes = 0;
            for (auto [p, v] : votes)
                if (v > bestVotes)
                    best = p, bestVotes = v;
            if (best < 0) {
                newPerson.exec(QStringLiteral("INSERT INTO persons (name) VALUES (NULL)"));
                best = newPerson.lastInsertId().toInt();
            }
            claimed.insert(best);
            pid = best;
        }
        for (int i : mem) {
            setPerson.addBindValue(pid);
            setPerson.addBindValue(rows[i].id);
            setPerson.exec();
        }
    }
    QSqlQuery tidy(db);
    tidy.exec(QStringLiteral(
        "DELETE FROM persons WHERE name IS NULL AND id NOT IN (SELECT DISTINCT person_id FROM faces WHERE person_id IS NOT NULL)"));
    // cover: keep a valid user choice, else the best-scoring face
    tidy.exec(QStringLiteral(
        "UPDATE persons SET cover_face_id = (SELECT f.id FROM faces f WHERE f.person_id = persons.id "
        "ORDER BY f.confirmed DESC, f.score * f.w DESC LIMIT 1) "
        "WHERE cover_face_id IS NULL OR cover_face_id NOT IN (SELECT id FROM faces WHERE person_id = persons.id)"));
    db.commit();
}

void LibraryAnalyzer::recluster() {
    if (m_running) {
        m_restart = true;
        return;
    }
    m_running = true;
    emit runningChanged();
    m_loop = QtConcurrent::run([this] {
        reclusterNow();
        QMetaObject::invokeMethod(this, [this] {
            m_running = false;
            emit runningChanged();
            bump();
        }, Qt::QueuedConnection);
    });
}

void LibraryAnalyzer::setThreshold(double t) {
    t = std::clamp(t, 0.2, 0.8);
    if (std::abs(t - m_threshold) < 1e-4)
        return;
    m_threshold = t;
    setSetting(QStringLiteral("faces_threshold"), QString::number(t));
    emit thresholdChanged();
    recluster();
}

QVariantMap LibraryAnalyzer::previewThreshold(double t) {
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT f.confirmed, COALESCE(f.person_id,-1), f.excluded_person, f.embedding FROM faces f "
                          "JOIN media m ON m.id = f.media_id WHERE %1 ORDER BY f.confirmed DESC, f.score DESC")
               .arg(QLatin1String(kAlive)));
    std::vector<float> embs;
    std::vector<int64_t> fixed, exclude;
    while (q.next()) {
        const QByteArray e = q.value(3).toByteArray();
        if (e.size() != int(KF_EMBED_DIM * sizeof(float)))
            continue;
        fixed.push_back(q.value(0).toBool() ? q.value(1).toInt() : -1);
        exclude.push_back(q.value(2).toInt());
        const auto *f = reinterpret_cast<const float *>(e.constData());
        embs.insert(embs.end(), f, f + KF_EMBED_DIM);
    }
    const size_t n = fixed.size();
    std::vector<uint32_t> labels(n);
    std::vector<int64_t> cp(n);
    const int64_t k = n ? kf_cluster(embs.data(), n, fixed.data(), exclude.data(), float(t), labels.data(), cp.data()) : 0;
    std::vector<int> size(size_t(std::max<int64_t>(k, 0)));
    for (uint32_t l : labels)
        ++size[l];
    int groups = 0, grouped = 0;
    for (int s : size)
        if (s >= 2)
            ++groups, grouped += s;
    return {{QStringLiteral("groups"), groups}, {QStringLiteral("grouped"), grouped}, {QStringLiteral("faces"), int(n)}};
}

// ── people ───────────────────────────────────────────────────────────────────

QVariantList LibraryAnalyzer::people(bool includeHidden) {
    QVariantList out;
    if (!m_facesEnabled)
        return out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral(
        "SELECT p.id, p.name, p.hidden, p.cover_face_id, COUNT(f.id) AS faces, COUNT(DISTINCT f.media_id) AS photos "
        "FROM persons p JOIN faces f ON f.person_id = p.id JOIN media m ON m.id = f.media_id "
        "WHERE %1 %2 GROUP BY p.id HAVING faces >= 2 OR p.name IS NOT NULL "
        "ORDER BY (p.name IS NULL), photos DESC")
               .arg(QLatin1String(kAlive), includeHidden ? QString() : QStringLiteral("AND p.hidden = 0")));
    while (q.next()) {
        out << QVariantMap{{QStringLiteral("id"), q.value(0)},
                           {QStringLiteral("name"), q.value(1).toString()},
                           {QStringLiteral("hidden"), q.value(2).toBool()},
                           {QStringLiteral("cover"), q.value(3)},
                           {QStringLiteral("faces"), q.value(4)},
                           {QStringLiteral("photos"), q.value(5)}};
    }
    return out;
}

QVariantMap LibraryAnalyzer::person(int id) {
    for (const QVariant &v : people(true))
        if (v.toMap().value(QStringLiteral("id")).toInt() == id)
            return v.toMap();
    return {};
}

QVariantList LibraryAnalyzer::personFaces(int id) {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("SELECT f.id, f.media_id, f.score, f.confirmed FROM faces f JOIN media m ON m.id = f.media_id "
                             "WHERE f.person_id = ? AND %1 ORDER BY f.confirmed DESC, f.score DESC")
                  .arg(QLatin1String(kAlive)));
    q.addBindValue(id);
    q.exec();
    while (q.next())
        out << QVariantMap{{QStringLiteral("faceId"), q.value(0)},
                           {QStringLiteral("mediaId"), q.value(1)},
                           {QStringLiteral("score"), q.value(2)},
                           {QStringLiteral("confirmed"), q.value(3).toBool()}};
    return out;
}

QVariantList LibraryAnalyzer::personMedia(int id) {
    return mediaWhere(QStringLiteral("m.id IN (SELECT media_id FROM faces WHERE person_id = ?)"), {id});
}

QVariantList LibraryAnalyzer::suggestedFaces(int id, int limit) {
    QSqlDatabase db = m_db->threadDb();
    // the person's centroid
    std::vector<float> c(KF_EMBED_DIM, 0.f);
    {
        QSqlQuery q(db);
        q.prepare(QStringLiteral("SELECT embedding FROM faces WHERE person_id = ?"));
        q.addBindValue(id);
        q.exec();
        while (q.next()) {
            const QByteArray e = q.value(0).toByteArray();
            if (e.size() != int(KF_EMBED_DIM * sizeof(float)))
                continue;
            const auto *f = reinterpret_cast<const float *>(e.constData());
            for (int i = 0; i < KF_EMBED_DIM; ++i)
                c[size_t(i)] += f[i];
        }
    }
    float norm = 0;
    for (float v : c)
        norm += v * v;
    norm = std::sqrt(norm);
    if (norm < 1e-6f)
        return {};
    for (float &v : c)
        v /= norm;

    // faces not in a named person, most similar first
    struct S {
        int face, media;
        float sim;
    };
    std::vector<S> cand;
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT f.id, f.media_id, f.embedding FROM faces f JOIN media m ON m.id = f.media_id "
        "LEFT JOIN persons p ON p.id = f.person_id "
        "WHERE %1 AND COALESCE(f.person_id,-1) != ? AND f.excluded_person != ? AND (p.id IS NULL OR p.name IS NULL)")
                  .arg(QLatin1String(kAlive)));
    q.addBindValue(id);
    q.addBindValue(id);
    q.exec();
    while (q.next()) {
        const QByteArray e = q.value(2).toByteArray();
        if (e.size() != int(KF_EMBED_DIM * sizeof(float)))
            continue;
        const auto *f = reinterpret_cast<const float *>(e.constData());
        float s = 0;
        for (int i = 0; i < KF_EMBED_DIM; ++i)
            s += f[i] * c[size_t(i)];
        if (s >= float(m_threshold) - 0.15f)
            cand.push_back({q.value(0).toInt(), q.value(1).toInt(), s});
    }
    std::sort(cand.begin(), cand.end(), [](const S &a, const S &b) { return a.sim > b.sim; });
    QVariantList out;
    for (size_t i = 0; i < cand.size() && int(i) < limit; ++i)
        out << QVariantMap{{QStringLiteral("faceId"), cand[i].face},
                           {QStringLiteral("mediaId"), cand[i].media},
                           {QStringLiteral("similarity"), double(cand[i].sim)}};
    return out;
}

void LibraryAnalyzer::renamePerson(int id, const QString &name) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare(QStringLiteral("UPDATE persons SET name = ? WHERE id = ?"));
    const QString n = name.trimmed();
    q.addBindValue(n.isEmpty() ? QVariant() : QVariant(n));
    q.addBindValue(id);
    q.exec();
    // naming a group vouches for its faces: they anchor this person from now on
    if (!n.isEmpty()) {
        QSqlQuery c(db);
        c.prepare(QStringLiteral("UPDATE faces SET confirmed = 1 WHERE person_id = ?"));
        c.addBindValue(id);
        c.exec();
    }
    bump();
}

void LibraryAnalyzer::setPersonHidden(int id, bool hidden) {
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("UPDATE persons SET hidden = ? WHERE id = ?"));
    q.addBindValue(hidden ? 1 : 0);
    q.addBindValue(id);
    q.exec();
    bump();
}

void LibraryAnalyzer::forgetPerson(int id) {
    QSqlDatabase db = m_db->threadDb();
    db.transaction();
    QSqlQuery q(db);
    q.prepare(QStringLiteral("DELETE FROM faces WHERE person_id = ?"));
    q.addBindValue(id);
    q.exec();
    q.prepare(QStringLiteral("DELETE FROM persons WHERE id = ?"));
    q.addBindValue(id);
    q.exec();
    db.commit();
    bump();
}

void LibraryAnalyzer::removeFaces(const QVariantList &faceIds) {
    QSqlDatabase db = m_db->threadDb();
    db.transaction();
    QSqlQuery q(db);
    q.prepare(QStringLiteral("UPDATE faces SET excluded_person = COALESCE(person_id,-1), person_id = NULL, confirmed = 0 "
                             "WHERE id = ?"));
    for (const QVariant &id : faceIds) {
        q.addBindValue(id.toInt());
        q.exec();
    }
    db.commit();
    // Show the change now: recluster() is deferred while the library is
    // being analysed, which left removed faces on screen until it finished.
    bump();
    recluster();
}

void LibraryAnalyzer::assignFaces(const QVariantList &faceIds, int personId) {
    QSqlDatabase db = m_db->threadDb();
    db.transaction();
    QSqlQuery q(db);
    q.prepare(QStringLiteral("UPDATE faces SET person_id = ?, confirmed = 1, excluded_person = -1 WHERE id = ?"));
    for (const QVariant &id : faceIds) {
        q.addBindValue(personId);
        q.addBindValue(id.toInt());
        q.exec();
    }
    db.commit();
    bump();
    recluster();
}

namespace {
QString idList(const QVariantList &ids) {
    QStringList out;
    for (const QVariant &v : ids)
        out << QString::number(v.toInt());
    return out.join(QLatin1Char(','));
}
} // namespace

void LibraryAnalyzer::removePersonFromMedia(int personId, const QVariantList &mediaIds) {
    if (mediaIds.isEmpty())
        return;
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("SELECT id FROM faces WHERE person_id = ? AND media_id IN (%1)").arg(idList(mediaIds)));
    q.addBindValue(personId);
    q.exec();
    QVariantList faces;
    while (q.next())
        faces << q.value(0);
    removeFaces(faces);
}

void LibraryAnalyzer::discardPersonFacesInMedia(int personId, const QVariantList &mediaIds) {
    if (mediaIds.isEmpty())
        return;
    // Not a face (a mask, a poster, a statue…): forget the detection. The
    // photo stays analysed, so it isn't detected again.
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("DELETE FROM faces WHERE person_id = ? AND media_id IN (%1)").arg(idList(mediaIds)));
    q.addBindValue(personId);
    q.exec();
    bump();
    recluster();
}

// ── review deck ───────────────────────────────────────────────────────────

namespace {
// Unit-length mean embedding of a person's faces (empty if none).
std::vector<float> personCentroid(QSqlDatabase &db, int personId) {
    std::vector<float> c(KF_EMBED_DIM, 0.f);
    QSqlQuery q(db);
    q.prepare(QStringLiteral("SELECT embedding FROM faces WHERE person_id = ?"));
    q.addBindValue(personId);
    q.exec();
    int n = 0;
    while (q.next()) {
        const QByteArray e = q.value(0).toByteArray();
        if (e.size() != int(KF_EMBED_DIM * sizeof(float)))
            continue;
        const auto *f = reinterpret_cast<const float *>(e.constData());
        for (int i = 0; i < KF_EMBED_DIM; ++i)
            c[size_t(i)] += f[i];
        ++n;
    }
    float norm = 0;
    for (float v : c)
        norm += v * v;
    norm = std::sqrt(norm);
    if (n == 0 || norm < 1e-6f)
        return {};
    for (float &v : c)
        v /= norm;
    return c;
}

float dotEmb(const QByteArray &e, const std::vector<float> &c) {
    const auto *f = reinterpret_cast<const float *>(e.constData());
    float s = 0;
    for (int i = 0; i < KF_EMBED_DIM; ++i)
        s += f[i] * c[size_t(i)];
    return s;
}

QVector<double> readSims(const QString &csv) {
    QVector<double> out;
    for (const QString &p : csv.split(QLatin1Char(','), Qt::SkipEmptyParts))
        out << p.toDouble();
    return out;
}
QString writeSims(QVector<double> v) {
    if (v.size() > 400)              // keep the most recent answers
        v.remove(0, v.size() - 400);
    QStringList out;
    for (double d : v)
        out << QString::number(d, 'f', 4);
    return out.join(QLatin1Char(','));
}
} // namespace

QVariantList LibraryAnalyzer::reviewQueue(int personId, int limit) {
    QVariantList out;
    if (!m_facesEnabled || limit <= 0)
        return out;
    QList<QPair<int, QString>> targets;
    if (personId >= 0) {
        targets << qMakePair(personId, person(personId).value(QStringLiteral("name")).toString());
    } else {
        const QVariantList ps = people(false);
        for (int i = 0; i < ps.size() && targets.size() < 6; ++i) {
            const QVariantMap p = ps[i].toMap();
            targets << qMakePair(p.value(QStringLiteral("id")).toInt(), p.value(QStringLiteral("name")).toString());
        }
    }
    if (targets.isEmpty())
        return out;
    const int per = std::max(4, limit / int(targets.size()));
    const float thr = float(m_threshold);
    QSqlDatabase db = m_db->threadDb();

    struct Card {
        int face;
        QString path;
        float sim;
        bool in;
    };
    QList<QVariantList> decks;
    for (const auto &[pid, pname] : std::as_const(targets)) {
        const std::vector<float> c = personCentroid(db, pid);
        if (c.empty())
            continue;
        std::vector<Card> mine, others;
        QSqlQuery q(db);
        // the person's unconfirmed faces, least typical first
        q.prepare(QStringLiteral("SELECT f.id, m.file_path, f.embedding FROM faces f JOIN media m ON m.id = f.media_id "
                                 "WHERE %1 AND f.person_id = ? AND f.confirmed = 0").arg(QLatin1String(kAlive)));
        q.addBindValue(pid);
        q.exec();
        while (q.next()) {
            const QByteArray e = q.value(2).toByteArray();
            if (e.size() == int(KF_EMBED_DIM * sizeof(float)))
                mine.push_back({q.value(0).toInt(), q.value(1).toString(), dotEmb(e, c), true});
        }
        // look-alikes outside the person, closest to the line first
        q.prepare(QStringLiteral("SELECT f.id, m.file_path, f.embedding FROM faces f JOIN media m ON m.id = f.media_id "
                                 "WHERE %1 AND COALESCE(f.person_id,-1) != ? AND f.excluded_person != ? AND f.confirmed = 0")
                      .arg(QLatin1String(kAlive)));
        q.addBindValue(pid);
        q.addBindValue(pid);
        q.exec();
        while (q.next()) {
            const QByteArray e = q.value(2).toByteArray();
            if (e.size() != int(KF_EMBED_DIM * sizeof(float)))
                continue;
            const float s = dotEmb(e, c);
            if (s >= thr - 0.15f)
                others.push_back({q.value(0).toInt(), q.value(1).toString(), s, false});
        }
        std::sort(mine.begin(), mine.end(), [](const Card &a, const Card &b) { return a.sim < b.sim; });
        std::sort(others.begin(), others.end(), [thr](const Card &a, const Card &b) {
            return std::abs(a.sim - thr) < std::abs(b.sim - thr);
        });
        // alternate the two kinds so the answers aren't all "yes" then "no"
        QVariantList deck;
        size_t a = 0, b = 0;
        while (deck.size() < per && (a < mine.size() || b < others.size())) {
            const bool takeMine = (deck.size() % 2 == 0 && a < mine.size()) || b >= others.size();
            const Card &cd = takeMine ? mine[a++] : others[b++];
            deck << QVariantMap{{QStringLiteral("faceId"), cd.face},
                                {QStringLiteral("personId"), pid},
                                {QStringLiteral("personName"), pname},
                                {QStringLiteral("personCover"), person(pid).value(QStringLiteral("cover"))},
                                {QStringLiteral("similarity"), double(cd.sim)},
                                {QStringLiteral("inPerson"), cd.in},
                                {QStringLiteral("thumb"), ThumbnailGenerator::thumbnailUrl(cd.path)}};
        }
        decks << deck;
    }
    // interleave people for the "everyone" deck
    for (int i = 0; out.size() < limit; ++i) {
        bool any = false;
        for (const QVariantList &d : std::as_const(decks))
            if (i < d.size() && out.size() < limit) {
                out << d[i];
                any = true;
            }
        if (!any)
            break;
    }
    return out;
}

void LibraryAnalyzer::answerReview(int faceId, int personId, bool same, double similarity) {
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    if (same) {
        q.prepare(QStringLiteral("UPDATE faces SET person_id = ?, confirmed = 1, excluded_person = -1 WHERE id = ?"));
        q.addBindValue(personId);
        q.addBindValue(faceId);
    } else {
        // out of this person (if it was in), and never grouped back into them
        q.prepare(QStringLiteral("UPDATE faces SET excluded_person = ?, "
                                 "person_id = CASE WHEN person_id = ? THEN NULL ELSE person_id END, "
                                 "confirmed = CASE WHEN person_id = ? THEN 0 ELSE confirmed END WHERE id = ?"));
        q.addBindValue(personId);
        q.addBindValue(personId);
        q.addBindValue(personId);
        q.addBindValue(faceId);
    }
    q.exec();
    // every answer is a labelled example for the threshold
    const QString key = same ? QStringLiteral("faces_review_yes") : QStringLiteral("faces_review_no");
    QVector<double> sims = readSims(setting(key, QString()));
    sims << similarity;
    setSetting(key, writeSims(sims));
    ++m_reviewAnswered;
}

QVariantMap LibraryAnalyzer::finishReview() {
    QVariantMap res{{QStringLiteral("answered"), m_reviewAnswered},
                    {QStringLiteral("threshold"), m_threshold},
                    {QStringLiteral("changed"), false}};
    if (m_reviewAnswered == 0)
        return res;
    m_reviewAnswered = 0;
    QVector<double> yes = readSims(setting(QStringLiteral("faces_review_yes"), QString()));
    QVector<double> no = readSims(setting(QStringLiteral("faces_review_no"), QString()));
    const double before = m_threshold;
    if (!yes.isEmpty() && !no.isEmpty()) {
        // the similarity that best separates "same person" from "not": try
        // every cut between the answers, keep the one with fewest mistakes
        QVector<double> all = yes + no;
        std::sort(all.begin(), all.end());
        double best = m_threshold;
        int bestErr = INT_MAX;
        for (int i = 0; i + 1 < all.size(); ++i) {
            const double cut = (all[i] + all[i + 1]) / 2;
            int err = 0;
            for (double y : std::as_const(yes))
                err += y < cut;
            for (double n : std::as_const(no))
                err += n >= cut;
            if (err < bestErr || (err == bestErr && std::abs(cut - m_threshold) < std::abs(best - m_threshold)))
                bestErr = err, best = cut;
        }
        // trust grows with the number of answers; move gradually
        const double w = std::min(0.8, double(yes.size() + no.size()) / 60.0);
        const double t = std::clamp(m_threshold * (1 - w) + best * w, 0.25, 0.6);
        if (std::abs(t - m_threshold) >= 0.005) {
            setThreshold(t);          // re-groups
            res.insert(QStringLiteral("threshold"), m_threshold);
            res.insert(QStringLiteral("changed"), std::abs(m_threshold - before) >= 0.005);
            bump();
            return res;
        }
    }
    bump();
    recluster();
    return res;
}

int LibraryAnalyzer::newPerson(const QVariantList &faceIds, const QString &name) {
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("INSERT INTO persons (name) VALUES (?)"));
    const QString n = name.trimmed();
    q.addBindValue(n.isEmpty() ? QVariant() : QVariant(n));
    q.exec();
    const int id = q.lastInsertId().toInt();
    assignFaces(faceIds, id);
    return id;
}

void LibraryAnalyzer::mergePeople(int from, int into) {
    if (from == into)
        return;
    QSqlDatabase db = m_db->threadDb();
    db.transaction();
    QSqlQuery q(db);
    q.prepare(QStringLiteral("UPDATE faces SET person_id = ?, confirmed = 1 WHERE person_id = ?"));
    q.addBindValue(into);
    q.addBindValue(from);
    q.exec();
    q.prepare(QStringLiteral("UPDATE persons SET name = COALESCE(name, (SELECT name FROM persons WHERE id = ?)) WHERE id = ?"));
    q.addBindValue(from);
    q.addBindValue(into);
    q.exec();
    q.prepare(QStringLiteral("DELETE FROM persons WHERE id = ?"));
    q.addBindValue(from);
    q.exec();
    db.commit();
    recluster();
}

void LibraryAnalyzer::setCover(int personId, int faceId) {
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("UPDATE persons SET cover_face_id = ? WHERE id = ?"));
    q.addBindValue(faceId);
    q.addBindValue(personId);
    q.exec();
    bump();
}

QImage LibraryAnalyzer::faceImage(int faceId, int size) {
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("SELECT m.file_path, f.x, f.y, f.w, f.h FROM faces f JOIN media m ON m.id = f.media_id WHERE f.id = ?"));
    q.addBindValue(faceId);
    if (!q.exec() || !q.next())
        return {};
    const QString thumb = m_thumbs->getOrCreateThumbnail(q.value(0).toString(), kThumb);
    QImage img(thumb);
    if (img.isNull())
        return {};
    const double W = img.width(), H = img.height();
    const double cx = (q.value(1).toDouble() + q.value(3).toDouble() / 2) * W;
    const double cy = (q.value(2).toDouble() + q.value(4).toDouble() / 2) * H;
    // square crop with room for hair and chin
    const double side = std::max(q.value(3).toDouble() * W, q.value(4).toDouble() * H) * 1.6;
    QRect r(int(cx - side / 2), int(cy - side / 2), int(side), int(side));
    r = r.intersected(img.rect());
    if (r.isEmpty())
        return {};
    return img.copy(r).scaled(size, size, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
}

QImage FaceImageProvider::requestImage(const QString &id, QSize *size, const QSize &requested) {
    const int s = requested.isValid() ? std::max(requested.width(), requested.height()) : 192;
    // ids may carry a cache-busting "?rev" suffix
    const QImage img = m_analyzer->faceImage(id.section(QLatin1Char('?'), 0, 0).toInt(), std::clamp(s, 32, 512));
    if (size)
        *size = img.size();
    return img;
}

// ── explore ──────────────────────────────────────────────────────────────────

QVariantList LibraryAnalyzer::mediaWhere(const QString &where, const QVariantList &binds, const QString &order, int limit) {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.prepare(QStringLiteral("SELECT m.* FROM media m WHERE %1 AND (%2) ORDER BY %3 LIMIT %4")
                  .arg(QLatin1String(kAlive), where, order)
                  .arg(limit));
    for (const QVariant &b : binds)
        q.addBindValue(b);
    if (!q.exec()) {
        qWarning() << "LibraryAnalyzer query failed:" << q.lastError().text();
        return out;
    }
    const QSqlRecord rec = q.record();
    while (q.next())
        out << rowToMedia(q, rec);
    return out;
}

QVariantList LibraryAnalyzer::mediaByIds(const QVariantList &ids) {
    if (ids.isEmpty())
        return {};
    const QVariantList head = ids.mid(0, 2000);
    QVariantList rows = mediaWhere(QStringLiteral("m.id IN (%1)").arg(placeholders(int(head.size()))), head);
    // keep the caller's order (relevance)
    QHash<int, QVariant> byId;
    for (const QVariant &r : rows)
        byId.insert(r.toMap().value(QStringLiteral("id")).toInt(), r);
    QVariantList out;
    for (const QVariant &id : head)
        if (byId.contains(id.toInt()))
            out << byId.value(id.toInt());
    return out;
}

QVariantList LibraryAnalyzer::colorGroups() {
    QVariantList out;
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT a.color_bucket, COUNT(*) FROM media_analysis a JOIN media m ON m.id = a.media_id "
                          "WHERE %1 AND a.color_bucket > 0 GROUP BY a.color_bucket HAVING COUNT(*) >= 3 "
                          "ORDER BY COUNT(*) DESC")
               .arg(QLatin1String(kAlive)));
    while (q.next()) {
        const int b = q.value(0).toInt();
        QVariantList covers;
        QColor swatch;
        QSqlQuery c(m_db->threadDb());
        c.prepare(QStringLiteral("SELECT m.file_path, a.palette FROM media_analysis a JOIN media m ON m.id = a.media_id "
                                 "WHERE %1 AND a.color_bucket = ? ORDER BY a.color_frac DESC LIMIT 4")
                      .arg(QLatin1String(kAlive)));
        c.addBindValue(b);
        c.exec();
        while (c.next()) {
            covers << ThumbnailGenerator::thumbnailUrl(c.value(0).toString());
            const QByteArray p = c.value(1).toByteArray();
            if (!swatch.isValid() && p.size() >= 3)
                swatch = QColor(uchar(p[0]), uchar(p[1]), uchar(p[2]));
        }
        out << QVariantMap{{QStringLiteral("bucket"), b},
                           {QStringLiteral("name"), bucketName(b)},
                           {QStringLiteral("count"), q.value(1)},
                           {QStringLiteral("covers"), covers},
                           {QStringLiteral("swatch"), swatch}};
    }
    return out;
}

QVariantList LibraryAnalyzer::colorMedia(int bucket) {
    return mediaWhere(QStringLiteral("m.id IN (SELECT media_id FROM media_analysis WHERE color_bucket = ?)"), {bucket},
                      QStringLiteral("(SELECT color_frac FROM media_analysis WHERE media_id = m.id) DESC"));
}

void LibraryAnalyzer::ensurePlaces() {
    if (!m_world) {
        if (!m_worldRequested) {
            m_worldRequested = true;
            auto *w = new QFutureWatcher<KgWorld *>(this);
            connect(w, &QFutureWatcher<KgWorld *>::finished, this, [this, w] {
                m_world = w->result();
                w->deleteLater();
                if (m_world)
                    bump();
            });
            w->setFuture(kaderWorld());
        }
        return;
    }
    if (m_placesRevision >= 0)
        return;
    m_placeOf.clear();
    QSqlQuery q(m_db->threadDb());
    q.exec(QStringLiteral("SELECT m.id, m.latitude, m.longitude FROM media m WHERE %1 AND m.latitude IS NOT NULL "
                          "AND m.longitude IS NOT NULL AND NOT (m.latitude = 0 AND m.longitude = 0)")
               .arg(QLatin1String(kAlive)));
    while (q.next()) {
        const QString p = placeOf(q.value(1).toDouble(), q.value(2).toDouble());
        if (!p.isEmpty())
            m_placeOf.insert(q.value(0).toInt(), p);
    }
    m_placesRevision = m_revision;
}

QString LibraryAnalyzer::placeOf(double lat, double lon, double maxKm) const {
    if (!m_world)
        return {};
    char buf[256];
    const size_t n = kg_world_place_name(m_world, lat, lon, maxKm, reinterpret_cast<uint8_t *>(buf), sizeof buf, nullptr);
    return QString::fromUtf8(buf, qsizetype(n));
}

QVariantList LibraryAnalyzer::places(int limit) {
    ensurePlaces();
    QHash<QString, QVector<int>> by;
    for (auto it = m_placeOf.cbegin(); it != m_placeOf.cend(); ++it)
        by[it.value()].push_back(it.key());
    QVector<QPair<QString, QVector<int>>> sorted;
    for (auto it = by.cbegin(); it != by.cend(); ++it)
        sorted.push_back({it.key(), it.value()});
    std::sort(sorted.begin(), sorted.end(), [](const auto &a, const auto &b) { return a.second.size() > b.second.size(); });
    QVariantList out;
    for (const auto &[name, ids] : sorted) {
        if (out.size() >= limit)
            break;
        const QVariantList cover = mediaByIds({ids.first()});
        out << QVariantMap{{QStringLiteral("name"), name},
                           {QStringLiteral("count"), int(ids.size())},
                           {QStringLiteral("cover"), cover.isEmpty() ? QVariant() : cover.first().toMap().value(QStringLiteral("thumb"))}};
    }
    return out;
}

QVariantList LibraryAnalyzer::placeMedia(const QString &name) {
    ensurePlaces();
    QVariantList ids;
    for (auto it = m_placeOf.cbegin(); it != m_placeOf.cend(); ++it)
        if (it.value() == name)
            ids << it.key();
    QVariantList rows = mediaByIds(ids);
    std::sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("creation_date")).toLongLong() >
               b.toMap().value(QStringLiteral("creation_date")).toLongLong();
    });
    return rows;
}

QVariantList LibraryAnalyzer::memories() {
    QVariantList out;
    QSqlDatabase db = m_db->threadDb();
    const QDate today = QDate::currentDate();

    auto coversOf = [](const QVariantList &media) {
        QVariantList c;
        for (const QVariant &m : media.mid(0, 4))
            c << m.toMap().value(QStringLiteral("thumb"));
        return c;
    };

    // On this day: ±3 days around today's date, in earlier years
    {
        QSqlQuery q(db);
        q.prepare(QStringLiteral(
            "SELECT CAST(strftime('%Y', m.creation_date, 'unixepoch', 'localtime') AS INTEGER) AS y, COUNT(*) FROM media m "
            "WHERE %1 AND m.creation_date > 0 "
            "AND abs(julianday(date(m.creation_date, 'unixepoch', 'localtime')) - "
            "        julianday(strftime('%Y', m.creation_date, 'unixepoch', 'localtime') || ?)) <= 3 "
            "AND CAST(strftime('%Y', m.creation_date, 'unixepoch', 'localtime') AS INTEGER) < ? "
            "GROUP BY y HAVING COUNT(*) >= 2 ORDER BY y DESC")
                      .arg(QLatin1String(kAlive)));
        q.addBindValue(today.toString(QStringLiteral("-MM-dd")));
        q.addBindValue(today.year());
        q.exec();
        while (q.next()) {
            const int y = q.value(0).toInt();
            const QString key = QStringLiteral("otd:%1").arg(y);
            QDate d(y, today.month(), today.day());
            if (!d.isValid()) // 29 February in a common year
                d = QDate(y, 2, 28);
            out << QVariantMap{{QStringLiteral("key"), key},
                               {QStringLiteral("kind"), QStringLiteral("onthisday")},
                               {QStringLiteral("years"), today.year() - y},
                               {QStringLiteral("subtitle"), QLocale().toString(d, QStringLiteral("d MMMM yyyy"))},
                               {QStringLiteral("count"), q.value(1)},
                               {QStringLiteral("covers"), coversOf(memoryMedia(key))}};
        }
    }

    // Trips: runs of geotagged photos far from home
    ensurePlaces();
    if (m_world) {
        struct P {
            int id;
            qint64 t;
            double lat, lon;
        };
        QVector<P> pts;
        QSqlQuery q(db);
        q.exec(QStringLiteral("SELECT m.id, m.creation_date, m.latitude, m.longitude FROM media m WHERE %1 AND "
                              "m.latitude IS NOT NULL AND NOT (m.latitude = 0 AND m.longitude = 0) AND m.creation_date > 0 "
                              "ORDER BY m.creation_date")
                   .arg(QLatin1String(kAlive)));
        while (q.next())
            pts.push_back({q.value(0).toInt(), q.value(1).toLongLong(), q.value(2).toDouble(), q.value(3).toDouble()});
        // home: the most photographed 1° cell
        QHash<QPair<int, int>, int> cells;
        for (const P &p : pts)
            ++cells[{int(std::floor(p.lat)), int(std::floor(p.lon))}];
        QPair<int, int> home{999, 999};
        int homeN = 0;
        for (auto it = cells.cbegin(); it != cells.cend(); ++it)
            if (it.value() > homeN)
                home = it.key(), homeN = it.value();
        auto km = [](double la1, double lo1, double la2, double lo2) {
            const double r = 6371.0, d2r = M_PI / 180.0;
            const double dl = (la2 - la1) * d2r, dn = (lo2 - lo1) * d2r;
            const double a = std::sin(dl / 2) * std::sin(dl / 2) +
                             std::cos(la1 * d2r) * std::cos(la2 * d2r) * std::sin(dn / 2) * std::sin(dn / 2);
            return 2 * r * std::asin(std::min(1.0, std::sqrt(a)));
        };
        const double homeLat = home.first + 0.5, homeLon = home.second + 0.5;
        QVariantList trips;
        int i = 0;
        // with a single location cluster there is no "away"
        const bool haveHome = cells.size() > 1;
        while (haveHome && i < pts.size()) {
            if (km(pts[i].lat, pts[i].lon, homeLat, homeLon) < 120) {
                ++i;
                continue;
            }
            int j = i;
            while (j + 1 < pts.size() && pts[j + 1].t - pts[j].t < 3 * 86400 &&
                   km(pts[j + 1].lat, pts[j + 1].lon, homeLat, homeLon) >= 120)
                ++j;
            if (j - i + 1 >= 4) {
                // name: the town if most photos were taken there, else the
                // country, else the two main countries; ties break by name so
                // the title is stable
                QMap<QString, int> towns, countries;
                for (int k = i; k <= j; ++k) {
                    const QString pl = m_placeOf.value(pts[k].id);
                    if (pl.isEmpty())
                        continue;
                    ++towns[pl];
                    ++countries[pl.section(QStringLiteral(", "), -1)];
                }
                auto top = [](const QMap<QString, int> &m) {
                    QVector<QPair<QString, int>> v;
                    for (auto it = m.cbegin(); it != m.cend(); ++it)
                        v.push_back({it.key(), it.value()});
                    std::stable_sort(v.begin(), v.end(), [](const auto &x, const auto &y) { return x.second > y.second; });
                    return v;
                };
                const auto tt = top(towns), cc = top(countries);
                const int runLen = j - i + 1;
                QString best;
                if (!tt.isEmpty() && tt[0].second * 2 >= runLen)
                    best = tt[0].first.section(QStringLiteral(", "), 0, 0);
                else if (!cc.isEmpty() && (cc.size() == 1 || cc[0].second * 10 >= runLen * 6))
                    best = cc[0].first;
                else if (cc.size() >= 2)
                    best = cc[0].first + QStringLiteral(" & ") + cc[1].first;
                const QDateTime a = QDateTime::fromSecsSinceEpoch(pts[i].t), b = QDateTime::fromSecsSinceEpoch(pts[j].t);
                const QString key = QStringLiteral("trip:%1:%2").arg(pts[i].t).arg(pts[j].t);
                const QVariantList c = coversOf(memoryMedia(key));
                trips.prepend(QVariantMap{{QStringLiteral("key"), key},
                                          {QStringLiteral("kind"), QStringLiteral("trip")},
                                          {QStringLiteral("title"), best},
                                          {QStringLiteral("subtitle"), a.date().toString(QStringLiteral("MMMM yyyy"))},
                                          {QStringLiteral("days"), int(a.daysTo(b)) + 1},
                                          {QStringLiteral("count"), j - i + 1},
                                          {QStringLiteral("covers"), c}});
            }
            i = j + 1;
        }
        out += trips.mid(0, 12);
    }

    // Years
    {
        QSqlQuery q(db);
        q.exec(QStringLiteral("SELECT CAST(strftime('%Y', m.creation_date, 'unixepoch', 'localtime') AS INTEGER) AS y, COUNT(*) "
                              "FROM media m WHERE %1 AND m.creation_date > 0 GROUP BY y HAVING COUNT(*) >= 12 ORDER BY y DESC")
                   .arg(QLatin1String(kAlive)));
        while (q.next()) {
            const int y = q.value(0).toInt();
            const QString key = QStringLiteral("year:%1").arg(y);
            const QVariantList c = coversOf(
                mediaWhere(QStringLiteral("strftime('%Y', m.creation_date, 'unixepoch', 'localtime') = ?"),
                           {QString::number(y)}, QStringLiteral("m.is_favorite DESC, (m.id * 2654435761) % 1000"), 4));
            out << QVariantMap{{QStringLiteral("key"), key},
                               {QStringLiteral("kind"), QStringLiteral("year")},
                               {QStringLiteral("title"), QString::number(y)},
                               {QStringLiteral("count"), q.value(1)},
                               {QStringLiteral("covers"), c}};
        }
    }
    return out;
}

QVariantList LibraryAnalyzer::memoryMedia(const QString &key) {
    const QStringList p = key.split(QLatin1Char(':'));
    if (p.value(0) == QLatin1String("otd")) {
        const QDate today = QDate::currentDate();
        QDate d(p.value(1).toInt(), today.month(), today.day());
        if (!d.isValid())
            d = QDate(p.value(1).toInt(), 2, 28);
        const qint64 mid = QDateTime(d, QTime(12, 0)).toSecsSinceEpoch();
        return mediaWhere(QStringLiteral("m.creation_date BETWEEN ? AND ?"), {mid - 3 * 86400 - 43200, mid + 3 * 86400 + 43200});
    }
    if (p.value(0) == QLatin1String("trip"))
        return mediaWhere(QStringLiteral("m.creation_date BETWEEN ? AND ? AND m.latitude IS NOT NULL"),
                          {p.value(1).toLongLong(), p.value(2).toLongLong()}, QStringLiteral("m.creation_date ASC"));
    if (p.value(0) == QLatin1String("year"))
        return mediaWhere(QStringLiteral("strftime('%Y', m.creation_date, 'unixepoch', 'localtime') = ?"), {p.value(1)});
    return {};
}

QVariantList LibraryAnalyzer::mediaForKey(const QString &key) {
    const QString kind = key.section(QLatin1Char(':'), 0, 0);
    const QString arg = key.section(QLatin1Char(':'), 1);
    if (kind == QLatin1String("person"))
        return personMedia(arg.toInt());
    if (kind == QLatin1String("color"))
        return colorMedia(arg.toInt());
    if (kind == QLatin1String("place"))
        return placeMedia(arg);
    if (kind == QLatin1String("album"))
        return mediaWhere(QStringLiteral("m.folder_path = ?"), {arg});
    if (kind == QLatin1String("video"))
        return mediaWhere(QStringLiteral("m.mime_type LIKE 'video/%'"), {});
    if (kind == QLatin1String("favorite"))
        return mediaWhere(QStringLiteral("m.is_favorite = 1"), {});
    return memoryMedia(key);
}

QVariantMap LibraryAnalyzer::search(const QString &query) {
    const QString ql = query.toLower().simplified();
    QVariantList chips;
    if (ql.isEmpty())
        return {};
    QStringList residual = ql.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    auto consume = [&residual](const QString &phrase) {
        for (const QString &w : phrase.toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts))
            residual.removeOne(w);
    };
    QStringList where;
    QVariantList binds;

    // people (by name, whole words)
    QVariantList personIds;
    for (const QVariant &v : people(true)) {
        const QVariantMap p = v.toMap();
        const QString name = p.value(QStringLiteral("name")).toString().toLower();
        if (name.isEmpty())
            continue;
        const QString first = name.section(QLatin1Char(' '), 0, 0);
        if (ql.contains(name) || (first.size() >= 3 && residual.contains(first))) {
            personIds << p.value(QStringLiteral("id"));
            chips << QVariantMap{{QStringLiteral("kind"), QStringLiteral("person")},
                                 {QStringLiteral("label"), p.value(QStringLiteral("name"))},
                                 {QStringLiteral("key"), QStringLiteral("person:%1").arg(p.value(QStringLiteral("id")).toInt())},
                                 {QStringLiteral("face"), p.value(QStringLiteral("cover"))}};
            consume(ql.contains(name) ? name : first);
        }
    }
    if (!personIds.isEmpty()) {
        where << QStringLiteral("m.id IN (SELECT media_id FROM faces WHERE person_id IN (%1))").arg(placeholders(int(personIds.size())));
        binds += personIds;
    }

    // colours
    static const QHash<QString, int> colourWords = [] {
        QHash<QString, int> h;
        for (int b = 1; b < 13; ++b)
            h.insert(bucketName(b), b);
        h.insert(QStringLiteral("grey"), 12);
        return h;
    }();
    QVariantList colours;
    for (const QString &w : QStringList(residual))
        if (colourWords.contains(w)) {
            colours << colourWords.value(w);
            chips << QVariantMap{{QStringLiteral("kind"), QStringLiteral("color")},
                                 {QStringLiteral("label"), w},
                                 {QStringLiteral("key"), QStringLiteral("color:%1").arg(colourWords.value(w))}};
            residual.removeOne(w);
        }
    if (!colours.isEmpty()) {
        where << QStringLiteral("m.id IN (SELECT media_id FROM media_analysis WHERE color_bucket IN (%1))").arg(placeholders(int(colours.size())));
        binds += colours;
    }

    // years and months
    static const QStringList months = {QStringLiteral("january"), QStringLiteral("february"), QStringLiteral("march"),
                                       QStringLiteral("april"), QStringLiteral("may"), QStringLiteral("june"),
                                       QStringLiteral("july"), QStringLiteral("august"), QStringLiteral("september"),
                                       QStringLiteral("october"), QStringLiteral("november"), QStringLiteral("december")};
    static const QRegularExpression yearRe(QStringLiteral("^(19|20)\\d\\d$"));
    QVariantList years, monthNums;
    for (const QString &w : QStringList(residual)) {
        if (yearRe.match(w).hasMatch()) {
            years << w;
            chips << QVariantMap{{QStringLiteral("kind"), QStringLiteral("year")}, {QStringLiteral("label"), w},
                                 {QStringLiteral("key"), QStringLiteral("year:") + w}};
            residual.removeOne(w);
            continue;
        }
        for (int m = 0; m < 12; ++m)
            if (w.size() >= 3 && months[m].startsWith(w) && (w.size() >= 4 || w == months[m].left(3))) {
                monthNums << QStringLiteral("%1").arg(m + 1, 2, 10, QLatin1Char('0'));
                chips << QVariantMap{{QStringLiteral("kind"), QStringLiteral("month")},
                                     {QStringLiteral("label"), QLocale().monthName(m + 1)}};
                residual.removeOne(w);
                break;
            }
    }
    if (!years.isEmpty()) {
        where << QStringLiteral("strftime('%Y', m.creation_date, 'unixepoch', 'localtime') IN (%1)").arg(placeholders(int(years.size())));
        binds += years;
    }
    if (!monthNums.isEmpty()) {
        where << QStringLiteral("strftime('%m', m.creation_date, 'unixepoch', 'localtime') IN (%1)").arg(placeholders(int(monthNums.size())));
        binds += monthNums;
    }

    // places (city or country names)
    ensurePlaces();
    if (!residual.isEmpty() && !m_placeOf.isEmpty()) {
        const QString rest = residual.join(QLatin1Char(' '));
        QSet<QString> matched;
        QSet<QString> names;
        for (const QString &n : std::as_const(m_placeOf))
            names.insert(n);
        for (const QString &n : names) {
            const QString city = n.section(QStringLiteral(", "), 0, 0).toLower();
            const QString country = n.section(QStringLiteral(", "), -1).toLower();
            if ((city.size() >= 3 && rest.contains(city)) || (country.size() >= 4 && rest.contains(country)))
                matched.insert(n);
        }
        if (!matched.isEmpty()) {
            QVariantList ids;
            QSet<QString> labels;
            for (auto it = m_placeOf.cbegin(); it != m_placeOf.cend(); ++it)
                if (matched.contains(it.value()))
                    ids << it.key();
            for (const QString &n : matched) {
                const QString city = n.section(QStringLiteral(", "), 0, 0).toLower();
                const QString country = n.section(QStringLiteral(", "), -1).toLower();
                const bool byCountry = !rest.contains(city);
                const QString label = byCountry ? n.section(QStringLiteral(", "), -1) : n;
                if (labels.contains(label))
                    continue;
                labels.insert(label);
                chips << QVariantMap{{QStringLiteral("kind"), QStringLiteral("place")}, {QStringLiteral("label"), label},
                                     {QStringLiteral("key"), byCountry ? QString() : QStringLiteral("place:") + n}};
                consume(byCountry ? country : city);
            }
            ids = ids.mid(0, 4000);
            where << QStringLiteral("m.id IN (%1)").arg(placeholders(int(ids.size())));
            binds += ids;
        }
    }

    // albums: folder names
    {
        const QString rest = residual.join(QLatin1Char(' '));
        if (rest.size() >= 3) {
            QSqlQuery q(m_db->threadDb());
            q.prepare(QStringLiteral("SELECT DISTINCT m.folder_path FROM media m WHERE %1 AND lower(m.folder_path) LIKE ? LIMIT 6")
                          .arg(QLatin1String(kAlive)));
            q.addBindValue(QStringLiteral("%/%") + rest + QStringLiteral("%"));
            q.exec();
            while (q.next()) {
                const QString folder = q.value(0).toString();
                const QString leaf = folder.section(QLatin1Char('/'), -1);
                if (!leaf.toLower().contains(rest))
                    continue;
                chips << QVariantMap{{QStringLiteral("kind"), QStringLiteral("album")}, {QStringLiteral("label"), leaf},
                                     {QStringLiteral("key"), QStringLiteral("album:") + folder}};
            }
        }
    }

    QVariantList media;
    const QString rest = residual.join(QLatin1Char(' '));
    if (!where.isEmpty()) {
        media = mediaWhere(where.join(QStringLiteral(" AND ")), binds);
    } else if (!rest.isEmpty()) {
        // nothing structured: file and folder names
        media = mediaWhere(QStringLiteral("lower(m.file_path) LIKE ?"), {QStringLiteral("%") + rest + QStringLiteral("%")},
                           QStringLiteral("m.creation_date DESC"), 600);
    }
    return {{QStringLiteral("chips"), chips}, {QStringLiteral("media"), media},
            {QStringLiteral("residual"), rest}, {QStringLiteral("structured"), !where.isEmpty()}};
}
