#include "SemanticSearchEngine.h"
#include "DatabaseManager.h"

#include <QStandardPaths>
#include <QDir>
#include <QNetworkRequest>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QVariantMap>
#include <QDebug>
#include <QThread>
#include <cmath>
#include <numeric>
#include <thread>

#include <llama.h>
#include <llama-cpp.h>
#include <mtmd.h>
#include <mtmd-helper.h>

// ─── SemanticWorker ───────────────────────────────────────────────────────────

SemanticWorker::SemanticWorker(DatabaseManager *db, QObject *parent)
    : QObject(parent), m_db(db)
{
    llama_log_set([](enum ggml_log_level, const char *, void *) {}, nullptr);
    mtmd_log_set ([](enum ggml_log_level, const char *, void *) {}, nullptr);
}

SemanticWorker::~SemanticWorker()
{
    unloadModel();
}

void SemanticWorker::loadModel(const QString &modelPath, const QString &mmprojPath)
{
    QMutexLocker lk(&m_mutex);
    if (m_model) { emit loaded(true); return; }

    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 99;

    auto *model = llama_model_load_from_file(modelPath.toLocal8Bit().constData(), mparams);
    if (!model) {
        emit workerError("Failed to load model: " + modelPath);
        emit loaded(false);
        return;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx        = 4096;
    cparams.n_batch      = 512;
    cparams.embeddings   = true;
    cparams.pooling_type = LLAMA_POOLING_TYPE_MEAN;
    cparams.n_threads    = (int32_t)std::max(1u, std::thread::hardware_concurrency() / 2);

    // Use non-deprecated API
    auto *ctx = llama_init_from_model(model, cparams);
    if (!ctx) {
        llama_model_free(model);
        emit workerError("Failed to create context");
        emit loaded(false);
        return;
    }

    mtmd_context_params vparams = mtmd_context_params_default();
    vparams.use_gpu       = true;
    vparams.print_timings = false;

    auto *mctx = mtmd_init_from_file(mmprojPath.toLocal8Bit().constData(), model, vparams);
    if (!mctx) {
        llama_free(ctx);
        llama_model_free(model);
        emit workerError("Failed to load mmproj: " + mmprojPath);
        emit loaded(false);
        return;
    }

    m_model = model;
    m_ctx   = ctx;
    m_mtmd  = mctx;
    m_nEmbd = llama_model_n_embd(model);
    emit loaded(true);
}

void SemanticWorker::unloadModel()
{
    QMutexLocker lk(&m_mutex);
    if (m_mtmd)  { mtmd_free(static_cast<mtmd_context*>(m_mtmd));        m_mtmd  = nullptr; }
    if (m_ctx)   { llama_free(static_cast<llama_context*>(m_ctx));       m_ctx   = nullptr; }
    if (m_model) { llama_model_free(static_cast<llama_model*>(m_model)); m_model = nullptr; }
    llama_backend_free();
    emit unloaded();
}

static void clearKV(llama_context *ctx)
{
    llama_memory_t mem = llama_get_memory(ctx);
    if (mem) llama_memory_clear(mem, false);
}

std::vector<float> SemanticWorker::embedImage(const QString &imagePath)
{
    auto *model = static_cast<llama_model   *>(m_model);
    auto *ctx   = static_cast<llama_context *>(m_ctx);
    auto *mctx  = static_cast<mtmd_context  *>(m_mtmd);
    Q_UNUSED(model)

    auto *bmp = mtmd_helper_bitmap_init_from_file(mctx, imagePath.toLocal8Bit().constData());
    if (!bmp) return {};

    const char *marker = mtmd_default_marker();
    std::string prompt(marker);

    mtmd_input_text txt { prompt.c_str(), true, true };
    const mtmd_bitmap *bmps[] = { bmp };

    auto *chunks = mtmd_input_chunks_init();
    if (mtmd_tokenize(mctx, chunks, &txt, bmps, 1) != 0) {
        mtmd_input_chunks_free(chunks);
        mtmd_bitmap_free(bmp);
        return {};
    }

    clearKV(ctx);
    llama_pos n_past = 0;
    int32_t ret = mtmd_helper_eval_chunks(mctx, ctx, chunks, n_past, 0, 512, true, &n_past);

    std::vector<float> result;
    if (ret == 0) {
        float *embd = llama_get_embeddings_seq(ctx, 0);
        if (embd && m_nEmbd > 0) {
            result.assign(embd, embd + m_nEmbd);
            float norm = 0.f;
            for (float v : result) norm += v * v;
            norm = std::sqrt(norm);
            if (norm > 1e-9f) for (float &v : result) v /= norm;
        }
    }

    mtmd_input_chunks_free(chunks);
    mtmd_bitmap_free(bmp);
    return result;
}

std::vector<float> SemanticWorker::embedText(const QString &text)
{
    auto *model = static_cast<llama_model   *>(m_model);
    auto *ctx   = static_cast<llama_context *>(m_ctx);
    const llama_vocab *vocab = llama_model_get_vocab(model);

    std::string str = text.toStdString();
    std::vector<llama_token> tokens((int)str.size() + 64);
    int n = llama_tokenize(vocab, str.c_str(), (int)str.size(),
                           tokens.data(), (int)tokens.size(), true, false);
    if (n <= 0) return {};
    tokens.resize((size_t)n);

    llama_batch batch = llama_batch_init(n, 0, 1);
    batch.n_tokens = n;
    for (int i = 0; i < n; i++) {
        batch.token[i]     = tokens[(size_t)i];
        batch.pos[i]       = (llama_pos)i;
        batch.n_seq_id[i]  = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i]    = (i == n - 1) ? 1 : 0;
    }

    clearKV(ctx);
    llama_decode(ctx, batch);
    llama_batch_free(batch);

    float *embd = llama_get_embeddings_seq(ctx, 0);
    std::vector<float> result;
    if (embd && m_nEmbd > 0) {
        result.assign(embd, embd + m_nEmbd);
        float norm = 0.f;
        for (float v : result) norm += v * v;
        norm = std::sqrt(norm);
        if (norm > 1e-9f) for (float &v : result) v /= norm;
    }
    return result;
}

