#include "SemanticSearchEngine.h"
#include "AppPaths.h"
#include "DatabaseManager.h"
#include "ThumbnailGenerator.h"

#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QNetworkRequest>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QVariantMap>
#include <QDebug>
#include <QImage>
#include <QThread>
#include <cmath>
#include <cstring>
#include <numeric>
#include <thread>

#if KADER_HAVE_LLAMA
#include <llama.h>
#include <llama-cpp.h>
#include <mtmd.h>
#include <mtmd-helper.h>
#endif

#include <poppler/cpp/poppler-document.h>
#include <poppler/cpp/poppler-page.h>

// ─── Text chunking helper ─────────────────────────────────────────────────────

static QStringList chunkText(const QString &text, int chunkSize = 700, int overlap = 70, int maxChunks = 20)
{
    QStringList chunks;
    int len = text.length();
    int start = 0;
    while (start < len && (int)chunks.size() < maxChunks) {
        chunks.append(text.mid(start, chunkSize));
        start += chunkSize - overlap;
    }
    return chunks;
}

static QString extractPdfText(const QString &path)
{
    auto doc = std::unique_ptr<poppler::document>(
        poppler::document::load_from_file(QFile::encodeName(path).toStdString()));
    if (!doc || doc->is_locked()) return {};
    QString full;
    for (int i = 0; i < doc->pages(); ++i) {
        auto page = std::unique_ptr<poppler::page>(doc->create_page(i));
        if (!page) continue;
        auto bytes = page->text().to_utf8();
        full += QString::fromUtf8(bytes.data(), (qsizetype)bytes.size()) + "\n";
    }
    return full.trimmed();
}

// ─── Embedding prompts ────────────────────────────────────────────────────────
// Qwen3-VL-Embedding embeds the hidden state of the last token of a chat
// prompt whose system line states the task; queries and the things they
// retrieve use different instructions. Embeddings made before this format
// (mean-pooled raw inputs) are not comparable and are re-indexed.
static const char *kModelVer   = "qwen3vl-emb-2b-q4km-v2";
static const char *kDocInstr   = "Represent the user's input.";
static const char *kQueryInstr = "Retrieve images or text relevant to the user's query.";

static std::string chatPrompt(const QString &instruction, const std::string &content)
{
    return "<|im_start|>system\n" + instruction.toStdString() + "<|im_end|>\n<|im_start|>user\n" + content +
           "<|im_end|>\n<|im_start|>assistant\n";
}

// ─── SemanticWorker ───────────────────────────────────────────────────────────

#if KADER_HAVE_LLAMA

