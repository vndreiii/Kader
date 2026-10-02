#include "UpdateManager.h"
#include "AppPaths.h"
#include "SettingsManager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

#include <openssl/evp.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#ifndef Q_OS_WIN
#include <sys/stat.h>
#endif

#ifndef KADER_UPDATE_REPO
#define KADER_UPDATE_REPO "vndreiii/kader"
#endif
#ifndef KADER_UPDATE_CHANNEL
#define KADER_UPDATE_CHANNEL ""
#endif
#ifndef KADER_UPDATE_PUBKEY
#define KADER_UPDATE_PUBKEY ""
#endif

namespace {

constexpr int kCheckIntervalMs = 6 * 60 * 60 * 1000; // every 6 h while running
constexpr int kFirstCheckDelayMs = 12 * 1000;         // after the UI settled

QString detectChannel() {
#ifdef Q_OS_WIN
    // Same build for both Windows packages: the portable .zip carries a
    // portable.txt marker, the installer leaves its uninstaller next to us.
    if (AppPaths::portable())
        return QStringLiteral("windows-portable");
    if (QFileInfo::exists(QCoreApplication::applicationDirPath() + QStringLiteral("/uninstall.exe")))
        return QStringLiteral("windows");
    return QStringLiteral("manual");
#endif
    const QString appImage = qEnvironmentVariable("APPIMAGE");
    if (!appImage.isEmpty() && QFileInfo(appImage).isFile())
        return QStringLiteral("appimage");
    const QString built = QStringLiteral(KADER_UPDATE_CHANNEL);
    if (built == QLatin1String("arch") && QFileInfo::exists(QStringLiteral("/usr/bin/pacman")))
        return QStringLiteral("arch");
    return QStringLiteral("manual");
}

QNetworkRequest request(const QString &url) {
    QNetworkRequest r{QUrl(url)};
    r.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    r.setHeader(QNetworkRequest::UserAgentHeader,
                QStringLiteral("Kader/%1 (updater)").arg(QCoreApplication::applicationVersion()));
    r.setTransferTimeout(60 * 1000);
    return r;
}

struct Version {
    int major = 0, minor = 0, fix = 0;
    QString pre;
    bool valid = false;
};

Version parseVersion(QString v) {
    static const QRegularExpression re(QStringLiteral(R"(^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$)"));
    const auto m = re.match(v.trimmed());
    Version out;
    if (!m.hasMatch())
        return out;
    out.major = m.captured(1).toInt();
    out.minor = m.captured(2).toInt();
    out.fix = m.captured(3).toInt();
    out.pre = m.captured(4);
    out.valid = true;
    return out;
}

} // namespace

UpdateManager::UpdateManager(SettingsManager *settings, QObject *parent)
    : QObject(parent), m_settings(settings), m_nam(new QNetworkAccessManager(this)), m_channel(detectChannel()) {
    m_timer.setInterval(kCheckIntervalMs);
    connect(&m_timer, &QTimer::timeout, this, [this] { check(false); });
}

UpdateManager::~UpdateManager() {
    if (m_reply)
        m_reply->abort();
}

QString UpdateManager::currentVersion() const {
    return QCoreApplication::applicationVersion();
}

void UpdateManager::start() {
    auto apply = [this] {
        if (m_settings && !m_settings->autoUpdate()) {
            m_timer.stop();
            return;
        }
        m_timer.start();
        QTimer::singleShot(kFirstCheckDelayMs, this, [this] { check(false); });
    };
    if (m_settings)
        connect(m_settings, &SettingsManager::autoUpdateChanged, this, apply);
    apply();
}

int UpdateManager::compareVersions(const QString &a, const QString &b) {
    const Version x = parseVersion(a), y = parseVersion(b);
    if (!x.valid || !y.valid)
        return x.valid ? 1 : (y.valid ? -1 : 0);
    for (auto [p, q] : {std::pair{x.major, y.major}, {x.minor, y.minor}, {x.fix, y.fix}})
        if (p != q)
            return p < q ? -1 : 1;
    // a release outranks its own pre-releases
    if (x.pre.isEmpty() != y.pre.isEmpty())
        return x.pre.isEmpty() ? 1 : -1;
    return QString::compare(x.pre, y.pre) < 0 ? -1 : (x.pre == y.pre ? 0 : 1);
}