void SemanticWorker::generateTextEmbedding(const QString &text, int queryId)
{
    QMutexLocker lk(&m_mutex);
    if (!m_model) return;
    auto embd = embedText(text);
    QByteArray blob;
    if (!embd.empty())
        blob = QByteArray(reinterpret_cast<const char*>(embd.data()),
                          (qsizetype)(embd.size() * sizeof(float)));
    emit textEmbeddingReady(queryId, blob);
}

void SemanticWorker::indexPendingMedia()
{
    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("SELECT m.id, m.file_path FROM media m "
              "WHERE m.is_trashed=0 AND m.is_hidden=0 "
              "AND m.id NOT IN (SELECT media_id FROM ai_embeddings) "
              "ORDER BY m.creation_date DESC");
    q.exec();

    QList<QPair<int,QString>> pending;
    while (q.next())
        pending.append({ q.value(0).toInt(), q.value(1).toString() });

    int total = (int)pending.size();
    int done  = 0;
    emit indexProgress(done, total);

    for (const auto &[id, path] : pending) {
        if (QThread::currentThread()->isInterruptionRequested()) break;
        QMutexLocker lk(&m_mutex);
        if (!m_model) break;
        auto embd = embedImage(path);
        if (!embd.empty()) {
            QSqlQuery ins(db);
            ins.prepare("INSERT OR REPLACE INTO ai_embeddings "
                        "(media_id, embedding, model_ver) VALUES (?, ?, ?)");
            ins.addBindValue(id);
            ins.addBindValue(QByteArray(reinterpret_cast<const char*>(embd.data()),
                                        (qsizetype)(embd.size() * sizeof(float))));
            ins.addBindValue(QString("qwen3vl-emb-2b-q4km"));
            ins.exec();
        }
        emit indexProgress(++done, total);
    }
}

// ─── SemanticSearchEngine ─────────────────────────────────────────────────────

QString SemanticSearchEngine::modelsDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation)
           + "/models";
}

QString SemanticSearchEngine::modelPath()
{
    return modelsDir() + "/Qwen.Qwen3-VL-Embedding-2B.Q4_K_M.gguf";
}

QString SemanticSearchEngine::mmprojPath()
{
    return modelsDir() + "/mmproj-Qwen.Qwen3-VL-Embedding-2B.f16.gguf";
}

bool SemanticSearchEngine::modelsPresent() const
{
    return QFile::exists(modelPath()) && QFile::exists(mmprojPath());
}