SemanticWorker::SemanticWorker(DatabaseManager *db, ThumbnailGenerator *thumbs, QObject *parent)
    : QObject(parent), m_db(db), m_thumbs(thumbs)
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
    mparams.n_gpu_layers = 0; // Vulkan backend (not ROCm HIP) locks up AMD GPU under load

    auto *model = llama_model_load_from_file(QFile::encodeName(modelPath).constData(), mparams);
    if (!model) {
        emit workerError("Failed to load model: " + modelPath);
        emit loaded(false);
        return;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx        = 4096;
    cparams.n_batch      = 512;
    cparams.embeddings   = true;
    // last-token pooling: the model's embedding is the final token's state
    // (mean pooling also only ever saw the last decode batch of a prompt)
    cparams.pooling_type = LLAMA_POOLING_TYPE_LAST;
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

    auto *mctx = mtmd_init_from_file(QFile::encodeName(mmprojPath).constData(), model, vparams);
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

// Evaluates one prompt (with an optional image at the media marker) and
// returns the L2-normalised last-token embedding.
std::vector<float> SemanticWorker::embedPrompt(const std::string &prompt, const void *bitmap)
{
    auto *ctx  = static_cast<llama_context *>(m_ctx);
    auto *mctx = static_cast<mtmd_context  *>(m_mtmd);
    auto *bmp  = static_cast<const mtmd_bitmap *>(bitmap);

    // parse_special: the chat-template markers are special tokens
    mtmd_input_text txt { prompt.c_str(), false, true };
    const mtmd_bitmap *bmps[] = { bmp };

    auto *chunks = mtmd_input_chunks_init();
    if (mtmd_tokenize(mctx, chunks, &txt, bmp ? bmps : nullptr, bmp ? 1 : 0) != 0) {
        mtmd_input_chunks_free(chunks);
        return {};
    }

    clearKV(ctx);
    // mtmd also lays out the M-RoPE positions Qwen3-VL needs for text
    llama_pos n_past = 0;
    const int32_t ret = mtmd_helper_eval_chunks(mctx, ctx, chunks, n_past, 0, 512, true, &n_past);
    mtmd_input_chunks_free(chunks);

    std::vector<float> result;
    if (ret == 0) {
        const float *embd = llama_get_embeddings_seq(ctx, 0);
        if (embd && m_nEmbd > 0) {
            result.assign(embd, embd + m_nEmbd);
            float norm = 0.f;
            for (float v : result) norm += v * v;
            norm = std::sqrt(norm);
            if (norm > 1e-9f) for (float &v : result) v /= norm;
        }
    }
    return result;
}

std::vector<float> SemanticWorker::embedImage(const QString &imagePath)
{
    // Decode through the thumbnail cache: every format the gallery shows
    // (HEIC, RAW, video frames) works, and the vision encoder gets a
    // 512px image instead of a full-resolution decode.
    const QString thumb = m_thumbs ? m_thumbs->getOrCreateThumbnail(imagePath, 768) : QString();
    QImage img(thumb.isEmpty() ? imagePath : thumb);
    if (img.isNull())
        return {};
    if (std::max(img.width(), img.height()) > 512)
        img = img.scaled(512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    img = img.convertToFormat(QImage::Format_RGB888);
    std::vector<unsigned char> rgb(size_t(img.width()) * size_t(img.height()) * 3);
    for (int y = 0; y < img.height(); ++y)
        std::memcpy(rgb.data() + size_t(y) * size_t(img.width()) * 3, img.constScanLine(y), size_t(img.width()) * 3);
    mtmd_bitmap *bmp = mtmd_bitmap_init(uint32_t(img.width()), uint32_t(img.height()), rgb.data());
    if (!bmp)
        return {};
    auto result = embedPrompt(chatPrompt(QString::fromLatin1(kDocInstr), mtmd_default_marker()), bmp);
    mtmd_bitmap_free(bmp);
    return result;
}

std::vector<float> SemanticWorker::embedText(const QString &text, const QString &instruction)
{
    return embedPrompt(chatPrompt(instruction, text.toStdString()), nullptr);
}

#else // !KADER_HAVE_LLAMA — build without llama.cpp: search reports itself unavailable

SemanticWorker::SemanticWorker(DatabaseManager *db, ThumbnailGenerator *thumbs, QObject *parent)
    : QObject(parent), m_db(db), m_thumbs(thumbs) {}

SemanticWorker::~SemanticWorker() = default;

void SemanticWorker::loadModel(const QString &, const QString &)
{
    emit workerError(QStringLiteral("AI search is not available in this build (compiled without llama.cpp)"));
    emit loaded(false);
}

void SemanticWorker::unloadModel() { emit unloaded(); }

std::vector<float> SemanticWorker::embedImage(const QString &) { return {}; }
std::vector<float> SemanticWorker::embedText(const QString &, const QString &) { return {}; }
std::vector<float> SemanticWorker::embedPrompt(const std::string &, const void *) { return {}; }

#endif

void SemanticWorker::generateTextEmbedding(const QString &text, int queryId)
{
    QMutexLocker lk(&m_mutex);
    if (!m_model) return;
    auto embd = embedText(text, QString::fromLatin1(kQueryInstr));
    QByteArray blob;
    if (!embd.empty())
        blob = QByteArray(reinterpret_cast<const char*>(embd.data()),
                          (qsizetype)(embd.size() * sizeof(float)));
    emit textEmbeddingReady(queryId, blob);
}

void SemanticWorker::embedTexts(const QStringList &texts, int requestId)
{
    QMutexLocker lk(&m_mutex);
    QList<QByteArray> out;
    for (const QString &t : texts) {
        std::vector<float> e;
        if (m_model)
            e = embedText(t, QString::fromLatin1(kQueryInstr));
        out << QByteArray(reinterpret_cast<const char *>(e.data()), qsizetype(e.size() * sizeof(float)));
    }
    emit textsEmbedded(requestId, out);
}

void SemanticWorker::indexPendingMedia()
{
    constexpr int BATCH = 8;  // yield to event loop every N images

    QSqlDatabase db = m_db->threadDb();

    // On first call of a run: count total pending and reset counters
    if (!m_idxRunning) {
        m_idxRunning = true;
        m_idxDone    = 0;
        QSqlQuery cnt(db);
        cnt.exec("SELECT COUNT(*) FROM media m "
                 "WHERE m.is_trashed=0 AND m.is_hidden=0 "
                 "AND m.id NOT IN (SELECT media_id FROM ai_embeddings)");
        m_idxTotal = cnt.next() ? cnt.value(0).toInt() : 0;
        emit indexProgress(0, m_idxTotal);
        if (m_idxTotal == 0) { m_idxRunning = false; return; }
    }

    // Fetch the next BATCH un-indexed images
    QSqlQuery q(db);
    q.prepare(QString("SELECT m.id, m.file_path FROM media m "
                      "WHERE m.is_trashed=0 AND m.is_hidden=0 "
                      "AND m.id NOT IN (SELECT media_id FROM ai_embeddings) "
                      "ORDER BY m.creation_date DESC "
                      "LIMIT %1").arg(BATCH));
    q.exec();

    QList<QPair<int,QString>> batch;
    while (q.next())
        batch.append({ q.value(0).toInt(), q.value(1).toString() });

    if (batch.isEmpty()) {
        // All done (possibly indexed in a prior run before this call)
        emit indexProgress(m_idxTotal, m_idxTotal);
        m_idxRunning = false;
        return;
    }

    for (const auto &[id, path] : batch) {
        if (QThread::currentThread()->isInterruptionRequested()) {
            m_idxRunning = false;
            return;
        }
        QMutexLocker lk(&m_mutex);
        if (!m_model) { m_idxRunning = false; return; }

        if (m_resourceMode < 2) {
            int delayMs = m_resourceMode == 0 ? 500 : 150;
            QThread::msleep(delayMs);
        }

        auto embd = embedImage(path);
        // Always store — failed files get a 1-byte sentinel so they are never retried.
        // The search cosine scan skips blobs whose size ≠ nEmbd*4, so sentinels are
        // harmless in queries.
        QSqlQuery ins(db);
        ins.prepare("INSERT OR REPLACE INTO ai_embeddings "
                    "(media_id, embedding, model_ver) VALUES (?, ?, ?)");
        ins.addBindValue(id);
        ins.addBindValue(embd.empty()
            ? QByteArray(1, '\0')
            : QByteArray(reinterpret_cast<const char*>(embd.data()),
                         (qsizetype)(embd.size() * sizeof(float))));
        ins.addBindValue(QString::fromLatin1(kModelVer));
        ins.exec();
        emit indexProgress(++m_idxDone, m_idxTotal);
    }

    // Re-post ourselves to process the next batch; other queued messages
    // (e.g. text embedding for a search) will interleave between batches.
    QMetaObject::invokeMethod(this, &SemanticWorker::indexPendingMedia,
                              Qt::QueuedConnection);
}

void SemanticWorker::indexPendingDocs(QStringList rootDirs)
{
    constexpr int BATCH = 4;  // fewer than images — text embedding is cheaper but docs have many chunks
    static const QSet<QString> docExts = { ".pdf", ".txt", ".md", ".csv" };

    QSqlDatabase db = m_db->threadDb();

    // On first call of a run: collect all un-indexed doc files and count chunks needed
    if (!m_docRunning) {
        m_docRunning = true;
        m_docDone    = 0;

        // Count total pending doc files (not chunks — we count files for progress)
        int total = 0;
        for (const QString &root : rootDirs) {
            QDirIterator it(root, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
            while (it.hasNext()) {
                QString p = it.next();
                QString ext = QFileInfo(p).suffix().toLower();
                if (!docExts.contains("." + ext)) continue;
                // Check if already fully indexed (has at least one chunk)
                QSqlQuery chk(db);
                chk.prepare("SELECT COUNT(*) FROM doc_chunks WHERE file_path=?");
                chk.addBindValue(p);
                if (chk.exec() && chk.next() && chk.value(0).toInt() > 0) continue;
                ++total;
            }
        }
        m_docTotal = total;
        emit docIndexProgress(0, m_docTotal);
        if (m_docTotal == 0) { m_docRunning = false; return; }
    }

    // Process up to BATCH doc files per invocation
    int processed = 0;
    for (const QString &root : rootDirs) {
        if (processed >= BATCH) break;
        QDirIterator it(root, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
        while (it.hasNext() && processed < BATCH) {
            if (QThread::currentThread()->isInterruptionRequested()) {
                m_docRunning = false; return;
            }
            QString p = it.next();
            QString ext = QFileInfo(p).suffix().toLower();
            if (!docExts.contains("." + ext)) continue;

            // Skip already-indexed files
            QSqlQuery chk(db);
            chk.prepare("SELECT COUNT(*) FROM doc_chunks WHERE file_path=?");
            chk.addBindValue(p);
            if (chk.exec() && chk.next() && chk.value(0).toInt() > 0) continue;

            // Extract text
            QString text;
            if (ext == "pdf") {
                text = extractPdfText(p);
            } else {
                QFile f(p);
                if (f.open(QIODevice::ReadOnly | QIODevice::Text))
                    text = QString::fromUtf8(f.readAll());
            }
            if (text.trimmed().isEmpty()) {
                // Mark as indexed with a dummy so we don't retry forever
                emit docIndexProgress(++m_docDone, m_docTotal);
                ++processed;
                continue;
            }

            // Chunk and embed
            QStringList chunks = chunkText(text);
            for (int ci = 0; ci < chunks.size(); ++ci) {
                QMutexLocker lk(&m_mutex);
                if (!m_model) { m_docRunning = false; return; }

                if (m_resourceMode < 2) {
                    int delayMs = m_resourceMode == 0 ? 200 : 50;
                    QThread::msleep(delayMs);
                }

                auto embd = embedText(chunks[ci], QString::fromLatin1(kDocInstr));
                if (!embd.empty()) {
                    QSqlQuery ins(db);
                    ins.prepare("INSERT OR IGNORE INTO doc_chunks "
                                "(file_path, chunk_idx, embedding, model_ver) VALUES (?,?,?,?)");
                    ins.addBindValue(p);
                    ins.addBindValue(ci);
                    ins.addBindValue(QByteArray(reinterpret_cast<const char*>(embd.data()),
                                                (qsizetype)(embd.size() * sizeof(float))));
                    ins.addBindValue(QString::fromLatin1(kModelVer));
                    ins.exec();
                }
            }
            emit docIndexProgress(++m_docDone, m_docTotal);
            ++processed;
        }
    }

    if (m_docDone >= m_docTotal) {
        m_docRunning = false;
        return;
    }

    // Re-post for next batch
    QMetaObject::invokeMethod(this, [this, rootDirs]{
        indexPendingDocs(rootDirs);
    }, Qt::QueuedConnection);
}

// ─── SemanticSearchEngine ─────────────────────────────────────────────────────

QString SemanticSearchEngine::modelsDir()
{
    return AppPaths::localDataDir() + "/models";
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

SemanticSearchEngine::SemanticSearchEngine(DatabaseManager *db, ThumbnailGenerator *thumbs, QObject *parent)
    : QObject(parent), m_db(db), m_nam(new QNetworkAccessManager(this))
{
    // Embeddings from an older prompt/pooling format live in another space:
    // drop them so the library is re-indexed with the current one.
    {
        QSqlQuery dq(m_db->threadDb());
        dq.prepare("DELETE FROM ai_embeddings WHERE model_ver != ?");
        dq.addBindValue(QString::fromLatin1(kModelVer));
        dq.exec();
        dq.prepare("DELETE FROM doc_chunks WHERE model_ver != ?");
        dq.addBindValue(QString::fromLatin1(kModelVer));
        dq.exec();
    }

    // Load persisted docs-enabled setting
    {
        QSqlQuery sq(m_db->threadDb());
        sq.prepare("SELECT value FROM settings_kv WHERE key='ai_docs_enabled'");
        if (sq.exec() && sq.next())
            m_docsEnabled = (sq.value(0).toString() == "1");
    }

    // Pre-populate indexed counts so Settings shows "Done — N photos indexed"
    // immediately on startup without requiring a model load.
    {
        QSqlDatabase db = m_db->threadDb();
        QSqlQuery cq(db);
        // Real embeddings (length > 1 excludes the 1-byte failed-file sentinels)
        cq.exec("SELECT COUNT(*) FROM ai_embeddings WHERE length(embedding) > 1");
        if (cq.next()) m_indexedCount = cq.value(0).toInt();
        // Doc chunks
        cq.exec("SELECT COUNT(DISTINCT file_path) FROM doc_chunks");
        if (cq.next()) m_docIndexedCount = cq.value(0).toInt();
        // Set totals equal to counts so QML shows the "Done" branch
        m_indexTotal      = m_indexedCount;
        m_docIndexTotal   = m_docIndexedCount;
    }

    m_thread = new QThread(this);
    m_worker = new SemanticWorker(db, thumbs);
    m_worker->moveToThread(m_thread);

    connect(m_worker, &SemanticWorker::loaded,
            this, &SemanticSearchEngine::onWorkerLoaded);
    connect(m_worker, &SemanticWorker::textEmbeddingReady,
            this, &SemanticSearchEngine::onTextEmbeddingReady);
    connect(m_worker, &SemanticWorker::textsEmbedded,
            this, &SemanticSearchEngine::onTextsEmbedded);
    connect(m_worker, &SemanticWorker::indexProgress,
            this, &SemanticSearchEngine::onIndexProgress);
    connect(m_worker, &SemanticWorker::docIndexProgress,
            this, &SemanticSearchEngine::onDocIndexProgress);
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

    // Quick main-thread check — if nothing is pending, don't enter "indexing" state
    // and don't reset the displayed counts. This makes re-loading the model a no-op
    // when the library is already fully indexed.
    QSqlQuery chk(m_db->threadDb());
    chk.exec("SELECT COUNT(*) FROM media m "
             "WHERE m.is_trashed=0 AND m.is_hidden=0 "
             "AND m.id NOT IN (SELECT media_id FROM ai_embeddings)");
    if (chk.next() && chk.value(0).toInt() == 0) return;

    m_indexing = true; emit indexingChanged();
    m_indexedCount = 0; emit indexedCountChanged();
    m_indexTotal   = 0; emit indexTotalChanged();
    QMetaObject::invokeMethod(m_worker, &SemanticWorker::indexPendingMedia,
                              Qt::QueuedConnection);
}

void SemanticSearchEngine::setDocsEnabled(bool enabled)
{
    if (m_docsEnabled == enabled) return;
    m_docsEnabled = enabled;
    // Persist
    QSqlQuery q(m_db->threadDb());
    q.prepare("INSERT INTO settings_kv (key,value) VALUES ('ai_docs_enabled',?) "
              "ON CONFLICT(key) DO UPDATE SET value=excluded.value");
    q.addBindValue(enabled ? "1" : "0");
    q.exec();
    emit docsEnabledChanged();
    if (enabled && m_ready) indexAllDocs();
}

void SemanticSearchEngine::indexAllDocs()
{
    if (!m_ready) { emit engineError("Model not loaded"); return; }
    if (!m_docsEnabled) return;
    if (m_docIndexing) return;
    m_docIndexing = true; emit docIndexingChanged();
    m_docIndexedCount = 0; emit docIndexedCountChanged();
    m_docIndexTotal   = 0; emit docIndexTotalChanged();
    QStringList dirs = m_db->getIndexedDirectoryPaths();
    QMetaObject::invokeMethod(m_worker, [this, dirs]{
        m_worker->indexPendingDocs(dirs);
    }, Qt::QueuedConnection);
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
    if (!ok) { emit engineError("Model failed to load"); return; }

    // Fire any query that arrived while the model was loading
    if (!m_pendingQuery.isEmpty()) {
        QString q = m_pendingQuery;
        m_pendingQuery.clear();
        searchByText(q);  // queues text-embed first
    }

    // Auto-index photos then docs in the background (batched)
    indexAllMedia();
    if (m_docsEnabled) indexAllDocs();
    if (!m_indexing)
        computeScenes(); // library already indexed
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
    if (cur >= total) {   // handles total==0 (nothing to index) as well as normal completion
        m_indexing = false;
        emit indexingChanged();
        if (total > 0) qDebug() << "[AI] Indexing complete:" << cur << "embeddings stored";
        computeScenes();
    }
}

void SemanticSearchEngine::onDocIndexProgress(int cur, int total)
{
    m_docIndexedCount = cur;
    if (m_docIndexTotal != total) { m_docIndexTotal = total; emit docIndexTotalChanged(); }
    emit docIndexedCountChanged();
    if (cur >= total) {
        m_docIndexing = false;
        emit docIndexingChanged();
        if (total > 0) qDebug() << "[AI] Doc indexing complete:" << cur << "files processed";
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

void SemanticSearchEngine::searchByText(const QString &query)
{
    if (!m_ready) {
        if (!modelsPresent()) {
            emit engineError("AI model not downloaded — go to Settings to download it");
            return;
        }
        // Auto-load: queue the query and kick off model loading
        m_pendingQuery = query;
        loadModel();   // self-guards against double-load
        return;
    }

    int qid = m_nextQueryId++;
    // Callback runs on the main thread via onTextEmbeddingReady once the
    // worker finishes embedding the query text.  The DB cosine scan happens
    // here so it stays on the main thread and avoids thread-local DB issues.
    m_textCbs[qid] = [this](QByteArray blob) {
        if (blob.isEmpty()) { emit searchFinished({}); return; }

        int nEmbd = (int)(blob.size() / sizeof(float));
        const float *qvec = reinterpret_cast<const float*>(blob.constData());

        QSqlDatabase db = m_db->threadDb();
        QSqlQuery q(db);
        q.prepare("SELECT e.media_id, e.embedding FROM ai_embeddings e "
                  "JOIN media m ON m.id = e.media_id "
                  "WHERE m.is_trashed=0 AND m.is_hidden=0 AND m.is_ignored=0");
        q.exec();

        QVector<QPair<int,float>> scores;
        while (q.next()) {
            int id  = q.value(0).toInt();
            QByteArray eblob = q.value(1).toByteArray();
            if (eblob.size() != (qsizetype)(nEmbd * sizeof(float))) continue;
            scores.append({ id, cosine(qvec,
                reinterpret_cast<const float*>(eblob.constData()), nEmbd) });
        }

        std::sort(scores.begin(), scores.end(),
                  [](const auto &a, const auto &b){ return a.second > b.second; });
        // Adaptive cut-off: similarities are only meaningful relative to the
        // library, so keep what stands out from it (z ≥ 1.6), at least the
        // best dozen and at most 240 — not a fixed top 30.
        if (!scores.isEmpty()) {
            double mean = 0, var = 0;
            for (const auto &sc : scores) mean += sc.second;
            mean /= scores.size();
            for (const auto &sc : scores) var += (sc.second - mean) * (sc.second - mean);
            const double sd = std::sqrt(var / scores.size());
            const float cut = float(mean + 1.6 * sd);
            qsizetype keep = 0;
            while (keep < scores.size() && keep < 240 && (keep < 12 || scores[keep].second >= cut))
                ++keep;
            scores.resize(keep);
        }

        QVariantList out;
        for (const auto &[id, score] : scores) {
            QVariantMap m; m["id"] = id; m["score"] = (double)score; m["type"] = "image";
            out.append(m);
        }

        // Also search doc_chunks if docs are enabled — keep best score per file
        if (m_docsEnabled) {
            QSqlQuery dq(db);
            dq.exec("SELECT file_path, embedding FROM doc_chunks");
            QMap<QString, float> docBest;
            while (dq.next()) {
                QString fp  = dq.value(0).toString();
                QByteArray eb = dq.value(1).toByteArray();
                if (eb.size() != (qsizetype)(nEmbd * sizeof(float))) continue;
                float s = cosine(qvec, reinterpret_cast<const float*>(eb.constData()), nEmbd);
                if (!docBest.contains(fp) || s > docBest[fp]) docBest[fp] = s;
            }
            // Sort doc results and take top 10
            QVector<QPair<QString,float>> docScores;
            for (auto it = docBest.begin(); it != docBest.end(); ++it)
                docScores.append({ it.key(), it.value() });
            std::sort(docScores.begin(), docScores.end(),
                      [](const auto &a, const auto &b){ return a.second > b.second; });
            if (docScores.size() > 10) docScores.resize(10);
            for (const auto &[fp, score] : docScores) {
                QVariantMap m;
                m["type"]  = "doc";
                m["file_path"] = fp;
                m["name"]  = QFileInfo(fp).fileName();
                m["score"] = (double)score;
                out.append(m);
            }
        }

        emit searchFinished(out);
    };

    // QueuedConnection — worker runs async, emits textEmbeddingReady back to
    // main thread, which then fires the callback above via onTextEmbeddingReady.
    QMetaObject::invokeMethod(m_worker, [this, query, qid]{
        m_worker->generateTextEmbedding(query, qid);
    }, Qt::QueuedConnection);
}

void SemanticSearchEngine::setResourceBudget(int mode)
{
    if (m_worker)
        QMetaObject::invokeMethod(m_worker, [this, mode]{
            m_worker->setResourceBudget(mode);
        }, Qt::QueuedConnection);
}

// ── Scenes ────────────────────────────────────────────────────────────────────

namespace {
struct SceneDef { const char *key; const char *name; const char *prompt; };
// Zero-shot categories: matched against image embeddings with the query
// instruction, like a search the user didn't have to type.
constexpr SceneDef kScenes[] = {
    {"sunset",   "Sunsets",        "a sunset or sunrise with a colourful sky"},
    {"beach",    "Beaches",        "a sandy beach by the sea"},
    {"mountain", "Mountains",      "mountains and peaks landscape"},
    {"snow",     "Snow",           "snow and winter landscape"},
    {"forest",   "Forests",        "a forest with trees"},
    {"water",    "Lakes & rivers", "a lake or river"},
    {"city",     "Cities",         "a city street with buildings"},
    {"architecture", "Architecture", "architecture, a building facade or interior"},
    {"night",    "Night",          "a photo taken at night with lights"},
    {"food",     "Food",           "a plate of food or a meal"},
    {"dog",      "Dogs",           "a dog"},
    {"cat",      "Cats",           "a cat"},
    {"wildlife", "Animals",        "wild animals in nature"},
    {"flower",   "Flowers",        "flowers and plants close up"},
    {"car",      "Cars",           "a car or vehicle"},
    {"selfie",   "Portraits",      "a portrait photo of a person"},
    {"document", "Documents",      "a document, receipt or screenshot with text"},
    {"sky",      "Sky & clouds",   "the sky with clouds"},
};
} // namespace

void SemanticSearchEngine::computeScenes()
{
    if (!m_ready || m_scenesBusy)
        return;
    m_scenesBusy = true;
    emit scenesChanged();
    QStringList prompts;
    for (const auto &sc : kScenes)
        prompts << QString::fromLatin1(sc.prompt);
    m_sceneRequest = m_nextQueryId++;
    const int rid = m_sceneRequest;
    QMetaObject::invokeMethod(m_worker, [this, prompts, rid] { m_worker->embedTexts(prompts, rid); },
                              Qt::QueuedConnection);
}

void SemanticSearchEngine::onTextsEmbedded(int requestId, QList<QByteArray> embeddings)
{
    if (requestId != m_sceneRequest)
        return;
    const int nScenes = int(std::size(kScenes));
    const int dim = embeddings.isEmpty() ? 0 : int(embeddings.first().size() / sizeof(float));
    QVector<int> ids;
    QVector<QVector<float>> sims(nScenes); // sims[scene][image]
    if (dim > 0) {
        QSqlQuery q(m_db->threadDb());
        q.exec("SELECT e.media_id, e.embedding FROM ai_embeddings e JOIN media m ON m.id = e.media_id "
               "WHERE m.is_trashed=0 AND m.is_hidden=0 AND COALESCE(m.is_ignored,0)=0");
        while (q.next()) {
            const QByteArray e = q.value(1).toByteArray();
            if (e.size() != qsizetype(dim * sizeof(float)))
                continue;
            ids << q.value(0).toInt();
            const auto *v = reinterpret_cast<const float *>(e.constData());
            for (int s = 0; s < nScenes; ++s) {
                const auto *t = reinterpret_cast<const float *>(embeddings[s].constData());
                sims[s] << (embeddings[s].size() == e.size() ? cosine(t, v, dim) : -1.f);
            }
        }
    }
    // Standardise each scene's similarities over the library, then give each
    // photo to the scene it stands out for most (z ≥ 1.25).
    QVector<double> mean(nScenes), sd(nScenes);
    for (int s = 0; s < nScenes; ++s) {
        double m = 0, v = 0;
        for (float x : sims[s]) m += x;
        m /= std::max<qsizetype>(1, ids.size());
        for (float x : sims[s]) v += (x - m) * (x - m);
        mean[s] = m;
        sd[s] = std::max(1e-6, std::sqrt(v / std::max<qsizetype>(1, ids.size())));
    }
    QHash<QString, QVector<QPair<float, int>>> members;
    for (int i = 0; i < ids.size(); ++i) {
        int best = -1;
        double bz = 1.25;
        for (int s = 0; s < nScenes; ++s) {
            const double z = (sims[s][i] - mean[s]) / sd[s];
            if (z > bz) { bz = z; best = s; }
        }
        if (best >= 0)
            members[QString::fromLatin1(kScenes[best].key)] << qMakePair(float(bz), ids[i]);
    }
    m_sceneMembers.clear();
    m_scenes.clear();
    for (const auto &sc : kScenes) {
        auto list = members.value(QString::fromLatin1(sc.key));
        if (list.size() < 3)
            continue;
        std::sort(list.begin(), list.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
        QVector<int> idsOrdered;
        for (const auto &p : list) idsOrdered << p.second;
        const QString key = QStringLiteral("scene:") + QString::fromLatin1(sc.key);
        m_sceneMembers.insert(key, idsOrdered);
        QVariantList cover;
        for (int i = 0; i < std::min<qsizetype>(4, idsOrdered.size()); ++i) cover << idsOrdered[i];
        m_scenes << QVariantMap{{"key", key}, {"name", QString::fromLatin1(sc.name)},
                                {"count", int(idsOrdered.size())}, {"coverIds", cover}};
    }
    std::sort(m_scenes.begin(), m_scenes.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("count").toInt() > b.toMap().value("count").toInt();
    });
    m_scenesBusy = false;
    emit scenesChanged();
}

QVariantList SemanticSearchEngine::sceneMediaIds(const QString &key) const
{
    QVariantList out;
    for (int id : m_sceneMembers.value(key))
        out << id;
    return out;
}
