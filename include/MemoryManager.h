#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Auto-generated "Memories": short slideshow videos built from random photos and clips of
// a single day, set to a bundled CC0 track with a fade in/out. A batch of up to
// 5 is generated in the background, lives for a week, then is replaced.
//
// Owns its own `memories` table (same gallery.db, own connections) and the
// <dataDir>/memories folder; rendering happens on a worker thread via ffmpeg.
class MemoryManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool generating READ generating NOTIFY generatingChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    explicit MemoryManager(QObject *parent = nullptr);

    bool generating() const { return m_generating; }
    int  revision() const { return m_revision; }

    // Startup check: renders a new batch (and deletes the old one) unless a
    // non-expired batch exists. Returns immediately; work is off-thread.
    Q_INVOKABLE void ensureBatch();

    // Renders a fresh batch now (the user asked for new ones); the current batch
    // stays until the new one is ready. No-op while a batch is rendering.
    Q_INVOKABLE void regenerate();

    // "Create memory" editor: the bundled songs [{file, name, mood}], a date
    // (yyyy-MM-dd, the middle photo's) and a title prefill for the chosen photos,
    // and the render itself. Custom memories never expire and are not replaced by
    // regenerate(). Returns false if nothing was started.
    Q_INVOKABLE QVariantList tracks() const;
    // Photos the editor's picker offers (newest first), as media maps for ThumbGrid.
    Q_INVOKABLE QVariantList libraryPhotos() const;
    Q_INVOKABLE QString thumbUrl(const QString &path) const;   // library thumbnail (photos and videos)
    // Copies the user's own song into <dataDir>/memory-music so the editor lists
    // it with the bundled ones; returns the stored path, or "" on failure.
    Q_INVOKABLE QString importSong(const QString &urlOrPath);
    Q_INVOKABLE QString suggestDate(const QStringList &photos) const;
    Q_INVOKABLE QString defaultTitle(const QString &isoDate) const;
    // musicStart: seconds into the song where the soundtrack begins.
    Q_INVOKABLE bool createCustom(const QStringList &photos, const QString &trackFile,
                                  const QString &title, const QString &isoDate, double musicStart = 0);
    Q_INVOKABLE QVariantList waveform(const QString &path, int buckets) const;
    Q_INVOKABLE double songDuration(const QString &path) const;            // seconds, 0 if unreadable
    Q_INVOKABLE double estimateDuration(const QStringList &paths) const;   // length of the finished memory

    // [{id, title, date, mood, video, cover, durationMs, photoCount, expiresAt}]
    Q_INVOKABLE QVariantList list() const;

    // Copies the mp4 to destUrl ("file://…" or path; a folder gets the default
    // file name appended). Returns the written path, or "" on failure.
    Q_INVOKABLE QString exportTo(int id, const QString &destUrl) const;
    Q_INVOKABLE QString suggestedFileName(int id) const;
    Q_INVOKABLE bool remove(int id);

    // "Save as…" through the XDG FileChooser portal (SaveFile, with a suggested
    // name). Returns false if the portal can't be reached, so the caller can
    // fall back to a Qt dialog. Emits saved(path) once the file is written.
    Q_INVOKABLE bool saveViaPortal(int id);

    // Same for choosing an audio file (FileChooser.OpenFile, audio filter). The
    // result goes through importSong(), so it ends in songAdded / songRejected.
    Q_INVOKABLE bool pickSongViaPortal();

signals:
    void generatingChanged();
    void revisionChanged();
    void saved(const QString &path);
    void songAdded(const QString &path);          // a usable song is now in tracks()
    void songRejected(const QString &fileName);   // not an audio file ffmpeg can read

private slots:
    void onPortalResponse(uint response, const QVariantMap &results);

private:
    bool callFileChooser(const char *method, const QString &title, QVariantMap options);
    void startBatch();
    void finishBatch(int made);

    QString m_dbPath;
    QString m_dir;
    bool    m_generating = false;
    int     m_revision = 0;
    int     m_pendingSaveId = -1;   // memory awaiting the portal's answer
    bool    m_pendingSong = false;  // an OpenFile dialog is open
    QString m_pendingHandle;
};