SemanticSearchEngine::SemanticSearchEngine(DatabaseManager *db, QObject *parent)
    : QObject(parent), m_db(db), m_nam(new QNetworkAccessManager(this))
{
    m_thread = new QThread(this);
    m_worker = new SemanticWorker(db);
    m_worker->moveToThread(m_thread);

    connect(m_worker, &SemanticWorker::loaded,
            this, &SemanticSearchEngine::onWorkerLoaded);
    connect(m_worker, &SemanticWorker::textEmbeddingReady,
            this, &SemanticSearchEngine::onTextEmbeddingReady);
    connect(m_worker, &SemanticWorker::indexProgress,
            this, &SemanticSearchEngine::onIndexProgress);
    connect(m_worker, &SemanticWorker::workerError,
            this, &SemanticSearchEngine::onWorkerError);
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);

    m_thread->start();
}

SemanticSearchEngine::~SemanticSearchEngine()
{
    m_thread->requestInterruption();
    QMetaObject::invokeMethod(m_worker, &SemanticWorker::unloadModel,
                              Qt::BlockingQueuedConnection);
    m_thread->quit();
    m_thread->wait(5000);
}

void SemanticSearchEngine::loadModel()
{
    if (m_ready || m_loading) return;
    m_loading = true;
    emit loadingChanged();
    QString mp = modelPath(), mmpp = mmprojPath();
    QMetaObject::invokeMethod(m_worker, [this, mp, mmpp]{
        m_worker->loadModel(mp, mmpp);
    }, Qt::QueuedConnection);
}

void SemanticSearchEngine::unloadModel()
{
    m_ready = false;
    emit readyChanged();
    QMetaObject::invokeMethod(m_worker, &SemanticWorker::unloadModel,
                              Qt::QueuedConnection);
}

void SemanticSearchEngine::indexAllMedia()
{
    if (!m_ready) { emit engineError("Model not loaded"); return; }
    if (m_indexing) return;
    m_indexing = true; emit indexingChanged();
    m_indexedCount = 0; emit indexedCountChanged();
    m_indexTotal   = 0; emit indexTotalChanged();
    QMetaObject::invokeMethod(m_worker, &SemanticWorker::indexPendingMedia,
                              Qt::QueuedConnection);
}

// ── Download ──────────────────────────────────────────────────────────────────

void SemanticSearchEngine::downloadModels()
{
    if (m_downloading) return;
    QDir().mkpath(modelsDir());

    m_dlQueue.clear();
    QPair<QString,QString> files[2] = {
        { "https://huggingface.co/DevQuasar/Qwen.Qwen3-VL-Embedding-2B-GGUF/resolve/main/Qwen.Qwen3-VL-Embedding-2B.Q4_K_M.gguf",
          modelPath() },
        { "https://huggingface.co/DevQuasar/Qwen.Qwen3-VL-Embedding-2B-GGUF/resolve/main/mmproj-Qwen.Qwen3-VL-Embedding-2B.f16.gguf",
          mmprojPath() }
    };
    for (const auto &f : files)
        if (!QFile::exists(f.second))
            m_dlQueue.append(f);

    if (m_dlQueue.isEmpty()) { emit modelsPresentChanged(); return; }
    m_dlIdx = 0; m_dlCancel = false;
    m_downloading = true; emit downloadingChanged();
    downloadNext();
}

void SemanticSearchEngine::cancelDownload()
{
    m_dlCancel = true;
    if (m_reply) m_reply->abort();
}

void SemanticSearchEngine::downloadNext()
{
    if (m_dlCancel || m_dlIdx >= m_dlQueue.size()) {
        m_downloading = false; emit downloadingChanged();
        if (!m_dlCancel && modelsPresent()) emit modelsPresentChanged();
        return;
    }
    const auto &[url, path] = m_dlQueue[m_dlIdx];
    m_dlStatus = "Downloading " + QFileInfo(path).fileName()
               + " (" + QString::number(m_dlIdx + 1)
               + "/" + QString::number(m_dlQueue.size()) + ")...";
    emit dlStatusChanged();

    m_dlFile = new QFile(path + ".part", this);
    m_dlFile->open(QIODevice::WriteOnly | QIODevice::Truncate);

    QNetworkRequest req{QUrl(url)};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_nam->get(req);
    connect(m_reply, &QNetworkReply::downloadProgress,
            this, &SemanticSearchEngine::onDownloadProgress);
    connect(m_reply, &QNetworkReply::readyRead, this, [this]{
        if (m_dlFile) m_dlFile->write(m_reply->readAll());
    });
    connect(m_reply, &QNetworkReply::finished,
            this, &SemanticSearchEngine::onDownloadFinished);
}