bool UpdateManager::verifySignature(const QByteArray &message, const QByteArray &signature) {
    const QByteArray key = QByteArray::fromBase64(QByteArrayLiteral(KADER_UPDATE_PUBKEY));
    if (key.size() != 32 || signature.size() != 64)
        return false;
    EVP_PKEY *pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr,
                                                 reinterpret_cast<const unsigned char *>(key.constData()), 32);
    if (!pkey)
        return false;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    bool ok = ctx && EVP_DigestVerifyInit(ctx, nullptr, nullptr, nullptr, pkey) == 1
              && EVP_DigestVerify(ctx, reinterpret_cast<const unsigned char *>(signature.constData()),
                                  size_t(signature.size()),
                                  reinterpret_cast<const unsigned char *>(message.constData()),
                                  size_t(message.size())) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return ok;
}

void UpdateManager::setState(State s, const QString &error) {
    m_state = s;
    m_error = error;
    emit stateChanged();
}

QString UpdateManager::baseUrl() const {
    // Override for testing against a local mirror of a release.
    const QString override = qEnvironmentVariable("KADER_UPDATE_BASE_URL");
    if (!override.isEmpty())
        return override;
    return QStringLiteral("https://github.com/%1/releases/latest/download").arg(QStringLiteral(KADER_UPDATE_REPO));
}

QString UpdateManager::assetUrl(const QString &name) const {
    const QString encoded = QString::fromUtf8(QUrl::toPercentEncoding(name));
    if (!qEnvironmentVariable("KADER_UPDATE_BASE_URL").isEmpty() || m_tag.isEmpty())
        return baseUrl() + QLatin1Char('/') + encoded;
    return QStringLiteral("https://github.com/%1/releases/download/%2/%3")
        .arg(QStringLiteral(KADER_UPDATE_REPO), m_tag, encoded);
}

void UpdateManager::check(bool userInitiated) {
    if (m_state == Checking || m_state == Downloading || m_state == Installing || m_state == Installed)
        return;
    setState(Checking);

    QNetworkReply *manifest = m_nam->get(request(baseUrl() + QStringLiteral("/kader-update.json")));
    QNetworkReply *sig = m_nam->get(request(baseUrl() + QStringLiteral("/kader-update.json.sig")));
    auto pending = std::make_shared<int>(2);
    auto done = [=]() {
        if (--*pending > 0)
            return;
        manifest->deleteLater();
        sig->deleteLater();
        m_lastChecked = QLocale().toString(QDateTime::currentDateTime(), QStringLiteral("d MMM yyyy, HH:mm"));
        if (manifest->error() != QNetworkReply::NoError || sig->error() != QNetworkReply::NoError) {
            const int code = manifest->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            // 404: no release published yet — that's "up to date", not an error.
            if (code == 404) {
                setState(Idle);
                if (userInitiated)
                    emit upToDate();
                return;
            }
            setState(userInitiated ? Failed : Idle,
                     tr("Could not reach GitHub: %1").arg(manifest->error() != QNetworkReply::NoError
                                                              ? manifest->errorString() : sig->errorString()));
            return;
        }
        onManifest(manifest->readAll(), QByteArray::fromBase64(sig->readAll().trimmed()), userInitiated);
    };
    connect(manifest, &QNetworkReply::finished, this, done);
    connect(sig, &QNetworkReply::finished, this, done);
}

