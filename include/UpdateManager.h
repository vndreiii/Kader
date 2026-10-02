#pragma once

#include <QByteArray>
#include <QCryptographicHash>
#include <QFile>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QTimer>

class QNetworkAccessManager;
class QNetworkReply;
class QProcess;
class SettingsManager;

// Self-update engine backed by GitHub Releases.
//
// Each release carries `kader-update.json` (version, notes and per-channel
// asset name/size/SHA-256) plus `kader-update.json.sig`, an Ed25519 signature
// of the manifest made in CI. The manifest is only trusted after the signature
// verifies against the public key compiled into the app; downloads are then
// only installed if their SHA-256 matches the signed manifest.
//
// Install channels:
//   appimage — the running AppImage ($APPIMAGE) is atomically replaced.
//   arch     — the release's pacman package is installed with
//              `pkexec pacman -U` (builds made by the PKGBUILD).
//   manual   — anything else: the user is pointed at the release page.
class UpdateManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString channel READ channel CONSTANT)
    Q_PROPERTY(bool canInstall READ canInstall CONSTANT)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY stateChanged)
    Q_PROPERTY(QString notes READ notes NOTIFY stateChanged)
    Q_PROPERTY(QString releaseUrl READ releaseUrl NOTIFY stateChanged)
    Q_PROPERTY(qint64 downloadSize READ downloadSize NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QString lastChecked READ lastChecked NOTIFY stateChanged)

public:
    enum State {
        Idle,          // nothing known yet / up to date
        Checking,
        Available,     // verified newer release found
        Downloading,
        Installing,
        Installed,     // restart to finish
        Failed
    };
    Q_ENUM(State)

    explicit UpdateManager(SettingsManager *settings, QObject *parent = nullptr);
    ~UpdateManager() override;

    QString currentVersion() const;
    QString channel() const { return m_channel; }
    bool canInstall() const { return m_channel != QLatin1String("manual"); }
    State state() const { return m_state; }
    bool available() const { return m_state == Available || m_state == Downloading
                                    || m_state == Installing || m_state == Installed; }
    QString latestVersion() const { return m_latest; }
    QString notes() const { return m_notes; }
    QString releaseUrl() const { return m_releaseUrl; }
    qint64 downloadSize() const { return m_assetSize; }
    double progress() const { return m_progress; }
    QString error() const { return m_error; }
    QString lastChecked() const { return m_lastChecked; }

    // Kick off the periodic background check (respects Settings.autoUpdate).
    void start();

    // `userInitiated` surfaces "you're up to date" / errors instead of
    // staying silent, and ignores a previously skipped version.
    Q_INVOKABLE void check(bool userInitiated = true);
    Q_INVOKABLE void install();
    Q_INVOKABLE void skip();
    Q_INVOKABLE void dismiss();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void openReleasePage();

    // -1 / 0 / 1 like strcmp; understands MAJOR.MINOR.FIX[-prerelease].
    static int compareVersions(const QString &a, const QString &b);
    // Ed25519 verification with the compiled-in release key.
    static bool verifySignature(const QByteArray &message, const QByteArray &signature);

signals:
    void stateChanged();
    void progressChanged();
    // A newer version became available and should be offered to the user.
    void updateOffered();
    // Result of a user-initiated check that found nothing newer.
    void upToDate();

private:
    void setState(State s, const QString &error = {});
    void fetchManifest();
    void onManifest(const QByteArray &manifest, const QByteArray &signature, bool userInitiated);
    QString assetUrl(const QString &name) const;
    QString baseUrl() const;
    void finishDownload();
    void installAppImage();
    void installArch();

    SettingsManager *m_settings;
    QNetworkAccessManager *m_nam;
    QTimer m_timer;
    QString m_channel;

    State m_state = Idle;
    QString m_error;
    QString m_latest, m_tag, m_notes, m_releaseUrl, m_lastChecked;
    QString m_assetName;
    QByteArray m_assetSha256;
    qint64 m_assetSize = 0;
    double m_progress = 0;

    QPointer<QNetworkReply> m_reply;
    QFile m_download;
    QCryptographicHash m_hash{QCryptographicHash::Sha256};
    QPointer<QProcess> m_installer;
    QString m_restartPath;
};