void SemanticSearchEngine::onDownloadProgress(qint64 recv, qint64 total)
{
    if (total > 0)
        m_dlProgress = ((double)m_dlIdx + (double)recv / total) / m_dlQueue.size();
    else
        m_dlProgress = (double)m_dlIdx / m_dlQueue.size();
    emit dlProgressChanged();
}

void SemanticSearchEngine::onDownloadFinished()
{
    bool ok = m_reply && m_reply->error() == QNetworkReply::NoError;
    if (m_dlFile) {
        m_dlFile->close();
        QString part = m_dlFile->fileName();
        delete m_dlFile; m_dlFile = nullptr;
        if (ok) {
            QString final = part; final.chop(5);
            QFile::remove(final); QFile::rename(part, final);
        } else {
            QFile::remove(part);
        }
    }
    if (m_reply) { m_reply->deleteLater(); m_reply = nullptr; }
    if (!ok && !m_dlCancel) {
        m_downloading = false; emit downloadingChanged();
        emit engineError("Download failed"); return;
    }
    m_dlIdx++;
    downloadNext();
}

// ── Slots ─────────────────────────────────────────────────────────────────────

void SemanticSearchEngine::onWorkerLoaded(bool ok)
{
    m_loading = false; emit loadingChanged();
    m_ready   = ok;    emit readyChanged();
    if (!ok) emit engineError("Model failed to load");
}

void SemanticSearchEngine::onTextEmbeddingReady(int queryId, QByteArray blob)
{
    auto it = m_textCbs.find(queryId);
    if (it != m_textCbs.end()) { it.value()(blob); m_textCbs.erase(it); }
}

void SemanticSearchEngine::onIndexProgress(int cur, int total)
{
    m_indexedCount = cur;
    if (m_indexTotal != total) { m_indexTotal = total; emit indexTotalChanged(); }
    emit indexedCountChanged();
    if (cur >= total && total > 0) {
        m_indexing = false;
        emit indexingChanged();
        qDebug() << "[AI] Indexing complete:" << cur << "embeddings stored";
    }
}

void SemanticSearchEngine::onWorkerError(QString msg)
{
    qWarning() << "[SemanticSearch]" << msg;
    emit engineError(msg);
}

// ── Search ────────────────────────────────────────────────────────────────────

float SemanticSearchEngine::cosine(const float *a, const float *b, int n)
{
    float dot = 0.f;
    for (int i = 0; i < n; i++) dot += a[i] * b[i];
    return dot;
}

QVariantList SemanticSearchEngine::searchByText(const QString &query)
{
    if (!m_ready) { emit engineError("Model not loaded"); return {}; }

    QByteArray queryBlob;
    int qid = m_nextQueryId++;
    m_textCbs[qid] = [&queryBlob](QByteArray b){ queryBlob = b; };
    QMetaObject::invokeMethod(m_worker, [this, query, qid]{
        m_worker->generateTextEmbedding(query, qid);
    }, Qt::BlockingQueuedConnection);

    if (queryBlob.isEmpty()) return {};

    int nEmbd = (int)(queryBlob.size() / sizeof(float));
    const float *qvec = reinterpret_cast<const float*>(queryBlob.constData());

    QSqlDatabase db = m_db->threadDb();
    QSqlQuery q(db);
    q.prepare("SELECT e.media_id, e.embedding FROM ai_embeddings e "
              "JOIN media m ON m.id = e.media_id "
              "WHERE m.is_trashed=0 AND m.is_ignored=0");
    q.exec();

    QVector<QPair<int,float>> scores;
    while (q.next()) {
        int id = q.value(0).toInt();
        QByteArray blob = q.value(1).toByteArray();
        if (blob.size() != (qsizetype)(nEmbd * sizeof(float))) continue;
        scores.append({ id, cosine(qvec,
            reinterpret_cast<const float*>(blob.constData()), nEmbd) });
    }

    std::sort(scores.begin(), scores.end(),
              [](const auto &a, const auto &b){ return a.second > b.second; });
    if (scores.size() > 30) scores.resize(30);

    QVariantList out;
    for (const auto &[id, score] : scores) {
        QVariantMap m; m["id"] = id; m["score"] = (double)score;
        out.append(m);
    }
    return out;
}