void UpdateManager::onManifest(const QByteArray &manifest, const QByteArray &signature, bool userInitiated) {
    if (!verifySignature(manifest, signature)) {
        // Never act on an unsigned or tampered manifest.
        setState(userInitiated ? Failed : Idle, tr("The update information is not correctly signed — ignoring it."));
        return;
    }
    const QJsonObject m = QJsonDocument::fromJson(manifest).object();
    const QString version = m.value(QStringLiteral("version")).toString();
    if (compareVersions(version, currentVersion()) <= 0) {
        setState(Idle);
        if (userInitiated)
            emit upToDate();
        return;
    }
    if (!userInitiated && m_settings && m_settings->skippedVersion() == version) {
        setState(Idle);
        return;
    }
    m_latest = version;
    m_tag = m.value(QStringLiteral("tag")).toString(QStringLiteral("v") + version);
    m_notes = m.value(QStringLiteral("notes")).toString();
    m_releaseUrl = QStringLiteral("https://github.com/%1/releases/tag/%2").arg(QStringLiteral(KADER_UPDATE_REPO), m_tag);

    // Both Windows channels update through the release's setup program.
    const QString assetKey = m_channel.startsWith(QLatin1String("windows")) ? QStringLiteral("windows") : m_channel;
    const QJsonObject asset = m.value(QStringLiteral("assets")).toObject().value(assetKey).toObject();
    m_assetName = asset.value(QStringLiteral("name")).toString();
    m_assetSha256 = QByteArray::fromHex(asset.value(QStringLiteral("sha256")).toString().toLatin1());
    m_assetSize = qint64(asset.value(QStringLiteral("size")).toDouble());
    if (canInstall() && (m_assetName.isEmpty() || m_assetSha256.size() != 32 || m_assetName.contains(QLatin1Char('/')))) {
        // The release has nothing installable for this channel.
        m_assetName.clear();
    }
    setState(Available);
    emit updateOffered();
}

void UpdateManager::install() {
    if (m_state != Available && m_state != Failed)
        return;
    if (!canInstall() || m_assetName.isEmpty()) {
        openReleasePage();
        return;
    }

    QString dir;
    if (m_channel == QLatin1String("appimage")) {
        // Download next to the running AppImage so the final rename is atomic.
        dir = QFileInfo(qEnvironmentVariable("APPIMAGE")).absolutePath();
        if (!QFileInfo(dir).isWritable()) {
            setState(Failed, tr("Kader can't write to %1. Move the AppImage to a folder you own, "
                                "or download the update manually.").arg(dir));
            return;
        }
    } else {
        if (m_channel == QLatin1String("windows-portable")
            && !QFileInfo(QCoreApplication::applicationDirPath()).isWritable()) {
            setState(Failed, tr("Kader can't write to %1. Move the Kader folder somewhere you own, "
                                "or download the update manually.")
                                 .arg(AppPaths::displayPath(QCoreApplication::applicationDirPath())));
            return;
        }
        dir = AppPaths::cacheDir() + QStringLiteral("/updates");
        QDir().mkpath(dir);
    }
    m_download.setFileName(dir + QStringLiteral("/.kader-update-") + m_latest + QStringLiteral(".part"));
    if (!m_download.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        setState(Failed, tr("Cannot write the download: %1").arg(m_download.errorString()));
        return;
    }
    m_hash.reset();
    m_progress = 0;
    emit progressChanged();
    setState(Downloading);

    m_reply = m_nam->get(request(assetUrl(m_assetName)));
    connect(m_reply, &QNetworkReply::readyRead, this, [this] {
        const QByteArray chunk = m_reply->readAll();
        m_hash.addData(chunk);
        m_download.write(chunk);
    });
    connect(m_reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        if (total <= 0)
            total = m_assetSize;
        m_progress = total > 0 ? double(got) / double(total) : 0.0;
        emit progressChanged();
    });
    connect(m_reply, &QNetworkReply::finished, this, &UpdateManager::finishDownload);
}

void UpdateManager::finishDownload() {
    QNetworkReply *reply = m_reply;
    if (!reply)
        return;
    reply->deleteLater();
    const QByteArray rest = reply->readAll();
    m_hash.addData(rest);
    m_download.write(rest);
    m_download.close();

    if (reply->error() != QNetworkReply::NoError) {
        m_download.remove();
        setState(Failed, tr("Download failed: %1").arg(reply->errorString()));
        return;
    }
    if (m_hash.result() != m_assetSha256) {
        m_download.remove();
        setState(Failed, tr("The downloaded file does not match the signed checksum — it was not installed."));
        return;
    }
    if (m_channel == QLatin1String("appimage"))
        installAppImage();
    else if (m_channel.startsWith(QLatin1String("windows")))
        stageWindowsSetup();
    else
        installArch();
}

void UpdateManager::stageWindowsSetup() {
    // The verified setup runs on restart (see restart()): it waits for Kader
    // to exit, updates this folder in place and starts the new version.
    const QString setup = QFileInfo(m_download.fileName()).absolutePath() + QLatin1Char('/') + m_assetName;
    QFile::remove(setup);
    if (!QFile::rename(m_download.fileName(), setup)) {
        m_download.remove();
        setState(Failed, tr("Could not stage the update."));
        return;
    }
    m_pendingSetup = setup;
    m_progress = 1;
    emit progressChanged();
    setState(Installed);
}

