#pragma once

#include <QObject>
#include <QString>

class QProcess;

// Minimal, fast video editing via ffmpeg stream-copy. Trims [startMs, endMs],
// optionally drops the audio track, and always writes a NEW file next to the
// original (<base>_edited[.N].<ext>) — it never overwrites the source.
class VideoEditor : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit VideoEditor(QObject *parent = nullptr);

    bool busy() const { return m_busy; }

    // startMs/endMs are in milliseconds. inputUrl may be a "file://" URL or path.
    // Runs asynchronously; emits finished(outputPath) or failed(error).
    Q_INVOKABLE void trim(const QString &inputUrl, qint64 startMs, qint64 endMs,
                          bool dropAudio);

signals:
    void busyChanged();
    void finished(const QString &outputPath);
    void failed(const QString &error);

private:
    static QString localPath(const QString &url);
    static QString uniqueOutputPath(const QString &inputPath);

    void setBusy(bool b);

    bool      m_busy = false;
    QProcess *m_proc = nullptr;
};
