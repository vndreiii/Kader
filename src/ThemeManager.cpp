#include "ThemeManager.h"
#include "MaterialColor.h"
#include <algorithm>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPalette>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStyleHints>
#include <QTextStream>

// Colours are generated from one seed colour with Material Color Utilities
// (MaterialColor.cpp — the same maths as Android and matugen), in the scheme
// style the user picks. The seed is Kader's purple, a preset, or the
// system's: a matugen-generated file, Quickshell's palette, or the desktop
// accent colour (Windows, KDE).

namespace {
const QString kDefaultSeed = QStringLiteral("#6750A4");

QString stateDir() {
    QString x = qEnvironmentVariable("XDG_STATE_HOME");
    return x.isEmpty() ? QDir::homePath() + QStringLiteral("/.local/state") : x;
}
QString configDir() {
    QString x = qEnvironmentVariable("XDG_CONFIG_HOME");
    return x.isEmpty() ? QDir::homePath() + QStringLiteral("/.config") : x;
}
QString quickshellPath() {
    return stateDir() + QStringLiteral("/quickshell/user/generated/material_colors.scss");
}
} // namespace

ThemeManager::ThemeManager(QObject *parent) : QObject(parent) {
    m_watcher = new QFileSystemWatcher(this);
    // matugen and Quickshell rewrite their files by replacing them, which
    // drops the watch: re-arm on every change (and watch the folders, for
    // files that don't exist yet).
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { watchFiles(); refreshTheme(); });
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { watchFiles(); refreshTheme(); });

    QSettings s;
    m_themeMode = s.value("themeMode", 0).toInt();
    // colorSource replaces the old on/off "dynamicColor" (on = system colours)
    if (s.contains("colorSource"))
        m_colorSource = std::clamp(s.value("colorSource").toInt(), 0, 2);
    else
        m_colorSource = s.value("dynamicColor", true).toBool() ? 2 : 0;
    m_seed = s.value("seedColor", kDefaultSeed).toString();
    m_variant = std::clamp(s.value("schemeVariant", 0).toInt(), 0, int(MaterialColor::Variant::Count) - 1);

    if (auto *hints = QGuiApplication::styleHints())
        connect(hints, &QStyleHints::colorSchemeChanged, this, &ThemeManager::refreshTheme);
    if (qApp)
        qApp->installEventFilter(this);
    watchFiles();
    refreshTheme();
}

bool ThemeManager::eventFilter(QObject *watched, QEvent *event) {
    if (watched == qApp && event->type() == QEvent::ApplicationPaletteChange)
        QMetaObject::invokeMethod(this, &ThemeManager::refreshTheme, Qt::QueuedConnection);
    return QObject::eventFilter(watched, event);
}

bool ThemeManager::systemIsLight() {
    const auto *hints = QGuiApplication::styleHints();
    return hints && hints->colorScheme() == Qt::ColorScheme::Light;
}

QString ThemeManager::matugenPath() const {
    return configDir() + QStringLiteral("/kader/matugen.json");
}

void ThemeManager::watchFiles() {
    for (const QString &f : {matugenPath(), quickshellPath()}) {
        const QString dir = QFileInfo(f).absolutePath();
        if (QFileInfo::exists(dir) && !m_watcher->directories().contains(dir))
            m_watcher->addPath(dir);
        if (QFileInfo::exists(f) && !m_watcher->files().contains(f))
            m_watcher->addPath(f);
    }
}

QStringList ThemeManager::presetColors() const {
    // Material's baseline purple, then a spread of hues
    return {kDefaultSeed, QStringLiteral("#B3261E"), QStringLiteral("#984061"), QStringLiteral("#8B5000"),
            QStringLiteral("#6D5E0F"), QStringLiteral("#386A20"), QStringLiteral("#006A6A"), QStringLiteral("#006493"),
            QStringLiteral("#0061A4"), QStringLiteral("#4355B9"), QStringLiteral("#7D5260"), QStringLiteral("#5D5F5F")};
}

QStringList ThemeManager::variantNames() const {
    QStringList out;
    for (int v = 0; v < int(MaterialColor::Variant::Count); ++v)
        out << MaterialColor::variantName(MaterialColor::Variant(v));
    return out;
}

void ThemeManager::setThemeMode(int mode) {
    if (m_themeMode == mode) return;
    m_themeMode = mode;
    QSettings().setValue("themeMode", mode);
    emit themeModeChanged();
    refreshTheme();
}

void ThemeManager::setColorSource(int src) {
    src = std::clamp(src, 0, 2);
    if (m_colorSource == src) return;
    m_colorSource = src;
    QSettings().setValue("colorSource", src);
    emit colorSourceChanged();
    emit dynamicColorChanged();
    refreshTheme();
}

void ThemeManager::setDynamicColor(bool dynamic) {
    setColorSource(dynamic ? 2 : 0);
}

void ThemeManager::setSeedColor(const QString &c) {
    if (!QColor::isValidColorName(c) || m_seed == c) return;
    m_seed = c;
    QSettings().setValue("seedColor", c);
    emit colorSourceChanged();
    refreshTheme();
}

void ThemeManager::setSchemeVariant(int v) {
    v = std::clamp(v, 0, int(MaterialColor::Variant::Count) - 1);
    if (m_variant == v) return;
    m_variant = v;
    QSettings().setValue("schemeVariant", v);
    emit colorSourceChanged();
    refreshTheme();
}

