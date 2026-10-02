#include "VideoEditor.h"

#include <QProcess>
#include <QFileInfo>
#include <QFile>
#include <QUrl>
#include <QStringList>
#include <QDebug>
#include <QStandardPaths>

VideoEditor::VideoEditor(QObject *parent) : QObject(parent) {}

QString VideoEditor::localPath(const QString &url) {
    if (url.startsWith("file://"))
        return QUrl(url).toLocalFile();
    return url;
}

// <dir>/<base>_edited.<ext>, adding _1, _2, … until the name is free.
QString VideoEditor::uniqueOutputPath(const QString &inputPath) {
    QFileInfo info(inputPath);
    const QString dir    = info.absolutePath();
    const QString base   = info.completeBaseName() + "_edited";
    const QString suffix = info.suffix();

    QString candidate = QString("%1/%2.%3").arg(dir, base, suffix);
    int n = 1;
    while (QFile::exists(candidate))
        candidate = QString("%1/%2_%3.%4").arg(dir, base, QString::number(n++), suffix);
    return candidate;
}

void VideoEditor::setBusy(bool b) {
    if (m_busy == b) return;
    m_busy = b;
    emit busyChanged();
}

void VideoEditor::trim(const QString &inputUrl, qint64 startMs, qint64 endMs,
                       bool dropAudio) {
    if (m_busy) { emit failed("Another export is already running."); return; }

    const QString input = localPath(inputUrl);
    if (input.isEmpty() || !QFile::exists(input)) {
        emit failed("Source video not found.");
        return;
    }
    if (endMs <= startMs) {
        emit failed("End point must be after the start point.");
        return;
    }

    const double startSec = startMs / 1000.0;
    const double durSec    = (endMs - startMs) / 1000.0;
    const QString output   = uniqueOutputPath(input);
    const QString suffix   = QFileInfo(input).suffix().toLower();

    // Fast, lossless stream copy. -ss before -i = index seek (near-instant); cuts
    // land on the nearest keyframe, which is fine for quick trims.
    QStringList args;
    args << "-hide_banner" << "-loglevel" << "error"
         << "-ss" << QString::number(startSec, 'f', 3)
         << "-i"  << input
         << "-t"  << QString::number(durSec, 'f', 3)
         << "-map" << "0:v:0";
    if (dropAudio)
        args << "-an";
    else
        args << "-map" << "0:a:0?";          // keep first audio track if present
    args << "-c" << "copy"
         << "-avoid_negative_ts" << "make_zero";
    if (suffix == "mp4" || suffix == "mov" || suffix == "m4v")
        args << "-movflags" << "+faststart";  // instant preview, moov at front
    args << output;

    m_proc = new QProcess(this);
    m_proc->setProgram(QStandardPaths::findExecutable(QStringLiteral("ffmpeg")));
    m_proc->setArguments(args);

    connect(m_proc, &QProcess::finished, this,
            [this, output](int code, QProcess::ExitStatus status) {
        const QString err = m_proc ? QString::fromUtf8(m_proc->readAllStandardError()) : QString();
        if (m_proc) { m_proc->deleteLater(); m_proc = nullptr; }
        setBusy(false);
        if (status == QProcess::NormalExit && code == 0 && QFile::exists(output)) {
            emit finished(output);
        } else {
            QFile::remove(output);  // don't leave a half-written file
            emit failed(err.isEmpty() ? "ffmpeg failed." : err.trimmed());
        }
    });
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (!m_proc) return;
        const QString err = m_proc->errorString();
        m_proc->deleteLater(); m_proc = nullptr;
        setBusy(false);
        emit failed(err.isEmpty() ? "Could not start ffmpeg." : err);
    });

    setBusy(true);
    qDebug() << "VideoEditor: ffmpeg" << args.join(' ');
    m_proc->start();
}