void UpdateManager::installAppImage() {
    const QString target = qEnvironmentVariable("APPIMAGE");
    const QByteArray from = QFile::encodeName(m_download.fileName());
    const QByteArray to = QFile::encodeName(target);
#ifndef Q_OS_WIN
    ::chmod(from.constData(), 0755);
#endif
    // rename(2) replaces the old file atomically; the running instance keeps
    // its already-mounted image, so nothing breaks until the restart.
    if (::rename(from.constData(), to.constData()) != 0) {
        const QString why = QString::fromLocal8Bit(std::strerror(errno));
        m_download.remove();
        setState(Failed, tr("Could not replace the AppImage: %1").arg(why));
        return;
    }
    m_restartPath = target;
    m_progress = 1;
    emit progressChanged();
    setState(Installed);
}

void UpdateManager::installArch() {
    // pacman wants the real package name to infer the compression format.
    const QString pkg = QFileInfo(m_download.fileName()).absolutePath() + QLatin1Char('/') + m_assetName;
    QFile::remove(pkg);
    if (!QFile::rename(m_download.fileName(), pkg)) {
        setState(Failed, tr("Could not stage the package."));
        return;
    }
    const QString pkexec = QStandardPaths::findExecutable(QStringLiteral("pkexec"));
    if (pkexec.isEmpty()) {
        setState(Failed, tr("pkexec is not available. Install the update from a terminal:\nsudo pacman -U \"%1\"").arg(pkg));
        return;
    }
    setState(Installing);
    m_installer = new QProcess(this);
    m_installer->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_installer, &QProcess::finished, this, [this, pkg](int code, QProcess::ExitStatus status) {
        const QString log = QString::fromLocal8Bit(m_installer->readAll()).trimmed();
        m_installer->deleteLater();
        if (status == QProcess::NormalExit && code == 0) {
            QFile::remove(pkg);
            m_restartPath = QStringLiteral("/usr/bin/kader");
            setState(Installed);
        } else if (code == 126 || code == 127) {
            setState(Available); // authentication dismissed: offer again
        } else {
            setState(Failed, tr("pacman could not install the update:\n%1").arg(log.right(600)));
        }
    });
    m_installer->start(pkexec, {QStringLiteral("/usr/bin/pacman"), QStringLiteral("-U"),
                                QStringLiteral("--noconfirm"), pkg});
}

void UpdateManager::skip() {
    if (m_settings && !m_latest.isEmpty())
        m_settings->setSkippedVersion(m_latest);
    dismiss();
}

void UpdateManager::dismiss() {
    if (m_state == Available || m_state == Failed)
        setState(Idle);
}

void UpdateManager::restart() {
    if (!m_pendingSetup.isEmpty()) {
        // NSIS: /S silent, /D= target folder (must be last and unquoted).
        QProcess setup;
        setup.setProgram(m_pendingSetup);
        QString args = QStringLiteral("/S /UPDATE");
        if (m_channel == QLatin1String("windows-portable"))
            args += QStringLiteral(" /PORTABLE");
        args += QStringLiteral(" /D=") + QDir::toNativeSeparators(QCoreApplication::applicationDirPath());
#ifdef Q_OS_WIN
        setup.setNativeArguments(args);
#else
        setup.setArguments(args.split(QLatin1Char(' ')));
#endif
        if (setup.startDetached())
            QCoreApplication::quit();
        else
            setState(Failed, tr("Could not start the update installer."));
        return;
    }
    const QString exe = !m_restartPath.isEmpty() ? m_restartPath : QCoreApplication::applicationFilePath();
    if (QProcess::startDetached(exe, QCoreApplication::arguments().mid(1)))
        QCoreApplication::quit();
}

void UpdateManager::openReleasePage() {
    QDesktopServices::openUrl(QUrl(!m_releaseUrl.isEmpty()
        ? m_releaseUrl
        : QStringLiteral("https://github.com/%1/releases/latest").arg(QStringLiteral(KADER_UPDATE_REPO))));
}