// The system's seed colour, best first: a matugen file (from Kader's matugen
// template), Quickshell's generated palette, then the desktop accent colour.
QColor ThemeManager::systemSeed(bool *darkHint, bool *hasHint) {
    *hasHint = false;
    QFile mf(matugenPath());
    if (mf.open(QIODevice::ReadOnly)) {
        const QJsonObject o = QJsonDocument::fromJson(mf.readAll()).object();
        QColor c(o.value("source_color").toString());
        if (!c.isValid()) c = QColor(o.value("source").toString());
        if (!c.isValid()) c = QColor(o.value("primary").toString());
        const QString mode = o.value("mode").toString().toLower();
        if (mode == "dark" || mode == "light") { *hasHint = true; *darkHint = mode == "dark"; }
        if (c.isValid()) { m_systemSource = QStringLiteral("matugen"); return c; }
    }
    QFile qf(quickshellPath());
    if (qf.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QHash<QString, QString> vars;
        static const QRegularExpression re(QStringLiteral("^\\$([\\w-]+)\\s*:\\s*([^;]+);"));
        QTextStream in(&qf);
        while (!in.atEnd()) {
            const auto m = re.match(in.readLine().trimmed());
            if (m.hasMatch()) vars.insert(m.captured(1).toLower(), m.captured(2).trimmed());
        }
        QColor c(vars.value("source_color", vars.value("sourcecolor", vars.value("primary"))));
        if (vars.contains("darkmode")) { *hasHint = true; *darkHint = vars.value("darkmode") == "true"; }
        if (c.isValid()) { m_systemSource = QStringLiteral("quickshell"); return c; }
    }
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    const QColor accent = QGuiApplication::palette().color(QPalette::Accent);
    if (accent.isValid() && accent != QPalette().color(QPalette::Accent)) {
        m_systemSource = QStringLiteral("accent");
        return accent;
    }
#endif
    return {};
}

void ThemeManager::refreshTheme() {
    bool dark = m_themeMode == 2 || (m_themeMode == 0 && !systemIsLight());
    QColor seed(kDefaultSeed);
    m_systemSource.clear();
    if (m_colorSource == 1) {
        seed = QColor(m_seed);
    } else if (m_colorSource == 2) {
        bool hint = false, hasHint = false;
        const QColor sys = systemSeed(&hint, &hasHint);
        if (sys.isValid()) seed = sys;
        // "System" mode follows matugen's / Quickshell's light-dark choice
        if (m_themeMode == 0 && hasHint) dark = hint;
    }
    if (!seed.isValid()) seed = QColor(kDefaultSeed);
    m_colors.clear();
    const auto roles = MaterialColor::scheme(seed, MaterialColor::Variant(m_variant), dark);
    for (auto it = roles.cbegin(); it != roles.cend(); ++it)
        m_colors.insert(it.key(), it.value());
    emit themeChanged();
}

#define GET_COLOR(name, fallback) \
QColor ThemeManager::name() const { \
    QString col = m_colors.value("$" #name, m_colors.value(#name, fallback)).toString(); \
    return QColor(col); \
}

GET_COLOR(primary, "#6750A4")
GET_COLOR(onPrimary, "#FFFFFF")
GET_COLOR(primaryContainer, "#EADDFF")
GET_COLOR(onPrimaryContainer, "#21005D")
GET_COLOR(secondary, "#625B71")
GET_COLOR(onSecondary, "#FFFFFF")
GET_COLOR(secondaryContainer, "#E8DEF8")
GET_COLOR(onSecondaryContainer, "#1D192B")
GET_COLOR(tertiary, "#7D5260")
GET_COLOR(onTertiary, "#FFFFFF")
GET_COLOR(tertiaryContainer, "#FFD8E4")
GET_COLOR(onTertiaryContainer, "#31111D")
GET_COLOR(error, "#B3261E")
GET_COLOR(onError, "#FFFFFF")
GET_COLOR(errorContainer, "#F9DEDC")
GET_COLOR(onErrorContainer, "#410E0B")
GET_COLOR(surface, "#FEF7FF")
GET_COLOR(surfaceDim, "#DED8E1")
GET_COLOR(surfaceBright, "#FEF7FF")
GET_COLOR(surfaceContainerLowest, "#FFFFFF")
GET_COLOR(surfaceContainerLow, "#F7F2FA")
GET_COLOR(surfaceContainer, "#F3EDF7")
GET_COLOR(surfaceContainerHigh, "#ECE6F0")
GET_COLOR(surfaceContainerHighest, "#E6E0E9")
GET_COLOR(onSurface, "#1D1B20")
GET_COLOR(onSurfaceVariant, "#49454F")
GET_COLOR(outline, "#79747E")
GET_COLOR(outlineVariant, "#CAC4D0")
GET_COLOR(inverseSurface, "#322F35")
GET_COLOR(inverseOnSurface, "#F5EFF7")
GET_COLOR(inversePrimary, "#D0BCFF")

bool ThemeManager::isDark() const {
    return isColorDark(surface());
}

bool ThemeManager::isColorDark(const QColor &color) const {
    double yiq = ((color.red() * 299) + (color.green() * 587) + (color.blue() * 114)) / 1000.0;
    return yiq < 128.0;
}
