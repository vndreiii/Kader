#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

// Auto-generated "Memories": short slideshow videos built from random photos of
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

    // [{id, title, date, mood, video, cover, durationMs, photoCount, expiresAt}]
    Q_INVOKABLE QVariantList list() const;

    // Copies the mp4 to destUrl ("file://…" or path; a folder gets the default
    // file name appended). Returns the written path, or "" on failure.
    Q_INVOKABLE QString exportTo(int id, const QString &destUrl) const;
    Q_INVOKABLE QString suggestedFileName(int id) const;
    Q_INVOKABLE bool remove(int id);

signals:
    void generatingChanged();
    void revisionChanged();

private:
    void finishBatch(int made);

    QString m_dbPath;
    QString m_dir;
    bool    m_generating = false;
    int     m_revision = 0;
};
